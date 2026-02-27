//
//  WebScraperService.swift
//  裙子股市 - 数据抓取服务
//
//  实现各平台的数据抓取，包含反爬策略
//

import Foundation

/// 抓取结果
enum ScrapingResult {
    case success([LolitaItem])
    case failure(ScrapingError)
    case rateLimited(retryAfter: TimeInterval)
}

/// 抓取错误类型
enum ScrapingError: Error {
    case invalidURL
    case networkError(Error)
    case parsingError(String)
    case blocked(String)
    case captchaRequired
    case loginRequired
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .parsingError(let message):
            return "解析错误: \(message)"
        case .blocked(let reason):
            return "被阻止: \(reason)"
        case .captchaRequired:
            return "需要验证码"
        case .loginRequired:
            return "需要登录"
        case .unknown:
            return "未知错误"
        }
    }
}

/// 网页抓取服务 - 带反爬策略
@MainActor
final class WebScraperService {
    static let shared = WebScraperService()
    
    // MARK: - 配置
    
    /// 请求间隔（秒）- 避免请求过快
    private let requestInterval: TimeInterval = 3.0
    
    /// 最大重试次数
    private let maxRetries = 3
    
    /// User-Agent池
    private let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    ]
    
    /// 上次请求时间
    private var lastRequestTime: Date?
    
    /// 会话配置
    private var session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        // 使用系统默认的Cookie管理
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 主入口
    
    /// 抓取指定平台的搜索结果
    func scrapeSearchResults(
        platform: PlatformType,
        keyword: String,
        page: Int = 1
    ) async -> ScrapingResult {
        // 遵守请求间隔
        await respectRateLimit()
        
        switch platform {
        case .xianyu:
            return await scrapeXianyu(keyword: keyword, page: page)
        case .xiaohongshu:
            return await scrapeXiaohongshu(keyword: keyword, page: page)
        case .taobao:
            return await scrapeTaobao(keyword: keyword, page: page)
        case .weidian:
            return await scrapeWeidian(keyword: keyword, page: page)
        case .other:
            return .failure(.unknown)
        }
    }
    
    /// 抓取商品详情
    func scrapeItemDetail(
        platform: PlatformType,
        itemId: String,
        url: String
    ) async -> ScrapingResult {
        await respectRateLimit()
        
        // 根据平台调用不同的详情抓取方法
        switch platform {
        case .xianyu:
            return await scrapeXianyuDetail(itemId: itemId, url: url)
        default:
            return .failure(.unknown)
        }
    }
    
    // MARK: - 闲鱼抓取
    
    /// 抓取闲鱼搜索结果
    /// 注意：闲鱼的反爬非常严格，这里提供的是基本框架
    private func scrapeXianyu(keyword: String, page: Int) async -> ScrapingResult {
        // 构建搜索URL
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let urlString = "https://s.2.taobao.com/list/?q=\(encodedKeyword)&page=\(page)"
        
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // 检查响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknown)
            }
            
            // 处理各种状态码
            switch httpResponse.statusCode {
            case 200:
                // 解析HTML
                return await parseXianyuHTML(data: data, keyword: keyword)
            case 403:
                return .failure(.blocked("IP被禁止访问"))
            case 429:
                return .rateLimited(retryAfter: 60)
            case 503:
                // 可能是验证码页面
                if let html = String(data: data, encoding: .utf8),
                   html.contains("验证码") || html.contains("captcha") {
                    return .failure(.captchaRequired)
                }
                return .failure(.blocked("服务不可用"))
            default:
                return .failure(.unknown)
            }
            
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    /// 解析闲鱼HTML
    private func parseXianyuHTML(data: Data, keyword: String) async -> ScrapingResult {
        // 这里应该使用SwiftSoup或类似库解析HTML
        // 由于HTML解析比较复杂，这里提供基本框架
        
        guard let html = String(data: data, encoding: .utf8) else {
            return .failure(.parsingError("无法解码HTML"))
        }
        
        // 检查是否需要登录
        if html.contains("登录") && html.contains("密码") {
            return .failure(.loginRequired)
        }
        
        // 检查是否被反爬
        if html.contains("访问过于频繁") || html.contains("系统繁忙") {
            return .failure(.blocked("访问过于频繁"))
        }
        
        // TODO: 使用正则表达式或HTML解析库提取商品信息
        // 这里返回模拟数据作为示例
        var items: [LolitaItem] = []
        
        // 模拟解析结果
        for i in 0..<10 {
            let item = LolitaItem(
                platform: .xianyu,
                platformItemId: "xianyu_\(Int.random(in: 100000...999999))",
                rawTitle: "\(keyword) \(i+1)号商品",
                currentPrice: Double.random(in: 100...5000)
            )
            item.originalURL = "https://2.taobao.com/item.htm?id=\(item.platformItemId)"
            items.append(item)
        }
        
        return .success(items)
    }
    
    /// 抓取闲鱼商品详情
    private func scrapeXianyuDetail(itemId: String, url: String) async -> ScrapingResult {
        guard let url = URL(string: url) else {
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            
            // 解析详情页
            // TODO: 实现详情解析
            
            return .success([])
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    // MARK: - 小红书抓取
    
    /// 抓取小红书搜索结果
    /// 注意：小红书需要特殊的API调用方式
    private func scrapeXiaohongshu(keyword: String, page: Int) async -> ScrapingResult {
        // 小红书的API需要特殊的签名和Headers
        // 这里提供基本框架
        
        let urlString = "https://www.xiaohongshu.com/search_result?keyword=\(keyword)"
        
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        // 小红书需要特殊的Headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .failure(.blocked("无法访问小红书"))
            }
            
            // 解析JSON响应
            // TODO: 实现小红书数据解析
            
            return .success([])
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    // MARK: - 淘宝抓取
    
    /// 抓取淘宝搜索结果
    private func scrapeTaobao(keyword: String, page: Int) async -> ScrapingResult {
        // 淘宝搜索URL
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let urlString = "https://s.taobao.com/search?q=\(encodedKeyword)&s=\((page - 1) * 44)"
        
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknown)
            }
            
            // 淘宝通常返回JSONP格式
            if httpResponse.statusCode == 200 {
                return await parseTaobaoResponse(data: data, keyword: keyword)
            } else {
                return .failure(.blocked("淘宝访问受限"))
            }
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    /// 解析淘宝响应
    private func parseTaobaoResponse(data: Data, keyword: String) async -> ScrapingResult {
        // 淘宝返回的是JSONP格式，需要提取JSON部分
        guard let responseString = String(data: data, encoding: .utf8) else {
            return .failure(.parsingError("无法解码响应"))
        }
        
        // 提取JSON内容（去掉JSONP的回调函数包装）
        // 例如：jsonp123({...}) -> {...}
        // TODO: 实现JSONP解析
        
        return .success([])
    }
    
    // MARK: - 微店抓取
    
    /// 抓取微店搜索结果
    private func scrapeWeidian(keyword: String, page: Int) async -> ScrapingResult {
        // 微店的API相对开放一些
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let urlString = "https://api.vdian.com/api?param={\"keyword\":\"\(encodedKeyword)\"}"
        
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue(randomUserAgent(), forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            
            // 解析JSON响应
            // TODO: 实现微店数据解析
            
            return .success([])
        } catch {
            return .failure(.networkError(error))
        }
    }
    
    // MARK: - 反爬策略
    
    /// 遵守请求频率限制
    private func respectRateLimit() async {
        if let lastTime = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastTime)
            if timeSinceLastRequest < requestInterval {
                let waitTime = requestInterval - timeSinceLastRequest
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
    
    /// 随机User-Agent
    private func randomUserAgent() -> String {
        return userAgents.randomElement() ?? userAgents[0]
    }
    
    /// 随机延迟（用于模拟人类行为）
    private func randomDelay() async {
        let delay = Double.random(in: 1.0...3.0)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    
    // MARK: - 高级抓取策略
    
    /// 使用快捷指令抓取（绕过部分反爬）
    /// 这是一个巧妙的思路：利用iOS快捷指令的真实浏览器环境
    func scrapeWithShortcuts(platform: PlatformType, keyword: String) async -> ScrapingResult {
        // 打开快捷指令URL Scheme
        let shortcutsURL = "shortcuts://run-shortcut?name=SkirtMarketScraper&input=text&text=\(keyword)"
        
        // 注意：这需要用户预先配置好快捷指令
        // 快捷指令可以使用"获取网页内容"动作，拥有真实的浏览器环境
        
        // 这里只是一个示例框架
        return .failure(.unknown)
    }
    
    /// 代理抓取（如果用户配置了代理）
    func scrapeWithProxy(platform: PlatformType, keyword: String, proxy: URL) async -> ScrapingResult {
        // 配置代理
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: proxy.host!,
            kCFNetworkProxiesHTTPPort: proxy.port!
        ]
        
        let proxySession = URLSession(configuration: config)
        
        // 使用代理会话进行请求
        // TODO: 实现代理抓取
        
        return .failure(.unknown)
    }
}

// MARK: - 抓取任务包装器

/// 在TaskDispatcher中使用的抓取包装器
extension WebScraperService {
    /// 执行抓取任务（供TaskDispatcher调用）
    func executeScrapingTask(_ task: MonitorTask) async -> ScrapingResult {
        switch task.taskType {
        case .search:
            guard let keyword = task.keyword else {
                return .failure(.parsingError("缺少关键词"))
            }
            return await scrapeSearchResults(
                platform: task.platform,
                keyword: keyword
            )
            
        case .detail:
            guard let url = task.targetURL else {
                return .failure(.parsingError("缺少URL"))
            }
            return await scrapeItemDetail(
                platform: task.platform,
                itemId: task.taskID,
                url: url
            )
            
        default:
            return .failure(.unknown)
        }
    }
}

// MARK: - 使用建议

/*
## 关于数据抓取的重要说明

由于闲鱼、小红书、淘宝等平台的反爬机制非常严格，直接抓取存在以下问题：

1. **法律风险**：违反平台服务条款
2. **技术难度**：需要不断对抗反爬升级
3. **稳定性差**：容易被封IP/账号

### 推荐的替代方案：

#### 方案1：iOS快捷指令（推荐）
- 让用户通过快捷指令手动分享商品到App
- 利用系统分享扩展获取商品信息
- 完全合法，稳定性高

#### 方案2：浏览器扩展 + 同步
- 开发Safari/Chrome扩展
- 用户在浏览器中浏览时自动采集
- 通过iCloud同步到手机App

#### 方案3：用户众包
- 激励用户主动上报商品信息
- 建立积分/奖励机制
- 社区驱动的数据收集

#### 方案4：官方API（最理想）
- 申请各平台的开放平台API
- 虽然限制较多，但完全合法
- 需要企业资质申请

### 当前实现建议：

当前代码提供了基础的抓取框架，但建议：
1. 优先使用方案1（快捷指令）获取数据
2. 将抓取服务作为fallback方案
3. 做好被封禁的准备（IP轮换、账号池等）
4. 遵守各平台的robots.txt和服务条款

### 快捷指令集成示例：

1. 创建快捷指令"分享商品到裙子股市"
2. 动作：获取网页内容 -> 解析商品信息
3. 动作：打开URL "yourapp://add-item?data=..."
4. App通过URL Scheme接收数据

这样既合法又稳定，是生产环境推荐的做法。
*/
