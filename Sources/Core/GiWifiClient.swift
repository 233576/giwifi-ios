import Foundation

/// GiWiFi APK Portal 客户端。
///
/// 认证链（对齐 APK 实际请求顺序）：
/// 1. `GET http://115.159.209.137`，不跟随重定向，从 `Location` 或正文拿 Portal 主机；
/// 2. 读本机 IPv4 / MAC；
/// 3. `POST {host}:8080/wocloud_v2/appUser/appLogin.bin` 账号层（JSON + 字段级 AES）；
/// 4. `POST {portal}/gportal/app/queryAuthState` 查在线状态与网关信息；
/// 5. 未在线则 `POST {portal}/gportal/app/authLogin`；
/// 6. 命中设备冲突则 `POST {portal}/gportal/app/reBindMac`，等 4 秒重探后重试一次。
final class GiWifiClient {

    enum Failure: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    private let session: URLSession
    private let log: (String) -> Void
    private var cachedPortal: URL?

    init(log: @escaping (String) -> Void = { _ in }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 25
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        self.log = log
    }

    // MARK: - 登录

    struct Result {
        var online: Bool
        var message: String
        var portalOrigin: String
        var serverMac: String
        var authState: Int?
    }

    func login(username: String, password: String, profile: TerminalProfile,
               appUuid: String, serviceType: Int,
               allowRebind: Bool = true) async -> Result? {
        do {
            var context = try await resolveContext()
            log("Portal：\(context.portal.absoluteString)")

            // 账号层
            if let account = await accountLogin(username: username, password: password,
                                                profile: profile, appUuid: appUuid,
                                                serviceType: serviceType, context: context) {
                log("账号层：resultCode=\(account.resultCode.map(String.init) ?? "nil") \(account.message)")
                if !account.isSuccess, let code = account.resultCode, code != 0 {
                    // 账号层失败不阻断，Portal 层仍可能直接放行（部分学校未启用账号层）
                    log("账号层未通过，继续走 Portal 认证")
                }
            }

            // 状态查询
            var state = await queryAuthState(context: context, username: username, appUuid: appUuid)
            if let state, state.isSuccess {
                if let serverMac = state.string("userMac") ?? state.string("staMac"),
                   NetworkIdentity.isUsableMac(serverMac) {
                    context.userMac = NetworkIdentity.normalizeMac(serverMac)
                    log("服务端识别 MAC：\(context.userMac)")
                }
                if let nasName = state.string("nasName") ?? state.string("wlanacname"),
                   !nasName.isEmpty {
                    context.nasName = nasName
                }
                if state.isOnline {
                    log("当前终端已在线（authState=\(state.authState ?? -1)）")
                    return Result(online: true, message: state.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: state.authState)
                }
            }

            // 认证
            var auth = await authLogin(context: context, username: username, password: password,
                                       profile: profile, appUuid: appUuid)
            log("认证：resultCode=\(auth?.resultCode.map(String.init) ?? "nil") \(auth?.message ?? "无响应")")

            if let auth, auth.isSuccess {
                return Result(online: true, message: auth.displayText,
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac, authState: auth.authState)
            }

            // 设备冲突 → 换绑
            if allowRebind, let auth, auth.requiresRebind {
                log("检测到设备冲突：\(auth.message)，开始换绑")
                guard let rebind = await rebindMac(context: context, username: username,
                                                   password: password, profile: profile,
                                                   appUuid: appUuid) else {
                    return Result(online: false, message: "换绑请求失败",
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: nil)
                }
                log("换绑：resultCode=\(rebind.resultCode.map(String.init) ?? "nil") \(rebind.message)")
                guard rebind.isSuccess else {
                    return Result(online: false, message: rebind.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: nil)
                }

                log("换绑成功，等待网关同步 4 秒")
                try? await Task.sleep(nanoseconds: 4_000_000_000)

                if let refreshed = try? await resolveContext() {
                    context.portal = refreshed.portal
                    context.userIp = refreshed.userIp
                    if !refreshed.userMac.isEmpty { context.userMac = refreshed.userMac }
                }

                state = await queryAuthState(context: context, username: username, appUuid: appUuid)
                if let state, state.isSuccess, state.isOnline {
                    log("换绑后已在线")
                    return Result(online: true, message: state.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: state.authState)
                }

                auth = await authLogin(context: context, username: username, password: password,
                                       profile: profile, appUuid: appUuid)
                log("换绑后重试：resultCode=\(auth?.resultCode.map(String.init) ?? "nil") \(auth?.message ?? "无响应")")
                if let auth, auth.isSuccess {
                    return Result(online: true, message: auth.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: auth.authState)
                }
                return Result(online: false, message: auth?.displayText ?? "换绑后认证未成功",
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac, authState: nil)
            }

            return Result(online: false, message: auth?.displayText ?? "认证未成功",
                          portalOrigin: context.portal.absoluteString,
                          serverMac: context.userMac, authState: nil)
        } catch {
            log("失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 仅查询在线状态，用于自动重连轮询。
    func checkState(username: String, appUuid: String) async -> Result? {
        guard let context = try? await resolveContext() else { return nil }
        guard let state = await queryAuthState(context: context, username: username, appUuid: appUuid),
              state.isSuccess else { return nil }
        var mac = context.userMac
        if let serverMac = state.string("userMac"), NetworkIdentity.isUsableMac(serverMac) {
            mac = NetworkIdentity.normalizeMac(serverMac)
        }
        return Result(online: state.isOnline, message: state.displayText,
                      portalOrigin: context.portal.absoluteString,
                      serverMac: mac, authState: state.authState)
    }

    // MARK: - Portal 发现

    private struct Context {
        var portal: URL
        var userIp: String
        var userMac: String
        var nasName: String
        var gatewayIp: String
    }

    private func resolveContext() async throws -> Context {
        let identity = NetworkIdentity.current()
        guard let identity, NetworkIdentity.isUsableIPv4(identity.ipv4) else {
            throw Failure.message("未获取到 Wi-Fi 的 IPv4 地址，请先连接校园网 Wi-Fi")
        }

        let portal = await discoverPortal()
        log("本机 IP：\(identity.ipv4)（\(identity.interfaceName)）")

        var nasName = ""
        if let components = URLComponents(url: portal, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name.lowercased() == "wlanacname" })?.value {
            nasName = value
        }

        return Context(portal: portal,
                       userIp: identity.ipv4,
                       userMac: identity.mac,
                       nasName: nasName,
                       gatewayIp: "")
    }

    /// 打固定探测地址，从 301/302/303/307/308 的 Location 或正文里的 URL 抓 Portal。
    private func discoverPortal() async -> URL {
        let fallback = URL(string: "http://\(GiWifiProtocol.fallbackHost)/gportal/web/login")!
        guard let probe = URL(string: GiWifiProtocol.probeURL) else { return cachedPortal ?? fallback }

        var request = URLRequest(url: probe)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue(GiWifiProtocol.discoveryUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if [301, 302, 303, 307, 308].contains(http.statusCode),
                   let location = http.value(forHTTPHeaderField: "Location"),
                   let url = parsePortalURL(location, relativeTo: probe) {
                    cachedPortal = url
                    return url
                }

                let body = String(data: data, encoding: .utf8) ?? ""
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if http.statusCode == 200, trimmed == #"{"resultCode":0,"data":"\"\""}"#, cachedPortal == nil {
                    return fallback
                }
                if let url = extractPortalURL(from: body, relativeTo: probe) {
                    cachedPortal = url
                    return url
                }
            }
        } catch {
            log("探测失败：\(error.localizedDescription)")
        }
        return cachedPortal ?? fallback
    }

