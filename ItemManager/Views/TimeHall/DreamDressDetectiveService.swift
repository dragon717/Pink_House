import Foundation
import UIKit
import Vision
import WebKit

enum DreamDressDetectivePhase: String, Equatable {
    case idle = "等待输入"
    case validating = "检查输入"
    case planning = "联网搜索商品"
    case fetching = "抓取静态页面"
    case structuring = "整理商品证据"
    case completed = "侦查完成"
}

nonisolated enum DreamDressEvidenceType: String, Codable, Equatable, Sendable {
    case webSearch = "平台搜索"
    case jsonLD = "JSON-LD Product"
    case openGraph = "OpenGraph"
    case pageMetadata = "页面标题"
    case renderedPage = "动态页面"
    case aiStructured = "DeepSeek 结构化"
}

nonisolated enum DreamDressAvailability: String, Codable, Equatable, Sendable {
    case available = "在售"
    case sold = "已售出"
    case delisted = "已下架"
    case unavailable = "暂不可购买"
    case unknown = "状态待确认"

    var sortPriority: Int {
        switch self {
        case .available: 0
        case .unknown: 1
        case .unavailable: 2
        case .sold: 3
        case .delisted: 4
        }
    }
}

struct DreamDressDetectiveInput: Equatable {
    var brandName: String
    var productName: String
    var productURL: String

