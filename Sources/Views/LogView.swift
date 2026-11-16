import SwiftUI
import UIKit

struct LogView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.logs.isEmpty {
                            Text("还没有日志记录")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 20)
                        } else {
                            ForEach(store.logs) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(line.stamp)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.35))
                                    Text(line.text)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .glassField(radius: 10)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white.opacity(0.75))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = store.logText
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .glassPill()
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.clearLogs()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Glass.failStart)
                                .frame(width: 32, height: 32)
                                .glassPill()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
