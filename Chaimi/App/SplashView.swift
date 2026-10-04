import SwiftUI

/// 开屏动画:三样食材从天而降落进一行,标题手写浮现,整体 ~2 秒,点击可跳过
struct SplashView: View {
    var onDone: () -> Void

    private let icons = ["food_fanqie", "food_xiaobaicai", "food_huluobo"]
    @State private var dropped = [false, false, false]
    @State private var showTitle = false
    @State private var wobble = false

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 26) {
                HStack(spacing: 22) {
                    ForEach(icons.indices, id: \.self) { i in
                        Image(icons[i])
                            .resizable().scaledToFit()
                            .frame(width: 76, height: 76)
                            .rotationEffect(.degrees(dropped[i] ? (wobble ? -4 : 4) : -24))
                            .offset(y: dropped[i] ? 0 : -420)
                            .opacity(dropped[i] ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.58).delay(Double(i) * 0.13), value: dropped[i])
                            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: wobble)
                    }
                }
                VStack(spacing: 8) {
                    Text("柴米")
                        .font(.hand(52))
                        .foregroundStyle(Color.ink)
                    Text("柴米油盐,先管柴米")
                        .font(.hand(16))
                        .foregroundStyle(Color.ink.opacity(0.6))
                }
                .scaleEffect(showTitle ? 1 : 0.8)
                .opacity(showTitle ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: showTitle)
            }
            .offset(y: -20)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .task {
            for i in icons.indices { dropped[i] = true }
            wobble = true
            try? await Task.sleep(for: .milliseconds(520))
            showTitle = true
            try? await Task.sleep(for: .milliseconds(1500))
            onDone()
        }
    }
}
