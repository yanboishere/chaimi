import Foundation

// MARK: - 本地菜谱推荐引擎

struct RecipeRecommendation: Identifiable {
    let recipe: LocalRecipe
    /// 必备主料中有多少在库
    let haveCount: Int
    let needCount: Int
    let missingIngredients: [String]
    let missingSeasonings: [String]
    /// 用到了哪些临期/过期食材(名称)
    let usesExpiring: [String]
    let score: Double
    var id: String { recipe.id }

    var coverageText: String {
        if needCount == 0 { return "随时可做" }
        if missingIngredients.isEmpty { return "食材齐全" }
        return "缺 \(missingIngredients.count) 样:\(missingIngredients.prefix(3).joined(separator: "、"))\(missingIngredients.count > 3 ? "…" : "")"
    }
}

enum RecipeRecommender {

    /// pantry: catalogId → 是否临期(含过期)
    static func recommend(pantryIds: [String: Bool], cuisine: String? = nil, limit: Int = 30) -> [RecipeRecommendation] {
        let book = RecipeBook.shared
        var out: [RecipeRecommendation] = []
        for recipe in book.recipes {
            if let cuisine, recipe.cui != cuisine { continue }
            let required = recipe.ing.filter { !$0.isOptional }
            var have = 0
            var missing: [String] = []
            var expiringUsed: [String] = []
            for ingredient in required {
                if let expiring = pantryIds[ingredient.id] {
                    have += 1
                    if expiring { expiringUsed.append(ingredient.displayName) }
                } else {
                    missing.append(ingredient.displayName)
                }
            }
            // 可选食材在库也加一点分/标临期
            for ingredient in recipe.ing where ingredient.isOptional {
                if pantryIds[ingredient.id] == true { expiringUsed.append(ingredient.displayName) }
            }
            var missingSea: [String] = []
            for s in recipe.sea {
                if pantryIds[s] == nil {
                    missingSea.append(Catalog.shared.byId[s]?.name ?? s)
                }
            }
            let need = required.count
            let coverage = need == 0 ? 1 : Double(have) / Double(need)
            // 没有任何主料在库的菜意义不大
            if have == 0 && need > 0 { continue }
            var score = coverage * 100
            score += Double(expiringUsed.count) * 24          // 优先消耗临期
            score -= Double(missing.count) * 9
            score -= Double(missingSea.count) * 2
            if missing.isEmpty { score += 18 }
            out.append(RecipeRecommendation(
                recipe: recipe, haveCount: have, needCount: need,
                missingIngredients: missing, missingSeasonings: missingSea,
                usesExpiring: Array(Set(expiringUsed)), score: score
            ))
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(limit))
    }
}
