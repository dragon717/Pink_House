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

nonisolated enum DreamDressEvidenceType: String, Equatable, Sendable {
    case webSearch = "平台搜索"
    case jsonLD = "JSON-LD Product"
    case openGraph = "OpenGraph"
    case pageMetadata = "页面标题"
    case renderedPage = "动态页面"
    case aiStructured = "DeepSeek 结构化"
}

nonisolated enum DreamDressAvailability: String, Equatable, Sendable {
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

nonisolated struct DreamDressCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let brand: String?
    let category: String?
    let price: String?
    let imageURL: URL?
    let availability: DreamDressAvailability
    let sourceURL: URL
    let evidenceType: DreamDressEvidenceType

    init(
        title: String,
        brand: String?,
        category: String? = nil,
        price: String?,
        imageURL: URL? = nil,
        availability: DreamDressAvailability = .unknown,
        sourceURL: URL,
        evidenceType: DreamDressEvidenceType
    ) {
        self.title = title
        self.brand = brand
        self.category = category
        self.price = price
        self.imageURL = imageURL
        self.availability = availability
        self.sourceURL = sourceURL
        self.evidenceType = evidenceType
        id = "\(title.lowercased())|\(sourceURL.absoluteString)"
    }

    func enriched(imageURL: URL?, availability: DreamDressAvailability) -> Self {
        Self(
            title: title,
            brand: brand,
            category: category,
            price: price,
            imageURL: self.imageURL ?? imageURL,
            availability: availability,
            sourceURL: sourceURL,
            evidenceType: evidenceType
        )
    }

    func enrichedFromRenderedPage(imageURL: URL?, availability: DreamDressAvailability) -> Self {
        Self(
            title: title,
            brand: brand,
            category: category,
            price: price,
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
            return "商品链接格式无效，请填写完整的 HTTPS 链接。"
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

enum DreamDressProductMatcher {
    private static let allowedAICategories: Set<String> = [
        "jsk", "op", "sk", "blouse", "accessory", "bag", "shoes", "socks", "ribbon", "headdress"
    ]
    private static let productTerms = [
        "连衣裙", "連衣裙", "吊带裙", "吊帶裙", "半身裙", "裙装", "裙裝", "洋装", "洋裝",
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
        "juliette et justine", "wunderwelt", "innocent world", "victorian maiden"
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
        let hasProductSignal = productTerms.contains(where: productText.contains)
            || !productWords.isDisjoint(with: productTokens)
            || containsLolitaCategoryToken(in: productText)
            || candidate.evidenceType == .webSearch && lolitaTerms.contains(where: productText.contains)
        guard hasProductSignal else { return false }

        let pageText = pageEvidence.lowercased()
        let pageWords = Set(pageText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let pageHasProduct = productTerms.contains(where: pageText.contains)
            || !pageWords.isDisjoint(with: productTokens)
            || containsLolitaCategoryToken(in: pageText)
            || candidate.evidenceType == .webSearch && lolitaTerms.contains(where: pageText.contains)
        let pageHasLolita = lolitaTerms.contains(where: pageText.contains)
            || containsLolitaCategoryToken(in: pageText)
            || knownLolitaBrands.contains(where: pageText.contains)
        guard pageHasProduct, pageHasLolita else { return false }

        let hints = [input.brandName, input.productName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return hints.isEmpty || hints.contains(where: pageText.contains)
    }

    private static func containsLolitaCategoryToken(in text: String) -> Bool {
        text.range(of: #"(?<![a-z])(?:jsk|op|sk)(?![a-z])"#, options: .regularExpression) != nil
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
        let parsedImageURL = parsed.compactMap(\.imageURL).first
        let parsedAvailability = parsed
            .map(\.availability)
            .first(where: { $0 != .unknown }) ?? availability(in: visibleEvidence(from: html))
        return candidate.enriched(
            imageURL: parsedImageURL,
            availability: resolvedAvailability(candidate.availability, parsedAvailability)
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
            let imageURL = imageURLValue(product["image"], baseURL: baseURL)
            let availability = availabilityValue(offer?["availability"] ?? product["availability"])
            let sourceURL = safeURLValue(product["url"], baseURL: baseURL) ?? baseURL
            return DreamDressCandidate(
                title: title,
                brand: brand,
                category: category,
                price: price,
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
        return DreamDressCandidate(
            title: decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines),
            brand: metadata["product:brand"] ?? metadata["og:site_name"],
            category: metadata["product:category"],
            price: price,
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

    private static func decodeEntities(_ value: String) -> String {
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
}

/// 动态平台只在静态 HTML 缺少图片或状态时渲染；Cookie 仅在 App WebKit 内持久化，不读取 Safari 登录态。
@MainActor
final class DreamDressDynamicPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<DreamDressRenderedPage?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didCapture = false
    private var captureAttempt = 0

    static func load(url: URL) async -> DreamDressRenderedPage? {
        let loader = DreamDressDynamicPageLoader()
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
        webView.isUserInteractionEnabled = false
    }

    nonisolated static func renderURL(for url: URL) -> URL {
        guard ["goofish.com", "www.goofish.com"].contains(url.host?.lowercased() ?? ""),
              url.path == "/item",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value,
              id.allSatisfy(\.isNumber)
        else { return url }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "h5.m.goofish.com"
        components.path = "/item"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url ?? url
    }

    private static let networkCaptureScript = #"""
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
            request.timeoutInterval = 75
            webView.load(request)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(75))
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

    private static let pageCaptureScript = #"""
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
            guard let self, let page = Self.parseCapture(value) else {
                self?.finish(nil)
                return
            }
            if (page.imageURL == nil || page.availability == .unknown), captureAttempt < 36 {
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
            webView.takeSnapshot(with: nil) { [weak self] image, _ in
                guard let self else { return }
                let ocrText = image.map(Self.recognizedText) ?? ""
                finish(DreamDressRenderedPage(
                    title: page.title,
                    visibleText: page.visibleText,
                    imageURL: page.imageURL,
                    availability: DreamDressHTMLParser.availability(in: ocrText)
                ))
            }
        }
    }

    private static func parseCapture(_ value: Any?) -> DreamDressRenderedPage? {
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
                : statusAvailability
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

    private let maximumResponseBytes = 1_500_000
    private let session: URLSession

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
    }

    static func validate(_ input: DreamDressDetectiveInput) throws {
        guard input.hasAnyValue else { throw DreamDressDetectiveError.emptyInput }
        let rawURL = input.productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawURL.isEmpty {
            guard let url = URL(string: rawURL) else { throw DreamDressDetectiveError.invalidURL }
            try validateURL(url)
        }
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

    func investigate(_ input: DreamDressDetectiveInput) async throws -> [DreamDressCandidate] {
        try Self.validate(input)
        let rawURL = input.productURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawURL.isEmpty {
            guard let url = URL(string: rawURL) else { throw DreamDressDetectiveError.invalidURL }
            return try await investigate(url: url, input: input)
        }

        let hits = try await searchProductHits(for: input)
        let candidates = hits.compactMap { hit -> DreamDressCandidate? in
            let inputBrand = nonEmpty(input.brandName)
            let candidate = DreamDressCandidate(
                title: hit.title,
                brand: inputBrand.flatMap { hit.title.localizedCaseInsensitiveContains($0) ? $0 : nil },
                price: nil,
                availability: DreamDressHTMLParser.availability(in: hit.title),
                sourceURL: hit.url,
                evidenceType: .webSearch
            )
            return DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: hit.title)
                ? candidate
                : nil
        }
#if DEBUG
        print("[DreamDressDetective] platform_hits=\(hits.count) accepted=\(candidates.count)")
#endif
        guard !candidates.isEmpty else { throw DreamDressDetectiveError.noResults }
        let enriched = await enrich(Array(unique(candidates).prefix(5)))
        return enriched.enumerated().sorted {
            ($0.element.availability.sortPriority, $0.offset)
                < ($1.element.availability.sortPriority, $1.offset)
        }.map(\.element)
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
        let page = try await fetch(url: url)
        let parsed = DreamDressHTMLParser.parse(html: page.text, baseURL: page.url)
        let pageEvidence = DreamDressHTMLParser.visibleEvidence(from: page.text)
        let structured = parsed.filter {
            $0.evidenceType != .pageMetadata
                && DreamDressProductMatcher.accepts($0, input: input, pageEvidence: pageEvidence)
        }
        if !structured.isEmpty { return await enrich(structured) }

        guard page.isHTML else { throw DreamDressDetectiveError.noResults }
        let rendered = Self.isCommercePlatformURL(url)
            ? await DreamDressDynamicPageLoader.load(url: url)
            : nil
        if let rendered,
           let title = rendered.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            let renderedCandidate = DreamDressCandidate(
                title: title,
                brand: nonEmpty(input.brandName),
                price: nil,
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
    }

    private func fetch(url: URL) async throws -> FetchedPage {
        try Self.validateURL(url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
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
        if ["captcha", "verify you are human", "需要登录", "请先登录", "robot check"].contains(where: lowered.contains) {
            throw DreamDressDetectiveError.blockedOrRequiresLogin
        }
        return FetchedPage(
            url: finalURL,
            text: text,
            isHTML: isHTML || (!isJSON && text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")),
            metadata: String(text.prefix(2_000))
        )
    }

    private struct WebSearchHit {
        let title: String
        let url: URL
    }

    private func searchProductHits(for input: DreamDressDetectiveInput) async throws -> [WebSearchHit] {
        guard let apiKey = AIConfigManager.shared.dsApiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw DreamDressDetectiveError.service("缺少 DS_API_KEY，无法联网搜索商品。")
        }
        let brand = nonEmpty(input.brandName) ?? ""
        let product = nonEmpty(input.productName) ?? ""
        if !brand.isEmpty, !product.isEmpty {
            let brandHits = try? await resilientSearchProductHits(query: brand, apiKey: apiKey)
            if let brandHits, !brandHits.isEmpty { return brandHits }
            return try await resilientSearchProductHits(query: product, apiKey: apiKey)
        }
        return try await resilientSearchProductHits(query: brand.isEmpty ? product : brand, apiKey: apiKey)
    }

    private func resilientSearchProductHits(query: String, apiKey: String) async throws -> [WebSearchHit] {
        let hits = try await searchProductHits(query: query, apiKey: apiKey)
        if !hits.isEmpty { return hits }
        return try await searchProductHits(query: "\(query) 闲鱼 洛丽塔", apiKey: apiKey)
    }

    private func searchProductHits(query: String, apiKey: String) async throws -> [WebSearchHit] {
        let prompt = """
        请用 web_search 搜索“\(query) site:goofish.com/item”。
        只查真实商品或出售帖，不要猜测网址；调用方会直接读取搜索工具结果。
        """
        let requestBody: [String: Any] = [
            "model": "deepseek-v4-flash",
            "max_tokens": 1_000,
            "stream": false,
            "thinking": ["type": "disabled"],
            "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 3]],
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
        print("[DreamDressDetective] response_bytes=\(data.count) commerce_hits=\(hits.count)")
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
        return results.filter { result in
            guard isCommercePlatformURL(result.url),
                  seen.insert(result.url.absoluteString).inserted
            else { return false }
            return true
        }
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
                && ["video", "note"].contains(segments[0])
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

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw DreamDressDetectiveError.requestTimedOut
        }
    }

    private func searchData(for request: URLRequest) async throws -> (Data, URLResponse) {
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

    private func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func unique(_ candidates: [DreamDressCandidate]) -> [DreamDressCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
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
