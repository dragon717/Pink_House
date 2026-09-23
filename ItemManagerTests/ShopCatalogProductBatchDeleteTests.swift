//
//  ShopCatalogProductBatchDeleteTests.swift
//  ItemManagerTests
//
//  商品批量删除契约（2026-09-23 需求：批量删除商品 + 二次确认）。
//
//  口径与「批次会话批量删除」一致，守卫与单品删除完全同一套：
//    1. 预检只读：不写盘，且与执行同源（弹窗说删几件，实际就删几件）
//    2. 种子档案（Bundle 只读）→ 拦截，附原因
//    3. 被用户心愿/尾款/衣橱引用（含软删除）→ 拦截，附原因
//    4. 部分成功：可删的删掉，被拦截的**保留在库里**并返回原因，供处理后重试
//    5. 级联口径：连带清理该商品的规格与尺码表；销售历史按硬约束保留
//    6. 鉴权：仍需运营白名单
//    7. 测试隔离：一律 ShopCatalogStorage.useTemporaryForTesting()，
//       绝不触碰用户真实 Application Support 路径（2026-09-21 事故防线）
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogProductBatchDeleteTests: XCTestCase {

    private var store: ShopCatalogStore { ShopCatalogStore.shared }
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        _ = store.loadFromBundleIfNeeded()
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

    /// 往覆盖层放一件可删商品（连带一条规格 + 一张尺码表 + 一条销售记录）
    @discardableResult
    private func makeOverlayProduct(id: String, name: String) throws -> CatalogProduct {
        let product = CatalogProduct(id: id, shopID: "shop-batchdel", seriesID: "series-batchdel",
                                     name: name, category: "JSK")
        try ShopCatalogDraftStore.upsertEntity(product, keyPath: \.products)
        try ShopCatalogDraftStore.upsertEntity(
            CatalogProductVariant(id: "\(id)-var", productID: id, color: "粉", size: "M"),
            keyPath: \.variants)
        var chart = CatalogSizeChart(id: "\(id)-chart", productID: id)
        chart.columns = ["胸围"]
        chart.rows = [CatalogSizeRow(label: "M", values: ["88"])]
        try ShopCatalogDraftStore.upsertEntity(chart, keyPath: \.sizeCharts)
        try ShopCatalogDraftStore.upsertEntity(
            CatalogSaleEvent(id: "\(id)-sale", productID: id, type: .stock, price: 500),
            keyPath: \.saleEvents)
        store.reloadWithOverlay()
        return product
    }

    /// 种子商品 id（随版本内置，物理删除不可能）
    private let seedProductID = "prod-ag-xueguo-jsk"

    // MARK: 1. 预检只读 + 与执行同源

    func testPreviewIsReadOnlyAndSeparatesDeletableFromBlocked() throws {
        let product = try makeOverlayProduct(id: "prod-bd-preview", name: "预览款")
        let seed = try XCTUnwrap(store.product(id: seedProductID))

        let preview = try ShopCatalogDraftStore.previewProductDeletion(
            [product, seed], store: store, modelContext: modelContext())

        XCTAssertEqual(preview.deletableNames, ["预览款"])
        XCTAssertEqual(preview.deletableCount, 1)
        XCTAssertEqual(preview.blocked.map(\.productID), [seedProductID])
        XCTAssertEqual(preview.blocked.first?.reason, .seedImmutable)

        // 预检绝不写盘：两件商品都还在
        XCTAssertNotNil(store.product(id: product.id))
        XCTAssertNotNil(store.product(id: seedProductID))
    }

    func testPreviewAndExecutionAgreeOnDeletableCount() throws {
        let a = try makeOverlayProduct(id: "prod-bd-agree-a", name: "一致款A")
        let b = try makeOverlayProduct(id: "prod-bd-agree-b", name: "一致款B")
        let seed = try XCTUnwrap(store.product(id: seedProductID))
        let targets = [a, b, seed]

        let preview = try ShopCatalogDraftStore.previewProductDeletion(
            targets, store: store, modelContext: modelContext())
        let result = try ShopCatalogDraftStore.deleteProducts(
            targets, store: store, modelContext: modelContext())

        XCTAssertEqual(result.deletedIDs.count, preview.deletableCount,
                       "弹窗说会删几件，实际就必须删几件（预检与执行同源）")
        XCTAssertEqual(result.blocked.map(\.productID), preview.blocked.map(\.productID))
        XCTAssertEqual(result.deletedIDs, [a.id, b.id])
    }

    // MARK: 2. 级联口径

    func testDeleteCascadesVariantsAndSizeChartButKeepsSaleHistory() throws {
        let product = try makeOverlayProduct(id: "prod-bd-cascade", name: "级联款")
        XCTAssertNotNil(store.variants(forProduct: product.id).first)
        XCTAssertNotNil(store.sizeChart(forProduct: product.id))

        let result = try ShopCatalogDraftStore.deleteProducts(
            [product], store: store, modelContext: modelContext())

        XCTAssertEqual(result.deletedIDs, [product.id])
        XCTAssertTrue(result.blocked.isEmpty)
        XCTAssertNil(store.product(id: product.id), "商品应已物理删除")
        XCTAssertTrue(store.variants(forProduct: product.id).isEmpty, "规格应连带清理")
        XCTAssertNil(store.sizeChart(forProduct: product.id), "尺码表应连带清理")
        XCTAssertEqual(store.saleEvents(forProduct: product.id).map(\.id),
                       ["\(product.id)-sale"],
                       "销售历史按硬约束保留，删除商品不得抹掉历史记录")
    }

    // MARK: 3. 引用保护

    func testReferencedProductIsBlockedAndKeptInCatalog() throws {
        let product = try makeOverlayProduct(id: "prod-bd-ref", name: "被引用款")

        // 用户把它加进了衣橱（含未落盘的 pending changes 也能被引用查询命中）
        let context = modelContext()
        let clothing = Clothing(name: "被引用款", types: "JSK", price: 500, stock: 1)
        clothing.catalogProductID = product.id
        context.insert(clothing)

        let result = try ShopCatalogDraftStore.deleteProducts(
            [product], store: store, modelContext: context)

        XCTAssertTrue(result.deletedIDs.isEmpty, "被引用时不得删除任何东西")
        XCTAssertEqual(result.blocked.map(\.productID), [product.id])
        XCTAssertEqual(result.blocked.first?.reason, .referencedByUserData)
        XCTAssertNotNil(store.product(id: product.id), "被引用商品必须保留在库里（仅可归档）")
    }

    // MARK: 4. 种子保护

    func testSeedProductIsBlockedWithSeedReason() throws {
        let seed = try XCTUnwrap(store.product(id: seedProductID))
        let result = try ShopCatalogDraftStore.deleteProducts(
            [seed], store: store, modelContext: modelContext())

        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertEqual(result.blocked.first?.reason, .seedImmutable)
        XCTAssertNotNil(store.product(id: seedProductID), "种子商品必须保留")
    }

    // MARK: 5. 部分成功：可删的删掉，被拦截的保留

    func testPartialSuccessDeletesDeletableAndKeepsBlocked() throws {
        let deletable = try makeOverlayProduct(id: "prod-bd-part-ok", name: "可删款")
        let blocked = try makeOverlayProduct(id: "prod-bd-part-blocked", name: "拦下款")

        let context = modelContext()
        let clothing = Clothing(name: "拦下款", types: "JSK", price: 500, stock: 1)
        clothing.catalogProductID = blocked.id
        context.insert(clothing)

        let result = try ShopCatalogDraftStore.deleteProducts(
            [deletable, blocked], store: store, modelContext: context)

        XCTAssertEqual(result.deletedIDs, [deletable.id], "可删的正常删除")
        XCTAssertEqual(result.blocked.map(\.productID), [blocked.id], "被拦截的附原因返回")
        XCTAssertNil(store.product(id: deletable.id))
        XCTAssertNotNil(store.product(id: blocked.id), "被拦截条目必须保留，供处理后重试")
    }

    // MARK: 6. 边界：重复入参 / 空入参 / 鉴权

    func testDuplicateIDsAreDeletedOnce() throws {
        let product = try makeOverlayProduct(id: "prod-bd-dup", name: "重复款")
        let result = try ShopCatalogDraftStore.deleteProducts(
            [product, product, product], store: store, modelContext: modelContext())

        XCTAssertEqual(result.deletedIDs, [product.id])
        XCTAssertEqual(result.blocked.count, 0, "同一件重复传入不得算成多次拦截")
    }

    func testEmptySelectionIsNoOp() throws {
        let before = Set((store.catalog?.products ?? []).map(\.id))
        let result = try ShopCatalogDraftStore.deleteProducts(
            [], store: store, modelContext: modelContext())

        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertTrue(result.blocked.isEmpty)
        XCTAssertEqual(Set((store.catalog?.products ?? []).map(\.id)), before,
                       "空选择不得改变任何数据")
    }

    func testBatchDeleteRequiresCreatorAccess() throws {
        let product = try makeOverlayProduct(id: "prod-bd-auth", name: "鉴权款")
        CreatorAccess.setTestOverride(.viewer)

        XCTAssertThrowsError(try ShopCatalogDraftStore.deleteProducts(
            [product], store: store, modelContext: modelContext()))
        XCTAssertNotNil(store.product(id: product.id), "鉴权失败时商品必须保留")

        CreatorAccess.setTestOverride(.creator)
        let result = try ShopCatalogDraftStore.deleteProducts(
            [product], store: store, modelContext: modelContext())
        XCTAssertEqual(result.deletedIDs, [product.id], "恢复权限后同样选择可直接重试")
    }

    // MARK: 7. 拦截原因文案可操作

    func testBlockedReasonMessagesExplainWhatToDoInstead() {
        XCTAssertTrue(CatalogProductDeleteReason.referencedByUserData.message.contains("归档"),
                      "必须告诉操作者「仅可归档」这一替代动作")
        XCTAssertTrue(CatalogProductDeleteReason.seedImmutable.message.contains("种子"),
                      "必须说明是种子档案导致删不掉")
    }
}
