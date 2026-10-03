import Foundation

// MARK: - Anthropic Messages API 客户端(URLSession 直连,无 SDK)

enum ClaudeError: LocalizedError {
    case noAPIKey
    case invalidKey
    case rateLimited
    case overloaded
    case http(Int, String)
    case refusal(String?)
    case emptyContent
    case badJSON(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "还没有配置 API Key,请到「设置」里添加。"
        case .invalidKey: return "API Key 无效或已撤销(401),请检查设置。"
        case .rateLimited: return "请求太频繁(429),稍等一会儿再试。"
        case .overloaded: return "Anthropic 服务暂时繁忙(529),稍后重试。"
        case .http(let code, let msg): return "请求失败(\(code)):\(msg)"
        case .refusal(let why): return "模型拒绝了这个请求\(why.map { ":\($0)" } ?? ""),换个说法试试。"
        case .emptyContent: return "模型没有返回内容,请重试。"
        case .badJSON(let hint): return "返回内容解析失败:\(hint)"
        case .network(let e): return "网络错误:\(e.localizedDescription)"
        }
    }
}

struct ScannedFoodItem: Decodable, Identifiable {
    let name: String
    let catalogId: String
    let quantity: Double
    let unit: String
    var id: String { name + unit }
    var catalogItem: CatalogItem? { catalogId.isEmpty ? nil : Catalog.shared.byId[catalogId] }
}

struct WebRecipe: Decodable, Identifiable {
    struct Ingredient: Decodable, Hashable { let name: String; let amount: String }
    let name: String
    let cuisine: String
    let ingredients: [Ingredient]
    let seasonings: [String]
    let steps: [String]
    let kcalPerServing: Double
    let sourceTitle: String
    let sourceUrl: String
    var id: String { name + sourceUrl }
}

struct Citation: Hashable { let title: String; let url: String }

