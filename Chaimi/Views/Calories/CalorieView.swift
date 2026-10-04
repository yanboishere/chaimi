import SwiftUI
import SwiftData
import Charts

// MARK: - 卡路里记录 + Apple 健康 + 膳食对照

struct CalorieView: View {
    @Query(sort: \CalorieEntry.date, order: .reverse) private var entries: [CalorieEntry]
    @Query private var pantry: [PantryItem]
    @Environment(\.modelContext) private var context

    @AppStorage("dailyCalorieLimit") private var dailyLimit: Double = 0
    @AppStorage("bodyProfile") private var profileJSON: String = ""
    @AppStorage("budgetMode") private var budgetModeRaw = BudgetMode.fixed.rawValue
    @AppStorage("healthConnected") private var healthConnected = false

    @State private var showManualAdd = false
    @State private var aiAdvice: String? = nil
    @State private var aiLoading = false
    @State private var budgetAdvice: BudgetAdvice? = nil
    @State private var budgetLoading = false
    @State private var errorText: String? = nil

    // Apple 健康
    @State private var todayActive: Double? = nil
    @State private var todayBasal: Double? = nil
    @State private var weekActive: [DailyEnergy] = []
    @State private var healthLoading = false

    private var cal: Calendar { Calendar.current }
    private var profile: BodyProfile { BodyProfile.load(from: profileJSON) }
    private var bmr: Double { NutritionCalc.bmr(profile) }
    private var budgetMode: BudgetMode { BudgetMode(rawValue: budgetModeRaw) ?? .fixed }

    private var todayEntries: [CalorieEntry] { entries.filter { cal.isDateInToday($0.date) } }
    private var todayKcal: Double { todayEntries.reduce(0) { $0 + $1.kcal } }

    /// 今日预算:固定模式用设置值;健康模式 = BMR + 今日运动 + 目标盈亏
    private var todayBudget: Double? {
        switch budgetMode {
        case .fixed:
            return dailyLimit > 0 ? dailyLimit : nil
        case .health:
            return TargetCalc.dynamicBudget(bmr: bmr, todayActive: todayActive ?? 0, goalDelta: profile.goal.delta)
        }
    }

