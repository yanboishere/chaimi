import SwiftUI
import SwiftData

// MARK: - 库存主页

struct PantryListView: View {
    enum Filter: String, CaseIterable { case all = "全部", expiring = "临期", expired = "已过期" }
    enum GroupMode: String { case category, storage }

    @Query(sort: \PantryItem.expiryDate) private var items: [PantryItem]
    @Environment(\.modelContext) private var context

    @AppStorage("pantryGroupMode") private var groupModeRaw = GroupMode.category.rawValue
    /// 展开的分组 id,逗号分隔持久化
    @AppStorage("pantryExpandedGroups") private var expandedRaw = ""

    @State private var filter: Filter = .all
    @State private var categoryFilter: String? = nil
    @State private var searchText = ""
    @State private var showCatalogPicker = false
    @State private var scanMode: ScanSheetMode? = nil
    @State private var editingItem: PantryItem? = nil

    private var groupMode: GroupMode { GroupMode(rawValue: groupModeRaw) ?? .category }

    private var filtered: [PantryItem] {
        items.filter { item in
            switch filter {
            case .all: break
            case .expiring: if case .expiring = item.freshness {} else { return false }
            case .expired: if case .expired = item.freshness {} else { return false }
            }
            if let categoryFilter, item.categoryId != categoryFilter { return false }
            if !searchText.isEmpty && !item.name.localizedCaseInsensitiveContains(searchText) { return false }
            return true
        }
    }

    // MARK: 分组

    private struct GroupSection: Identifiable {
        let id: String
        let title: String
        let emoji: String?
        let items: [PantryItem]
        var urgentCount: Int { items.filter { if case .fresh = $0.freshness { return false }; return true }.count }
    }

    private var sections: [GroupSection] {
        switch groupMode {
        case .storage:
            return StorageKind.allCases.compactMap { kind in
                let rows = filtered.filter { $0.storage == kind }
                guard !rows.isEmpty else { return nil }
                return GroupSection(id: "st_\(kind.rawValue)", title: kind.label, emoji: kind.emoji, items: rows)
            }
        case .category:
            let dict = Dictionary(grouping: filtered, by: \.categoryId)
            var out = Catalog.shared.categories.compactMap { cat -> GroupSection? in
                guard let rows = dict[cat.id], !rows.isEmpty else { return nil }
                return GroupSection(id: "cat_\(cat.id)", title: cat.name, emoji: nil, items: rows)
            }
            if let other = dict["other"], !other.isEmpty {
                out.append(GroupSection(id: "cat_other", title: "其他", emoji: nil, items: other))
            }
            return out
        }
    }

    /// 搜索或筛选时强制全部展开,方便直接看到结果
    private var forceExpanded: Bool { !searchText.isEmpty || filter != .all || categoryFilter != nil }

    private var expandedIds: Set<String> {
        Set(expandedRaw.split(separator: ",").map(String.init))
    }
    private func isExpanded(_ id: String) -> Bool { forceExpanded || expandedIds.contains(id) }
    private func toggle(_ id: String) {
        var s = expandedIds
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        expandedRaw = s.sorted().joined(separator: ",")
    }
    private var allExpanded: Bool { sections.allSatisfy { expandedIds.contains($0.id) } }
    private func toggleAll() {
        expandedRaw = allExpanded ? "" : sections.map(\.id).sorted().joined(separator: ",")
    }

    private var expiringCount: Int { items.filter { if case .expiring = $0.freshness { return true }; return false }.count }
    private var expiredCount: Int { items.filter { if case .expired = $0.freshness { return true }; return false }.count }

