//
//  SkirtMarketTests.swift
//  ItemManagerTests
//
//  裙装股市单元测试
//

import XCTest
import SwiftData
import GRDB
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
            rawTitle: "测试裙装",
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

    func testSkirtMarketImportParserExtractsPlatformURLAndPrice() {
        let taobao = SkirtMarketImportParser.localParse("淘宝 AP 辉夜姬 JSK ¥1580 https://item.taobao.com/item.htm?id=123456")
        XCTAssertEqual(taobao.platformHint, "taobao")
        XCTAssertEqual(taobao.sourceURL, "https://item.taobao.com/item.htm?id=123456")
        XCTAssertEqual(taobao.price, 1580)

        let xianyu = SkirtMarketImportParser.localParse("闲鱼急出 Baby 裙子 价格：880 https://www.goofish.com/item?id=abc")
        XCTAssertEqual(xianyu.platformHint, "xianyu")
        XCTAssertEqual(xianyu.price, 880)

        let xhs = SkirtMarketImportParser.localParse("小红书笔记 https://xhslink.com/a1b2c3")
        XCTAssertEqual(xhs.platformHint, "xiaohongshu")
    }

    func testParsedItemBuildsTimedPriceEvents() {
        let capturedAt = Date()
        var item = ParsedItem.fallback(
            from: SkirtMarketImportLocalParse(
                platformHint: "taobao",
                sourceURL: "https://item.taobao.com/item.htm?id=123456",
                title: "AP 辉夜姬 JSK",
                price: 1580
            ),
            rawText: "AP 辉夜姬 JSK",
            capturedAt: capturedAt
        )
        item.originalPriceText = "1980"
        item.depositPriceText = "200"
        item.balancePriceText = "1380"
        item.depositDateText = "2026-07-01"
        item.finalPaymentDateText = "2026-08-01"

        let events = item.priceEvents()
        XCTAssertEqual(events.map(\.kind), ["current", "original", "deposit", "balance"])
        XCTAssertTrue(events.allSatisfy { $0.observedAt == capturedAt })
        XCTAssertNotNil(events.first(where: { $0.kind == "deposit" })?.appliesAt)
        XCTAssertNotNil(events.first(where: { $0.kind == "balance" })?.appliesAt)
    }

    func testDeepSeekJSONMapsToRecordableParsedItem() throws {
        let rawJSON = """
        {
          "items": [
            {
              "title": "AP 辉夜姬 黑色 JSK",
              "brand": "Angelic Pretty",
              "series": "辉夜姬",
              "category": "jsk",
              "color": "黑色",
              "size": "M",
              "condition": "全新",
              "is_lolita_related": true,
              "sale_intent": "reservation",
              "confidence": 0.92,
              "missing_fields": [],
              "price_events": [
                {"kind": "current", "amount": 1580, "currency": "CNY", "observed_at": "2026-06-25T08:00:00Z", "applies_at": null, "note": null},
                {"kind": "original", "amount": 1980, "currency": "CNY", "observed_at": "2026-06-25T08:00:00Z", "applies_at": null, "note": null},
                {"kind": "deposit", "amount": 200, "currency": "CNY", "observed_at": "2026-06-25T08:00:00Z", "applies_at": "2026-07-01", "note": null},
                {"kind": "balance", "amount": 1380, "currency": "CNY", "observed_at": "2026-06-25T08:00:00Z", "applies_at": "2026-08-01", "note": null}
              ]
            }
          ]
        }
        """
        let response = try JSONDecoder().decode(SkirtMarketDeepSeekResponse.self, from: Data(rawJSON.utf8))
        let local = SkirtMarketImportParser.localParse("淘宝 AP 辉夜姬 JSK ¥1580 https://item.taobao.com/item.htm?id=123456")
        let capturedAt = ISO8601DateFormatter().date(from: "2026-06-25T08:00:00Z")!
        let parsed = ParsedItem.fromAI(response.items[0], local: local, rawText: "raw", rawJSON: rawJSON, capturedAt: capturedAt)
        let record = parsed.makeGRDBItem()

        XCTAssertEqual(parsed.title, "AP 辉夜姬 黑色 JSK")
        XCTAssertEqual(record.brand, "Angelic Pretty")
        XCTAssertEqual(record.cleanedName, "辉夜姬")
        XCTAssertEqual(record.currentPrice, 1580)
        XCTAssertEqual(record.originalPrice, 1980)
        XCTAssertEqual(record.depositPrice, 200)
        XCTAssertEqual(record.balancePrice, 1380)
        XCTAssertNotNil(record.depositDate)
        XCTAssertNotNil(record.finalPaymentDate)
        XCTAssertEqual(parsed.priceEvents().count, 4)
    }

    func testGRDBPersistsParsedItemAndPriceEvents() throws {
        let rawJSON = #"{"items":[]}"#
        let capturedAt = ISO8601DateFormatter().date(from: "2026-06-25T08:00:00Z")!
        var parsed = ParsedItem.fallback(
            from: SkirtMarketImportLocalParse(
                platformHint: "xianyu",
                sourceURL: "https://www.goofish.com/item?id=abc",
                title: "Baby 海月姬 OP",
                price: 880
            ),
            rawText: "闲鱼 Baby 海月姬 OP 价格：880",
            capturedAt: capturedAt
        )
        parsed.brand = "Baby"
        parsed.series = "海月姬"
        parsed.originalPriceText = "1680"
        parsed.rawAnalysisJSON = rawJSON

        let queue = try makeSkirtMarketDatabaseQueue()
        let record = parsed.makeGRDBItem()
        let events = parsed.priceEvents()

        try queue.write { db in
            try record.insert(db)
            for event in events {
                try event.insert(db)
            }
        }

        let saved = try queue.read { db in
            try GRDBLolitaItem.fetchByPlatformID(db, platformID: record.platformID)
        }
        let savedEvents = try queue.read { db in
            try GRDBLolitaPriceEvent
                .filter(Column("platform_id") == record.platformID)
                .fetchAll(db)
        }

        XCTAssertEqual(saved?.rawTitle, "Baby 海月姬 OP")
        XCTAssertEqual(saved?.brand, "Baby")
        XCTAssertEqual(saved?.currentPrice, 880)
        XCTAssertEqual(saved?.originalPrice, 1680)
        XCTAssertEqual(saved?.analysisCapturedAt, capturedAt)
        XCTAssertEqual(Set(savedEvents.map(\.kind)), Set(["current", "original"]))
        XCTAssertTrue(savedEvents.allSatisfy { $0.observedAt == capturedAt })
    }

    private func makeSkirtMarketDatabaseQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.create(table: "lolita_items") { t in
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
                t.column("sync_status", .text).notNull().defaults(to: "pending")
                t.column("modified_at", .datetime).notNull()
                t.column("price_trend", .text).notNull().defaults(to: "unknown")
                t.column("source_url", .text)
                t.column("original_price", .double)
                t.column("deposit_price", .double)
                t.column("balance_price", .double)
                t.column("deposit_date", .datetime)
                t.column("final_payment_date", .datetime)
                t.column("analysis_captured_at", .datetime)
                t.column("analysis_confidence", .double)
                t.column("raw_analysis_json", .text)
                t.uniqueKey(["platform_id"])
            }

            try db.create(table: "lolita_price_events") { t in
                t.primaryKey("id", .text)
                t.column("platform_id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("amount", .double).notNull()
                t.column("currency", .text).notNull().defaults(to: "CNY")
                t.column("observed_at", .datetime).notNull()
                t.column("applies_at", .datetime)
                t.column("source", .text).notNull()
            }
        }
        return queue
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
