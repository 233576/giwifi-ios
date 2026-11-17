import Foundation

/// GiWiFi APK 协议常量与报文构造。所有命名与字段顺序都对齐 APK 实际发出的字节。
enum GiWifiProtocol {

    /// App Portal 载荷使用的 AES 密钥（16 字节 ASCII）。
    static let aesKey = "5447c08b53e8dac4"

    /// 签名密钥。
    static let signSecret = "5447c08b53e8dac47f81269f98cfeada"

    /// 连通性探测地址：APK 启动时打这个固定公网 IP，靠 302 跳转拿 Portal 主机。
    static let probeURL = "http://115.159.209.137"

    /// 探测返回空成功标记时使用的主机。
    static let fallbackHost = "as.gwifi.com.cn"

    /// 默认 Portal 站点：直接指定，跳过公网探测。
    /// Portal 首页上那个 `<input name="nas_name">` 的默认值。
    ///
    /// 它不是真实网关名（真实名常带 HG / BRAS 后缀），但当页面抓不到时，
    /// 用它做基底再拼后缀，能覆盖到真实值，比留空好得多。
    static let fallbackNasName = "GiWiFi_lnsf"

    static let defaultPortal = "http://100.100.9.2/gportal/web/login"

    /// App Portal 接口统一 UA。
    static let apiUserAgent = "okhttp/3.8.0"

    /// 按终端类别返回浏览器 UA（只剩手机 / 平板 / 电脑三种，型号统一 Apple）。
    ///
    /// 应用内 Portal 网页必须用真正的浏览器 UA：实测 curl / okhttp 的 UA 会被
    /// Portal 直接拒成 403，拿不到页面里的 `nas_name`。用 Safari UA 出网后
    /// 服务端按 UA 判设备，所以 UA 也要和档案（手机/平板/电脑）保持一致。
    static func browserUserAgent(for profile: TerminalProfile) -> String {
        profile.kind.userAgent
    }

    /// 给日志用：`手机 · iPhone` 之类的一句话描述。
    static func userAgentSummary(for profile: TerminalProfile) -> String {
        let kind = profile.kind
        let device: String
        switch kind {
        case .phone: device = "iPhone"
        case .pad: device = "iPad"
        case .pc: device = "Mac"
        }
        return "\(kind.title) · \(device)"
    }

    /// 探测请求 UA（APK 内置的小米浏览器标识）。
    static let discoveryUserAgent = "Mozilla/5.0 (Linux; U; Android 11; zh-cn; "
        + "M2011K2C Build/RKQ1.200928.002) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Version/4.0 Chrome/79.0.3945.147 "
        + "Mobile Safari/537.36 XiaoMi/MiuiBrowser/14.7.10"

    /// 客户端版本号，原样上报。
    static let apkVersion = "2.4.1.21"

    /// 账号层默认 service_type（GiWiFi 用户）。
    static let defaultServiceType = 1

    // MARK: - 网页表单登录（/gportal/Web/loginAction）

    /// Portal 网页登录固定的 AES 密钥，来自页面内联脚本：
    /// `CryptoJS.AES.encrypt(data, Utf8.parse("1234567887654321"), {iv, CBC, ZeroPadding})`
    static let webLoginAESKey = "1234567887654321"

    /// 网页登录提交路径。
    static let webLoginPath = "/gportal/Web/loginAction"

    /// 从 Portal 登录页解析 `#loginForm` 的隐藏域（含 `iv`）。
    ///
    /// 页面里每个表单各带一份 `sign`/`iv`/`nas_name`，只取 `id="loginForm"` 那一段，
    /// 否则会拿到注册 / 改密表单的同名字段。
    static func parseLoginForm(_ html: String) -> (pairs: [(String, String)], iv: String)? {
        guard let start = html.range(of: "id=\"loginForm\"") else { return nil }
        let tail = html[start.upperBound...]
        guard let end = tail.range(of: "</form>") else { return nil }
        let fragment = String(tail[..<end.lowerBound])

        var pairs: [(String, String)] = []
        var iv = ""
        for inputTag in matches("<input[^>]*>", in: fragment) {
            guard let name = attribute("name", in: inputTag), !name.isEmpty else { continue }
            let type = attribute("type", in: inputTag)?.lowercased() ?? "text"
            guard type == "hidden" else { continue }
            let value = attribute("value", in: inputTag) ?? ""
            if name == "iv" { iv = value }
            pairs.append((name, value))
        }
        guard !iv.isEmpty else { return nil }
        return (pairs, iv)
    }

