//
//  GRDBLolitaItem.swift
//  裙子股市 - GRDB 数据模型
//
//  完全独立于 SwiftData 的 LolitaItem 模型
//

import Foundation
import GRDB

/// GRDB 版本的 LolitaItem
/// 使用 Codable 和 GRDB 的 Record 协议
struct GRDBLolitaItem: Codable, FetchableRecord, PersistableRecord, Identifiable {
    // MARK: - 字段
    
    /// 本地唯一ID
    var id: String
    
    /// CloudKit Record ID
    var cloudKitRecordID: String?
    
    /// 平台+商品ID组合的唯一标识
    var platformID: String
    
    /// 来源平台
    var platform: String
    
    /// 商品标题（原始）
    var rawTitle: String
    
    /// AI清洗后的商品名称
    var cleanedName: String?
    
    /// 品牌名称
    var brand: String?
    
    /// 当前价格
    var currentPrice: Double
    
    /// 货币单位
    var currency: String
    
    /// 商品状态
    var status: String
    
    /// 是否已删除
    var isDeleted: Bool
    
    /// 首次发现时间
    var firstSeenAt: Date
    
    /// 最后更新时间
    var lastUpdated: Date
    
    /// 同步状态: pending, synced, conflict
    var syncStatus: String
    
    /// 本地修改时间（用于冲突检测）
    var modifiedAt: Date
    
    /// 价格趋势: bargain(好价), fair(合理), premium(溢价), unknown(未知)
    var priceTrend: String
    
    // MARK: - 表名
    
    static var databaseTableName: String {
        "lolita_items"
    }
    
    // MARK: - 初始化
    
    init(
        id: String = UUID().uuidString,
        cloudKitRecordID: String? = nil,
        platform: String,
        platformID: String,
        rawTitle: String,
        cleanedName: String? = nil,
        brand: String? = nil,
        currentPrice: Double,
        currency: String = "CNY",
        status: String = "unknown",
        isDeleted: Bool = false,
        firstSeenAt: Date = Date(),
        lastUpdated: Date = Date(),
        syncStatus: String = "pending",
        modifiedAt: Date = Date(),
        priceTrend: String = "unknown"
    ) {
        self.id = id
        self.cloudKitRecordID = cloudKitRecordID
        self.platform = platform
        self.platformID = platformID
        self.rawTitle = rawTitle
        self.cleanedName = cleanedName
        self.brand = brand
        self.currentPrice = currentPrice
        self.currency = currency
        self.status = status
        self.isDeleted = isDeleted
        self.firstSeenAt = firstSeenAt
        self.lastUpdated = lastUpdated
        self.syncStatus = syncStatus
        self.modifiedAt = modifiedAt
        self.priceTrend = priceTrend
    }
    
    // MARK: - 计算属性
    
    /// 显示用的商品名称
    var displayName: String {
        cleanedName ?? rawTitle
    }
    
    /// 是否为萌款（基于价格阈值判断，可配置）
    var isPopularStyle: Bool {
        let popularKeywords = ["ap", "baby", "anp", "iw", "vm", "mm", "jej"]
        let titleLower = rawTitle.lowercased()
        return popularKeywords.contains { titleLower.contains($0) }
    }
}

// MARK: - 数据库列定义

extension GRDBLolitaItem {
    /// 定义数据库列
    enum Columns {
        static let id = Column("id")
        static let cloudKitRecordID = Column("cloud_kit_record_id")
        static let platformID = Column("platform_id")
        static let platform = Column("platform")
        static let rawTitle = Column("raw_title")
        static let cleanedName = Column("cleaned_name")
        static let brand = Column("brand")
        static let currentPrice = Column("current_price")
        static let currency = Column("currency")
        static let status = Column("status")
        static let isDeleted = Column("is_deleted")
        static let firstSeenAt = Column("first_seen_at")
        static let lastUpdated = Column("last_updated")
        static let syncStatus = Column("sync_status")
        static let modifiedAt = Column("modified_at")
        static let priceTrend = Column("price_trend")
    }
}

// MARK: - 查询扩展

