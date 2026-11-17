import SwiftUI
import UIKit

struct ProfileEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// 传入 nil 表示新建。
    let profile: TerminalProfile?

    @State private var name = ""
    @State private var kind: DeviceKind = .phone
    @State private var manufacturer = ""
    @State private var model = ""
    @State private var sdk = ""
    @State private var release = ""
    @State private var macOverride = ""

    private var isNew: Bool { profile == nil }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        identityCard
                        modelCard
                        macCard
                        presetCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(isNew ? "新建设备档案" : "编辑设备档案")
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
                        save()
                    } label: {
                        Text("保存")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .flatPill(selected: canSave)
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                }
            }
            .onAppear(perform: fill)
        }
        .preferredColorScheme(.dark)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && staModelValue.count >= 3
    }

    // MARK: - 身份

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlatSectionHeader(title: "身份")

            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .font(.footnote)
                    .foregroundStyle(Flat.textTertiary)
                    .frame(width: 18)
                TextField("档案名称（例如 我的 iPad）", text: $name)
                    .foregroundStyle(.white)
            }
            .flatField()

            HStack(spacing: 8) {
                ForEach(DeviceKind.allCases) { option in
                    let selected = kind == option
                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 15, weight: .medium))
                            Text(option.title)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(selected ? Flat.accent : Flat.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .flatPill(selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("btype=\(kind.btype) · staType=\(kind.staType)：GiWiFi 只认手机 / 平板 / 电脑三类。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 机型

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "机型描述 staModel")

            VStack(spacing: 10) {
                labeledField("厂商", "如 Xiaomi", $manufacturer)
                labeledField("型号", "如 M2011K2C", $model)
                labeledField("SDK", "如 30", $sdk, keyboard: .numberPad)
                labeledField("Android 版本", "如 11", $release, keyboard: .decimalPad)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle")
                    .font(.caption2)
                Text("上传值：\(staModelValue)")
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(2)
            }
            .foregroundStyle(Flat.textSecondary)
        }
        .padding(16)
        .flatCard()
    }

    private func labeledField(_ label: String, _ placeholder: String,
                              _ text: Binding<String>,
                              keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Flat.textSecondary)
                .frame(width: 66, alignment: .leading)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
        }
        .flatField(radius: 12)
    }

    // MARK: - MAC

    private var macCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "伪装 MAC")

            HStack(spacing: 10) {
                Image(systemName: "number")
                    .font(.footnote)
                    .foregroundStyle(Flat.textTertiary)
                    .frame(width: 18)
                TextField("留空则用本机 / 服务端返回的 MAC", text: $macOverride)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .foregroundStyle(.white)
            }
            .flatField()

            Text("iOS 读不到真实 MAC，这里填的地址会直接写进认证报文；留空则按 IP 识别。")
                .font(.caption2)
                .foregroundStyle(Flat.textTertiary)
        }
        .padding(16)
        .flatCard()
    }

    // MARK: - 快速填充

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlatSectionHeader(title: "快速填充")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TerminalProfile.builtins) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            Text(preset.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Flat.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .flatPill()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .flatCard(fill: Flat.surfaceLow)
    }

    private var staModelValue: String {
        [manufacturer, model, sdk, release]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ",")
    }

    private func apply(_ preset: TerminalProfile) {
        let parts = preset.staModel.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 4 {
            manufacturer = parts[0]
            model = parts[1]
            sdk = parts[2]
            release = parts[3]
        }
        kind = preset.kind
        if name.isEmpty { name = preset.name }
    }

    /// 切换类别时把机型描述换成该类别的默认值（苹果机型）。
    private func select(_ option: DeviceKind) {
        kind = option
        let parts = option.defaultModel.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 4 {
            manufacturer = parts[0]
            model = parts[1]
            sdk = parts[2]
            release = parts[3]
        }
        if name.isEmpty { name = option.title }
    }

    private func fill() {
        guard let profile else {
            if name.isEmpty { apply(TerminalProfile.phone) }
            return
        }
        name = profile.name
        kind = profile.kind
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
            updated.btype = kind.btype
            updated.staType = kind.staType
            updated.staModel = staModelValue
            updated.macOverride = macOverride.trimmingCharacters(in: .whitespaces)
            store.updateProfile(updated)
        } else {
            let created = TerminalProfile(name: trimmedName,
                                          btype: kind.btype,
                                          staType: kind.staType,
                                          staModel: staModelValue,
                                          macOverride: macOverride.trimmingCharacters(in: .whitespaces))
            store.addProfile(created)
            store.selectProfile(created.id)
        }
        dismiss()
    }
}