actor ClaudeAPI {
    static let shared = ClaudeAPI()

    static let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"]
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private var model: String {
        UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-opus-5-5"
    }

    // MARK: 底层请求

    private func send(_ body: [String: Any], timeout: TimeInterval = 300) async throws -> [String: Any] {
        guard let key = KeychainStore.loadAPIKey() else { throw ClaudeError.noAPIKey }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data; let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw ClaudeError.network(error) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.badJSON("HTTP \(status)")
        }
        if status != 200 {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "未知错误"
            switch status {
            case 401: throw ClaudeError.invalidKey
            case 429: throw ClaudeError.rateLimited
            case 529: throw ClaudeError.overloaded
            default: throw ClaudeError.http(status, msg)
            }
        }
        if json["stop_reason"] as? String == "refusal" {
            let why = (json["stop_details"] as? [String: Any])?["explanation"] as? String
            throw ClaudeError.refusal(why)
        }
        return json
    }

    private func textBlocks(_ response: [String: Any]) -> String {
        guard let content = response["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
    }

    private func decodeStructured<T: Decodable>(_ type: T.Type, from response: [String: Any]) throws -> T {
        let text = textBlocks(response)
        guard !text.isEmpty else { throw ClaudeError.emptyContent }
        guard let data = text.data(using: .utf8) else { throw ClaudeError.badJSON("非 UTF-8") }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw ClaudeError.badJSON(String(text.prefix(120))) }
    }

    /// 目录速查表(id: 名称),给视觉识别提示用
    private var catalogDirectory: String {
        Catalog.shared.items.map { "\($0.id):\($0.name)" }.joined(separator: " ")
    }

    // MARK: 1. 测试连接

    func testConnection() async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 64,
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": "回复两个字:正常"]],
        ]
        let resp = try await send(body, timeout: 60)
        return (resp["model"] as? String) ?? model
    }

    // MARK: 2. 识别小票 / 食材照片(视觉 + 结构化输出)

    func extractItems(imageJPEG: Data) async throws -> [ScannedFoodItem] {
        struct Payload: Decodable { let items: [ScannedFoodItem] }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["items"],
            "properties": ["items": [
                "type": "array",
                "items": [
                    "type": "object", "additionalProperties": false,
                    "required": ["name", "catalogId", "quantity", "unit"],
                    "properties": [
                        "name": ["type": "string", "description": "识别出的食材/商品名(中文)"],
                        "catalogId": ["type": "string", "description": "对应目录 id;不在目录中则为空字符串"],
                        "quantity": ["type": "number"],
                        "unit": ["type": "string", "description": "个/克/盒/瓶等"],
                    ],
                ],
            ]],
        ]
        let prompt = """
        这张图是一张超市购物小票,或者是食材/调料的照片。请识别出其中所有可以入库的食材、肉类、调味品、食品,忽略购物袋、会员、合计等非商品信息。\
        每个条目给出名称、数量和单位(没有就按常理估一个),并且在下面的目录里找最接近的条目填 catalogId(格式 id:名称;找不到就填空字符串):
        \(catalogDirectory)
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": imageJPEG.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ]],
        ]
        let resp = try await send(body)
        return try decodeStructured(Payload.self, from: resp).items
    }

    // MARK: 3. 联网搜索菜谱(web_search 服务端工具,两步:搜索 → 结构化)

    func searchRecipes(cuisine: String, ingredients: [String], count: Int = 4) async throws -> (recipes: [WebRecipe], citations: [Citation]) {
        let tools: [[String: Any]] = [["type": "web_search_20250305", "name": "web_search", "max_uses": 5]]
        let ask = """
        请搜索中文菜谱网站(例如下厨房、豆果美食、美食杰),帮我找 \(count) 道\(cuisine),\
        主要使用这些家里现有的食材:\(ingredients.joined(separator: "、"))。\
        每道菜给出:菜名、主料和用量、需要的调料、3-6 步做法概述、每份大约多少千卡。优先选做法家常、步骤简单的。
        """
        var messages: [[String: Any]] = [["role": "user", "content": ask]]
        var resp = try await send([
            "model": model, "max_tokens": 6000,
            "output_config": ["effort": "low"],
            "tools": tools, "messages": messages,
        ])
        // 服务器端工具循环可能暂停,按文档把 assistant 内容原样带回继续
        var hops = 0
        while resp["stop_reason"] as? String == "pause_turn", hops < 3 {
            hops += 1
            messages.append(["role": "assistant", "content": resp["content"] ?? []])
            resp = try await send([
                "model": model, "max_tokens": 6000,
                "output_config": ["effort": "low"],
                "tools": tools, "messages": messages,
            ])
        }

        // 收集引用来源(文内 citations + 搜索结果)
        var citations: [Citation] = []
        var seen = Set<String>()
        func add(_ title: String?, _ url: String?) {
            guard let url, !url.isEmpty, !seen.contains(url) else { return }
            seen.insert(url)
            citations.append(Citation(title: title?.isEmpty == false ? title! : url, url: url))
        }
        for block in (resp["content"] as? [[String: Any]]) ?? [] {
            for c in (block["citations"] as? [[String: Any]]) ?? [] {
                add(c["title"] as? String, c["url"] as? String)
            }
            if block["type"] as? String == "web_search_tool_result",
               let results = block["content"] as? [[String: Any]] {
                for r in results { add(r["title"] as? String, r["url"] as? String) }
            }
        }

        let gathered = textBlocks(resp)
        guard !gathered.isEmpty else { throw ClaudeError.emptyContent }

        // 第二步:整理成结构化 JSON(结构化输出与引用不能同用,所以分开两次调用)
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["recipes"],
            "properties": ["recipes": [
                "type": "array",
                "items": [
                    "type": "object", "additionalProperties": false,
                    "required": ["name", "cuisine", "ingredients", "seasonings", "steps", "kcalPerServing", "sourceTitle", "sourceUrl"],
                    "properties": [
                        "name": ["type": "string"],
                        "cuisine": ["type": "string"],
                        "ingredients": ["type": "array", "items": [
                            "type": "object", "additionalProperties": false, "required": ["name", "amount"],
                            "properties": ["name": ["type": "string"], "amount": ["type": "string"]],
                        ]],
                        "seasonings": ["type": "array", "items": ["type": "string"]],
                        "steps": ["type": "array", "items": ["type": "string"]],
                        "kcalPerServing": ["type": "number"],
                        "sourceTitle": ["type": "string"],
                        "sourceUrl": ["type": "string", "description": "从来源列表中选最匹配的一个;没有就空字符串"],
                    ],
                ],
            ]],
        ]
        let sourceList = citations.map { "\($0.title) — \($0.url)" }.joined(separator: "\n")
        struct Payload: Decodable { let recipes: [WebRecipe] }
        let structured = try await send([
            "model": model, "max_tokens": 4000,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": "把下面的菜谱内容整理成 JSON。可用来源列表:\n\(sourceList.isEmpty ? "(无)" : sourceList)\n\n菜谱内容:\n\(gathered)"]],
        ])
        let recipes = try decodeStructured(Payload.self, from: structured).recipes
        return (recipes, citations)
    }

    // MARK: 4. 膳食建议

    func dietAdvice(weeklySummary: String, profile: String) async throws -> String {
        let system = """
        你是一位讲证据的中文营养师,参考《中国居民膳食指南(2022)》和平衡膳食宝塔的建议量:\
        谷类200-300克+薯类50-100克、蔬菜300-500克、水果200-350克、动物性食物120-200克(畜禽40-75/水产40-75/蛋约50,每周至少2次水产)、\
        奶300-500克、大豆坚果25-35克、油25-30克、盐<5克、水1500-1700毫升。\
        根据用户的身体参数和最近的饮食记录,给出 4-6 条具体、可执行、口语化的建议,不超过 300 字,不要用 markdown 标题。
        """
        let body: [String: Any] = [
            "model": model, "max_tokens": 1200,
            "system": system,
            "output_config": ["effort": "low"],
            "messages": [["role": "user", "content": "我的情况:\(profile)\n\n最近 7 天的饮食记录汇总:\n\(weeklySummary)"]],
        ]
        let resp = try await send(body, timeout: 120)
        let text = textBlocks(resp)
        guard !text.isEmpty else { throw ClaudeError.emptyContent }
        return text
    }
}
