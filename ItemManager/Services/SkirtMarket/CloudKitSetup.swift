//
//  CloudKitSetup.swift
//  裙装股市 - CloudKit 容器初始化
//
//  用于首次部署时初始化 CloudKit 容器和记录类型
//

import Foundation
import CloudKit

/// CloudKit 容器初始化工具
/// 在应用首次启动时自动创建所需的记录类型和权限
@MainActor
final class CloudKitSetup {
    static let shared = CloudKitSetup()
    
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.bugod2.SkirtMarket")
        self.publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - 初始化容器
    
    /// 执行完整的 CloudKit 容器初始化
    /// 包括：创建记录类型、设置权限、创建索引
    func initializeContainer() async {
        print("🔧 开始初始化 CloudKit 容器: iCloud.bugod2.SkirtMarket")
        
        // 1. 检查账户状态
        guard await checkAccountStatus() else {
            print("❌ iCloud 账户不可用，跳过初始化")
            return
        }
        
        // 2. 创建记录类型（Schema）
        await createRecordTypes()
        
        // 3. 设置权限
        await setupPermissions()
        
        // 4. 创建订阅
        await setupSubscriptions()
        
        print("✅ CloudKit 容器初始化完成")
    }
    
    // MARK: - 检查账户状态
    
    private func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                print("✅ iCloud 账户可用")
                return true
            case .noAccount:
                print("⚠️ 用户未登录 iCloud")
            case .restricted:
                print("⚠️ iCloud 账户受限")
            case .couldNotDetermine:
                print("⚠️ 无法确定 iCloud 状态")
            @unknown default:
                print("⚠️ 未知的 iCloud 状态")
            }
        } catch {
            print("❌ 检查 iCloud 状态失败: \(error)")
        }
        return false
    }
    
    // MARK: - 创建记录类型
    
    private func createRecordTypes() async {
        print("📋 创建记录类型...")
        
        // 创建 LolitaItem 记录类型
        await createLolitaItemRecordType()
        
        // 创建 SkirtStockMetric 记录类型
        await createSkirtStockMetricRecordType()
        
        // 创建 LolitaMarketIndex 记录类型
        await createLolitaMarketIndexRecordType()
        
        // 创建 MonitorTask 记录类型
        await createMonitorTaskRecordType()
        
        // 创建 MonitorNode 记录类型
        await createMonitorNodeRecordType()
    }
    
    /// 创建 LolitaItem 记录类型
    private func createLolitaItemRecordType() async {
        let recordType = CKRecord.RecordType("LolitaItem")
        
        // 创建记录类型定义
        let platformIDField = CKRecordFieldDefinition(
            fieldName: "platformID",
            fieldType: .string,
            isOptional: false
        )
        
        let platformField = CKRecordFieldDefinition(
            fieldName: "platform",
            fieldType: .string,
            isOptional: false
        )
        
        let rawTitleField = CKRecordFieldDefinition(
            fieldName: "rawTitle",
            fieldType: .string,
            isOptional: false
        )
        
        let cleanedNameField = CKRecordFieldDefinition(
            fieldName: "cleanedName",
            fieldType: .string,
            isOptional: true
        )
        
        let brandField = CKRecordFieldDefinition(
            fieldName: "brand",
            fieldType: .string,
            isOptional: true
        )
        
        let currentPriceField = CKRecordFieldDefinition(
            fieldName: "currentPrice",
            fieldType: .double,
            isOptional: false
        )
        
        let currencyField = CKRecordFieldDefinition(
            fieldName: "currency",
            fieldType: .string,
            isOptional: false
        )
        
        let statusField = CKRecordFieldDefinition(
            fieldName: "status",
            fieldType: .string,
            isOptional: false
        )
        
        let isDeletedField = CKRecordFieldDefinition(
            fieldName: "isDeleted",
            fieldType: .int64,
            isOptional: false
        )
        
        let lastUpdatedField = CKRecordFieldDefinition(
            fieldName: "lastUpdated",
            fieldType: .date,
            isOptional: false
        )
        
        // 保存示例记录来创建类型
        let record = CKRecord(recordType: recordType)
        record["platformID"] = "init_placeholder" as CKRecordValue
        record["platform"] = "other" as CKRecordValue
        record["rawTitle"] = "初始化占位" as CKRecordValue
        record["currentPrice"] = 0.0 as CKRecordValue
        record["currency"] = "CNY" as CKRecordValue
        record["status"] = "unknown" as CKRecordValue
        record["isDeleted"] = 0 as CKRecordValue
        record["lastUpdated"] = Date() as CKRecordValue
        
        do {
            _ = try await publicDatabase.save(record)
            print("  ✅ LolitaItem 记录类型已创建")
            
            // 删除占位记录
            try await publicDatabase.deleteRecord(withID: record.recordID)
        } catch {
            print("  ⚠️ LolitaItem 创建结果: \(error.localizedDescription)")
        }
    }
    
    /// 创建 SkirtStockMetric 记录类型
    private func createSkirtStockMetricRecordType() async {
        let recordType = CKRecord.RecordType("SkirtStockMetric")
        
        let record = CKRecord(recordType: recordType)
        record["skirtName"] = "init_placeholder" as CKRecordValue
        record["platformID"] = "init" as CKRecordValue
        record["currentPrice"] = 0.0 as CKRecordValue
        record["priceChange"] = 0.0 as CKRecordValue
        record["changePercent"] = 0.0 as CKRecordValue
        record["volume24h"] = 0 as CKRecordValue
        record["trend"] = "stable" as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        
        do {
            _ = try await publicDatabase.save(record)
            print("  ✅ SkirtStockMetric 记录类型已创建")
            try await publicDatabase.deleteRecord(withID: record.recordID)
        } catch {
            print("  ⚠️ SkirtStockMetric 创建结果: \(error.localizedDescription)")
        }
    }
    
    /// 创建 LolitaMarketIndex 记录类型
    private func createLolitaMarketIndexRecordType() async {
        let recordType = CKRecord.RecordType("LolitaMarketIndex")
        
        let record = CKRecord(recordType: recordType)
        record["indexValue"] = 1000.0 as CKRecordValue
        record["changePercent"] = 0.0 as CKRecordValue
        record["totalVolume"] = 0 as CKRecordValue
        record["activeItems"] = 0 as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue
        
        do {
            _ = try await publicDatabase.save(record)
            print("  ✅ LolitaMarketIndex 记录类型已创建")
            try await publicDatabase.deleteRecord(withID: record.recordID)
        } catch {
            print("  ⚠️ LolitaMarketIndex 创建结果: \(error.localizedDescription)")
        }
    }
    
    /// 创建 MonitorTask 记录类型
    private func createMonitorTaskRecordType() async {
        let recordType = CKRecord.RecordType("MonitorTask")
        
        let record = CKRecord(recordType: recordType)
        record["platformID"] = "init_placeholder" as CKRecordValue
        record["platform"] = "other" as CKRecordValue
        record["taskType"] = "priceCheck" as CKRecordValue
        record["status"] = "pending" as CKRecordValue
        record["priority"] = 5 as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        
        do {
            _ = try await publicDatabase.save(record)
            print("  ✅ MonitorTask 记录类型已创建")
            try await publicDatabase.deleteRecord(withID: record.recordID)
        } catch {
            print("  ⚠️ MonitorTask 创建结果: \(error.localizedDescription)")
        }
    }
    
    /// 创建 MonitorNode 记录类型
    private func createMonitorNodeRecordType() async {
        let recordType = CKRecord.RecordType("MonitorNode")
        
        let record = CKRecord(recordType: recordType)
        record["nodeID"] = "init_placeholder" as CKRecordValue
        record["deviceName"] = "初始化设备" as CKRecordValue
        record["isActive"] = 0 as CKRecordValue
        record["lastSeen"] = Date() as CKRecordValue
        record["completedTasks"] = 0 as CKRecordValue
        record["reliabilityScore"] = 0.0 as CKRecordValue
        
        do {
            _ = try await publicDatabase.save(record)
            print("  ✅ MonitorNode 记录类型已创建")
            try await publicDatabase.deleteRecord(withID: record.recordID)
        } catch {
            print("  ⚠️ MonitorNode 创建结果: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 设置权限
    
    private func setupPermissions() async {
        print("🔐 设置权限...")
        print("  ⚠️ 权限配置需要在 CloudKit Dashboard 手动完成")
        print("  📖 请参考 CloudKitSetup.md 文档")
    }
    
    // MARK: - 设置订阅
    
    private func setupSubscriptions() async {
        print("📡 设置订阅...")
        
        let recordTypes = ["LolitaItem", "SkirtStockMetric", "LolitaMarketIndex", "MonitorTask"]
        
        for recordType in recordTypes {
            let subscriptionID = "\(recordType.lowercased())-changes"
            
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
                print("  ✅ 订阅 \(subscriptionID) 创建成功")
            } catch {
                print("  ⚠️ 订阅 \(subscriptionID): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 辅助类型

struct CKRecordFieldDefinition {
    let fieldName: String
    let fieldType: CKRecordFieldType
    let isOptional: Bool
}

enum CKRecordFieldType {
    case string
    case int64
    case double
    case date
    case reference
    case asset
    case location
}
