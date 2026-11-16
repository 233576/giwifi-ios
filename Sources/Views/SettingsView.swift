import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var editing: TerminalProfile?
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("校园网账号（手机号）", text: $username)
                        .textContentType(.username)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("账号")
                } footer: {
                    Text("密码只保存在本机钥匙串。")
                }

                Section {
                    HStack {
                        Text("设备标识 appUuid")
                        Spacer()
                        Text(store.settings.appUuid.suffix(9))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button("重新生成设备标识") { confirmingReset = true }
                } header: {
                    Text("设备")
                } footer: {
                    Text("appUuid 是 GiWiFi 识别终端的凭据，重新生成后需要重新认证一次。")
                }

                Section {
                    Stepper(value: Binding(
                        get: { store.settings.serviceType },
                        set: { value in store.updateSettings { $0.serviceType = value } }
                    ), in: 1...3) {
                        HStack {
                            Text("service_type")
                            Spacer()
                            Text("\(store.settings.serviceType)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("协议参数")
                } footer: {
                    Text("默认 1，个别学校要求 2 或 3；认证失败可以先按学校要求调整。")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { store.settings.autoReconnect },
                        set: { store.setAutoReconnect($0) }
                    )) {
                        Text("掉线自动重连")
                    }
                    Toggle(isOn: Binding(
                        get: { store.settings.autoRebind },
                        set: { value in store.updateSettings { $0.autoRebind = value } }
                    )) {
                        Text("设备冲突时自动换绑")
                    }
                    Stepper(value: Binding(
                        get: { Int(store.settings.reconnectInterval) },
                        set: { value in store.updateSettings { $0.reconnectInterval = Double(value) } }
                    ), in: 10...300, step: 5) {
                        HStack {
                            Text("检查间隔")
                            Spacer()
                            Text("\(Int(store.settings.reconnectInterval)) 秒")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("保持在线")
                }

                Section {
                    ForEach(store.profiles) { profile in
                        Button {
                            if profile.isBuiltin {
                                editingProfileCopy(profile)
                            } else {
                                editing = profile
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name)
                                        .foregroundStyle(.primary)
                                    Text(profile.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == store.settings.selectedProfileID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let profile = store.profiles[index]
                            if !profile.isBuiltin {
                                store.deleteProfile(profile.id)
                            }
                        }
                    }
                    Button {
                        editing = TerminalProfile(name: "", btype: "1", staType: "phone",
                                                  staModel: "", macOverride: "")
                    } label: {
                        Label("新建设备档案", systemImage: "plus.circle")
                    }
                } header: {
                    Text("设备档案")
                } footer: {
                    Text("内置档案不可删除；点内置档案会复制一份再编辑。")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Self.appVersion)
                            .foregroundStyle(.secondary)
                    }
                    Link("参考实现 xGiWifi（Dart/Flutter）",
                         destination: URL(string: "https://github.com/Mhenwa/xGiWifi")!)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        store.updateSettings { settings in
                            settings.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
                            settings.password = password
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                username = store.settings.username
                password = store.settings.password
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
