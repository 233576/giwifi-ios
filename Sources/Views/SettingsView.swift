import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var portal: String = GiWifiProtocol.defaultPortal
    @State private var nasName: String = ""
    @State private var editing: TerminalProfile?
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        accountCard
                        deviceCard
                        portalCard
                        nasCard
                        protocolCard
                        keepOnlineCard
                        profileCard
                        aboutCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Flat.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.updateSettings { settings in
                            settings.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
                            settings.password = password
                            settings.portalOverride = portal.trimmingCharacters(in: .whitespacesAndNewlines)
                            settings.nasName = nasName.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .flatPill(selected: true)
                    }
                }
            }
            .onAppear {
                username = store.settings.username
                password = store.settings.password
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
        .preferredColorScheme(.dark)
    }

    // MARK: - 账号

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "账号")

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .font(.footnote)
                        .foregroundStyle(Flat.textTertiary)
                        .frame(width: 18)
                    TextField("校园网账号（手机号）", text: $username)
                        .textContentType(.username)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.white)
                }
                .flatField()

                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Flat.textTertiary)
                        .frame(width: 18)
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .foregroundStyle(.white)
                }
                .flatField()
            }

            Text("密码只保存在本机钥匙串。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
                .padding(.leading, 4)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 设备

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "设备")

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

            Text("appUuid 是 GiWiFi 识别终端的凭据，重新生成后需要重新认证一次。")
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
            }
            .flatField()

            HStack(spacing: 10) {
                Button {
                    portal = GiWifiProtocol.defaultPortal
                } label: {
                    Text("恢复默认站点")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Flat.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .flatPill()
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Text("留空则走 APK 原始探测（115.159.209.137 → 302 跳转）。填了就直连该站点，认证接口按同一主机拼接。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
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
            }
            .flatField()

            Text("认证被拒 CHALLENGE_ERR_DENY 基本都是这里对不上。留空时先用 queryAuthState 返回的真实网关名，取不到再抓 Portal 页面；填了就只认这个值。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
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

            Text("默认 1，个别学校要求 2 或 3；认证失败可以先按学校要求调整。")
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

            Rectangle()
                .fill(Flat.stroke)
                .frame(height: 1)

            toggleRow("设备冲突时自动换绑",
                      isOn: Binding(
                        get: { store.settings.autoRebind },
                        set: { value in store.updateSettings { $0.autoRebind = value } }
                      ))

            Rectangle()
                .fill(Flat.stroke)
                .frame(height: 1)

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

    // MARK: - 设备档案

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FlatSectionHeader(title: "设备档案")
                Button {
                    editing = TerminalProfile(name: "", btype: "1", staType: "phone",
                                              staModel: "", macOverride: "")
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

            VStack(spacing: 8) {
                ForEach(store.profiles) { profile in
                    profileRow(profile)
                }
            }

            Text("内置档案不可删除；点内置档案会复制一份再编辑。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    private func profileRow(_ profile: TerminalProfile) -> some View {
        let selected = profile.id == store.settings.selectedProfileID
        return Button {
            if profile.isBuiltin {
                editingProfileCopy(profile)
            } else {
                editing = profile
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: profile.staType == "pad" ? "ipad" : "iphone")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
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
                        .foregroundStyle(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .flatField(radius: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !profile.isBuiltin {
                Button(role: .destructive) {
                    store.deleteProfile(profile.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            Button {
                store.selectProfile(profile.id)
            } label: {
                Label("设为当前", systemImage: "checkmark")
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

    private func editingProfileCopy(_ profile: TerminalProfile) {
        editing = TerminalProfile(name: profile.name + " 副本",
                                  btype: profile.btype,
                                  staType: profile.staType,
                                  staModel: profile.staModel,
                                  macOverride: profile.macOverride)
    }

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
