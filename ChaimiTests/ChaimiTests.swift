import XCTest
@testable import Chaimi

final class ChaimiTests: XCTestCase {

    // MARK: 目录完整性

    func testHandFontRegistered() {
        let zcoolFamilies = UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains("zcool") || $0.contains("快乐") }
        let font = UIFont(name: "ZCOOLKuaiLe-Regular", size: 14)
        XCTAssertNotNil(font, "手写字体未注册;已注册的相关 family: \(zcoolFamilies), 全部: \(UIFont.familyNames.sorted().prefix(80))")
    }

    func testCatalogLoads() {
        XCTAssertGreaterThan(Catalog.shared.items.count, 150, "目录应有 150+ 条")
        XCTAssertEqual(Catalog.shared.categories.count, 11)
    }

    func testCatalogIdsUnique() {
        let ids = Catalog.shared.items.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "目录 id 不能重复")
    }

    func testCatalogCategoriesValid() {
        let catIds = Set(Catalog.shared.categories.map(\.id))
        for item in Catalog.shared.items {
            XCTAssertTrue(catIds.contains(item.cat), "\(item.id) 的分类 \(item.cat) 不存在")
        }
    }

    func testEveryCatalogItemHasIcon() {
        for item in Catalog.shared.items {
            XCTAssertNotNil(UIImage(named: item.imageName), "缺少图标资源 \(item.imageName)")
        }
    }

    // MARK: 菜谱引用

    func testRecipeIngredientsResolve() {
        for recipe in RecipeBook.shared.recipes {
            for ing in recipe.ing {
                XCTAssertNotNil(Catalog.shared.byId[ing.id], "菜谱 \(recipe.id) 的主料 \(ing.id) 不在目录里")
            }
            for s in recipe.sea {
                XCTAssertNotNil(Catalog.shared.byId[s], "菜谱 \(recipe.id) 的调料 \(s) 不在目录里")
            }
            XCTAssertNotNil(UIImage(named: recipe.imageName), "缺少菜谱图标 \(recipe.imageName)")
            XCTAssertFalse(recipe.steps.isEmpty)
        }
        XCTAssertGreaterThanOrEqual(RecipeBook.shared.recipes.count, 40)
    }

    // MARK: 小票解析

    func testReceiptParserMatchesSampleLines() {
        let lines = [
            "盒马鲜生 望京店",
            "2026-10-03 18:42  收银:0038",
            "普罗旺斯番茄 450g 8.90",
            "黄瓜 3根装 6.50",
            "精品五花肉 500g 29.80",
            "内酯豆腐 350g 3.50",
            "金龙鱼玉米油 1.8L 35.90",
            "青线椒 250g 5.80",
            "可生食鸡蛋 10枚 15.90",
            "环保购物袋 1.00",
            "合计 13 件 165.80",
        ]
        let rows = ReceiptParser.parse(lines: lines)
        let matchedIds = Set(rows.compactMap { $0.item?.id })
        XCTAssertTrue(matchedIds.contains("fanqie"), "番茄应匹配")
        XCTAssertTrue(matchedIds.contains("huanggua"))
        XCTAssertTrue(matchedIds.contains("wuhuarou"))
        XCTAssertTrue(matchedIds.contains("nendoufu"))
        XCTAssertTrue(matchedIds.contains("shiyongyou"), "玉米油应该通过别名匹配到食用油")
        XCTAssertTrue(matchedIds.contains("xianjiao"))
        XCTAssertTrue(matchedIds.contains("jidan"))
        // 杂项行不应出现
        XCTAssertFalse(rows.contains { $0.raw.contains("合计") })
        XCTAssertFalse(rows.contains { $0.raw.contains("购物袋") })
        XCTAssertFalse(rows.contains { $0.raw.contains("收银") })
    }

    func testQuantityExtraction() {
        let q1 = ReceiptParser.extractQuantity("黄瓜 3根装", fallbackUnit: "根")
        XCTAssertEqual(q1?.qty, 3)
        XCTAssertEqual(q1?.unit, "根")
        let q2 = ReceiptParser.extractQuantity("精品五花肉 500g", fallbackUnit: "克")
        XCTAssertEqual(q2?.qty, 500)
        XCTAssertEqual(q2?.unit, "克")
        let q3 = ReceiptParser.extractQuantity("牛奶 x2", fallbackUnit: "盒")
        XCTAssertEqual(q3?.qty, 2)
        let q4 = ReceiptParser.extractQuantity("排骨 1.5斤", fallbackUnit: "克")
        XCTAssertEqual(q4?.qty, 750)
    }

    func testPriceExtraction() {
        XCTAssertEqual(ReceiptParser.extractPrice("番茄 450g 8.90"), 8.90)
        XCTAssertEqual(ReceiptParser.extractPrice("鸡蛋 ¥15.90"), 15.90)
        XCTAssertNil(ReceiptParser.extractPrice("纯文字行"))
    }

    // MARK: 保质期状态

    func testFreshnessLogic() {
        let cal = Calendar.current
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: .now)! }
        if case .expired(let d) = PantryItem.freshness(expiryDate: day(-3)) { XCTAssertEqual(d, 3) } else { XCTFail("应为过期") }
        if case .expiring(let d) = PantryItem.freshness(expiryDate: day(0)) { XCTAssertEqual(d, 0) } else { XCTFail("今天到期应为临期") }
        if case .expiring = PantryItem.freshness(expiryDate: day(2)) {} else { XCTFail("2天内应为临期") }
        if case .fresh = PantryItem.freshness(expiryDate: day(5)) {} else { XCTFail("5天应为新鲜") }
        if case .fresh(nil) = PantryItem.freshness(expiryDate: nil) {} else { XCTFail("无日期应为长期") }
    }

    // MARK: 营养计算

    func testBMRAndTargets() {
        var p = BodyProfile()
        p.sex = .male; p.age = 30; p.heightCm = 175; p.weightKg = 70; p.activity = .light; p.goal = .loss300
        // Mifflin-St Jeor: 10*70 + 6.25*175 - 5*30 + 5 = 1648.75
        XCTAssertEqual(NutritionCalc.bmr(p), 1648.75, accuracy: 0.01)
        XCTAssertEqual(NutritionCalc.tdee(p), 1648.75 * 1.375, accuracy: 0.01)
        XCTAssertEqual(NutritionCalc.suggestedCalories(p), (1648.75 * 1.375 - 300).rounded(), accuracy: 0.01)
        p.weightKg = 30; p.heightCm = 120; p.age = 90; p.goal = .loss500
        XCTAssertGreaterThanOrEqual(NutritionCalc.suggestedCalories(p), 1200, "减脂下限 1200")
    }

    func testPagodaVerdicts() {
        XCTAssertEqual(Pagoda.verdict(group: .veg, avgGrams: 350), .ok)
        XCTAssertEqual(Pagoda.verdict(group: .veg, avgGrams: 100), .low)
        XCTAssertEqual(Pagoda.verdict(group: .meat, avgGrams: 160), .high)
        XCTAssertEqual(Pagoda.verdict(group: .oil, avgGrams: 50), .high)
        XCTAssertEqual(Pagoda.verdict(group: .veg, avgGrams: 0), .none)
    }

    // MARK: 推荐引擎

    func testRecommenderPrefersExpiring() {
        // 库存:番茄(临期)+鸡蛋 → 番茄炒蛋应排前面且标记临期
        let pantry: [String: Bool] = ["fanqie": true, "jidan": false, "xiaocong": false, "yan": false, "baitang": false, "shiyongyou": false]
        let recs = RecipeRecommender.recommend(pantryIds: pantry)
        XCTAssertFalse(recs.isEmpty)
        guard let top = recs.first(where: { $0.recipe.id == "fanqiechaodan" }) else {
            return XCTFail("番茄炒蛋应在推荐里")
        }
        XCTAssertTrue(top.missingIngredients.isEmpty, "主料应齐全")
        XCTAssertTrue(top.usesExpiring.contains("番茄"))
        XCTAssertEqual(recs.first?.recipe.id, "fanqiechaodan", "食材齐全又消耗临期的菜应排第一")
    }

    func testRecommenderCuisineFilter() {
        let pantry: [String: Bool] = ["wuhuarou": false, "qingjiao": false, "doubanjiang": false, "jidan": false, "fanqie": false]
        let recs = RecipeRecommender.recommend(pantryIds: pantry, cuisine: "chuan")
        XCTAssertFalse(recs.isEmpty)
        XCTAssertTrue(recs.allSatisfy { $0.recipe.cui == "chuan" })
    }

    // MARK: 文本匹配

    func testCatalogMatcher() {
        XCTAssertEqual(Catalog.shared.match(line: "新鲜西红柿 2个")?.id, "fanqie")
        XCTAssertEqual(Catalog.shared.match(line: "老干妈风味豆豉")?.id, "lajiangjiang")
        XCTAssertEqual(Catalog.shared.match(line: "五常大米 5kg")?.id, "dami")
        XCTAssertNil(Catalog.shared.match(line: "88.00"))
    }
}
