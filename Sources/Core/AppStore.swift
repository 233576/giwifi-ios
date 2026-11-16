import Foundation
import Combine

/// 应用状态机：负责认证、状态轮询、自动重连与日志。
@MainActor
final class AppStore: ObservableObject {

    enum ConnectState: String {
        case idle
        case connecting
        case online
        case offline
        case failed

        var title: String {
            switch self {
            case .idle: return "未连接"
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
    @Published private(set) var detail: String = "连接校园网 Wi-Fi 后点「立即认证」"
    @Published private(set) var portal: String = ""
    @Published private(set) var serverMac: String = ""
    @Published private(set) var logs: [LogLine] = []
    @Published private(set) var autoRunning = false
    @Published var errorText: String?

    private var autoTask: Task<Void, Never>?
    private static let settingsKey = "giwifi.settings.v1"
    private static let logLimit = 300

    nonisolated init() {}

    /// 从 UserDefaults 与钥匙串恢复上次的账号与参数。
    func restore() {
        var loaded = settings
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AccountSettings.self, from: data) {
            loaded = decoded
        }
        if let password = Keychain.load(), !password.isEmpty {
            loaded.password = password
        }
        settings = loaded
    }

    // MARK: - 设置读写

    var profiles: [TerminalProfile] { settings.allProfiles }

    var currentProfile: TerminalProfile { settings.selectedProfile }

    func updateSettings(_ mutate: (inout AccountSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        persist()
    }

    func selectProfile(_ id: UUID) {
        updateSettings { $0.selectedProfileID = id }
    }

    func addProfile(_ profile: TerminalProfile) {
        updateSettings { $0.customProfiles.append(profile) }
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
                copy.selectedProfileID = TerminalProfile.android.id
            }
        }
    }

    func resetAppUuid() {
        updateSettings { $0.appUuid = GiWifiProtocol.makeAppUuid() }
        append("已重置设备标识：\(settings.appUuid)")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        if !settings.password.isEmpty {
            Keychain.save(settings.password)
        } else {
            Keychain.delete()
        }
    }

    // MARK: - 认证

    func login(auto: Bool = false) async {
        guard !settings.username.isEmpty else {
            errorText = "请先填写校园网账号"
            return
        }
        guard state != .connecting else { return }

        persist()
        state = .connecting
        detail = auto ? "自动重连中…" : "正在认证…"
        if !auto { logs.removeAll() }
        append("==== \(auto ? "自动重连" : "开始认证")：\(settings.username) ====")
        append("设备档案：\(currentProfile.name)｜\(currentProfile.subtitle)")

        let profile = currentProfile
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
            state = .online
            detail = result.message.isEmpty ? "已认证，可以上网了" : result.message
            append("认证成功：\(detail)")
        } else {
            state = .failed
            detail = result.message.isEmpty ? "认证未通过" : result.message
            append("认证失败：\(detail)")
        }
    }

    /// 只查在线状态，不触发认证。
    func refreshState() async {
        guard !settings.username.isEmpty else { return }
        let client = GiWifiClient(portalOverride: settings.portalOverride, nasName: settings.nasName) { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }
        guard let result = await client.checkState(username: settings.username,
                                                   appUuid: settings.appUuid) else {
            if state != .connecting { state = .offline }
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
                                                appUuid: settings.appUuid) {
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
        if !autoRunning, state == .connecting, trimmed.count < 40, detail.hasPrefix("正在") {
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
