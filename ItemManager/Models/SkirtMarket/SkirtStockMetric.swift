//
//  SkirtStockMetric.swift
//  裙子股市 - 股市指标模型
//
//  用于存储特定裙子的市场统计数据，实现K线图和大盘指数
//

import Foundation
import SwiftData

/// 裙子股市指标 - 用于绘制K线图和大盘指数
@Model
final class SkirtStockMetric {
    // MARK: - 标识
    
    /// 唯一标识：裙子名称+时间戳
    /// 注意：CloudKit不支持unique约束
    var metricID: String = ""
    
    /// 内部UUID
    var id: UUID = UUID()
    
    // MARK: - 裙子标识
    
    /// 裙子名称（标准化后的名称）
    var skirtName: String = ""
    
    /// 品牌
    var brand: String?
    
    /// 类型
    var itemType: LolitaItemType?
    
    /// 语义哈希（关联到LolitaItem）
    var semanticHash: String?
    
    // MARK: - 时间信息
    
    /// 统计时间戳（精确到小时）
    var timestamp: Date = Date()
    
    /// 统计日期（用于按天分组）
    var dateString: String = ""  // 格式: "2024-01-15"
    
    /// 统计小时（0-23）
    var hour: Int = 0
    
    // MARK: - 价格指标（K线数据）
    
    /// 该时段最高价
    var highPrice: Double = 0.0
    
    /// 该时段最低价
    var lowPrice: Double = 0.0
    
    /// 该时段平均价
    var averagePrice: Double = 0.0
    
    /// 该时段中位数价格
    var medianPrice: Double?
    
    /// 该时段起始价格（开盘价概念）
    var openPrice: Double?
    
    /// 该时段结束价格（收盘价概念）
    var closePrice: Double?
    
    // MARK: - 成交量指标
    
    /// 全网挂牌量（去重后）
    var listingCount: Int = 0
    
    /// 新增挂牌数
    var newListings: Int = 0
    
    /// 成交数（如果可获取）
    var soldCount: Int?
    
    /// 下架数
    var removedCount: Int?
    
    // MARK: - 平台分布
    
    /// 闲鱼数量
    var xianyuCount: Int = 0
    
    /// 小红书数量
    var xiaohongshuCount: Int = 0
    
    /// 淘宝数量
    var taobaoCount: Int = 0
    
    /// 微店数量
    var weidianCount: Int = 0
    
    // MARK: - AI情绪指标
    
    /// 市场情绪分数（-1到1）
    /// 正值：积极（大家都在蹲）
    /// 负值：消极（大家都在出）
    var sentimentScore: Double = 0.0
    
    /// 急出商品比例（0-1）
    var urgentSaleRatio: Double?
    
    /// 好价商品比例（0-1）
    var bargainRatio: Double?
    
    /// 溢价商品比例（0-1）
    var premiumRatio: Double?
    
    // MARK: - 大盘指数贡献
    
    /// 该裙子对大盘指数的贡献权重
    var indexWeight: Double = 1.0
    
    /// 价格变动率（相对于上一时段）
    var priceChangeRatio: Double?
    
    /// 成交量变动率
    var volumeChangeRatio: Double?
    
    // MARK: - 分布式节点信息
    
    /// 计算该指标的设备ID
    var calculatorDeviceId: String?
    
    /// 数据来源节点数
    var sourceNodeCount: Int = 1
    
    // MARK: - 时间戳
    
    /// 记录创建时间
    var createdAt: Date = Date()
    
    /// 最后更新时间
    var lastUpdated: Date = Date()
    
    // MARK: - 初始化
    
