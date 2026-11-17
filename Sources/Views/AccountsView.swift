import SwiftUI

/// 账号管理：一个列表，点谁就登录谁。
struct AccountsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// 从主页进来时是「选择账号」模式，选完直接认证并关掉。
    var isPicker: Bool = false

    @State private var adding = false
    @State private var editing: Account?
    @State private var pendingDelete: Account?

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        if store.accounts.isEmpty {
                            emptyCard
                        } else {
                            ForEach(store.accounts) { account in
                                row(account)
                            }
                        }

                        Button {
                            adding = true
                        } label: {
                            Label("添加账号", systemImage: "plus")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FlatButtonStyle(tint: Flat.accent, filled: false, height: 44))
                        .padding(.top, 4)

                        Text("密码只存在本机钥匙串；每个账号有独立的设备标识 appUuid。")
                            .font(.caption2)
                            .foregroundStyle(Flat.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("账号管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isPicker {
                        Button("关闭") { dismiss() }
                            .foregroundStyle(Flat.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Flat.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $adding) {
                AccountEditorView(account: nil).environmentObject(store)
            }
            .sheet(item: $editing) { account in
                AccountEditorView(account: account).environmentObject(store)
            }
            .alert("删除账号？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    if let account = pendingDelete {
                        store.deleteAccount(account.id)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text(pendingDelete.map { "「\($0.displayName)」的密码会一并从钥匙串删除。" } ?? "")
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Flat.textTertiary)
            Text("还没有账号")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Flat.textPrimary)
            Text("添加校园网账号（手机号 + 密码）后即可认证")
                .font(.caption)
                .foregroundStyle(Flat.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .flatCard()
    }

    private func row(_ account: Account) -> some View {
        let isCurrent = account.id == store.settings.currentAccountID
        return Button {
            Task {
                await store.loginAccount(account.id)
                if isPicker { dismiss() }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Flat.accent.opacity(0.2) : Flat.surfaceHigh)
                        .frame(width: 36, height: 36)
                    Text(String(account.displayName.prefix(1)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCurrent ? Flat.accent : Flat.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Flat.textPrimary)
                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Flat.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .flatPill(selected: true, tint: Flat.green)
                        }
                    }
                    Text(account.username)
                        .font(.caption)
                        .foregroundStyle(Flat.textTertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Flat.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .flatCard()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await store.loginAccount(account.id) }
            } label: {
                Label("登录该账号", systemImage: "bolt.fill")
            }
            Button {
                store.selectAccount(account.id)
            } label: {
                Label("设为当前", systemImage: "checkmark.circle")
            }
            Button {
                editing = account
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = account
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// 新增 / 编辑账号。
struct AccountEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let account: Account?

    @State private var name = ""
    @State private var username = ""
    @State private var password = ""

    private var isNew: Bool { account == nil }

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            FlatSectionHeader(title: "账号")

                            field(icon: "person.fill", placeholder: "校园网账号（手机号）", text: $username, secure: false)
                            field(icon: "lock.fill", placeholder: isNew ? "密码" : "密码（留空则不修改）",
                                  text: $password, secure: true)
                        }
                        .padding(16)
                        .flatCard()

                        VStack(alignment: .leading, spacing: 10) {
                            FlatSectionHeader(title: "备注名")
                            field(icon: "tag.fill", placeholder: "例如 我的手机 / 室友账号", text: $name, secure: false)
                            Text("备注名只是给自己看的，认证时用的是上面的账号。")
                                .font(.caption2)
                                .foregroundStyle(Flat.textTertiary)
                        }
                        .padding(16)
                        .flatCard(fill: Flat.surfaceLow)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(isNew ? "添加账号" : "编辑账号")
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
            .onAppear {
                name = account?.name ?? ""
                username = account?.username ?? ""
            }
        }
    }

    private func field(icon: String, placeholder: String,
                       text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Flat.textTertiary)
                .frame(width: 18)
            if secure {
                SecureField(placeholder, text: text)
                    .textContentType(.password)
                    .foregroundStyle(.white)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(.numbersAndPunctuation)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)
            }
        }
        .flatField()
    }

    private func save() {
        if let account {
            store.updateAccount(account.id, name: name, username: username,
                                password: password.isEmpty ? nil : password)
        } else {
            store.addAccount(name: name, username: username, password: password)
        }
        dismiss()
    }
}
