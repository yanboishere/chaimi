import Foundation

/// 老虎机抽菜引擎:纯逻辑,可单测。
/// 三个转轮 = 蔬菜 / 荤(蛋白) / 调料;落点由抽中的菜谱反推。
enum SlotEngine {

    // MARK: 转轮素材池(优先用库存,不够用目录兜底)

    static func pools(pantryCatalogIds: Set<String>) -> (veg: [CatalogItem], protein: [CatalogItem], seasoning: [CatalogItem]) {
        let all = Catalog.shared.items
        func pool(_ belongs: (CatalogItem) -> Bool) -> [CatalogItem] {
            let inPantry = all.filter { belongs($0) && pantryCatalogIds.contains($0.id) }
            let base = inPantry.count >= 4 ? inPantry : all.filter(belongs)
            return base.shuffled()
        }
        let veg = pool { $0.cat == "veg" || $0.cat == "mushroom" }
        let protein = pool { $0.cat == "meat" || $0.cat == "seafood" || $0.cat == "bean" }
        let seasoning = pool { $0.cat == "condiment" }
        return (veg, protein, seasoning)
    }

    // MARK: 由菜谱反推三个落点

    static func reelTargets(for recipe: LocalRecipe) -> (veg: CatalogItem, protein: CatalogItem, seasoning: CatalogItem) {
        let items = recipe.ing.compactMap(\.catalogItem)
        let veg = items.first { $0.cat == "veg" || $0.cat == "mushroom" }
            ?? items.first { $0.grp == .veg || $0.grp == .fruit }
            ?? Catalog.shared.byId["xiaobaicai"]!
        let protein = items.first { $0.cat == "meat" || $0.cat == "seafood" }
            ?? items.first { $0.cat == "bean" || $0.grp == .egg }
            ?? Catalog.shared.byId["jidan"]!
        // 调料优先挑有记忆点的,别总是落在盐和油上
        let basics: Set<String> = ["yan", "shiyongyou", "baitang", "dianfen", "liaojiu", "jijing"]
        let seaItems = recipe.sea.compactMap { Catalog.shared.byId[$0] }
        let seasoning = seaItems.first { !basics.contains($0.id) }
            ?? seaItems.first
            ?? Catalog.shared.byId["yan"]!
        return (veg, protein, seasoning)
    }

    // MARK: 加权抽一道菜

    /// - Parameters:
    ///   - type: 菜式筛选,nil 为不限
    ///   - pantryIds: 在库 catalogId
    ///   - urgentIds: 临期/过期 catalogId(加权优先消耗)
    ///   - excluding: 上一次的结果,避免连抽重复
    ///   - onlyInStock: 「不用买菜」模式——只要非可选主料全在库的菜(调料不作硬性要求)
    static func pick(type: DishType?, pantryIds: Set<String>, urgentIds: Set<String>,
                     excluding: String? = nil,
                     onlyInStock: Bool = false,
                     recipes: [LocalRecipe] = RecipeBook.shared.recipes) -> LocalRecipe? {
        var candidates = recipes.filter { type == nil || $0.dishTypes.contains(type!) }
        if onlyInStock {
            candidates = candidates.filter { recipe in
                recipe.ing.allSatisfy { $0.isOptional || pantryIds.contains($0.id) }
            }
        }
        if candidates.isEmpty { return nil }
        if candidates.count > 1, let excluding {
            candidates.removeAll { $0.id == excluding }
        }
        let weighted: [(LocalRecipe, Double)] = candidates.map { recipe in
            let required = recipe.ing.filter { !$0.isOptional }
            let missing = required.filter { !pantryIds.contains($0.id) }.count
            var weight = 1.0
            if required.isEmpty || missing == 0 { weight = 5 }
            else if missing == 1 { weight = 2.5 }
            if recipe.ing.contains(where: { urgentIds.contains($0.id) }) { weight *= 2 }
            return (recipe, weight)
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total)
        for (recipe, weight) in weighted {
            roll -= weight
            if roll < 0 { return recipe }
        }
        return weighted.last?.0
    }
}
