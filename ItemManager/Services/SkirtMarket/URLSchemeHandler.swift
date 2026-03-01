//
//  URLSchemeHandler.swift
//  裙子股市 - URL Scheme处理器
//
//  处理从快捷指令传入的商品数据
//

import Foundation
import SwiftData
import SwiftUI

/// URL Scheme处理器
@MainActor
final class URLSchemeHandler {
    static let shared = URLSchemeHandler()
    
    /// URL Scheme名称
    static let scheme = "skirtmarket"
    
    /// 支持的Action
    enum Action: String {
        case importItem = "import"     // 导入商品
        case addTask = "addtask"       // 添加任务
        case openItem = "item"         // 打开商品详情
        case search = "search"         // 搜索
    }
    
    private init() {}
    
    // MARK: - 处理URL
    
    /// 处理传入的URL
    /// - Parameter url: 传入的URL
    /// - Returns: 是否成功处理
    @discardableResult
    func handleURL(_ url: URL) -> Bool {
        print("🔗 收到URL: \(url.absoluteString)")
        
        // 检查URL Scheme
        guard url.scheme == Self.scheme else {
            print("❌ 不匹配的URL Scheme: \(url.scheme ?? "nil")")
            return false
        }
        
        // 获取Action
        guard let actionString = url.host,
              let action = Action(rawValue: actionString) else {
            print("❌ 未知的Action")
            return false
        }
        
        // 解析参数
        let parameters = parseParameters(from: url)
        
        // 根据Action处理
        switch action {
        case .importItem:
            return handleImportItem(parameters: parameters)
        case .addTask:
            return handleAddTask(parameters: parameters)
        case .openItem:
            return handleOpenItem(parameters: parameters)
        case .search:
            return handleSearch(parameters: parameters)
        }
    }
    
    // MARK: - 参数解析
    