    var hasAnyValue: Bool {
        [brandName, productName, productURL].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

typealias DreamDressCandidateProgress = @MainActor @Sendable ([DreamDressCandidate]) -> Void

nonisolated struct DreamDressInvestigationResult: Codable, Sendable {
    let foundCount: Int
    let allCandidates: [DreamDressCandidate]
    let validCandidates: [DreamDressCandidate]
    let cachedAt: Date
    let sourceUpdatedAt: Date?
    let isFromCache: Bool

    func limited(to count: Int, isFromCache: Bool) -> Self {
        let visibleCandidates = Array(allCandidates.prefix(count))
        let visibleIDs = Set(visibleCandidates.map(\.id))
        return Self(
            foundCount: visibleCandidates.count,
            allCandidates: visibleCandidates,
            validCandidates: validCandidates.filter { visibleIDs.contains($0.id) },
            cachedAt: cachedAt,
            sourceUpdatedAt: sourceUpdatedAt,
            isFromCache: isFromCache
        )
    }
}

nonisolated struct DreamDressInvestigationPage: Sendable {
    let result: DreamDressInvestigationResult
    let hasMore: Bool
}

nonisolated enum DreamDressPagination {
    static let pageSize = 20
    static let prefetchDistance = 10
    static let queriesPerPage = 4

    static func shouldPrefetch(visibleIndex: Int, totalCount: Int) -> Bool {
        totalCount > 0
            && visibleIndex >= max(0, totalCount - prefetchDistance - 1)
    }
}

nonisolated struct DreamDressProductDetails: Codable, Equatable, Sendable {
    let types: [String]
    let colors: [String]
    let sizes: [String]
    let length: String?
    let condition: String?
    let accessories: [String]

    var isEmpty: Bool {
        types.isEmpty && colors.isEmpty && sizes.isEmpty
            && length == nil && condition == nil && accessories.isEmpty
    }

    func merging(_ other: Self?) -> Self {
        guard let other else { return self }
        return Self(
            types: Self.unique(types + other.types),
            colors: Self.unique(colors + other.colors),
            sizes: Self.unique(sizes + other.sizes),
            length: length ?? other.length,
            condition: condition == "非全新" || other.condition == "非全新"
                ? "非全新"
                : condition ?? other.condition,
            accessories: Self.unique(accessories + other.accessories)
        )
    }

    static func extract(
        from text: String,
        category: String? = nil,
        color: String? = nil,
        size: String? = nil,
        condition: String? = nil
    ) -> Self? {
        let evidence = [category, text].compactMap { $0 }.joined(separator: " ")
        let typePatterns: [(String, String)] = [
            (#"(?i)(?<![a-z])jsk(?![a-z])|ジャンパースカート|背心裙"#, "JSK"),
            (#"(?i)(?<![a-z])op(?![a-z])|ワンピース|连衣裙"#, "OP"),
            (#"(?i)(?<![a-z])sk(?![a-z])|スカート|半身裙"#, "SK"),
            (#"(?i)blouse|ブラウス|衬衫"#, "衬衫"),
            (#"(?i)cardigan|カーディガン|开衫"#, "开衫"),
            (#"(?i)coat|コート|大衣|外套"#, "外套"),
            (#"(?i)apron|エプロン|围裙"#, "围裙"),
            (#"(?i)headdress|ヘッドドレス|头饰"#, "头饰"),
            (#"(?i)shoes|シューズ|鞋"#, "鞋"),
            (#"(?i)socks|ソックス|袜"#, "袜子"),
            (#"(?i)bag|バッグ|包"#, "包"),
            (#"罩裙"#, "罩裙")
        ]
        let types = unique(typePatterns.compactMap { pattern, value in
            evidence.range(of: pattern, options: .regularExpression) == nil ? nil : value
        })

        let directColors = splitValues(color).map(normalizedColor)
        let colorTerms = captures(
            #"(?i)(奶(?:油)?黄(?:色)?|生成(?:り|色)?|sax|サックス|水色|天蓝色?|藏青色?|海军蓝|粉红色?|粉色|pink|ピンク|白色|白系|white|黑色|黑系|black|红色|红系|red|蓝色|蓝系|blue|绿色|绿系|green|黄色|黄系|yellow|紫色|紫系|purple|米色|米白色?|beige|ベージュ|灰色|gray|grey|棕色|茶色|brown|金色|银色)"#,
            in: evidence
        ).map(normalizedColor)

        let directSizes = splitValues(size).map { $0.uppercased() }
        let sizes = unique(directSizes + captures(
            #"(?i)(?<![A-Z0-9])(XXS|XS|S|M|L|XL|XXL|XXXL|FREE|F)(?:\s*(?:码|サイズ))?(?![A-Z0-9])"#,
            in: evidence
        ).map { $0.uppercased() })

        let measuredLength = firstCapture(
            #"(?i)(?:裙长|衣长|长度)\s*[:：]?\s*(\d+(?:\.\d+)?\s*(?:cm|厘米))"#,
            in: evidence
        )
        let namedLength = ["超短", "短款", "及膝", "中长", "长款", "拖地"]
            .first(where: evidence.contains)
        let parsedCondition: String?
        if let condition, !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedCondition = normalizeCondition(condition)
        } else if evidence.range(
            of: #"全新(?:未拆|未使用)?|未使用|新品|new with tags|brand new"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            parsedCondition = "全新"
        } else if evidence.range(
            of: #"二手|中古|非全新|使用感|状态(?:一般|好|较好)|瑕疵|污渍|破损|used|pre-owned"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            parsedCondition = "非全新"
        } else {
            parsedCondition = nil
        }

        let accessoryPatterns: [(String, String)] = [
            (#"(?i)KC|发带|カチューシャ"#, "发带"),
            (#"(?i)headdress|ヘッドドレス|头饰"#, "头饰"),
            (#"蝴蝶结|リボン|ribbon"#, "蝴蝶结"),
            (#"胸针|ブローチ|brooch"#, "胸针"),
            (#"腰带|ベルト|belt"#, "腰带"),
            (#"围裙|エプロン|apron"#, "围裙"),
            (#"袖套|袖付|sleeves"#, "袖套"),
            (#"领结|ネクタイ|tie"#, "领结")
        ]
        let accessories = unique(accessoryPatterns.compactMap { pattern, value in
            evidence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil ? nil : value
        })
        let result = Self(
            types: types,
            colors: unique(directColors + colorTerms),
            sizes: sizes,
            length: measuredLength ?? namedLength,
            condition: parsedCondition,
            accessories: accessories
        )
        return result.isEmpty ? nil : result
    }

    private static func splitValues(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .components(separatedBy: CharacterSet(charactersIn: ",，、/|+"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let range = Range(match.range(at: captureIndex), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text).first
    }

    private static func normalizedColor(_ value: String) -> String {
        let value = value.lowercased()
        if value.range(of: #"奶(?:油)?黄"#, options: .regularExpression) != nil { return "奶黄色" }
        if value.contains("生成") { return "生成色" }
        if ["sax", "サックス", "水色"].contains(where: value.contains) { return "水色" }
        if value.contains("天蓝") { return "天蓝色" }
        if value.contains("藏青") || value.contains("海军蓝") { return "藏青色" }
        if value.contains("pink") || value.contains("ピンク") || value.contains("粉") { return "粉色" }
        if value.contains("white") || value.contains("白") { return "白色" }
        if value.contains("black") || value.contains("黑") { return "黑色" }
        if value.contains("red") || value.contains("红") { return "红色" }
        if value.contains("blue") || value.contains("蓝") { return "蓝色" }
        if value.contains("green") || value.contains("绿") { return "绿色" }
        if value.contains("yellow") || value.contains("黄") { return "黄色" }
        if value.contains("purple") || value.contains("紫") { return "紫色" }
        if value.contains("beige") || value.contains("ベージュ") || value.contains("米") { return "米色" }
        if value.contains("gray") || value.contains("grey") || value.contains("灰") { return "灰色" }
        if value.contains("brown") || value.contains("棕") || value.contains("茶") { return "棕色" }
        if value.contains("金") { return "金色" }
        if value.contains("银") { return "银色" }
        return value
    }

    private static func normalizeCondition(_ value: String) -> String {
        value.range(
            of: #"二手|中古|非全新|使用|一般|瑕疵|污渍|破损|used|pre-owned"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil ? "全新" : "非全新"
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

nonisolated struct DreamDressCandidate: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let brand: String?
    let category: String?
    let price: String?
    let details: DreamDressProductDetails?
    let imageURL: URL?
    let availability: DreamDressAvailability
    let sourceURL: URL
    let evidenceType: DreamDressEvidenceType

    init(
        title: String,
        brand: String?,
        category: String? = nil,
        price: String?,
        details: DreamDressProductDetails? = nil,
        imageURL: URL? = nil,
        availability: DreamDressAvailability = .unknown,
        sourceURL: URL,
        evidenceType: DreamDressEvidenceType
    ) {
        self.title = title
        self.brand = brand
        self.category = category
        self.price = price
        self.details = details
        self.imageURL = imageURL
        self.availability = availability
        self.sourceURL = sourceURL
        self.evidenceType = evidenceType
        id = "\(title.lowercased())|\(sourceURL.absoluteString)"
    }

    func enriched(
        imageURL: URL?,
        availability: DreamDressAvailability,
        brand: String? = nil,
        category: String? = nil,
        price: String? = nil,
        details: DreamDressProductDetails? = nil
    ) -> Self {
        Self(
            title: title,
            brand: self.brand ?? brand,
            category: self.category ?? category,
            price: self.price ?? price,
            details: self.details?.merging(details) ?? details,
            imageURL: self.imageURL ?? imageURL,
            availability: availability,
            sourceURL: sourceURL,
            evidenceType: evidenceType
        )
    }

    func enrichedFromRenderedPage(
        imageURL: URL?,
        availability: DreamDressAvailability,
        price: String?,
        details: DreamDressProductDetails?
    ) -> Self {
        Self(
            title: title,
            brand: brand,
            category: category,
            price: self.price ?? price,
            details: self.details?.merging(details) ?? details,
            imageURL: imageURL ?? self.imageURL,
            availability: availability == .unknown ? self.availability : availability,
            sourceURL: sourceURL,
            evidenceType: evidenceType
        )
    }
}

enum DreamDressDetectiveError: LocalizedError, Equatable {
    case emptyInput
    case invalidURL
    case unsafeURL
    case responseTooLarge
    case unsupportedContentType
    case httpStatus(Int)
    case blockedOrRequiresLogin
    case dynamicPage
    case requestTimedOut
    case noResults
    case invalidCrawlPlan
    case service(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请至少填写品牌名、商品名或商品链接。"
        case .invalidURL:
            return "未识别到有效商品链接，请粘贴分享文本或完整的 HTTPS 链接。"
        case .unsafeURL:
            return "出于安全原因，不能抓取本机、内网或云元数据地址。"
        case .responseTooLarge:
            return "页面超过 1.5 MB，已停止抓取。"
        case .unsupportedContentType:
            return "链接不是可读取的 HTML 或 JSON 页面。"
        case .httpStatus(let status):
            return "商品页面返回 HTTP \(status)。"
        case .blockedOrRequiresLogin:
            return "页面需要登录、验证码或被站点封禁，未尝试绕过。"
        case .dynamicPage:
            return "页面主要依赖动态渲染，未发现可验证的商品信息。"
        case .requestTimedOut:
            return "联网侦查超时，请稍后重试或直接粘贴商品链接。"
        case .noResults:
            return "没有找到可验证的洛丽塔服饰商品，请补充商品名或商品链接。"
        case .invalidCrawlPlan:
            return "检索计划没有提供可验证的 HTTPS 商品入口。"
        case .service(let message):
            return message
        }
    }
}

nonisolated enum DreamDressProductMatcher {
    private static let allowedAICategories: Set<String> = [
        "jsk", "op", "sk", "blouse", "accessory", "bag", "shoes", "socks", "ribbon", "headdress"
    ]
    private static let productTerms = [
        "连衣裙", "連衣裙", "连身裙", "連身裙", "吊带裙", "吊帶裙", "背带裙", "背帶裙",
        "连体裤", "連身褲", "半身裙", "裙装", "裙裝", "洋装", "洋裝", "dress", "skirt",
        "洛丽塔裙", "洛麗塔裙", "lo裙", "ワンピース", "ジャンパースカート", "スカート",
        "one piece", "one-piece", "jumperskirt",
        "小物", "袜子", "襪子", "ソックス", "靴下", "stocking", "tights", "socks",
        "包包", "小包", "手提包", "斜挎包", "バッグ", "ポシェット", "handbag", "shoulder bag", "tote bag",
        "丝带", "絲帶", "リボン", "ribbon", "蝴蝶结", "蝴蝶結", "发饰", "髮飾", "ヘアアクセサリー",
        "胸针", "胸針", "brooch", "blouse", "ブラウス", "鞋", "シューズ", "shoes"
    ]
    private static let productTokens: Set<String> = ["jsk", "op", "sk", "bag", "bow", "sock"]
    private static let lolitaTerms = ["lolita", "洛丽塔", "洛麗塔", "ロリータ"]
    private static let knownLolitaBrands = [
        "angelic pretty", "baby, the stars shine bright", "alice and the pirates",
        "juliette et justine", "wunderwelt", "innocent world", "victorian maiden",
        "pink house", "pinkhouse", "ピンクハウス"
    ]

    static func acceptsAIItem(isLolitaRelated: Bool, category: String?) -> Bool {
        guard isLolitaRelated, let category else { return false }
        return allowedAICategories.contains(category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func accepts(
        _ candidate: DreamDressCandidate,
        input: DreamDressDetectiveInput,
        pageEvidence: String
    ) -> Bool {
        let productText = [candidate.title, candidate.category]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let productWords = Set(productText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let normalizedCandidateText = normalizedSearchText(productText)
        let inputHints = [input.brandName, input.productName]
            .flatMap { [normalizedSearchText($0)] + searchAliases(for: $0).map(normalizedSearchText) }
            .filter { !$0.isEmpty }
        let isMatchingGoofishListing = candidate.evidenceType == .webSearch
            && isGoofishItemURL(candidate.sourceURL)
            && inputHints.contains(where: normalizedCandidateText.contains)
        let hasProductSignal = productTerms.contains(where: productText.contains)
            || !productWords.isDisjoint(with: productTokens)
            || containsLolitaCategoryToken(in: productText)
            || candidate.evidenceType == .webSearch && lolitaTerms.contains(where: productText.contains)
            || isMatchingGoofishListing
        guard hasProductSignal else { return false }

        let pageText = pageEvidence.lowercased()
        let pageWords = Set(pageText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let pageHasProduct = productTerms.contains(where: pageText.contains)
            || !pageWords.isDisjoint(with: productTokens)
            || containsLolitaCategoryToken(in: pageText)
            || candidate.evidenceType == .webSearch && lolitaTerms.contains(where: pageText.contains)
            || isMatchingGoofishListing
        let pageHasLolita = lolitaTerms.contains(where: pageText.contains)
            || containsLolitaCategoryToken(in: pageText)
            || knownLolitaBrands.contains(where: pageText.contains)
        guard pageHasProduct, pageHasLolita else { return false }

        let normalizedPageText = normalizedSearchText(pageEvidence)
        return inputHints.isEmpty || inputHints.contains(where: normalizedPageText.contains)
    }

    nonisolated static func searchAliases(for value: String) -> [String] {
        normalizedSearchText(value) == "pinkhouse" ? ["ピンクハウス"] : []
    }

    nonisolated static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func containsLolitaCategoryToken(in text: String) -> Bool {
        text.range(of: #"(?<![a-z])(?:jsk|op|sk)(?![a-z])"#, options: .regularExpression) != nil
    }

    private static func isGoofishItemURL(_ url: URL) -> Bool {
        guard ["goofish.com", "www.goofish.com"].contains(url.host?.lowercased() ?? ""),
              url.path == "/item",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value
        else { return false }
        return !id.isEmpty && id.allSatisfy(\.isNumber)
    }
}

/// 只解析静态页面证据；联网搜索结果仍需经过同一商品校验。
nonisolated enum DreamDressHTMLParser {
    static func parse(html: String, baseURL: URL) -> [DreamDressCandidate] {
        var candidates = jsonLDCandidates(in: html, baseURL: baseURL)
        if candidates.isEmpty, let fallback = metadataCandidate(in: html, baseURL: baseURL) {
            candidates = [fallback]
        }
        let metadata = metaAttributes(in: html)
        let metadataImageURL = metadataImageURL(metadata, baseURL: baseURL)
        let pageAvailability = availability(in: visibleEvidence(from: html))
        return unique(candidates).prefix(5).map { candidate in
            candidate.enriched(
                imageURL: metadataImageURL,
                availability: resolvedAvailability(candidate.availability, pageAvailability)
            )
        }
    }

    static func enrich(_ candidate: DreamDressCandidate, html: String, baseURL: URL) -> DreamDressCandidate {
        let parsed = parse(html: html, baseURL: baseURL)
        let parsedCandidate = parsed.first
        let parsedAvailability = parsed
            .map(\.availability)
            .first(where: { $0 != .unknown }) ?? availability(in: visibleEvidence(from: html))
        return candidate.enriched(
            imageURL: parsedCandidate?.imageURL,
            availability: resolvedAvailability(candidate.availability, parsedAvailability),
            brand: parsedCandidate?.brand,
            category: parsedCandidate?.category,
            price: parsedCandidate?.price,
            details: parsedCandidate?.details ?? DreamDressProductDetails.extract(
                from: "\(candidate.title) \(String(visibleEvidence(from: html).prefix(2_000)))",
                category: parsedCandidate?.category
            )
        )
    }

    static func availability(in evidence: String) -> DreamDressAvailability {
        let text = evidence.lowercased()
        if ["已售出", "已卖出", "卖掉了", "交易成功", "sold out", "soldout"].contains(where: text.contains) {
            return .sold
        }
        if ["已下架", "商品已下架", "宝贝不存在", "商品不存在", "链接已失效", "discontinued"].contains(where: text.contains) {
            return .delisted
        }
        if ["暂时缺货", "无货", "已售罄", "out of stock", "outofstock"].contains(where: text.contains) {
            return .unavailable
        }
        if ["在线", "在售", "立即购买", "立即下单", "我想要", "加入购物车", "buy now", "in stock"].contains(where: text.contains) {
            return .available
        }
        return .unknown
    }

    static func visibleEvidence(from html: String) -> String {
        var text = html
        text = replacingMatches(#"(?is)<(script|style|noscript)\b[^>]*>.*?</\1>"#, in: text, with: " ")
        text = replacingMatches(#"(?is)<[^>]+>"#, in: text, with: " ")
        return decodeEntities(text)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func jsonLDCandidates(in html: String, baseURL: URL) -> [DreamDressCandidate] {
        let pattern = #"(?is)<script\b[^>]*type\s*=\s*[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#
        let scripts = captureMatches(pattern, in: html)
        var candidates: [DreamDressCandidate] = []

        for script in scripts {
            guard let data = script.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }
            candidates.append(contentsOf: productCandidates(in: object, baseURL: baseURL))
        }

        if candidates.isEmpty,
           let data = html.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            candidates.append(contentsOf: productCandidates(in: object, baseURL: baseURL))
        }
        return candidates
    }

    private static func productCandidates(in object: Any, baseURL: URL) -> [DreamDressCandidate] {
        var products: [[String: Any]] = []
        collectProducts(from: object, into: &products)
        return products.compactMap { product in
            guard let title = stringValue(product["name"]), !title.isEmpty else { return nil }
            let brand = brandValue(product["brand"])
            let category = stringValue(product["category"])
            let offer = firstOffer(product["offers"])
            let price = priceValue(offer?["price"] ?? product["price"], currency: stringValue(offer?["priceCurrency"] ?? product["priceCurrency"]))
            let description = detailStringValue(product["description"]) ?? ""
            let imageURL = imageURLValue(product["image"], baseURL: baseURL)
            let availability = availabilityValue(offer?["availability"] ?? product["availability"])
            let sourceURL = safeURLValue(product["url"], baseURL: baseURL) ?? baseURL
            return DreamDressCandidate(
                title: title,
                brand: brand,
                category: category,
                price: price,
                details: DreamDressProductDetails.extract(
                    from: "\(title) \(description)",
                    category: category,
                    color: detailStringValue(product["color"]),
                    size: detailStringValue(product["size"]),
                    condition: detailStringValue(product["itemCondition"])
                ),
                imageURL: imageURL,
                availability: availability,
                sourceURL: sourceURL,
                evidenceType: .jsonLD
            )
        }
    }

    private static func collectProducts(from value: Any, into products: inout [[String: Any]]) {
        if let array = value as? [Any] {
            array.forEach { collectProducts(from: $0, into: &products) }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }
        let types: [String]
        if let type = dictionary["@type"] as? String {
            types = [type]
        } else {
            types = dictionary["@type"] as? [String] ?? []
        }
        if types.contains(where: { $0.lowercased() == "product" || $0.lowercased() == "productgroup" }) {
            products.append(dictionary)
        }
        dictionary.values.forEach { collectProducts(from: $0, into: &products) }
    }

    private static func metadataCandidate(in html: String, baseURL: URL) -> DreamDressCandidate? {
        let metadata = metaAttributes(in: html)
        let title = metadata["og:title"] ?? titleValue(in: html)
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sourceURL = safeURLValue(metadata["og:url"], baseURL: baseURL)
            ?? canonicalURL(in: html, baseURL: baseURL)
            ?? baseURL
        let price = priceValue(
            metadata["product:price:amount"],
            currency: metadata["product:price:currency"]
        )
        let decodedTitle = decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return DreamDressCandidate(
            title: decodedTitle,
            brand: metadata["product:brand"] ?? metadata["og:site_name"],
            category: metadata["product:category"],
            price: price,
            details: DreamDressProductDetails.extract(
                from: "\(decodedTitle) \(metadata["og:description"] ?? "")",
                category: metadata["product:category"],
                color: metadata["product:color"],
                size: metadata["product:size"],
                condition: metadata["product:condition"]
            ),
            imageURL: metadataImageURL(metadata, baseURL: baseURL),
            availability: availabilityValue(metadata["product:availability"]),
            sourceURL: sourceURL,
            evidenceType: metadata["og:title"] == nil ? .pageMetadata : .openGraph
        )
    }

    private static func metaAttributes(in html: String) -> [String: String] {
        let tags = captureMatches(#"(?is)<meta\b([^>]+)>"#, in: html)
        var result: [String: String] = [:]
        for tag in tags {
            let attributes = attributes(in: tag)
            guard let key = attributes["property"] ?? attributes["name"],
                  let content = attributes["content"] else { continue }
            result[key.lowercased()] = decodeEntities(content)
        }
        return result
    }

    private static func attributes(in tag: String) -> [String: String] {
        let matches = allMatches(#"(?i)([a-z_:][-a-z0-9_:.]*)\s*=\s*[\"']([^\"']*)[\"']"#, in: tag)
        var result: [String: String] = [:]
        for match in matches where match.count > 2 {
            result[match[1].lowercased()] = match[2]
        }
        return result
    }

    private static func canonicalURL(in html: String, baseURL: URL) -> URL? {
        let tags = captureMatches(#"(?is)<link\b([^>]+)>"#, in: html)
        for tag in tags {
            let attributes = attributes(in: tag)
            if attributes["rel"]?.lowercased().split(separator: " ").contains("canonical") == true,
               let href = attributes["href"] {
                return safeURLValue(href, baseURL: baseURL)
            }
        }
        return nil
    }

    private static func titleValue(in html: String) -> String? {
        guard let value = captureMatches(#"(?is)<title\b[^>]*>(.*?)</title>"#, in: html).first else {
            return nil
        }
        return decodeEntities(value)
    }

    private static func firstOffer(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let array = value as? [[String: Any]] { return array.first }
        if let array = value as? [Any] { return array.compactMap { $0 as? [String: Any] }.first }
        return nil
    }

    private static func brandValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let dictionary = value as? [String: Any] { return stringValue(dictionary["name"]) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return decodeEntities(string).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func detailStringValue(_ value: Any?) -> String? {
        if let value = stringValue(value) { return value }
        if let values = value as? [Any] {
            let joined = values.compactMap(stringValue).joined(separator: ", ")
            return joined.isEmpty ? nil : joined
        }
        if let dictionary = value as? [String: Any] {
            return stringValue(dictionary["name"] ?? dictionary["value"])
        }
        return nil
    }

    private static func priceValue(_ value: Any?, currency: String?) -> String? {
        guard let value = stringValue(value), !value.isEmpty else { return nil }
        let normalizedCurrency = currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedCurrency.map { "\(value) \($0)" } ?? value
    }

    private static func imageURLValue(_ value: Any?, baseURL: URL) -> URL? {
        if let url = safeURLValue(value, baseURL: baseURL) { return url }
        if let values = value as? [Any] {
            return values.lazy.compactMap { imageURLValue($0, baseURL: baseURL) }.first
        }
        if let dictionary = value as? [String: Any] {
            return safeURLValue(dictionary["contentUrl"] ?? dictionary["url"], baseURL: baseURL)
        }
        return nil
    }

    private static func metadataImageURL(_ metadata: [String: String], baseURL: URL) -> URL? {
        safeURLValue(
            metadata["og:image:secure_url"] ?? metadata["og:image"] ?? metadata["og:image:url"] ?? metadata["twitter:image"],
            baseURL: baseURL
        )
    }

    private static func availabilityValue(_ value: Any?) -> DreamDressAvailability {
        guard let value = stringValue(value)?.lowercased() else { return .unknown }
        if value.contains("instock") || value == "in stock" { return .available }
        if value.contains("soldout") || value == "sold out" { return .sold }
        if value.contains("discontinued") { return .delisted }
        if value.contains("outofstock") || value == "out of stock" { return .unavailable }
        return availability(in: value)
    }

    private static func resolvedAvailability(
        _ current: DreamDressAvailability,
        _ page: DreamDressAvailability
    ) -> DreamDressAvailability {
        if page == .sold || page == .delisted { return page }
        return current == .unknown ? page : current
    }

    private static func urlValue(_ value: Any?, baseURL: URL) -> URL? {
        guard let string = stringValue(value), !string.isEmpty else { return nil }
        return URL(string: string, relativeTo: baseURL)?.absoluteURL
    }

    private static func safeURLValue(_ value: Any?, baseURL: URL) -> URL? {
        guard let url = urlValue(value, baseURL: baseURL),
              DreamDressDetectiveService.isAllowedHTTPSURL(url) else { return nil }
        return url
    }

    private static func unique(_ candidates: [DreamDressCandidate]) -> [DreamDressCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    private static func captureMatches(_ pattern: String, in text: String) -> [String] {
        allMatches(pattern, in: text).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private static func replacingMatches(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

struct DreamDressRenderedPage: Sendable {
    let title: String?
    let visibleText: String
    let imageURL: URL?
    let availability: DreamDressAvailability
    let finalURL: URL?

    init(
        title: String?,
        visibleText: String,
        imageURL: URL?,
        availability: DreamDressAvailability,
        finalURL: URL? = nil
    ) {
        self.title = title
        self.visibleText = visibleText
        self.imageURL = imageURL
        self.availability = availability
        self.finalURL = finalURL
    }
}

/// 动态平台只在静态 HTML 缺少图片或状态时渲染；Cookie 仅在 App WebKit 内持久化，不读取 Safari 登录态。
@MainActor
final class DreamDressDynamicPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<DreamDressRenderedPage?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didCapture = false
    private var captureAttempt = 0
    private var usesOCR = true

    static func load(url: URL, usesOCR: Bool = true) async -> DreamDressRenderedPage? {
        let loader = DreamDressDynamicPageLoader()
        loader.usesOCR = usesOCR
        return await loader.load(url: url)
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.networkCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let createdWebView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 900),
            configuration: configuration
        )
        super.init()
        webView = createdWebView
        webView.navigationDelegate = self
        webView.customUserAgent = DreamDressDetectiveService.browserUserAgent
        webView.isUserInteractionEnabled = false
    }

    nonisolated static func renderURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return url }
        if ["goofish.com", "www.goofish.com"].contains(host),
           url.path == "/item",
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           id.allSatisfy(\.isNumber) {
            components.host = "h5.m.goofish.com"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        } else if host == "wiki.smzdm.com" {
            components.host = "wiki.m.smzdm.com"
        }
        return components.url ?? url
    }

    static let networkCaptureScript = #"""
    (() => {
      window.__dreamDressResponses = [];
      const record = value => {
        try {
          const text = typeof value === 'string' ? value : JSON.stringify(value);
          if (text && text.includes('itemDO') && text.length <= 1500000) {
            window.__dreamDressResponses.push(text);
          }
        } catch (_) {}
      };
      const originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = async function(...args) {
          const response = await originalFetch.apply(this, args);
          response.clone().text().then(record).catch(() => {});
          return response;
        };
      }
      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(...args) {
        this.addEventListener('load', function() {
          try { record(this.responseType === 'json' ? this.response : this.responseText); } catch (_) {}
        });
        return originalOpen.apply(this, args);
      };
      XMLHttpRequest.prototype.send = function(...args) {
        return originalSend.apply(this, args);
      };
    })();
    """#

    private func load(url: URL) async -> DreamDressRenderedPage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) {
                webView.frame = CGRect(
                    origin: .zero,
                    size: CGSize(
                        width: max(window.bounds.width, 1024),
                        height: max(window.bounds.height, 900)
                    )
                )
                window.insertSubview(webView, at: 0)
            }
            var request = URLRequest(url: Self.renderURL(for: url))
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            webView.load(request)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.finish(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didCapture else { return }
        didCapture = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.capturePage()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
#if DEBUG
        print("[DreamDressDetective] render_navigation_failed error=\(error.localizedDescription)")
#endif
        finish(nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
#if DEBUG
        print("[DreamDressDetective] render_provisional_failed error=\(error.localizedDescription)")
#endif
        finish(nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame != false,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        guard DreamDressDetectiveService.isAllowedHTTPSURL(url) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    static let pageCaptureScript = #"""
        (() => {
          const clean = value => (value || '').replace(/\s+/g, ' ').trim();
          const visible = element => {
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' &&
              Number(style.opacity || 1) > 0 && rect.width > 1 && rect.height > 1;
          };
          const topLimit = Math.max(window.innerHeight * 1.8, 1400);
          const normalizeURL = value => {
            if (!value) return '';
            if (value.startsWith('//')) return `https:${value}`;
            if (value.startsWith('http://')) return `https://${value.slice(7)}`;
            return value;
          };
          const captured = window.__dreamDressResponses || [];
          let platformItem = null;
          const findItem = value => {
            if (!value || typeof value !== 'object') return null;
            if (value.itemDO && typeof value.itemDO === 'object') return value.itemDO;
            for (const child of Object.values(value)) {
              const found = findItem(child);
              if (found) return found;
            }
            return null;
          };
          for (const raw of captured) {
            try {
              const start = raw.indexOf('{');
              const end = raw.lastIndexOf('}');
              if (start < 0 || end <= start) continue;
              platformItem = findItem(JSON.parse(raw.slice(start, end + 1)));
              if (platformItem) break;
            } catch (_) {}
          }
          const elements = Array.from(document.querySelectorAll('body *')).filter(element => {
            if (!visible(element)) return false;
            const rect = element.getBoundingClientRect();
            return rect.bottom > 0 && rect.top < topLimit;
          });
          const statusPriority = [
            '商品已下架', '已下架', '宝贝不存在', '商品不存在',
            '已售出', '已卖出', '卖掉了', '交易成功',
            '暂时缺货', '已售罄', '无货',
            '立即购买', '立即下单', '我想要', '加入购物车', '在线', '在售'
          ];
          const shortTexts = elements.map(element => clean(element.innerText))
            .filter(text => text.length > 0 && text.length <= 24);
          const status = clean(platformItem?.itemStatusStr) ||
            statusPriority.find(token => shortTexts.some(text => text === token || text.includes(token))) || '';

          const titleCandidates = elements.filter(element => {
            const text = clean(element.innerText);
            if (text.length < 4 || text.length > 180) return false;
            const name = String(element.className || '').toLowerCase();
            return /^H[1-3]$/.test(element.tagName) || name.includes('title');
          }).map(element => {
            const rect = element.getBoundingClientRect();
            const fontSize = Number.parseFloat(getComputedStyle(element).fontSize) || 0;
            return { text: clean(element.innerText), score: fontSize * 10000 + rect.width * rect.height - Math.max(rect.top, 0) };
          }).sort((a, b) => b.score - a.score);

          const imageCandidates = Array.from(document.images).filter(image => {
            if (!visible(image)) return false;
            const rect = image.getBoundingClientRect();
            const source = image.dataset.src || image.dataset.original || image.currentSrc || image.src || '';
            return source.startsWith('https://') && rect.bottom > 0 && rect.top < topLimit &&
              rect.width >= 120 && rect.height >= 120 && image.naturalWidth >= 160 && image.naturalHeight >= 160;
          }).map(image => {
            const rect = image.getBoundingClientRect();
            return {
              url: image.dataset.src || image.dataset.original || image.currentSrc || image.src,
              score: rect.width * rect.height + image.naturalWidth * image.naturalHeight * 0.01 - Math.max(rect.top, 0)
            };
          }).sort((a, b) => b.score - a.score);

          const platformImages = Array.isArray(platformItem?.imageInfos)
            ? platformItem.imageInfos.map(image => normalizeURL(image?.url || image?.imageUrl || '')).filter(Boolean)
            : [];

          return JSON.stringify({
            title: clean(platformItem?.title || platformItem?.itemTitle) || titleCandidates[0]?.text || document.title || '',
            visibleText: clean(document.body?.innerText).slice(0, 120000),
            imageURL: platformImages[0] || normalizeURL(imageCandidates[0]?.url || ''),
            status
          });
        })()
        """#

    private func capturePage() {

        webView.evaluateJavaScript(Self.pageCaptureScript) { [weak self] value, _ in
            guard let self, let page = Self.parseCapture(value, finalURL: webView.url) else {
                self?.finish(nil)
                return
            }
            if page.imageURL == nil, captureAttempt < 5 {
                captureAttempt += 1
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.capturePage()
                }
                return
            }
            guard page.availability == .unknown else {
                finish(page)
                return
            }
            guard usesOCR else {
                finish(page)
                return
            }
            webView.takeSnapshot(with: nil) { [weak self] image, _ in
                guard let self else { return }
                let ocrText = image.map(Self.recognizedText) ?? ""
                finish(DreamDressRenderedPage(
                    title: page.title,
                    visibleText: page.visibleText,
                    imageURL: page.imageURL,
                    availability: DreamDressHTMLParser.availability(in: ocrText),
                    finalURL: page.finalURL
                ))
            }
        }
    }

    static func parseCapture(_ value: Any?, finalURL: URL? = nil) -> DreamDressRenderedPage? {
        guard let json = value as? String,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let imageURL = (object["imageURL"] as? String).flatMap(URL.init(string:)).flatMap {
            DreamDressDetectiveService.isAllowedHTTPSURL($0) ? $0 : nil
        }
        let visibleText = object["visibleText"] as? String ?? ""
        let statusText = object["status"] as? String ?? ""
        let statusAvailability = DreamDressHTMLParser.availability(in: statusText)
        return DreamDressRenderedPage(
            title: (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            visibleText: visibleText,
            imageURL: imageURL,
            availability: statusAvailability == .unknown
                ? DreamDressHTMLParser.availability(in: visibleText)
                : statusAvailability,
            finalURL: finalURL
        )
    }

    private static func recognizedText(in image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func finish(_ page: DreamDressRenderedPage?) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
        continuation.resume(returning: page)
    }
}

final class DreamDressDetectiveService: @unchecked Sendable {
    static let shared = DreamDressDetectiveService()
    nonisolated static let browserUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let maximumResponseBytes = 1_500_000
    private let maximumImageBytes = 12_000_000
    private let cacheFreshness: TimeInterval = 30 * 60
    private let session: URLSession
    private let productImageCache = NSCache<NSURL, UIImage>()

    private struct SourceValidator: Codable, Sendable {
        let url: URL
        let eTag: String?
        let lastModified: String?
        let sourceUpdatedAt: Date?
    }

    private struct CacheEntry: Codable, Sendable {
        let result: DreamDressInvestigationResult
        var lastCheckedAt: Date
        let validator: SourceValidator?
        let nextQueryIndex: Int?
        let didSearchYahoo: Bool?
        let isExhausted: Bool?
    }

    private struct SearchOutcome: Sendable {
        let candidates: [DreamDressCandidate]
        let validator: SourceValidator?
    }

    private struct SearchPage: Sendable {
        let candidates: [DreamDressCandidate]
        let validator: SourceValidator?
        let nextQueryIndex: Int
        let didSearchYahoo: Bool
        let isExhausted: Bool
    }

    private struct CandidateEnrichment: Sendable {
        let allCandidates: [DreamDressCandidate]
        let validCandidates: [DreamDressCandidate]
    }

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 35
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(
            configuration: configuration,
            delegate: DreamDressRedirectDelegate(),
            delegateQueue: nil
        )
        productImageCache.countLimit = 32
    }

    static func validate(_ input: DreamDressDetectiveInput) throws {
        guard input.hasAnyValue else { throw DreamDressDetectiveError.emptyInput }
        let rawURL = input.productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawURL.isEmpty {
            guard let url = productURL(from: rawURL) else { throw DreamDressDetectiveError.invalidURL }
            try validateURL(url)
        }
    }

    nonisolated static func productURL(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let detected = detector?.firstMatch(in: value, range: range)?.url
        let direct = detected ?? URL(string: value.contains("://") ? value : "https://\(value)")
        guard let direct,
              var components = URLComponents(url: direct, resolvingAgainstBaseURL: false) else { return nil }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        return components.url
    }

    nonisolated static func validateURL(_ url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil
        else {
            throw DreamDressDetectiveError.invalidURL
        }
        guard isSafeHost(host) else { throw DreamDressDetectiveError.unsafeURL }
    }

    nonisolated static func isAllowedHTTPSURL(_ url: URL) -> Bool {
        (try? validateURL(url)) != nil
    }

    nonisolated static func cacheKey(for input: DreamDressDetectiveInput) -> String {
        let normalizedURL = productURL(from: input.productURL)?.absoluteString ?? input.productURL
        let normalized = [input.brandName, input.productName, normalizedURL]
            .map(DreamDressProductMatcher.normalizedSearchText)
            .joined(separator: "|")
        return "dream_dress_detective.cache.v3."
            + Data(normalized.utf8).base64EncodedString()
    }

    nonisolated static func isCacheFresh(
        lastCheckedAt: Date,
        now: Date = Date(),
        freshness: TimeInterval = 30 * 60
    ) -> Bool {
        now.timeIntervalSince(lastCheckedAt) < freshness
    }

    private func cachedEntry(forKey key: String) async -> CacheEntry? {
        guard let data = UserDefaults.standard.data(forKey: key),
              var entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else { return nil }
        if Self.isCacheFresh(lastCheckedAt: entry.lastCheckedAt, freshness: cacheFreshness) {
            return entry
        }
        guard let validator = entry.validator,
              await sourceIsUnchanged(validator) else { return nil }
        entry.lastCheckedAt = Date()
        saveCache(entry, forKey: key)
        return entry
    }

    private func saveCache(_ entry: CacheEntry, forKey key: String) {
        // ponytail: per-query UserDefaults cache; add file-backed LRU only if real usage grows enough to matter.
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func sourceIsUnchanged(_ validator: SourceValidator) async -> Bool {
        var request = URLRequest(url: validator.url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let eTag = validator.eTag { request.setValue(eTag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = validator.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        guard validator.eTag != nil || validator.lastModified != nil,
              let (_, response) = try? await data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 304 { return true }
        guard (200..<300).contains(http.statusCode) else { return false }
        return validator.eTag.map { http.value(forHTTPHeaderField: "ETag") == $0 }
            ?? validator.lastModified.map { http.value(forHTTPHeaderField: "Last-Modified") == $0 }
            ?? false
    }

    nonisolated private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }

    func investigate(
        _ input: DreamDressDetectiveInput,
        forceRefresh: Bool = false
    ) async throws -> DreamDressInvestigationResult {
        try await investigatePage(
            input,
            requestedCount: DreamDressPagination.pageSize,
            forceRefresh: forceRefresh
        ).result
    }

    func investigatePage(
        _ input: DreamDressDetectiveInput,
        requestedCount: Int,
        forceRefresh: Bool = false,
        onCandidatesFound: DreamDressCandidateProgress? = nil
    ) async throws -> DreamDressInvestigationPage {
        try Self.validate(input)
        let requestedCount = max(1, requestedCount)
        let cacheKey = Self.cacheKey(for: input)
        let rawURL = input.productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawURL.isEmpty {
            if !forceRefresh, let cached = await cachedEntry(forKey: cacheKey) {
                return DreamDressInvestigationPage(
                    result: cached.result.limited(to: requestedCount, isFromCache: true),
                    hasMore: false
                )
            }
            guard let url = Self.productURL(from: rawURL) else { throw DreamDressDetectiveError.invalidURL }
            let found = unique(try await investigate(url: url, input: input))
            guard !found.isEmpty else { throw DreamDressDetectiveError.noResults }
            await onCandidatesFound?(found)
            let enrichment = await enrichAndValidate(found)
            let now = Date()
            let result = makeResult(
                allCandidates: enrichment.allCandidates,
                validCandidates: enrichment.validCandidates,
                cachedAt: now
            )
            try Task.checkCancellation()
            saveCache(
                CacheEntry(
                    result: result,
                    lastCheckedAt: now,
                    validator: nil,
                    nextQueryIndex: nil,
                    didSearchYahoo: true,
                    isExhausted: true
                ),
                forKey: cacheKey
            )
            return DreamDressInvestigationPage(
                result: result.limited(to: requestedCount, isFromCache: false),
                hasMore: false
            )
        }

        let cached = forceRefresh ? nil : await cachedEntry(forKey: cacheKey)
        if let cached,
           (cached.result.allCandidates.count >= requestedCount || cached.isExhausted == true) {
            return DreamDressInvestigationPage(
                result: cached.result.limited(to: requestedCount, isFromCache: true),
                hasMore: cached.result.allCandidates.count > requestedCount || cached.isExhausted != true
            )
        }

        let previousCandidates = cached?.result.allCandidates ?? []
        let outcome = try await searchCandidates(
            for: input,
            existing: previousCandidates,
            startingAt: cached?.nextQueryIndex ?? 0,
            didSearchYahoo: cached?.didSearchYahoo ?? false,
            minimumCount: requestedCount,
            onCandidatesFound: onCandidatesFound
        )
        let found = unique(outcome.candidates)
        guard !found.isEmpty else { throw DreamDressDetectiveError.noResults }
        let previousValid = cached?.result.validCandidates ?? []
        let previousIDs = Set(previousCandidates.map(\.id))
        let added = await enrichAndValidate(found.filter { !previousIDs.contains($0.id) })
        let enrichedByID = Dictionary(uniqueKeysWithValues: added.allCandidates.map { ($0.id, $0) })
        let enrichedFound = found.map { enrichedByID[$0.id] ?? $0 }
        let valid = unique(previousValid + added.validCandidates)
        let now = Date()
#if DEBUG
        print("[DreamDressDetective] found=\(found.count) valid_images=\(valid.count)")
#endif
        let result = makeResult(
            allCandidates: enrichedFound,
            validCandidates: valid,
            cachedAt: now,
            sourceUpdatedAt: outcome.validator?.sourceUpdatedAt ?? cached?.result.sourceUpdatedAt
        )
        try Task.checkCancellation()
        saveCache(
            CacheEntry(
                result: result,
                lastCheckedAt: now,
                validator: outcome.validator ?? cached?.validator,
                nextQueryIndex: outcome.nextQueryIndex,
                didSearchYahoo: outcome.didSearchYahoo,
                isExhausted: outcome.isExhausted
            ),
            forKey: cacheKey
        )
        return DreamDressInvestigationPage(
            result: result.limited(to: requestedCount, isFromCache: false),
            hasMore: found.count > requestedCount || !outcome.isExhausted
        )
    }

    private func makeResult(
        allCandidates: [DreamDressCandidate],
        validCandidates: [DreamDressCandidate],
        cachedAt: Date,
        sourceUpdatedAt: Date? = nil
    ) -> DreamDressInvestigationResult {
        DreamDressInvestigationResult(
            foundCount: allCandidates.count,
            allCandidates: allCandidates,
            validCandidates: validCandidates.enumerated().sorted {
                ($0.element.availability.sortPriority, $0.offset)
                    < ($1.element.availability.sortPriority, $1.offset)
            }.map(\.element),
            cachedAt: cachedAt,
            sourceUpdatedAt: sourceUpdatedAt,
            isFromCache: false
        )
    }

    private func searchCandidates(
        for input: DreamDressDetectiveInput,
        existing: [DreamDressCandidate],
        startingAt: Int,
        didSearchYahoo: Bool,
        minimumCount: Int,
        onCandidatesFound: DreamDressCandidateProgress?
    ) async throws -> SearchPage {
        var candidates = existing
        let apiKey = AIConfigManager.shared.dsApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        var lastSearchError: Error?
        let queries = Self.searchQueries(for: input)
        var nextQueryIndex = min(max(0, startingAt), queries.count)
        let initialCount = candidates.count
        let pageEndIndex = min(nextQueryIndex + DreamDressPagination.queriesPerPage, queries.count)
        if apiKey?.isEmpty == false {
            while candidates.count < minimumCount, nextQueryIndex < queries.count {
                if nextQueryIndex >= pageEndIndex, candidates.count > initialCount { break }
                let query = queries[nextQueryIndex]
                nextQueryIndex += 1
                do {
                    let previousCount = candidates.count
                    let hits = try await searchProductHits(query: query, apiKey: apiKey!)
                    candidates.append(contentsOf: makeCandidates(from: hits, input: input))
                    candidates = uniqueBySourceURL(candidates)
                    if candidates.count > previousCount {
                        await onCandidatesFound?(candidates)
                    }
                } catch {
                    lastSearchError = error
                }
            }
        } else {
            nextQueryIndex = queries.count
        }

        var didSearchYahoo = didSearchYahoo
        var validator: SourceValidator?
        if candidates.count < minimumCount, nextQueryIndex >= queries.count, !didSearchYahoo {
            didSearchYahoo = true
            let hadAggregatedCandidates = !candidates.isEmpty
            do {
                let previousCount = candidates.count
                let direct = try await yahooAuctionCandidates(for: input)
                candidates.append(contentsOf: direct.candidates)
                candidates = uniqueBySourceURL(candidates)
                if candidates.count > previousCount {
                    await onCandidatesFound?(candidates)
                }
                // A Yahoo validator can only prove a Yahoo-only result unchanged.
                validator = hadAggregatedCandidates ? nil : direct.validator
            } catch {
                lastSearchError = error
            }
        }
#if DEBUG
        print("[DreamDressDetective] accepted=\(candidates.count)")
#endif
        guard !candidates.isEmpty else {
            if let lastSearchError { throw lastSearchError }
            if apiKey?.isEmpty != false {
                throw DreamDressDetectiveError.service("缺少 DS_API_KEY，无法联网搜索商品。")
            }
            throw DreamDressDetectiveError.noResults
        }
        return SearchPage(
            candidates: candidates,
            validator: existing.isEmpty && candidates.count > 0 ? validator : nil,
            nextQueryIndex: nextQueryIndex,
            didSearchYahoo: didSearchYahoo,
            isExhausted: nextQueryIndex >= queries.count && didSearchYahoo
        )
    }

    private func yahooAuctionCandidates(for input: DreamDressDetectiveInput) async throws -> SearchOutcome {
        let rawName = [input.brandName, input.productName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard rawName.range(of: #"[A-Za-z぀-ヿ]"#, options: .regularExpression) != nil else {
            return SearchOutcome(candidates: [], validator: nil)
        }
        let name = DreamDressProductMatcher.searchAliases(for: rawName).first ?? rawName
        var components = URLComponents(string: "https://auctions.yahoo.co.jp/search/search")!
        components.queryItems = [URLQueryItem(name: "p", value: "\(name) (スカート OR ワンピース)")]
        guard let url = components.url else { return SearchOutcome(candidates: [], validator: nil) }
        let page = try await fetch(url: url)
        return SearchOutcome(
            candidates: Array(Self.yahooAuctionCandidates(from: page.text, input: input).prefix(10)),
            validator: page.validator
        )
    }

    nonisolated static func yahooAuctionCandidates(
        from html: String,
        input: DreamDressDetectiveInput
    ) -> [DreamDressCandidate] {
        let pattern = #"data-auction-id="([A-Za-z0-9]+)"[\s\S]{0,1200}?data-auction-title="([^"]+)"[\s\S]{0,1200}?data-auction-img="([^"]+)"[\s\S]{0,1200}?data-auction-price="([0-9]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).compactMap { match in
            func capture(_ index: Int) -> String? {
                guard let range = Range(match.range(at: index), in: html) else { return nil }
                return DreamDressHTMLParser.decodeEntities(String(html[range]))
            }
            guard let id = capture(1), seen.insert(id).inserted,
                  let title = capture(2),
                  let image = capture(3), let imageURL = URL(string: image),
                  let sourceURL = URL(string: "https://auctions.yahoo.co.jp/jp/auction/\(id)")
            else { return nil }
            let price = capture(4).flatMap { $0.isEmpty ? nil : "¥\($0)" }
            let candidate = DreamDressCandidate(
                title: title,
                brand: nil,
                price: price,
                details: DreamDressProductDetails.extract(from: title),
                imageURL: imageURL,
                availability: .unknown,
                sourceURL: sourceURL,
                evidenceType: .webSearch
            )
            return DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: title)
                ? candidate
                : nil
        }.prefix(20).map { $0 }
    }

    private func enrichAndValidate(_ candidates: [DreamDressCandidate]) async -> CandidateEnrichment {
        let staticResults = await withTaskGroup(of: (Int, DreamDressCandidate, Bool).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { [self] in
                    let enriched = if candidate.evidenceType == .renderedPage {
                        candidate
                    } else if let page = try? await fetch(url: candidate.sourceURL) {
                        DreamDressHTMLParser.enrich(candidate, html: page.text, baseURL: page.url)
                    } else {
                        candidate
                    }
                    let imageIsValid = if let imageURL = enriched.imageURL {
                        await productImage(at: imageURL, referer: enriched.sourceURL) != nil
                    } else {
                        false
                    }
                    return (index, enriched, imageIsValid)
                }
            }
            var results: [(Int, DreamDressCandidate, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        var all = staticResults.map { $0.1 }
        var valid = staticResults.filter { $0.2 }.map { $0.1 }
        let validIDs = Set(valid.map(\.id))
        let dynamicCandidates = Array(all.enumerated()
            .filter { _, candidate in
                Self.needsRenderedVerification(
                    candidate,
                    imageIsValid: validIDs.contains(candidate.id)
                )
            })

        for start in stride(from: 0, to: dynamicCandidates.count, by: 2) {
            let end = min(start + 2, dynamicCandidates.count)
            let rendered = await withTaskGroup(of: (Int, DreamDressCandidate)?.self) { group in
                for (index, candidate) in dynamicCandidates[start..<end] {
                    group.addTask {
                        guard let page = await DreamDressDynamicPageLoader.load(
                            url: candidate.sourceURL,
                            usesOCR: false
                        ) else { return nil }
                        return (index, candidate.enrichedFromRenderedPage(
                            imageURL: page.imageURL,
                            availability: page.availability,
                            price: Self.price(in: page.visibleText),
                            details: DreamDressProductDetails.extract(
                                from: "\(page.title ?? candidate.title) \(String(page.visibleText.prefix(2_000)))",
                                category: candidate.category
                            )
                        ))
                    }
                }
                var results: [(Int, DreamDressCandidate)] = []
                for await result in group {
                    if let result { results.append(result) }
                }
                return results
            }
            for (index, enriched) in rendered {
                all[index] = enriched
                guard let imageURL = enriched.imageURL,
                      await productImage(at: imageURL, referer: enriched.sourceURL) != nil else { continue }
                if let validIndex = valid.firstIndex(where: { $0.id == enriched.id }) {
                    valid[validIndex] = enriched
                } else {
                    valid.append(enriched)
                }
            }
        }

        let order = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($0.element.id, $0.offset) })
        return CandidateEnrichment(
            allCandidates: all,
            validCandidates: valid.sorted { order[$0.id, default: .max] < order[$1.id, default: .max] }
        )
    }

    func productImage(at url: URL, referer: URL) async -> UIImage? {
        guard Self.isAllowedHTTPSURL(url) else { return nil }
        if let cached = productImageCache.object(forKey: url as NSURL) { return cached }
        let host = referer.host?.lowercased() ?? ""
        let isGoofish = host == "goofish.com" || host.hasSuffix(".goofish.com")
        let attemptCount = isGoofish ? 3 : 1

        for attempt in 0..<attemptCount {
            guard !Task.isCancelled else { return nil }
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = attempt == 0 ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData
            request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            if attempt > 0 {
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            }
            guard let (data, response) = try? await data(for: request),
                  data.count <= maximumImageBytes,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.mimeType?.lowercased().hasPrefix("image/") == true,
                  let image = UIImage(data: data),
                  image.size.width >= 200,
                  image.size.height >= 200 else { continue }
            if isGoofish, Self.isGoofishBoomPlaceholder(image) { continue }
            productImageCache.setObject(image, forKey: url as NSURL)
            return image
        }
        return nil
    }

    nonisolated static func isGoofishBoomPlaceholder(recognizedStrings: [String]) -> Bool {
        recognizedStrings.contains { value in
            let normalized = value.uppercased().unicodeScalars
                .filter(CharacterSet.alphanumerics.contains)
                .map(String.init)
                .joined()
            return normalized == "BOOM" || normalized == "B00M"
        }
    }

    nonisolated private static func isGoofishBoomPlaceholder(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return isGoofishBoomPlaceholder(recognizedStrings: strings)
    }

    private func enrich(_ candidates: [DreamDressCandidate]) async -> [DreamDressCandidate] {
        var results: [DreamDressCandidate] = []
        for candidate in candidates {
            if let page = try? await fetch(url: candidate.sourceURL) {
                results.append(DreamDressHTMLParser.enrich(candidate, html: page.text, baseURL: page.url))
            } else {
                results.append(candidate)
            }
        }
        return results
    }

    private func investigate(url: URL, input: DreamDressDetectiveInput) async throws -> [DreamDressCandidate] {
        if Self.isProductShortURL(url) {
            guard let rendered = await DreamDressDynamicPageLoader.load(url: url),
                  let title = rendered.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                throw DreamDressDetectiveError.blockedOrRequiresLogin
            }
            let sourceURL = rendered.finalURL.flatMap {
                Self.isAllowedHTTPSURL($0) ? $0 : nil
            } ?? url
            let candidate = DreamDressCandidate(
                title: title,
                brand: nonEmpty(input.brandName),
                price: Self.price(in: rendered.visibleText),
                details: DreamDressProductDetails.extract(
                    from: "\(title) \(String(rendered.visibleText.prefix(2_000)))"
                ),
                imageURL: rendered.imageURL,
                availability: rendered.availability,
                sourceURL: sourceURL,
                evidenceType: .renderedPage
            )
            guard DreamDressProductMatcher.accepts(
                candidate,
                input: input,
                pageEvidence: rendered.visibleText
            ) else { throw DreamDressDetectiveError.noResults }
            return [candidate]
        }

        let page = try await fetch(url: url)
        let parsed = DreamDressHTMLParser.parse(html: page.text, baseURL: page.url)
        let pageEvidence = DreamDressHTMLParser.visibleEvidence(from: page.text)
        let structured = parsed.filter {
            $0.evidenceType != .pageMetadata
                && DreamDressProductMatcher.accepts($0, input: input, pageEvidence: pageEvidence)
        }
        if !structured.isEmpty { return await enrich(structured) }

        guard page.isHTML else { throw DreamDressDetectiveError.noResults }
            let rendered = Self.isSearchResultURL(url)
                ? await DreamDressDynamicPageLoader.load(url: url)
                : nil
        if let rendered,
           let title = rendered.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            let renderedCandidate = DreamDressCandidate(
                title: title,
                brand: nonEmpty(input.brandName),
                price: Self.price(in: rendered.visibleText),
                details: DreamDressProductDetails.extract(
                    from: "\(title) \(String(rendered.visibleText.prefix(2_000)))"
                ),
                imageURL: rendered.imageURL,
                availability: rendered.availability,
                sourceURL: page.url,
                evidenceType: .renderedPage
            )
            if DreamDressProductMatcher.accepts(
                renderedCandidate,
                input: input,
                pageEvidence: rendered.visibleText
            ) {
                return [renderedCandidate]
            }
        }
        let evidence = String(
            (page.metadata + "\n" + (rendered?.visibleText ?? pageEvidence))
                .prefix(12_000)
        )
        let localParse = SkirtMarketImportParser.localParse(evidence)
        let deepSeekInput = SkirtMarketDeepSeekInput(
            mode: SkirtMarketDeepSeekImportMode.link.rawValue,
            platformHint: page.url.host ?? "unknown",
            sourceURL: page.url.absoluteString,
            keyword: [input.brandName, input.productName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            capturedAt: SkirtMarketImportParser.isoString(),
            rawText: evidence,
            localParse: localParse
        )

        do {
            let result = try await SkirtMarketDeepSeekImportService.shared.analyze(input: deepSeekInput)
            let candidates = result.items.prefix(5).compactMap { item -> DreamDressCandidate? in
                guard DreamDressProductMatcher.acceptsAIItem(
                    isLolitaRelated: item.isLolitaRelated,
                    category: item.category
                ) else { return nil }
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let event = item.priceEvents.first(where: { $0.kind == "current" }) ?? item.priceEvents.first
                let price = event?.amount.map { amount in
                    let value = amount.rounded() == amount ? String(Int(amount)) : String(amount)
                    return event?.currency.map { "\(value) \($0)" } ?? value
                }
                let candidate = DreamDressCandidate(
                    title: title,
                    brand: item.brand,
                    category: item.category,
                    price: price,
                    details: DreamDressProductDetails.extract(
                        from: "\(title) \(evidence)",
                        category: item.category,
                        color: item.color,
                        size: item.size,
                        condition: item.condition
                    ),
                    imageURL: rendered?.imageURL ?? parsed.compactMap(\.imageURL).first,
                    availability: rendered?.availability == .unknown
                        ? parsed.map(\.availability).first(where: { $0 != .unknown }) ?? .unknown
                        : rendered?.availability ?? .unknown,
                    sourceURL: page.url,
                    evidenceType: .aiStructured
                )
                guard DreamDressProductMatcher.accepts(
                    candidate,
                    input: input,
                    pageEvidence: evidence
                ) else { return nil }
                return candidate
            }
            guard !candidates.isEmpty else { throw DreamDressDetectiveError.noResults }
            return Array(candidates)
        } catch let error as DreamDressDetectiveError {
            throw error
        } catch {
            throw DreamDressDetectiveError.service(error.localizedDescription)
        }
    }

    private struct FetchedPage {
        let url: URL
        let text: String
        let isHTML: Bool
        let metadata: String
        let validator: SourceValidator
    }

    private func fetch(url: URL) async throws -> FetchedPage {
        try Self.validateURL(url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DreamDressDetectiveError.service("商品页面没有返回有效 HTTP 响应。")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if [401, 403, 429].contains(httpResponse.statusCode) {
                throw DreamDressDetectiveError.blockedOrRequiresLogin
            }
            throw DreamDressDetectiveError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= maximumResponseBytes else { throw DreamDressDetectiveError.responseTooLarge }
        guard let finalURL = response.url else { throw DreamDressDetectiveError.invalidURL }
        try Self.validateURL(finalURL)

        let mime = (httpResponse.mimeType ?? "").lowercased()
        let isHTML = ["text/html", "application/xhtml+xml"].contains(mime)
        let isJSON = ["application/json", "application/ld+json"].contains(mime)
        if !isHTML && !isJSON {
            let prefix = String(decoding: data.prefix(256), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard prefix.hasPrefix("<") || prefix.hasPrefix("{") || prefix.hasPrefix("[") else {
                throw DreamDressDetectiveError.unsupportedContentType
            }
        }
        let text = String(decoding: data, as: UTF8.self)
        let lowered = text.lowercased()
        if [
            "captcha", "verify you are human", "需要登录", "请先登录", "robot check",
            "aliyun_waf_aa", "aliyunwaf_", "x-waf-captcha", "/probe.js"
        ].contains(where: lowered.contains) {
            throw DreamDressDetectiveError.blockedOrRequiresLogin
        }
        return FetchedPage(
            url: finalURL,
            text: text,
            isHTML: isHTML || (!isJSON && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")),
            metadata: String(text.prefix(2_000)),
            validator: SourceValidator(
                url: finalURL,
                eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified"),
                sourceUpdatedAt: Self.httpDate(httpResponse.value(forHTTPHeaderField: "Last-Modified"))
            )
        )
    }

    nonisolated private struct WebSearchHit: Sendable {
        let title: String
        let url: URL
    }

    nonisolated static func searchQueries(for input: DreamDressDetectiveInput) -> [String] {
        var seen = Set<String>()
        let brand = input.brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = input.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        var values: [(value: String, includeAliases: Bool)] = []
        if !brand.isEmpty, !product.isEmpty {
            values.append(("\(brand) \(product)", false))
        }
        values.append(contentsOf: [
            (value: brand, includeAliases: true),
            (value: product, includeAliases: true)
        ].filter { !$0.value.isEmpty })
        return values.flatMap { item -> [String] in
            let variants = item.includeAliases ? queryVariants(for: item.value) : [item.value]
            let terms = variants.map { variant in
                variant.contains(where: \.isWhitespace) ? "\"\(variant)\"" : variant
            }
            guard !terms.isEmpty else { return [] }
            let expression = terms.count == 1 ? terms[0] : "(\(terms.joined(separator: " OR ")))"
            return [
                "\(expression) 裙 连衣裙 スカート ワンピース 二手 中古",
                "\(expression) 淘宝 天猫 商品 价格 详情 裙",
                "\(expression) 闲鱼 goofish 二手 在售",
                "site:goofish.com/item \(expression)",
                "\(expression) 小红书 出物 穿搭 裙",
                "\(expression) 抖音商城 今日头条 商品 价格 裙",
                "\(expression) Mercari メルカリ 中古 スカート ワンピース",
                "\(expression) Yahoo!オークション ヤフオク 中古 スカート ワンピース",
                "\(expression) 楽天市場 公式 通販 スカート ワンピース"
            ]
        }.filter { seen.insert($0.lowercased()).inserted }
    }

    nonisolated static func queryVariants(for value: String) -> [String] {
        let original = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !original.isEmpty else { return [] }
        let compact = replacingMatches(#"[\s_\-]+"#, in: original, with: "")
        let camelSpaced = replacingMatches(#"([a-z0-9])([A-Z])"#, in: original, with: "$1 $2")
        let mixedSpaced = replacingMatches(
            #"(?<=[\p{Han}])(?=[A-Za-z0-9])|(?<=[A-Za-z0-9])(?=[\p{Han}])"#,
            in: original,
            with: " "
        )
        var seen = Set<String>()
        return ([original, compact, camelSpaced, mixedSpaced] + DreamDressProductMatcher.searchAliases(for: original))
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(4)
            .map { String($0.prefix(80)) }
    }

    nonisolated static func price(in text: String) -> String? {
        for pattern in [
            #"(?:JP¥|¥|￥|RMB|CNY|JPY)\s*[0-9][0-9,.]*"#,
            #"[0-9][0-9,.]*\s*(?:元|円|CNY|JPY)"#
        ] {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
                continue
            }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    nonisolated static func priceAmount(_ value: String) -> Double? {
        guard let range = value.range(of: #"\d[\d,.]*"#, options: .regularExpression) else { return nil }
        return Double(String(value[range]).replacingOccurrences(of: ",", with: ""))
    }

    nonisolated static func priceCurrency(
        for value: String,
        sourceURL: URL
    ) -> ClothingPriceCurrency {
        let uppercased = value.uppercased()
        if uppercased.contains("JPY") || value.contains("日元") || value.contains("円") || value.contains("JP¥") {
            return .jpy
        }
        if uppercased.contains("CNY") || uppercased.contains("RMB") || value.contains("人民币")
            || value.contains("元") || value.contains("￥") {
            return .cny
        }
        let host = sourceURL.host?.lowercased() ?? ""
        return host.hasSuffix(".jp")
            || host.contains("yahoo.co.jp")
            || host.contains("rakuten.co.jp")
            || host.contains("mercari.com")
            ? .jpy
            : .cny
    }

    nonisolated private func searchProductHits(query: String, apiKey: String) async throws -> [WebSearchHit] {
        let prompt = """
        请用 web_search 搜索“\(query)”。
        优先返回近期更新、当前在售、带公开商品主图的原平台 HTTPS 商品详情页；尽可能返回多个不同商品，不要返回文章、搜索列表或猜测网址。
        """
        let requestBody: [String: Any] = [
            "model": "deepseek-v4-flash",
            "max_tokens": 256,
            "stream": false,
            "thinking": ["type": "disabled"],
            "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 1]],
            "messages": [["role": "user", "content": prompt]]
        ]
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/anthropic/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        let (data, response) = try await searchData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw DreamDressDetectiveError.invalidCrawlPlan }
        guard httpResponse.statusCode == 200 else { throw DreamDressDetectiveError.service("联网搜索服务返回 HTTP \(httpResponse.statusCode)。") }
        guard data.count <= maximumResponseBytes else { throw DreamDressDetectiveError.responseTooLarge }
        let rejectedTitles = ["投诉", "退款", "退定金", "百科", "新闻", "地图", "攻略", "品牌介绍", "搜索列表"]
        let hits = Self.webSearchHits(from: data)
            .filter { hit in !rejectedTitles.contains(where: hit.title.contains) }
            .map { WebSearchHit(title: $0.title, url: $0.url) }
#if DEBUG
        print("[DreamDressDetective] query=\(query) response_bytes=\(data.count) product_hits=\(hits.count)")
#endif
        return hits
    }

    nonisolated static func webSearchURLs(from data: Data) -> [URL] {
        webSearchHits(from: data).map(\.url)
    }

    nonisolated private static func webSearchHits(from data: Data) -> [(title: String, url: URL)] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var results: [(title: String, url: URL)] = []
        collectWebSearchResults(from: object, into: &results)
        var seen = Set<String>()
        return results.compactMap { result in
            let url = canonicalSearchResultURL(result.url)
            guard isSearchResultURL(url),
                  seen.insert(url.absoluteString).inserted
            else { return nil }
            return (result.title, url)
        }
    }

    nonisolated private static func canonicalSearchResultURL(_ url: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return url }
        let path = components.path.lowercased()
        let itemCode = components.queryItems?
            .first(where: { ["itemcode", "aid"].contains($0.name.lowercased()) })?.value ?? ""
        let validItemCode = itemCode.range(of: #"^[A-Za-z][0-9]+$"#, options: .regularExpression) != nil

        if host == "zenmarket.jp", validItemCode {
            if path.hasSuffix("/mercariproduct.aspx") {
                return URL(string: "https://jp.mercari.com/item/\(itemCode)")!
            }
            if path.hasSuffix("/auction.aspx") {
                return URL(string: "https://auctions.yahoo.co.jp/jp/auction/\(itemCode)")!
            }
        }
        if ["j-subculture.com", "www.j-subculture.com"].contains(host),
           let rawTarget = components.queryItems?.first(where: { $0.name == "shopping_url" })?.value,
           let target = URL(string: rawTarget),
           isSearchResultURL(target) {
            return target
        }
        if ["letao.com.hk", "www.letao.com.hk"].contains(host), validItemCode {
            if components.queryItems?.first(where: { $0.name == "domain" })?.value == "mercari" {
                return URL(string: "https://jp.mercari.com/item/\(itemCode)")!
            }
            if path.hasSuffix("/auctions/item.php") {
                return URL(string: "https://auctions.yahoo.co.jp/jp/auction/\(itemCode)")!
            }
        }
        return url
    }

    nonisolated private static func collectWebSearchResults(
        from value: Any,
        into results: inout [(title: String, url: URL)]
    ) {
        if let array = value as? [Any] {
            array.forEach { collectWebSearchResults(from: $0, into: &results) }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }
        if dictionary["type"] as? String == "web_search_result",
           let title = dictionary["title"] as? String,
           let rawURL = dictionary["url"] as? String,
           let url = URL(string: rawURL) {
            results.append((title, url))
        }
        dictionary.values.forEach { collectWebSearchResults(from: $0, into: &results) }
    }

    nonisolated static func isCommercePlatformURL(_ url: URL) -> Bool {
        guard isAllowedHTTPSURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased()
        else { return false }
        let path = components.path.lowercased()
        let segments = path.split(separator: "/").map(String.init)
        let numericID: (String) -> Bool = { name in
            guard let value = components.queryItems?
                .first(where: { $0.name.lowercased() == name.lowercased() })?.value,
                  !value.isEmpty else { return false }
            return value.allSatisfy { $0.isASCII && $0.isNumber }
        }

        if host == "item.taobao.com" || host == "detail.tmall.com" {
            return path == "/item.htm" && numericID("id")
        }
        if host == "goofish.com" || host == "www.goofish.com" {
            return path == "/item" && numericID("id")
        }
        if host == "xiaohongshu.com" || host == "www.xiaohongshu.com" {
            let noteID = segments.last ?? ""
            let validID = noteID.count == 24 && noteID.allSatisfy { $0.isHexDigit }
            return validID && (segments.dropLast() == ["discovery", "item"] || segments.dropLast() == ["explore"])
        }
        if host == "www.douyin.com" {
            return segments.count == 2
                && ["video", "note", "shipin"].contains(segments[0])
                && segments[1].allSatisfy(\.isNumber)
        }
        if host == "haohuo.jinritemai.com" {
            return (path == "/views/product/item2" && numericID("id"))
                || (path == "/ecommerce/trade/detail/index.html" && (numericID("id") || numericID("product_id")))
        }
        if host == "weidian.com" || host == "www.weidian.com" {
            return path == "/item.html" && numericID("itemID")
        }
        return false
    }

    nonisolated static func isSearchResultURL(_ url: URL) -> Bool {
        if isCommercePlatformURL(url) { return true }
        guard isAllowedHTTPSURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return false }
        let path = components.path.lowercased()
        let segments = path.split(separator: "/")
        if host == "wiki.smzdm.com" {
            return segments.count == 2 && segments[0] == "p" && !segments[1].isEmpty
        }
        if host == "qiandao.com" || host == "www.qiandao.com" {
            guard path == "/spu",
                  let id = components.queryItems?.first(where: { $0.name == "id" })?.value
            else { return false }
            return !id.isEmpty && id.allSatisfy(\.isNumber)
        }
        if host == "lolitalibrary.com" || host == "www.lolitalibrary.com" {
            return segments.count == 3
                && segments[0] == "library"
                && segments[1] == "detail"
                && segments[2].allSatisfy(\.isNumber)
        }
        if host == "pinkhouse-webshop.jp" {
            return segments.count >= 4 && segments.prefix(2) == ["item", "pinkhouse"]
        }
        if host == "jp.mercari.com" {
            return segments.count == 2 && segments[0] == "item" && !segments[1].isEmpty
        }
        if host == "item.rakuten.co.jp" {
            return segments.count == 2 && segments.allSatisfy { !$0.isEmpty }
        }
        if host == "auctions.yahoo.co.jp" {
            return segments.count == 3 && segments.prefix(2) == ["jp", "auction"] && !segments[2].isEmpty
        }
        if host == "paypayfleamarket.yahoo.co.jp" {
            return segments.count == 2 && segments[0] == "item" && !segments[1].isEmpty
        }
        if host == "wunderwelt.jp" || host == "www.wunderwelt.jp" {
            return segments.count == 2 && segments[0] == "products" && !segments[1].isEmpty
        }
        return false
    }

    nonisolated static func isProductShortURL(_ url: URL) -> Bool {
        guard isAllowedHTTPSURL(url), let host = url.host?.lowercased() else { return false }
        return ["m.tb.cn", "e.tb.cn", "tb.cn", "xhslink.com", "v.douyin.com"].contains(host)
    }

    nonisolated static func needsRenderedVerification(
        _ candidate: DreamDressCandidate,
        imageIsValid: Bool
    ) -> Bool {
        candidate.evidenceType != .renderedPage
            && isSearchResultURL(candidate.sourceURL)
            && (!imageIsValid || candidate.imageURL == nil || candidate.price == nil)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw DreamDressDetectiveError.requestTimedOut
        }
    }

    nonisolated private func searchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await URLSession.shared.data(for: request) }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw DreamDressDetectiveError.requestTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw DreamDressDetectiveError.requestTimedOut
            }
            return result
        }
    }

    nonisolated private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private func makeCandidates(
        from hits: [WebSearchHit],
        input: DreamDressDetectiveInput
    ) -> [DreamDressCandidate] {
        let inputBrand = nonEmpty(input.brandName)
        return hits.compactMap { hit in
            let candidate = DreamDressCandidate(
                title: hit.title,
                brand: inputBrand.flatMap {
                    DreamDressProductMatcher.normalizedSearchText(hit.title)
                        .contains(DreamDressProductMatcher.normalizedSearchText($0)) ? $0 : nil
                },
                price: Self.price(in: hit.title),
                details: DreamDressProductDetails.extract(from: hit.title),
                availability: DreamDressHTMLParser.availability(in: hit.title),
                sourceURL: hit.url,
                evidenceType: .webSearch
            )
            return DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: hit.title)
                ? candidate
                : nil
        }
    }

    nonisolated private func unique(_ candidates: [DreamDressCandidate]) -> [DreamDressCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    nonisolated private func uniqueBySourceURL(_ candidates: [DreamDressCandidate]) -> [DreamDressCandidate] {
        var seen = Set<URL>()
        return candidates.filter { seen.insert($0.sourceURL).inserted }
    }

    nonisolated private static func isSafeHost(_ host: String) -> Bool {
        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        let blockedNames = [
            "localhost", "localhost.localdomain", "metadata.google.internal",
            "metadata", "instance-data", "host.docker.internal"
        ]
        guard !blockedNames.contains(normalizedHost),
              !normalizedHost.hasSuffix(".localhost"),
              !normalizedHost.hasSuffix(".local"),
              !normalizedHost.hasSuffix(".internal") else { return false }
        if normalizedHost.contains(":") || normalizedHost.allSatisfy({ $0.isNumber || $0 == "." }) {
            return false
        }
        let octets = normalizedHost.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return true }
        let values = octets.compactMap { UInt8($0) }
        let first = values[0]
        let second = values[1]
        if first == 0 || first == 10 || first == 127 || first == 169 && second == 254 || first == 192 && second == 168 {
            return false
        }
        if first == 172 && (16...31).contains(second) { return false }
        if first == 100 && (64...127).contains(second) { return false }
        return true
    }

    nonisolated private static func replacingMatches(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}

private final class DreamDressRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              DreamDressDetectiveService.isAllowedHTTPSURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
