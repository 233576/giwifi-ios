import Foundation

// MARK: - 设备类别

/// 上报的设备类别。GiWiFi 只区分手机 / 平板 / 电脑三类，
/// 型号统一用苹果的，避免各品牌机型对不上的问题。
enum DeviceKind: String, CaseIterable, Codable, Identifiable {
    case phone
    case pad
    case pc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "手机"
        case .pad: return "平板"
        case .pc: return "电脑"
        }
    }

    /// 上报字段 `btype`。
    var btype: String {
        switch self {
        case .phone: return "1"
        case .pad: return "2"
        case .pc: return "3"
        }
    }

    /// 上报字段 `staType`。
    var staType: String {
        switch self {
        case .phone: return "phone"
        case .pad: return "pad"
        case .pc: return "pc"
        }
    }

    /// `MANUFACTURER,MODEL,SDK,RELEASE`
    var defaultModel: String {
        switch self {
        case .phone: return "Apple,iPhone 16 Pro,35,15"
        case .pad: return "Apple,iPad Pro 13,35,15"
        case .pc: return "Apple,MacBook Pro,35,15"
        }
    }

    /// 内置网页登录时固定使用的浏览器 UA：必须是真正的浏览器 UA，
    /// 否则 Portal 直接返回 403（实测 okhttp / curl 的 UA 会被拦）。
    var userAgent: String {
        switch self {
        case .phone:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 "
                + "Mobile/15E148 Safari/604.1"
        case .pad:
            return "Mozilla/5.0 (iPad; CPU OS 18_5 like Mac OS X) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 "
                + "Mobile/15E148 Safari/604.1"
        case .pc:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 "
                + "Safari/605.1.15"
        }
    }

    var symbol: String {
        switch self {
        case .phone: return "iphone"
        case .pad: return "ipad"
        case .pc: return "laptopcomputer"
        }
    }

    static func from(staType: String, btype: String) -> DeviceKind {
        let type = staType.lowercased()
        if type.contains("pad") || btype == "2" { return .pad }
        if type.contains("pc") || type.contains("mac") || btype == "3" { return .pc }
        return .phone
    }
}

// MARK: - 终端档案

/// 终端档案：决定认证时上报成什么设备。
///
/// 这就是「设备认证伪装」的核心 —— GiWiFi 服务端按上报的 `staModel`、`btype`、
/// `staType` 与 MAC 判断设备类型，客户端只需把这些字段填成目标设备的值，
/// 不必真的修改网卡地址，因此 iOS 上也能用。
struct TerminalProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// `1` = 手机，`2` = 平板，`3` = 电脑。
    var btype: String
    /// `phone` / `pad` / `pc`。
    var staType: String
    /// `MANUFACTURER,MODEL,SDK,RELEASE`，例如 `Apple,iPhone 16 Pro,35,15`。
    var staModel: String
    /// 伪装 MAC，留空表示用本机（iOS 通常读不到，会自动改由服务端返回的 MAC 回填）。
    var macOverride: String
    /// 内置模板不可删除。
    var isBuiltin: Bool

    init(id: UUID = UUID(), name: String, btype: String, staType: String,
         staModel: String, macOverride: String = "", isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.btype = btype
        self.staType = staType
        self.staModel = staModel
        self.macOverride = macOverride
        self.isBuiltin = isBuiltin
    }

    /// 由类别直接造一个档案（内置三类都用它）。
    init(kind: DeviceKind, id: UUID, name: String, isBuiltin: Bool = true) {
        self.id = id
        self.name = name
        self.btype = kind.btype
        self.staType = kind.staType
        self.staModel = kind.defaultModel
        self.macOverride = ""
        self.isBuiltin = isBuiltin
    }

    var kind: DeviceKind {
        DeviceKind.from(staType: staType, btype: btype)
    }

    /// 上报用的 MAC：只接受合法格式，否则返回空串（让服务端按 IP 识别）。
    var wireMac: String {
        NetworkIdentity.normalizeMac(macOverride)
    }

    var subtitle: String {
        "\(kind.title) · \(staModel)"
    }

    // MARK: - 内置模板

    static let phone = TerminalProfile(
        kind: .phone,
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000001")!,
        name: "手机"
    )

    static let pad = TerminalProfile(
        kind: .pad,
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000002")!,
        name: "平板"
    )

    static let pc = TerminalProfile(
        kind: .pc,
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000003")!,
        name: "电脑"
    )

    /// 兼容旧代码里的名字。
    static let android = phone
    static let apad = pad

    static let builtins: [TerminalProfile] = [phone, pad, pc]

    static func builtin(for kind: DeviceKind) -> TerminalProfile {
        switch kind {
        case .phone: return .phone
        case .pad: return .pad
        case .pc: return .pc
        }
    }
}