    private var last7Days: [(date: Date, kcal: Double)] {
        (0..<7).reversed().map { offset in
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: .now)!)
            let total = entries.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.kcal }
            return (day, total)
        }
    }

    private func activeKcal(on day: Date) -> Double? {
        weekActive.first { cal.isDate($0.day, inSameDayAs: day) }?.activeKcal
    }

    /// 本周净盈亏(只统计有摄入记录的天):Σ摄入 − Σ(BMR+运动)
    private var weeklyNet: Double? {
        guard healthConnected, !weekActive.isEmpty else { return nil }
        let days = last7Days.filter { $0.kcal > 0 }
        guard !days.isEmpty else { return nil }
        return days.reduce(0.0) { sum, day in
            sum + TargetCalc.netBalance(intake: day.kcal, bmr: bmr, active: activeKcal(on: day.date) ?? 0)
        }
    }

    private var weeklyGroupAvg: [FoodGroup: Double] {
        let since = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now))!
        var sum: [FoodGroup: Double] = [:]
        for e in entries where e.date >= since {
            for (g, v) in e.groupGrams { sum[g, default: 0] += v }
        }
        return sum.mapValues { $0 / 7 }
    }

    private var weeklyKcalAvg: Double {
        let nonZero = last7Days.filter { $0.kcal > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(0) { $0 + $1.kcal } / Double(nonZero.count)
    }

    private var snackCandidates: [PantryItem] {
        pantry.filter { $0.quantity > 0 && ($0.categoryId == "snack" || $0.categoryId == "fruit" || $0.categoryId == "dairy") }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        todayCard
                        if !healthConnected { healthConnectCard }
                        quickAdd
                        weekChart
                        pagodaCard
                        adviceCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("吃了多少")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showManualAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .sheet(isPresented: $showManualAdd) { ManualCalorieSheet() }
            .alert("出错了", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("好") {}
            } message: { Text(errorText ?? "") }
            .task {
                if DemoLaunch.wantsHealth {
                    healthConnected = true
                    budgetModeRaw = BudgetMode.health.rawValue
                }
                await refreshHealth()
            }
        }
    }

    // MARK: Apple 健康

    @MainActor
    private func refreshHealth() async {
        guard healthConnected else { return }
        todayActive = await Health.provider.todayActiveKcal()
        todayBasal = await Health.provider.todayBasalKcal()
        weekActive = await Health.provider.dailyActiveKcal(daysBack: 7)
    }

    @MainActor
    private func connectHealth() async {
        healthLoading = true
        defer { healthLoading = false }
        guard Health.provider.isAvailable else {
            errorText = "这台设备不支持 Apple 健康。"
            return
        }
        let ok = await Health.provider.requestAuthorization()
        if ok {
            healthConnected = true
            await refreshHealth()
        } else {
            errorText = "没拿到授权。可以在 系统设置 → 健康 → 数据访问 里打开柴米的读取权限。"
        }
    }

    private var healthConnectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").foregroundStyle(Color.tomatoRed).font(.title3)
                Text("连接 Apple 健康").font(.hand(17)).foregroundStyle(Color.ink)
            }
            Text("读取每天的运动消耗(只读,不出本机),把「今天还能吃多少」算得更准,还能看摄入 vs 消耗对照。")
                .font(.hand(13)).foregroundStyle(Color.ink.opacity(0.65))
            Button {
                Task { await connectHealth() }
            } label: {
                if healthLoading { ProgressView().frame(maxWidth: .infinity) }
                else { Text("授权读取").font(.hand(15)).frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered)
            .disabled(healthLoading)
        }
        .doodleCard()
    }

    // MARK: 今日

    private var todayCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.ink.opacity(0.12), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: todayBudget.map { min(1, todayKcal / $0) } ?? 0)
                        .stroke(todayBudget.map { todayKcal > $0 } == true ? Color.tomatoRed : Color.leafGreen,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: todayKcal)
                    VStack(spacing: 2) {
                        Text("\(Int(todayKcal))").font(.hand(26)).foregroundStyle(Color.ink)
                        Text(todayBudget.map { "/ \(Int($0))" } ?? "未设上限").font(.hand(12)).foregroundStyle(Color.ink.opacity(0.55))
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("今天").font(.hand(20)).foregroundStyle(Color.ink)
                        if budgetMode == .health {
                            TagChip(text: "跟随健康", color: .accentColor, filled: true)
                        }
                    }
                    if let budget = todayBudget {
                        let left = budget - todayKcal
                        Text(left >= 0 ? "还能吃 \(Int(left)) 千卡" : "超了 \(Int(-left)) 千卡 🫣")
                            .font(.hand(15))
                            .foregroundStyle(left >= 0 ? Color.leafGreen : Color.tomatoRed)
                    } else {
                        Text("到「设置」里定一个每日上限").font(.hand(14)).foregroundStyle(Color.ink.opacity(0.6))
                    }
                    if healthConnected, let active = todayActive {
                        Text("🔥 今日已消耗 \(Int(active)) 千卡").font(.hand(13)).foregroundStyle(Color.warnOrange)
                    }
                    ForEach(todayEntries.prefix(2)) { e in
                        Text("· \(e.name)  \(Int(e.kcal))千卡").font(.hand(13)).foregroundStyle(Color.ink.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
            if budgetMode == .health {
                Text("今日预算 = 基础 \(Int(bmr)) + 运动 \(Int(todayActive ?? 0))\(profile.goal.delta == 0 ? "" : (profile.goal.delta > 0 ? " + 增肌 \(Int(profile.goal.delta))" : " − 减脂 \(Int(-profile.goal.delta))")) = \(Int(todayBudget ?? 0)) 千卡,随运动实时上调")
                    .font(.hand(12))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let basal = todayBasal, basal > 0 {
                    Text("对照:健康 App 记录今日静息消耗 \(Int(basal)) 千卡(公式按全天 \(Int(bmr)) 估)")
                        .font(.hand(11)).foregroundStyle(Color.ink.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .doodleCard()
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("吃了零食水果?点一下就记").font(.hand(16)).foregroundStyle(Color.ink)
            if snackCandidates.isEmpty {
                Text("库存里暂时没有零食/水果/乳品").font(.hand(13)).foregroundStyle(Color.ink.opacity(0.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(snackCandidates) { item in
                        QuickSnackButton(item: item)
                    }
                }
            }
        }
        .doodleCard()
    }

    // MARK: 周图表(摄入柱 vs 消耗线)

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("这一周").font(.hand(18)).foregroundStyle(Color.ink)
                Spacer()
                if healthConnected {
                    HStack(spacing: 10) {
                        Label("摄入", systemImage: "square.fill").font(.hand(11)).foregroundStyle(Color.leafGreen)
                        Label("消耗", systemImage: "line.diagonal").font(.hand(11)).foregroundStyle(Color.warnOrange)
                    }
                }
            }
            Chart {
                ForEach(last7Days, id: \.date) { day in
                    let burn = healthConnected ? (activeKcal(on: day.date) ?? 0) + bmr : nil
                    BarMark(x: .value("日期", day.date, unit: .day), y: .value("千卡", day.kcal))
                        .foregroundStyle(
                            (burn.map { day.kcal > $0 } ?? (dailyLimit > 0 && day.kcal > dailyLimit))
                            ? Color.tomatoRed.gradient : Color.leafGreen.gradient)
                        .cornerRadius(4)
                }
                if healthConnected {
                    ForEach(weekActive) { d in
                        LineMark(x: .value("日期", d.day, unit: .day), y: .value("消耗", d.activeKcal + bmr))
                            .foregroundStyle(Color.warnOrange)
                            .lineStyle(StrokeStyle(lineWidth: 2.4))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("日期", d.day, unit: .day), y: .value("消耗", d.activeKcal + bmr))
                            .foregroundStyle(Color.warnOrange)
                            .symbolSize(26)
                    }
                } else if dailyLimit > 0 {
                    RuleMark(y: .value("上限", dailyLimit))
                        .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [6, 4]))
                        .foregroundStyle(Color.warnOrange)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("上限 \(Int(dailyLimit))").font(.hand(11)).foregroundStyle(Color.warnOrange)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .frame(height: 160)

            if let net = weeklyNet {
                let fat = TargetCalc.fatGrams(fromKcal: abs(net))
                Text(net <= 0
                     ? "本周净亏空 \(Int(-net)) 千卡,约减 \(Int(fat)) 克脂肪 🎉"
                     : "本周净盈余 \(Int(net)) 千卡,约囤 \(Int(fat)) 克脂肪 🫠")
                    .font(.hand(13))
                    .foregroundStyle(net <= 0 ? Color.leafGreen : Color.warnOrange)
                Text("消耗线 = 基础代谢 \(Int(bmr)) + 当日运动(Apple 健康)").font(.hand(11)).foregroundStyle(Color.ink.opacity(0.4))
            } else if weeklyKcalAvg > 0 {
                Text("有记录的日子平均 \(Int(weeklyKcalAvg)) 千卡/天")
                    .font(.hand(12)).foregroundStyle(Color.ink.opacity(0.55))
            }
        }
        .doodleCard()
    }

    // MARK: 宝塔对照

    private var pagodaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("对照膳食宝塔(近7天平均)").font(.hand(18)).foregroundStyle(Color.ink)
            Text("《中国居民平衡膳食宝塔(2022)》建议量,单位:克/天").font(.hand(11)).foregroundStyle(Color.ink.opacity(0.5))
            ForEach(Pagoda.ranges.filter { $0.group != .salt }) { range in
                PagodaRow(range: range, avg: weeklyGroupAvg[range.group] ?? 0)
            }
        }
        .doodleCard()
    }

    // MARK: 建议(规则 + AI)

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("建议").font(.hand(18)).foregroundStyle(Color.ink)
            ForEach(Pagoda.advice(avgPerDay: weeklyGroupAvg, kcalAvg: weeklyKcalAvg, limit: todayBudget), id: \.self) { tip in
                Text("· \(tip)").font(.hand(14)).foregroundStyle(Color.ink.opacity(0.8))
            }

            if let advice = budgetAdvice {
                Divider()
                Text("🤖 Claude 建议的每日预算").font(.hand(15)).foregroundStyle(Color.accentColor)
                Text("\(Int(advice.suggestedDailyLimit)) 千卡").font(.hand(30)).foregroundStyle(Color.ink)
                Text(advice.summary).font(.hand(13)).foregroundStyle(Color.ink.opacity(0.75))
                ForEach(advice.tips, id: \.self) { t in
                    Text("· \(t)").font(.hand(13)).foregroundStyle(Color.ink.opacity(0.75))
                }
                Button {
                    dailyLimit = advice.suggestedDailyLimit
                    budgetModeRaw = BudgetMode.fixed.rawValue
                } label: {
                    Text("设为我的每日上限").font(.hand(15)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if let aiAdvice {
                Divider()
                Text("🤖 Claude 营养师点评").font(.hand(15)).foregroundStyle(Color.accentColor)
                Text(aiAdvice).font(.hand(14)).foregroundStyle(Color.ink.opacity(0.85))
            }
            if KeychainStore.hasKey {
                HStack(spacing: 10) {
                    Button {
                        Task { await askBudget() }
                    } label: {
                        if budgetLoading { ProgressView().frame(maxWidth: .infinity) }
                        else { Label("让 Claude 定预算", systemImage: "target").font(.hand(14)).frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(budgetLoading)
                    Button {
                        Task { await askAI() }
                    } label: {
                        if aiLoading { ProgressView().frame(maxWidth: .infinity) }
                        else { Label("点评这一周", systemImage: "sparkles").font(.hand(14)).frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(aiLoading)
                }
            }
        }
        .doodleCard()
    }

    private func weeklyTable() -> String {
        var lines: [String] = ["最近7天(日期 | 摄入千卡 | 运动消耗千卡):"]
        for day in last7Days {
            let active = activeKcal(on: day.date).map { String(Int($0)) } ?? "无数据"
            lines.append("\(day.date.formatted(.dateTime.month().day())) | \(Int(day.kcal)) | \(active)")
        }
        for (g, v) in weeklyGroupAvg.sorted(by: { $0.value > $1.value }) {
            lines.append("\(g.label) 平均 \(Int(v)) 克/天")
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private func askBudget() async {
        budgetLoading = true
        defer { budgetLoading = false }
        let context = """
        \(profile.summaryText)
        公式估算基础代谢 \(Int(bmr)) 千卡\(todayBasal.map { ",健康App今日静息消耗 \(Int($0)) 千卡" } ?? "")
        \(weeklyTable())
        """
        do { budgetAdvice = try await ClaudeAPI.shared.budgetAdvice(context: context) }
        catch { errorText = error.localizedDescription }
    }

    @MainActor
    private func askAI() async {
        aiLoading = true
        defer { aiLoading = false }
        let recent = entries.prefix(15).map { "\($0.name) \(Int($0.kcal))千卡" }.joined(separator: ";")
        let summary = weeklyTable() + "\n最近吃过:\(recent)\n目标预算 \(todayBudget.map { String(Int($0)) } ?? "未设置") 千卡"
        do {
            aiAdvice = try await ClaudeAPI.shared.dietAdvice(weeklySummary: summary, profile: profile.summaryText)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 子视图

private struct PagodaRow: View {
    let range: PagodaRange
    let avg: Double

    private var verdict: Pagoda.Verdict { Pagoda.verdict(group: range.group, avgGrams: avg) }
    private var color: Color {
        switch verdict {
        case .ok: return .leafGreen
        case .low: return .warnOrange
        case .high: return .tomatoRed
        case .none: return Color.ink.opacity(0.3)
        }
    }
    private var label: String {
        switch verdict {
        case .ok: return "合适"
        case .low: return "偏少"
        case .high: return "偏多"
        case .none: return "没数据"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(range.group.label).font(.hand(14)).foregroundStyle(Color.ink).frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                let full = max(range.hi * 1.6, avg * 1.1, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ink.opacity(0.08))
                    Capsule().fill(Color.leafGreen.opacity(0.18))
                        .frame(width: geo.size.width * (range.hi - range.lo) / full)
                        .offset(x: geo.size.width * range.lo / full)
                    Capsule().fill(color.opacity(0.85))
                        .frame(width: max(4, geo.size.width * min(avg, full) / full), height: 7)
                }
            }
            .frame(height: 12)
            Text("\(Int(avg))").font(.hand(13)).foregroundStyle(color).frame(width: 36, alignment: .trailing)
            Text("建议\(range.rangeText)").font(.hand(11)).foregroundStyle(Color.ink.opacity(0.5)).frame(width: 74, alignment: .leading)
            Text(label).font(.hand(12)).foregroundStyle(color).frame(width: 40, alignment: .trailing)
        }
    }
}

private struct QuickSnackButton: View {
    let item: PantryItem
    @Environment(\.modelContext) private var context
    @State private var justLogged = false

    private var defaultGrams: Double {
        switch item.unit {
        case "袋", "盒", "包": return 50
        case "个", "根", "支", "杯", "罐", "瓶": return 120
        default: return 100
        }
    }

    var body: some View {
        Button {
            guard let per100 = item.kcalPer100g else { return }
            let kcal = per100 * defaultGrams / 100
            let groups: [FoodGroup: Double] = item.catalogItem.map { [$0.grp: defaultGrams] } ?? [:]
            context.insert(CalorieEntry(name: item.name, kcal: kcal, source: "snack", groupGrams: groups))
            try? context.save()
            withAnimation(.snappy) { justLogged = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justLogged = false }
        } label: {
            VStack(spacing: 4) {
                FoodIconView(imageName: item.imageName, freshness: item.freshness, size: 46)
                Text(justLogged ? "已记 ✓" : item.name).font(.hand(12))
                    .foregroundStyle(justLogged ? Color.leafGreen : Color.ink)
                if let k = item.kcalPer100g {
                    Text("≈\(Int(k * defaultGrams / 100))千卡").font(.hand(10)).foregroundStyle(Color.ink.opacity(0.45))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 手动记录

struct ManualCalorieSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CalorieEntry.date, order: .reverse) private var entries: [CalorieEntry]

    @State private var name = ""
    @State private var kcal: Double = 400

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                List {
                    Section {
                        TextField("吃了什么,比如:外卖麻辣烫", text: $name).font(.hand(16))
                        HStack {
                            Slider(value: $kcal, in: 50...2000, step: 10)
                            Text("\(Int(kcal))千卡").font(.hand(14)).frame(width: 70)
                        }
                        Button {
                            context.insert(CalorieEntry(name: name.isEmpty ? "一顿饭" : name, kcal: kcal, source: "manual"))
                            try? context.save()
                            dismiss()
                        } label: {
                            Text("记下来").font(.hand(17)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } header: { Text("手动记一笔").font(.hand(13)) }

                    Section {
                        ForEach(entries.prefix(20)) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(.hand(15))
                                    Text("\(e.date.formatted(.dateTime.month().day().hour().minute())) · \(e.sourceLabel)")
                                        .font(.hand(11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(e.kcal))千卡").font(.hand(14))
                            }
                        }
                        .onDelete { idx in
                            let shown = Array(entries.prefix(20))
                            for i in idx { context.delete(shown[i]) }
                            try? context.save()
                        }
                    } header: { Text("最近记录(左滑删除)").font(.hand(13)) }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("记录饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
