import SwiftUI

/// 水墨配色：宣纸白、松烟墨、青黛、朱砂印。
enum Ink {
    static let paper = Color(red: 0.965, green: 0.953, blue: 0.925)        // #F6F3EC
    static let paperDeep = Color(red: 0.933, green: 0.914, blue: 0.871)
    static let ink = Color(red: 0.118, green: 0.125, blue: 0.133)          // #1E2022
    static let inkSoft = Color(red: 0.322, green: 0.337, blue: 0.349)
    static let inkFaint = Color(red: 0.482, green: 0.490, blue: 0.494)
    static let indigo = Color(red: 0.231, green: 0.357, blue: 0.427)       // #3B5B6D 青黛
    static let cinnabar = Color(red: 0.722, green: 0.231, blue: 0.165)     // #B83B2A 朱砂
    static let moss = Color(red: 0.353, green: 0.463, blue: 0.376)
    static let gold = Color(red: 0.702, green: 0.588, blue: 0.373)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// 宣纸底：暖白 + 淡淡的墨晕。
struct PaperBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Ink.paper
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Ink.paperDeep.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(Ink.indigo.opacity(0.08))
                    .frame(width: geometry.size.width * 0.95, height: geometry.size.width * 0.95)
                    .blur(radius: 70)
                    .offset(x: -geometry.size.width * 0.22, y: -geometry.size.height * 0.26)
                Circle()
                    .fill(Ink.ink.opacity(0.06))
                    .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                    .blur(radius: 60)
                    .offset(x: geometry.size.width * 0.32, y: geometry.size.height * 0.34)
            }
        }
        .ignoresSafeArea()
    }
}

/// 朱砂印章。
struct InkSeal: View {
    var text: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(Ink.cinnabar)
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Ink.cinnabar.opacity(0.45), lineWidth: 1.4)
                .padding(-3)
            Text(text)
                .font(Ink.serif(size * 0.48, .semibold))
                .foregroundColor(Ink.paper)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-3))
        .shadow(color: Ink.cinnabar.opacity(0.28), radius: 5, x: 0, y: 2)
    }
}

/// 纸卡片。
struct InkCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Ink.ink.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Ink.ink.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

/// 小圆图标按钮，工具栏和卡片里都用。
struct InkIconButton: View {
    var systemName: String
    var title: String?
    var isActive: Bool = false
    var tint: Color = Ink.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 30)
                    .background(
                        Circle().fill(isActive ? tint.opacity(0.16) : Color.clear)
                    )
                if let title = title {
                    Text(title)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(isActive ? tint : Ink.ink.opacity(0.8))
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 数值进度条。
struct InkBar: View {
    var value: Double?
    var tint: Color = Ink.indigo
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.ink.opacity(0.08))
                if let value = value {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
                }
            }
        }
        .frame(height: height)
    }
}

/// 协议 / 状态小标签。
struct InkTag: View {
    var text: String
    var tint: Color = Ink.indigo

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.13)))
            .foregroundColor(tint)
    }
}

/// 描边输入框样式。
struct InkFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Ink.ink.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    func inkField() -> some View {
        modifier(InkFieldStyle())
    }
}

/// 页面顶部标题：主标题 + 印章。
struct InkHeader: View {
    var title: String
    var subtitle: String?
    var seal: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Ink.serif(26, .semibold))
                    .foregroundColor(Ink.ink)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Ink.inkFaint)
                }
            }
            Spacer(minLength: 8)
            InkSeal(text: seal, size: 40)
        }
    }
}

/// 底部临时提示。
struct InkToast: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Ink.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Ink.ink.opacity(0.9)))
            .shadow(color: Ink.ink.opacity(0.2), radius: 10, x: 0, y: 4)
    }
}

/// 空状态里的水墨小山。
struct InkEmptyMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Ink.indigo.opacity(0.08))
                .frame(width: 150, height: 150)
                .blur(radius: 20)
            Image(systemName: "mountain.2")
                .font(.system(size: 54, weight: .light))
                .foregroundColor(Ink.ink.opacity(0.55))
            Circle()
                .fill(Ink.cinnabar)
                .frame(width: 9, height: 9)
                .offset(x: 46, y: 36)
        }
    }
}