// MARK: - 账号

/// 一个校园网账号。密码不进 settings（存钥匙串，key = 账号 id）。
struct Account: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var username: String
    /// 每个账号独立的设备标识，换绑时只影响这个账号。
    var appUuid: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "", username: String,
         appUuid: String = GiWifiProtocol.makeAppUuid(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.username = username
        self.appUuid = appUuid
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? username : trimmed
    }

    var subtitle: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "" : name
    }
}

// MARK: - 设置

/// 账号与运行参数。
struct AccountSettings: Codable {
    /// 当前生效的账号名（等于 `settings.accounts` 里被选中那条的 username）。
    var username: String
    /// 当前账号密码（内存与钥匙串之间同步，不落 UserDefaults）。
    var password: String
    var appUuid: String
    var selectedProfileID: UUID
    var customProfiles: [TerminalProfile]
    var accounts: [Account]
    var currentAccountID: UUID?
    var autoReconnect: Bool
    /// 自动重连轮询间隔（秒）。
    var reconnectInterval: Double
    /// 检测到未认证时是否自动换绑。
    var autoRebind: Bool
    var serviceType: Int
    /// 指定 Portal 站点；留空表示走 APK 原始的 115.159.209.137 探测。
    var portalOverride: String
    /// 手填网关名（nasName）。留空表示先用 queryAuthState 返回的真实值，再退回 Portal 页面抓取。
    var nasName: String

    enum CodingKeys: String, CodingKey {
        case username, password, appUuid, selectedProfileID, customProfiles
        case accounts, currentAccountID
        case autoReconnect, reconnectInterval, autoRebind, serviceType, portalOverride, nasName
    }

    init(username: String, password: String, appUuid: String, selectedProfileID: UUID,
         customProfiles: [TerminalProfile], accounts: [Account] = [],
         currentAccountID: UUID? = nil,
         autoReconnect: Bool, reconnectInterval: Double,
         autoRebind: Bool, serviceType: Int,
         portalOverride: String = GiWifiProtocol.defaultPortal,
         nasName: String = "") {
        self.username = username
        self.password = password
        self.appUuid = appUuid
        self.selectedProfileID = selectedProfileID
        self.customProfiles = customProfiles
        self.accounts = accounts
        self.currentAccountID = currentAccountID
        self.autoReconnect = autoReconnect
        self.reconnectInterval = reconnectInterval
        self.autoRebind = autoRebind
        self.serviceType = serviceType
        self.portalOverride = portalOverride
        self.nasName = nasName
    }

    /// 旧版本缓存里没有新字段，缺字段时补默认值，避免整份设置被丢弃。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        appUuid = try container.decodeIfPresent(String.self, forKey: .appUuid)
            ?? GiWifiProtocol.makeAppUuid()
        selectedProfileID = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileID)
            ?? TerminalProfile.phone.id
        customProfiles = try container.decodeIfPresent([TerminalProfile].self,
                                                       forKey: .customProfiles) ?? []
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        currentAccountID = try container.decodeIfPresent(UUID.self, forKey: .currentAccountID)
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        reconnectInterval = try container.decodeIfPresent(Double.self,
                                                          forKey: .reconnectInterval) ?? 30
        autoRebind = try container.decodeIfPresent(Bool.self, forKey: .autoRebind) ?? true
        serviceType = try container.decodeIfPresent(Int.self, forKey: .serviceType)
            ?? GiWifiProtocol.defaultServiceType
        portalOverride = try container.decodeIfPresent(String.self, forKey: .portalOverride)
            ?? GiWifiProtocol.defaultPortal
        nasName = try container.decodeIfPresent(String.self, forKey: .nasName) ?? ""
    }

    static func `default`() -> AccountSettings {
        AccountSettings(
            username: "",
            password: "",
            appUuid: GiWifiProtocol.makeAppUuid(),
            selectedProfileID: TerminalProfile.phone.id,
            customProfiles: [],
            accounts: [],
            currentAccountID: nil,
            autoReconnect: true,
            reconnectInterval: 30,
            autoRebind: true,
            serviceType: GiWifiProtocol.defaultServiceType,
            portalOverride: GiWifiProtocol.defaultPortal,
            nasName: ""
        )
    }

    var allProfiles: [TerminalProfile] {
        TerminalProfile.builtins + customProfiles
    }

    func profile(for id: UUID) -> TerminalProfile {
        allProfiles.first(where: { $0.id == id }) ?? TerminalProfile.phone
    }

    var selectedProfile: TerminalProfile { profile(for: selectedProfileID) }

    var currentAccount: Account? {
        guard let currentAccountID else { return nil }
        return accounts.first(where: { $0.id == currentAccountID })
    }
}
