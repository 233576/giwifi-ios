import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var portal: String = GiWifiProtocol.defaultPortal
    @State private var nasName: String = ""
    @State private var editing: TerminalProfile?
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        accountsCard
                        kindCard
                        portalCard
                        nasCard
                        protocolCard
                        keepOnlineCard
                        customProfileCard
                        aboutCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                portal = store.settings.portalOverride
                nasName = store.settings.nasName
            }
            .sheet(item: $editing) { profile in
                ProfileEditorView(profile: profile).environmentObject(store)
            }
            .alert("重新生成设备标识？", isPresented: $confirmingReset) {
                Button("取消", role: .cancel) {}
                Button("生成", role: .destructive) { store.resetAppUuid() }
            } message: {
                Text("下次认证会以新设备身份登录，可能需要重新换绑。")
            }
        }
    }

    // MARK: - 账号管理入口

    private var accountsCard: some View {
        NavigationLink {
            AccountsView().environmentObject(store)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Flat.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("账号管理")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Flat.textPrimary)
                    Text(store.accounts.isEmpty
                         ? "添加校园网账号，支持多个账号切换登录"
                         : "\(store.accounts.count) 个账号 · 当前 \(store.currentAccountName)")
                        .font(.caption2)
                        .foregroundStyle(Flat.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Flat.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .flatCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 设备类别

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "上报设备")

            HStack(spacing: 8) {
                ForEach(DeviceKind.allCases) { kind in
                    let selected = store.currentProfile.kind == kind
                    Button {
                        store.selectKind(kind)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 17, weight: .medium))
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

            VStack(alignment: .leading, spacing: 4) {
                Text("上报值：\(store.currentProfile.staModel)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Flat.textSecondary)
                Text("btype=\(store.currentProfile.btype) · staType=\(store.currentProfile.staType)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Flat.textTertiary)
            }

            Text("只区分手机 / 平板 / 电脑，型号统一用苹果；内置网页登录的 UA 会跟着一起换。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - Portal

    private var portalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "Portal 站点")

            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.footnote)
                    .foregroundStyle(Flat.textTertiary)
                    .frame(width: 18)
                TextField("http://100.100.9.2/gportal/web/login", text: $portal)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
                    .onSubmit { applyPortal() }
            }
            .flatField()

            HStack(spacing: 10) {
                Button {
                    portal = GiWifiProtocol.defaultPortal
                    applyPortal()
                } label: {
                    Text("恢复默认站点")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Flat.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .flatPill()
                }
                .buttonStyle(.plain)

                Button {
                    applyPortal()
                } label: {
                    Text("保存")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .flatPill(selected: true)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Text("留空则走 APK 原始探测（115.159.209.137 → 302 跳转）。填了就直连该站点。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    private func applyPortal() {
        let value = portal.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings { $0.portalOverride = value }
        store.append("Portal 站点已更新：\(value.isEmpty ? "自动探测" : value)")
    }

    // MARK: - 网关名

    private var nasCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "网关名 nasName")

            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.footnote)
                    .foregroundStyle(Flat.textTertiary)
                    .frame(width: 18)
                TextField("留空自动获取（如 GiWiFi_lnsfHG）", text: $nasName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
                    .onSubmit { applyNasName() }
            }
            .flatField()

            Text("认证被拒 CHALLENGE_ERR_DENY 基本都是这里对不上。留空时先用 queryAuthState 返回的真实网关名，取不到再抓 Portal 页面。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    private func applyNasName() {
        let value = nasName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings { $0.nasName = value }
        store.append("网关名已更新：\(value.isEmpty ? "自动" : value)")
    }

    // MARK: - 协议参数

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "协议参数")

            Stepper(value: Binding(
                get: { store.settings.serviceType },
                set: { value in store.updateSettings { $0.serviceType = value } }
            ), in: 1...3) {
                HStack {
                    Text("service_type")
                        .font(.subheadline)
                        .foregroundStyle(Flat.textPrimary)
                    Spacer()
                    Text("\(store.settings.serviceType)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Flat.accent)
                }
            }

            FlatDivider(inset: 0)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设备标识 appUuid")
                        .font(.subheadline)
                        .foregroundStyle(Flat.textPrimary)
                    Text("…\(store.settings.appUuid.suffix(9))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Flat.textTertiary)
                }
                Spacer()
                Button {
                    confirmingReset = true
                } label: {
                    Text("重新生成")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .flatPill()
                }
                .buttonStyle(.plain)
            }

            Text("每个账号有独立的 appUuid，重新生成后需要重新认证一次。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 保持在线

    private var keepOnlineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlatSectionHeader(title: "保持在线")

            toggleRow("掉线自动重连",
                      isOn: Binding(
                        get: { store.settings.autoReconnect },
                        set: { store.setAutoReconnect($0) }
                      ))

            FlatDivider(inset: 0)

            toggleRow("设备冲突时自动换绑",
                      isOn: Binding(
                        get: { store.settings.autoRebind },
                        set: { value in store.updateSettings { $0.autoRebind = value } }
                      ))

            FlatDivider(inset: 0)

            Stepper(value: Binding(
                get: { Int(store.settings.reconnectInterval) },
                set: { value in store.updateSettings { $0.reconnectInterval = Double(value) } }
            ), in: 10...300, step: 5) {
                HStack {
                    Text("检查间隔")
                        .font(.subheadline)
                        .foregroundStyle(Flat.textPrimary)
                    Spacer()
                    Text("\(Int(store.settings.reconnectInterval)) 秒")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Flat.accent)
                }
            }
        }
        .padding(16)
        .flatCard()
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Flat.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Flat.green)
        }
    }

    // MARK: - 自定义档案

    private var customProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FlatSectionHeader(title: "自定义机型")
                Button {
                    editing = TerminalProfile(name: "", btype: DeviceKind.phone.btype,
                                              staType: DeviceKind.phone.staType,
                                              staModel: DeviceKind.phone.defaultModel,
                                              macOverride: "")
                } label: {
                    Label("新建", systemImage: "plus.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .flatPill()
                }
                .buttonStyle(.plain)
            }

            if store.customProfiles.isEmpty {
                Text("没有自定义机型。内置的手机 / 平板 / 电脑已经够用，需要特定型号再来这里加。")
                    .font(.caption2)
                    .foregroundStyle(Flat.textTertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.customProfiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
        .padding(16)
        .flatCard()
    }

    private func profileRow(_ profile: TerminalProfile) -> some View {
        let selected = profile.id == store.settings.selectedProfileID
        return Button {
            editing = profile
        } label: {
            HStack(spacing: 10) {
                Image(systemName: profile.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(Flat.textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Flat.textPrimary)
                    Text(profile.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Flat.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Flat.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Flat.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .flatField(radius: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.selectProfile(profile.id)
            } label: {
                Label("设为当前", systemImage: "checkmark")
            }
            Button(role: .destructive) {
                store.deleteProfile(profile.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "关于")

            HStack {
                Text("版本")
                    .font(.subheadline)
                    .foregroundStyle(Flat.textPrimary)
                Spacer()
                Text(Self.appVersion)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Flat.textSecondary)
            }

            Link(destination: URL(string: "https://github.com/Mhenwa/xGiWifi")!) {
                HStack {
                    Text("参考实现 xGiWifi（Dart/Flutter）")
                        .font(.footnote)
                        .foregroundStyle(Flat.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(Flat.accent.opacity(0.7))
                }
            }
        }
        .padding(16)
        .flatCard(fill: Flat.surfaceLow)
    }

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
