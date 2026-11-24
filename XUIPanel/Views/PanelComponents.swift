import SwiftUI

/// 小节标题：标题 + 数量 + 右侧说明。
struct SectionHeader: View {
    var title: String
    var count: Int?
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Ink.serif(15, .semibold))
                .foregroundColor(Ink.ink)
            if let count = count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Ink.inkFaint)
            }
            Spacer(minLength: 4)
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 10.5))
                    .foregroundColor(Ink.inkFaint)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// 概览里的三块指标：CPU / 内存 / 磁盘。
struct MetricTile: View {
    var title: String
    var value: String
    var ratio: Double
    var tint: Color
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Ink.inkFaint)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(Ink.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            InkBar(value: ratio, tint: tint, height: 4)
            if let note = note {
                Text(note)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Ink.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Ink.ink.opacity(0.035))
        )
    }
}

/// 一行小信息：上面小标题，下面数值。
struct StatItem: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(Ink.inkFaint)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Ink.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 等宽两列的「标题—数值」行。
struct KeyValueRow: View {
    var title: String
    var value: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundColor(Ink.inkFaint)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundColor(tint ?? Ink.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// 快捷动作按钮：图标 + 标题，可带进度。
struct QuickActionButton: View {
    var title: String
    var symbol: String
    var tint: Color = Ink.indigo
    var filled: Bool = false
    var loading: Bool = false
    var action: () -> Void

    private var foreground: Color {
        filled ? Ink.paper : tint
    }

    private var background: Color {
        filled ? Ink.ink : tint.opacity(0.1)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 卡片里的小胶囊动作（复制 / 二维码 / 订阅）。
struct ChipButton: View {
    var title: String
    var symbol: String
    var active: Bool = false
    var tint: Color = Ink.indigo
    var action: () -> Void

    private var color: Color { active ? Ink.moss : tint }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.1)))
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

/// 空状态提示。
struct PanelHint: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Ink.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
    }
}

/// 加载中卡片。
struct PanelLoadingCard: View {
    var title: String = "正在读取面板数据"
    var note: String = "用的是网页同一套登录状态"

    var body: some View {
        InkCard {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Ink.ink)
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(Ink.inkFaint)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 读不到数据时的卡片，可重试 / 去登录 / 打开网页。
struct PanelErrorCard: View {
    var title: String = "读不到面板数据"
    var message: String
    var onRetry: () -> Void
    var onLogin: (() -> Void)?
    var onWeb: (() -> Void)?
    var retrying: Bool = false

    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Ink.cinnabar)
                    Text(title)
                        .font(Ink.serif(15, .semibold))
                        .foregroundColor(Ink.ink)
                    Spacer(minLength: 0)
                }

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button(action: onRetry) {
                        HStack(spacing: 5) {
                            if retrying {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Text("重试")
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundColor(Ink.indigo)
                    }

                    if let onLogin = onLogin {
                        Button(action: onLogin) {
                            HStack(spacing: 5) {
                                Image(systemName: "person.badge.key")
                                    .font(.system(size: 11, weight: .medium))
                                Text("登录面板")
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundColor(Ink.cinnabar)
                        }
                    }

                    if let onWeb = onWeb {
                        Button(action: onWeb) {
                            Text("原版网页")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(Ink.inkSoft)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }
}