    /// 拼出 `$.serialize()` 等价的表单串并加密成 `{"data":..,"iv":..}`。
    static func webLoginBody(pairs: [(String, String)],
                             iv: String,
                             username: String,
                             password: String) -> String? {
        var merged = pairs.filter { $0.0 != "user_account" && $0.0 != "user_password" }
        merged.append(("user_account", username))
        merged.append(("user_password", password))
        let serialized = Crypto.formSerialize(merged)
        guard let encrypted = Crypto.aes128CBCZeroPadBase64(plaintext: serialized,
                                                            key: webLoginAESKey,
                                                            iv: iv) else { return nil }
        let payload: [String: Any] = ["data": encrypted, "iv": iv]
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let text = String(data: json, encoding: .utf8) else { return nil }
        return text
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = name + #"\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }

    // MARK: - 报文构造

    /// 按 key 字典序拼接 `k=v&k=v`（值不做编码，与 APK 一致）。
    static func sortedFieldsString(_ fields: [String: String]) -> String {
        fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: "&")
    }

    /// 构造带签名的明文字段串：`...&sign=<md5>`。
    ///
    /// - Parameter encodedField: 需要额外做 Java form 编码的字段（APK 只对密码这么做）。
    static func signedPayload(_ fields: [String: String], encodedField: String?) -> String {
        let rawForSign = sortedFieldsString(fields)
        let signature = Crypto.md5Hex(rawForSign + signSecret)

        var encoded = fields
        if let encodedField, let value = encoded[encodedField] {
            encoded[encodedField] = Crypto.javaFormURLEncode(value)
        }
        return sortedFieldsString(encoded) + "&sign=" + signature
    }

    /// 明文 → AES-128-ECB → base64 → Java form 编码，得到 `data` 参数值。
    static func encodeData(_ plaintext: String) -> String? {
        guard let base64 = Crypto.aes128ECBEncryptBase64(plaintext: plaintext, key: aesKey) else {
            return nil
        }
        return Crypto.javaFormURLEncode(base64)
    }

    /// 账号层字段加密（`service_type`、`phone`、`staticPassword` 等）。
    static func encryptAccountField(_ value: String) -> String {
        Crypto.aes128ECBEncryptBase64(plaintext: value, key: aesKey) ?? ""
    }

    // MARK: - appUuid

    /// 生成 GiWiFi 风格的 appUuid：UUIDv4 去掉第四段与第五段之间的连字符（35 位）。
    static func makeAppUuid() -> String {
        let uuid = UUID().uuidString.lowercased()
        let parts = uuid.split(separator: "-").map(String.init)
        guard parts.count == 5 else { return uuid }
        // 8-4-4-4-12 → 8-4-4-4+12
        return parts[0] + "-" + parts[1] + "-" + parts[2] + "-" + parts[3] + parts[4]
    }

    /// 校验 appUuid 格式（长度 35、无第二个连字符段）。
    static func isValidAppUuid(_ value: String) -> Bool {
        value.count == 35 && value.split(separator: "-").count == 4
    }
}

// MARK: - 响应模型

/// 单个 App Portal 接口的响应。
struct PortalResponse {
    let resultCode: Int?
    let message: String
    let data: [String: Any]?
    /// 解密后的 data 原文，仅用于日志诊断。
    var rawPayload: String = ""
    /// 当 `data` 本身是字符串时（例如 43 返回的绑定链接）保留原文。
    var dataText: String = ""

    /// 43 时服务端会回一条 `/Giportal/index.php/Sta/bindSta?token=..&timestamp=..&sign=..`，
    /// GET 它即完成换绑（官方 App 的「确认完成绑定」就是这一下）。
    var bindPath: String {
        let text = dataText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("/") ? text : ""
    }

    var isSuccess: Bool { resultCode == 0 || resultCode == 200 }

    var requiresRebind: Bool {
        if resultCode == 43 { return true }
        return (resultCode == 1 || resultCode == 203) && message.contains("绑定")
    }

