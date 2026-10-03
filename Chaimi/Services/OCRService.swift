import Foundation
import Vision
import CoreGraphics

/// 本地(离线)识别:小票文字 OCR + 单品照片分类,全部走 Apple Vision,不出设备。
enum OCRService {

    /// 识别图中文字,按行返回。同一水平带上的多个片段(名称/价格分栏)会合并成一行。
    static func recognizeLines(in image: CGImage) async throws -> [String] {
        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (req.results as? [VNRecognizedTextObservation]) ?? [])
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
                catch { cont.resume(throwing: error) }
            }
        }

        struct Frag { let text: String; let x: CGFloat; let y: CGFloat; let h: CGFloat }
        let frags: [Frag] = observations.compactMap { ob in
            guard let candidate = ob.topCandidates(1).first else { return nil }
            let b = ob.boundingBox
            return Frag(text: candidate.string, x: b.minX, y: b.midY, h: b.height)
        }
        // Vision 的 y 轴向上;按 y 从大到小(即从上到下)分带合并
        let sorted = frags.sorted { $0.y > $1.y }
        var lines: [[Frag]] = []
        for f in sorted {
            if var last = lines.last, let anchor = last.first,
               abs(anchor.y - f.y) < max(anchor.h, f.h) * 0.6 {
                last.append(f); lines[lines.count - 1] = last
            } else {
                lines.append([f])
            }
        }
        return lines.map { group in
            group.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
        }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 单品照片分类(离线),返回映射到目录的候选
    static func classifyFood(in image: CGImage, limit: Int = 5) async throws -> [(item: CatalogItem, confidence: Double)] {
        let results: [VNClassificationObservation] = try await withCheckedThrowingContinuation { cont in
            let request = VNClassifyImageRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (req.results as? [VNClassificationObservation]) ?? [])
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
                catch { cont.resume(throwing: error) }
            }
        }
        var seen = Set<String>()
        var out: [(CatalogItem, Double)] = []
        for ob in results where ob.confidence > 0.1 {
            guard let id = visionLabelMap[ob.identifier], let item = Catalog.shared.byId[id], !seen.contains(id) else { continue }
            seen.insert(id)
            out.append((item, Double(ob.confidence)))
            if out.count >= limit { break }
        }
        return out
    }

    /// Apple Vision 分类标签 → 目录 id
    static let visionLabelMap: [String: String] = [
        "apple": "pingguo", "banana": "xiangjiao", "oranges": "chengzi", "mandarine": "juzi",
        "pear": "li", "peach": "taozi", "grape": "putao", "grapes": "putao", "strawberry": "caomei",
        "blueberry": "lanmei", "watermelon": "xigua", "cantaloupe": "hamigua", "honeydew": "hamigua",
        "melon": "hamigua", "lemon": "ningmeng", "lime": "ningmeng", "kiwi": "mihoutao", "mango": "mangguo",
        "cherry": "chelizi", "tomato": "fanqie", "cucumber": "huanggua", "carrot": "huluobo",
        "potato": "tudou", "onion": "yangcong", "garlic": "dasuan", "broccoli": "xilanhua",
        "cauliflower": "huacai", "cabbage": "yuanbaicai", "lettuce": "shengcai", "spinach": "bocai",
        "eggplant": "qiezi", "pumpkin": "nangua", "zucchini": "xihulu", "corn": "yumi",
        "pepper_veggie": "qingjiao", "bell_pepper": "qingjiao", "radish": "bailuobo", "celery": "qincai",
        "mushroom": "xianggu", "chives": "jiucai", "taro": "yutou", "leek": "dacong", "cilantro": "xiangcai",
        "egg": "jidan", "chicken": "sanhuangji", "steak": "niupai", "meat": "wuhuarou", "bacon": "peigen",
        "sausage": "xiangchang", "pepperoni": "xiangchang", "salami": "xiangchang", "ham": "huotui",
        "fish": "luyu", "salmon": "sanwenyu", "tuna": "daiyu", "crab": "pangxie", "lobster": "jiweixia",
        "oyster": "shenghao", "clam": "hage", "mussel": "hage", "scallop": "shanbei", "shellfish": "hage",
        "shrimp": "jiweixia", "prawn": "jiweixia", "squid": "youyu",
        "bread": "tusi", "white_bread": "tusi", "cheese": "zhishipian", "butter": "huangyou",
        "yogurt": "suannai", "milkshake": "niunai", "honey": "fengmi", "oatmeal": "yanmai", "cereal": "yanmai",
        "rice": "dami", "pasta": "yidalimian", "dumpling": "shuijiao", "cookie": "binggan",
        "chocolate": "qiaokeli", "chocolate_chip": "qiaokeli", "coffee_bean": "guaer", "peanut": "huashengmi",
        "nut": "meirijianguo", "chestnut": "meirijianguo", "popcorn": "shupian", "fries": "shupian",
        "beer": "pijiu", "wine": "pijiu", "juice": "guozhi", "ice_cream": "bingqilin",
        "green_beans": "doujiao", "bean": "doujiao", "pea": "helandou", "coconut": "yiner",
    ]
}
