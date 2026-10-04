import SwiftUI
import SwiftData
import UIKit

// MARK: - 摇一摇今天吃什么(拟物化老虎机)

struct SlotMachineView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var pantry: [PantryItem]

    @State private var dishType: DishType? = nil
    @AppStorage("onlyInStockMode") private var onlyInStock = false
    @AppStorage("onlyInStockStrict") private var strictSeasonings = false
    @State private var noMatchAlert = false
    @State private var strips: [[CatalogItem]] = [[], [], []]
    @State private var offsets: [CGFloat] = [1, 1, 1]
    @State private var spinning = false
    @State private var result: LocalRecipe? = nil
    @State private var lampTick = false
    @State private var soundOn = SoundPlayer.shared.enabled

    // 出票动画:凭条从出票口整体下滑抽出,被机身"遮住"的部分不可见
    @State private var ticketVisible = false
    @State private var printProgress: CGFloat = 0
    @State private var stamped = false
    @State private var ticketHeight: CGFloat = 470
    @State private var ticketNo = Int.random(in: 1...9999)

    private let rowHeight: CGFloat = 70
    private let reelLabels = ["蔬", "荤", "味"]

    private var pantryIds: Set<String> {
        Set(pantry.filter { $0.quantity > 0 }.compactMap(\.catalogId))
    }
    private var urgentIds: Set<String> {
        Set(pantry.filter { if case .fresh = $0.freshness { return false }; return true }.compactMap(\.catalogId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        typeChips
                            .padding(.bottom, 14)
                        HStack(alignment: .center, spacing: 8) {
                            machineBody
                            LeverView(disabled: spinning) { pullSpin() }
                        }
                        .zIndex(1)                     // 机身盖住还没抽出来的票
                        ticketArea
                            .padding(.leading, 10)
                            .padding(.trailing, 72)    // 对准机身(避开右侧拉杆),从出票口正下方出来
                        if !ticketVisible && !spinning {
                            Text("👉 往下拽右边的拉杆\n从你家库存里摇出今天这顿")
                                .font(.hand(14))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.ink.opacity(0.55))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 16)
                        }
                    }
                    .padding(14)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("今天吃什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .alert("这一类摇不出来了", isPresented: $noMatchAlert) {
                Button("好") {}
                if onlyInStock && strictSeasonings {
                    Button("放宽:只要主料齐") { strictSeasonings = false }
                }
                if onlyInStock {
                    Button("关掉「不用买菜」") { onlyInStock = false }
                }
            } message: {
                Text(onlyInStock
                     ? (strictSeasonings
                        ? "按「主料+调料都齐」的严格标准,现有库存凑不齐这一类的任何一道。补点货,或放宽标准。"
                        : "现有库存凑不齐这一类里的任何一道菜。去「库存」补点货,或者关掉「不用买菜」。")
                     : "这个类型下暂时没有菜谱。")
            }
            .navigationDestination(for: String.self) { id in
                if let recipe = RecipeBook.shared.recipes.first(where: { $0.id == id }) {
                    RecipeDetailView(recipe: recipe)
                }
            }
        }
        .task {
            prepareIdleStrips()
            if DemoLaunch.wantsSlot {
                try? await Task.sleep(for: .milliseconds(700))
                spin()
            }
        }
        .task(id: spinning) {
            // 转动时招牌小灯交替闪
            while spinning && !Task.isCancelled {
                lampTick.toggle()
                try? await Task.sleep(for: .milliseconds(260))
            }
            lampTick = false
        }
    }

    // MARK: 类型筛选

    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    guard !spinning else { return }
                    withAnimation(.snappy) { onlyInStock.toggle() }
                } label: {
                    TagChip(text: onlyInStock ? "🧺 不用买菜 ✓" : "🧺 不用买菜",
                            color: onlyInStock ? .leafGreen : .ink, filled: onlyInStock)
                }
                .buttonStyle(.plain)
                if onlyInStock {
                    Button {
                        guard !spinning else { return }
                        withAnimation(.snappy) { strictSeasonings.toggle() }
                    } label: {
                        TagChip(text: strictSeasonings ? "调料也齐 ✓" : "调料也要齐",
                                color: strictSeasonings ? .leafGreen : .ink, filled: strictSeasonings)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                Divider().frame(height: 18)
                chip(nil, "不限")
                ForEach(DishType.allCases) { t in chip(t, t.label) }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ t: DishType?, _ label: String) -> some View {
        Button {
            guard !spinning else { return }
            withAnimation(.snappy) { dishType = t }
        } label: {
            TagChip(text: label, color: dishType == t ? .accentColor : .ink, filled: dishType == t)
        }
        .buttonStyle(.plain)
    }

    // MARK: 机身

    private let woodLight = Color(red: 0.93, green: 0.78, blue: 0.55)
    private let wood = Color(red: 0.85, green: 0.64, blue: 0.37)
    private let woodDark = Color(red: 0.70, green: 0.48, blue: 0.24)

    private var machineBody: some View {
        VStack(spacing: 10) {
            marquee
            reelWindow
            printerSlot
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [woodLight, wood, woodDark], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.ink.opacity(0.35), radius: 5, x: 2, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.ink.opacity(0.75), lineWidth: 2.2)
        )
        .overlay(alignment: .topLeading) { rivet.padding(8) }
        .overlay(alignment: .topTrailing) { soundToggle.padding(6) }
        .overlay(alignment: .bottomLeading) { rivet.padding(8) }
        .overlay(alignment: .bottomTrailing) { rivet.padding(8) }
    }

    private var rivet: some View {
        Circle()
            .fill(RadialGradient(colors: [Color.white.opacity(0.9), Color.gray], center: .topLeading, startRadius: 0, endRadius: 7))
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color.ink.opacity(0.5), lineWidth: 0.8))
    }

    private var soundToggle: some View {
        Button {
            soundOn.toggle()
            SoundPlayer.shared.enabled = soundOn
        } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ink.opacity(0.65))
                .frame(width: 24, height: 24)
                .background(Circle().fill(woodLight.opacity(0.8)))
                .overlay(Circle().stroke(Color.ink.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var marquee: some View {
        HStack(spacing: 10) {
            lamp(on: spinning && lampTick)
            Text("今 天 吃 什 么")
                .font(.hand(17))
                .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.86))
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            lamp(on: spinning && !lampTick)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [woodDark, Color(red: 0.5, green: 0.33, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
        )
        .overlay(Capsule().strokeBorder(Color.ink.opacity(0.6), lineWidth: 1.5))
    }

    private func lamp(on: Bool) -> some View {
        Circle()
            .fill(on
                  ? AnyShapeStyle(RadialGradient(colors: [.white, .yellow, .orange], center: .center, startRadius: 0, endRadius: 7))
                  : AnyShapeStyle(Color(red: 0.45, green: 0.3, blue: 0.14)))
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color.ink.opacity(0.6), lineWidth: 1))
            .shadow(color: on ? .yellow.opacity(0.9) : .clear, radius: 5)
    }

    private var reelWindow: some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Text(reelLabels[i])
                        .font(.hand(13))
                        .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.86).opacity(0.9))
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    ReelView(strip: strips[i], offsetRows: offsets[i], rowHeight: rowHeight)
                        .frame(maxWidth: .infinity, maxHeight: rowHeight * 3)
                    if i < 2 {
                        Rectangle().fill(Color.ink.opacity(0.35)).frame(width: 1.5)
                    }
                }
            }
            .background(Color(red: 0.99, green: 0.97, blue: 0.90))
            .overlay(centerRowMarker)
            .overlay(cylinderShading)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.ink.opacity(0.8), lineWidth: 2)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            )
        }
    }

    /// 圆筒曲面:上下压暗 + 中线玻璃反光
    private var cylinderShading: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.38), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: rowHeight * 0.85)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .top, endPoint: .bottom)
                .frame(height: rowHeight * 0.85)
        }
        .overlay(
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.22), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                .frame(height: 16)
                .offset(y: -rowHeight * 0.32)
        )
        .allowsHitTesting(false)
    }

    private var centerRowMarker: some View {
        HStack {
            Triangle().fill(Color.tomatoRed).frame(width: 9, height: 14)
            Spacer()
            Triangle().fill(Color.tomatoRed).frame(width: 9, height: 14).rotationEffect(.degrees(180))
        }
        .padding(.horizontal, 2)
        .allowsHitTesting(false)
    }

    private var printerSlot: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            .frame(height: 9)
            .padding(.horizontal, 30)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ink.opacity(0.6), lineWidth: 1).padding(.horizontal, 30))
    }

    // MARK: 出票区(凭条从机身底部缝隙滑出)

    @ViewBuilder
    private var ticketArea: some View {
        if ticketVisible, let recipe = result {
            TicketView(recipe: recipe, no: ticketNo, pantryIds: pantryIds, stamped: stamped)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { ticketHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in ticketHeight = h }
                    }
                )
                .rotationEffect(.degrees(0), anchor: .top)
                // 底边对齐容器底:容器变高 = 凭条被一点点"抽"下来
                .frame(height: max(1, ticketHeight * printProgress), alignment: .bottom)
                .clipped()
                .padding(.top, -14)   // 容器顶对准机身底部的出票缝(机身 zIndex 更高,盖住未出部分)
        }
    }

    // MARK: 逻辑

    private func prepareIdleStrips() {
        let pools = SlotEngine.pools(pantryCatalogIds: pantryIds)
        for (i, pool) in [pools.veg, pools.protein, pools.seasoning].enumerated() {
            strips[i] = buildStrip(pool: pool, target: pool.first ?? Catalog.shared.items[0], length: 3)
            offsets[i] = 1
        }
    }

    /// 轮带:随机前缀 + 目标(倒数第二行,停轮时正好在中奖行)+ 一行垫底
    private func buildStrip(pool: [CatalogItem], target: CatalogItem, length: Int) -> [CatalogItem] {
        var out: [CatalogItem] = []
        var source = pool.isEmpty ? [target] : pool
        while out.count < length - 2 {
            source.shuffle()
            out.append(contentsOf: source)
        }
        out = Array(out.prefix(length - 2))
        out.append(target)
        out.append(source.randomElement() ?? target)
        return out
    }

    private func pullSpin() {
        // 有旧票先"吸"回打印口,再开新一轮;没票直接开摇
        guard ticketVisible, printProgress > 0 else { return spin() }
        SoundPlayer.shared.play("slot_print")
        withAnimation(.easeIn(duration: 0.35)) { printProgress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { spin() }
    }

    private func spin() {
        guard !spinning else { return }
        guard let recipe = SlotEngine.pick(type: dishType, pantryIds: pantryIds, urgentIds: urgentIds,
                                           excluding: result?.id, onlyInStock: onlyInStock,
                                           strictSeasonings: strictSeasonings) else {
            noMatchAlert = true
            return
        }
        let targets = SlotEngine.reelTargets(for: recipe)
        let pools = SlotEngine.pools(pantryCatalogIds: pantryIds)

        ticketVisible = false
        stamped = false
        printProgress = 0
        spinning = true
        result = recipe
        ticketNo = Int.random(in: 1...9999)

        let targetList = [targets.veg, targets.protein, targets.seasoning]
        let poolList = [pools.veg, pools.protein, pools.seasoning]
        let lengths = [20, 26, 32]
        for i in 0..<3 {
            strips[i] = buildStrip(pool: poolList[i], target: targetList[i], length: lengths[i])
            offsets[i] = 0
        }

        SoundPlayer.shared.play("slot_spin")
        let durations: [Double] = [1.1, 1.65, 2.2]
        DispatchQueue.main.async {
            for i in 0..<3 {
                withAnimation(.timingCurve(0.16, 0.84, 0.44, 1, duration: durations[i])) {
                    offsets[i] = CGFloat(strips[i].count - 2)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + durations[i]) {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + durations[2] + 0.25) {
                spinning = false
                printTicket()
            }
        }
    }

    private func printTicket() {
        ticketVisible = true
        SoundPlayer.shared.play("slot_print")
        // 两段式:先匀速抽出大半,最后"噔"地一下拽到底
        withAnimation(.easeInOut(duration: 0.78)) { printProgress = 0.9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { printProgress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.12) {
            SoundPlayer.shared.play("slot_stamp")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { stamped = true }
        }
    }
}

// MARK: - 拉杆

struct LeverView: View {
    var disabled: Bool
    var onPull: () -> Void

    @State private var pull: CGFloat = 0
    private let maxPull: CGFloat = 92
    private let trackHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 2) {
            // 滑槽 + 杆 + 红球
            ZStack(alignment: .top) {
                Capsule()
                    .fill(LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 10, height: trackHeight)
                    .overlay(Capsule().stroke(Color.ink.opacity(0.5), lineWidth: 1))
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: trackHeight - pull - 24)
                    .offset(y: pull + 20)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.5), Color.tomatoRed, Color(red: 0.5, green: 0.12, blue: 0.1)], center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: 24))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.ink.opacity(0.7), lineWidth: 1.6))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .offset(y: pull)
            }
            .frame(height: trackHeight + 14)
            // 底座
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ink.opacity(0.6), lineWidth: 1.2))
            Text(disabled ? "…" : "拉我")
                .font(.hand(12))
                .foregroundStyle(Color.ink.opacity(0.55))
        }
        .opacity(disabled ? 0.55 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard !disabled else { return }
                    let newPull = min(maxPull, max(0, value.translation.height))
                    if newPull >= maxPull * 0.62 && pull < maxPull * 0.62 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    pull = newPull
                }
                .onEnded { _ in
                    let fire = pull >= maxPull * 0.62 && !disabled
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { pull = 0 }
                    if fire {
                        SoundPlayer.shared.play("slot_lever")
                        onPull()
                    }
                }
        )
        .onTapGesture {
            guard !disabled else { return }
            SoundPlayer.shared.play("slot_lever")
            withAnimation(.easeIn(duration: 0.12)) { pull = maxPull }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { pull = 0 }
                onPull()
            }
        }
        .accessibilityLabel("拉杆,开始摇菜")
        .accessibilityAddTraits(.isButton)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - 单个转轮

