import SwiftUI

struct HomeView: View {
    let openInitialListen: () -> Void

    var body: some View {
        ZStack {
            HomeTheme.paper2
                .ignoresSafeArea()

            GridTexture()
                .opacity(0.6)
                .allowsHitTesting(false)

            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Text("A LISTENING PRACTICE PLATFORM")
                        .font(.system(size: 12, design: .monospaced))
                        .tracking(1.68)
                        .foregroundColor(HomeTheme.ink3)

                    Text("OwlListen")
                        .font(.system(size: 46, weight: .regular, design: .serif))
                        .tracking(-0.5)
                        .foregroundColor(HomeTheme.ink1)
                }

                HStack(alignment: .top, spacing: 20) {
                    ModeCard(
                        badge: "第一步 · 标注",
                        badgeColor: .blue,
                        title: "初次精听",
                        description: "连续听，把没跟上的句子在波形上拖拽框选，选中即自动回环反复攻克；难句攒成错题包，导出带 Whisper 原文的 ZIP。",
                        accentColor: HomeTheme.brand,
                        features: [
                            "拖拽框选断句",
                            "选中即自动回环",
                            "片段备注",
                            "导出 ZIP 错题包",
                        ],
                        action: openInitialListen
                    )

                    ModeCard(
                        badge: "第二步 · 复习",
                        badgeColor: .green,
                        title: "精听复习",
                        description: "导入错题包，逐句反复听写，Diff 对照原文查漏补缺，没攻克的句子随手标记重听。",
                        accentColor: HomeTheme.success,
                        features: [
                            "逐句听写",
                            "原文 Diff 对照",
                            "标记重听",
                            "全键盘操作",
                        ],
                        action: {}
                    )

                    ModeCard(
                        badge: "日常 · 泛听",
                        badgeColor: .blue,
                        title: "听有声书",
                        description: "打开 M4B 有声书，自动解析章节、变速播放、进度自动续读，用作精听之外的大量泛听输入。",
                        accentColor: HomeTheme.audiobook,
                        features: [
                            "自动解析章节",
                            "0.5×～1.75× 变速",
                            "进度自动续读",
                            "支持 M4B",
                        ],
                        action: {}
                    )
                }
                .frame(width: 1020)
            }
        }
    }
}

private struct ModeCard: View {
    enum BadgeColor {
        case blue
        case green
    }

    let badge: String
    let badgeColor: BadgeColor
    let title: String
    let description: String
    let accentColor: Color
    let features: [String]
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                BadgeView(text: badge, color: badgeColor)
                    .padding(.bottom, 12)

                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(accentColor)
                    .padding(.bottom, 10)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(HomeTheme.ink3)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accentColor.opacity(0.7))
                                .frame(width: 5, height: 5)
                            Text(feature)
                                .font(.system(size: 12))
                                .foregroundColor(HomeTheme.ink2)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 28)
            .padding(.trailing, 26)
            .padding(.bottom, 24)
            .padding(.leading, 32)
            .frame(width: 326.67, height: 300, alignment: .topLeading)
            .background(HomeTheme.paper)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 4)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("→")
                    .font(.system(size: 20))
                    .foregroundColor(hovered ? accentColor : HomeTheme.border2)
                    .padding(.trailing, 20)
                    .padding(.bottom, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        hovered ? accentColor.opacity(0.4) : HomeTheme.border2,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: hovered ? accentColor.opacity(0.09) : HomeTheme.ink1.opacity(0.06),
                radius: hovered ? 16 : 10,
                y: hovered ? 8 : 4
            )
            .offset(y: hovered ? -2 : 0)
            .animation(.easeOut(duration: 0.2), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct BadgeView: View {
    let text: String
    let color: ModeCard.BadgeColor

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .tracking(1)
            .foregroundColor(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var foreground: Color {
        color == .blue ? HomeTheme.brand : HomeTheme.success
    }

    private var background: Color {
        color == .blue ? HomeTheme.brandSoft : HomeTheme.successSoft
    }
}

private struct GridTexture: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += 40
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 40
            }
            context.stroke(path, with: .color(HomeTheme.border), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

private enum HomeTheme {
    static let paper = Color(red: 0.98, green: 0.98, blue: 0.969)
    static let paper2 = Color(red: 0.957, green: 0.953, blue: 0.933)
    static let ink1 = Color(red: 0.102, green: 0.153, blue: 0.267)
    static let ink2 = Color(red: 0.239, green: 0.31, blue: 0.431)
    static let ink3 = Color(red: 0.518, green: 0.573, blue: 0.667)
    static let brand = Color(red: 0.102, green: 0.306, blue: 0.847)
    static let brandSoft = Color(red: 0.91, green: 0.933, blue: 0.98)
    static let success = Color(red: 0.086, green: 0.396, blue: 0.204)
    static let successSoft = Color(red: 0.863, green: 0.988, blue: 0.906)
    static let audiobook = Color(red: 0.976, green: 0.451, blue: 0.086)
    static let border = ink1.opacity(0.09)
    static let border2 = ink1.opacity(0.16)
}
