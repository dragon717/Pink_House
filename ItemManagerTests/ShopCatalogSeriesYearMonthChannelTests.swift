//
//  ShopCatalogSeriesYearMonthChannelTests.swift
//  ItemManagerTests
//
//  2026-09-24 需求五：「其他系列都带有月份，为什么只有它不带月份」的**根源修复**验收。
//
//  根源：批次 / 草稿链路原先只承载 `newSeriesYear`，而建系列的两处
//  （`publish` / `ensureAttributionEntities`）都只写 `year:`，
//  于是凡经「批量录入 → 批次归属 → 发布」诞生的系列 `month` 恒为 nil，
//  列表里就只有那一批显示「2026」而其它显示「2026-10」。
//
//  修复分三层，本套件逐层钉住：
//    1. 通道 —— `CatalogProductDraft.newSeriesMonth` / `CatalogBatchEntrySession.newSeriesMonth`
//       一路带到建系列那一步（旧 JSON 缺键自动 nil，零迁移）；
//    2. 写入 —— `ensureAttributionEntities` / `publish` 建系列时写 `month`；
//    3. 存量补全 —— 复用既有系列时「**只填空不覆盖**」补 month（年份对不上就不补），
//       另有 `completeSeriesYearMonth` 作为批次详情页的显式修复入口。
//
//  ⚠️ `ShopCatalogDraftStore.shared.drafts / batches` 跨套件累积，
//  断言一律按 batchID 收窄或断言前后快照。
//

import XCTest
@testable import ItemManager

// MARK: - ① 纯逻辑：年月补全 + 发布指纹

@MainActor
final class CatalogSeriesYearMonthCompletionTests: XCTestCase {

    private func series(year: Int?, month: Int?) -> CatalogSeries {
        var series = CatalogSeries(id: "s-completing", shopID: "shop-1", name: "补全测试系列")
        series.year = year
        series.month = month
        return series
    }

    // MARK: 只填空不覆盖

    func testFillsBothWhenSeriesHasNoYear() {
        let completed = CatalogSeriesYearMonthCompletionTests.unwrapped(
            ShopCatalogDraftStore.seriesCompletingYearMonth(series(year: nil, month: nil),
                                                            year: 2026, month: 10))
        XCTAssertEqual(completed.year, 2026)
        XCTAssertEqual(completed.month, 10, "年月同源：年补进来了，月必须跟着一起补")
    }

    func testFillsMonthWhenYearMatches() {
        let completed = CatalogSeriesYearMonthCompletionTests.unwrapped(
            ShopCatalogDraftStore.seriesCompletingYearMonth(series(year: 2026, month: nil),
                                                            year: 2026, month: 10))
        XCTAssertEqual(completed.year, 2026)
        XCTAssertEqual(completed.month, 10)
    }

    func testNeverOverwritesExistingMonth() {
        XCTAssertNil(ShopCatalogDraftStore.seriesCompletingYearMonth(series(year: 2026, month: 3),
                                                                     year: 2026, month: 10),
                     "已有月份是运营声明，绝不被补全逻辑改写")
    }

    func testDoesNotFillMonthWhenYearMismatches() {
        XCTAssertNil(ShopCatalogDraftStore.seriesCompletingYearMonth(series(year: 2025, month: nil),
                                                                     year: 2026, month: 10),
                     "年份不一致 = 另一年的同名系列，硬补月份就是脏数据")
    }

    func testDoesNothingWithoutAnyInput() {
        XCTAssertNil(ShopCatalogDraftStore.seriesCompletingYearMonth(series(year: 2026, month: nil),
                                                                     year: nil, month: nil))
    }

    func testFillsYearOnlyWhenNoMonthProvided() {
        let completed = CatalogSeriesYearMonthCompletionTests.unwrapped(
            ShopCatalogDraftStore.seriesCompletingYearMonth(series(year: nil, month: nil),
                                                            year: 2026, month: nil))
        XCTAssertEqual(completed.year, 2026)
        XCTAssertNil(completed.month, "没填月份就不许凭空造一个")
    }

    // MARK: 发布指纹（加字段必须进指纹，且不能改变存量指纹）

    func testYearMonthKeyKeepsLegacyShapeWhenMonthIsNil() {
        XCTAssertEqual(CatalogProductDraft.yearMonthKey(year: nil, month: nil), "-")
        XCTAssertEqual(CatalogProductDraft.yearMonthKey(year: 2026, month: nil), "2026",
                       "只有年份时必须与旧实现的指纹段逐字相同，否则存量草稿会被判成「内容变了」重新发布")
        XCTAssertEqual(CatalogProductDraft.yearMonthKey(year: 2026, month: 10), "2026-10")
    }

