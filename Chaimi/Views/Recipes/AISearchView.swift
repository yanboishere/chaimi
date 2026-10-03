import SwiftUI
import SwiftData

// MARK: - AI 联网搜菜谱

struct AISearchView: View {
    let pantry: [PantryItem]

    @State private var cuisine: String = "家常菜"
    @State private var selectedIds: Set<String> = []
    @State private var extraText = ""
    @State private var phase: Phase = .idle
    @State private var results: [WebRecipe] = []
    @State private var citations: [Citation] = []
    @State private var errorText: String? = nil
    @State private var cookTarget: WebRecipe? = nil

    enum Phase: Equatable { case idle, searching(String), done }

    private var hasKey: Bool { KeychainStore.hasKey }

    private var selectableItems: [PantryItem] {
        pantry.filter { $0.quantity > 0 && $0.categoryId != "condiment" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !hasKey {
                    noKeyCard
                } else {
                    composer
                    if case .searching(let text) = phase {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(text).font(.hand(15)).foregroundStyle(Color.ink.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                        .doodleCard()
                    }
                    ForEach(results) { recipe in
                        WebRecipeCard(recipe: recipe) { cookTarget = recipe }
                    }
                    if !citations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("来源").font(.hand(15)).foregroundStyle(Color.ink.opacity(0.7))
                            ForEach(citations.prefix(6), id: \.url) { c in
                                if let url = URL(string: c.url) {
                                    Link(c.title, destination: url)
                                        .font(.hand(13))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .doodleCard()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .alert("搜索失败", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("好") {}
        } message: { Text(errorText ?? "") }
        .sheet(item: $cookTarget) { recipe in
            CookSheet(recipeName: recipe.name,
                      kcalPerServing: recipe.kcalPerServing,
                      defaultServings: 1,
                      groupGramsPerDish: estimateGroups(recipe),
                      consumableIds: matchedIds(recipe),
                      source: "ai")
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if selectedIds.isEmpty {
                // 默认勾选临期的食材
                for item in pantry {
                    if case .fresh = item.freshness {} else if let id = item.catalogId { selectedIds.insert(id) }
                }
            }
        }
    }

    private var noKeyCard: some View {
        VStack(spacing: 10) {
            Text("🔑").font(.system(size: 40))
            Text("联网搜菜谱需要 Anthropic API Key").font(.hand(18)).foregroundStyle(Color.ink)
            Text("去「设置」页粘贴你的 Key(存在本机钥匙串里)。\n没有 Key 也可以用左边的「看库存推荐」,完全离线。")
                .font(.hand(14)).multilineTextAlignment(.center).foregroundStyle(Color.ink.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .doodleCard()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想吃哪个菜系?").font(.hand(16)).foregroundStyle(Color.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecipeBook.shared.cuisines) { c in
                        Button { cuisine = c.name } label: {
                            TagChip(text: c.name, color: cuisine == c.name ? .accentColor : .ink, filled: cuisine == c.name)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("用哪些库存食材?(已帮你勾上临期的)").font(.hand(16)).foregroundStyle(Color.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(selectableItems) { item in
                    if let id = item.catalogId {
                        Button {
                            if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
                        } label: {
                            TagChip(text: item.name, color: selectedIds.contains(id) ? .leafGreen : .ink, filled: selectedIds.contains(id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("补充要求,比如:少油、孩子吃、15分钟内", text: $extraText)
                .font(.hand(15))
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await search() }
            } label: {
                Label("用 Claude 联网搜菜谱", systemImage: "sparkle.magnifyingglass")
                    .font(.hand(17)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIds.isEmpty || phase == .searching("搜索中…") )
            Text("会实际调用 API 并产生少量费用;搜索一次通常几分钱到一两毛。")
                .font(.hand(11)).foregroundStyle(Color.ink.opacity(0.45))
        }
        .doodleCard()
    }

    @MainActor
    private func search() async {
        let names = selectedIds.compactMap { Catalog.shared.byId[$0]?.name }
        guard !names.isEmpty else { return }
        phase = .searching("Claude 正在联网搜索菜谱…")
        results = []; citations = []
        do {
            let ask = extraText.isEmpty ? cuisine : "\(cuisine)(要求:\(extraText))"
            let (recipes, cites) = try await ClaudeAPI.shared.searchRecipes(cuisine: ask, ingredients: names)
            results = recipes
            citations = cites
            phase = .done
            if recipes.isEmpty { errorText = "没搜到合适的菜谱,换几样食材试试。" }
        } catch {
            phase = .idle
            errorText = error.localizedDescription
        }
    }

    private func matchedIds(_ recipe: WebRecipe) -> [String] {
        var ids: [String] = []
        for ing in recipe.ingredients {
            if let item = Catalog.shared.match(line: ing.name) { ids.append(item.id) }
        }
        for s in recipe.seasonings {
            if let item = Catalog.shared.match(line: s) { ids.append(item.id) }
        }
        return ids
    }

    private func estimateGroups(_ recipe: WebRecipe) -> [FoodGroup: Double] {
        var out: [FoodGroup: Double] = [:]
        for ing in recipe.ingredients {
            guard let item = Catalog.shared.match(line: ing.name) else { continue }
            out[item.grp, default: 0] += LocalRecipe.estimateGrams(quantityText: ing.amount, item: item)
        }
        return out
    }
}

// MARK: - 联网菜谱卡片

struct WebRecipeCard: View {
    let recipe: WebRecipe
    var onCook: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recipe.name).font(.hand(20)).foregroundStyle(Color.ink)
                TagChip(text: recipe.cuisine, color: .accentColor)
                Spacer()
                Text("≈\(Int(recipe.kcalPerServing))千卡/份").font(.hand(12)).foregroundStyle(Color.ink.opacity(0.6))
            }
            Text("主料:" + recipe.ingredients.map { "\($0.name)\($0.amount.isEmpty ? "" : " \($0.amount)")" }.joined(separator: "、"))
                .font(.hand(14)).foregroundStyle(Color.ink.opacity(0.8))
            Text("调料:" + recipe.seasonings.joined(separator: "、"))
                .font(.hand(13)).foregroundStyle(Color.ink.opacity(0.65))
            if expanded {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, s in
                    Text("\(i + 1). \(s)").font(.hand(14)).foregroundStyle(Color.ink.opacity(0.8))
                }
                if !recipe.sourceUrl.isEmpty, let url = URL(string: recipe.sourceUrl) {
                    Link("来源:\(recipe.sourceTitle.isEmpty ? recipe.sourceUrl : recipe.sourceTitle)", destination: url)
                        .font(.hand(12))
                }
            }
            HStack {
                Button(expanded ? "收起做法" : "看做法") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.hand(14)).buttonStyle(.bordered)
                Spacer()
                Button("做好了,记一笔") { onCook() }
                    .font(.hand(14)).buttonStyle(.borderedProminent)
            }
        }
        .doodleCard()
    }
}
