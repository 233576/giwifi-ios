import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAccounts = false
    @State private var showingProfileEditor = false
    @State private var showingPortalWeb = false

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        accountCard
                        statusCard
                        actionRow
                        kindStrip
                        autoRow
                        infoCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refreshState() }
            }
            .navigationTitle("GiWiFi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAccounts) {
                AccountsView(isPicker: true).environmentObject(store)
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
                if store.needsRebind {
                    Button("换绑到本机") {
                        Task { await store.confirmRebind() }
                    }
                }
                if store.needsProfile || store.needsWebAuth {
                    Button("内置网页登录") { openPortal() }
                }
                Button("取消", role: .cancel) { store.clearError() }
            } message: {
                Text(store.errorText ?? "")
            }
        }
    }

    /// Portal 地址（手填优先，否则用默认站点）。
    private var portalURL: URL? {
        let raw = store.settings.portalOverride.isEmpty
            ? GiWifiProtocol.defaultPortal
            : store.settings.portalOverride
        return GiWifiClient.normalizedPortalURL(raw)
    }

    private func openPortal() {
        store.clearError()
        showingPortalWeb = true
    }

    // MARK: - 账号

    private var accountCard: some View {
        Button {
            showAccounts = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Flat.accent.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Flat.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.currentAccountName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Flat.textPrimary)
                    Text(store.settings.username.isEmpty ? "点此添加或登录账号" : store.settings.username)
                        .font(.caption)
                        .foregroundStyle(Flat.textTertiary)
                }

                Spacer(minLength: 0)

                Text("\(store.accounts.count) 个账号")
                    .font(.caption2)
                    .foregroundStyle(Flat.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Flat.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .flatCard()
        }
        .buttonStyle(.plain)
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

                Text(store.state == .online ? "在线" : "离线")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(store.state == .online ? Flat.green : Flat.textTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .flatPill(selected: store.state == .online,
                              tint: Flat.green)
            }

            FlatProgressBar(progress: progress, tint: stateColor)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 操作

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.login() }
            } label: {
                HStack(spacing: 8) {
                    if store.state == .connecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(buttonTitle)
                        .font(.headline)
                }
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: true, height: 50))
            .disabled(store.state == .connecting)

            HStack(spacing: 10) {
                Button {
                    Task { await store.refreshState() }
                } label: {
                    Label("检测状态", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 42))

                Button {
                    openPortal()
                } label: {
                    Label("内置网页", systemImage: "safari")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 42))
            }

            // 网页表单登录：页内自签，绕开 API 通路的 CHALLENGE_ERR_DENY
            Button {
                Task { await store.webLoginNow() }
            } label: {
                Label("网页表单登录", systemImage: "text.insert")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.purple, filled: false, height: 42))
            .disabled(store.state == .connecting)

            // 常驻入口：账号绑在别的设备上（43/203）时点这里换绑到本机
            Button {
                Task { await store.rebindDevice() }
            } label: {
                HStack(spacing: 8) {
                    if store.state == .connecting && store.rebinding {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Flat.orange)
                    } else {
                        Image(systemName: "iphone.and.arrow.forward")
                    }
                    Text(store.needsRebind ? "换绑到本机（需要确认）" : "换绑到本机")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FlatButtonStyle(tint: Flat.orange, filled: store.needsRebind, height: 42))
            .disabled(store.state == .connecting)
        }
    }

    // MARK: - 设备类型

    private var kindStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FlatSectionHeader(title: "上报设备")
                Spacer()
                Button {
                    showingProfileEditor = true
                } label: {
                    Text("自定义机型")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Flat.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .flatPill()
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(DeviceKind.allCases) { kind in
                    let selected = store.currentProfile.kind == kind
                    Button {
                        store.selectKind(kind)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 18, weight: .medium))
                            Text(kind.title)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(selected ? Flat.accent : Flat.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .flatPill(selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("报文字段 btype/staType/staModel 与浏览器 UA 会一起切换。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 自动

    private var autoRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("自动守护")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Flat.textPrimary)
                Text(store.autoRunning
                     ? "每 \(Int(store.settings.reconnectInterval)) 秒检测，掉线自动认证"
                     : "关闭时只能手动认证")
                    .font(.caption2)
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

            infoLine("设备档案", "\(store.currentProfile.kind.title) · \(store.currentProfile.staModel)")
            FlatDivider(inset: 16)
            infoLine("服务端 MAC", store.serverMac.isEmpty ? "未获取" : store.serverMac)
            FlatDivider(inset: 16)
            infoLine("Portal", store.portal.isEmpty ? "未探测" : store.portal)
            FlatDivider(inset: 16)
            infoLine("浏览器 UA", store.currentProfile.kind.userAgent)
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

    // MARK: - 派生状态

    private var buttonTitle: String {
        switch store.state {
        case .online: return "重新认证"
        case .connecting: return "认证中…"
        default: return "立即认证"
        }
    }

    private var symbol: String {
        switch store.state {
        case .online: return "checkmark"
        case .checking, .connecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark"
        case .offline, .idle: return "wifi.slash"
        }
    }

    private var stateColor: Color {
        switch store.state {
        case .online: return Flat.green
        case .checking, .connecting: return Flat.accent
        case .failed: return Flat.red
        case .offline, .idle: return Flat.textTertiary
        }
    }

    private var progress: Double {
        switch store.state {
        case .online: return 1
        case .checking: return 0.35
        case .connecting: return 0.65
        case .failed: return 0.28
        case .offline, .idle: return 0.06
        }
    }
}

#Preview {
    RootView().environmentObject(AppStore())
}