    func testPublishOperationKeyChangesWhenMonthChanges() {
        func draft(month: Int?) -> CatalogProductDraft {
            var draft = CatalogProductDraft()
            draft.name = "指纹测试单品"
            draft.price = 199
            draft.newSeriesName = "指纹测试系列"
            draft.newSeriesYear = 2026
            draft.newSeriesMonth = month
            return draft
        }
        let keyNil = draft(month: nil).publishOperationKey
        let keyTen = draft(month: 10).publishOperationKey
        XCTAssertNotEqual(keyNil, keyTen, "补月份是一次真实的新内容，不能被幂等入口吞掉")
        XCTAssertTrue(keyNil.contains("|2026|"), "只带年份的指纹段仍是裸年份：\(keyNil)")
        XCTAssertTrue(keyTen.contains("|2026-10|"), "带月份的指纹段是 yyyy-MM：\(keyTen)")
    }

    func testDraftOldJSONWithoutMonthDecodesAsNil() throws {
        var draft = CatalogProductDraft()
        draft.name = "旧草稿"
        draft.newSeriesYear = 2026
        draft.newSeriesMonth = 10
        let data = try ShopCatalogJSONCoding.encoder().encode(draft)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "newSeriesMonth")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ShopCatalogJSONCoding.decoder().decode(CatalogProductDraft.self, from: legacy)
        XCTAssertEqual(decoded.newSeriesYear, 2026)
        XCTAssertNil(decoded.newSeriesMonth, "旧草稿缺键必须置 nil，不能抛错")

        var session = CatalogBatchEntrySession()
        session.newSeriesName = "旧批次系列"
        session.newSeriesYear = 2026
        let sessionData = try ShopCatalogJSONCoding.encoder().encode(session)
        var sessionObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: sessionData) as? [String: Any])
        sessionObject.removeValue(forKey: "newSeriesMonth")
        let legacySession = try JSONSerialization.data(withJSONObject: sessionObject)
        let decodedSession = try ShopCatalogJSONCoding.decoder()
            .decode(CatalogBatchEntrySession.self, from: legacySession)
        XCTAssertNil(decodedSession.newSeriesMonth)
    }

    /// `XCTUnwrap` 在 helper 里用会更啰嗦，这里给个带断言的窄封装
    private static func unwrapped(_ series: CatalogSeries?,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) -> CatalogSeries {
        guard let series else {
            XCTFail("应当判定为「需要补全」", file: file, line: line)
            return CatalogSeries(id: "", shopID: "", name: "")
        }
        return series
    }
}

// MARK: - ② 存储链路：批次 → 系列 的年月必须真的落库

@MainActor
final class ShopCatalogSeriesYearMonthStoreTests: XCTestCase {

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

    private func drafts(in batchID: String) -> [CatalogProductDraft] {
        draftStore.drafts.filter { $0.batchID == batchID }
    }

