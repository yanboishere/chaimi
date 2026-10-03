import Foundation
import SwiftData

@Model
final class CalorieEntry {
    var date: Date
    var name: String
    var kcal: Double
    /// recipe / snack / manual / ai
    var source: String
    /// 各宝塔分组的克数,JSON 编码
    var groupGramsJSON: String

    init(date: Date = .now, name: String, kcal: Double, source: String, groupGrams: [FoodGroup: Double] = [:]) {
        self.date = date
        self.name = name
        self.kcal = kcal
        self.source = source
        let raw = Dictionary(uniqueKeysWithValues: groupGrams.map { ($0.key.rawValue, $0.value) })
        self.groupGramsJSON = (try? String(data: JSONEncoder().encode(raw), encoding: .utf8)) ?? "{}"
        if self.groupGramsJSON.isEmpty { self.groupGramsJSON = "{}" }
    }

    var groupGrams: [FoodGroup: Double] {
        guard let data = groupGramsJSON.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        var out: [FoodGroup: Double] = [:]
        for (k, v) in raw { if let g = FoodGroup(rawValue: k) { out[g] = v } }
        return out
    }

    var sourceLabel: String {
        switch source {
        case "recipe": return "做饭"
        case "snack": return "零食"
        case "ai": return "AI 菜谱"
        default: return "手动"
        }
    }
}
