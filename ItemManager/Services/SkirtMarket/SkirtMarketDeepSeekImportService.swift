import Foundation

enum SkirtMarketDeepSeekImportMode: String, CaseIterable, Codable, Identifiable {
    case link
    case keyword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link: return "链接模式"
        case .keyword: return "关键词模式"
        }
    }
}

struct SkirtMarketImportLocalParse: Codable, Equatable {
    var platformHint: String
    var sourceURL: String?
    var title: String?
    var price: Double?
}

struct SkirtMarketDeepSeekInput: Codable {
    var mode: String
    var platformHint: String
    var sourceURL: String?
    var keyword: String?
    var capturedAt: String
    var rawText: String
    var localParse: SkirtMarketImportLocalParse

    enum CodingKeys: String, CodingKey {
        case mode
        case platformHint = "platform_hint"
        case sourceURL = "source_url"
        case keyword
        case capturedAt = "captured_at"
        case rawText = "raw_text"
        case localParse = "local_parse"
    }
}

struct SkirtMarketDeepSeekAnalysisResult {
    var items: [SkirtMarketDeepSeekItem]
    var rawJSON: String
}

struct SkirtMarketDeepSeekResponse: Codable {
    var items: [SkirtMarketDeepSeekItem]
}

struct SkirtMarketDeepSeekItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var brand: String?
    var series: String?
    var category: String?
    var color: String?
    var size: String?
    var condition: String?
    var isLolitaRelated: Bool
    var saleIntent: String?
    var confidence: Double?
    var missingFields: [String]
    var priceEvents: [SkirtMarketDeepSeekPriceEvent]

    enum CodingKeys: String, CodingKey {
        case title
        case brand
        case series
        case category
        case color
        case size
        case condition
        case isLolitaRelated = "is_lolita_related"
        case saleIntent = "sale_intent"
        case confidence
        case missingFields = "missing_fields"
        case priceEvents = "price_events"
    }
}

struct SkirtMarketDeepSeekPriceEvent: Codable, Identifiable {
    var id = UUID()
    var kind: String
    var amount: Double?
    var currency: String?
    var observedAt: String?
    var appliesAt: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case amount
        case currency
        case observedAt = "observed_at"
        case appliesAt = "applies_at"
        case note
    }
}

enum SkirtMarketImportParser {
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func localParse(_ text: String) -> SkirtMarketImportLocalParse {
        let firstURL = urls(in: text).first?.absoluteString
        let platform = platformHint(text: text, urlString: firstURL)
        return SkirtMarketImportLocalParse(
            platformHint: platform,
            sourceURL: firstURL,
            title: extractTitle(from: text),
            price: extractPrice(from: text)
        )
    }

    static func urls(in text: String) -> [URL] {
        guard let linkDetector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return linkDetector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    static func platformID(platform: String, sourceURL: String?) -> String {
        let fallback = UUID().uuidString
        guard let sourceURL,
              let url = URL(string: sourceURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return "\(platform)_\(fallback)"
        }

        let queryItems = components.queryItems ?? []
        let candidate = queryItems.first(where: { ["id", "itemID", "note_id"].contains($0.name) })?.value
            ?? url.pathComponents.last(where: { $0 != "/" && !$0.isEmpty })
            ?? url.host
            ?? fallback
        return "\(platform)_\(candidate)"
    }

    static func isoString(from date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    static func dateString(from date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func platformHint(text: String, urlString: String?) -> String {
        let lowered = "\(text) \(urlString ?? "")".lowercased()
        if lowered.contains("闲鱼") || lowered.contains("goofish") || lowered.contains("2.taobao.com") {
            return "xianyu"
        }
        if lowered.contains("小红书") || lowered.contains("xiaohongshu") || lowered.contains("xhslink") {
            return "xiaohongshu"
        }
        if lowered.contains("淘宝") || lowered.contains("taobao") || lowered.contains("tmall") || lowered.contains("m.tb.cn") {
            return "taobao"
        }
        if lowered.contains("微店") || lowered.contains("weidian") {
            return "weidian"
        }
        return "unknown"
    }

    private static func extractTitle(from text: String) -> String? {
        let bracketPatterns = ["【([^】]+)】", "《([^》]+)》", "\\[([^\\]]+)\\]"]
        for pattern in bracketPatterns {
            guard let match = firstCapture(pattern, in: text) else { continue }
            let title = match.trimmingCharacters(in: .whitespacesAndNewlines)
            if !["闲鱼", "淘宝", "小红书", "微店"].contains(title) {
                return title
            }
        }

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                !line.isEmpty && urls(in: line).isEmpty && extractPrice(from: line) == nil
            }
    }

    private static func extractPrice(from text: String) -> Double? {
        let patterns = [
            #"¥\s*(\d+(?:\.\d+)?)"#,
            #"(?:价格|现价|到手价|转让价)[:：]?\s*(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)\s*元"#
        ]

        for pattern in patterns {
            if let value = firstCapture(pattern, in: text), let price = Double(value) {
                return price
            }
        }

        return nil
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }
}

enum SkirtMarketDeepSeekImportError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 DS_API_KEY，请先配置 GenerativeAI-Info.plist。"
        case .invalidResponse:
            return "DeepSeek 返回格式无法解析。"
        case .http(let status, let body):
            return "DeepSeek HTTP \(status): \(body)"
        }
    }
}

