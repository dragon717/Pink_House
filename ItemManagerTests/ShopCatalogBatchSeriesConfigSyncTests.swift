//
//  ShopCatalogBatchSeriesConfigSyncTests.swift
//  ItemManagerTests
//
//  2026-09-24 需求一验收：「这三项配置属于系列级别数据，保存时前后端需保证
//  批次数据与所属系列数据同步更新」。
//
//  落地方式是「单一写入点 + 链接归一」，本套件逐条钉住它：
//    1. 三项配置只有一处存储（`CatalogSeries`）——批次里没有副本，写一次即全系列生效；
//    2. `saveSeriesConfig` 把**未自报系列**（继承整批归属）的草稿显式挂到该系列 id，
//       从此它们的归属不再依赖「批次当前选择」这层间接引用；
//    3. 单品页自己改过归属（自报系列）的草稿**永不被覆盖**（既有裁定）；
//    4. `ensureAttributionEntities` 与 `publish` 同源：同名系列复用、不建第二条，
//       并且**幂等**（重复点击不会建出重复系列）。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogBatchSeriesConfigSyncTests: XCTestCase {

    private let store = ShopCatalogSeedFixture.makeStore()
    private let draftStore = ShopCatalogDraftStore.shared

    override func setUp() {
        super.setUp()
        // 测试隔离（2026-09-21 事故防线）：一律重定向到临时目录
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        store.reloadWithOverlay()
        draftStore.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        store.reloadWithOverlay()
        super.tearDown()
    }

    /// 造一个批次：session 不预设系列（模拟「还没归属」的真实起点）
    @discardableResult
    private func makeBatch(draftNames: [String]) throws -> CatalogBatchEntrySession {
        let session = CatalogBatchEntrySession()
        var drafts: [CatalogProductDraft] = []
        for name in draftNames {
            var draft = CatalogProductDraft()
            draft.name = name
            draft.price = 100
            drafts.append(draft)
        }
        _ = try draftStore.createBatch(session, drafts: drafts)
        return session
    }

    private func drafts(in batchID: String) -> [CatalogProductDraft] {
        // ⚠️ `drafts` 是跨套件累积的 @Published 单例，断言一律按 batchID 收窄
        draftStore.drafts.filter { $0.batchID == batchID }
    }

    // MARK: 1. 保存配置 → 只链接「未自报系列」的草稿

    func testSaveSeriesConfigLinksInheritedDraftsOnly() throws {
        let session = try makeBatch(draftNames: ["继承款", "自报款"])
        let own = try XCTUnwrap(drafts(in: session.id).first { $0.name == "自报款" })
        var mutated = own
        mutated.seriesID = "series-ag-xingwu-2025"      // 单品页自己改过归属
        try draftStore.upsert(mutated)

        let series = try XCTUnwrap(store.series(id: "series-ag-xueguo-2026"))
        let linked = try draftStore.saveSeriesConfig(series, batchID: session.id)

        XCTAssertEqual(linked, 1, "只有未自报系列的那条应该被链接")
        let after = drafts(in: session.id)
        XCTAssertEqual(after.filter { $0.seriesID == series.id }.count, 1)
        XCTAssertEqual(after.filter { $0.seriesID == "series-ag-xingwu-2025" }.count, 1,
                       "自报系列的草稿永不被整批覆盖（既有裁定）")
    }

    /// 再保存一次不该重复计数（已链接的草稿不再进候选）
    func testSaveSeriesConfigIsIdempotent() throws {
        let session = try makeBatch(draftNames: ["幂等款"])
        let series = try XCTUnwrap(store.series(id: "series-ag-xueguo-2026"))
        XCTAssertEqual(try draftStore.saveSeriesConfig(series, batchID: session.id), 1)
        XCTAssertEqual(try draftStore.saveSeriesConfig(series, batchID: session.id), 0,
                       "第二次保存不应再报同步条数")
    }

    // MARK: 2. ensureAttributionEntities：与发布同源 + 幂等

    func testEnsureReusesSameNameSeriesInsteadOfCreatingDuplicate() throws {
        var session = CatalogBatchEntrySession()
        session.shopID = "shop-alice-girl"
        session.newSeriesName = "雪国来信"          // 该店下已存在同名系列
        _ = try draftStore.createBatch(session, drafts: [])

        let seriesCountBefore = store.catalog?.series.count ?? 0
        let resolved = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: session.id,
                                                                             store: store))
        XCTAssertEqual(resolved.series.id, "series-ag-xueguo-2026",
                       "同名系列必须命中同店同名去重，而不是新建")

        store.reloadWithOverlay()
        XCTAssertEqual(store.catalog?.series.count, seriesCountBefore, "不得凭空多一条系列")

        // 批次会话与整批草稿的归属 id 被归一
        let sessionAfter = try XCTUnwrap(draftStore.batches.first { $0.id == session.id })
        XCTAssertEqual(sessionAfter.seriesID, "series-ag-xueguo-2026")
        XCTAssertEqual(sessionAfter.shopID, "shop-alice-girl")
    }

    func testEnsureCreatesOnceAndIsIdempotentForBrandNewSeries() throws {
        var session = CatalogBatchEntrySession()
        session.newShopName = "新店家"
        session.newSeriesName = "全新系列"
        session.newSeriesYear = 2026
        _ = try draftStore.createBatch(session, drafts: [])

        let first = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: session.id,
                                                                          store: store))
        store.reloadWithOverlay()
        let countAfterFirst = store.catalog?.series.count ?? 0

        let second = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: session.id,
                                                                           store: store))
        store.reloadWithOverlay()
        XCTAssertEqual(second.series.id, first.series.id, "重复调用必须复用同一条系列")
        XCTAssertEqual(second.shop.id, first.shop.id, "重复调用必须复用同一家店家")
        XCTAssertEqual(store.catalog?.series.count, countAfterFirst, "幂等：不再多建")
        XCTAssertEqual(second.series.year, 2026, "年月/季节随归属一并落库")
    }

    /// 归属信息不足（既没有既有 id、也没填名称）→ 返回 nil，不静默造实体
    func testEnsureReturnsNilWhenAttributionIsIncomplete() throws {
        let session = CatalogBatchEntrySession()      // 店家、系列都没给
        _ = try draftStore.createBatch(session, drafts: [])
        XCTAssertNil(try draftStore.ensureAttributionEntities(batchID: session.id, store: store))
    }

    // MARK: 3. 三项配置写一次，批次与同系列商品读到的是同一份

    func testSavedSeriesConfigIsSharedByBatchAndItsProducts() throws {
        let series = try XCTUnwrap(store.series(id: "series-ag-xueguo-2026"))
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.salePhase = .reservationActive
        form.reservationEndAt = Date(timeIntervalSince1970: 1_800_000_000)
        form.balanceDueKind = .exact
        form.balanceDueAt = Date(timeIntervalSince1970: 1_800_100_000)
        form.cover = "local:new-cover.jpg"
        form.descriptionText = "批次详情页改过的简介"
        form.priceChartColumnsText = "款式,预约价,定金,尾款"
        form.priceChartRowsText = "雪国来信 JSK:428,128,300"
        let updated = form.apply(to: series)

        _ = try draftStore.saveSeriesConfig(updated, batchID: nil)
        store.reloadWithOverlay()

        let shared = try XCTUnwrap(store.series(id: "series-ag-xueguo-2026"))
        // 三项配置都在系列上（唯一存储点）
        XCTAssertEqual(shared.salePhase, .reservationActive)
        XCTAssertEqual(shared.balanceDueKind, .exact)
        XCTAssertEqual(shared.cover, "local:new-cover.jpg")
        XCTAssertEqual(shared.description, "批次详情页改过的简介")
        XCTAssertEqual(shared.priceChart?.rows.first?.label, "雪国来信 JSK")
        XCTAssertEqual(shared.priceChart?.rows.first?.values, ["428", "128", "300"])
        // 首列「款式」是行标签列名 —— 共用解析口径会把它剔除（`CatalogManualChartText.normalized`）
        XCTAssertEqual(shared.priceChart?.columns, ["预约价", "定金", "尾款"])
        // 系列基础信息与商品归属不受影响（同一系列的商品仍在同一系列下）
        XCTAssertEqual(shared.name, "雪国来信")
        XCTAssertEqual(shared.year, 2026)
        XCTAssertEqual(shared.season, "冬")
        XCTAssertFalse(store.products(inSeries: shared.id).isEmpty,
                       "同系列商品仍通过 seriesID 读到这一份配置")
    }
}
