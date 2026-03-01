//
//  CloudKitManager.swift
//  裙子股市 - 原生 CloudKit API 管理器
//
//  使用独立的 CloudKit 容器实现公共数据库功能
//  容器标识符: iCloud.bugod2.SkirtMarket
//

import Foundation
import CloudKit

/// CloudKit 管理器 - 操作裙子股市的公共数据库
@MainActor
final class CloudKitManager {
    static let shared = CloudKitManager()
    
    /// CloudKit 容器 - 使用独立的容器标识符
    private let container: CKContainer
    
    /// 公共数据库 - 所有用户共享
    private let publicDatabase: CKDatabase
    
    /// 是否已配置
    private(set) var isConfigured = false
    
    /// iCloud 账户状态
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    
    private init() {
        // 使用独立的 CloudKit 容器标识符
        // 需要在 Xcode Signing & Capabilities 中添加 iCloud.bugod2.SkirtMarket
        self.container = CKContainer(identifier: "iCloud.bugod2.SkirtMarket")
        self.publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - 配置
    
    /// 配置 CloudKit 并检查账户状态
    func configure() async {
        print("☁️ CloudKitManager: 配置公共数据库...")
        
        do {
            // 检查 iCloud 账户状态
            let status = try await container.accountStatus()
            self.accountStatus = status
            
            switch status {
            case .available:
                print("✅ iCloud 账户可用")
                self.isConfigured = true
                
                // 设置订阅
                await setupSubscriptions()
                
            case .noAccount:
                print("⚠️ 用户未登录 iCloud")
                self.isConfigured = false
            case .restricted:
                print("⚠️ iCloud 账户受限")
                self.isConfigured = false
            case .couldNotDetermine:
                print("⚠️ 无法确定 iCloud 状态")
                self.isConfigured = false
            @unknown default:
                print("⚠️ 未知的 iCloud 状态")
                self.isConfigured = false
            }
        } catch {
            print("❌ CloudKit 配置失败: \(error)")
            self.isConfigured = false
        }
    }
    
    // MARK: - 订阅设置
    
    /// 设置 CloudKit 订阅 - 监听数据变更
    private func setupSubscriptions() async {
        print("📡 设置 CloudKit 订阅...")
        
        let recordTypes = ["LolitaItem", "SkirtStockMetric", "LolitaMarketIndex", "MonitorTask"]
        
        for recordType in recordTypes {
            let subscriptionID = "\(recordType.lowercased())-changes"
            
            // 检查订阅是否已存在
            do {
                _ = try await publicDatabase.record(for: CKRecord.ID(recordName: subscriptionID))
                print("  ✓ 订阅 \(subscriptionID) 已存在")
                continue
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
                _ = try await publicDatabase.save(subscription)
                print("  ✓ 订阅 \(subscriptionID) 创建成功")
            } catch {
                print("  ⚠️ 订阅 \(subscriptionID) 创建失败: \(error)")
            }
        }
    }
    
    // MARK: - CRUD 操作
    
    /// 保存 LolitaItem 到公共数据库
    func saveLolitaItem(_ item: LolitaItem) async throws {
        let record = item.toCKRecord()
        let savedRecord = try await publicDatabase.save(record)
        print("✅ 保存到 CloudKit: \(item.platformID)")
        
        // 更新本地记录的 recordID
        item.cloudKitRecordID = savedRecord.recordID.recordName
    }
    
    /// 从公共数据库获取所有 LolitaItem
    func fetchAllLolitaItems() async throws -> [LolitaItem] {
        let query = CKQuery(recordType: "LolitaItem", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "lastUpdated", ascending: false)]
        
        let (matchResults, _) = try await publicDatabase.records(matching: query)
        
        let items = matchResults.compactMap { (_, result) -> LolitaItem? in
            switch result {
            case .success(let record):
                return LolitaItem.fromCKRecord(record)
            case .failure(let error):
                print("❌ 获取记录失败: \(error)")
                return nil
            }
        }
        
        print("📦 从 CloudKit 获取了 \(items.count) 个商品")
        return items
    }
    
    /// 删除公共数据库中的记录
    func deleteLolitaItem(recordID: String) async throws {
        let recordID = CKRecord.ID(recordName: recordID)
        try await publicDatabase.deleteRecord(withID: recordID)
        print("🗑️ 从 CloudKit 删除: \(recordID)")
    }
    
    // MARK: - 同步操作
    
