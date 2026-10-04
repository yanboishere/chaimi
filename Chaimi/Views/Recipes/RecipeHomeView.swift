import SwiftUI
import SwiftData

// MARK: - 菜谱主页(本地推荐 / AI 搜索)

struct RecipeHomeView: View {
    @Query private var pantry: [PantryItem]
    @State private var tab = 0
    @State private var cuisine: String? = nil
    @State private var showSlot = false

    /// catalogId → 是否临期/过期
    private var pantryMap: [String: Bool] {
        var map: [String: Bool] = [:]
        for item in pantry {
            guard let id = item.catalogId, item.quantity > 0 else { continue }
            let urgent: Bool
            switch item.freshness {
            case .fresh: urgent = false
            default: urgent = true
            }
            map[id] = (map[id] ?? false) || urgent
        }
        return map
    }

    private var urgentItems: [PantryItem] {
        pantry.filter { if case .fresh = $0.freshness { return false }; return true }
    }

    private var recommendations: [RecipeRecommendation] {
        RecipeRecommender.recommend(pantryIds: pantryMap, cuisine: cuisine)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        Text("看库存推荐").tag(0)
                        Text("AI 联网搜菜谱").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14).padding(.bottom, 8)

                    if tab == 0 { localList } else { AISearchView(pantry: pantry) }
                }
            }
            .navigationTitle("今天吃什么")
            .fullScreenCover(isPresented: $showSlot) { SlotMachineView() }
            .onAppear { if DemoLaunch.wantsSlot { showSlot = true } }
        }
    }

    private var slotBanner: some View {
        Button { showSlot = true } label: {
            HStack(spacing: 12) {
                Text("🎰").font(.system(size: 38))
                VStack(alignment: .leading, spacing: 3) {
                    Text("选不出来?摇一下!").font(.hand(19)).foregroundStyle(Color.ink)
                    Text("按库存抽一道菜,可筛肉菜/素菜/面食/米饭…")
                        .font(.hand(12)).foregroundStyle(Color.ink.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Color.ink.opacity(0.35))
            }
            .doodleCard()
        }
        .buttonStyle(.plain)
    }

    private var localList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                slotBanner
                if !urgentItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⏰ 先吃它们").font(.hand(17)).foregroundStyle(Color.warnOrange)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(urgentItems) { item in
                                    VStack(spacing: 3) {
                                        FoodIconView(imageName: item.imageName, freshness: item.freshness, size: 46)
                                        Text(item.name).font(.hand(12)).foregroundStyle(Color.ink)
                                    }
                                }
                            }
                        }
                    }
                    .doodleCard()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        cuisineChip(nil, "全部")
                        ForEach(RecipeBook.shared.cuisines) { c in cuisineChip(c.id, c.name) }
                    }
                    .padding(.vertical, 2)
                }

                if recommendations.isEmpty {
                    VStack(spacing: 8) {
                        Image("recipe_fanqiechaodan").resizable().scaledToFit().frame(width: 90).opacity(0.8)
                        Text("库存太少,还推荐不出菜").font(.hand(18)).foregroundStyle(Color.ink)
                        Text("先去「库存」加点食材吧").font(.hand(14)).foregroundStyle(Color.ink.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(recommendations) { rec in
                    NavigationLink(value: rec.recipe.id) {
                        RecommendationCard(rec: rec)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .navigationDestination(for: String.self) { recipeId in
            if let recipe = RecipeBook.shared.recipes.first(where: { $0.id == recipeId }) {
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    private func cuisineChip(_ id: String?, _ label: String) -> some View {
        Button {
            withAnimation(.snappy) { cuisine = id }
        } label: {
            TagChip(text: label, color: cuisine == id ? .accentColor : .ink, filled: cuisine == id)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 推荐卡片

struct RecommendationCard: View {
    let rec: RecipeRecommendation

    var body: some View {
        HStack(spacing: 12) {
            Image(rec.recipe.imageName).resizable().scaledToFit().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rec.recipe.name).font(.hand(19)).foregroundStyle(Color.ink)
                    TagChip(text: rec.recipe.cuisineName, color: .accentColor)
                }
                HStack(spacing: 8) {
                    Text("⏱ \(rec.recipe.time)分钟").font(.hand(12)).foregroundStyle(Color.ink.opacity(0.6))
                    Text("🔥 \(Int(rec.recipe.kcalPerServing))千卡/份").font(.hand(12)).foregroundStyle(Color.ink.opacity(0.6))
                }
                Text(rec.coverageText)
                    .font(.hand(13))
                    .foregroundStyle(rec.missingIngredients.isEmpty ? Color.leafGreen : Color.ink.opacity(0.65))
                if !rec.usesExpiring.isEmpty {
                    Text("⚠️ 能消耗临期:\(rec.usesExpiring.joined(separator: "、"))")
                        .font(.hand(12)).foregroundStyle(Color.warnOrange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Color.ink.opacity(0.35))
        }
        .doodleCard()
    }
}

// MARK: - 菜谱详情

struct RecipeDetailView: View {
    let recipe: LocalRecipe
    @Query private var pantry: [PantryItem]
    @State private var showCook = false

    private func pantryHas(_ catalogId: String) -> Bool {
        pantry.contains { $0.catalogId == catalogId && $0.quantity > 0 }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Spacer()
                        Image(recipe.imageName).resizable().scaledToFit().frame(width: 130, height: 130)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        TagChip(text: recipe.cuisineName, color: .accentColor, filled: true)
                        ForEach(recipe.tags, id: \.self) { TagChip(text: $0) }
                    }
                    HStack(spacing: 14) {
                        Label("\(recipe.time) 分钟", systemImage: "clock")
                        Label("\(recipe.serves) 人份", systemImage: "person.2")
                        Label("≈\(Int(recipe.kcalPerServing)) 千卡/份", systemImage: "flame")
                    }
                    .font(.hand(14))
                    .foregroundStyle(Color.ink.opacity(0.7))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("主料").font(.hand(19)).foregroundStyle(Color.ink)
                        ForEach(recipe.ing, id: \.id) { ing in
                            HStack {
                                Text(pantryHas(ing.id) ? "✅" : "🛒")
                                Text(ing.displayName + (ing.isOptional ? "(可选)" : "")).font(.hand(16)).foregroundStyle(Color.ink)
                                Spacer()
                                Text(ing.q).font(.hand(14)).foregroundStyle(Color.ink.opacity(0.6))
                            }
                        }
                    }
                    .doodleCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("调料").font(.hand(19)).foregroundStyle(Color.ink)
                        FlowChips(items: recipe.sea.map { id in
                            (Catalog.shared.byId[id]?.name ?? id, pantryHas(id))
                        })
                    }
                    .doodleCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("做法").font(.hand(19)).foregroundStyle(Color.ink)
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1)").font(.hand(15))
                                    .frame(width: 24, height: 24)
                                    .background(Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.4))
                                    .foregroundStyle(Color.accentColor)
                                Text(step).font(.hand(16)).foregroundStyle(Color.ink.opacity(0.85))
                            }
                        }
                    }
                    .doodleCard()

                    Button { showCook = true } label: {
                        Text("做好了!扣库存 + 记卡路里")
                            .font(.hand(18)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCook) {
            CookSheet(recipeName: recipe.name,
                      kcalPerServing: recipe.kcalPerServing,
                      defaultServings: recipe.serves,
                      groupGramsPerDish: recipe.groupGrams,
                      consumableIds: recipe.ing.map(\.id) + recipe.sea,
                      source: "recipe")
            .presentationDetents([.medium, .large])
        }
    }
}

/// 简易流式标签(有/没有 两色)
struct FlowChips: View {
    let items: [(String, Bool)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                TagChip(text: (pair.1 ? "✓ " : "缺 ") + pair.0, color: pair.1 ? .leafGreen : .warnOrange, filled: true)
            }
        }
    }
}

