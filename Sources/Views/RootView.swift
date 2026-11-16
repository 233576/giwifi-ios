import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var showingProfileEditor = false
    @State private var showingPortalWeb = false

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        statusCard
                        actionRow
                        profileStrip
                        autoRow
                        infoCard
                        logPreview
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("GiWiFi 助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLogs = true
                    } label: {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Flat.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Flat.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store)
            }
            .sheet(isPresented: $showLogs) {
                LogView().environmentObject(store)
            }
            .sheet(isPresented: $showingProfileEditor) {
                ProfileEditorView(profile: nil).environmentObject(store)
            }
            .sheet(isPresented: $showingPortalWeb) {
                if let url = portalURL {
                    PortalWebView(url: url,
                                  userAgent: GiWifiProtocol.browserUserAgent(for: store.currentProfile)) {
                        Task { await store.refreshState() }
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { store.errorText != nil },
                set: { if !$0 { store.clearError() } }
            )) {
                if store.needsProfile || store.needsWebAuth {
                    Button("内置网页登录") { openPortal() }
                }
                Button("好", role: .cancel) { store.clearError() }
            } message: {
                Text(store.errorText ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Portal 地址（手填优先，否则用默认站点）。
    private var portalURL: URL? {
        let raw = store.settings.portalOverride.isEmpty
            ? GiWifiProtocol.defaultPortal
            : store.settings.portalOverride
        return GiWifiClient.normalizedPortalURL(raw)
    }

    /// 打开应用内 Portal 网页：UA 跟随设备档案，避免服务端把这次网页登录当成另一台设备。
    private func openPortal() {
        store.clearError()
        showingPortalWeb = true
    }

    // MARK: - 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                FlatStatusMark(symbol: symbol, tint: stateColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.state.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text(store.detail)
                        .font(.footnote)
                        .foregroundStyle(Flat.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(online ? "在线" : "离线")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(online ? Flat.green : Flat.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .flatPill(selected: false)
            }

            FlatProgressBar(progress: progressValue, tint: stateColor, height: 4)

            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.caption2)
                Text(store.settings.username.isEmpty ? "未填写账号" : store.settings.username)
                    .font(.caption.monospacedDigit())
                Spacer()
                Image(systemName: "wifi.router")
                    .font(.caption2)
                Text(store.currentProfile.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    private var online: Bool { store.state == .online }

    private var progressValue: Double {
        switch store.state {
        case .online: return 1.0
        case .connecting: return 0.6
        case .failed: return 0.3
        case .offline: return 0.08
        case .idle: return 0.16
        }
    }

    private var stateColor: Color {
        switch store.state {
        case .online: return Flat.green
        case .connecting: return Flat.orange
        case .failed: return Flat.red
        case .offline: return Color(hex: 0x6B7280)
        case .idle: return Flat.accent
        }
    }

    private var symbol: String {
        switch store.state {
        case .online: return "wifi"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .offline: return "wifi.slash"
        case .idle: return "wifi"
        }
    }

    // MARK: - 操作

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.login() }
            } label: {
                HStack(spacing: 8) {
                    if store.state == .connecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(store.state == .connecting ? "认证中…" : "立即认证")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(FlatButtonStyle(filled: true, height: 50))
            .disabled(store.state == .connecting)

            HStack(spacing: 10) {
                Button {
                    Task { await store.refreshState() }
                } label: {
                    Label("查状态", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(FlatButtonStyle(height: 44))

                Button {
                    store.setAutoReconnect(!store.autoRunning)
                } label: {
                    Label(store.autoRunning ? "停止守护" : "自动守护",
                          systemImage: store.autoRunning ? "stop.fill" : "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(store.autoRunning ? Flat.green : Flat.textPrimary)
                }
                .buttonStyle(FlatButtonStyle(height: 44))
            }

            Button {
                openPortal()
            } label: {
                Label("打开 Portal 网页（补全资料 / 网页登录）", systemImage: "safari")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Flat.textSecondary)
            }
            .buttonStyle(FlatButtonStyle(height: 44))
        }
    }

    // MARK: - 多端切换

    private var profileStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FlatSectionHeader(title: "设备身份")
                Button {
                    showingProfileEditor = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Flat.accent)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.profiles) { profile in
                        profileChip(profile)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(16)
        .flatCard()
    }

    private func profileChip(_ profile: TerminalProfile) -> some View {
        let selected = profile.id == store.settings.selectedProfileID
        return Button {
            store.selectProfile(profile.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: profile.staType == "pad" ? "ipad" : "iphone")
                        .font(.caption2)
                    Text(profile.name)
                        .font(.footnote.weight(.medium))
                }
                Text(profile.staType == "pad" ? "平板 · \(profile.btype)" : "手机 · \(profile.btype)")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : Flat.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Flat.textPrimary)
            .flatPill(selected: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 自动重连

    private var autoRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Flat.accent)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Flat.accent.opacity(0.14))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("掉线自动重连")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Flat.textPrimary)
                Text("每 \(Int(store.settings.reconnectInterval)) 秒检查一次")
                    .font(.caption)
                    .foregroundStyle(Flat.textTertiary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { store.settings.autoReconnect },
                set: { store.setAutoReconnect($0) }
            ))
            .labelsHidden()
            .tint(Flat.accent)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 信息

    private var infoCard: some View {
        VStack(spacing: 0) {
            FlatSectionHeader(title: "连接信息")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            FlatDivider(inset: 16)

            infoLine("当前档案", store.currentProfile.subtitle)
            FlatDivider(inset: 16)
            infoLine("服务端 MAC", store.serverMac.isEmpty ? "未获取" : store.serverMac)
            FlatDivider(inset: 16)
            infoLine("Portal", store.portal.isEmpty ? "未探测" : store.portal)
        }
        .padding(.bottom, 4)
        .flatCard()
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Flat.textTertiary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Flat.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 日志

    private var logPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FlatSectionHeader(title: "运行日志")
                Button {
                    showLogs = true
                } label: {
                    Text("全部")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Flat.accent)
                }
                .buttonStyle(.plain)
            }

            if store.logs.isEmpty {
                Text("还没有记录")
                    .font(.footnote)
                    .foregroundStyle(Flat.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(store.logs.suffix(6)) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.stamp)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Flat.textTertiary)
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Flat.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(16)
        .flatCard(fill: Flat.surfaceLow)
    }
}

#Preview {
    RootView().environmentObject(AppStore())
}