final class SkirtMarketDeepSeekImportService {
    static let shared = SkirtMarketDeepSeekImportService()

    private init() {}

    func analyze(input: SkirtMarketDeepSeekInput) async throws -> SkirtMarketDeepSeekAnalysisResult {
        guard let apiKey = AIConfigManager.shared.dsApiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            throw SkirtMarketDeepSeekImportError.missingAPIKey
        }

        let userPayload = try String(data: JSONEncoder().encode(input), encoding: .utf8) ?? "{}"
        let requestBody = SkirtMarketDeepSeekChatRequest(
            model: "deepseek-v4-flash",
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: userPayload)
            ],
            responseFormat: .init(type: "json_object"),
            thinking: .init(type: "disabled"),
            stream: false,
            temperature: 0.1,
            maxTokens: 1800
        )

        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkirtMarketDeepSeekImportError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SkirtMarketDeepSeekImportError.http(httpResponse.statusCode, String(body.prefix(240)))
        }

        let chatResponse = try JSONDecoder().decode(SkirtMarketDeepSeekChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content,
              let jsonData = content.data(using: .utf8)
        else {
            throw SkirtMarketDeepSeekImportError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(SkirtMarketDeepSeekResponse.self, from: jsonData)
        return SkirtMarketDeepSeekAnalysisResult(items: decoded.items, rawJSON: content)
    }

    private static let systemPrompt = """
    你是 Lolita 裙装市场信息分析器，只输出 JSON。
    任务：从用户给出的淘宝、闲鱼、小红书、微店链接文本或关键词搜索结果中提取商品信息和价格时间线。

    规则：
    - 不联网，不假装已访问链接。
    - 不猜价格、不猜日期；看不出就填 null，并把字段名写入 missing_fields。
    - 价格必须放入 price_events，每个价格都有 observed_at；定金/尾款如有时间，写 applies_at。
    - Lolita 判断覆盖 AP、Angelic Pretty、Baby、AATP、Meta、IW、VM、古典玩偶，以及 OP、JSK、SK、小物、袜子、包、丝带、鞋等语义。
    - 只有页面证据明确描述具体洛丽塔商品时 is_lolita_related 才能为 true；品牌介绍、公司主页、直播、粉丝社群、论坛、资讯和社交页面必须为 false，category 必须为 other。
    - 不得把用户输入的品牌名或关键词当成页面证据；如果不是 Lolita 相关，is_lolita_related=false，仍返回可确认的字段。

    输出格式：
    {
      "items": [
        {
          "title": "string",
          "brand": "string|null",
          "series": "string|null",
          "category": "jsk|op|sk|blouse|accessory|bag|shoes|socks|ribbon|headdress|other",
          "color": "string|null",
          "size": "string|null",
          "condition": "string|null",
          "is_lolita_related": true,
          "sale_intent": "sell|buy|deposit|final_payment|reservation|unknown",
          "confidence": 0.0,
          "missing_fields": ["string"],
          "price_events": [
            {
              "kind": "current|original|deposit|balance",
              "amount": 0.0,
              "currency": "CNY",
              "observed_at": "ISO-8601",
              "applies_at": "ISO-8601|null",
              "note": "string|null"
            }
          ]
        }
      ]
    }
    """
}

private struct SkirtMarketDeepSeekChatRequest: Codable {
    struct Message: Codable {
        var role: String
        var content: String
    }

    struct ResponseFormat: Codable {
        var type: String
    }

    struct Thinking: Codable {
        var type: String
    }

    var model: String
    var messages: [Message]
    var responseFormat: ResponseFormat
    var thinking: Thinking
    var stream: Bool
    var temperature: Double
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case thinking
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct SkirtMarketDeepSeekChatResponse: Codable {
    struct Choice: Codable {
        var message: Message
    }

    struct Message: Codable {
        var role: String?
        var content: String?
    }

    var choices: [Choice]
}
