//
//  TimeHallTreasuredWishMigrationTests.swift
//  ItemManagerTests
//
//  重构方案 §5.6 收藏行 / §7 Phase 4 前置：旧馆收藏（timeHall.treasured.v1）
//  → 心愿尾款 运行时一次性迁移（2026-09-21 口径确认：PriceMode.wishlist）。
//    · 直查匹配："th-\(treasuredID)"
//    · productCode 二级解析："th-\(productCode)"
//    · 未匹配 → 留旧馆归档（unmatched 记录，treasured.v1 不动）
//    · 幂等：逐条跳过已有 catalogProductID 记录；标记键只跑一轮
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class TimeHallTreasuredWishMigrationTests: XCTestCase {

    private var store = ShopCatalogStore()
    private var retainedContainers: [ModelContainer] = []
    private var testDefaults: UserDefaults!
    private let suiteName = "TimeHallTreasuredWishMigrationTests"

    override func setUp() {
        super.setUp()
        // 整域清理：收藏键（v1/v2）与迁移标记都不得跨测试残留，
        // 否则 TimeHallUserStateStore.load() 的并集会污染后续用例
        Self.cleanSuite()
        testDefaults = UserDefaults(suiteName: suiteName)
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
    }

    override func tearDown() {
        Self.cleanSuite()
        super.tearDown()
    }

    private static func cleanSuite() {
        let defaults = UserDefaults(suiteName: "TimeHallTreasuredWishMigrationTests")
        defaults?.removeObject(forKey: TimeHallTreasuredWishMigrator.markerKey)
        defaults?.removeObject(forKey: TimeHallTreasuredWishMigrator.checkpointKey)
        defaults?.removeObject(forKey: "timeHall.treasured.v1")
        defaults?.removeObject(forKey: "timeHall.treasured.v2")
    }

    /// 取一个有价格档案的迁移商品（心愿落库后 balance = 全款 > 0，供断言）
    private func pricedTHProduct() -> CatalogProduct? {
        store.catalog?.products.first {
            $0.id.hasPrefix("th-")
                && (store.priceArchive(forProduct: $0.id).currentStockPrice
                    ?? store.priceArchive(forProduct: $0.id).historicalReservationPrice) != nil
        }
    }

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    /// 任意收藏 → 指定落库结果（追加式，供多收藏场景组合）
    private func addUserState(_ ids: [String]) -> TimeHallUserStateStore {
        let userState = TimeHallUserStateStore(defaults: testDefaults)
        for id in ids { userState.setTreasured(id, true) }
        return userState
    }

    // MARK: 直查匹配 → 心愿尾款记录

    func testDirectMatchCreatesWishlistRecord() throws {
        // 取种子里有价格档案的真实迁移商品，用其源 id 作收藏 id
        let product = try XCTUnwrap(
            pricedTHProduct(),
            "合并种子后应存在带价格的 th- 迁移商品")
        let treasuredID = String(product.id.dropFirst(3))
        let context = modelContext()

        let report = TimeHallTreasuredWishMigrator.run(
            store: store,
            userState: addUserState([treasuredID]),
            defaults: testDefaults,
            modelContext: context)

        XCTAssertEqual(report.matched[treasuredID], product.id)
        XCTAssertEqual(report.createdCount, 1)
        XCTAssertTrue(report.unmatched.isEmpty)

        let pid = product.id
        let clothing = try XCTUnwrap(context.fetch(
            FetchDescriptor<Clothing>(predicate: #Predicate { $0.catalogProductID == pid })
        ).first)
        XCTAssertTrue(clothing.isDepositPlan, "收藏按心愿尾款口径落库")
        XCTAssertEqual(FinancialDataSanitizer.money(clothing.deposit), 0, "心愿未付定金")
        XCTAssertTrue(clothing.balance > 0, "全款记待付尾款")
        XCTAssertFalse(clothing.isDeleted)
        context.delete(clothing)
    }

    // MARK: productCode 二级解析

    func testProductCodeFallbackResolvesViaLegacySeed() throws {
        // 在旧馆种子里找一个 id ≠ productCode 且迁移商品存在的真实样例
        let timeHall = TimeHallCatalogStore.shared
        let sample = timeHall.items.first { item in
            guard let code = item.productCode, !code.isEmpty, code != item.id else { return false }
            return store.product(id: "th-\(code)") != nil
        }
        let item = try XCTUnwrap(sample, "旧馆种子应存在 productCode 与 id 不同的可迁移样例")
        let productID = "th-\(item.productCode!)"

        let resolved = TimeHallTreasuredWishMigrator.resolveProduct(
            treasuredID: item.id,
            productCodeByID: Dictionary(uniqueKeysWithValues: timeHall.items.map { ($0.id, $0.productCode) }),
            store: store)
        XCTAssertEqual(resolved?.id, productID, "应经 productCode 二级解析命中迁移商品")

        // 全链路：以旧 item id 作收藏 id 也应落库成功
        let context = modelContext()
        let report = TimeHallTreasuredWishMigrator.run(
            store: store,
            userState: addUserState([item.id]),
            defaults: testDefaults,
            modelContext: context)
        XCTAssertEqual(report.matched[item.id], productID)
        XCTAssertEqual(report.createdCount, 1)
        let pid2 = productID
        let clothing = try XCTUnwrap(context.fetch(
            FetchDescriptor<Clothing>(predicate: #Predicate { $0.catalogProductID == pid2 })
        ).first)
        context.delete(clothing)
    }

    // MARK: 未匹配 → 留旧馆归档

    func testUnmatchedTreasuredRecordedNotDropped() throws {
        let context = modelContext()
        let report = TimeHallTreasuredWishMigrator.run(
            store: store,
            userState: addUserState(["no-such-legacy-item"]),
            defaults: testDefaults,
            modelContext: context)

        XCTAssertEqual(report.unmatched, ["no-such-legacy-item"])
        XCTAssertTrue(report.matched.isEmpty)
        XCTAssertEqual(report.createdCount, 0)
        XCTAssertTrue((try context.fetch(FetchDescriptor<Clothing>())).isEmpty, "未匹配不产生任何记录")
    }

    // MARK: 幂等（重复执行不产生重复记录）

    func testSecondRunSkipsExistingRecords() throws {
        let product = try XCTUnwrap(pricedTHProduct())
        let treasuredID = String(product.id.dropFirst(3))
        let context = modelContext()
        let userState = addUserState([treasuredID])

        let first = TimeHallTreasuredWishMigrator.run(store: store, userState: userState,
                                                     defaults: testDefaults, modelContext: context)
        XCTAssertEqual(first.createdCount, 1)

        let second = TimeHallTreasuredWishMigrator.run(store: store, userState: userState,
                                                      defaults: testDefaults, modelContext: context)
        XCTAssertEqual(second.createdCount, 0, "重复执行不得新建记录")
        XCTAssertEqual(second.skippedExisting, 1, "应命中已有记录护栏")
        let pid = product.id
        let existing = try XCTUnwrap(context.fetch(
            FetchDescriptor<Clothing>(predicate: #Predicate { $0.catalogProductID == pid })
        ).first)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Clothing>(
                predicate: #Predicate { $0.catalogProductID == pid })).count, 1)
        context.delete(existing)
    }

    // MARK: 标记键只跑一轮

    func testRunIfNotYetMigratedRunsOnlyOnce() throws {
        let product = try XCTUnwrap(pricedTHProduct())
        let treasuredID = String(product.id.dropFirst(3))
        let context = modelContext()

        let first = TimeHallTreasuredWishMigrator.runIfNotYetMigrated(
            store: store,
            userState: addUserState([treasuredID]),
            defaults: testDefaults,
            modelContext: context)
        XCTAssertEqual(first?.createdCount, 1)
        XCTAssertNotNil(testDefaults.data(forKey: TimeHallTreasuredWishMigrator.markerKey), "执行后应写标记")

        let second = TimeHallTreasuredWishMigrator.runIfNotYetMigrated(
            store: store,
            userState: userStateForRead(),
            defaults: testDefaults,
            modelContext: context)
        XCTAssertNil(second, "标记存在时不再执行")
        let pid = product.id
        context.delete(try XCTUnwrap(context.fetch(
            FetchDescriptor<Clothing>(predicate: #Predicate { $0.catalogProductID == pid })).first))
    }

    private func userStateForRead() -> TimeHallUserStateStore {
        TimeHallUserStateStore(defaults: testDefaults)
    }

    // MARK: R08 逐条检查点（2026-09-22 第三版收口）

    private func syntheticCatalog(productID: String) -> ShopCatalog {
        var catalog = ShopCatalog()
        catalog.shops = [CatalogShop(id: "shop-r08", name: "R08 店家")]
        catalog.series = [CatalogSeries(id: "series-r08", shopID: "shop-r08", name: "R08 系列")]
        catalog.products = [CatalogProduct(id: productID, shopID: "shop-r08",
                                           seriesID: "series-r08", name: "R08 商品",
                                           category: "JSK")]
        catalog.saleEvents = [CatalogSaleEvent(id: "ev-r08", productID: productID,
                                               type: .stock, price: 100)]
        return catalog
    }

    /// 未完成的一轮**不得**写「全部完成」标记，且下轮要继续补迁未完成项
    func testIncompleteRunDoesNotSealAndRetriesWhenResourceArrives() throws {
        let context = modelContext()
        let userState = addUserState(["r08-item"])

        // 第一轮：Catalog 里还没有这条商品 → 记 pending，标记写「未完成」
        let missing = ShopCatalogStore(catalog: syntheticCatalog(productID: "th-other"))
        let first = TimeHallTreasuredWishMigrator.run(
            store: missing, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(first.createdCount, 0)
        XCTAssertEqual(first.unmatched, ["r08-item"])
        XCTAssertFalse(first.isComplete, "有未完成项时不得标记全部完成")

        let marker = try XCTUnwrap(TimeHallTreasuredWishMigrator.loadMarker(testDefaults))
        XCTAssertFalse(marker.completed)

        // 标记未封死：自动入口**仍会**再跑（旧实现见标记即整轮跳过）
        XCTAssertNotNil(TimeHallTreasuredWishMigrator.runIfNotYetMigrated(
            store: missing, userState: userState, defaults: testDefaults, modelContext: context))

        // 资源补齐（候选包合入后可解析）→ 只重试未完成项，成功落库
        let ready = ShopCatalogStore(catalog: syntheticCatalog(productID: "th-r08-item"))
        let second = TimeHallTreasuredWishMigrator.run(
            store: ready, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(second.createdCount, 1, "资源补齐后应补迁成功")
        XCTAssertEqual(second.retriedCount, 1, "本轮重试的是历史未完成项")
        XCTAssertTrue(second.isComplete)

        // 第三次：已成功的不再重复
        let third = TimeHallTreasuredWishMigrator.run(
            store: ready, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(third.createdCount, 0)
        XCTAssertEqual(third.skippedExisting, 1)

        let pid = "th-r08-item"
        for c in try context.fetch(FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.catalogProductID == pid })) { context.delete(c) }
    }

    /// 迁移后用户主动删除 → 重放**不复活**（不能只凭「现在查不到记录」就再建一条）
    func testUserDeletedWishIsNotResurrectedOnReplay() throws {
        let ready = ShopCatalogStore(catalog: syntheticCatalog(productID: "th-r08-del"))
        let context = modelContext()
        let userState = addUserState(["r08-del"])

        let first = TimeHallTreasuredWishMigrator.run(
            store: ready, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(first.createdCount, 1)

        // 用户主动删除
        let pid = "th-r08-del"
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.catalogProductID == pid })).first)
        context.delete(created)
        try context.save()

        let second = TimeHallTreasuredWishMigrator.run(
            store: ready, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(second.createdCount, 0, "用户主动删除后重放不得复活")
        XCTAssertEqual(second.removedByUserCount, 1)

        // 标记成 removedByUser 后，后续任何一轮都不再处理
        let third = TimeHallTreasuredWishMigrator.run(
            store: ready, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(third.createdCount, 0)
        XCTAssertEqual(third.removedByUserCount, 0, "已判定删除的不再重复计数")
    }

    /// 失败的条目保留原因，可单条重试；成功的不会被重试（检查点按条独立）
    func testCheckpointsTrackPerItemStateAndReasons() throws {
        let context = modelContext()
        let userState = addUserState(["r08-a", "r08-b"])
        let catalog = ShopCatalog()   // 空 Catalog：两条都匹配不到
        let empty = ShopCatalogStore(catalog: catalog)

        let report = TimeHallTreasuredWishMigrator.run(
            store: empty, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(report.unmatched.count, 2)
        XCTAssertFalse(report.isComplete)

        let checkpoints = TimeHallTreasuredWishMigrator.loadCheckpoints(testDefaults)
        XCTAssertEqual(checkpoints["r08-a"]?.state, .pending)
        XCTAssertEqual(checkpoints["r08-b"]?.state, .pending)
        XCTAssertNotNil(checkpoints["r08-a"]?.detail, "失败/待定必须保留原因")

        // 只让 r08-a 具备解析条件 → 只补迁 a，b 仍待定
        var mixed = syntheticCatalog(productID: "th-r08-a")
        mixed.products.append(CatalogProduct(id: "th-r08-a", shopID: "shop-r08",
                                             seriesID: "series-r08", name: "A", category: "JSK"))
        let partial = ShopCatalogStore(catalog: syntheticCatalog(productID: "th-r08-a"))
        let second = TimeHallTreasuredWishMigrator.run(
            store: partial, userState: userState, defaults: testDefaults, modelContext: context)
        XCTAssertEqual(second.createdCount, 1)
        XCTAssertEqual(second.retriedCount, 2, "两条都进入重试，但只有 a 具备条件")
        XCTAssertFalse(second.isComplete, "b 仍未完成")

        let after = TimeHallTreasuredWishMigrator.loadCheckpoints(testDefaults)
        XCTAssertEqual(after["r08-a"]?.state, .migrated)
        XCTAssertEqual(after["r08-b"]?.state, .pending)

        let pid = "th-r08-a"
        for c in try context.fetch(FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.catalogProductID == pid })) { context.delete(c) }
    }

    /// Catalog 未就绪：不执行、不写任何标记（等具备条件再迁）
    func testCatalogNotReadyDoesNotWriteMarker() {
        let context = modelContext()
        let notLoaded = ShopCatalogStore()
        XCTAssertNil(notLoaded.catalog)
        XCTAssertNil(TimeHallTreasuredWishMigrator.runIfNotYetMigrated(
            store: notLoaded, userState: addUserState(["r08-x"]),
            defaults: testDefaults, modelContext: context))
        XCTAssertNil(TimeHallTreasuredWishMigrator.loadMarker(testDefaults),
                     "资源未就绪不得写标记（否则会封死后续迁移）")
    }
}