    init(
        skirtName: String,
        timestamp: Date,
        highPrice: Double,
        lowPrice: Double,
        averagePrice: Double,
        listingCount: Int
    ) {
        self.id = UUID()
        self.skirtName = skirtName
        self.timestamp = timestamp
        
        // 生成唯一ID
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        self.metricID = "\(skirtName)_\(formatter.string(from: timestamp))"
        
        // 日期信息
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateString = formatter.string(from: timestamp)
        self.hour = Calendar.current.component(.hour, from: timestamp)
        
        // 价格
        self.highPrice = highPrice
        self.lowPrice = lowPrice
        self.averagePrice = averagePrice
        
        // 成交量
        self.listingCount = listingCount
        self.newListings = 0
        
        // 平台分布
        self.xianyuCount = 0
        self.xiaohongshuCount = 0
        self.taobaoCount = 0
        self.weidianCount = 0
        
        // 情绪
        self.sentimentScore = 0
        self.indexWeight = 1.0
        self.sourceNodeCount = 1
        
        // 时间戳
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
    
    // MARK: - 计算属性
    
    /// 价格振幅
    var priceAmplitude: Double {
        guard averagePrice > 0 else { return 0 }
        return (highPrice - lowPrice) / averagePrice
    }
    
    /// 市场热度（基于挂牌量和情绪）
    var marketHeat: Double {
        let volumeFactor = min(Double(listingCount) / 100.0, 1.0)  // 最多100件算满热度
        let sentimentFactor = (sentimentScore + 1) / 2  // 转换到0-1
        return (volumeFactor + sentimentFactor) / 2
    }
    
    /// 投资建议
    var investmentSuggestion: InvestmentSuggestion {
        if sentimentScore > 0.5 && bargainRatio ?? 0 > 0.3 {
            return .buy  // 情绪积极且好价多，建议买入
        } else if sentimentScore < -0.3 && urgentSaleRatio ?? 0 > 0.4 {
            return .strongBuy  // 大家都在出，可以抄底
        } else if premiumRatio ?? 0 > 0.5 {
            return .avoid  // 溢价太高，观望
        } else {
            return .hold  // 持有观望
        }
    }
    
    /// 更新指标
    func update(
        highPrice: Double? = nil,
        lowPrice: Double? = nil,
        averagePrice: Double? = nil,
        listingCount: Int? = nil
    ) {
        if let high = highPrice {
            self.highPrice = max(self.highPrice, high)
        }
        if let low = lowPrice {
            self.lowPrice = min(self.lowPrice, low)
        }
        if let avg = averagePrice {
            self.averagePrice = avg
        }
        if let count = listingCount {
            self.listingCount = count
        }
        self.lastUpdated = Date()
    }
}

// MARK: - 投资建议枚举

enum InvestmentSuggestion: String, Codable {
    case strongBuy = "strongBuy"
    case buy = "buy"
    case hold = "hold"
    case avoid = "avoid"
    case sell = "sell"

    var displayName: String {
        switch self {
        case .strongBuy: return "强烈建议买入"
        case .buy: return "建议买入"
        case .hold: return "持有观望"
        case .avoid: return "建议回避"
        case .sell: return "建议卖出"
        }
    }

    var icon: String {
        switch self {
        case .strongBuy: return "🔥"
        case .buy: return "📈"
        case .hold: return "⏸️"
        case .avoid: return "⚠️"
        case .sell: return "📉"
        }
    }
    
    var color: String {
        switch self {
        case .strongBuy: return "#FF4500"
        case .buy: return "#32CD32"
        case .hold: return "#FFD700"
        case .avoid: return "#FF8C00"
        case .sell: return "#DC143C"
        }
    }
}

// MARK: - 大盘指数模型

/// 萌款大盘指数 - 综合反映市场热度
@Model
final class LolitaMarketIndex {
    /// 注意：CloudKit不支持unique约束
    var timestamp: Date = Date()
    
    /// 指数值（基准1000）
    var indexValue: Double = 1000.0
    
    /// 涨跌幅
    var changePercent: Double = 0.0
    
    /// 参与计算的萌款数量
    var componentCount: Int = 0
    
    /// 总挂牌量
    var totalListings: Int = 0
    
    /// 市场平均情绪
    var averageSentiment: Double = 0.0
    
    /// 活跃节点数
    var activeNodes: Int = 1
    
    init(timestamp: Date, indexValue: Double, totalListings: Int) {
        self.timestamp = timestamp
        self.indexValue = indexValue
        self.totalListings = totalListings
        self.changePercent = 0
        self.componentCount = 0
        self.averageSentiment = 0
        self.activeNodes = 1
    }
}

// MARK: - 查询扩展

extension SkirtStockMetric {
    /// 按裙子名称查询
    static func predicateForSkirtName(_ name: String) -> Predicate<SkirtStockMetric> {
        #Predicate { metric in
            metric.skirtName == name
        }
    }
    
    /// 按日期范围查询
    static func predicateForDateRange(start: Date, end: Date) -> Predicate<SkirtStockMetric> {
        #Predicate { metric in
            metric.timestamp >= start && metric.timestamp <= end
        }
    }
    
    /// 按品牌查询
    static func predicateForBrand(_ brand: String) -> Predicate<SkirtStockMetric> {
        #Predicate { metric in
            metric.brand == brand
        }
    }
}
