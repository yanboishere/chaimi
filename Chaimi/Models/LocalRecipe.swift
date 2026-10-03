import Foundation

// MARK: - 内置菜谱库

struct Cuisine: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct RecipeIngredient: Codable, Hashable {
    let id: String
    let q: String
    var opt: Bool? = nil
    var isOptional: Bool { opt ?? false }
    var catalogItem: CatalogItem? { Catalog.shared.byId[id] }
    var displayName: String { catalogItem?.name ?? id }
}

struct LocalRecipe: Codable, Identifiable, Hashable {
    struct Icon: Codable, Hashable { let t: String; let c: String }
    let id: String
    let name: String
    let cui: String
    let icon: Icon
    let time: Int
    let serves: Int
    let kcal: Double
    let tags: [String]
    let ing: [RecipeIngredient]
    let sea: [String]
    let steps: [String]

    var imageName: String { "recipe_\(id)" }
    var cuisineName: String { RecipeBook.shared.cuisineName(cui) }
    var kcalPerServing: Double { kcal }

    /// 估算整道菜各宝塔分组的生重克数(按主料规格粗估)
    var groupGrams: [FoodGroup: Double] {
        var out: [FoodGroup: Double] = [:]
        for i in ing {
            guard let item = i.catalogItem else { continue }
            let grams = LocalRecipe.estimateGrams(quantityText: i.q, item: item)
            out[item.grp, default: 0] += grams
        }
        return out
    }

    static func estimateGrams(quantityText: String, item: CatalogItem) -> Double {
        // "400克" / "250g" 直接取数;其余按常见单位粗估
        let digits = quantityText.prefix { "0123456789.".contains($0) }
        let value = Double(digits) ?? 1
        if quantityText.contains("克") || quantityText.lowercased().contains("g") { return value }
        switch item.unit {
        case "个", "根", "只", "块": return value * 120
        case "把", "颗", "袋", "盒": return value * 250
        case "杯": return value * 150
        default: return 100
        }
    }
}

struct RecipeFile: Codable {
    let cuisines: [Cuisine]
    let recipes: [LocalRecipe]
}

final class RecipeBook {
    static let shared = RecipeBook()
    let cuisines: [Cuisine]
    let recipes: [LocalRecipe]
    private let cuisineById: [String: Cuisine]

    private init() {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RecipeFile.self, from: data) else {
            cuisines = []; recipes = []; cuisineById = [:]
            assertionFailure("recipes.json 加载失败")
            return
        }
        cuisines = file.cuisines
        recipes = file.recipes
        cuisineById = Dictionary(uniqueKeysWithValues: file.cuisines.map { ($0.id, $0) })
    }

    func cuisineName(_ id: String) -> String { cuisineById[id]?.name ?? id }
}
