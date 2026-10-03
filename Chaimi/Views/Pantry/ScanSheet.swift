import SwiftUI
import SwiftData
import PhotosUI

enum ScanSheetMode: String, Identifiable {
    case receipt, photo
    var id: String { rawValue }
    var title: String { self == .receipt ? "扫小票入库" : "拍食材入库" }
}

// MARK: - 扫描识别入库

struct ScanSheet: View {
    let mode: ScanSheetMode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem? = nil
    @State private var image: UIImage? = nil
    @State private var showCamera = false
    @State private var phase: Phase = .pickImage
    @State private var rows: [ParsedReceiptLine] = []
    @State private var errorText: String? = nil
    @State private var aiUsed = false

    enum Phase { case pickImage, working(String), review }

    private var hasAPIKey: Bool { KeychainStore.hasKey }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                switch phase {
                case .pickImage: pickView
                case .working(let text): workingView(text)
                case .review: reviewView
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                        await start(with: ui)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { ui in Task { await start(with: ui) } }
                    .ignoresSafeArea()
            }
            .alert("识别失败", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("好") { if rows.isEmpty { phase = .pickImage } }
            } message: { Text(errorText ?? "") }
            .task {
                // 演示模式:自动加载示例小票跑一遍本地 OCR
                if DemoLaunch.wantsScan, mode == .receipt, case .pickImage = phase,
                   let url = Bundle.main.url(forResource: "SampleReceipt", withExtension: "png"),
                   let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                    await start(with: ui)
                }
            }
        }
    }

    // MARK: 选图

    private var pickView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(mode == .receipt ? "food_dami" : "food_fanqie")
                .resizable().scaledToFit().frame(width: 100).opacity(0.85)
            Text(mode == .receipt
                 ? "拍下超市小票,自动识别买了什么\n(识别在手机本地完成,不联网)"
                 : "拍一张食材/调料的照片\n离线识别常见果蔬肉蛋")
                .font(.hand(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink.opacity(0.75))
            Spacer()

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("拍照", systemImage: "camera.fill").font(.hand(18)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle").font(.hand(18)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            if mode == .receipt {
                Button {
                    if let url = Bundle.main.url(forResource: "SampleReceipt", withExtension: "png"),
                       let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                        Task { await start(with: ui) }
                    }
                } label: {
                    Label("用示例小票试试", systemImage: "sparkles").font(.hand(16)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if hasAPIKey {
                Text("已配置 API Key:识别结果还可以用 Claude 再增强一遍")
                    .font(.hand(12)).foregroundStyle(Color.ink.opacity(0.5))
            }
        }
        .padding(20)
    }

    private func workingView(_ text: String) -> some View {
        VStack(spacing: 16) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                    .opacity(0.9)
            }
            ProgressView()
            Text(text).font(.hand(17)).foregroundStyle(Color.ink.opacity(0.8))
        }
        .padding(20)
    }

    // MARK: 识别流程

    @MainActor
    private func start(with ui: UIImage) async {
        image = ui
        phase = .working(mode == .receipt ? "正在本地识别小票文字…" : "正在本地识别照片…")
        guard let cg = ui.fixedOrientationCGImage() else {
            errorText = "无法读取这张图片"; phase = .pickImage; return
        }
        do {
            if mode == .receipt {
                let lines = try await OCRService.recognizeLines(in: cg)
                rows = ReceiptParser.parse(lines: lines)
            } else {
                let candidates = try await OCRService.classifyFood(in: cg)
                rows = candidates.enumerated().map { idx, c in
                    ParsedReceiptLine(raw: "照片识别:\(c.item.name) (置信度 \(Int(c.confidence * 100))%)",
                                      item: c.item, quantity: c.item.qty, unit: c.item.unit,
                                      price: nil, include: idx == 0)
                }
            }
            aiUsed = false
            phase = .review
            if rows.isEmpty {
                errorText = mode == .receipt
                    ? "没认出可入库的商品。小票拍清楚一点,或者试试 AI 识别。"
                    : "没认出这是什么食材,可以试试 AI 识别或手动添加。"
            }
        } catch {
            errorText = error.localizedDescription
            phase = .pickImage
        }
    }

    @MainActor
    private func runAI() async {
        guard let image, let jpeg = image.resizedJPEG(maxEdge: 1800) else { return }
        phase = .working("Claude 正在识别图片…")
        do {
            let found = try await ClaudeAPI.shared.extractItems(imageJPEG: jpeg)
            rows = found.map { f in
                ParsedReceiptLine(raw: "AI:\(f.name)", item: f.catalogItem,
                                  quantity: f.quantity > 0 ? f.quantity : (f.catalogItem?.qty ?? 1),
                                  unit: f.unit.isEmpty ? (f.catalogItem?.unit ?? "份") : f.unit,
                                  price: nil, include: true)
            }
            aiUsed = true
            phase = .review
            if rows.isEmpty { errorText = "AI 也没认出可入库的商品。" }
        } catch {
            errorText = error.localizedDescription
            phase = .review
        }
    }

    // MARK: 结果确认

    private var includedCount: Int { rows.filter { $0.include && $0.item != nil }.count }

    private var reviewView: some View {
        VStack(spacing: 0) {
            List {
                if let image {
                    HStack {
                        Spacer()
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach($rows) { $row in
                        ScanRowView(row: $row)
                    }
                } header: {
                    Text(aiUsed ? "Claude 识别结果,确认后入库" : "本地识别结果,确认后入库")
                        .font(.hand(14))
                } footer: {
                    Text("没匹配上的行可以点「选择食材」手动指定;杂项行会自动忽略。")
                        .font(.hand(12))
                }
            }
            .scrollContentBackground(.hidden)

            VStack(spacing: 8) {
                if hasAPIKey && !aiUsed {
                    Button { Task { await runAI() } } label: {
                        Label("用 Claude 重新识别(更准)", systemImage: "sparkles")
                            .font(.hand(16)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button { confirmImport() } label: {
                    Text("入库 \(includedCount) 样").font(.hand(18)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(includedCount == 0)
            }
            .padding(14)
            .background(.ultraThinMaterial)
        }
    }

    private func confirmImport() {
        for row in rows where row.include {
            guard let item = row.item else { continue }
            context.insert(PantryItem(
                catalogId: item.id, name: item.name,
                unit: row.unit, quantity: row.quantity,
                storage: item.st,
                expiryDate: PantryItem.defaultExpiry(for: item, storage: item.st)))
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - 识别结果行

private struct ScanRowView: View {
    @Binding var row: ParsedReceiptLine
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $row.include).labelsHidden().disabled(row.item == nil)
            if let item = row.item {
                Image(item.imageName).resizable().scaledToFit().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.hand(16)).foregroundStyle(Color.ink)
                    Text(row.raw).font(.hand(11)).foregroundStyle(Color.ink.opacity(0.45)).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        TextField("数量", value: $row.quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 54)
                            .font(.hand(15))
                        Text(row.unit).font(.hand(14)).foregroundStyle(Color.ink.opacity(0.7))
                    }
                    if let p = row.price { Text("¥\(p, specifier: "%.2f")").font(.hand(11)).foregroundStyle(Color.ink.opacity(0.4)) }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.raw).font(.hand(14)).foregroundStyle(Color.ink.opacity(0.7)).lineLimit(1)
                    Text("未匹配到目录").font(.hand(11)).foregroundStyle(Color.warnOrange)
                }
                Spacer()
                Button("选择食材") { showPicker = true }
                    .font(.hand(13)).buttonStyle(.bordered)
            }
        }
        .listRowBackground(Color.paperCard.opacity(0.7))
        .sheet(isPresented: $showPicker) {
            QuickMatchPicker { item in
                row.item = item
                row.quantity = item.qty
                row.unit = item.unit
                row.include = true
            }
        }
    }
}

/// 轻量目录选择器(给未匹配行指定食材)
private struct QuickMatchPicker: View {
    var onPick: (CatalogItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var shown: [CatalogItem] {
        if search.isEmpty { return Catalog.shared.items }
        let n = Catalog.normalize(search)
        return Catalog.shared.items.filter { item in
            item.aliasesIncludingName.contains { Catalog.normalize($0).contains(n) || n.contains(Catalog.normalize($0)) }
        }
    }

    var body: some View {
        NavigationStack {
            List(shown) { item in
                Button {
                    onPick(item); dismiss()
                } label: {
                    HStack {
                        Image(item.imageName).resizable().scaledToFit().frame(width: 34, height: 34)
                        Text(item.name).font(.hand(16)).foregroundStyle(Color.ink)
                        Spacer()
                        Text(Catalog.shared.category(id: item.cat)?.name ?? "").font(.hand(12)).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "搜索食材")
            .navigationTitle("选择对应食材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

// MARK: - 相机

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let ui = info[.originalImage] as? UIImage { parent.onImage(ui) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - UIImage 工具

extension UIImage {
    /// 纠正 EXIF 方向并返回 CGImage
    func fixedOrientationCGImage() -> CGImage? {
        if imageOrientation == .up { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    /// 压到长边 maxEdge 的 JPEG(控制上传体积与视觉 token)
    func resizedJPEG(maxEdge: CGFloat, quality: CGFloat = 0.72) -> Data? {
        let longest = max(size.width, size.height)
        let scaleFactor = longest > maxEdge ? maxEdge / longest : 1
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return img.jpegData(compressionQuality: quality)
    }
}
