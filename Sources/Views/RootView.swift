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
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        profileStrip
                        actionRow
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLogs = true
                    } label: {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .glassPill()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .glassPill()
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

    // MARK: - 状态卡

    private var statusCard: some View {
        VStack(spacing: 14) {
            GlassStatusRing(
                progress: ringProgress,
                gradient: stateGradient,
                symbol: symbol,
                title: store.state.title,
                animating: store.state == .connecting
            )
            .frame(width: 148, height: 148)
            .padding(.top, 8)

            Text(store.detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.caption)
                Text(store.settings.username.isEmpty ? "未填写账号" : store.settings.username)
                    .font(.footnote.monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassPill()
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var ringProgress: CGFloat {
        switch store.state {
        case .online: return 1.0
        case .connecting: return 0.72
        case .failed: return 0.55
        case .offline: return 0.22
        case .idle: return 0.32
        }
    }

    private var stateGradient: LinearGradient {
        switch store.state {
        case .online:
            return LinearGradient(colors: [Glass.onlineStart, Glass.onlineEnd],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .connecting:
            return LinearGradient(colors: [Glass.warnStart, Glass.warnEnd],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .failed:
            return LinearGradient(colors: [Glass.failStart, Glass.failEnd],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .offline, .idle:
            return LinearGradient(colors: [Glass.accentStart, Glass.accentEnd],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
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

    // MARK: - 多端切换

    private var profileStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionHeader(title: "设备身份")
                Button {
                    showingProfileEditor = true
                } label: {
                    Label("新建", systemImage: "plus.circle")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassPill()
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.profiles) { profile in
                        profileChip(profile)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .glassCard()
    }

    private func profileChip(_ profile: TerminalProfile) -> some View {
        let selected = profile.id == store.settings.selectedProfileID
        return Button {
            store.selectProfile(profile.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: profile.staType == "pad" ? "ipad" : "iphone")
                        .font(.caption)
                    Text(profile.name)
                        .font(.footnote.weight(.semibold))
                }
                Text(profile.staType == "pad" ? "平板 · btype=\(profile.btype)" : "手机 · btype=\(profile.btype)")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.85))
            .glassPill(selected: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 操作

    private var actionRow: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.login() }
            } label: {
                HStack(spacing: 8) {
                    if store.state == .connecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                    }
                    Text(store.state == .connecting ? "认证中…" : "立即认证")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(GlassButtonStyle(tint: Glass.accentStart, height: 52))
            .disabled(store.state == .connecting)

            HStack(spacing: 12) {
                Button {
                    Task { await store.refreshState() }
                } label: {
                    Label("查状态", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .buttonStyle(GlassButtonStyle(height: 46))

                Button {
                    if store.autoRunning {
                        store.setAutoReconnect(false)
                    } else {
                        store.setAutoReconnect(true)
                    }
                } label: {
                    Label(store.autoRunning ? "停止守护" : "自动守护",
                          systemImage: store.autoRunning ? "stop.circle" : "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(store.autoRunning ? Color.white : Color.white.opacity(0.92))
                }
                .buttonStyle(GlassButtonStyle(
                    tint: store.autoRunning ? Glass.onlineStart : nil,
                    height: 46
                ))
            }

            Button {
                openPortal()
            } label: {
                Label("打开 Portal 网页（补全资料 / 网页登录）", systemImage: "safari")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(GlassButtonStyle(height: 44))
        }
    }

    private var autoRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title3)
                .foregroundStyle(Glass.accentStart)

            VStack(alignment: .leading, spacing: 3) {
                Text("掉线自动重连")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("每 \(Int(store.settings.reconnectInterval)) 秒检查一次")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { store.settings.autoReconnect },
                set: { store.setAutoReconnect($0) }
            ))
            .labelsHidden()
            .tint(Glass.onlineStart)
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - 信息

    private var infoCard: some View {
        VStack(spacing: 0) {
            GlassSectionHeader(title: "连接信息")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            infoLine("当前档案", store.currentProfile.subtitle)
            dividerLine()
            infoLine("服务端 MAC", store.serverMac.isEmpty ? "未获取" : store.serverMac)
            dividerLine()
            infoLine("Portal", store.portal.isEmpty ? "未探测" : store.portal)
        }
        .padding(.bottom, 6)
        .glassCard()
    }

    private func dividerLine() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - 日志预览

    private var logPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GlassSectionHeader(title: "运行日志")
                Button {
                    showLogs = true
                } label: {
                    Text("全部")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassPill()
                }
                .buttonStyle(.plain)
            }

            if store.logs.isEmpty {
                Text("还没有记录")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.logs.suffix(6)) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.stamp)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.38))
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCard(elevated: false)
    }
}

#Preview {
    RootView().environmentObject(AppStore())
}