    /// 解析URL参数
    private func parseParameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]
        
        // 使用URLComponents解析
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                parameters[item.name] = item.value
            }
        }
        
        return parameters
    }
    
    // MARK: - Action处理
    
    /// 处理导入商品
    private func handleImportItem(parameters: [String: String]) -> Bool {
        print("📦 处理导入商品")
        
        // 获取data参数（JSON格式，URL编码）
        guard let encodedData = parameters["data"],
              let jsonData = encodedData.removingPercentEncoding?.data(using: .utf8) else {
            print("❌ 缺少data参数或解码失败")
            return false
        }
        
        // 解析JSON
        do {
            let productInfo = try JSONDecoder().decode(ShortcutProductInfo.self, from: jsonData)
            print("✅ 解析商品信息成功: \(productInfo.title)")
            
            // 创建LolitaItem
            let item = createItem(from: productInfo)
            
            // 保存到数据库
            saveItem(item)
            
            // 发送通知，让UI更新
            NotificationCenter.default.post(
                name: .didReceiveNewItemFromShortcut,
                object: item
            )
            
            return true
            
        } catch {
            print("❌ JSON解析失败: \(error)")
            return false
        }
    }
    
    /// 处理添加任务
    private func handleAddTask(parameters: [String: String]) -> Bool {
        print("📝 处理添加任务")
        
        guard let keyword = parameters["keyword"],
              let platformString = parameters["platform"],
              let platform = PlatformType(rawValue: platformString) else {
            print("❌ 缺少必要参数")
            return false
        }
        
        // 创建任务
        Task {
            await TaskDispatcher.shared.createTask(
                type: .search,
                platform: platform,
                keyword: keyword,
                priority: 8  // 来自快捷指令的任务优先级较高
            )
        }
        
        return true
    }
    
    /// 处理打开商品
    private func handleOpenItem(parameters: [String: String]) -> Bool {
        print("📱 处理打开商品")
        
        guard let platformID = parameters["id"] else {
            return false
        }
        
        // 发送通知，让UI导航到商品详情
        NotificationCenter.default.post(
            name: .shouldOpenItemDetail,
            object: platformID
        )
        
        return true
    }
    
    /// 处理搜索
    private func handleSearch(parameters: [String: String]) -> Bool {
        print("🔍 处理搜索")
        
        guard let keyword = parameters["keyword"] else {
            return false
        }
        
        // 发送通知，让UI执行搜索
        NotificationCenter.default.post(
            name: .shouldPerformSearch,
            object: keyword
        )
        
        return true
    }
    
    // MARK: - 辅助方法
    
    /// 从快捷指令信息创建LolitaItem
    private func createItem(from info: ShortcutProductInfo) -> LolitaItem {
        // 确定平台
        let platform: PlatformType
        switch info.platform.lowercased() {
        case "xianyu", "闲鱼":
            platform = .xianyu
        case "xiaohongshu", "小红书":
            platform = .xiaohongshu
        case "taobao", "淘宝":
            platform = .taobao
        case "weidian", "微店":
            platform = .weidian
        default:
            platform = .other
        }
        
        // 解析价格
        let price = parsePrice(info.price)
        
        // 创建Item
        let item = LolitaItem(
            platform: platform,
            platformItemId: extractItemID(from: info.url) ?? UUID().uuidString,
            rawTitle: info.title,
            currentPrice: price,
            originalURL: info.url
        )
        
        // 设置图片
        item.mainImageURL = info.image
        
        // 设置卖家信息
        item.sellerName = info.seller
        
        // 标记来源
        item.collectorDeviceId = TaskDispatcher.shared.currentNodeId
        item.collectorNodeName = "快捷指令导入"
        
        return item
    }
    
    /// 解析价格字符串
    private func parsePrice(_ priceString: String) -> Double {
        // 去除非数字字符（保留小数点）
        let cleaned = priceString.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
        return Double(cleaned) ?? 0
    }
    
    /// 从URL提取商品ID
    private func extractItemID(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        // 根据不同平台提取ID
        let queryItems = components.queryItems ?? []
        
        // 闲鱼：id=xxx
        if let id = queryItems.first(where: { $0.name == "id" })?.value {
            return id
        }
        
        // 小红书：note_id=xxx
        if let noteId = queryItems.first(where: { $0.name == "note_id" })?.value {
            return noteId
        }
        
        // 淘宝：id=xxx
        // 已经在上面的通用逻辑中处理
        
        return nil
    }
    
    /// 保存商品到数据库
    private func saveItem(_ item: LolitaItem) {
        guard let context = SkirtMarketPersistenceV2.shared.mainContext else {
            print("❌ 无法获取数据库上下文")
            return
        }
        
        // 检查是否已存在（简化谓词，避免复杂表达式）
        let descriptor = FetchDescriptor<LolitaItem>(
            predicate: #Predicate { item in
                item.platformID == item.platformID
            }
        )
        
        do {
            let allItems = try context.fetch(descriptor)
            let existing = allItems.first { $0.platformID == item.platformID }
            if let existing = existing {
                // 更新现有记录
                existing.currentPrice = item.currentPrice
                existing.lastUpdated = Date()
                existing.status = .onSale
                print("🔄 更新现有商品: \(item.platformID)")
            } else {
                // 插入新记录
                context.insert(item)
                print("✅ 插入新商品: \(item.platformID)")
            }
            
            try context.save()
            print("💾 保存成功")
            
        } catch {
            print("❌ 保存失败: \(error)")
        }
    }
}

// MARK: - 数据模型

/// 快捷指令传入的商品信息
struct ShortcutProductInfo: Codable {
    let platform: String
    let title: String
    let price: String
    let url: String
    let image: String?
    let seller: String?
}

// MARK: - 通知扩展

extension Notification.Name {
    /// 从快捷指令收到新商品
    static let didReceiveNewItemFromShortcut = Notification.Name("didReceiveNewItemFromShortcut")
    
    /// 应该打开商品详情
    static let shouldOpenItemDetail = Notification.Name("shouldOpenItemDetail")
    
    /// 应该执行搜索
    static let shouldPerformSearch = Notification.Name("shouldPerformSearch")
}

// MARK: - 使用示例

/*
// 在AppDelegate中处理URL Scheme
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return URLSchemeHandler.shared.handleURL(url)
    }
    
    // iOS 13+ 使用SceneDelegate时，在SceneDelegate中处理
}

// 在SceneDelegate中
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        URLSchemeHandler.shared.handleURL(url)
    }
}

// 在SwiftUI App中
@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    URLSchemeHandler.shared.handleURL(url)
                }
        }
    }
}

// 监听通知更新UI
struct ContentView: View {
    @State private var showImportSuccess = false
    @State private var importedItemName = ""
    
    var body: some View {
        NavigationStack {
            // ...
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveNewItemFromShortcut)) { notification in
            if let item = notification.object as? LolitaItem {
                importedItemName = item.displayName
                showImportSuccess = true
            }
        }
        .alert("导入成功", isPresented: $showImportSuccess) {
            Button("确定") {}
        } message: {
            Text("已成功导入商品: \(importedItemName)")
        }
    }
}
*/
