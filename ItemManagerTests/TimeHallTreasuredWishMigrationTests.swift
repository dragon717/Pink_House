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

        let first = TimeHallTreasuredWishMigrator.run(store: store, userState: userState, modelContext: context)
        XCTAssertEqual(first.createdCount, 1)

        let second = TimeHallTreasuredWishMigrator.run(store: store, userState: userState, modelContext: context)
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
}
