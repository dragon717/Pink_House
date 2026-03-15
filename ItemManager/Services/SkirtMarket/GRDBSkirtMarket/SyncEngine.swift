//
//  SyncEngine.swift
//  裙装股市 - CloudKit 同步引擎
//
//  使用"影子模型"架构：本地 GRDB + 云端 CloudKit
//

import Foundation
import CloudKit
import GRDB

/// 同步引擎 - 协调本地 GRDB 和云端 CloudKit
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()
    
    /// CloudKit 容器
    private let container: CKContainer
    
    /// 公共数据库
    private let publicDatabase: CKDatabase
    
    /// 是否正在同步
    private(set) var isSyncing = false
    
    /// 同步队列（确保顺序执行）
    private let syncQueue = DispatchQueue(label: "com.skirtmarket.sync", qos: .utility)
    
    /// 定时器
    private var syncTimer: Timer?
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.bugod2.SkirtMarket")
        self.publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - 配置
    
    /// 配置同步引擎
    func configure() async {
        print("🔄 SyncEngine: 配置同步引擎...")
        
        // 检查 iCloud 账户状态
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                print("✅ iCloud 账户可用，同步功能已启用")
            case .noAccount:
                print("⚠️ 用户未登录 iCloud，同步功能不可用")
            case .restricted:
                print("⚠️ iCloud 账户受限，同步功能不可用")
            case .couldNotDetermine:
                print("⚠️ 无法确定 iCloud 状态")
            @unknown default:
                print("⚠️ 未知的 iCloud 状态")
            }
        } catch {
            print("❌ 检查 iCloud 状态失败: \(error)")
        }
        
        // 启动定时同步
        startPeriodicSync()
    }
    
    /// 启动定时同步（每5分钟）
    func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.syncToCloud()
            }
        }
        print("🔄 定时同步已启动（每5分钟）")
    }
    
    /// 停止定时同步
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        print("🛑 定时同步已停止")
    }
    
    // MARK: - 同步到云端
    
    /// 将本地变更同步到 CloudKit
    func syncToCloud() async {
        guard !isSyncing else {
            print("⏳ 同步正在进行中，跳过本次")
            return
        }
        
        guard let writer = GRDBManager.shared.writer else {
            print("❌ 数据库未初始化")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        print("☁️ 开始同步到 CloudKit...")
        
        do {
            // 1. 获取待同步的 LolitaItem
            let pendingItems = try await writer.read { db in
                try GRDBLolitaItem.fetchPendingSync(db, limit: 50)
            }
            
            print("📤 待同步商品: \(pendingItems.count) 个")
            
            // 2. 逐个同步到 CloudKit
            for item in pendingItems {
                do {
                    try await syncItemToCloud(item)
                } catch {
                    print("❌ 同步商品失败 \(item.id): \(error)")
                }
            }
            
            // 3. 同步其他类型...
            // TODO: 同步 SkirtStockMetric, LolitaMarketIndex 等
            
            print("✅ 同步完成")
            
        } catch {
            print("❌ 同步失败: \(error)")
        }
    }
    
    /// 同步单个商品到 CloudKit
    private func syncItemToCloud(_ item: GRDBLolitaItem) async throws {
        // 创建 CKRecord
        let record = CKRecord(recordType: "LolitaItem")
        record["platformID"] = item.platformID as CKRecordValue
        record["platform"] = item.platform as CKRecordValue
        record["rawTitle"] = item.rawTitle as CKRecordValue
        record["cleanedName"] = item.cleanedName as CKRecordValue?
        record["brand"] = item.brand as CKRecordValue?
        record["currentPrice"] = item.currentPrice as CKRecordValue
        record["currency"] = item.currency as CKRecordValue
        record["status"] = item.status as CKRecordValue
        record["isDeleted"] = item.isDeleted as CKRecordValue
        record["lastUpdated"] = item.lastUpdated as CKRecordValue
        
        // 保存到 CloudKit
        let savedRecord = try await publicDatabase.save(record)
        
        // 更新本地同步状态
        if let writer = GRDBManager.shared.writer {
            try await writer.write { db in
                try item.markAsSynced(db, cloudKitRecordID: savedRecord.recordID.recordName)
            }
        }
        
        print("✅ 已同步: \(item.rawTitle)")
    }
    
    // MARK: - 从云端拉取
    
    /// 从 CloudKit 拉取最新数据
    func pullFromCloud() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        print("☁️ 开始从 CloudKit 拉取数据...")
        
        do {
            // 1. 拉取 LolitaItem
            // 使用 platformID != "" 作为查询条件，避免查询 recordName
            let predicate = NSPredicate(format: "platformID != %@", "")
            let query = CKQuery(recordType: "LolitaItem", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "lastUpdated", ascending: false)]
            
            let (matchResults, _) = try await publicDatabase.records(matching: query)
            
            var count = 0
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    try await processPulledRecord(record)
                    count += 1
                case .failure(let error):
                    print("❌ 拉取记录失败: \(error)")
                }
            }
            
            print("✅ 从云端拉取了 \(count) 条记录")
            
        } catch {
            print("❌ 拉取失败: \(error)")
        }
    }
    
    /// 处理拉取的记录
    private func processPulledRecord(_ record: CKRecord) async throws {
        guard let writer = GRDBManager.shared.writer else { return }
        
        let platformID = record["platformID"] as? String ?? ""
        let cloudKitID = record.recordID.recordName
        
        // 检查本地是否已存在
        let existingItem = try await writer.read { db in
            try GRDBLolitaItem.fetchByPlatformID(db, platformID: platformID)
        }
        
        if var existing = existingItem {
            // 更新现有记录
            existing.cloudKitRecordID = cloudKitID
            existing.rawTitle = record["rawTitle"] as? String ?? existing.rawTitle
            existing.currentPrice = record["currentPrice"] as? Double ?? existing.currentPrice
            existing.lastUpdated = record["lastUpdated"] as? Date ?? Date()
            existing.syncStatus = "synced"
            
            try await writer.write { db in
                try existing.update(db)
            }
        } else {
            // 创建新记录
            let newItem = GRDBLolitaItem(
                cloudKitRecordID: cloudKitID,
                platform: record["platform"] as? String ?? "other",
                platformID: platformID,
                rawTitle: record["rawTitle"] as? String ?? "",
                cleanedName: record["cleanedName"] as? String,
                brand: record["brand"] as? String,
                currentPrice: record["currentPrice"] as? Double ?? 0,
                currency: record["currency"] as? String ?? "CNY",
                status: record["status"] as? String ?? "unknown",
                isDeleted: record["isDeleted"] as? Bool ?? false,
                lastUpdated: record["lastUpdated"] as? Date ?? Date(),
                syncStatus: "synced"
            )
            
            try await writer.write { db in
                try newItem.insert(db)
            }
        }
    }
    
    // MARK: - 删除同步
    
    /// 从 CloudKit 删除记录
    func deleteFromCloud(cloudKitRecordID: String) async throws {
        let recordID = CKRecord.ID(recordName: cloudKitRecordID)
        try await publicDatabase.deleteRecord(withID: recordID)
        print("🗑️ 已从 CloudKit 删除: \(cloudKitRecordID)")
    }
}

// MARK: - 同步状态

enum SyncStatus: String {
    case pending = "pending"    // 等待同步
    case synced = "synced"      // 已同步
    case conflict = "conflict"  // 冲突
    case failed = "failed"      // 失败
}
