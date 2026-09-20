//
//  ShopCatalogBatchAttributionTests.swift
//  ItemManagerTests
//
//  批次录入整批归属整合验收（V1.1 §4.1）：
//    · applyBatchAttribution：一次指定店家+系列 → 整批草稿同步，未发布条目生效
//    · 已发布/归档条目不回写（发布产物已入覆盖层）
//    · 同系列多单品发布后聚合到同一个系列（不散建系列），用户端单一入口可看可选
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogBatchAttributionTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        for name in ["shop-catalog-override.json", "shop-catalog-drafts.json", "shop-catalog-batches.json"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        store.reloadWithOverlay()
        CreatorAccess.setTestOverride(nil)
        super.tearDown()
    }

    private var draftStore: ShopCatalogDraftStore { ShopCatalogDraftStore.shared }

    /// 构造整批归属（既有店家 id + 新建系列名），应用到 batchID
    private func apply(_ batchID: String,
                       shopID: String? = nil, newShop: String = "整合测试店家",
                       seriesID: String? = nil, newSeries: String = "整合测试系列") -> Int {
        draftStore.applyBatchAttribution(
            batchID: batchID,
            shopID: shopID, newShopName: newShop, newShopAliases: "alias-a,alias-b",
            seriesID: seriesID, newSeriesName: newSeries, newSeriesYear: 2026, newSeriesSeason: "冬")
    }

    private func makeDraft(name: String) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.saleKind = .stock
        draft.price = 199
        draft.category = "JSK"
        return draft
    }

    // MARK: 整批归属同步

    func testApplyBatchAttributionSyncsAllDraftsAndSession() throws {
        let session = CatalogBatchEntrySession()
        let drafts = (1...3).map { makeDraft(name: "整批单品-\($0)") }
        draftStore.createBatch(session, drafts: drafts)

        let count = apply(session.id)
        XCTAssertEqual(count, 3, "整批 3 条全部同步")

        for draft in draftStore.drafts where draft.batchID == session.id {
            XCTAssertNil(draft.shopID)
            XCTAssertEqual(draft.newShopName, "整合测试店家")
            XCTAssertEqual(draft.newShopAliases, "alias-a,alias-b")
            XCTAssertNil(draft.seriesID)
            XCTAssertEqual(draft.newSeriesName, "整合测试系列")
            XCTAssertEqual(draft.newSeriesYear, 2026)
            XCTAssertEqual(draft.newSeriesSeason, "冬")
        }

        // 批次会话本身同步持久化（重开 App 后归属仍在）
        let persisted = try XCTUnwrap(
            ShopCatalogDraftStore.loadBatches().first { $0.id == session.id })
        XCTAssertEqual(persisted.newShopName, "整合测试店家")
        XCTAssertEqual(persisted.newSeriesName, "整合测试系列")
        XCTAssertEqual(persisted.newSeriesYear, 2026)
    }

    func testApplyBatchAttributionSkipsPublishedDrafts() throws {
        let session = CatalogBatchEntrySession()
        var published = makeDraft(name: "已发布单品")
        published.status = .published
        let pending = makeDraft(name: "待处理单品")
        draftStore.createBatch(session, drafts: [published, pending])

        let count = apply(session.id)
        XCTAssertEqual(count, 1, "已发布条目不回写")

        let back = try XCTUnwrap(draftStore.drafts.first { $0.id == published.id })
        XCTAssertEqual(back.newShopName, "", "发布产物归属以覆盖层为准，草稿字段不回写")
    }

    // MARK: 同系列聚合发布（整合后的最终产物形态）

    /// 完整发布链路：draft → submitted → reviewed → publish
    private func publish(_ draft: CatalogProductDraft) throws -> String {
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        return try draftStore.publish(d, store: store)
    }

    func testSameSeriesBatchPublishesIntoOneSeries() throws {
        let session = CatalogBatchEntrySession()
        let names = ["聚合款-JSK", "聚合款-KC", "聚合款-包"]
        let drafts = names.map { makeDraft(name: $0) }
        draftStore.createBatch(session, drafts: drafts)

        // 整批归属：同一店家 + 同一新建系列（复刻运营整合操作）
        let count = apply(session.id, newShop: "聚合发布店家", newSeries: "聚合发布系列")
        XCTAssertEqual(count, 3)

        // 逐条走完发布（互不耦合）
        var summaries: [String] = []
        for draft in draftStore.drafts where draft.batchID == session.id {
            summaries.append(try publish(draft))
        }
        XCTAssertEqual(summaries.count, 3)

        // 关键断言：3 个单品聚合到同一个系列，而不是散建 3 个系列
        let shop = try XCTUnwrap(store.searchShops(keyword: "聚合发布店家").first)
        let seriesList = store.series(inShop: shop.id)
        XCTAssertEqual(seriesList.count, 1, "同批次同系列只建一条系列")
        XCTAssertEqual(seriesList.first?.name, "聚合发布系列")

        store.reloadWithOverlay()
        let products = store.products(inSeries: try XCTUnwrap(seriesList.first).id)
        XCTAssertEqual(products.count, 3, "系列下 3 个单品齐全")
        XCTAssertEqual(Set(products.map(\.category)), ["JSK"], "多品类单品信息各自完整")

        // 通过「系列」这个单一入口可以定位全部单品（用户端查看/选择链路）
        XCTAssertEqual(store.productCount(inSeries: try XCTUnwrap(seriesList.first).id), 3)
    }
}
