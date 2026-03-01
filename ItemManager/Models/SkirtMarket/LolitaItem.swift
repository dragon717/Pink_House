//
//  LolitaItem.swift
//  裙子股市 - 核心商品模型
//
//  用于存储从各平台抓取的Lolita裙子/小物信息
//

import Foundation
import SwiftData

/// 电商平台类型
enum PlatformType: String, Codable, CaseIterable {
    case xianyu = "xianyu"
    case xiaohongshu = "xiaohongshu"
    case taobao = "taobao"
    case weidian = "weidian"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .xianyu: return "闲鱼"
        case .xiaohongshu: return "小红书"
        case .taobao: return "淘宝"
        case .weidian: return "微店"
        case .other: return "其他"
        }
    }
}

/// 商品状态
enum ItemStatus: String, Codable, CaseIterable {
    case onSale = "onSale"
    case sold = "sold"
    case reserved = "reserved"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .onSale: return "在售"
        case .sold: return "已售"
        case .reserved: return "预订"
        case .unknown: return "未知"
        }
    }
}

/// 商品类型
enum LolitaItemType: String, Codable, CaseIterable {
    case jsk = "jsk"
    case op = "op"
    case sk = "sk"
    case accessory = "accessory"
    case bag = "bag"
    case shoes = "shoes"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .jsk: return "JSK"
        case .op: return "OP"
        case .sk: return "SK"
        case .accessory: return "小物"
        case .bag: return "包"
        case .shoes: return "鞋"
        case .other: return "其他"
        }
    }
}

/// Lolita商品数据模型 - 存储在CloudKit Public DB中实现分布式共享
@Model
final class LolitaItem {
    // MARK: - 唯一标识
    
    /// CloudKit Record ID - 用于同步
    var cloudKitRecordID: String?
    
    /// 平台+商品ID组合的唯一标识，用于基础去重
    /// 格式: "platform_itemId" 例如: "xianyu_123456789"
    /// 注意：CloudKit不支持unique约束，应用层通过SkirtIndexCache去重
    var platformID: String = ""
    
    /// 内部UUID
    var id: UUID = UUID()
    
    // MARK: - 平台信息
    
    /// 来源平台
    var platform: PlatformType = PlatformType.other
    
    /// 平台原始链接
    var originalURL: String?
    
    /// 平台商品ID
    var platformItemId: String = ""
    
    // MARK: - 商品基本信息
    
    /// 商品标题（原始）
    var rawTitle: String = ""
    
    /// AI清洗后的商品名称
    var cleanedName: String?
    
    /// 品牌名称
    var brand: String?
    
    /// 商品类型
    var itemType: LolitaItemType?
    
    /// 颜色
    var color: String?
    
    /// 尺寸
    var size: String?
    
    // MARK: - 价格信息
    
    /// 当前价格
    var currentPrice: Double = 0.0
    
    /// 原价（如果有）
    var originalPrice: Double?
    
    /// 货币单位
    var currency: String = "CNY"
    
    /// 是否包含运费
    var includesShipping: Bool = false
    
    // MARK: - 商品状态
    
    /// 商品状态
    var status: ItemStatus = ItemStatus.unknown
    
    /// 成色描述（全新/九成新等）
    var condition: String?
    
    /// 是否有吊牌
    var hasTags: Bool?
    
    /// 是否一手
    var isFirstHand: Bool?
    
    // MARK: - 媒体信息
    
    /// 主图URL
    var mainImageURL: String?
    
    /// 所有图片URL（JSON数组）
    var imageURLs: String?
    
    /// 图片视觉指纹（用于AI去重）
    var visualFingerprint: String?
    
    // MARK: - AI处理结果
    
    /// 语义哈希（品牌+名称+类型+颜色组合）
    var semanticHash: String?
    
    /// AI识别的商品特征描述
    var aiDescription: String?
    
    /// AI置信度（0-1）
    var aiConfidence: Double?
    
    /// 是否为Lolita相关商品（AI过滤）
    var isLolitaRelated: Bool = true
    
    /// 情绪分析分数（-1到1，负值表示急出）
    var sentimentScore: Double?
    
    // MARK: - 卖家信息
    
    /// 卖家ID
    var sellerId: String?
    
    /// 卖家昵称
    var sellerName: String?
    
    /// 卖家信用等级
    var sellerRating: String?
    
    /// 卖家位置
    var sellerLocation: String?
    
