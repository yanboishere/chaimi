import Foundation
import SwiftData

@Model
final class PantryItem {
    var catalogId: String?
    var name: String
    var unit: String
    var quantity: Double
    var storageRaw: String
    var addedAt: Date
    var expiryDate: Date?
    var note: String

    init(catalogId: String?, name: String, unit: String, quantity: Double,
         storage: StorageKind, addedAt: Date = .now, expiryDate: Date?, note: String = "") {
        self.catalogId = catalogId
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.storageRaw = storage.rawValue
        self.addedAt = addedAt
        self.expiryDate = expiryDate
        self.note = note
    }

    var storage: StorageKind {
        get { StorageKind(rawValue: storageRaw) ?? .fridge }
        set { storageRaw = newValue.rawValue }
    }

    var catalogItem: CatalogItem? { catalogId.flatMap { Catalog.shared.byId[$0] } }
    var imageName: String? { catalogItem?.imageName }
    var categoryId: String { catalogItem?.cat ?? "other" }
    var kcalPer100g: Double? { catalogItem?.kcal }

    enum Freshness: Equatable {
        case fresh(daysLeft: Int?)
        case expiring(daysLeft: Int)
        case expired(daysAgo: Int)
    }

    static func freshness(expiryDate: Date?, now: Date = .now) -> Freshness {
        guard let expiry = expiryDate else { return .fresh(daysLeft: nil) }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.startOfDay(for: expiry)
        let days = cal.dateComponents([.day], from: start, to: end).day ?? 0
        if days < 0 { return .expired(daysAgo: -days) }
        if days <= 2 { return .expiring(daysLeft: days) }
        return .fresh(daysLeft: days)
    }

    var freshness: Freshness { Self.freshness(expiryDate: expiryDate) }

    var freshnessText: String {
        switch freshness {
        case .fresh(let d?): return "剩 \(d) 天"
        case .fresh(nil): return "长期"
        case .expiring(0): return "今天到期!"
        case .expiring(let d): return "剩 \(d) 天"
        case .expired(let d): return "过期 \(d) 天"
        }
    }

    static func defaultExpiry(for item: CatalogItem, storage: StorageKind, from date: Date = .now) -> Date? {
        guard let days = item.shelfLifeDays(for: storage) ?? item.defaultShelfLifeDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: date))
    }
}
