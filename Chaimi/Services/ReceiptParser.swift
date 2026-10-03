import Foundation

// MARK: - 小票解析(规则引擎,全离线)

struct ParsedReceiptLine: Identifiable {
    let id = UUID()
    var raw: String
    var item: CatalogItem?
    var quantity: Double
    var unit: String
    var price: Double?
    var include: Bool
    var matched: Bool { item != nil }
}

enum ReceiptParser {

    /// 明显不是商品的行
    static let noiseKeywords = [
        "合计", "总计", "应收", "实收", "找零", "优惠", "折扣", "会员", "积分", "收银", "店号", "单号",
        "欢迎", "谢谢", "光临", "电话", "地址", "退换", "保留", "小票", "发票", "微信", "支付宝", "现金",
        "银行卡", "welcome", "total", "cash", "no.", "tel", "购物袋", "塑料袋", "日期",
    ]

    static func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.count < 2 { return true }
        for k in noiseKeywords where lower.contains(k) { return true }
        // 纯分隔线/纯数字条码行
        let nonDecor = lower.filter { !"-=*_. ·:¥0123456789".contains($0) }
        if nonDecor.isEmpty { return true }
        return false
    }

    /// 提取行尾价格(如 "29.80" / "¥29.8")
    static func extractPrice(_ line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:¥\s*)?(\d{1,4}\.\d{1,2})\s*$"#) else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Double(ns.substring(with: m.range(at: 1)))
    }

    /// 提取数量与单位:匹配 "3根" "500g" "10枚" "x2" 等
    static func extractQuantity(_ line: String, fallbackUnit: String) -> (qty: Double, unit: String)? {
        let unitPattern = "(千克|毫升|克|斤|两|个|只|根|把|盒|袋|瓶|罐|包|枚|片|块|支|条|颗|串|朵|节|头|杯|听|桶|kg|ml|g|l)"
        if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*"# + unitPattern, options: [.caseInsensitive]) {
            let ns = line as NSString
            if let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let value = Double(ns.substring(with: m.range(at: 1))) ?? 1
                var unit = ns.substring(with: m.range(at: 2))
                var qty = value
                switch unit.lowercased() {
                case "g", "克": unit = "克"
                case "kg", "千克": unit = "克"; qty = value * 1000
                case "斤": unit = "克"; qty = value * 500
                case "两": unit = "克"; qty = value * 50
                case "ml", "l", "毫升", "升": unit = "毫升"; qty = unit == "升" || unit.lowercased() == "l" ? value * 1000 : value
                default: break
                }
                return (qty, unit)
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"[x×\*]\s*(\d+)"#, options: [.caseInsensitive]) {
            let ns = line as NSString
            if let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                return (Double(ns.substring(with: m.range(at: 1))) ?? 1, fallbackUnit)
            }
        }
        return nil
    }

    /// 把 OCR 行解析成候选入库条目(含未匹配行,交给界面让用户决定)
    static func parse(lines: [String]) -> [ParsedReceiptLine] {
        var out: [ParsedReceiptLine] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isNoise(line) { continue }
            let price = extractPrice(line)
            let item = Catalog.shared.match(line: line)
            // 没匹配上目录、又没有价格的行,多半是表头/杂讯,丢弃
            if item == nil && price == nil { continue }
            let fallbackUnit = item?.unit ?? "份"
            let qtyUnit = extractQuantity(line, fallbackUnit: fallbackUnit)
            out.append(ParsedReceiptLine(
                raw: line,
                item: item,
                quantity: qtyUnit?.qty ?? item?.qty ?? 1,
                unit: qtyUnit?.unit ?? fallbackUnit,
                price: price,
                include: item != nil
            ))
        }
        return out
    }
}