    func string(_ key: String) -> String? {
        guard let value = data?[key] else { return nil }
        if value is NSNull { return nil }
        return String(describing: value)
    }

    func int(_ key: String) -> Int? {
        guard let value = data?[key], !(value is NSNull) else { return nil }
        if let number = value as? Int { return number }
        return Int(String(describing: value))
    }

    /// 认证状态：2 或 200 视为已在线。
    var authState: Int? { int("authState") }
    var isOnline: Bool { authState == 2 || authState == 200 }

    var displayText: String {
        if let tips = string("tips"), !tips.trimmingCharacters(in: .whitespaces).isEmpty {
            return tips
        }
        if !message.isEmpty { return message }
        if isSuccess { return "认证成功" }
        if let code = resultCode { return "认证失败（resultCode=\(code)）" }
        return "认证失败"
    }

    /// 解析响应体。`data` 可能是明文 JSON 对象、JSON 字符串，或 AES 密文。
    static func parse(_ body: String) -> PortalResponse? {
        guard let object = Self.decodeJSONObject(body) else { return nil }

        let topCode = Self.intValue(object["resultCode"] ?? object["errcode"] ?? object["errorCode"])
        let topMessage = Self.stringValue(object["resultMsg"] ?? object["errmsg"]
                                          ?? object["info"] ?? object["message"])

        // data 可能是对象 / JSON 字符串 / 密文，逐种尝试解包
        var payload: [String: Any] = [:]
        if let raw = object["data"] ?? object["resultData"] {
            if let map = raw as? [String: Any] {
                payload = map
            } else if let text = raw as? String {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if trimmed.hasPrefix("{") {
                        payload = Self.decodeJSONObject(trimmed) ?? [:]
                    } else {
                        // 密文：先 form 解码，再 AES 解密
                        let decoded = Self.javaFormDecode(trimmed)
                        if let plain = Crypto.aes128ECBDecryptBase64(decoded, key: GiWifiProtocol.aesKey),
                           let parsed = Self.decodeJSONObject(plain) {
                            payload = parsed
                        }
                    }
                }
            }
        }

        // 内层可能再套一层 resultCode，优先用内层的
        let innerCode = Self.intValue(payload["resultCode"] ?? payload["errcode"] ?? payload["errorCode"])
        let innerMessage = Self.stringValue(payload["resultMsg"] ?? payload["errmsg"]
                                            ?? payload["info"] ?? payload["message"])
        let code = innerCode ?? topCode
        let message = innerMessage.isEmpty ? topMessage : innerMessage

        // 内层若还有 data 字段就再降一层，否则整个 payload 就是业务数据
        let business = Self.mapValue(payload["data"] ?? payload["resultData"]) ?? (payload.isEmpty ? nil : payload)

        if code == nil, business == nil {
            return nil
        }
        var raw = ""
        if !payload.isEmpty,
           let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: json, encoding: .utf8) {
            raw = text
        }
        var result = PortalResponse(resultCode: code, message: message, data: business, rawPayload: raw)
        if let text = payload["data"] as? String, !text.hasPrefix("{"), !text.hasPrefix("[") {
            result.dataText = text
        }
        return result
    }

    /// 账号层响应：顶层 `data` 通常是 JSON 字符串。
    static func parseAccount(_ body: String) -> PortalResponse? {
        guard let object = Self.decodeJSONObject(body) else { return nil }

        var payload = object
        if let nested = mapValue(object["data"]) {
            for (key, value) in nested { payload[key] = value }
        } else if let text = object["data"] as? String,
                  text.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
                  let nested = decodeJSONObject(text) {
            for (key, value) in nested { payload[key] = value }
        }

        return PortalResponse(
            resultCode: intValue(payload["resultCode"] ?? payload["errorCode"] ?? payload["errcode"]),
            message: stringValue(payload["resultMsg"] ?? payload["errmsg"] ?? payload["message"] ?? object["info"]),
            data: mapValue(object["data"])
        )
    }

    // MARK: - 小工具

    static func decodeJSONObject(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func javaFormDecode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    static func intValue(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return Int(String(describing: value))
    }

    static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    static func mapValue(_ value: Any?) -> [String: Any]? {
        if let map = value as? [String: Any] { return map }
        if let text = value as? String, text.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            return decodeJSONObject(text)
        }
        return nil
    }
}
