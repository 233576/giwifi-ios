import SwiftUI

/// 液态玻璃（Liquid Glass）视觉层。
///
/// iOS 26 有系统级 `.glassEffect()`，但本工程最低支持 iOS 16，
/// 所以这里用 `Material` + 多层高光描边手搓一套等效质感：
/// 半透明毛玻璃底、左上高光、右下暗边、外投影，跟系统的玻璃卡片观感一致。
enum Glass {
    static let cardRadius: CGFloat = 24
    static let chipRadius: CGFloat = 16
    static let controlRadius: CGFloat = 18

    static let accentStart = Color(red: 0.35, green: 0.78, blue: 1.00)
    static let accentEnd = Color(red: 0.42, green: 0.47, blue: 1.00)

    static let onlineStart = Color(red: 0.32, green: 0.92, blue: 0.66)
    static let onlineEnd = Color(red: 0.20, green: 0.72, blue: 0.86)
    static let warnStart = Color(red: 1.00, green: 0.78, blue: 0.35)
    static let warnEnd = Color(red: 1.00, green: 0.52, blue: 0.36)
    static let failStart = Color(red: 1.00, green: 0.45, blue: 0.52)
    static let failEnd = Color(red: 0.92, green: 0.31, blue: 0.60)
}

// MARK: - 背景

/// 极光背景：深底 + 三团彩色光晕 + 极淡网格，给玻璃提供"可透的东西"。
struct AuroraBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.16),
                        Color(red: 0.08, green: 0.06, blue: 0.20),
                        Color(red: 0.03, green: 0.05, blue: 0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.24, green: 0.62, blue: 1.00).opacity(0.55))
                    .frame(width: w * 1.1, height: w * 1.1)
                    .blur(radius: 110)
                    .offset(x: -w * 0.34, y: -h * 0.30)

                Circle()
                    .fill(Color(red: 0.62, green: 0.30, blue: 1.00).opacity(0.45))
                    .frame(width: w * 0.95, height: w * 0.95)
                    .blur(radius: 120)
                    .offset(x: w * 0.36, y: -h * 0.06)

                Circle()
                    .fill(Color(red: 0.10, green: 0.85, blue: 0.78).opacity(0.32))
                    .frame(width: w * 0.85, height: w * 0.85)
                    .blur(radius: 130)
                    .offset(x: -w * 0.12, y: h * 0.42)

                // 极淡网格，增加"玻璃后面有结构"的层次
                GridTexture()
                    .stroke(Color.white.opacity(0.045), lineWidth: 0.6)
            }
        }
        .ignoresSafeArea()
    }
}

private struct GridTexture: Shape {
    var spacing: CGFloat = 34

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

// MARK: - 玻璃卡片

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = Glass.cardRadius
    var tint: Color? = nil
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if let tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.42), tint.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    // 玻璃厚度：左上高光 → 右下暗边
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.16), .white.opacity(0.02), .black.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.overlay)

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.12), .white.opacity(0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: .black.opacity(elevated ? 0.35 : 0.18),
                    radius: elevated ? 22 : 10,
                    x: 0,
                    y: elevated ? 12 : 5)
    }
}

extension View {
    /// 液态玻璃卡片。
    func glassCard(radius: CGFloat = Glass.cardRadius,
                   tint: Color? = nil,
                   elevated: Bool = true) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint, elevated: elevated))
    }

    /// 玻璃列表/表单背景（透明化系统底色，露出极光背景）。
    func glassListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}

// MARK: - 玻璃按钮

struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var radius: CGFloat = Glass.controlRadius
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if let tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.85), tint.opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.overlay)

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.65), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// 小尺寸玻璃胶囊（设备身份 chip、状态标签等）。
struct GlassPill: ViewModifier {
    var selected: Bool = false
    var tint: Color = Glass.accentStart

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    if selected {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(colors: [tint.opacity(0.90), tint.opacity(0.55)],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
                            )
                    }
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(selected ? 0.75 : 0.35),
                                                    .white.opacity(0.10)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: .black.opacity(selected ? 0.30 : 0.12), radius: 10, y: 4)
    }
}

extension View {
    func glassPill(selected: Bool = false, tint: Color = Glass.accentStart) -> some View {
        modifier(GlassPill(selected: selected, tint: tint))
    }
}

// MARK: - 状态环

/// 玻璃状态环：外圈玻璃底、内圈渐变进度、中心图标。
struct GlassStatusRing: View {
    var progress: CGFloat
    var gradient: LinearGradient
    var symbol: String
    var title: String
    var animating: Bool

    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
            Circle()
                .fill(
                    LinearGradient(colors: [.white.opacity(0.10), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 12)
                .padding(8)

            Circle()
                .trim(from: 0, to: max(0.04, progress))
                .stroke(gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(animating
                           ? .linear(duration: 1.4).repeatForever(autoreverses: false)
                           : .easeInOut(duration: 0.7),
                           value: spin)
                .animation(.easeInOut(duration: 0.7), value: progress)
                .padding(8)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)

            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .onAppear { if animating { spin = true } }
        .onChange(of: animating) { value in spin = value }
    }
}

// MARK: - 玻璃输入框

struct GlassFieldModifier: ViewModifier {
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(colors: [.white.opacity(0.10), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
    }
}

extension View {
    func glassField(radius: CGFloat = 14) -> some View {
        modifier(GlassFieldModifier(radius: radius))
    }
}

// MARK: - 分区标题

struct GlassSectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 6)
    }
}