    /// 同步本地数据到 CloudKit
    func syncLocalToCloud(localItems: [LolitaItem]) async {
        guard isConfigured else {
            print("⚠️ CloudKit 未配置，跳过同步")
            return
        }
        
        print("🔄 开始同步到 CloudKit...")
        
        for item in localItems where !item.isDeleted {
            do {
                try await saveLolitaItem(item)
            } catch {
                print("❌ 同步失败: \(item.platformID) - \(error)")
            }
        }
        
        print("✅ 同步完成")
    }
    
    /// 从 CloudKit 拉取最新数据
    func pullFromCloud() async -> [LolitaItem] {
        guard isConfigured else {
            print("⚠️ CloudKit 未配置，跳过拉取")
            return []
        }
        
        do {
            let items = try await fetchAllLolitaItems()
            print("✅ 从 CloudKit 拉取了 \(items.count) 个商品")
            return items
        } catch {
            print("❌ 拉取失败: \(error)")
            return []
        }
    }
}

// MARK: - LolitaItem CloudKit 扩展

extension LolitaItem {
    /// 转换为 CloudKit Record
    func toCKRecord() -> CKRecord {
        let recordID: CKRecord.ID
        if let cloudKitID = cloudKitRecordID {
            recordID = CKRecord.ID(recordName: cloudKitID)
        } else {
            recordID = CKRecord.ID(recordName: platformID)
        }
        
        let record = CKRecord(recordType: "LolitaItem", recordID: recordID)
        
        record["platformID"] = platformID as CKRecordValue
        record["platform"] = platform.rawValue as CKRecordValue
        record["rawTitle"] = rawTitle as CKRecordValue
        record["cleanedName"] = cleanedName as CKRecordValue?
        record["brand"] = brand as CKRecordValue?
        record["currentPrice"] = currentPrice as CKRecordValue
        record["currency"] = currency as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        record["isDeleted"] = isDeleted as CKRecordValue
        record["lastUpdated"] = lastUpdated as CKRecordValue
        
        return record
    }
    
    /// 从 CloudKit Record 创建实例
    static func fromCKRecord(_ record: CKRecord) -> LolitaItem {
        let platformID = record["platformID"] as? String ?? ""
        let platformRaw = record["platform"] as? String ?? "other"
        let platform = PlatformType(rawValue: platformRaw) ?? .other
        let rawTitle = record["rawTitle"] as? String ?? ""
        let currentPrice = record["currentPrice"] as? Double ?? 0
        
        let item = LolitaItem(
            platform: platform,
            platformItemId: platformID,
            rawTitle: rawTitle,
            currentPrice: currentPrice
        )
        
        item.cloudKitRecordID = record.recordID.recordName
        item.cleanedName = record["cleanedName"] as? String
        item.brand = record["brand"] as? String
        item.currency = record["currency"] as? String ?? "CNY"
        item.status = ItemStatus(rawValue: record["status"] as? String ?? "unknown") ?? .unknown
        item.isDeleted = record["isDeleted"] as? Bool ?? false
        item.lastUpdated = record["lastUpdated"] as? Date ?? Date()
        
        return item
    }
}

// MARK: - 使用说明

/*
## CloudKit 配置步骤

### 1. Xcode 配置
在项目的 Signing & Capabilities 中添加：
- iCloud 功能
- 容器标识符: iCloud.bugod2.SkirtMarket
- 勾选 CloudKit

### 2. CloudKit Dashboard 配置
访问 https://icloud.developer.apple.com/dashboard/
- 选择容器: iCloud.bugod2.SkirtMarket
- 创建记录类型: LolitaItem, SkirtStockMetric, LolitaMarketIndex, MonitorTask
- 配置权限: Public Database 允许读取

### 3. 使用示例

```swift
// 配置 CloudKit
await CloudKitManager.shared.configure()

// 保存商品
let item = LolitaItem(...)
try await CloudKitManager.shared.saveLolitaItem(item)

// 获取所有商品
let items = try await CloudKitManager.shared.fetchAllLolitaItems()

// 同步本地数据到 CloudKit
await CloudKitManager.shared.syncLocalToCloud(localItems: localItems)

// 从 CloudKit 拉取数据
let cloudItems = await CloudKitManager.shared.pullFromCloud()
```

### 4. 数据流

本地 SwiftData (缓存) <-> CloudKitManager <-> CloudKit Public Database
                                      ^
                                      |
                              其他设备同步
*/
