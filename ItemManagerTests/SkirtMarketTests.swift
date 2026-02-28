//
//  SkirtMarketTests.swift
//  ItemManagerTests
//
//  裙子股市单元测试
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class SkirtMarketTests: XCTestCase {
    
    // MARK: - 测试数据
    
    func testLolitaItemCreation() {
        let item = LolitaItem(
            platform: .xianyu,
            platformItemId: "123456",
            rawTitle: "AP 辉夜姬 黑色 JSK",
            currentPrice: 15800.0
        )
        
        XCTAssertEqual(item.platform, .xianyu)
        XCTAssertEqual(item.platformID, "闲鱼_123456")
        XCTAssertEqual(item.rawTitle, "AP 辉夜姬 黑色 JSK")
        XCTAssertEqual(item.currentPrice, 15800.0)
        XCTAssertFalse(item.isDeleted)
    }
    
    func testSemanticHashGeneration() {
        let item = LolitaItem(
            platform: .xianyu,
            platformItemId: "123456",
            rawTitle: "AP 辉夜姬 黑色 JSK",
            currentPrice: 15800.0
        )
        
        item.cleanedName = "辉夜姬"
        item.brand = "AP"
        item.itemType = .jsk
        item.color = "黑"
        item.semanticHash = "ap_辉夜姬_jsk_黑"
        
        XCTAssertEqual(item.semanticHash, "ap_辉夜姬_jsk_黑")
        XCTAssertTrue(item.isPopularStyle)
    }
    
    // MARK: - 测试索引缓存
    
    func testSkirtIndexCache() async {
        let cache = SkirtIndexCache.shared
        
        // 清空缓存
        cache.clearCache()
        XCTAssertEqual(cache.cachedItemCount, 0)
        
        // 创建测试商品
        let item = LolitaItem(
            platform: .xianyu,
            platformItemId: "test123",
            rawTitle: "测试裙子",
            currentPrice: 1000.0
        )
        item.semanticHash = "test_brand_name_jsk"
        
        // 更新缓存
        cache.updateCache(with: item)
        XCTAssertEqual(cache.cachedItemCount, 1)
        
        // 测试查找
        let found = cache.findByPlatformID(item.platformID)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.platformID, item.platformID)
        
        // 测试语义哈希查找
        let byHash = cache.findBySemanticHash("test_brand_name_jsk")
        XCTAssertEqual(byHash.count, 1)
        
        // 测试重复检查
        let isDuplicate = cache.hasDuplicate(
            semanticHash: "test_brand_name_jsk",
            platformID: "different_id"
        )
        XCTAssertTrue(isDuplicate)
        
        // 清理
        cache.clearCache()
    }
    
    // MARK: - 测试任务模型
    
    func testMonitorTaskLifecycle() {
        let task = MonitorTask(
            taskType: .search,
            platform: .xianyu,
            keyword: "AP 辉夜姬",
            priority: 5,
            creatorNodeId: "test_node"
        )
        
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.taskType, .search)
        XCTAssertEqual(task.platform, .xianyu)
        XCTAssertEqual(task.keyword, "AP 辉夜姬")
        
        // 测试分配
        let assigned = task.assign(to: "worker_node")
        XCTAssertTrue(assigned)
        XCTAssertEqual(task.status, .assigned)
        XCTAssertEqual(task.assignedNodeId, "worker_node")
        
        // 测试开始处理
        let started = task.startProcessing()
        XCTAssertTrue(started)
        XCTAssertEqual(task.status, .processing)
        
        // 测试完成
        task.complete(itemsFound: 10, itemsNew: 5)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.itemsFound, 10)
        XCTAssertEqual(task.itemsNew, 5)
    }
    
    func testTaskRetry() {
        let task = MonitorTask(
            taskType: .search,
            platform: .xianyu,
            keyword: "测试",
            priority: 5,
            creatorNodeId: "test_node"
        )
        
        _ = task.assign(to: "worker")
        _ = task.startProcessing()
        
        // 模拟失败
        task.fail(reason: "网络错误")
        XCTAssertEqual(task.retryCount, 1)
        XCTAssertEqual(task.status, .pending) // 重置为待处理
        
        // 重试直到超过最大重试次数
        for _ in 0..<task.maxRetries {
            _ = task.assign(to: "worker")
            _ = task.startProcessing()
            task.fail(reason: "网络错误")
        }
        
        XCTAssertEqual(task.status, .failed)
    }
    
    // MARK: - 测试股市指标
    
    func testSkirtStockMetric() {
        let metric = SkirtStockMetric(
            skirtName: "AP 辉夜姬",
            timestamp: Date(),
            highPrice: 18000.0,
            lowPrice: 15000.0,
            averagePrice: 16500.0,
            listingCount: 25
        )
        
        XCTAssertEqual(metric.skirtName, "AP 辉夜姬")
        XCTAssertEqual(metric.highPrice, 18000.0)
        XCTAssertEqual(metric.lowPrice, 15000.0)
        XCTAssertEqual(metric.averagePrice, 16500.0)
        XCTAssertEqual(metric.listingCount, 25)
        
        // 测试价格振幅
        let amplitude = metric.priceAmplitude
        XCTAssertGreaterThan(amplitude, 0)
        
        // 测试投资建议
        metric.sentimentScore = 0.6
        metric.bargainRatio = 0.4
        let suggestion = metric.investmentSuggestion
        XCTAssertEqual(suggestion, .buy)
    }
    
    // MARK: - 测试去重结果
    
    func testDeduplicationResult() {
        let newItemResult = DeduplicationResult.newItem
        let duplicateResult = DeduplicationResult.duplicate(existingItemID: "test_id")
        let similarResult = DeduplicationResult.similarButDifferent(similarItemID: "similar_id")
        
        // 验证结果可以被正确处理
        var newCount = 0
        var duplicateCount = 0
        
        for result in [newItemResult, duplicateResult, similarResult] {
            switch result {
            case .newItem:
                newCount += 1
            case .duplicate:
                duplicateCount += 1
            case .similarButDifferent:
                newCount += 1
            }
        }
        
        XCTAssertEqual(newCount, 2)
        XCTAssertEqual(duplicateCount, 1)
    }
    
    // MARK: - 测试批量去重结果
    
    func testBatchDeduplicationResult() {
        let result = BatchDeduplicationResult(
            totalProcessed: 100,
            duplicatesFound: 30,
            newItems: 70,
            cacheHits: 20,
            aiProcessed: 80,
            details: []
        )
        
        XCTAssertEqual(result.totalProcessed, 100)
        XCTAssertEqual(result.duplicatesFound, 30)
        XCTAssertEqual(result.newItems, 70)
        XCTAssertEqual(result.cacheHits, 20)
        XCTAssertEqual(result.aiProcessed, 80)
        XCTAssertEqual(result.cacheHitRate, 0.2)
        XCTAssertEqual(result.aiSavingsRate, 0.2)
    }
}

// MARK: - 性能测试

@MainActor
final class SkirtMarketPerformanceTests: XCTestCase {
    
    func testIndexCachePerformance() {
        let cache = SkirtIndexCache.shared
        cache.clearCache()
        
        // 创建大量测试数据
        for i in 0..<1000 {
            let item = LolitaItem(
                platform: .xianyu,
                platformItemId: "perf_\(i)",
                rawTitle: "测试商品 \(i)",
                currentPrice: Double.random(in: 1000...10000)
            )
            item.semanticHash = "hash_\(i % 100)" // 100个不同的哈希
            cache.updateCache(with: item)
        }
        
        measure {
            // 测试查找性能
            for i in 0..<100 {
                _ = cache.findBySemanticHash("hash_\(i)")
            }
        }
        
        cache.clearCache()
    }
}
