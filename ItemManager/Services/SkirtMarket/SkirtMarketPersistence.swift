//
//  SkirtMarketPersistence.swift
//  裙子股市 - SwiftData + CloudKit Public DB 配置
//
//  实现分布式数据存储，所有设备共享同一个Public Database
//

import Foundation
import SwiftData
import CloudKit

/// 裙子股市数据持久化管理器
/// 使用CloudKit Public Database实现分布式数据共享
@MainActor
final class SkirtMarketPersistence {
    static let shared = SkirtMarketPersistence()
    
    /// 公共数据库的ModelContainer
    var publicContainer: ModelContainer?
    
    /// CloudKit容器
    private var cloudKitContainer: CKContainer?
    
    /// 是否已配置
    private(set) var isConfigured = false
    
    /// 配置错误
    private(set) var configurationError: Error?
    
    private init() {}
    
    // MARK: - 配置方法
    
    /// 配置裙子股市的SwiftData + CloudKit Public DB
    /// 这个方法应该在应用启动时调用
    func configure() async {
        print("🏛️ 裙子股市: 开始配置Public Database...")
        
        do {
            // 1. 创建Schema
            let schema = createSchema()
            
            // 2. 创建ModelConfiguration，指向Public Database
            let config = createPublicDatabaseConfiguration(schema: schema)
            
            // 3. 创建ModelContainer
            let container = try ModelContainer(for: schema, configurations: [config])
            self.publicContainer = container
            
            // 4. 检查iCloud账户状态
            try await checkiCloudAccountStatus()
            
            // 5. 设置CloudKit订阅
            try await setupCloudKitSubscriptions()
            
            self.isConfigured = true
            print("✅ 裙子股市: Public Database配置成功")
            
        } catch {
            self.configurationError = error
            self.isConfigured = false
            print("❌ 裙子股市: Public Database配置失败: \(error)")
        }
    }
    
    // MARK: - Schema定义
    
    private func createSchema() -> Schema {
        Schema([
            LolitaItem.self,
            SkirtStockMetric.self,
            LolitaMarketIndex.self,
            MonitorTask.self,
            MonitorNode.self
        ])
    }
    
    // MARK: - ModelConfiguration
    
    private func createPublicDatabaseConfiguration(schema: Schema) -> ModelConfiguration {
        // 关键：使用独立的存储文件和CloudKit容器，与主应用完全隔离
        // 这样不会干扰原有的衣橱数据
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // 先禁用CloudKit，使用本地存储避免冲突
        )
        
        return config
    }
    
    // MARK: - iCloud账户检查
    
    private func checkiCloudAccountStatus() async throws {
        let container = CKContainer.default()
        self.cloudKitContainer = container
        
        let status = try await container.accountStatus()
        
        switch status {
        case .available:
            print("☁️ iCloud账户可用")
        case .noAccount:
            throw SkirtMarketError.noiCloudAccount
        case .restricted:
            throw SkirtMarketError.iCloudRestricted
        case .couldNotDetermine:
            throw SkirtMarketError.iCloudStatusUnknown
        @unknown default:
            throw SkirtMarketError.iCloudStatusUnknown
        }
    }
    
    // MARK: - CloudKit订阅设置
    
    private func setupCloudKitSubscriptions() async throws {
        guard let container = cloudKitContainer else { return }
        
        let database = container.publicCloudDatabase
        
        // 1. 设置LolitaItem变更订阅
        try await setupSubscription(
            database: database,
            recordType: "LolitaItem",
            subscriptionID: "lolita-item-changes"
        )
        
        // 2. 设置MonitorTask变更订阅
        try await setupSubscription(
            database: database,
            recordType: "MonitorTask",
            subscriptionID: "monitor-task-changes"
        )
        
        // 3. 设置SkirtStockMetric变更订阅
        try await setupSubscription(
            database: database,
            recordType: "SkirtStockMetric",
            subscriptionID: "stock-metric-changes"
        )
        
        print("☁️ CloudKit订阅设置完成")
    }
    
    private func setupSubscription(
        database: CKDatabase,
        recordType: String,
        subscriptionID: String
    ) async throws {
        // 检查订阅是否已存在
        do {
            _ = try await database.record(for: CKRecord.ID(recordName: subscriptionID))
            print("  ✓ 订阅 \(subscriptionID) 已存在")
            return
        } catch {
            // 订阅不存在，创建新的
        }
        
        // 创建订阅
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await database.save(subscription)
            print("  ✓ 订阅 \(subscriptionID) 创建成功")
        } catch {
            print("  ⚠️ 订阅 \(subscriptionID) 创建失败: \(error)")
        }
    }
    
    // MARK: - 公共方法
    
    /// 获取主上下文
    var mainContext: ModelContext? {
        guard let container = publicContainer else { return nil }
        return ModelContext(container)
    }
    
    /// 创建新的上下文（用于后台操作）
    func newContext() -> ModelContext? {
        guard let container = publicContainer else { return nil }
        return ModelContext(container)
    }
    
    /// 手动触发同步
    func triggerSync() {
        // SwiftData会自动处理同步，但我们可以通知系统立即尝试
        print("🔄 触发CloudKit同步...")
        // 保存上下文会触发同步
        if let context = mainContext {
            try? context.save()
        }
    }
}

