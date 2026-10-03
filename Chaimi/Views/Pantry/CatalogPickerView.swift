import SwiftUI
import SwiftData

// MARK: - 手动添加:目录浏览器

struct CatalogPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category: String = "veg"
    @State private var picked: CatalogItem? = nil

    private var shown: [CatalogItem] {
        if !search.isEmpty {
            let n = Catalog.normalize(search)
            return Catalog.shared.items.filter { item in
                item.aliasesIncludingName.contains { Catalog.normalize($0).contains(n) || n.contains(Catalog.normalize($0)) }
            }
        }
        return Catalog.shared.items(in: category)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(spacing: 10) {
                    if search.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Catalog.shared.categories) { cat in
                                    Button {
                                        withAnimation(.snappy) { category = cat.id }
                                    } label: {
                                        TagChip(text: cat.name, color: category == cat.id ? .accentColor : .ink, filled: category == cat.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(shown) { item in
                                Button { picked = item } label: {
                                    VStack(spacing: 5) {
                                        Image(item.imageName).resizable().scaledToFit().frame(width: 58, height: 58)
                                        Text(item.name).font(.hand(14)).lineLimit(1).foregroundStyle(Color.ink)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .doodleCard(padding: 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("添加食材")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索 190 种常见食材调料")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(item: $picked) { item in
                ItemFormSheet(catalogItem: item) { picked = nil; dismiss() }
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - 入库表单

struct ItemFormSheet: View {
    let catalogItem: CatalogItem
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Double = 1
    @State private var storage: StorageKind = .fridge
    @State private var expiry: Date = .now
    @State private var hasExpiry = true

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(spacing: 14) {
                    Image(catalogItem.imageName).resizable().scaledToFit().frame(width: 96, height: 96)
                    Text(catalogItem.name).font(.hand(26)).foregroundStyle(Color.ink)

                    VStack(spacing: 12) {
                        HStack {
                            Text("数量").font(.hand(16)).foregroundStyle(Color.ink)
                            Spacer()
                            Stepper(value: $quantity, in: 0.5...9999, step: quantity >= 50 ? 50 : 1) {
                                Text("\(quantity == quantity.rounded() ? String(Int(quantity)) : String(format: "%.1f", quantity)) \(catalogItem.unit)")
                                    .font(.hand(16))
                            }
                            .fixedSize()
                        }
                        HStack {
                            Text("存放").font(.hand(16)).foregroundStyle(Color.ink)
                            Spacer()
                            HandPicker(options: StorageKind.allCases.map { ($0, $0.label) }, selection: Binding(
                                get: { storage },
                                set: { storage = $0; resetExpiry() }))
                        }
                        Toggle(isOn: $hasExpiry) {
                            Text("记录保质期").font(.hand(16)).foregroundStyle(Color.ink)
                        }
                        if hasExpiry {
                            DatePicker(selection: $expiry, displayedComponents: .date) {
                                Text("保质期至").font(.hand(16)).foregroundStyle(Color.ink)
                            }
                        }
                    }
                    .doodleCard()

                    Button {
                        context.insert(PantryItem(
                            catalogId: catalogItem.id, name: catalogItem.name, unit: catalogItem.unit,
                            quantity: quantity, storage: storage,
                            expiryDate: hasExpiry ? expiry : nil))
                        try? context.save()
                        dismiss(); onDone()
                    } label: {
                        Text("放进库存").font(.hand(18)).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear {
                quantity = catalogItem.qty
                storage = catalogItem.st
                resetExpiry()
            }
        }
    }

    private func resetExpiry() {
        if let d = PantryItem.defaultExpiry(for: catalogItem, storage: storage) {
            expiry = d; hasExpiry = true
        } else {
            hasExpiry = false
        }
    }
}
