//
//  ShopCatalogOpsV11Tests.swift
//  ItemManagerTests
//
//  重构方案 Phase 2 验收（V1.1 P0 补齐）：
//    · archivedAt 归档标记：向后兼容解码（§5.1）
//    · 覆盖层合并规则升级：同 id 替换 + SaleEvent 只追加（§5.3）
//    · 用户侧归档过滤（§5.1 查询层收口）
//    · 淘宝批量解析逐条容错（G6）
//    · 批次会话 + 批量提交 + 单品粒度审核（G1/G2）
//    · 发布携带图片/规格/尺码表（G5）
//    · 引用保护：被引用商品删除拦截、归档后用户端隐藏（G3/G4）
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogOpsV11Tests: XCTestCase {

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

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    /// 完整发布链路：draft → submitted → reviewed → publish（§31 状态机）
    private func publishNew(_ draft: CatalogProductDraft) throws -> String {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        return try draftStore.publish(d, store: store)
    }

    // MARK: §5.1 archivedAt 向后兼容

    func testArchivedAtDecodeBackwardCompat() throws {
        // 旧 JSON 无 archivedAt → nil；带 archivedAt → 正常解析
        let oldJSON = """
        {"id":"s1","shopID":"shop-1","name":"系列"}
        """
        let series = try JSONDecoder().decode(CatalogSeries.self, from: Data(oldJSON.utf8))
        XCTAssertNil(series.archivedAt)

        let newJSON = """
        {"id":"s1","shopID":"shop-1","name":"系列","archivedAt":"2026-09-21T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archived = try decoder.decode(CatalogSeries.self, from: Data(newJSON.utf8))
        XCTAssertNotNil(archived.archivedAt)
    }

    // MARK: §5.3 覆盖层合并：同 id 替换 + SaleEvent 只追加

    func testOverlaySameIDReplaceAndSaleEventAppendOnly() throws {
        var draft = CatalogProductDraft()
        draft.name = "合并测试款"
        draft.saleKind = .stock
        draft.price = 100
        draft.newShopName = "合并测试店家"
        draft.newSeriesName = "合并测试系列"
        _ = try publishNew(draft)

        guard let product = store.product(named: "合并测试款") else {
            return XCTFail("发布后用户侧应可见")
        }
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, 1)

        // 编辑（改名）：同 id 替换后新名字可见，id 不变
        var updated = product
        updated.name = "合并测试款·改名"
        try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.products)
        store.reloadWithOverlay()
        XCTAssertEqual(store.product(id: product.id)?.name, "合并测试款·改名", "同 id 替换应生效且 id 不变")

        // 追加现货：SaleEvent 只增不减，价格历史完整保留
        var draft2 = CatalogProductDraft()
        draft2.name = "合并测试款·改名"
        draft2.saleKind = .stock
        draft2.price = 128
        draft2.newShopName = "合并测试店家"
        draft2.newSeriesName = "合并测试系列"
        _ = try publishNew(draft2)
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, 2, "追加现货应新增 SaleEvent")
        XCTAssertEqual(store.catalog?.products.filter { $0.id == product.id }.count, 1, "同名商品不新建")
    }

    // MARK: §5.1 用户侧归档过滤

    func testArchivedEntitiesHiddenFromUserQueries() throws {
        var draft = CatalogProductDraft()
        draft.name = "归档测试款"
        draft.saleKind = .stock
        draft.price = 88
        draft.newShopName = "归档测试店家"
        draft.newSeriesName = "归档测试系列"
        _ = try publishNew(draft)

        guard let product = store.product(named: "归档测试款") else {
            return XCTFail("发布后应可见")
        }
        let shopID = product.shopID
        XCTAssertEqual(store.searchShops(keyword: "归档测试店家").count, 1)

        // 归档商品：用户端查询不可见，原始 catalog 仍保留（用户收藏记录不丢）
        try ShopCatalogDraftStore.archiveProduct(product)
        store.reloadWithOverlay()
        XCTAssertNil(store.product(id: product.id), "归档商品用户侧不可见")
        XCTAssertEqual(store.products(inSeries: product.seriesID).count, 0)
        let rawProduct = store.catalog?.products.first { $0.id == product.id }
        XCTAssertNotNil(rawProduct, "归档不删数据")
        XCTAssertNotNil(rawProduct?.archivedAt)

        // 归档系列：series(inShop:) 不可见
        let series = store.catalog?.series.first { $0.id == product.seriesID }
        try ShopCatalogDraftStore.archiveSeries(XCTUnwrap(series))
        store.reloadWithOverlay()
        XCTAssertEqual(store.series(inShop: shopID).count, 0)

        // 归档店家：列表不可见
        let shop = store.catalog?.shops.first { $0.id == shopID }
        try ShopCatalogDraftStore.archiveShop(XCTUnwrap(shop))
        store.reloadWithOverlay()
        XCTAssertEqual(store.searchShops(keyword: "归档测试店家").count, 0)
    }

    // MARK: G6 批量解析

    func testTaobaoBatchParseSplitsByLinkAndToleratesFailures() {
        let text = """
        【新品】樱花 JSK 定金:100 尾款:328 https://item.taobao.com/item.htm?id=111
        现货小物 KC ¥59 https://item.taobao.com/item.htm?id=222
        复制这条信息打开淘宝
        """
        let outcome = ShopCatalogTaobaoParser.parseBatch(text)
        XCTAssertEqual(outcome.drafts.count, 2, "两条链接各生成一条草稿")
        // 第一条含定金 → 预约；第二条 ¥59 → 现货
        XCTAssertEqual(outcome.drafts[0].saleKind, .reservation)
        XCTAssertEqual(outcome.drafts[1].saleKind, .stock)
        // 「复制这条信息打开淘宝」无可解析字段 → 失败清单，不阻塞
        XCTAssertEqual(outcome.failures.count, 1)
    }

    func testTaobaoBatchParseEmptyInput() {
        let outcome = ShopCatalogTaobaoParser.parseBatch("   ")
        XCTAssertTrue(outcome.drafts.isEmpty)
        XCTAssertTrue(outcome.failures.isEmpty)
    }

    // MARK: G1/G2 批次 + 单品粒度审核

    func testBatchCreateSubmitAndPerItemReview() throws {
        let draftStore = ShopCatalogDraftStore.shared
        var session = CatalogBatchEntrySession()
        session.newShopName = "批次店家"
        session.newSeriesName = "批次系列"

        var drafts: [CatalogProductDraft] = []
        for (index, category) in ["OP", "JSK", "KC"].enumerated() {
            var d = CatalogProductDraft()
            d.name = "批次款\(index)"
            d.category = category
            d.saleKind = .stock
            d.price = Double(index + 1) * 100
            drafts.append(d)
        }
        let summary = draftStore.createBatch(session, drafts: drafts)
        XCTAssertTrue(summary.contains("3 条"))

        // 批量提交：3 条全部 draft → submitted
        let submitted = try draftStore.submitBatch(session.id)
        XCTAssertEqual(submitted, 3)

        // 单品粒度审核：1 条通过、1 条驳回、1 条保持待审
        let submittedDrafts = draftStore.drafts.filter { $0.batchID == session.id && $0.status == .submitted }
        XCTAssertEqual(submittedDrafts.count, 3)
        try draftStore.review(submittedDrafts[0], approve: true)
        try draftStore.review(submittedDrafts[1], approve: false)
        XCTAssertEqual(draftStore.drafts.first { $0.id == submittedDrafts[0].id }?.status, .reviewed)
        XCTAssertEqual(draftStore.drafts.first { $0.id == submittedDrafts[1].id }?.status, .draft, "驳回应退回草稿")
        XCTAssertEqual(draftStore.drafts.first { $0.id == submittedDrafts[2].id }?.status, .submitted)
    }

    // MARK: G5 发布携带完整商品资料

    func testPublishWritesImagesVariantsSizeChart() throws {
        var draft = CatalogProductDraft()
        draft.name = "完整资料款"
        draft.saleKind = .stock
        draft.price = 299
        draft.newShopName = "完整资料店家"
        draft.newSeriesName = "完整资料系列"
        draft.images = [
            CatalogAsset(id: "asset-full-1", type: .productImage, originalURL: "full-1.jpg"),
            CatalogAsset(id: "asset-full-2", type: .productImage, originalURL: "https://example.com/2.jpg"),
        ]
        draft.variants = [
            CatalogProductVariant(id: "var-full-1", productID: "", color: "粉", size: "M"),
            CatalogProductVariant(id: "var-full-2", productID: "", color: "粉", size: "L"),
        ]
        var chart = CatalogSizeChart(id: "sizechart-full", productID: "")
        chart.unit = "cm"
        chart.columns = ["尺码", "胸围"]
        chart.rows = [CatalogSizeRow(label: "M", values: ["M", "88"])]
        chart.sourceImage = "full-chart.jpg"
        draft.sizeChart = chart

        _ = try publishNew(draft)

        guard let product = store.product(named: "完整资料款") else {
            return XCTFail("发布后应可见")
        }
        XCTAssertEqual(product.images.count, 2, "商品图应随发布落库")
        XCTAssertEqual(store.variants(forProduct: product.id).count, 2, "配色尺码应随发布落库")
        let savedChart = store.sizeChart(forProduct: product.id)
        XCTAssertEqual(savedChart?.columns, ["尺码", "胸围"])
        XCTAssertEqual(savedChart?.sourceImage, "full-chart.jpg", "尺码表原图必须保留")
    }

    // MARK: G3/G4 引用保护

    func testReferencedProductCannotBeDeletedOnlyArchived() throws {
        var draft = CatalogProductDraft()
        draft.name = "引用保护款"
        draft.saleKind = .stock
        draft.price = 66
        draft.newShopName = "引用保护店家"
        draft.newSeriesName = "引用保护系列"
        _ = try publishNew(draft)

        guard let product = store.product(named: "引用保护款") else {
            return XCTFail("发布后应可见")
        }

        // 用户把该商品加入衣橱（Clothing.catalogProductID 引用）。
        // 注意：不调用 context.save() —— 内存容器的 save 会偶发抛
        // 「No eligible connection available」（ObjC 异常，try/catch 拦不住）；
        // 同 context 的 fetch 含 pending changes，无需落盘即可被引用保护查询到。
        let context = modelContext()
        let clothing = Clothing(name: "引用保护款", types: "OP", price: 66, stock: 1)
        clothing.catalogProductID = product.id
        context.insert(clothing)

        // 删除被引用商品 → 拦截（引用保护）
        XCTAssertThrowsError(try ShopCatalogDraftStore.deleteProduct(
            product, store: store, modelContext: context)) { error in
            guard case ShopCatalogEntityError.referencedOnlyArchive = error else {
                return XCTFail("应抛 referencedOnlyArchive，实际：\(error)")
            }
        }
        XCTAssertNotNil(store.catalog?.products.first { $0.id == product.id }, "被引用商品数据保留")

        // 归档 → 用户端隐藏，Clothing 记录仍指向它（收藏保留）
        try ShopCatalogDraftStore.archiveProduct(product)
        store.reloadWithOverlay()
        XCTAssertNil(store.product(id: product.id))
        XCTAssertEqual(try ShopCatalogReferenceGuard.referencedProductIDs(
            [product.id], modelContext: context), [product.id])
    }

    func testUnreferencedOverlayProductCanBeDeleted() throws {
        var draft = CatalogProductDraft()
        draft.name = "可删款"
        draft.saleKind = .stock
        draft.price = 10
        draft.newShopName = "可删店家"
        draft.newSeriesName = "可删系列"
        _ = try publishNew(draft)

        guard let product = store.product(named: "可删款") else {
            return XCTFail("发布后应可见")
        }
        let context = modelContext()
        // 无引用 → 覆盖层商品可物理删除
        try ShopCatalogDraftStore.deleteProduct(product, store: store, modelContext: context)
        store.reloadWithOverlay()
        XCTAssertNil(store.catalog?.products.first { $0.id == product.id }, "物理删除后应移除")

        // 种子商品（Bundle 只读）→ 删除被拦截，仅归档
        let seedProduct = try XCTUnwrap(store.catalog?.products.first { $0.id == "prod-ag-xueguo-jsk" })
        XCTAssertThrowsError(try ShopCatalogDraftStore.deleteProduct(
            seedProduct, store: store, modelContext: context)) { error in
            guard case ShopCatalogEntityError.seedImmutableOnlyArchive = error else {
                return XCTFail("应抛 seedImmutableOnlyArchive，实际：\(error)")
            }
        }
    }
}

// MARK: - Store 测试辅助

extension ShopCatalogStore {
    /// 按名称查商品（仅测试用；已排除归档）
    func product(named name: String) -> CatalogProduct? {
        catalog?.products.first { $0.name == name && Self.isLive($0.archivedAt) }
    }
}