extension GRDBLolitaItem {
    /// 获取所有未删除的商品
    static func fetchAllActive(_ db: Database) throws -> [GRDBLolitaItem] {
        try GRDBLolitaItem
            .filter(Columns.isDeleted == false)
            .order(Columns.lastUpdated.desc)
            .fetchAll(db)
    }
    
    /// 按平台查询
    static func fetchByPlatform(_ db: Database, platform: String) throws -> [GRDBLolitaItem] {
        try GRDBLolitaItem
            .filter(Columns.platform == platform && Columns.isDeleted == false)
            .order(Columns.lastUpdated.desc)
            .fetchAll(db)
    }
    
    /// 按品牌查询
    static func fetchByBrand(_ db: Database, brand: String) throws -> [GRDBLolitaItem] {
        try GRDBLolitaItem
            .filter(Columns.brand == brand && Columns.isDeleted == false)
            .order(Columns.lastUpdated.desc)
            .fetchAll(db)
    }
    
    /// 按价格区间查询
    static func fetchByPriceRange(_ db: Database, min: Double, max: Double) throws -> [GRDBLolitaItem] {
        try GRDBLolitaItem
            .filter(Columns.currentPrice >= min && Columns.currentPrice <= max && Columns.isDeleted == false)
            .order(Columns.currentPrice.desc)
            .fetchAll(db)
    }
    
    /// 按 platformID 查询（用于去重）
    static func fetchByPlatformID(_ db: Database, platformID: String) throws -> GRDBLolitaItem? {
        try GRDBLolitaItem
            .filter(Columns.platformID == platformID)
            .fetchOne(db)
    }
    
    /// 获取需要同步的记录
    static func fetchPendingSync(_ db: Database, limit: Int = 100) throws -> [GRDBLolitaItem] {
        try GRDBLolitaItem
            .filter(Columns.syncStatus == "pending")
            .order(Columns.modifiedAt.asc)
            .limit(limit)
            .fetchAll(db)
    }
    
    /// 更新同步状态
    func markAsSynced(_ db: Database, cloudKitRecordID: String? = nil) throws {
        var updated = self
        updated.syncStatus = "synced"
        updated.cloudKitRecordID = cloudKitRecordID ?? self.cloudKitRecordID
        try updated.update(db)
    }
    
    /// 软删除
    func softDelete(_ db: Database) throws {
        var updated = self
        updated.isDeleted = true
        updated.syncStatus = "pending"
        updated.modifiedAt = Date()
        try updated.update(db)
    }
}

// MARK: - SwiftUI 响应式支持

import SwiftUI
import Combine

/// GRDB 观察器 - 替代 SwiftUI 的 @Query
/// 监听数据库变化并自动更新视图
@MainActor
final class GRDBLolitaItemObserver: ObservableObject {
    @Published var items: [GRDBLolitaItem] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private var observation: DatabaseCancellable?
    
    /// 开始观察所有活跃商品
    func startObservingActive() {
        isLoading = true
        
        guard let reader = GRDBManager.shared.reader else {
            error = GRDBError.databaseNotInitialized
            isLoading = false
            return
        }
        
        // 创建观察器
        let observation = ValueObservation.tracking { db in
            try GRDBLolitaItem.fetchAllActive(db)
        }
        
        self.observation = observation.start(
            in: reader,
            scheduling: .immediate,
            onError: { [weak self] error in
                self?.error = error
                self?.isLoading = false
            },
            onChange: { [weak self] items in
                self?.items = items
                self?.isLoading = false
            }
        )
    }
    
    /// 开始观察特定平台的商品
    func startObservingPlatform(_ platform: String) {
        isLoading = true
        
        guard let reader = GRDBManager.shared.reader else {
            error = GRDBError.databaseNotInitialized
            isLoading = false
            return
        }
        
        let observation = ValueObservation.tracking { db in
            try GRDBLolitaItem.fetchByPlatform(db, platform: platform)
        }
        
        self.observation = observation.start(
            in: reader,
            scheduling: .immediate,
            onError: { [weak self] error in
                self?.error = error
                self?.isLoading = false
            },
            onChange: { [weak self] items in
                self?.items = items
                self?.isLoading = false
            }
        )
    }
    
    /// 停止观察
    func stopObserving() {
        observation?.cancel()
        observation = nil
    }
    
    deinit {
        observation?.cancel()
    }
}
