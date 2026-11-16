import Foundation

/// 终端档案：决定认证时上报成什么设备。
///
/// 这就是「设备认证伪装」的核心 —— GiWiFi 服务端按上报的 `staModel`、`btype`、
/// `staType` 与 MAC 判断设备类型，客户端只需把这些字段填成目标设备的值，
/// 不必真的修改网卡地址，因此 iOS 上也能用。
struct TerminalProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// `1` = 手机，`2` = 平板。
    var btype: String
    /// `phone` / `pad`。
    var staType: String
    /// `MANUFACTURER,MODEL,SDK,RELEASE`，例如 `Google,Pixel 9,35,15`。
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

    /// 上报用的 MAC：只接受合法格式，否则返回空串（让服务端按 IP 识别）。
    var wireMac: String {
        NetworkIdentity.normalizeMac(macOverride)
    }

    var subtitle: String {
        "\(staModel) · \(staType) · btype=\(btype)"
    }

    // MARK: - 内置模板

    static let android = TerminalProfile(
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000001")!,
        name: "Android 手机",
        btype: "1",
        staType: "phone",
        staModel: "Google,Pixel 9,35,15",
        isBuiltin: true
    )

    static let apad = TerminalProfile(
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000002")!,
        name: "Android 平板",
        btype: "2",
        staType: "pad",
        staModel: "samsung,SM-T870,34,14",
        isBuiltin: true
    )

    static let xiaomi = TerminalProfile(
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000003")!,
        name: "小米手机",
        btype: "1",
        staType: "phone",
        staModel: "Xiaomi,M2011K2C,30,11",
        isBuiltin: true
    )

    static let huaweiPad = TerminalProfile(
        id: UUID(uuidString: "0A11D001-0000-4000-8000-000000000004")!,
        name: "华为平板",
        btype: "2",
        staType: "pad",
        staModel: "HUAWEI,BAH3-W09,29,10",
        isBuiltin: true
    )

    static let builtins: [TerminalProfile] = [android, apad, xiaomi, huaweiPad]
}

/// 账号与运行参数。
struct AccountSettings: Codable {
    var username: String
    var password: String
    var appUuid: String
    var selectedProfileID: UUID
    var customProfiles: [TerminalProfile]
    var autoReconnect: Bool
    /// 自动重连轮询间隔（秒）。
    var reconnectInterval: Double
    /// 检测到未认证时是否自动换绑。
    var autoRebind: Bool
    var serviceType: Int
    /// 指定 Portal 站点；留空表示走 APK 原始的 115.159.209.137 探测。
    var portalOverride: String

    enum CodingKeys: String, CodingKey {
        case username, password, appUuid, selectedProfileID, customProfiles
        case autoReconnect, reconnectInterval, autoRebind, serviceType, portalOverride
    }

    init(username: String, password: String, appUuid: String, selectedProfileID: UUID,
         customProfiles: [TerminalProfile], autoReconnect: Bool, reconnectInterval: Double,
         autoRebind: Bool, serviceType: Int,
         portalOverride: String = GiWifiProtocol.defaultPortal) {
        self.username = username
        self.password = password
        self.appUuid = appUuid
        self.selectedProfileID = selectedProfileID
        self.customProfiles = customProfiles
        self.autoReconnect = autoReconnect
        self.reconnectInterval = reconnectInterval
        self.autoRebind = autoRebind
        self.serviceType = serviceType
        self.portalOverride = portalOverride
    }

    /// 旧版本缓存里没有 `portalOverride`，缺字段时补默认值，避免整份设置被丢弃。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        appUuid = try container.decodeIfPresent(String.self, forKey: .appUuid)
            ?? GiWifiProtocol.makeAppUuid()
        selectedProfileID = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileID)
            ?? TerminalProfile.android.id
        customProfiles = try container.decodeIfPresent([TerminalProfile].self,
                                                       forKey: .customProfiles) ?? []
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        reconnectInterval = try container.decodeIfPresent(Double.self,
                                                          forKey: .reconnectInterval) ?? 30
        autoRebind = try container.decodeIfPresent(Bool.self, forKey: .autoRebind) ?? true
        serviceType = try container.decodeIfPresent(Int.self, forKey: .serviceType)
            ?? GiWifiProtocol.defaultServiceType
        portalOverride = try container.decodeIfPresent(String.self, forKey: .portalOverride)
            ?? GiWifiProtocol.defaultPortal
    }

    static func `default`() -> AccountSettings {
        AccountSettings(
            username: "",
            password: "",
            appUuid: GiWifiProtocol.makeAppUuid(),
            selectedProfileID: TerminalProfile.android.id,
            customProfiles: [],
            autoReconnect: true,
            reconnectInterval: 30,
            autoRebind: true,
            serviceType: GiWifiProtocol.defaultServiceType,
            portalOverride: GiWifiProtocol.defaultPortal
        )
    }

    var allProfiles: [TerminalProfile] {
        TerminalProfile.builtins + customProfiles
    }

    func profile(for id: UUID) -> TerminalProfile {
        allProfiles.first(where: { $0.id == id }) ?? TerminalProfile.android
    }

    var selectedProfile: TerminalProfile { profile(for: selectedProfileID) }
}