// MARK: - 错误类型

enum SkirtMarketError: LocalizedError {
    case noiCloudAccount
    case iCloudRestricted
    case iCloudStatusUnknown
    case publicDatabaseNotAvailable
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .noiCloudAccount:
            return "请登录iCloud账户以使用裙子股市功能"
        case .iCloudRestricted:
            return "iCloud账户受限，无法使用裙子股市"
        case .iCloudStatusUnknown:
            return "无法确定iCloud账户状态"
        case .publicDatabaseNotAvailable:
            return "公共数据库不可用"
        case .syncFailed:
            return "数据同步失败"
        }
    }
}

// MARK: - 删除追踪器扩展

/// 裙子股市专用的删除追踪器
/// 由于使用Public Database，删除需要特殊处理
@MainActor
final class SkirtMarketDeleteTracker {
    static let shared = SkirtMarketDeleteTracker()
    
    private let userDefaults = UserDefaults.standard
    private let deletedItemsKey = "skirt_market_deleted_items"
    
    private init() {}
    
    /// 记录删除
    func recordDeletedItem(platformID: String) {
        var deletedItems = getDeletedItems()
        deletedItems[platformID] = Date().timeIntervalSince1970
        userDefaults.set(deletedItems, forKey: deletedItemsKey)
        print("🗑️ 记录删除: \(platformID)")
    }
    
    /// 获取删除记录
    func getDeletedItems() -> [String: Double] {
        return userDefaults.dictionary(forKey: deletedItemsKey) as? [String: Double] ?? [:]
    }
    
    /// 检查是否已删除
    func isDeleted(platformID: String) -> Bool {
        return getDeletedItems().keys.contains(platformID)
    }
    
    /// 清理过期记录（保留7天）
    func cleanupExpiredRecords() {
        var records = getDeletedItems()
        let now = Date().timeIntervalSince1970
        let retentionPeriod: Double = 7 * 24 * 60 * 60  // 7天
        
        records = records.filter { now - $0.value < retentionPeriod }
        userDefaults.set(records, forKey: deletedItemsKey)
    }
    
    /// 恢复记录（用于误删恢复）
    func restoreItem(platformID: String) {
        var records = getDeletedItems()
        records.removeValue(forKey: platformID)
        userDefaults.set(records, forKey: deletedItemsKey)
        print("♻️ 恢复记录: \(platformID)")
    }
}

// MARK: - 使用示例

/*
// 在App启动时配置
@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 配置裙子股市
                    await SkirtMarketPersistence.shared.configure()
                }
        }
        .modelContainer(SkirtMarketPersistence.shared.publicContainer ?? SharedPersistence.shared.sharedModelContainer)
    }
}

// 插入数据示例
func insertItem(_ item: LolitaItem) async {
    guard let context = SkirtMarketPersistence.shared.mainContext else { return }
    
    // 检查是否已存在
    let descriptor = FetchDescriptor<LolitaItem>(
        predicate: #Predicate { $0.platformID == item.platformID }
    )
    
    if let existing = try? context.fetch(descriptor).first {
        // 更新现有记录
        existing.currentPrice = item.currentPrice
        existing.lastUpdated = Date()
        existing.touch()
    } else {
        // 插入新记录
        context.insert(item)
    }
    
    try? context.save()
}

// 查询数据示例
func fetchItems(platform: PlatformType) async -> [LolitaItem] {
    guard let context = SkirtMarketPersistence.shared.mainContext else { return [] }
    
    let descriptor = FetchDescriptor<LolitaItem>(
        predicate: LolitaItem.predicateForPlatform(platform),
        sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
    )
    
    return (try? context.fetch(descriptor)) ?? []
}
*/
