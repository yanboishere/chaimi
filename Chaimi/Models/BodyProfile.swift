import Foundation

// MARK: - 身体参数与营养计算

struct BodyProfile: Codable, Equatable {
    enum Sex: String, Codable, CaseIterable { case male, female
        var label: String { self == .male ? "男" : "女" }
    }
    enum Activity: Double, Codable, CaseIterable {
        case sedentary = 1.2, light = 1.375, moderate = 1.55, active = 1.725
        var label: String {
            switch self {
            case .sedentary: return "久坐(几乎不动)"
            case .light: return "轻度(每周1-3次运动)"
            case .moderate: return "中度(每周3-5次运动)"
            case .active: return "高强度(几乎每天运动)"
            }
        }
    }
    enum Goal: String, Codable, CaseIterable {
        case keep, loss300, loss500, gain300
        var label: String {
            switch self {
            case .keep: return "保持体重"
            case .loss300: return "温和减脂(-300千卡/天)"
            case .loss500: return "进取减脂(-500千卡/天)"
            case .gain300: return "增肌增重(+300千卡/天)"
            }
        }
        var delta: Double {
            switch self {
            case .keep: return 0
            case .loss300: return -300
            case .loss500: return -500
            case .gain300: return 300
            }
        }
    }

    var sex: Sex = .male
    var age: Int = 28
    var heightCm: Double = 172
    var weightKg: Double = 68
    var activity: Activity = .light
    var goal: Goal = .keep

    static func load(from json: String) -> BodyProfile {
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(BodyProfile.self, from: data) else { return BodyProfile() }
        return p
    }
    var json: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "{}"
    }

    var summaryText: String {
        "\(sex.label), \(age)岁, \(Int(heightCm))cm, \(String(format: "%.1f", weightKg))kg, 活动水平:\(activity.label), 目标:\(goal.label)"
    }
}

enum NutritionCalc {
    /// Mifflin-St Jeor 基础代谢
    static func bmr(_ p: BodyProfile) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        return p.sex == .male ? base + 5 : base - 161
    }
    static func tdee(_ p: BodyProfile) -> Double { bmr(p) * p.activity.rawValue }
    /// 推荐每日摄入(减脂目标下不低于 1200)
    static func suggestedCalories(_ p: BodyProfile) -> Double {
        max(1200, (tdee(p) + p.goal.delta).rounded())
    }
}

// MARK: - 平衡膳食宝塔(2022)对照

/// 《中国居民平衡膳食宝塔(2022)》成人每日建议量(克),数据来源见 README
struct PagodaRange: Identifiable {
    let group: FoodGroup
    let lo: Double
    let hi: Double
    var id: String { group.rawValue }
    var rangeText: String { group == .salt ? "<\(Int(hi))" : "\(Int(lo))–\(Int(hi))" }
}

enum Pagoda {
    static let ranges: [PagodaRange] = [
        .init(group: .grain, lo: 250, hi: 400),   // 谷类200-300 + 薯类50-100
        .init(group: .veg, lo: 300, hi: 500),
        .init(group: .fruit, lo: 200, hi: 350),
        .init(group: .meat, lo: 40, hi: 75),
        .init(group: .aquatic, lo: 40, hi: 75),
        .init(group: .egg, lo: 40, hi: 50),
        .init(group: .dairy, lo: 300, hi: 500),
        .init(group: .soynut, lo: 25, hi: 35),
        .init(group: .oil, lo: 25, hi: 30),
        .init(group: .salt, lo: 0, hi: 5),
    ]

    enum Verdict { case low, ok, high, none }

    static func verdict(group: FoodGroup, avgGrams: Double) -> Verdict {
        guard let r = ranges.first(where: { $0.group == group }) else { return .none }
        if avgGrams <= 0 { return .none }
        if group == .salt || group == .oil || group == .sugar {
            return avgGrams > r.hi ? .high : .ok
        }
        if avgGrams < r.lo * 0.8 { return .low }
        if avgGrams > r.hi * 1.3 { return .high }
        return .ok
    }

    /// 基于近一周分组摄入,输出离线建议(不依赖 API)
    static func advice(avgPerDay: [FoodGroup: Double], kcalAvg: Double, limit: Double?) -> [String] {
        var tips: [String] = []
        if let limit, limit > 0, kcalAvg > 0 {
            if kcalAvg > limit * 1.1 {
                tips.append("近一周平均摄入 \(Int(kcalAvg)) 千卡,超过目标 \(Int(limit)) 千卡约 \(Int((kcalAvg / limit - 1) * 100))%,建议减少高油高糖的菜和零食。")
            } else if kcalAvg < limit * 0.7 {
                tips.append("近一周平均摄入只有目标的 \(Int(kcalAvg / limit * 100))%,吃得偏少也不利于代谢,注意规律三餐。")
            } else {
                tips.append("近一周平均 \(Int(kcalAvg)) 千卡,和目标 \(Int(limit)) 千卡相符,保持得不错。")
            }
        }
        func avg(_ g: FoodGroup) -> Double { avgPerDay[g] ?? 0 }
        if verdict(group: .veg, avgGrams: avg(.veg)) == .low { tips.append("蔬菜偏少(建议每天 300–500 克),深色蔬菜最好占一半。") }
        if verdict(group: .fruit, avgGrams: avg(.fruit)) == .low { tips.append("水果偏少(建议每天 200–350 克),果汁不能代替鲜果。") }
        if verdict(group: .dairy, avgGrams: avg(.dairy)) == .low { tips.append("奶类不足(建议每天相当于 300–500 克液态奶),可以加一杯牛奶或酸奶。") }
        if verdict(group: .aquatic, avgGrams: avg(.aquatic)) == .low { tips.append("水产吃得少,膳食指南建议每周至少吃 2 次水产品。") }
        let meatAvg = avg(.meat)
        if verdict(group: .meat, avgGrams: meatAvg) == .high { tips.append("畜禽肉偏多(建议每天 40–75 克),可以用鱼虾、豆制品替换一部分红肉。") }
        if verdict(group: .soynut, avgGrams: avg(.soynut)) == .low { tips.append("大豆/坚果不足(建议每天 25–35 克),豆腐豆浆是好来源。") }
        if verdict(group: .oil, avgGrams: avg(.oil)) == .high { tips.append("烹调油偏多(建议每天 25–30 克),多用蒸煮凉拌,少油炸。") }
        if tips.isEmpty { tips.append("记录还不多,先把吃过的饭菜记下来,积累一周数据后这里会给出对照建议。") }
        tips.append("提示:建议值来自《中国居民平衡膳食宝塔(2022)》,按一段时间的平均值看即可,不必每天严格达标。")
        return tips
    }
}