    // MARK: - 时间戳
    
    /// 首次发现时间
    var firstSeenAt: Date = Date()
    
    /// 最后更新时间
    var lastUpdated: Date = Date()
    
    /// 商品发布时间（平台原始时间）
    var platformPostedAt: Date?
    
    /// 数据过期时间（用于自动清理）
    var expiresAt: Date?
    
    // MARK: - 分布式节点信息
    
    /// 采集该数据的设备ID
    var collectorDeviceId: String?
    
    /// 采集该数据的节点名称
    var collectorNodeName: String?
    
    /// 采集IP地区（用于反爬分析）
    var collectorRegion: String?
    
    // MARK: - 软删除标记
    
    /// 是否已删除
    var isDeleted: Bool = false
    
    /// 删除时间
    var deletedAt: Date?
    
    /// 删除原因
    var deleteReason: String?
    
    // MARK: - 初始化
    
    init(
        platform: PlatformType,
        platformItemId: String,
        rawTitle: String,
        currentPrice: Double,
        originalURL: String? = nil
    ) {
        self.id = UUID()
        self.platform = platform
        self.platformItemId = platformItemId
        self.platformID = "\(platform.rawValue)_\(platformItemId)"
        self.rawTitle = rawTitle
        self.currentPrice = currentPrice
        self.originalURL = originalURL
        
        // 默认值
        self.currency = "CNY"
        self.includesShipping = false
        self.status = .unknown
        self.isLolitaRelated = true  // 默认假设是相关商品，后续AI验证
        self.firstSeenAt = Date()
        self.lastUpdated = Date()
        self.isDeleted = false
        
        // 计算过期时间（30天后）
        self.expiresAt = Calendar.current.date(byAdding: .day, value: 30, to: Date())
    }
    
    // MARK: - 计算属性
    
    /// 显示用的商品名称（优先使用清洗后的名称）
    var displayName: String {
        cleanedName ?? rawTitle
    }
    
    /// 是否为萌款（基于价格阈值判断，可配置）
    var isPopularStyle: Bool {
        // 萌款通常价格较高或有特定关键词
        let popularKeywords = ["ap", "baby", "anp", "iw", "vm", "mm", "jej"]
        let titleLower = rawTitle.lowercased()
        return popularKeywords.contains { titleLower.contains($0) }
    }
    
    /// 价格趋势（相对于原价）
    var priceTrend: PriceTrend {
        guard let original = originalPrice, original > 0 else {
            return .unknown
        }
        let ratio = currentPrice / original
        if ratio < 0.7 {
            return .bargain  // 好价
        } else if ratio > 1.3 {
            return .premium  // 溢价
        } else {
            return .fair     // 合理
        }
    }
    
    /// 更新最后修改时间
    func touch() {
        self.lastUpdated = Date()
    }
}

// MARK: - 价格趋势枚举

enum PriceTrend: String, Codable {
    case bargain = "bargain"
    case fair = "fair"
    case premium = "premium"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .bargain: return "好价"
        case .fair: return "合理"
        case .premium: return "溢价"
        case .unknown: return "未知"
        }
    }
}

// MARK: - 查询扩展

extension LolitaItem {
    /// 按品牌查询的谓词
    static func predicateForBrand(_ brand: String) -> Predicate<LolitaItem> {
        #Predicate { item in
            item.brand == brand && item.isDeleted == false
        }
    }
    
    /// 按价格区间查询的谓词
    static func predicateForPriceRange(min: Double, max: Double) -> Predicate<LolitaItem> {
        #Predicate { item in
            item.currentPrice >= min && item.currentPrice <= max && item.isDeleted == false
        }
    }
    
    // 注意：涉及枚举的查询改为内存过滤
    
    /// 按平台过滤（内存过滤）
    static func filterByPlatform(_ platform: PlatformType, from items: [LolitaItem]) -> [LolitaItem] {
        items.filter { $0.platform == platform && !$0.isDeleted }
    }
    
    /// 按语义哈希去重查询的谓词
    static func predicateForSemanticHash(_ hash: String) -> Predicate<LolitaItem> {
        #Predicate { item in
            item.semanticHash == hash
        }
    }
    
    /// 获取活跃商品（未删除且未过期）
    static func predicateForActive() -> Predicate<LolitaItem> {
        #Predicate { item in
            item.isDeleted == false
        }
    }
}
