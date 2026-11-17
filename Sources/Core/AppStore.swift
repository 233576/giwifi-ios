import Foundation
import Combine

/// 应用状态机：负责认证、状态轮询、自动重连、多账号与日志。
@MainActor
final class AppStore: ObservableObject {

    enum ConnectState: String {
        case idle
        case checking
        case connecting
        case online
        case offline
        case failed

        var title: String {
            switch self {
            case .idle: return "未连接"
            case .checking: return "检测中"
            case .connecting: return "认证中"
            case .online: return "已在线"
            case .offline: return "未认证"
            case .failed: return "失败"
            }
        }
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time: Date
        let text: String

        var stamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: time)
        }
    }

    @Published private(set) var settings: AccountSettings = AccountSettings.default()
    @Published private(set) var state: ConnectState = .idle
    @Published private(set) var detail: String = "连上校园网 Wi-Fi 后会自动检测状态"
    @Published private(set) var portal: String = ""
    @Published private(set) var serverMac: String = ""
    @Published private(set) var logs: [LogLine] = []
    @Published private(set) var autoRunning = false
    @Published var errorText: String?
    /// 服务端要求先完善个人信息（resultCode=40），首页会多出一个「打开 Portal 网页」按钮。
    @Published private(set) var needsProfile = false
    /// 网关拒绝了 API 认证（CHALLENGE_ERR_DENY），此时只能走内置网页登录。
    @Published private(set) var needsWebAuth = false

    private var autoTask: Task<Void, Never>?
    private static let settingsKey = "giwifi.settings.v2"
    private static let legacySettingsKey = "giwifi.settings.v1"
    private static let logLimit = 300

    nonisolated init() {}

    // MARK: - 持久化

    /// 从 UserDefaults 与钥匙串恢复账号与参数，并做一次旧版数据迁移。
    func restore() {
        var loaded = settings
        var data = UserDefaults.standard.data(forKey: Self.settingsKey)
        if data == nil { data = UserDefaults.standard.data(forKey: Self.legacySettingsKey) }
        if let data, let decoded = try? JSONDecoder().decode(AccountSettings.self, from: data) {
            loaded = decoded
        }

        // 旧版只有一个账号：迁移成 accounts 里的一条。
        if loaded.accounts.isEmpty, !loaded.username.isEmpty {
            let migrated = Account(name: loaded.username, username: loaded.username,
                                   appUuid: loaded.appUuid)
            loaded.accounts = [migrated]
            loaded.currentAccountID = migrated.id
            let legacyPassword = loaded.password
            if !legacyPassword.isEmpty {
                Keychain.save(legacyPassword, account: migrated.id.uuidString)
            }
        }

        if let id = loaded.currentAccountID,
           let account = loaded.accounts.first(where: { $0.id == id }) {
            loaded.username = account.username
            loaded.appUuid = account.appUuid
            loaded.password = Keychain.load(account: id.uuidString) ?? loaded.password
        } else if let first = loaded.accounts.first {
            loaded.currentAccountID = first.id
            loaded.username = first.username
            loaded.appUuid = first.appUuid
            loaded.password = Keychain.load(account: first.id.uuidString) ?? ""
        } else if let password = Keychain.load(), !password.isEmpty {
            loaded.password = password
        }

        settings = loaded
        persist()
    }

    private func persist() {
        var copy = settings
        if let id = copy.currentAccountID,
           let index = copy.accounts.firstIndex(where: { $0.id == id }) {
            copy.accounts[index].username = copy.username
            copy.accounts[index].appUuid = copy.appUuid
            if copy.accounts[index].name.trimmingCharacters(in: .whitespaces).isEmpty {
                copy.accounts[index].name = copy.username
            }
        }
        settings = copy
        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        let key = copy.currentAccountID?.uuidString ?? "giwifi-credentials"
        if !copy.password.isEmpty {
            Keychain.save(copy.password, account: key)
        } else {
            Keychain.delete(account: key)
        }
    }

    // MARK: - 账号

    var accounts: [Account] { settings.accounts }

    var currentAccount: Account? { settings.currentAccount }

    var currentAccountName: String {
        currentAccount?.displayName ?? (settings.username.isEmpty ? "未添加账号" : settings.username)
    }

    @discardableResult
    func addAccount(name: String, username: String, password: String) -> Account {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let account = Account(name: trimmedName.isEmpty ? trimmedUser : trimmedName,
                              username: trimmedUser,
                              appUuid: GiWifiProtocol.makeAppUuid())
        updateSettings { copy in
            copy.accounts.append(account)
            copy.currentAccountID = account.id
            copy.username = account.username
            copy.appUuid = account.appUuid
            copy.password = password
        }
        Keychain.save(password, account: account.id.uuidString)
        append("已添加账号：\(account.displayName)")
        return account
    }

    func updateAccount(_ id: UUID, name: String, username: String, password: String?) {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        updateSettings { copy in
            guard let index = copy.accounts.firstIndex(where: { $0.id == id }) else { return }
            copy.accounts[index].name = trimmedName.isEmpty ? trimmedUser : trimmedName
            copy.accounts[index].username = trimmedUser
            if copy.currentAccountID == id {
                copy.username = trimmedUser
                if let password { copy.password = password }
            }
        }
        if let password { Keychain.save(password, account: id.uuidString) }
    }

    func deleteAccount(_ id: UUID) {
        let removed = settings.accounts.first(where: { $0.id == id })
        updateSettings { copy in
            copy.accounts.removeAll(where: { $0.id == id })
            if copy.currentAccountID == id {
                let next = copy.accounts.first
                copy.currentAccountID = next?.id
                copy.username = next?.username ?? ""
                copy.appUuid = next?.appUuid ?? GiWifiProtocol.makeAppUuid()
                copy.password = ""
            }
        }
        Keychain.delete(account: id.uuidString)
        if let removed { append("已删除账号：\(removed.displayName)") }
        if state != .connecting { state = .idle }
    }

    /// 切换当前账号（不发起认证）。
    func selectAccount(_ id: UUID) {
        guard let account = settings.accounts.first(where: { $0.id == id }) else { return }
        let password = Keychain.load(account: id.uuidString) ?? ""
        updateSettings { copy in
            copy.currentAccountID = id
            copy.username = account.username
            copy.appUuid = account.appUuid
            copy.password = password
        }
        state = .idle
        detail = "已切换到 \(account.displayName)"
        append("切换账号：\(account.displayName)（\(account.username)）")
    }

    /// 切换并立即认证指定账号。
    func loginAccount(_ id: UUID) async {
        selectAccount(id)
        await login()
    }

    func resetAppUuid() {
        updateSettings { $0.appUuid = GiWifiProtocol.makeAppUuid() }
        append("已重置设备标识：\(settings.appUuid)")
    }

    // MARK: - 设置

    var profiles: [TerminalProfile] { settings.allProfiles }

    var customProfiles: [TerminalProfile] { settings.customProfiles }

    var currentProfile: TerminalProfile { settings.selectedProfile }

    func updateSettings(_ mutate: (inout AccountSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        persist()
    }

    /// 切换到某个设备类别（手机 / 平板 / 电脑）。
    func selectKind(_ kind: DeviceKind) {
        updateSettings { $0.selectedProfileID = TerminalProfile.builtin(for: kind).id }
    }

    func selectProfile(_ id: UUID) {
        updateSettings { $0.selectedProfileID = id }
    }

    func addProfile(_ profile: TerminalProfile) {
        updateSettings { $0.customProfiles.append(profile) }
        selectProfile(profile.id)
    }

    func updateProfile(_ profile: TerminalProfile) {
        updateSettings { copy in
            if let index = copy.customProfiles.firstIndex(where: { $0.id == profile.id }) {
                copy.customProfiles[index] = profile
            }
        }
    }

    func deleteProfile(_ id: UUID) {
        updateSettings { copy in
            copy.customProfiles.removeAll(where: { $0.id == id })
            if copy.selectedProfileID == id {
                copy.selectedProfileID = TerminalProfile.phone.id
            }
        }
    }

    // MARK: - 启动自动检测

    /// 打开 App 后等 2 秒再静默检测一次状态（不触发认证）。
    func autoDetectOnLaunch() async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !Task.isCancelled else { return }
        guard !settings.username.isEmpty else {
            state = .idle
            detail = "还没有账号，去「设置 → 账号管理」添加"
            append("未检测：尚未添加账号")
            return
        }
        state = .checking
        detail = "正在检测当前网络状态…"
        append("==== 启动自动检测 ====")
        await refreshState()
    }

    // MARK: - 认证

    func login(auto: Bool = false) async {
        guard !settings.username.isEmpty else {
            errorText = "请先在「设置 → 账号管理」添加校园网账号"
            return
        }
        guard state != .connecting else { return }

        persist()
        state = .connecting
        detail = auto ? "自动重连中…" : "正在认证…"
        if !auto { logs.removeAll() }
        let profile = currentProfile
        append("==== \(auto ? "自动重连" : "开始认证")：\(currentAccountName) ====")
        append("设备档案：\(profile.kind.title)｜\(profile.subtitle)")
        append("浏览器 UA（\(profile.kind.title)）：\(profile.kind.userAgent)")

        let client = GiWifiClient(portalOverride: settings.portalOverride, nasName: settings.nasName) { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }

        let result = await client.login(
            username: settings.username,
            password: settings.password,
            profile: profile,
            appUuid: settings.appUuid,
            serviceType: settings.serviceType,
            allowRebind: settings.autoRebind
        )

        guard let result else {
            state = .failed
            detail = "无法连接认证服务器，请确认已连上校园网"
            append("认证失败：无响应")
            return
        }

        portal = result.portalOrigin
        if !result.serverMac.isEmpty { serverMac = result.serverMac }
        if result.online {
            needsProfile = false
            needsWebAuth = false
            state = .online
            detail = result.message.isEmpty ? "已认证，可以上网了" : result.message
            append("认证成功：\(detail)")
        } else {
            state = .failed
            detail = result.message.isEmpty ? "认证未通过" : result.message
            needsProfile = result.needsProfile
            needsWebAuth = result.needsWebAuth
            append("认证失败：\(detail)")
        }
    }

    /// 只查在线状态，不触发认证。
    func refreshState() async {
        guard !settings.username.isEmpty else {
            state = .idle
            return
        }
        let client = GiWifiClient(portalOverride: settings.portalOverride, nasName: settings.nasName) { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }
        let wasChecking = state == .checking
        guard let result = await client.checkState(username: settings.username,
                                                   appUuid: settings.appUuid,
                                                   profile: currentProfile) else {
            if state != .connecting { state = .offline }
            if wasChecking { detail = "检测失败，请确认已连上校园网" }
            return
        }
        portal = result.portalOrigin
        if !result.serverMac.isEmpty { serverMac = result.serverMac }
        if result.online {
            state = .online
            detail = result.message.isEmpty ? "已在线" : result.message
        } else if state != .connecting {
            state = .offline
            detail = "当前未认证"
        }
        append("状态：\(result.online ? "在线" : "未认证")（authState=\(result.authState.map(String.init) ?? "-")）")
    }

    // MARK: - 自动重连

    func setAutoReconnect(_ enabled: Bool) {
        updateSettings { $0.autoReconnect = enabled }
        if enabled {
            startAuto()
        } else {
            stopAuto()
        }
    }

    func startAuto() {
        guard autoTask == nil else { return }
        autoRunning = true
        append("自动重连已开启（间隔 \(Int(settings.reconnectInterval)) 秒）")
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = max(10, self.settings.reconnectInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.autoTick()
            }
        }
    }

    func stopAuto() {
        autoTask?.cancel()
        autoTask = nil
        autoRunning = false
        append("自动重连已停止")
    }

    private func autoTick() async {
        guard settings.autoReconnect else {
            stopAuto()
            return
        }
        let client = GiWifiClient(portalOverride: settings.portalOverride, nasName: settings.nasName) { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }
        if let result = await client.checkState(username: settings.username,
                                                appUuid: settings.appUuid,
                                                profile: currentProfile) {
            if !result.serverMac.isEmpty { serverMac = result.serverMac }
            if result.online {
                if state != .online {
                    state = .online
                    detail = "已在线（自动检测）"
                    append("自动检测：在线")
                }
                return
            }
        }
        append("自动检测：掉线，重新认证")
        await login(auto: true)
    }

    // MARK: - 日志

    func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logs.append(LogLine(time: Date(), text: trimmed))
        if logs.count > Self.logLimit {
            logs.removeFirst(logs.count - Self.logLimit)
        }
        if !autoRunning, state == .connecting, trimmed.count < 40,
           detail.hasPrefix("正在") {
            detail = trimmed
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func clearError() {
        errorText = nil
    }

    var logText: String {
        logs.map { "\($0.stamp)  \($0.text)" }.joined(separator: "\n")
    }
}