private struct ReelView: View {
    let strip: [CatalogItem]
    let offsetRows: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(strip.enumerated()), id: \.offset) { _, item in
                Image(item.imageName)
                    .resizable().scaledToFit()
                    .frame(width: rowHeight - 18, height: rowHeight - 18)
                    .frame(height: rowHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .offset(y: -offsetRows * rowHeight + rowHeight)
        .frame(height: rowHeight * 3, alignment: .top)
        .clipped()
    }
}

// MARK: - 点菜凭证(锯齿小票)

struct TicketView: View {
    let recipe: LocalRecipe
    let no: Int
    let pantryIds: Set<String>
    var stamped: Bool = true

    private var targets: (veg: CatalogItem, protein: CatalogItem, seasoning: CatalogItem) {
        SlotEngine.reelTargets(for: recipe)
    }
    private var missing: [String] {
        recipe.ing.filter { !$0.isOptional && !pantryIds.contains($0.id) }.map(\.displayName)
    }
    private var missingSeasonings: [String] {
        recipe.sea.filter { !pantryIds.contains($0) }.compactMap { Catalog.shared.byId[$0]?.name }
    }
    private var typeLabels: [String] {
        recipe.dishTypes.sorted { $0.rawValue < $1.rawValue }.map(\.label)
    }

