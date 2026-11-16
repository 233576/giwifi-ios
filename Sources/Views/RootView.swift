import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var showingProfileEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    profileStrip
                    actionRow
                    autoRow
                    infoCard
                    logPreview
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("GiWiFi 助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLogs = true
                    } label: {
                        Image(systemName: "text.alignleft")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
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
            .alert("提示", isPresented: Binding(
                get: { store.errorText != nil },
                set: { if !$0 { store.clearError() } }
            )) {
                Button("好", role: .cancel) { store.clearError() }
            } message: {
                Text(store.errorText ?? "")
            }
        }
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: store.state == .connecting ? 0.75 : (store.state == .online ? 1 : 0.25))
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(store.state == .connecting ? 0 : -90))
                    .animation(.easeInOut(duration: 0.6), value: store.state)
                VStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                    Text(store.state.title)
                        .font(.headline)
                }
                .foregroundStyle(color)
            }
            .frame(width: 132, height: 132)
            .padding(.top, 6)

            Text(store.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)

            Text(store.settings.username.isEmpty ? "未填写账号" : store.settings.username)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var color: Color {
        switch store.state {
        case .online: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .offline: return .gray
        case .idle: return .accentColor
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("设备身份")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showingProfileEditor = true
                } label: {
                    Label("新建", systemImage: "plus.circle")
                        .font(.footnote)
                }
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func profileChip(_ profile: TerminalProfile) -> some View {
        let selected = profile.id == store.settings.selectedProfileID
        return Button {
            store.selectProfile(profile.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: profile.staType == "pad" ? "ipad" : "iphone")
                        .font(.caption)
                    Text(profile.name)
                        .font(.footnote.weight(.semibold))
                }
                Text(profile.staType == "pad" ? "平板 · btype=\(profile.btype)" : "手机 · btype=\(profile.btype)")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 操作

    private var actionRow: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.login() }
            } label: {
                HStack {
                    if store.state == .connecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                    }
                    Text(store.state == .connecting ? "认证中…" : "立即认证")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(store.state == .connecting ? Color.gray : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(store.state == .connecting)

            HStack(spacing: 10) {
                Button {
                    Task { await store.refreshState() }
                } label: {
                    Label("查状态", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    if store.autoRunning {
                        store.setAutoReconnect(false)
                    } else {
                        store.setAutoReconnect(true)
                    }
                } label: {
                    Label(store.autoRunning ? "停止守护" : "自动守护",
                          systemImage: store.autoRunning ? "stop.circle" : "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .font(.subheadline)
        }
    }

    private var autoRow: some View {
        Toggle(isOn: Binding(
            get: { store.settings.autoReconnect },
            set: { store.setAutoReconnect($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("掉线自动重连")
                    .font(.subheadline.weight(.medium))
                Text("每 \(Int(store.settings.reconnectInterval)) 秒检查一次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 信息

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoLine("当前档案", store.currentProfile.subtitle)
            Divider().padding(.leading, 16)
            infoLine("服务端 MAC", store.serverMac.isEmpty ? "未获取" : store.serverMac)
            Divider().padding(.leading, 16)
            infoLine("Portal", store.portal.isEmpty ? "未探测" : store.portal)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - 日志预览

    private var logPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("运行日志")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("全部") { showLogs = true }
                    .font(.footnote)
            }

            if store.logs.isEmpty {
                Text("还没有记录")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(store.logs.suffix(6)) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.stamp)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    RootView().environmentObject(AppStore())
}
