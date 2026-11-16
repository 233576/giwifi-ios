import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// 传入 nil 表示新建。
    let profile: TerminalProfile?

    @State private var name = ""
    @State private var btype = "1"
    @State private var staType = "phone"
    @State private var manufacturer = ""
    @State private var model = ""
    @State private var sdk = ""
    @State private var release = ""
    @State private var macOverride = ""

    private var isNew: Bool { profile == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("档案名称（例如 我的 iPad）", text: $name)
                    Picker("类型 btype", selection: $btype) {
                        Text("1 · 手机").tag("1")
                        Text("2 · 平板").tag("2")
                    }
                    Picker("类别 staType", selection: $staType) {
                        Text("phone").tag("phone")
                        Text("pad").tag("pad")
                    }
                } header: {
                    Text("身份")
                } footer: {
                    Text("btype 与 staType 必须匹配：手机 1/phone，平板 2/pad。")
                }

                Section {
                    TextField("厂商，如 Xiaomi", text: $manufacturer)
                        .autocorrectionDisabled()
                    TextField("型号，如 M2011K2C", text: $model)
                        .autocorrectionDisabled()
                    TextField("SDK，如 30", text: $sdk)
                        .keyboardType(.numberPad)
                    TextField("Android 版本，如 11", text: $release)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("机型描述 staModel")
                } footer: {
                    Text(stripPreview)
                }

                Section {
                    TextField("留空则用本机 / 服务端返回的 MAC", text: $macOverride)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("伪装 MAC")
                } footer: {
                    Text("iOS 读不到真实 MAC，这里填的地址会直接写进认证报文；留空则按 IP 识别。")
                }

                Section {
                    quickPresets
                } header: {
                    Text("快速填充")
                }
            }
            .navigationTitle(isNew ? "新建设备档案" : "编辑设备档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || staModelValue.count < 3)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private var staModelValue: String {
        [manufacturer, model, sdk, release]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ",")
    }

    private var stripPreview: String {
        "上传值：\(staModelValue)"
    }

    @ViewBuilder
    private var quickPresets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TerminalProfile.builtins) { preset in
                    Button(preset.name) {
                        apply(preset)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func apply(_ preset: TerminalProfile) {
        let parts = preset.staModel.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 4 {
            manufacturer = parts[0]
            model = parts[1]
            sdk = parts[2]
            release = parts[3]
        }
        btype = preset.btype
        staType = preset.staType
        if name.isEmpty { name = preset.name }
    }

    private func fill() {
        guard let profile else {
            if name.isEmpty { apply(TerminalProfile.android) }
            return
        }
        name = profile.name
        btype = profile.btype
        staType = profile.staType
        macOverride = profile.macOverride
        let parts = profile.staModel.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 4 {
            manufacturer = parts[0]
            model = parts[1]
            sdk = parts[2]
            release = parts[3]
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let profile, !profile.isBuiltin {
            var updated = profile
            updated.name = trimmedName
            updated.btype = btype
            updated.staType = staType
            updated.staModel = staModelValue
            updated.macOverride = macOverride.trimmingCharacters(in: .whitespaces)
            store.updateProfile(updated)
        } else {
            let created = TerminalProfile(name: trimmedName,
                                          btype: btype,
                                          staType: staType,
                                          staModel: staModelValue,
                                          macOverride: macOverride.trimmingCharacters(in: .whitespaces))
            store.addProfile(created)
            store.selectProfile(created.id)
        }
        dismiss()
    }
}
