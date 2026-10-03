import SwiftUI

// MARK: - 手绘主题

extension Font {
    /// 站酷快乐体(OFL 许可),整个 App 的手写体
    static func hand(_ size: CGFloat) -> Font { .custom("ZCOOLKuaiLe-Regular", size: size) }
}

extension Color {
    static let paper = Color("PaperBackground")
    static let paperCard = Color("PaperCard")
    static let ink = Color("InkPrimary")
    static let tomatoRed = Color(red: 0.74, green: 0.28, blue: 0.29)
    static let leafGreen = Color(red: 0.42, green: 0.60, blue: 0.31)
    static let warnOrange = Color(red: 0.88, green: 0.48, blue: 0.25)
}

/// 纸面背景(带少量斑点肌理)
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Color.paper
            Canvas { ctx, size in
                var seed: UInt64 = 88172645463325252
                func rnd() -> CGFloat {
                    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                    return CGFloat(seed % 10_000) / 10_000
                }
                for _ in 0..<140 {
                    let r = rnd() * 1.6 + 0.4
                    let rect = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: r, height: r)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color.ink.opacity(0.05)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 手绘卡片:米白底 + 不太整齐的描边
struct DoodleCard: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.paperCard)
                        .shadow(color: Color.ink.opacity(0.10), radius: 2.5, x: 1, y: 2)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1.6, dash: [10, 3, 5, 2]))
                        .rotationEffect(.degrees(0.15))
                }
            )
    }
}

extension View {
    func doodleCard(padding: CGFloat = 12) -> some View { modifier(DoodleCard(padding: padding)) }
}

/// 库存食材图标:新鲜原样;临期加弹跳 ⚠️;过期整体黑灰 + 霉斑 + 苍蝇绕圈动画
struct FoodIconView: View {
    let imageName: String?
    let freshness: PantryItem.Freshness
    var size: CGFloat = 72

    @State private var animate = false

    private var isExpired: Bool { if case .expired = freshness { return true }; return false }
    private var isExpiring: Bool { if case .expiring = freshness { return true }; return false }

    var body: some View {
        ZStack {
            iconImage
                .saturation(isExpired ? 0.08 : 1)
                .brightness(isExpired ? -0.1 : 0)
                .opacity(isExpired ? 0.8 : 1)

            if isExpired {
                // 霉斑
                moldSpot(x: -0.18, y: -0.12, s: 0.30, color: .init(red: 0.45, green: 0.52, blue: 0.30))
                moldSpot(x: 0.22, y: 0.10, s: 0.22, color: .init(red: 0.38, green: 0.45, blue: 0.28))
                moldSpot(x: -0.05, y: 0.26, s: 0.16, color: .init(red: 0.50, green: 0.55, blue: 0.34))
                // 绕圈的小苍蝇
                Text("🪰")
                    .font(.system(size: size * 0.26))
                    .offset(x: cos(animate ? .pi * 2 : 0) * size * 0.42,
                            y: sin(animate ? .pi * 2 : 0) * size * 0.30 - size * 0.30)
                    .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: animate)
                Text("❗️")
                    .font(.system(size: size * 0.30))
                    .offset(x: size * 0.34, y: -size * 0.34)
            } else if isExpiring {
                Text("⚠️")
                    .font(.system(size: size * 0.32))
                    .scaleEffect(animate ? 1.22 : 0.92)
                    .rotationEffect(.degrees(animate ? 8 : -8))
                    .offset(x: size * 0.34, y: -size * 0.36 + (animate ? -3 : 1))
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: animate)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate = true }
    }

    @ViewBuilder private var iconImage: some View {
        if let imageName, UIImage(named: imageName) != nil {
            Image(imageName).resizable().scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2).fill(Color.ink.opacity(0.08))
                Text("🥡").font(.system(size: size * 0.5))
            }
        }
    }

    private func moldSpot(x: CGFloat, y: CGFloat, s: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color.opacity(animate ? 0.62 : 0.45))
            .frame(width: size * s, height: size * s)
            .blur(radius: 1.2)
            .overlay(
                Circle().fill(Color.white.opacity(0.35)).frame(width: size * s * 0.3)
                    .offset(x: -size * s * 0.15, y: -size * s * 0.15)
            )
            .offset(x: size * x, y: size * y)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: animate)
    }
}

/// 小圆角标签
struct TagChip: View {
    let text: String
    var color: Color = .ink
    var filled: Bool = false
    var body: some View {
        Text(text)
            .font(.hand(13))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                Capsule().fill(filled ? color.opacity(0.16) : .clear)
                    .overlay(Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1.2))
            )
            .foregroundStyle(color)
    }
}

/// 手写风分段选择
struct HandPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.snappy) { selection = value }
                } label: {
                    Text(label)
                        .font(.hand(15))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(selection == value ? Color.accentColor.opacity(0.18) : Color.paperCard)
                                .overlay(Capsule().strokeBorder(selection == value ? Color.accentColor : Color.ink.opacity(0.3), lineWidth: 1.4))
                        )
                        .foregroundStyle(selection == value ? Color.accentColor : Color.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
