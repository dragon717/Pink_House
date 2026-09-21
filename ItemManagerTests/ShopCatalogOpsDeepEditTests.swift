//
//  ShopCatalogOpsDeepEditTests.swift
//  ItemManagerTests
//
//  运营端完整能力收口（V1.1 §4.2 深度编辑）：
//    · updatePublishedProduct：已发布商品全字段替换（图片/规格/尺码表/名称/分类）
//      —— id 不变、未变图片行复用原 asset id（断链保护）、规格/尺码表整组重建
//    · appendSaleEvent：追加式销售记录（预约价永不覆盖——计划 §7 约束）
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogOpsDeepEditTests: XCTestCase {

    private var store = ShopCatalogStore()
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        for name in ["shop-catalog-override.json", "shop-catalog-drafts.json", "shop-catalog-batches.json"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        store.reloadWithOverlay()
        super.tearDown()
    }

    /// 完整发布链路：draft → submitted → reviewed → publish（§31 状态机）
    private func publishNew(_ draft: CatalogProductDraft) throws -> CatalogProduct {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(d, store: store)
        return try XCTUnwrap(store.product(named: draft.name), "发布后用户侧应可见")
    }

    private func asset(_ ref: String, id: String) -> CatalogAsset {
        CatalogAsset(id: id, type: .productImage,
                     thumbnailURL: nil, previewURL: nil,
                     originalURL: ref, width: nil, height: nil)
    }

    // MARK: updatePublishedProduct 全字段替换

    func testDeepEditReplacesImagesVariantsSizeChartKeepsID() throws {
        var draft = CatalogProductDraft()
        draft.name = "深度编辑款"
        draft.category = "JSK"
        draft.saleKind = .stock
        draft.price = 300
        draft.newShopName = "深度编辑店家"
        draft.newSeriesName = "深度编辑系列"
        draft.images = [asset("old-a.png", id: "asset-deep-old-a"),
                        asset("old-b.png", id: "asset-deep-old-b")]
        draft.variants = [CatalogProductVariant(id: "var-deep-1", productID: "",
                                                color: "夜空蓝", size: "M", imageAssetID: nil)]
        let published = try publishNew(draft)
        let oldID = published.id
        XCTAssertEqual(published.images.count, 2)

        // 深度编辑：换图 / 改规格（带图文绑定）/ 加尺码表 / 改名改分类
        let assets = [asset("new-a.png", id: "asset-deep-new-a")]
        let variants = [CatalogProductVariant(id: "var-deep-2", productID: published.id,
                                              color: "初雪白", size: "S",
                                              imageAssetID: "asset-deep-new-a")]
        var chart = CatalogSizeChart(id: "sizechart-deep-1", productID: published.id)
        chart.unit = "cm"
        chart.columns = ["尺码", "胸围"]
        chart.rows = [CatalogSizeRow(label: "S", values: ["S", "84"])]
        var updated = published
        updated.name = "深度编辑款·改"
        updated.category = "OP"
        try ShopCatalogDraftStore.updatePublishedProduct(
            updated, assets: assets, variants: variants, sizeChart: chart)
        store.reloadWithOverlay()

        let reloaded = try XCTUnwrap(store.product(named: "深度编辑款·改"))
        XCTAssertEqual(reloaded.id, oldID, "id 永不改变")
        XCTAssertEqual(reloaded.category, "OP")
        XCTAssertEqual(reloaded.images, ["asset-deep-new-a"])

        // 规格整组重建：旧规格消失、新规格图文绑定可达
        let newVariants = store.variants(forProduct: oldID)
        XCTAssertEqual(newVariants.count, 1)
        XCTAssertEqual(newVariants.first?.color, "初雪白")
        XCTAssertEqual(newVariants.first?.imageAssetID, "asset-deep-new-a")

        // 尺码表整组重建
        let reloadedChart = try XCTUnwrap(store.sizeChart(forProduct: oldID))
        XCTAssertEqual(reloadedChart.columns, ["尺码", "胸围"])
        XCTAssertEqual(reloadedChart.rows.first?.label, "S")

        // 旧图 asset 已被清理（覆盖层内不再可达）
        XCTAssertNil(store.asset(id: "asset-deep-old-a"))
        XCTAssertNil(store.asset(id: "asset-deep-old-b"))
        XCTAssertNotNil(store.asset(id: "asset-deep-new-a"))
    }

    func testDeepEditReusesAssetIDForUnchangedImageRows() throws {
        var draft = CatalogProductDraft()
        draft.name = "断链保护款"
        draft.saleKind = .stock
        draft.price = 100
        draft.newShopName = "断链保护店家"
        draft.newSeriesName = "断链保护系列"
        draft.images = [asset("keep-a.png", id: "asset-keep-a"),
                        asset("drop-b.png", id: "asset-drop-b")]
        let published = try publishNew(draft)

        // 图片行首行 originalURL 未变 → 复用原 asset id；第二行被替换
        let assets = [asset("keep-a.png", id: "asset-keep-a"),
                      asset("fresh-c.png", id: "asset-fresh-c")]
        try ShopCatalogDraftStore.updatePublishedProduct(
            published, assets: assets, variants: [], sizeChart: nil)
        store.reloadWithOverlay()

        let reloaded = try XCTUnwrap(store.product(named: "断链保护款"))
        XCTAssertEqual(reloaded.images.first, "asset-keep-a", "未变行必须复用原 id")
        XCTAssertNil(store.asset(id: "asset-drop-b"), "被移除的旧图应清理")
        XCTAssertNotNil(store.asset(id: "asset-fresh-c"))
    }

    // MARK: appendSaleEvent 追加式

    func testAppendSaleEventKeepsReservationAndAddsStock() throws {
        var draft = CatalogProductDraft()
        draft.name = "追加记录款"
        draft.saleKind = .reservation
        draft.price = 200
        draft.deposit = 50
        draft.newShopName = "追加记录店家"
        draft.newSeriesName = "追加记录系列"
        let published = try publishNew(draft)

        var archive = store.priceArchive(forProduct: published.id)
        XCTAssertEqual(archive.historicalReservationPrice, 200)
        XCTAssertNil(archive.currentStockPrice)

        // 追加现货：价格档案出现现货价，预约记录保留
        try ShopCatalogDraftStore.appendSaleEvent(
            productID: published.id, type: .stock, price: 260, deposit: nil, balance: nil)
        store.reloadWithOverlay()
        archive = store.priceArchive(forProduct: published.id)
        XCTAssertEqual(archive.currentStockPrice, 260)
        XCTAssertEqual(archive.historicalReservationPrice, 200, "预约价永不覆盖")
        XCTAssertEqual(archive.stockOverReservationDelta, 60)
        XCTAssertEqual(archive.stockOverReservationDeltaPercent ?? 0, 30, accuracy: 0.001)

        // 再追加一条预约（新一档）：追加不替换，记录数递增
        let before = store.saleEvents(forProduct: published.id).count
        try ShopCatalogDraftStore.appendSaleEvent(
            productID: published.id, type: .reservation, price: 180, deposit: 40, balance: nil)
        store.reloadWithOverlay()
        XCTAssertEqual(store.saleEvents(forProduct: published.id).count, before + 1)
        // 缺省尾款 = 价格 − 定金
        let events = store.saleEvents(forProduct: published.id)
        let latest = events.last { $0.type == .reservation }
        XCTAssertEqual(latest?.balance, 140)
    }

    func testDeepEditRequiresCreatorAccess() throws {
        // 显式注入 viewer：setTestOverride(nil) 会回落到真实判定（本机开关可能放行）
        CreatorAccess.setTestOverride(.viewer)
        let published = CatalogProduct(id: "prod-x", shopID: "s", seriesID: "sr",
                                       name: "白名单校验", category: "JSK")
        XCTAssertThrowsError(try ShopCatalogDraftStore.updatePublishedProduct(
            published, assets: [], variants: [], sizeChart: nil))
        XCTAssertThrowsError(try ShopCatalogDraftStore.appendSaleEvent(
            productID: "prod-x", type: .stock, price: 1, deposit: nil, balance: nil))
    }
}