    private func parsePortalURL(_ value: String, relativeTo base: URL) -> URL? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        guard !normalized.isEmpty else { return nil }
        let url = URL(string: normalized, relativeTo: base)?.absoluteURL
        guard let url else { return nil }
        return url.path.lowercased().contains("/gportal/web/login") ? url : nil
    }

    private func extractPortalURL(from body: String, relativeTo base: URL) -> URL? {
        let normalized = body
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        guard let regex = try? NSRegularExpression(pattern: #"(?:https?|ftp)://[^\s"'<>]+"#,
                                                  options: [.caseInsensitive]) else { return nil }
        let range = NSRange(normalized.startIndex..., in: normalized)
        for match in regex.matches(in: normalized, options: [], range: range) {
            guard let matchRange = Range(match.range, in: normalized) else { continue }
            if let url = parsePortalURL(String(normalized[matchRange]), relativeTo: base) {
                return url
            }
        }
        return nil
    }

    // MARK: - 接口调用

    private func accountLogin(username: String, password: String, profile: TerminalProfile,
                              appUuid: String, serviceType: Int, context: Context) async -> PortalResponse? {
        guard var components = URLComponents(url: context.portal, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.port = 8080
        components.path = "/wocloud_v2/appUser/appLogin.bin"
        components.query = nil
        guard let url = components.url else { return nil }

        let encrypt = GiWifiProtocol.encryptAccountField
        let inner: [String: String] = [
            "service_type": encrypt(String(serviceType)),
            "phone": encrypt(username),
            "staticPassword": encrypt(password),
            "ip": encrypt(context.userIp),
            "apMac": "",
            "gwAddress": encrypt(context.gatewayIp),
            "staType": encrypt(profile.staType),
            "staModel": encrypt(profile.staModel)
        ]

        guard let innerData = try? JSONSerialization.data(withJSONObject: inner, options: [.sortedKeys]),
              let innerText = String(data: innerData, encoding: .utf8) else { return nil }

        let outer: [String: String] = [
            "token": encrypt(""),
            "version": GiWifiProtocol.apkVersion,
            "mac": encrypt(macForProfile(profile, context: context)),
            "gatewayId": encrypt(""),
            "data": innerText
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: outer, options: []) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return PortalResponse.parseAccount(String(data: data, encoding: .utf8) ?? "")
        } catch {
            log("账号层请求异常：\(error.localizedDescription)")
            return nil
        }
    }

    private func queryAuthState(context: Context, username: String, appUuid: String) async -> PortalResponse? {
        let fields: [String: String] = [
            "timestamp": String(Int(Date().timeIntervalSince1970)),
            "userIp": context.userIp,
            "userName": username
        ]
        return await postPortal(path: "/gportal/app/queryAuthState", fields: fields,
                                encodedField: nil, portal: context.portal, name: "状态查询")
    }

    private func authLogin(context: Context, username: String, password: String,
                           profile: TerminalProfile, appUuid: String) async -> PortalResponse? {
        var fields: [String: String] = [
            "appUuid": appUuid,
            "userIp": context.userIp,
            "nasName": wireNasName(context.nasName),
            "ssid": "",
            "nasIp": "",
            "vlan": "1",
            "apMac": "",
            "userFirstUrl": "",
            "userName": username,
            "passwd": password,
            "btype": profile.btype,
            "staType": profile.staType,
            "staModel": profile.staModel,
            "timestamp": String(Int(Date().timeIntervalSince1970))
        ]
        let mac = macForProfile(profile, context: context)
        if !mac.isEmpty { fields["userMac"] = mac }

        return await postPortal(path: "/gportal/app/authLogin", fields: fields,
                                encodedField: "passwd", portal: context.portal, name: "认证")
    }

    private func rebindMac(context: Context, username: String, password: String,
                           profile: TerminalProfile, appUuid: String) async -> PortalResponse? {
        var fields: [String: String] = [
            "appUuid": appUuid,
            "nasName": wireNasName(context.nasName),
            "userIp": context.userIp,
            "btype": profile.btype,
            "staType": profile.staType,
            "staModel": profile.staModel,
            "userName": username,
            "passwd": password,
            "timestamp": String(Int(Date().timeIntervalSince1970))
        ]
        let mac = macForProfile(profile, context: context)
        if !mac.isEmpty { fields["userMac"] = mac }

        return await postPortal(path: "/gportal/app/reBindMac", fields: fields,
                                encodedField: "passwd", portal: context.portal, name: "换绑")
    }

    private func postPortal(path: String, fields: [String: String], encodedField: String?,
                            portal: URL, name: String) async -> PortalResponse? {
        guard var components = URLComponents(url: portal, resolvingAgainstBaseURL: false) else { return nil }
        components.path = path
        components.query = nil
        components.scheme = "http"
        guard let url = components.url else { return nil }

        let plaintext = GiWifiProtocol.signedPayload(fields, encodedField: encodedField)
        guard let data = GiWifiProtocol.encodeData(plaintext) else {
            log("\(name)：载荷加密失败")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.setValue(GiWifiProtocol.apiUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("data=\(data)".utf8)

        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            let body = String(data: responseData, encoding: .utf8) ?? ""
            if !(200...299).contains(http.statusCode) {
                log("\(name)：HTTP \(http.statusCode)")
                return nil
            }
            return PortalResponse.parse(body)
        } catch {
            log("\(name)请求异常：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 字段辅助

    /// 上报 MAC：优先档案里填的伪装值，其次本机读到/服务端返回的值。
    private func macForProfile(_ profile: TerminalProfile, context: Context) -> String {
        let override = profile.wireMac
        if !override.isEmpty { return override }
        return context.userMac
    }

    /// APK 把 `GIWIFI-BAS` 以小写 `giwifi-bas` 上报。
    private func wireNasName(_ value: String) -> String {
        value.uppercased() == "GIWIFI-BAS" ? "giwifi-bas" : value
    }
}
