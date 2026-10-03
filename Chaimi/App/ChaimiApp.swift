import SwiftUI
import SwiftData

@main
struct ChaimiApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: PantryItem.self, CalorieEntry.self)
        } catch {
            fatalError("SwiftData 初始化失败: \(error)")
        }
        // 截图/演示模式:跳过首启弹窗,库存为空时自动填入示例数据
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            UserDefaults.standard.set(true, forKey: "didOfferSampleData")
            let context = ModelContext(container)
            let count = (try? context.fetchCount(FetchDescriptor<PantryItem>())) ?? 0
            if count == 0 { SampleData.seed(into: context) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Color.accentColor)
                .fontDesign(.rounded)
        }
        .modelContainer(container)
    }
}

// MARK: - 示例数据

enum SampleData {
    /// 插入一批演示库存(包含临期/过期各一两条,便于看到动画)+ 一周卡路里记录
    @MainActor
    static func seed(into context: ModelContext) {
        let cal = Calendar.current
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: .now)! }

        let rows: [(String, Double, Int?)] = [ // (catalogId, qty, 距今天的到期偏移;nil=按默认)
            ("fanqie", 4, nil), ("huanggua", 3, nil), ("tudou", 5, nil), ("xilanhua", 1, nil),
            ("bocai", 1, 1),            // 明天到期 → 临期动画
            ("nendoufu", 1, 0),         // 今天到期
            ("niunai", 1, -2),          // 已过期 → 腐烂动画
            ("jidan", 10, nil), ("wuhuarou", 500, 2), ("jitui", 4, nil), ("jiweixia", 400, -1),
            ("dami", 1, nil), ("guamian", 2, nil), ("shiyongyou", 1, nil), ("yan", 1, nil),
            ("shengchou", 1, nil), ("laochou", 1, nil), ("xiangcu", 1, nil), ("haoyou", 1, nil),
            ("doubanjiang", 1, nil), ("huajiao", 1, nil), ("ganlajiao", 1, nil), ("baitang", 1, nil),
            ("dianfen", 1, nil), ("liaojiu", 1, nil), ("jiang", 2, nil), ("dasuan", 3, nil),
            ("xiaocong", 1, 2), ("dacong", 2, nil), ("qingjiao", 3, nil), ("xianggu", 250, nil),
            ("suannai", 4, nil), ("shupian", 1, nil), ("kele", 4, nil), ("meirijianguo", 1, nil),
            ("pingguo", 4, nil), ("xiangjiao", 5, 1),
        ]
        for (id, qty, expiryOffset) in rows {
            guard let item = Catalog.shared.byId[id] else { continue }
            let expiry: Date?
            if let offset = expiryOffset {
                expiry = cal.startOfDay(for: day(offset))
            } else {
                expiry = PantryItem.defaultExpiry(for: item, storage: item.st)
            }
            context.insert(PantryItem(
                catalogId: id, name: item.name, unit: item.unit, quantity: qty,
                storage: item.st, addedAt: day(-1), expiryDate: expiry
            ))
        }

        // 最近一周的卡路里记录,让图表有内容
        let meals: [(Int, String, Double, String, [FoodGroup: Double])] = [
            (-6, "番茄炒蛋 + 米饭", 650, "recipe", [.veg: 180, .egg: 100, .grain: 150, .oil: 15]),
            (-6, "拿铁", 180, "manual", [.dairy: 200]),
            (-5, "麻婆豆腐盖饭", 780, "recipe", [.soynut: 200, .meat: 50, .grain: 200, .oil: 20]),
            (-5, "薯片", 270, "snack", [:]),
            (-4, "清蒸鲈鱼 + 两碗饭", 820, "recipe", [.aquatic: 160, .grain: 300, .oil: 10]),
            (-3, "可乐鸡翅 + 米饭", 900, "recipe", [.meat: 180, .grain: 200, .sugar: 20, .oil: 15]),
            (-3, "酸奶", 90, "snack", [.dairy: 120]),
            (-2, "外卖黄焖鸡", 950, "manual", [.meat: 150, .grain: 250, .oil: 30]),
            (-1, "蒜蓉西兰花 + 鸡胸肉", 520, "recipe", [.veg: 260, .meat: 150, .oil: 12]),
            (-1, "每日坚果", 170, "snack", [.soynut: 28]),
            (0, "皮蛋瘦肉粥", 320, "recipe", [.grain: 120, .meat: 40, .egg: 30]),
        ]
        for (offset, name, kcal, source, groups) in meals {
            let date = cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: day(offset)))!
            context.insert(CalorieEntry(date: date, name: name, kcal: kcal, source: source, groupGrams: groups))
        }
        try? context.save()
    }

    @MainActor
    static func clearPantry(_ context: ModelContext) {
        try? context.delete(model: PantryItem.self)
        try? context.save()
    }

    @MainActor
    static func clearCalories(_ context: ModelContext) {
        try? context.delete(model: CalorieEntry.self)
        try? context.save()
    }
}