    private static let ticketDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    var body: some View {
        VStack(spacing: 10) {
            Text("柴 米 食 堂 · 点 菜 凭 证")
                .font(.hand(14)).foregroundStyle(Color.ink.opacity(0.65))
                .padding(.top, 18)
            Text("NO.\(String(format: "%04d", no)) · \(Self.ticketDate.string(from: .now))")
                .font(.hand(11)).foregroundStyle(Color.ink.opacity(0.4))
            DashedLine()
            Text("今天就做")
                .font(.hand(13)).foregroundStyle(Color.ink.opacity(0.55))
            Text(recipe.name)
                .font(.hand(34))
                .foregroundStyle(Color.ink)
            HStack(spacing: 6) {
                TagChip(text: recipe.cuisineName, color: .accentColor, filled: true)
                ForEach(typeLabels, id: \.self) { TagChip(text: $0) }
            }
            HStack(spacing: 14) {
                reelStamp(targets.veg)
                Text("+").font(.hand(20)).foregroundStyle(Color.ink.opacity(0.5))
                reelStamp(targets.protein)
                Text("+").font(.hand(20)).foregroundStyle(Color.ink.opacity(0.5))
                reelStamp(targets.seasoning)
            }
            .padding(.vertical, 2)
            Text("⏱ \(recipe.time) 分钟 · 🔥 ≈\(Int(recipe.kcalPerServing)) 千卡/份")
                .font(.hand(13)).foregroundStyle(Color.ink.opacity(0.6))
            if missing.isEmpty {
                Text(missingSeasonings.isEmpty ? "✅ 主料调料全都有,直接开火" : "✅ 主料家里全都有,直接开火")
                    .font(.hand(12)).foregroundStyle(Color.leafGreen)
            } else {
                Text("还缺:\(missing.joined(separator: "、")),得先买或换一道")
                    .font(.hand(12)).foregroundStyle(Color.warnOrange)
            }
            if !missingSeasonings.isEmpty {
                Text("调料缺 \(missingSeasonings.prefix(3).joined(separator: "、"))\(missingSeasonings.count > 3 ? "等" : ""),可按口味替代或省略")
                    .font(.hand(11)).foregroundStyle(Color.ink.opacity(0.45))
            }
            DashedLine()
            NavigationLink(value: recipe.id) {
                Text("看菜谱做起来").font(.hand(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            TicketShape()
                .fill(Color.paperCard)
                .shadow(color: Color.ink.opacity(0.18), radius: 4, x: 1, y: 3)
        )
        .overlay(TicketShape().stroke(Color.ink.opacity(0.5), lineWidth: 1.4))
        .overlay(alignment: .bottomTrailing) {
            Text("柴米")
                .font(.hand(16))
                .foregroundStyle(Color.paperCard)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.tomatoRed.opacity(0.88)))
                .rotationEffect(.degrees(-10))
                .scaleEffect(stamped ? 1 : 2.2)
                .opacity(stamped ? 1 : 0)
                .offset(x: -22, y: -56)
        }
    }

    private func reelStamp(_ item: CatalogItem) -> some View {
        VStack(spacing: 3) {
            Image(item.imageName).resizable().scaledToFit().frame(width: 46, height: 46)
            Text(item.name).font(.hand(11)).foregroundStyle(Color.ink.opacity(0.7)).lineLimit(1)
        }
        .frame(width: 72)
    }
}

/// 上下锯齿边的小票形状
struct TicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tooth: CGFloat = 14
        let depth: CGFloat = 7
        let teeth = max(4, Int(rect.width / tooth))
        let step = rect.width / CGFloat(teeth)
        p.move(to: CGPoint(x: 0, y: depth))
        for i in 0..<teeth {
            let x0 = CGFloat(i) * step
            p.addLine(to: CGPoint(x: x0 + step / 2, y: 0))
            p.addLine(to: CGPoint(x: x0 + step, y: depth))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - depth))
        for i in stride(from: teeth - 1, through: 0, by: -1) {
            let x0 = CGFloat(i) * step
            p.addLine(to: CGPoint(x: x0 + step / 2, y: rect.height))
            p.addLine(to: CGPoint(x: x0, y: rect.height - depth))
        }
        p.closeSubpath()
        return p
    }
}

struct DashedLine: View {
    var body: some View {
        Line()
            .stroke(Color.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return p
        }
    }
}
