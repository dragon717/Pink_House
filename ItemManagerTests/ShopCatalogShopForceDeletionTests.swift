//
//  ShopCatalogShopForceDeletionTests.swift
//  ItemManagerTests
//
//  店家强制删除（级联）契约（2026-09-24）：
//    1. 级联：店家 → 系列 → 商品 → 规格/尺码表，一次删除，覆盖层整批只写一次
//    2. 种子实体物理删不掉 → 写墓碑，合并层排除（含种子与其覆盖层副本）
//    3. 被用户心愿/衣橱引用的商品**保留**（引用保护红线），如实计入汇报
//    4. 销售事件 append-only 硬约束：永不删除
//    5. 预检只读且与执行同源；upsertEntity 同 id 重录 = 复活（清墓碑）
//    6. 测试隔离：ShopCatalogStorage.useTemporaryForTesting()，绝不触碰生产路径
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogShopForceDeletionTests: XCTestCase {

    /// 独立实例：不与 `.shared` 的跨套件状态耦合（V1.1 测试同款口径）。
    /// `forceDeleteShop` 会同步 reload 传入的实例，断言直接读它。
    private var store = ShopCatalogStore()
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        // 种子已连根清理（2026-09-24）：种子语义由合成夹具提供
        store = ShopCatalogSeedFixture.makeStore()
        CreatorAccess.setTestOverride(.creator)
        store.reloadWithOverlay()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        store.reloadWithOverlay()
        super.tearDown()
    }

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Schema([Clothing.self, Brand.self, Tag.self]),
                                            configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    // MARK: 夹具

    /// 往覆盖层放一家完整店家：1 店 + N 系列 + 每系列 1 商品 + 规格/尺码表/销售事件
    private func makeOverlayShop(
        id: String, name: String, seriesCount: Int
    ) throws -> CatalogShop {
        let shop = CatalogShop(id: id, name: name)
        try ShopCatalogDraftStore.upsertEntity(shop, keyPath: \.shops)
        for s in 0..<seriesCount {
            let seriesID = "\(id)-series-\(s)"
            try ShopCatalogDraftStore.upsertEntity(
                CatalogSeries(id: seriesID, shopID: id, name: "系列\(s)"),
                keyPath: \.series)
            let productID = "\(id)-prod-\(s)"
            try ShopCatalogDraftStore.upsertEntity(
                CatalogProduct(id: productID, shopID: id, seriesID: seriesID,
                               name: "商品\(s)", category: "JSK"),
                keyPath: \.products)
            try ShopCatalogDraftStore.upsertEntity(
                CatalogProductVariant(id: "\(productID)-var", productID: productID,
                                      color: "粉", size: "M"),
                keyPath: \.variants)
            var chart = CatalogSizeChart(id: "\(productID)-chart", productID: productID)
            chart.columns = ["胸围"]
            chart.rows = [CatalogSizeRow(label: "M", values: ["88"])]
            try ShopCatalogDraftStore.upsertEntity(chart, keyPath: \.sizeCharts)
            try ShopCatalogDraftStore.upsertEntity(
                CatalogSaleEvent(id: "\(productID)-sale", productID: productID,
                                 type: .stock, price: 500),
                keyPath: \.saleEvents)
        }
        store.reloadWithOverlay()
        return shop
    }

    /// 种子店家（随版本内置，物理删除不可能）
    private let seedShopID = "shop-alice-girl"

    // MARK: 1. 覆盖层店家：级联删除 + 汇报数量

    func testForceDeleteRemovesOverlayShopWithAllChildren() throws {
        let shop = try makeOverlayShop(id: "shop-force-a", name: "级联验收店家", seriesCount: 2)
        let productIDs = (0..<2).map { "shop-force-a-prod-\($0)" }

        let report = try ShopCatalogDraftStore.forceDeleteShop(
            shop, store: store, modelContext: modelContext())

        // 汇报数量与夹具一一对应
        XCTAssertEqual(report.shopName, "级联验收店家")
        XCTAssertEqual(report.deletedSeriesCount, 2)
        XCTAssertEqual(report.deletedProductCount, 2)
        XCTAssertEqual(report.deletedVariantCount, 2)
        XCTAssertEqual(report.deletedSizeChartCount, 2)
        XCTAssertEqual(report.childRecordCount, 8)
        XCTAssertTrue(report.keptReferencedProductNames.isEmpty)
        XCTAssertEqual(report.retainedSaleEventCount, 2, "销售事件只汇报，不删除")

        // 合并视图：全链路消失
        XCTAssertNil(store.catalog?.shops.first { $0.id == shop.id })
        XCTAssertTrue((store.catalog?.series ?? []).allSatisfy { $0.shopID != shop.id })
        for pid in productIDs {
            XCTAssertNil(store.product(id: pid), "商品应消失")
            XCTAssertTrue((store.catalog?.variants ?? []).allSatisfy { $0.productID != pid },
                          "规格应连坐消失")
            XCTAssertTrue((store.catalog?.sizeCharts ?? []).allSatisfy { $0.productID != pid },
                          "尺码表应连坐消失")
        }
        // 销售事件保留（append-only 硬约束）
        XCTAssertEqual((store.catalog?.saleEvents ?? []).filter { $0.productID == productIDs[0] }.count, 1)
    }

    // MARK: 2. 种子店家：墓碑生效

    func testForceDeleteTombstonesSeedShopAndHidesItFromMergedCatalog() throws {
        let seedShop = try XCTUnwrap(store.catalog?.shops.first { $0.id == seedShopID })
        let seedSeriesCount = store.catalog!.series.filter { $0.shopID == seedShopID }.count
        let seedProductIDs = Set(store.catalog!.products.filter { $0.shopID == seedShopID }.map(\.id))
        XCTAssertFalse(seedProductIDs.isEmpty, "种子夹具应存在（shop-alice-girl）")
        let saleEventsBefore = store.catalog!.saleEvents.count

        let report = try ShopCatalogDraftStore.forceDeleteShop(
            seedShop, store: store, modelContext: modelContext())

        XCTAssertEqual(report.deletedSeriesCount, seedSeriesCount)
        XCTAssertEqual(report.deletedProductCount, seedProductIDs.count)
        // 墓碑写入覆盖层
        let overlay = try XCTUnwrap(ShopCatalogDraftStore.loadOverlay())
        XCTAssertTrue(overlay.removedShopIDs.contains(seedShopID))
        XCTAssertTrue(overlay.removedSeriesIDs.contains("series-ag-xueguo-2026"))
        XCTAssertTrue(overlay.removedProductIDs.contains("prod-ag-xueguo-jsk"))
        // 合并视图排除；销售事件总数不变（历史保留）
        XCTAssertNil(store.catalog?.shops.first { $0.id == seedShopID })
        XCTAssertTrue((store.catalog?.series ?? []).allSatisfy { $0.shopID != seedShopID })
        XCTAssertEqual(store.catalog!.saleEvents.count, saleEventsBefore, "销售事件一条不删")
        // 规格连坐：种子规格也从合并视图消失
        XCTAssertTrue((store.catalog?.variants ?? []).allSatisfy { !seedProductIDs.contains($0.productID) })
    }

    // MARK: 3. 引用保护：被引用商品保留并汇报

    func testForceDeleteKeepsReferencedProducts() throws {
        let shop = try makeOverlayShop(id: "shop-force-ref", name: "引用保留店家", seriesCount: 1)
        let keptProductID = "shop-force-ref-prod-0"

        // 用户把该商品加入衣橱（不 save：内存容器 save 偶发抛错，fetch 含 pending changes）
        let context = modelContext()
        let clothing = Clothing(name: "引用保留款", types: "JSK", price: 66, stock: 1)
        clothing.catalogProductID = keptProductID
        context.insert(clothing)

        let report = try ShopCatalogDraftStore.forceDeleteShop(
            shop, store: store, modelContext: context)

        XCTAssertEqual(report.deletedProductCount, 0, "唯一商品被引用 → 不删")
        XCTAssertEqual(report.keptReferencedProductNames, ["商品0"], "保留要如实汇报")
        XCTAssertNotNil(store.product(id: keptProductID), "被引用商品数据保留")
        XCTAssertNil(store.catalog?.shops.first { $0.id == shop.id }, "店家本身仍删除")
        // 保留商品不写墓碑
        let overlay = try XCTUnwrap(ShopCatalogDraftStore.loadOverlay())
        XCTAssertFalse(overlay.removedProductIDs.contains(keptProductID))
    }

    // MARK: 4. 预检只读 + 与执行同源

    func testPreviewIsReadOnlyAndAgreesWithExecution() throws {
        let shop = try makeOverlayShop(id: "shop-force-preview", name: "预检店家", seriesCount: 3)

        let preview = try ShopCatalogDraftStore.previewShopForceDeletion(
            shop, store: store, modelContext: modelContext())

        // 预检不写盘
        XCTAssertNotNil(store.catalog?.shops.first { $0.id == shop.id })
        XCTAssertEqual(preview.deletedSeriesCount, 3)
        XCTAssertEqual(preview.deletedProductCount, 3)

        let report = try ShopCatalogDraftStore.forceDeleteShop(
            shop, store: store, modelContext: modelContext())
        XCTAssertEqual(report.deletedSeriesCount, preview.deletedSeriesCount)
        XCTAssertEqual(report.deletedProductCount, preview.deletedProductCount)
        XCTAssertEqual(report.deletedVariantCount, preview.deletedVariantCount)
        XCTAssertEqual(report.deletedSizeChartCount, preview.deletedSizeChartCount)
    }

    // MARK: 5. 复活：同 id 重录清墓碑

    func testUpsertSameIDClearsTombstone() throws {
        let shop = try makeOverlayShop(id: "shop-force-revive", name: "复活店家", seriesCount: 0)
        try ShopCatalogDraftStore.forceDeleteShop(shop, store: store, modelContext: modelContext())
        XCTAssertNil(store.catalog?.shops.first { $0.id == shop.id }, "删除后应消失")

        // 同 id 重新录入 → 墓碑清除 → 合并视图可见
        // （upsertEntity 只 reload `.shared`；本套件用独立实例，需手动刷一次）
        try ShopCatalogDraftStore.upsertEntity(
            CatalogShop(id: shop.id, name: "复活店家二代"), keyPath: \.shops)
        store.reloadWithOverlay()
        XCTAssertEqual(store.catalog?.shops.first { $0.id == shop.id }?.name, "复活店家二代")
    }

    // MARK: 6. 鉴权

    func testForceDeleteRequiresCreator() throws {
        // 先以创作者身份造夹具，再切成普通用户验证写接口被拦
        let shop = try makeOverlayShop(id: "shop-force-auth", name: "鉴权店家", seriesCount: 1)
        CreatorAccess.setTestOverride(.viewer)
        defer { CreatorAccess.setTestOverride(.creator) }
        XCTAssertThrowsError(try ShopCatalogDraftStore.forceDeleteShop(
            shop, store: store, modelContext: modelContext())) { error in
            guard error is CreatorAccessDenied else {
                return XCTFail("应抛 CreatorAccessDenied，实际：\(error)")
            }
        }
        // 拦截后不落任何墓碑
        let overlay = try XCTUnwrap(ShopCatalogDraftStore.loadOverlay())
        XCTAssertTrue(overlay.removedShopIDs.isEmpty)
    }
}
