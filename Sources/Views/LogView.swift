import SwiftUI
import UIKit

struct LogView: View {
    @EnvironmentObject private var store: AppStore
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                FlatBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.logs.isEmpty {
                            Text("还没有日志记录")
                                .font(.footnote)
                                .foregroundStyle(Flat.textTertiary)
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
                                        .foregroundStyle(Flat.textSecondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .flatField(radius: 10)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Flat.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = store.logText
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .flatPill()
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.clearLogs()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Flat.red)
                                .frame(width: 32, height: 32)
                                .flatPill()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