    // MARK: 视图

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        filterBar
                        if expiringCount + expiredCount > 0 && filter == .all {
                            alertBanner
                        }
                        if filtered.isEmpty {
                            emptyState
                        }
                        ForEach(sections) { sec in
                            sectionHeader(sec)
                            if isExpanded(sec.id) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                                    ForEach(sec.items) { item in
                                        PantryCard(item: item)
                                            .onTapGesture { editingItem = item }
                                    }
                                }
                                .padding(.bottom, 4)
                                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("柴米库存")
            .searchable(text: $searchText, prompt: "找找家里有什么")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { scanMode = .receipt } label: { Label("扫购物小票", systemImage: "doc.text.viewfinder") }
                        Button { scanMode = .photo } label: { Label("拍食材照片", systemImage: "camera.viewfinder") }
                        Button { showCatalogPicker = true } label: { Label("手动添加", systemImage: "plus.circle") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showCatalogPicker) { CatalogPickerView() }
            .sheet(item: $scanMode) { mode in ScanSheet(mode: mode) }
            .sheet(item: $editingItem) { item in PantryItemDetailSheet(item: item) }
            .onAppear {
                if DemoLaunch.wantsScan { scanMode = .receipt }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chaimiOpenExpiring)) { _ in
                withAnimation(.snappy) { filter = .expiring }
            }
        }
    }

    // MARK: 分组标题(点击折叠/展开)

    private func sectionHeader(_ sec: GroupSection) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) { toggle(sec.id) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded(sec.id) ? 90 : 0))
                    .foregroundStyle(Color.ink.opacity(0.5))
                if let emoji = sec.emoji { Text(emoji).font(.system(size: 17)) }
                Text(sec.title).font(.hand(19)).foregroundStyle(Color.ink)
                Text("\(sec.items.count)")
                    .font(.hand(13))
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Color.ink.opacity(0.08)))
                    .foregroundStyle(Color.ink.opacity(0.6))
                if sec.urgentCount > 0 {
                    Text("⚠️\(sec.urgentCount)")
                        .font(.hand(13))
                        .foregroundStyle(Color.warnOrange)
                }
                Spacer(minLength: 6)
                if !isExpanded(sec.id) {
                    HStack(spacing: -11) {
                        ForEach(Array(sec.items.prefix(4)), id: \.persistentModelID) { item in
                            miniIcon(item)
                        }
                    }
                    if sec.items.count > 4 {
                        Text("…").font(.hand(14)).foregroundStyle(Color.ink.opacity(0.45))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(forceExpanded)
        .doodleCard(padding: 10)
    }

    private func miniIcon(_ item: PantryItem) -> some View {
        ZStack {
            Circle()
                .fill(Color.paperCard)
                .overlay(Circle().strokeBorder(Color.ink.opacity(0.35), lineWidth: 1.1))
            if let name = item.imageName, UIImage(named: name) != nil {
                Image(name).resizable().scaledToFit().padding(3)
            } else {
                Text("🥡").font(.system(size: 14))
            }
        }
        .frame(width: 34, height: 34)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HandPicker(options: Filter.allCases.map { ($0, $0 == .expiring && expiringCount > 0 ? "临期\(expiringCount)" : $0 == .expired && expiredCount > 0 ? "过期\(expiredCount)" : $0.rawValue) }, selection: $filter)
                Divider().frame(height: 20)
                Menu {
                    Button("全部分类") { categoryFilter = nil }
                    ForEach(Catalog.shared.categories) { cat in
                        Button(cat.name) { categoryFilter = cat.id }
                    }
                } label: {
                    TagChip(text: categoryFilter.flatMap { Catalog.shared.category(id: $0)?.name } ?? "分类 ▾", color: .ink, filled: categoryFilter != nil)
                }
                if !forceExpanded && !sections.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { toggleAll() }
                    } label: {
                        TagChip(text: allExpanded ? "全部收起" : "全部展开", color: .ink)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.snappy(duration: 0.3)) {
                        groupModeRaw = groupMode == .category ? GroupMode.storage.rawValue : GroupMode.category.rawValue
                    }
                } label: {
                    TagChip(text: groupMode == .category ? "🗂 按种类" : "🧊 按存放", color: .accentColor, filled: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private var alertBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(expiredCount > 0 ? "🪰 有 \(expiredCount) 样已经过期,\(expiringCount) 样快过期了" : "⚠️ 有 \(expiringCount) 样快过期了,优先吃掉")
                .font(.hand(16))
                .foregroundStyle(Color.warnOrange)
            Text("点上面「临期/过期」筛选,或去「菜谱」页看看怎么消耗 →")
                .font(.hand(13))
                .foregroundStyle(Color.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doodleCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("food_dabaicai").resizable().scaledToFit().frame(width: 90).opacity(0.75)
            Text(searchText.isEmpty ? "库存是空的" : "没找到「\(searchText)」")
                .font(.hand(20)).foregroundStyle(Color.ink)
            Text("点右上角 ➕ 扫小票或手动添加")
                .font(.hand(15)).foregroundStyle(Color.ink.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

// MARK: - 单个食材卡片

struct PantryCard: View {
    let item: PantryItem

    private var quantityText: String {
        let q = item.quantity
        let qs = q == q.rounded() ? String(Int(q)) : String(format: "%.1f", q)
        return "\(qs) \(item.unit)"
    }

    private var freshColor: Color {
        switch item.freshness {
        case .fresh: return Color.ink.opacity(0.55)
        case .expiring: return .warnOrange
        case .expired: return .tomatoRed
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            FoodIconView(imageName: item.imageName, freshness: item.freshness, size: 68)
            Text(item.name)
                .font(.hand(15))
                .lineLimit(1)
                .foregroundStyle(Color.ink)
                .strikethrough({ if case .expired = item.freshness { return true }; return false }())
            Text(quantityText)
                .font(.hand(12))
                .foregroundStyle(Color.ink.opacity(0.55))
            Text(item.freshnessText)
                .font(.hand(12))
                .foregroundStyle(freshColor)
        }
        .frame(maxWidth: .infinity)
        .doodleCard(padding: 8)
    }
}

// MARK: - 食材详情 / 编辑

struct PantryItemDetailSheet: View {
    @Bindable var item: PantryItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var logGrams: Double = 100

    private var kcalForLog: Double? {
        guard let per100 = item.kcalPer100g, per100 > 0 else { return nil }
        return per100 * logGrams / 100
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        FoodIconView(imageName: item.imageName, freshness: item.freshness, size: 110)
                        Text(item.freshnessText).font(.hand(16)).foregroundStyle(Color.ink.opacity(0.7))

                        VStack(spacing: 12) {
                            HStack {
                                Text("数量").font(.hand(16)).foregroundStyle(Color.ink)
                                Spacer()
                                Stepper(value: $item.quantity, in: 0...9999, step: item.quantity >= 50 ? 50 : 1) {
                                    Text("\(item.quantity == item.quantity.rounded() ? String(Int(item.quantity)) : String(format: "%.1f", item.quantity)) \(item.unit)")
                                        .font(.hand(16))
                                }
                                .fixedSize()
                            }
                            HStack {
                                Text("存放").font(.hand(16)).foregroundStyle(Color.ink)
                                Spacer()
                                HandPicker(options: StorageKind.allCases.map { ($0, $0.label) }, selection: Binding(
                                    get: { item.storage },
                                    set: { newValue in
                                        item.storage = newValue
                                        if let cat = item.catalogItem {
                                            item.expiryDate = PantryItem.defaultExpiry(for: cat, storage: newValue, from: item.addedAt)
                                        }
                                    }))
                            }
                            DatePicker(selection: Binding(get: { item.expiryDate ?? .now }, set: { item.expiryDate = $0 }), displayedComponents: .date) {
                                Text("保质期至").font(.hand(16)).foregroundStyle(Color.ink)
                            }
                        }
                        .doodleCard()

                        if let kcal = kcalForLog {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("吃掉一些,记入今天的卡路里").font(.hand(16)).foregroundStyle(Color.ink)
                                HStack {
                                    Slider(value: $logGrams, in: 20...500, step: 10)
                                    Text("\(Int(logGrams))克").font(.hand(14)).frame(width: 56)
                                }
                                Button {
                                    let groups: [FoodGroup: Double] = item.catalogItem.map { [$0.grp: logGrams] } ?? [:]
                                    context.insert(CalorieEntry(name: item.name, kcal: kcal, source: "snack", groupGrams: groups))
                                    try? context.save()
                                    dismiss()
                                } label: {
                                    Text("记一笔 ≈\(Int(kcal)) 千卡").font(.hand(16)).frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .doodleCard()
                        }

                        HStack(spacing: 12) {
                            Button {
                                if item.quantity > 1 { item.quantity -= 1; try? context.save() }
                                else { context.delete(item); try? context.save(); dismiss() }
                            } label: {
                                Text("用掉 1 \(item.unit)").font(.hand(16)).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                context.delete(item); try? context.save(); dismiss()
                            } label: {
                                Text(("已吃完 / 扔掉")).font(.hand(16)).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { try? context.save(); dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
