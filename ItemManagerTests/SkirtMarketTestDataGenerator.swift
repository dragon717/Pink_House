//
//  SkirtMarketTestDataGenerator.swift
//  裙装股市 - 测试数据生成器
//
//  用于生成模拟数据以验证功能
//

import Foundation
import SwiftData

/// 测试数据生成器
@MainActor
final class SkirtMarketTestDataGenerator {
    static let shared = SkirtMarketTestDataGenerator()
    
    private init() {}
    
    // MARK: - 测试数据配置
    
    private let testSkirts = [
        ("AP 辉夜姬", "AP", LolitaItemType.jsk, 15800.0),
        ("Baby 铭记", "Baby", LolitaItemType.op, 12800.0),
        ("古典玩偶 熊童子", "古典玩偶", LolitaItemType.jsk, 9800.0),
        ("IW 提琴", "IW", LolitaItemType.jsk, 8500.0),
        ("VM 小玫瑰", "VM", LolitaItemType.sk, 7200.0),
        ("MM 圣女", "MM", LolitaItemType.op, 16800.0),
        ("JeJ 抱猫", "JeJ", LolitaItemType.jsk, 14500.0),
        ("AP 小白云", "AP", LolitaItemType.op, 11200.0),
        ("Baby 兔熊", "Baby", LolitaItemType.accessory, 3200.0),
        ("AP 贝壳", "AP", LolitaItemType.jsk, 18900.0)
    ]
    
    private let testKeywords = [
        "AP 辉夜姬", "Baby 铭记", "古典玩偶", "IW 提琴", "VM 小玫瑰",
        "MM 圣女", "JeJ 抱猫", "AP 小白云", "Baby 兔熊", "AP 贝壳",
        "Lolita 萌款", "日牌 裙装", "国牌 原创"
    ]
    
    // MARK: - 生成测试数据
    
    /// 生成完整的测试数据集
    func generateTestData() async {
        print("🧪 开始生成测试数据...")
        
        await generateTestItems()
        await generateTestMetrics()
        await generateTestTasks()
        await generateTestIndex()
        
        print("✅ 测试数据生成完成")
    }
    
    /// 生成测试商品数据
    private func generateTestItems() async {
        guard let context = SkirtMarketPersistence.shared.mainContext else {
            print("❌ 无法获取上下文")
            return
        }
        
        let platforms: [PlatformType] = [.xianyu, .xiaohongshu, .taobao, .weidian]
        let conditions = ["全新", "九成新", "八成新", "有瑕疵"]
        let colors = ["黑", "白", "粉", "蓝", "红", "紫", "生成", "若草"]
        
        var generatedCount = 0
        
        for (name, brand, type, basePrice) in testSkirts {
            // 每个裙装生成3-5个不同平台的商品
            let itemCount = Int.random(in: 3...5)
            
            for i in 0..<itemCount {
                let platform = platforms.randomElement()!
                let platformId = "test_\(platform.rawValue)_\(name)_\(i)_\(Int.random(in: 1000...9999))"
                
                // 价格波动 ±20%
                let priceVariation = Double.random(in: 0.8...1.2)
                let price = basePrice * priceVariation
                
                let item = LolitaItem(
                    platform: platform,
                    platformItemId: platformId,
                    rawTitle: "\(name) \(conditions.randomElement()!) \(colors.randomElement()!)",
                    currentPrice: price,
                    originalURL: "https://example.com/\(platformId)"
                )
                
                // 填充额外信息
                item.cleanedName = name
                item.brand = brand
                item.itemType = type
                item.color = colors.randomElement()
                item.condition = conditions.randomElement()
                item.status = Bool.random() ? .onSale : .sold
                item.isLolitaRelated = true
                item.semanticHash = "\(brand)_\(name)_\(type.rawValue)".lowercased()
                item.sentimentScore = Double.random(in: -0.5...0.5)
                item.aiConfidence = Double.random(in: 0.7...0.95)
                
                // 随机时间（过去7天内）
                let daysAgo = Double.random(in: 0...7)
                item.firstSeenAt = Date().addingTimeInterval(-daysAgo * 24 * 60 * 60)
                item.lastUpdated = item.firstSeenAt
                
                context.insert(item)
                generatedCount += 1
            }
        }
        
        do {
            try context.save()
            print("✅ 生成 \(generatedCount) 个测试商品")
        } catch {
            print("❌ 保存测试商品失败: \(error)")
        }
    }
    
