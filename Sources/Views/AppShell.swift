import SwiftUI

/// 底部三个页签：主页 / 日志 / 设置。
enum AppTab: String, CaseIterable, Identifiable {
    case home
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "主页"
        case .logs: return "日志"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "bolt.horizontal.fill"
        case .logs: return "text.alignleft"
        case .settings: return "gearshape.fill"
        }
    }
}

/// 应用外壳：内容区 + 悬浮底部导航栏。
struct AppShell: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            FlatBackground()

            Group {
                switch tab {
                case .home:
                    RootView()
                case .logs:
                    LogView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .preferredColorScheme(.dark)
        .task {
            await store.autoDetectOnLaunch()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Flat.accent : Flat.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Flat.surfaceHigh)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Flat.strokeStrong, lineWidth: 1)
                )
        )
        .padding(.horizontal, 26)
        .padding(.bottom, 4)
    }
}
