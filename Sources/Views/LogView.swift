import SwiftUI
import UIKit

struct LogView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                if store.logs.isEmpty {
                    Text("还没有日志记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.logs) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(line.stamp)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            UIPasteboard.general.string = store.logText
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            store.clearLogs()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }
}
