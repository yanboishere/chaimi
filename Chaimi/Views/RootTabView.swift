import SwiftUI
import SwiftData

struct RootTabView: View {
    @AppStorage("didOfferSampleData") private var didOfferSampleData = false
    @Environment(\.modelContext) private var context
    @State private var selection: Int = DemoLaunch.initialTab

    var body: some View {
        TabView(selection: $selection) {
            PantryListView()
                .tabItem { Label("库存", systemImage: "basket.fill") }
                .tag(0)
            RecipeHomeView()
                .tabItem { Label("菜谱", systemImage: "frying.pan.fill") }
                .tag(1)
            CalorieView()
                .tabItem { Label("记录", systemImage: "chart.bar.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .sheet(isPresented: Binding(get: { !didOfferSampleData && !DemoLaunch.isDemo }, set: { _ in didOfferSampleData = true })) {
            WelcomeSheet { wantsSample in
                if wantsSample { SampleData.seed(into: context) }
                didOfferSampleData = true
            }
            .interactiveDismissDisabled()
        }
    }
}

/// 截图/演示用的启动参数:-demoTab N 选 Tab,-demoData 预填示例数据,-demoScan 自动打开小票识别
enum DemoLaunch {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demoData") }
    static var wantsScan: Bool { ProcessInfo.processInfo.arguments.contains("-demoScan") }
    static var initialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }
}

private struct WelcomeSheet: View {
    let onChoice: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 18) {
                Spacer()
                HStack(spacing: 14) {
                    ForEach(["food_fanqie", "food_wuhuarou", "food_doubanjiang", "food_luyu"], id: \.self) {
                        Image($0).resizable().scaledToFit().frame(width: 58, height: 58)
                    }
                }
                Text("柴米")
                    .font(.hand(44))
                    .foregroundStyle(Color.ink)
                Text("管好家里的菜、肉和调料\n扫小票入库 · 快过期提醒 · 看库存推荐菜谱")
                    .font(.hand(17))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink.opacity(0.75))
                Spacer()
                Button {
                    onChoice(true); dismiss()
                } label: {
                    Text("放一批示例食材,先逛逛")
                        .font(.hand(18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    onChoice(false); dismiss()
                } label: {
                    Text("从空库存开始")
                        .font(.hand(16))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [PantryItem.self, CalorieEntry.self], inMemory: true)
}
