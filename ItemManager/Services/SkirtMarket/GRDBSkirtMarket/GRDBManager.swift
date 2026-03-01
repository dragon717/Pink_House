//
//  GRDBManager.swift
//  裙子股市 - GRDB 本地存储管理器
//
//  使用 GRDB 完全独立于 SwiftData，避免与主应用数据库冲突
//

import Foundation
import GRDB

/// GRDB 数据库管理器
/// 完全独立于 SwiftData，使用独立的 SQLite 文件
@MainActor
final class GRDBManager {
    static let shared = GRDBManager()
    
    /// 数据库连接池
    private var dbPool: DatabasePool?
    
    /// 是否已初始化
    private(set) var isInitialized = false
    
    private init() {}
    
    // MARK: - 初始化
    
    /// 初始化 GRDB 数据库
    func initialize() async throws {
        guard !isInitialized else { return }
        
        print("📦 GRDBManager: 初始化独立数据库...")
        
        // 获取独立的存储路径
        let dbURL = try getDatabaseURL()
        
        // 配置数据库
        var config = Configuration()
        config.prepareDatabase { db in
            // 启用外键约束
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        
        // 创建数据库连接池
        dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        
        // 创建表结构
        try await createTables()
        
        isInitialized = true
        print("✅ GRDBManager: 数据库初始化成功")
        print("   📁 路径: \(dbURL.path)")
    }
    
    /// 获取数据库文件 URL
    private func getDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        
        // 使用 Application Support 下的独立子目录
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw GRDBError.cannotFindApplicationSupport
        }
        
        // 创建独立的子目录（与主应用完全隔离）
        let skirtMarketDir = appSupport.appendingPathComponent("SkirtMarketGRDB", isDirectory: true)
        
        if !fileManager.fileExists(atPath: skirtMarketDir.path) {
            try fileManager.createDirectory(at: skirtMarketDir, withIntermediateDirectories: true)
            
            // 设置不参与 iCloud 备份
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = skirtMarketDir
            try mutableURL.setResourceValues(resourceValues)
        }
        
        return skirtMarketDir.appendingPathComponent("skirt_market.sqlite")
    }
    
    // MARK: - 创建表
    
    private func createTables() async throws {
        guard let dbPool = dbPool else {
            throw GRDBError.databaseNotInitialized
        }
        
        try await dbPool.write { db in
            // 1. LolitaItem 表
            try db.create(table: "lolita_items", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("cloud_kit_record_id", .text)
                t.column("platform_id", .text).notNull()
                t.column("platform", .text).notNull()
                t.column("raw_title", .text).notNull()
                t.column("cleaned_name", .text)
                t.column("brand", .text)
                t.column("current_price", .double).notNull()
                t.column("currency", .text).notNull().defaults(to: "CNY")
                t.column("status", .text).notNull().defaults(to: "unknown")
                t.column("is_deleted", .boolean).notNull().defaults(to: false)
                t.column("last_updated", .datetime).notNull()
                t.column("first_seen_at", .datetime).notNull()
                t.column("sync_status", .text).notNull().defaults(to: "pending") // pending, synced, conflict
                t.column("modified_at", .datetime).notNull()
                t.column("price_trend", .text).notNull().defaults(to: "unknown") // bargain, fair, premium, unknown
                
                // 索引
                t.uniqueKey(["platform_id"])
            }
            
            // 2. SkirtStockMetric 表
            try db.create(table: "skirt_metrics", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("skirt_name", .text).notNull()
                t.column("platform_id", .text).notNull()
                t.column("current_price", .double).notNull()
                t.column("price_change", .double).notNull().defaults(to: 0)
                t.column("change_percent", .double).notNull().defaults(to: 0)
                t.column("volume_24h", .integer).notNull().defaults(to: 0)
                t.column("trend", .text).notNull().defaults(to: "stable")
                t.column("timestamp", .datetime).notNull()
                t.column("sync_status", .text).notNull().defaults(to: "pending")
            }
            
            // 3. LolitaMarketIndex 表
            try db.create(table: "market_indices", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("index_value", .double).notNull()
                t.column("change_percent", .double).notNull().defaults(to: 0)
                t.column("total_volume", .integer).notNull().defaults(to: 0)
                t.column("active_items", .integer).notNull().defaults(to: 0)
                t.column("timestamp", .datetime).notNull()
                t.column("sync_status", .text).notNull().defaults(to: "pending")
            }
            
            // 4. MonitorTask 表
            try db.create(table: "monitor_tasks", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("platform_id", .text).notNull()
                t.column("platform", .text).notNull()
                t.column("task_type", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("priority", .integer).notNull().defaults(to: 5)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("claimed_by", .text)
                t.column("claimed_at", .datetime)
                t.column("result", .text)
                t.column("sync_status", .text).notNull().defaults(to: "pending")
            }
            
            // 5. MonitorNode 表
            try db.create(table: "monitor_nodes", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("node_id", .text).notNull().unique()
                t.column("device_name", .text).notNull()
                t.column("is_active", .boolean).notNull().defaults(to: false)
                t.column("last_seen", .datetime).notNull()
                t.column("completed_tasks", .integer).notNull().defaults(to: 0)
                t.column("reliability_score", .double).notNull().defaults(to: 1.0)
                t.column("sync_status", .text).notNull().defaults(to: "pending")
            }
            
            // 6. SyncOutbox 表 - 用于记录需要同步到 CloudKit 的变更
            try db.create(table: "sync_outbox", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("record_type", .text).notNull() // LolitaItem, SkirtStockMetric, etc.
                t.column("record_id", .text).notNull()   // 本地记录ID
                t.column("operation", .text).notNull()   // create, update, delete
                t.column("created_at", .datetime).notNull()
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
            }
        }
        
        print("✅ 数据库表创建完成")
    }
    
    // MARK: - 公共方法
    
    /// 获取数据库连接（用于读操作）
    var reader: DatabaseReader? {
        dbPool
    }
    
    /// 获取数据库连接（用于写操作）
    var writer: DatabaseWriter? {
        dbPool
    }
    
    /// 执行数据库迁移
    func migrate() async throws {
        // 未来版本的数据库迁移在这里处理
        print("📦 数据库迁移检查...")
    }
}

// MARK: - 错误类型

enum GRDBError: Error {
    case cannotFindApplicationSupport
    case databaseNotInitialized
    case migrationFailed(String)
}
