//
//  SkirtMarketTestDataGenerator.swift
//  裙子股市 - 测试数据生成器
//
//  用于生成模拟数据以测试界面功能
//

import Foundation
import SwiftData

/// 测试数据生成器
@MainActor
final class SkirtMarketTestDataGenerator {
    static let shared = SkirtMarketTestDataGenerator()
    
    private init() {}
    
    // MARK: - 生成测试数据
    
    /// 生成完整的测试数据集
    func generateTestData() async {
        print("🧪 开始生成裙子股市测试数据...")
        
        guard let context = SkirtMarketPersistence.shared.mainContext else {
            print("❌ 无法获取上下文")
            return
        }
        
        // 1. 生成萌款指标数据
        await generateStockMetrics(context: context)
        
        // 2. 生成大盘指数数据
        await generateMarketIndices(context: context)
        
        // 3. 生成商品数据
        await generateLolitaItems(context: context)
        
        // 4. 保存数据
        do {
            try context.save()
            print("✅ 测试数据生成完成")
        } catch {
            print("❌ 保存测试数据失败: \(error)")
        }
    }
    
    // MARK: - 生成萌款指标
    
    private func generateStockMetrics(context: ModelContext) async {
        let skirtNames = [
            "AP 辉夜姬", "Baby 铭记", "古典玩偶 小熊童子",
            "IW 罗赛特", "VM 小提琴", "MM 花葬夜",
            "JEJ 抱猫", "AP 小白云", "Baby 兔熊"
        ]
        
        let brands = ["AP", "Baby", "古典玩偶", "IW", "VM", "MM", "JEJ"]
        
        for (index, skirtName) in skirtNames.enumerated() {
            // 为每个萌款生成24小时的历史数据
            for hour in 0..<24 {
                let timestamp = Calendar.current.date(byAdding: .hour, value: -hour, to: Date()) ?? Date()
                let basePrice = Double(1000 + index * 500)
                let randomVariation = Double.random(in: -200...300)
                
                let metric = SkirtStockMetric(
                    skirtName: skirtName,
                    timestamp: timestamp,
                    highPrice: basePrice + randomVariation + 100,
                    lowPrice: basePrice + randomVariation - 100,
                    averagePrice: basePrice + randomVariation,
                    listingCount: Int.random(in: 5...50)
                )
                
                metric.brand = brands[index % brands.count]
                metric.sentimentScore = Double.random(in: -1...1)
                metric.xianyuCount = Int.random(in: 0...30)
                metric.xiaohongshuCount = Int.random(in: 0...20)
                metric.taobaoCount = Int.random(in: 0...10)
                metric.weidianCount = Int.random(in: 0...5)
                metric.bargainRatio = Double.random(in: 0...0.5)
                metric.urgentSaleRatio = Double.random(in: 0...0.3)
                metric.premiumRatio = Double.random(in: 0...0.4)
                
                context.insert(metric)
            }
        }
        
        print("  ✓ 生成 \(skirtNames.count) 个萌款的历史数据")
    }
    
    // MARK: - 生成大盘指数
    
    private func generateMarketIndices(context: ModelContext) async {
        var currentIndex: Double = 1250.0
        
        for hour in 0..<24 {
            let timestamp = Calendar.current.date(byAdding: .hour, value: -hour, to: Date()) ?? Date()
            let change = Double.random(in: -50...50)
            currentIndex += change
            
            let index = LolitaMarketIndex(
                timestamp: timestamp,
                indexValue: currentIndex,
                totalListings: Int.random(in: 500...2000)
            )
            
            index.changePercent = (change / currentIndex) * 100
            index.componentCount = Int.random(in: 10...30)
            index.averageSentiment = Double.random(in: -0.5...0.5)
            index.activeNodes = Int.random(in: 1...5)
            
            context.insert(index)
        }
        
        print("  ✓ 生成24小时大盘指数数据")
    }
    
    // MARK: - 生成商品数据
    
    private func generateLolitaItems(context: ModelContext) async {
        let platforms: [PlatformType] = [.xianyu, .xiaohongshu, .taobao, .weidian]
        let conditions = ["全新", "九成新", "八成新", "有瑕疵"]
        
        let sampleItems = [
            ("AP 辉夜姬 JSK 白色", 2800.0, "AP"),
            ("Baby 铭记 OP 粉色", 3500.0, "Baby"),
            ("古典玩偶 小熊童子", 1800.0, "古典玩偶"),
            ("IW 罗赛特 JSK", 2200.0, "IW"),
            ("VM 小提琴 SK", 1500.0, "VM"),
            ("AP 小白云 OP", 3200.0, "AP"),
            ("Baby 兔熊 大", 800.0, "Baby"),
            ("JEJ 抱猫", 4500.0, "JEJ")
        ]
        
        for (index, item) in sampleItems.enumerated() {
            let platform = platforms[index % platforms.count]
            let itemId = "test_\(index)_\(Int.random(in: 1000...9999))"
            
            let lolitaItem = LolitaItem(
                platform: platform,
                platformItemId: itemId,
                rawTitle: item.0,
                currentPrice: item.1 + Double.random(in: -300...500),
                originalURL: "https://example.com/\(itemId)"
            )
            
            lolitaItem.cleanedName = item.0
            lolitaItem.brand = item.2
            lolitaItem.condition = conditions.randomElement()
            lolitaItem.hasTags = Bool.random()
            lolitaItem.isFirstHand = Bool.random()
            lolitaItem.status = .onSale
            lolitaItem.semanticHash = "\(item.2)_\(item.0)"
            
            context.insert(lolitaItem)
        }
        
        print("  ✓ 生成 \(sampleItems.count) 个商品数据")
    }
    
    // MARK: - 清理测试数据
    
    func clearTestData() async {
        print("🧹 清理测试数据...")
        
        guard let context = SkirtMarketPersistence.shared.mainContext else {
            return
        }
        
        await clearEntity(LolitaItem.self, context: context)
        await clearEntity(SkirtStockMetric.self, context: context)
        await clearEntity(LolitaMarketIndex.self, context: context)
        await clearEntity(MonitorTask.self, context: context)
        
        do {
            try context.save()
            print("✅ 测试数据清理完成")
        } catch {
            print("❌ 清理测试数据失败: \(error)")
        }
    }
    
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
// 在App启动时生成测试数据
Task {
    await SkirtMarketTestDataGenerator.shared.generateTestData()
}

// 清理测试数据
Task {
    await SkirtMarketTestDataGenerator.shared.clearTestData()
}
*/
