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
    private let portalOverride: String
    private let nasNameOverride: String
    private var cachedPortal: URL?

    /// - Parameter portalOverride: 指定 Portal（如 `http://100.100.9.2/gportal/web/login`）。
    ///   非空时跳过 115.159.209.137 探测，直接用这个站点。
    init(portalOverride: String = "", nasName: String = "",
         log: @escaping (String) -> Void = { _ in }) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 25
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        self.log = log
        self.portalOverride = portalOverride
        self.nasNameOverride = nasName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 登录

    struct Result {
        var online: Bool
        var message: String
        var portalOrigin: String
        var serverMac: String
        var authState: Int?
        /// 服务端要求先完善个人信息（resultCode=40），UI 据此给出「打开 Portal 网页」入口。
        var needsProfile: Bool = false
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

            // 状态查询：该接口按 userIp 返回本机会话，未认证时 resultCode 也可能非 0，
            // 所以无论成功与否都要读 data —— 里面的 nasName / userMac 是服务端真值。
            let state = await queryAuthState(context: context, username: username, appUuid: appUuid)
            if let state {
                if let serverMac = state.string("userMac") ?? state.string("staMac")
                    ?? state.string("usermac") ?? state.string("clientMac"),
                   NetworkIdentity.isUsableMac(serverMac) {
                    context.userMac = NetworkIdentity.normalizeMac(serverMac)
                    log("服务端识别 MAC：\(context.userMac)")
                }
                if nasNameOverride.isEmpty,
                   let nasName = state.string("nasName") ?? state.string("wlanacname")
                    ?? state.string("nas_name"),
                   !nasName.isEmpty, nasName != context.nasName {
                    log("服务端 nasName：\(nasName)（本地此前为 \(context.nasName.isEmpty ? "空" : context.nasName)）")
                    context.nasName = nasName
                }
                if state.isSuccess, state.isOnline {
                    log("当前终端已在线（authState=\(state.authState ?? -1)）")
                    return Result(online: true, message: state.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: state.authState)
                }
            }

            // 认证
            let firstAuth = await authLogin(context: context, username: username, password: password,
                                            profile: profile, appUuid: appUuid)
            log("认证：resultCode=\(firstAuth?.resultCode.map(String.init) ?? "nil") \(firstAuth?.message ?? "无响应")")

            if let firstAuth, firstAuth.isSuccess {
                return Result(online: true, message: firstAuth.displayText,
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac, authState: firstAuth.authState)
            }

            // CHALLENGE_ERR_DENY（99）：几乎都是 nasName 与实际网关不一致，
            // 常见是漏掉 / 多出一个后缀（如 GiWiFi_lnsf vs 真实的 GiWiFi_lnsfHG）。
            if let firstAuth, !firstAuth.isSuccess,
               firstAuth.resultCode == 99 || firstAuth.message.contains("CHALLENGE") {
                for candidate in Self.nasNameVariants(context.nasName).prefix(3) {
                    log("认证被拒（\(firstAuth.message)），改用 nasName=\(candidate) 重试（等 5 秒避开频率限制）")
                    try? await Task.sleep(nanoseconds: 5_200_000_000)
                    var retryContext = context
                    retryContext.nasName = candidate
                    let retry = await authLogin(context: retryContext, username: username,
                                                password: password, profile: profile, appUuid: appUuid)
                    log("重试：resultCode=\(retry?.resultCode.map(String.init) ?? "nil") \(retry?.message ?? "无响应")")
                    if let retry, retry.isSuccess {
                        return Result(online: true, message: retry.displayText,
                                      portalOrigin: retryContext.portal.absoluteString,
                                      serverMac: retryContext.userMac, authState: retry.authState)
                    }
                    // 只要结果不再是 CHALLENGE_ERR_DENY，就说明 nasName 已经对了，
                    // 剩下的是账号本身的问题（密码错、资料没补全等），继续换 nasName 没有意义。
                    if let retry, !Self.isChallengeDenied(retry) {
                        return Result(online: false,
                                      message: Self.guidance(for: retry),
                                      portalOrigin: retryContext.portal.absoluteString,
                                      serverMac: retryContext.userMac,
                                      authState: retry.authState,
                                      needsProfile: Self.needsProfileCompletion(retry))
                    }
                }
            }


            // 设备冲突 → 换绑
            if allowRebind, let firstAuth, firstAuth.requiresRebind {
                log("检测到设备冲突：\(firstAuth.message)，开始换绑")
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

                let reboundState = await queryAuthState(context: context, username: username,
                                                        appUuid: appUuid)
                if let reboundState, reboundState.isSuccess, reboundState.isOnline {
                    log("换绑后已在线")
                    return Result(online: true, message: reboundState.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: reboundState.authState)
                }

                let retryAuth = await authLogin(context: context, username: username, password: password,
                                                profile: profile, appUuid: appUuid)
                log("换绑后重试：resultCode=\(retryAuth?.resultCode.map(String.init) ?? "nil") \(retryAuth?.message ?? "无响应")")
                if let retryAuth, retryAuth.isSuccess {
                    return Result(online: true, message: retryAuth.displayText,
                                  portalOrigin: context.portal.absoluteString,
                                  serverMac: context.userMac, authState: retryAuth.authState)
                }
                return Result(online: false, message: retryAuth?.displayText ?? "换绑后认证未成功",
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac, authState: nil)
            }

            if let firstAuth, !Self.isChallengeDenied(firstAuth) {
                return Result(online: false,
                              message: Self.guidance(for: firstAuth),
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac,
                              authState: firstAuth.authState,
                              needsProfile: Self.needsProfileCompletion(firstAuth))
            }

            return Result(online: false, message: firstAuth?.displayText ?? "认证未成功",
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

        let portal: URL
        if let manual = GiWifiClient.normalizedPortalURL(portalOverride) {
            portal = manual
            log("使用指定 Portal：\(manual.absoluteString)")
        } else {
            portal = await discoverPortal()
        }
        log("本机 IP：\(identity.ipv4)（\(identity.interfaceName)）")

        var nasName = nasNameOverride
        if nasName.isEmpty,
           let components = URLComponents(url: portal, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name.lowercased() == "wlanacname" })?.value {
            nasName = value
        }
        // 手填的 Portal 通常不带 wlanacname，抓一次首页把 nasName 与网关看到的 MAC 补上
        // （authLogin 要这两个字段，缺 MAC 时服务端会回 CHALLENGE_ERR_DENY）。
        var userMac = identity.mac
        if nasName.isEmpty || !NetworkIdentity.isUsableMac(userMac) {
            let meta = await harvestPortalMeta(portal: portal)
            if nasName.isEmpty { nasName = meta.nasName }
            if !NetworkIdentity.isUsableMac(userMac) { userMac = meta.mac }
        }

        return Context(portal: portal,
                       userIp: identity.ipv4,
                       userMac: userMac,
                       nasName: nasName,
                       gatewayIp: "")
    }

    /// 取 Portal 首页，从最终 URL 或 HTML 里找 `wlanacname` / `nasName` 与终端 MAC。
    private func harvestPortalMeta(portal: URL) async -> (nasName: String, mac: String) {
        var request = URLRequest(url: portal)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.setValue(GiWifiProtocol.discoveryUserAgent, forHTTPHeaderField: "User-Agent")
        var nasName = ""
        var mac = ""
        do {
            let (data, response) = try await session.data(for: request)
            var haystack = String(data: data, encoding: .utf8) ?? ""
            if let http = response as? HTTPURLResponse, let finalURL = http.url {
                haystack += " " + finalURL.absoluteString
            }
            for pattern in [#"name=["']nas_name["'][^>]*value=["']([^"']+)["']"#,
                            #"name=["']nasName["'][^>]*value=["']([^"']+)["']"#,
                            #"wlanacname=([A-Za-z0-9\-_]+)"#,
                            #"nas_name=([A-Za-z0-9\-_]+)"#,
                            #""nasName"\s*:\s*"([^"]+)""#] {
                if let value = Self.firstGroup(pattern, in: haystack), !value.isEmpty {
                    nasName = value
                    break
                }
            }
            for pattern in [#"name=["']userMac["'][^>]*value=["']([0-9A-Fa-f:\-]{11,17})["']"#,
                            #"name=["']user_mac["'][^>]*value=["']([0-9A-Fa-f:\-]{11,17})["']"#,
                            #""userMac"\s*:\s*"([0-9A-Fa-f:\-]{11,17})""#,
                            #"name=["']staMac["'][^>]*value=["']([0-9A-Fa-f:\-]{11,17})["']"#,
                            #""wlanusermac"\s*:\s*"([0-9A-Fa-f:\-]{11,17})""#,
                            #""clientMac"\s*:\s*"([0-9A-Fa-f:\-]{11,17})""#,
                            #"usermac=([0-9A-Fa-f:\-]{11,17})"#] {
                if let value = Self.firstGroup(pattern, in: haystack),
                   NetworkIdentity.isUsableMac(value) {
                    mac = NetworkIdentity.normalizeMac(value)
                    break
                }
            }
            if !nasName.isEmpty { log("Portal 首页 nasName：\(nasName)") }
            if !mac.isEmpty { log("Portal 首页 MAC：\(mac)") }
        } catch {
            log("获取 Portal 首页失败：\(error.localizedDescription)")
        }
        return (nasName, mac)
    }

    /// 正则取第一个捕获组。
    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [],
                                           range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// 是否是 CHALLENGE_ERR_DENY（网关名不匹配）。
    static func isChallengeDenied(_ response: PortalResponse) -> Bool {
        response.resultCode == 99 || response.message.uppercased().contains("CHALLENGE")
    }

    /// 服务端要求先补全个人信息。
    static func needsProfileCompletion(_ response: PortalResponse) -> Bool {
        response.resultCode == 40
            || response.message.contains("完善")
            || response.message.contains("个人信息")
    }

    /// 把服务端错误码翻译成「下一步该做什么」，避免用户只看到一串英文。
    static func guidance(for response: PortalResponse) -> String {
        let original = response.message
        if needsProfileCompletion(response) {
            return "服务端要求先完善个人信息（resultCode 40）。请点下面「打开 Portal 网页」，"
                + "用同一账号登录一次，按提示补全手机号 / 院系资料，再回来重新认证。"
        }
        switch response.resultCode {
        case 108:
            return "账号或密码不对（108）：\(original)"
        case 102:
            return "请求太频繁，等 5 秒再试（102）：\(original)"
        case 203, 43:
            return "该账号已绑定其它设备（\(response.resultCode ?? -1)）：\(original)"
        default:
            return original.isEmpty ? "认证未通过（resultCode=\(response.resultCode ?? -1)）" : original
        }
    }

    /// nasName 兜底候选：网关名常带后缀（HG / BRAS 等），HTML 抓到的往往少了后缀。
    static func nasNameVariants(_ raw: String) -> [String] {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }
        let suffixes = ["HG", "BRAS", "bras", "Bras"]
        var stripped = base
        for suffix in suffixes where base.hasSuffix(suffix) && base.count > suffix.count {
            stripped = String(base.dropLast(suffix.count))
            break
        }
        var out: [String] = []
        for suffix in suffixes {
            let candidate = stripped + suffix
            if candidate != base && !out.contains(candidate) { out.append(candidate) }
        }
        if stripped != base && !out.contains(stripped) { out.append(stripped) }
        return out
    }

    /// 规范化手填的 Portal：补 `http://`、校验 host、保留 query（`wlanacname` 等参数有用）。
    static func normalizedPortalURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty else { return nil }
        // Portal 接口一律明文 http（客户端签名也不带 TLS）
        components.scheme = "http"
        components.fragment = nil
        if components.path.isEmpty || components.path == "/" {
            components.path = "/gportal/web/login"
        }
        return components.url
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
        // APK 用 form map 提交，`data` 的值会被再编码一次；少这层编码服务端解不出密文，
        // 会直接回 `resultCode=99 error: data is error`。
        let bodyValue = Crypto.javaFormURLEncode(data)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.setValue(GiWifiProtocol.apiUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("data=\(bodyValue)".utf8)

        if name != "状态查询" {
            log("\(name)：POST \(url.path)｜\(redactedFields(fields, encodedField: encodedField))")
        }

        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            let body = String(data: responseData, encoding: .utf8) ?? ""
            if !(200...299).contains(http.statusCode) {
                log("\(name)：HTTP \(http.statusCode) \(body.prefix(200))")
                return nil
            }
            let parsed = PortalResponse.parse(body)
            if let parsed, !parsed.isSuccess {
                log("\(name)：密文 \(body.prefix(160))")
                log("\(name)：明文 \(parsed.rawPayload)")
            }
            return parsed
        } catch {
            log("\(name)请求异常：\(error.localizedDescription)")
            return nil
        }
    }

    /// 打印请求字段（密码打码），排错用。
    private func redactedFields(_ fields: [String: String], encodedField: String?) -> String {
        fields.keys.sorted().map { key in
            let value = key == encodedField ? "****" : (fields[key] ?? "")
            return "\(key)=\(value)"
        }.joined(separator: "&")
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