// MARK: - 做菜结算

struct CookSheet: View {
    let recipeName: String
    let kcalPerServing: Double
    let defaultServings: Int
    let groupGramsPerDish: [FoodGroup: Double]
    /// 这道菜会用到的 catalogId(主料+调料)
    let consumableIds: [String]
    let source: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantry: [PantryItem]

    @State private var servings: Int = 1
    @State private var consume: [PersistentIdentifier: Bool] = [:]
    @State private var logCalories = true

    private var touchable: [PantryItem] {
        pantry.filter { item in
            guard let id = item.catalogId, item.quantity > 0 else { return false }
            return consumableIds.contains(id)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                List {
                    Section {
                        Stepper(value: $servings, in: 1...12) {
                            Text("吃了 \(servings) 份").font(.hand(17))
                        }
                        Toggle(isOn: $logCalories) {
                            Text("记录卡路里 ≈\(Int(kcalPerServing * Double(servings))) 千卡").font(.hand(16))
                        }
                    } header: { Text("记一笔").font(.hand(13)) }

                    Section {
                        if touchable.isEmpty {
                            Text("库存里没有这道菜用到的食材").font(.hand(14)).foregroundStyle(.secondary)
                        }
                        ForEach(touchable) { item in
                            Toggle(isOn: Binding(
                                get: { consume[item.persistentModelID] ?? !isSeasoning(item) },
                                set: { consume[item.persistentModelID] = $0 })) {
                                HStack {
                                    Image(item.imageName ?? "").resizable().scaledToFit().frame(width: 32, height: 32)
                                    Text(item.name).font(.hand(16))
                                    Spacer()
                                    Text(isSeasoning(item) ? "调料,默认不扣" : "用掉 1 \(item.unit)")
                                        .font(.hand(12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text("从库存里扣掉").font(.hand(13)) }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(recipeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { apply() } }
            }
        }
    }

    private func isSeasoning(_ item: PantryItem) -> Bool {
        item.categoryId == "condiment" || item.categoryId == "staple"
    }

    private func apply() {
        for item in touchable {
            let shouldConsume = consume[item.persistentModelID] ?? !isSeasoning(item)
            guard shouldConsume else { continue }
            if item.quantity > 1 { item.quantity -= 1 } else { context.delete(item) }
        }
        if logCalories {
            // groupGramsPerDish 是整道菜(defaultServings 份)的克数,按实际吃的份数折算
            let factor = Double(servings) / Double(max(defaultServings, 1))
            let grams = groupGramsPerDish.mapValues { $0 * factor }
            context.insert(CalorieEntry(name: recipeName, kcal: kcalPerServing * Double(servings), source: source, groupGrams: grams))
        }
        try? context.save()
        dismiss()
    }
}