    /// 生成测试股市指标
    private func generateTestMetrics() async {
        guard let context = SkirtMarketPersistence.shared.mainContext else { return }
        
        let calendar = Calendar.current
        let now = Date()
        
        for (name, brand, type, basePrice) in testSkirts {
            // 生成过去7天，每天的数据
            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
                
                // 价格波动
                let priceVariation = Double.random(in: 0.9...1.1)
                let avgPrice = basePrice * priceVariation
                let highPrice = avgPrice * Double.random(in: 1.0...1.15)
                let lowPrice = avgPrice * Double.random(in: 0.85...1.0)
                
                let metric = SkirtStockMetric(
                    skirtName: name,
                    timestamp: date,
                    highPrice: highPrice,
                    lowPrice: lowPrice,
                    averagePrice: avgPrice,
                    listingCount: Int.random(in: 5...50)
                )
                
                metric.brand = brand
                metric.itemType = type
                metric.newListings = Int.random(in: 0...10)
                metric.xianyuCount = Int.random(in: 2...20)
                metric.xiaohongshuCount = Int.random(in: 1...15)
                metric.taobaoCount = Int.random(in: 0...10)
                metric.weidianCount = Int.random(in: 0...5)
                metric.sentimentScore = Double.random(in: -0.3...0.3)
                metric.bargainRatio = Double.random(in: 0.1...0.4)
                metric.premiumRatio = Double.random(in: 0.1...0.3)
                metric.urgentSaleRatio = Double.random(in: 0.05...0.2)
                
                context.insert(metric)
            }
        }
        
        do {
            try context.save()
            print("✅ 生成股市指标数据")
        } catch {
            print("❌ 保存股市指标失败: \(error)")
        }
    }
    
    /// 生成测试任务
    private func generateTestTasks() async {
        guard let context = SkirtMarketPersistence.shared.mainContext else { return }
        
        let platforms: [PlatformType] = [.xianyu, .xiaohongshu, .taobao, .weidian]
        let creatorNodeId = TaskDispatcher.shared.currentNodeId
        
        // 生成一些待处理任务
        for keyword in testKeywords.prefix(5) {
            let platform = platforms.randomElement()!
            let task = MonitorTask(
                taskType: .search,
                platform: platform,
                keyword: keyword,
                priority: Int.random(in: 3...8),
                creatorNodeId: creatorNodeId
            )
            context.insert(task)
        }
        
        // 生成一些已完成任务
        for keyword in testKeywords.suffix(3) {
            let platform = platforms.randomElement()!
            let task = MonitorTask(
                taskType: .search,
                platform: platform,
                keyword: keyword,
                priority: Int.random(in: 3...8),
                creatorNodeId: creatorNodeId
            )
            _ = task.assign(to: creatorNodeId)
            _ = task.startProcessing()
            task.complete(itemsFound: Int.random(in: 5...15), itemsNew: Int.random(in: 2...8))
            context.insert(task)
        }
        
        do {
            try context.save()
            print("✅ 生成测试任务")
        } catch {
            print("❌ 保存测试任务失败: \(error)")
        }
    }
    
    /// 生成测试大盘指数
    private func generateTestIndex() async {
        guard let context = SkirtMarketPersistence.shared.mainContext else { return }
        
        let calendar = Calendar.current
        let now = Date()
        var currentIndex: Double = 1250.0
        
        // 生成过去30天的指数
        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            
            // 随机波动 ±3%
            let change = Double.random(in: -0.03...0.03)
            currentIndex = currentIndex * (1 + change)
            
            let index = LolitaMarketIndex(
                timestamp: date,
                indexValue: currentIndex,
                totalListings: Int.random(in: 500...2000)
            )
            
            index.changePercent = change * 100
            index.componentCount = testSkirts.count
            index.averageSentiment = Double.random(in: -0.2...0.2)
            index.activeNodes = Int.random(in: 1...5)
            
            context.insert(index)
        }
        
        do {
            try context.save()
            print("✅ 生成大盘指数数据")
        } catch {
            print("❌ 保存大盘指数失败: \(error)")
        }
    }
    
    // MARK: - 清理测试数据
    
    /// 清理所有测试数据
    func clearTestData() async {
        print("🧹 清理测试数据...")
        
        guard let context = SkirtMarketPersistence.shared.mainContext else { return }
        
        // 分别清理每种实体类型
        await clearEntity(LolitaItem.self, context: context)
        await clearEntity(SkirtStockMetric.self, context: context)
        await clearEntity(MonitorTask.self, context: context)
        await clearEntity(MonitorNode.self, context: context)
        await clearEntity(LolitaMarketIndex.self, context: context)
        
        do {
            try context.save()
            print("✅ 测试数据已清理")
        } catch {
            print("❌ 清理测试数据失败: \(error)")
        }
    }
    
    /// 清理指定类型的实体
    private func clearEntity<T: PersistentModel>(_ type: T.Type, context: ModelContext) async {
        let descriptor = FetchDescriptor<T>()
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
        }
    }
}

// MARK: - 使用示例

/*
// 在开发调试时生成测试数据
Button("生成测试数据") {
    Task {
        await SkirtMarketTestDataGenerator.shared.generateTestData()
    }
}

// 清理测试数据
Button("清理测试数据") {
    Task {
        await SkirtMarketTestDataGenerator.shared.clearTestData()
    }
}
*/
