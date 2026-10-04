import Foundation
import HealthKit

// MARK: - 预算计算(纯函数,可单测)

enum BudgetMode: String {
    case fixed      // 固定每日上限
    case health     // 跟随 Apple 健康:基础代谢 + 今日运动 + 目标盈亏
}

enum TargetCalc {
    /// 健康联动的今日预算:BMR + 今日主动消耗 + 目标盈亏,减脂下限 1200
    static func dynamicBudget(bmr: Double, todayActive: Double, goalDelta: Double) -> Double {
        max(1200, (bmr + max(0, todayActive) + goalDelta).rounded())
    }

    /// 用近 N 天实测主动消耗校准 TDEE(比问卷活动系数准)
    static func calibratedTDEE(bmr: Double, avgActive: Double) -> Double {
        (bmr + max(0, avgActive)).rounded()
    }

    /// 一天的净盈亏:摄入 −(基础代谢 + 主动消耗)。负数=亏空(减脂方向)
    static func netBalance(intake: Double, bmr: Double, active: Double) -> Double {
        intake - (bmr + max(0, active))
    }

    /// 千卡换算为大约脂肪克数(7700 千卡 ≈ 1kg)
    static func fatGrams(fromKcal kcal: Double) -> Double {
        kcal / 7.7
    }
}

// MARK: - 健康数据源协议

struct DailyEnergy: Identifiable, Equatable {
    let day: Date          // startOfDay
    let activeKcal: Double
    var id: Date { day }
}

protocol HealthProviding {
    /// 设备支持 HealthKit 吗(模拟器也支持,但通常没数据)
    var isAvailable: Bool { get }
    /// 弹系统授权面板(只读 活动能量/静息能量)
    func requestAuthorization() async -> Bool
    /// 今日到目前为止的主动消耗(千卡);无数据返回 nil
    func todayActiveKcal() async -> Double?
    /// 今日静息消耗(对照 BMR 公式用);无数据返回 nil
    func todayBasalKcal() async -> Double?
    /// 近 N 天(含今天)逐日主动消耗
    func dailyActiveKcal(daysBack: Int) async -> [DailyEnergy]
}

enum Health {
    /// -demoHealth 启动参数下用仿真数据(模拟器截图/测试);真机用 HealthKit
    static let provider: HealthProviding =
        ProcessInfo.processInfo.arguments.contains("-demoHealth") ? MockHealthProvider() : HealthKitProvider()
}

// MARK: - HealthKit 实现

final class HealthKitProvider: HealthProviding {
    private let store = HKHealthStore()
    private let activeType = HKQuantityType(.activeEnergyBurned)
    private let basalType = HKQuantityType(.basalEnergyBurned)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [activeType, basalType])
            return true
        } catch {
            return false
        }
    }

    func todayActiveKcal() async -> Double? {
        await sumToday(type: activeType)
    }

    func todayBasalKcal() async -> Double? {
        await sumToday(type: basalType)
    }

    private func sumToday(type: HKQuantityType) async -> Double? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
                cont.resume(returning: kcal)
            }
            store.execute(query)
        }
    }

    func dailyActiveKcal(daysBack: Int) async -> [DailyEnergy] {
        let cal = Calendar.current
        let end = Date.now
        guard let start = cal.date(byAdding: .day, value: -(daysBack - 1), to: cal.startOfDay(for: end)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: activeType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: cal.startOfDay(for: end),
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var out: [DailyEnergy] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    out.append(DailyEnergy(day: stats.startDate, activeKcal: kcal))
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }
}

// MARK: - 仿真实现(-demoHealth)

final class MockHealthProvider: HealthProviding {
    var isAvailable: Bool { true }
    func requestAuthorization() async -> Bool { true }
    func todayActiveKcal() async -> Double? { 286 }
    func todayBasalKcal() async -> Double? { 1584 }
    func dailyActiveKcal(daysBack: Int) async -> [DailyEnergy] {
        let cal = Calendar.current
        let pattern: [Double] = [412, 183, 531, 96, 348, 264, 286]
        return (0..<daysBack).reversed().map { offset in
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: .now)!)
            return DailyEnergy(day: day, activeKcal: pattern[(daysBack - 1 - offset) % pattern.count])
        }
    }
}
