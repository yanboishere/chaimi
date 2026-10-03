import Foundation

// MARK: - 基础枚举

enum StorageKind: String, Codable, CaseIterable, Identifiable {
    case fridge, pantry, freezer
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fridge: return "冷藏"
        case .pantry: return "常温"
        case .freezer: return "冷冻"
        }
    }
    var emoji: String {
        switch self {
        case .fridge: return "🧊"
        case .pantry: return "🧺"
        case .freezer: return "❄️"
        }
    }
}

/// 《中国居民平衡膳食宝塔(2022)》食物分组
enum FoodGroup: String, Codable, CaseIterable {
    case grain, veg, fruit, meat, aquatic, egg, dairy, soynut, oil, salt, sugar, other
    var label: String {
        switch self {
        case .grain: return "谷薯类"
        case .veg: return "蔬菜"
        case .fruit: return "水果"
        case .meat: return "畜禽肉"
        case .aquatic: return "水产"
        case .egg: return "蛋类"
        case .dairy: return "奶类"
        case .soynut: return "大豆坚果"
        case .oil: return "油脂"
        case .salt: return "盐"
        case .sugar: return "添加糖"
        case .other: return "其他"
        }
    }
}

// MARK: - 目录数据

struct CatalogCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let order: Int
}

struct CatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let al: [String]
    let cat: String
    let unit: String
    let qty: Double
    let st: StorageKind
    let life: [String: Int]
    let kcal: Double
    let grp: FoodGroup

    enum CodingKeys: String, CodingKey { case id, name, al, cat, unit, qty, st, life, kcal, grp }

    var imageName: String { "food_\(id)" }
    var aliasesIncludingName: [String] { [name] + al }
    func shelfLifeDays(for storage: StorageKind) -> Int? { life[storage.rawValue] }
    /// 首选存放方式下的保质天数
    var defaultShelfLifeDays: Int? { shelfLifeDays(for: st) }
}

struct CatalogFile: Codable {
    let categories: [CatalogCategory]
    let items: [CatalogItem]
}

final class Catalog {
    static let shared = Catalog()

    let categories: [CatalogCategory]
    let items: [CatalogItem]
    let byId: [String: CatalogItem]
    /// (规范化别名, 条目) 按别名长度降序,供小票匹配用
    let normalizedAliases: [(alias: String, item: CatalogItem)]

    private init() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else {
            categories = []; items = []; byId = [:]; normalizedAliases = []
            assertionFailure("catalog.json 加载失败")
            return
        }
        categories = file.categories.sorted { $0.order < $1.order }
        items = file.items
        byId = Dictionary(uniqueKeysWithValues: file.items.map { ($0.id, $0) })
        var pairs: [(String, CatalogItem)] = []
        for item in file.items {
            for alias in item.aliasesIncludingName {
                let n = Catalog.normalize(alias)
                if n.count >= 2 { pairs.append((n, item)) }
            }
        }
        normalizedAliases = pairs.sorted { $0.0.count > $1.0.count }
    }

    func items(in category: String) -> [CatalogItem] { items.filter { $0.cat == category } }

    func category(id: String) -> CatalogCategory? { categories.first { $0.id == id } }

    /// 去掉空格、数字、规格词,便于小票行与别名做包含匹配
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let stripped = lowered.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.decimalDigits.contains($0) }
        var t = String(String.UnicodeScalarView(stripped))
        for word in ["新鲜", "精品", "有机", "散装", "袋装", "盒装", "特价", "促销", "进口", "国产", "冷冻", "冰鲜", "优选", "甄选", "家庭装", "大包装"] {
            t = t.replacingOccurrences(of: word, with: "")
        }
        for unit in ["kg", "ml", "g", "l", "克", "千克", "毫升", "升", "枚装", "根装", "只装", "个装", "斤"] {
            t = t.replacingOccurrences(of: unit, with: "")
        }
        return t
    }

    /// 在一行文本里找最匹配的目录条目(最长别名优先)
    func match(line: String) -> CatalogItem? {
        let n = Catalog.normalize(line)
        guard n.count >= 2 else { return nil }
        for (alias, item) in normalizedAliases where n.contains(alias) {
            return item
        }
        return nil
    }
}