    private func makeDraft(name: String) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.saleKind = .stock
        draft.price = 199
        draft.category = "JSK"
        return draft
    }

    private func publish(_ draft: CatalogProductDraft) throws -> String {
        try draftStore.advance(draft, to: .submitted)
        var current = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(current, to: .reviewed)
        current = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        return try draftStore.publish(current, store: store)
    }

    // MARK: 通道：createBatch 会把年月带到每条草稿

    func testCreateBatchCarriesMonthToDrafts() throws {
        let session = makeSession(shop: "年月通道店家", series: "年月通道系列", year: 2026, month: 10)
        try draftStore.createBatch(session, drafts: [makeDraft(name: "年月通道单品")])

        let created = drafts(in: session.id)
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.newSeriesYear, 2026)
        XCTAssertEqual(created.first?.newSeriesMonth, 10, "批次链路必须承载月份")
    }

    /// 只造批次会话（不写草稿）
    private func makeSession(shop: String, series: String, year: Int?, month: Int?) -> CatalogBatchEntrySession {
        var session = CatalogBatchEntrySession()
        session.newShopName = shop
        session.newSeriesName = series
        session.newSeriesYear = year
        session.newSeriesMonth = month
        return session
    }

    // MARK: 写入：建系列时必须带上 month

    func testEnsureAttributionEntitiesCreatesSeriesWithMonth() throws {
        let session = makeSession(shop: "年月建店", series: "年月建系列", year: 2026, month: 10)
        try draftStore.createBatch(session, drafts: [makeDraft(name: "建系列单品")])

        let resolved = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: session.id,
                                                                             store: store))
        store.reloadWithOverlay()

        XCTAssertEqual(resolved.series.year, 2026)
        XCTAssertEqual(resolved.series.month, 10, "经批次创建的系列必须带月份 —— 这正是「只有它不带月份」的根因")
        XCTAssertEqual(resolved.series.yearMonthText, "2026-10")

        let persisted = try XCTUnwrap(store.series(id: resolved.series.id))
        XCTAssertEqual(persisted.month, 10, "月份要真的落进覆盖层，而不是只留在内存返回值里")
    }

    // MARK: 存量补全：既有系列缺月份 → 补上；已有月份 → 不动

    func testEnsureAttributionEntitiesBackfillsMissingMonthOnExistingSeries() throws {
        // 第一步：用旧口径（只有年份）建系列 —— 复刻「只有它不带月份」的存量形态
        let legacy = makeSession(shop: "存量补全店家", series: "存量补全系列", year: 2026, month: nil)
        try draftStore.createBatch(legacy, drafts: [makeDraft(name: "存量单品")])
        let first = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: legacy.id,
                                                                          store: store))
        XCTAssertNil(first.series.month, "旧链路建出来的系列确实没有月份")

        // 第二步：运营在批次页补上年月 → 应用到整批 → 再确认一次系列
        _ = try draftStore.applyBatchAttribution(
            batchID: legacy.id,
            shopID: first.shop.id, newShopName: "存量补全店家", newShopAliases: "",
            seriesID: first.series.id, newSeriesName: "存量补全系列",
            newSeriesYear: 2026, newSeriesMonth: 10, newSeriesSeason: "")

        let second = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: legacy.id,
                                                                           store: store))
        store.reloadWithOverlay()

        XCTAssertEqual(second.series.id, first.series.id, "补全不得建出第二条系列")
        XCTAssertEqual(second.series.month, 10, "既有系列缺的月份要被补上")
        XCTAssertEqual(store.series(id: first.series.id)?.month, 10)
    }

    func testBackfillNeverOverwritesExistingMonth() throws {
        let session = makeSession(shop: "不覆盖店家", series: "不覆盖系列", year: 2026, month: 3)
        try draftStore.createBatch(session, drafts: [makeDraft(name: "不覆盖单品")])
        let created = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: session.id,
                                                                            store: store)).series
        XCTAssertEqual(created.month, 3)

        // 拿一个「同店同年但月不同」的输入去补 → 必须一个字节都不写
        let changed = try draftStore.completeSeriesYearMonth(seriesID: created.id, year: 2026, month: 10)
        XCTAssertFalse(changed, "已有月份时不许补全")
        store.reloadWithOverlay()
        XCTAssertEqual(store.series(id: created.id)?.month, 3)
    }

    func testCompleteSeriesYearMonthWritesOnceAndIsIdempotent() throws {
        let session = makeSession(shop: "幂等补全店家", series: "幂等补全系列", year: 2026, month: nil)
        try draftStore.createBatch(session, drafts: [makeDraft(name: "幂等单品")])
        let created = try XCTUnwrap(try draftStore.ensureAttributionEntities(batchID: session.id,
                                                                            store: store)).series

        XCTAssertTrue(try draftStore.completeSeriesYearMonth(seriesID: created.id,
                                                             year: 2026, month: 10))
        store.reloadWithOverlay()
        XCTAssertEqual(store.series(id: created.id)?.month, 10)

        XCTAssertFalse(try draftStore.completeSeriesYearMonth(seriesID: created.id,
                                                              year: 2026, month: 10),
                       "第二次调用无事可做 → 返回 false，不重复写盘")
        XCTAssertFalse(try draftStore.completeSeriesYearMonth(seriesID: "series-does-not-exist",
                                                              year: 2026, month: 10),
                       "系列不存在时如实返回 false，不假装成功")
    }

    // MARK: 发布链路：新系列带月份 / 既有系列补月份

    func testPublishCreatesSeriesWithMonth() throws {
        var draft = makeDraft(name: "发布带月单品")
        draft.newShopName = "发布带月店家"
        draft.newSeriesName = "发布带月系列"
        draft.newSeriesYear = 2026
        draft.newSeriesMonth = 10
        try draftStore.upsert(draft)

        _ = try publish(draft)
        store.reloadWithOverlay()

        let shop = try XCTUnwrap(store.searchShops(keyword: "发布带月店家").first)
        let series = try XCTUnwrap(store.series(inShop: shop.id).first { $0.name == "发布带月系列" })
        XCTAssertEqual(series.year, 2026)
        XCTAssertEqual(series.month, 10, "发布建系列时同样要写月份")
        XCTAssertEqual(series.yearMonthText, "2026-10")
    }

    func testPublishBackfillsMonthOnExistingSeriesWithoutCreatingAnother() throws {
        // 先用只有年份的旧口径落一条系列
        var legacyDraft = makeDraft(name: "补月单品-A")
        legacyDraft.newShopName = "补月店家"
        legacyDraft.newSeriesName = "补月系列"
        legacyDraft.newSeriesYear = 2026
        try draftStore.upsert(legacyDraft)
        _ = try publish(legacyDraft)
        store.reloadWithOverlay()
        let shop = try XCTUnwrap(store.searchShops(keyword: "补月店家").first)
        let legacySeries = try XCTUnwrap(store.series(inShop: shop.id).first { $0.name == "补月系列" })
        XCTAssertNil(legacySeries.month)

        let seriesCountBefore = try XCTUnwrap(store.catalog?.series.count)

        // 同系列再录一条、这次带上月份：同名系列必须复用，缺的月份补上
        var second = makeDraft(name: "补月单品-B")
        second.newShopName = "补月店家"
        second.newSeriesName = "补月系列"
        second.newSeriesYear = 2026
        second.newSeriesMonth = 10
        try draftStore.upsert(second)
        _ = try publish(second)
        store.reloadWithOverlay()

        let after = try XCTUnwrap(store.series(id: legacySeries.id))
        XCTAssertEqual(after.month, 10, "同名系列必须复用同一条并把缺的月份补上")
        XCTAssertEqual(store.catalog?.series.count, seriesCountBefore, "不得多建一条系列")
    }
}
