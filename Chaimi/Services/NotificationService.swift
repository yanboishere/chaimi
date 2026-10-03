import Foundation
import UserNotifications
import SwiftData

// MARK: - 过期提醒规划(纯逻辑,可单测)

struct ExpiryReminderPlan: Identifiable, Equatable {
    let id: String        // "expiry-yyyyMMdd",一天一条
    let fireDate: Date
    let title: String
    let body: String
}

enum NotificationPlanner {
    /// 把库存(名称+到期日)规划成若干条"每天一条"的提醒:
    /// - 常规:到期前一天的 hour:minute 提醒「明天到期:…」
    /// - 错过前一天时间点的(入库太晚),在到期当天同一时间补「今天到期:…」
    static func plans(items: [(name: String, expiry: Date?)], hour: Int, minute: Int,
                      now: Date = .now, horizonDays: Int = 30,
                      calendar: Calendar = .current) -> [ExpiryReminderPlan] {
        var tomorrowBuckets: [Date: [String]] = [:]   // 发送日 → 明天到期的名称
        var todayBuckets: [Date: [String]] = [:]      // 发送日 → 今天到期的名称
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) else { return [] }

        for (name, expiry) in items {
            guard let expiry else { continue }
            let expiryDay = calendar.startOfDay(for: expiry)
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: expiryDay) else { continue }
            if let slot1 = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayBefore),
               slot1 > now, slot1 <= horizon {
                tomorrowBuckets[dayBefore, default: []].append(name)
            } else if let slot2 = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: expiryDay),
                      slot2 > now, slot2 <= horizon {
                todayBuckets[expiryDay, default: []].append(name)
            }
        }

        let df = DateFormatter()
        df.calendar = calendar
        df.dateFormat = "yyyyMMdd"
        func clause(_ prefix: String, _ names: [String]) -> String? {
            guard !names.isEmpty else { return nil }
            let shown = names.prefix(4).joined(separator: "、")
            return names.count > 4 ? "\(prefix)\(shown)等\(names.count)样" : "\(prefix)\(shown)"
        }

        let days = Set(tomorrowBuckets.keys).union(todayBuckets.keys).sorted()
        return days.prefix(30).compactMap { day in
            guard let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            let parts = [clause("明天到期:", tomorrowBuckets[day] ?? []),
                         clause("今天到期:", todayBuckets[day] ?? [])].compactMap { $0 }
            guard !parts.isEmpty else { return nil }
            return ExpiryReminderPlan(
                id: "expiry-\(df.string(from: day))",
                fireDate: fire,
                title: "柴米 ⏰ 食材快过期了",
                body: parts.joined(separator: ";") + "。记得先吃掉~")
        }
    }
}

// MARK: - 本地通知调度

@MainActor
enum NotificationService {
    struct PendingPreview: Identifiable {
        let id: String
        let date: Date?
        let body: String
    }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "expiryReminderEnabled") }
    /// 提醒时间,存"从零点起的分钟数",默认 10:00
    static var reminderMinutes: Int { UserDefaults.standard.object(forKey: "expiryReminderTime") as? Int ?? 600 }

    static func authorize(provisional: Bool = false) async -> Bool {
        var opts: UNAuthorizationOptions = [.alert, .sound, .badge]
        if provisional { opts.insert(.provisional) }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: opts)) ?? false
    }

    static func authorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// 重建全部过期提醒(先清掉旧的 expiry-*,再按当前库存排)
    static func reschedule(items: [PantryItem]) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("expiry-") }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard enabled else { return }

        let plans = NotificationPlanner.plans(
            items: items.map { ($0.name, $0.expiryDate) },
            hour: reminderMinutes / 60, minute: reminderMinutes % 60)
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = ["chaimi": "expiry"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
        }
    }

    static func rescheduleFromStore(_ container: ModelContainer) async {
        let context = ModelContext(container)
        let items = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        await reschedule(items: items)
    }

    /// 设置页预览:已排好的提醒
    static func pendingPreviews() async -> [PendingPreview] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests
            .filter { $0.identifier.hasPrefix("expiry-") }
            .map { r in
                PendingPreview(id: r.identifier,
                               date: (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                                     ?? (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(),
                               body: r.content.body)
            }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// 演示模式:6 秒后弹一条示例提醒(验证横幅展示链路)
    static func scheduleDemoPing() async {
        let content = UNMutableNotificationContent()
        content.title = "柴米 ⏰ 食材快过期了"
        content.body = "明天到期:菠菜、香蕉;今天到期:嫩豆腐。记得先吃掉~"
        content.sound = .default
        content.userInfo = ["chaimi": "expiry"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 6, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "expiry-demo", content: content, trigger: trigger))
    }
}

// MARK: - 前台展示 & 点击跳转

extension Notification.Name {
    /// 点击过期提醒 → 跳到库存页并筛选临期
    static let chaimiOpenExpiring = Notification.Name("chaimi.openExpiring")
}

final class ChaimiNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ChaimiNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["chaimi"] != nil {
            await MainActor.run {
                NotificationCenter.default.post(name: .chaimiOpenExpiring, object: nil)
            }
        }
    }
}
