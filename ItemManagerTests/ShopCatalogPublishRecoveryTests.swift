//
//  ShopCatalogPublishRecoveryTests.swift
//  ItemManagerTests
//
//  第三版收口 R09 回归（方案 §9 T12 / T13）：
//    T12 重复发布同一 reviewed 快照；覆盖层成功但草稿状态写失败 → 只产生一次发布效果
//    T13 初次草稿同时填预约与现货；旧现货草稿 → 并存，旧 price 只按原现货语义解释一次
//
//  事故形态：publish 校验传入**草稿快照**、事件 ID 随机生成；覆盖层先落盘、
//  草稿状态后写回且 persist 吞错。重复点击 / 旧 reviewed 快照重放 / 半成功重试
//  都会再追加一组销售事件，商品页价格档案随之出现重复历史。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogPublishRecoveryTests: XCTestCase {

    private var store: ShopCatalogStore!
    private var draftStore: ShopCatalogDraftStore!

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        draftStore = ShopCatalogDraftStore.shared
        // 切到本套件临时目录后重新挂载：单例的草稿内存与「坏文件待处理」状态
        // 都是针对**上一个**目录的，不重载会把别套件的状态带进来。
        draftStore.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private func reviewedDraft(name: String, reservation: Double = 428,
                               stock: Double? = 498, deposit: Double? = 128,
                               balance: Double? = 300) throws -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.saleKind = .reservation
        draft.price = reservation
        draft.stockPrice = stock
        draft.deposit = deposit
        draft.balance = balance
        draft.newShopName = "发布恢复店家-" + name
        draft.newSeriesName = "发布恢复系列-" + name
        try draftStore.upsert(draft)
        try draftStore.advance(draft, to: .submitted)
        // 状态机校验的是**传入快照**的状态：必须重新取回已落库的草稿再推进，
        // 否则第二次 advance 仍拿着 .draft 快照，会被判成非法跃迁
        let submitted = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(submitted, to: .reviewed)
        return try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
    }

    private func events(for productID: String) -> [CatalogSaleEvent] {
        (ShopCatalogDraftStore.loadOverlay()?.saleEvents ?? [])
            .filter { $0.productID == productID }
    }

    // MARK: T12 重复提交

    func testPublishingSameReviewedSnapshotTwiceProducesOneEffect() throws {
        let draft = try reviewedDraft(name: "重复点击款")
        _ = try draftStore.publish(draft, store: store)

        let published = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        let productID = try XCTUnwrap(published.publishedResult?.productID)
        let firstEventIDs = events(for: productID).map(\.id).sorted()
        XCTAssertEqual(firstEventIDs.count, 2, "预约 + 现货各一条")

        // 场景一：草稿已记录结果、状态已是 published → 再次点击被状态机拦下
        XCTAssertThrowsError(try draftStore.publish(published, store: store))

        // 场景二：UI 仍持有旧的 reviewed 快照（内存里没有 publishedResult）再发一次
        var staleSnapshot = draft
        staleSnapshot.status = .reviewed
        staleSnapshot.publishedResult = nil
        let summary = try draftStore.publish(staleSnapshot, store: store)
        XCTAssertTrue(summary.contains("已恢复发布结果"),
                      "旧快照重放应走恢复分支，不追加事件，实际：\(summary)")

        let afterEventIDs = events(for: productID).map(\.id).sorted()
        XCTAssertEqual(afterEventIDs, firstEventIDs, "重复发布不得产生第二组销售事件")

        // 场景三：草稿重新读到最新状态（已是 published）后再点一次 →
        // 状态机直接拦下，且不产生任何副作用
        draftStore.loadDrafts()
        let settled = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        XCTAssertEqual(settled.status, .published)
        XCTAssertThrowsError(try draftStore.publish(settled, store: store)) { error in
            guard case ShopCatalogDraftStoreError.notReadyForPublish = error else {
                return XCTFail("已发布草稿再次发布必须被状态机拦下，实际：\(error)")
            }
        }
        XCTAssertEqual(events(for: productID).map(\.id).sorted(), firstEventIDs)
    }

    func testEventIDsAreDeterministicAcrossCalls() {
        let draftID = "draft-fixed-id"
        let key = "op-key"
        func id(_ type: CatalogSaleEventType, _ k: String) -> String {
            ShopCatalogDraftStore.publishEventID(draftID: draftID, type: type, eventKey: k)
        }
        let a = id(.reservation, key)
        let b = id(.reservation, key)
        XCTAssertEqual(a, b, "同一草稿 + 同一内容必须得到同一事件 ID（可反查才能防重复）")
        XCTAssertNotEqual(a, id(.stock, key), "不同类型必须不同 ID")
        XCTAssertNotEqual(a, id(.reservation, key + "-changed"), "内容变了才允许新 ID")
    }

    /// 只改其中一个价 → 只有那一条换 ID，另一条保持原样（不会整组重发）
    func testEventKeyIsScopedToItsOwnPrice() {
        var base = CatalogProductDraft()
        base.id = "draft-scope"
        base.name = "单价变更款"
        base.newShopName = "单店"
        base.newSeriesName = "单系列"
        base.price = 428
        base.stockPrice = 498

        var raisedReservation = base
        raisedReservation.price = 528

        XCTAssertEqual(base.saleEventKey(.stock), raisedReservation.saleEventKey(.stock),
                       "现货价没变 → 现货事件指纹不得变")
        XCTAssertNotEqual(base.saleEventKey(.reservation), raisedReservation.saleEventKey(.reservation),
                          "预约价变了 → 预约事件指纹必须变")
    }

    /// 内容变了就允许一次**真实的新发布**（不同于「价格修正」的重复提交）
    func testChangedContentAllowsOneNewPublish() throws {
        let draft = try reviewedDraft(name: "改价再发布款")
        _ = try draftStore.publish(draft, store: store)
        let published = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        let productID = try XCTUnwrap(published.publishedResult?.productID)
        let before = events(for: productID).count

        // 真的改了内容（价格不同）→ 操作键变化 → 允许落一条新记录
        var changed = published
        changed.status = .reviewed
        changed.price = 528
        changed.deposit = 200
        changed.balance = 328
        try draftStore.upsert(changed)
        _ = try draftStore.publish(changed, store: store)

        let after = events(for: productID).count
        XCTAssertGreaterThan(after, before, "内容变化属于真实新记录，不能被幂等拦掉")
        XCTAssertEqual(after, before + 1,
                       "只追加本次变化的那一条：改的是预约价，现货价没变就不得重发（实际 \(before) → \(after)）")
        // 现货事件 ID 必须与上次完全相同（未变的价格不该换 ID）
        let stockIDs = Set(events(for: productID).filter { $0.type == .stock }.map(\.id))
        XCTAssertEqual(stockIDs.count, 1, "现货价未变 → 现货事件不得出现第二条")
    }

    // MARK: 半成功恢复

    func testOverlayWrittenButDraftStatusLostIsRecoverable() throws {
        let draft = try reviewedDraft(name: "半成功款")
        _ = try draftStore.publish(draft, store: store)
        let published = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        let productID = try XCTUnwrap(published.publishedResult?.productID)
        let expectedEvents = events(for: productID).map(\.id).sorted()

        // 模拟「覆盖层写成功、草稿状态与结果写失败」：抹掉草稿里的发布记录
        var orphan = published
        orphan.status = .reviewed
        orphan.publishedResult = nil
        try draftStore.upsert(orphan)

        let summary = try draftStore.publish(orphan, store: store)
        XCTAssertTrue(summary.contains("已恢复发布结果"), "应识别为半成功恢复，实际：\(summary)")
        XCTAssertEqual(events(for: productID).map(\.id).sorted(), expectedEvents,
                       "恢复只补回执，绝不重新生成一组事件")

        let recovered = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        XCTAssertEqual(recovered.status, .published)
        XCTAssertEqual(recovered.publishedResult?.productID, productID)
    }

    /// 草稿状态写失败时抛错带出「已发布」事实，运营不会误以为没发出去而反复点
    func testStatusWriteFailureSurfacesPublishedFact() throws {
        let draft = try reviewedDraft(name: "状态回执失败款")
        try draftStore.upsert(draft)

        // 让草稿写盘失败：把 drafts 文件换成目录
        let draftsURL = ShopCatalogStorage.directory
            .appendingPathComponent("shop-catalog-drafts.json")
        try FileManager.default.removeItem(at: draftsURL)
        try FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try draftStore.publish(draft, store: store)) { error in
            guard case ShopCatalogDraftStoreError.publishResultUnrecorded = error else {
                return XCTFail("应抛出「产物已发布、回执未保存」，实际：\(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("已发布"))
            XCTAssertTrue(error.localizedDescription.contains("请勿重复点击"),
                          "必须明确告诉运营不要再点，实际：\(error.localizedDescription)")
        }

        // 产物确实已经在覆盖层里
        let overlay = try XCTUnwrap(ShopCatalogDraftStore.loadOverlay())
        XCTAssertFalse(overlay.saleEvents.isEmpty, "覆盖层产物是既成事实，不回滚")
    }

    // MARK: T13 预约 / 现货并存

    func testBothPricesPublishedTogetherAndOldStockDraftNotReinterpreted() throws {
        // 新口径：预约 + 现货并存 → 两条事件
        let both = try reviewedDraft(name: "双价并存款", reservation: 428, stock: 498)
        _ = try draftStore.publish(both, store: store)
        let productID = try XCTUnwrap(
            draftStore.drafts.first { $0.id == both.id }?.publishedResult?.productID)
        let kinds = Set(events(for: productID).map(\.type))
        XCTAssertEqual(kinds, [.reservation, .stock])

        // 旧现货草稿（saleKind == .stock 且未填 stockPrice）：price 只按现货语义解释一次
        var legacy = CatalogProductDraft()
        legacy.name = "旧现货草稿款"
        legacy.saleKind = .stock
        legacy.price = 380
        legacy.stockPrice = nil
        legacy.newShopName = "旧现货店家"
        legacy.newSeriesName = "旧现货系列"
        try draftStore.upsert(legacy)
        try draftStore.advance(legacy, to: .submitted)
        let legacySubmitted = try XCTUnwrap(draftStore.drafts.first { $0.id == legacy.id })
        try draftStore.advance(legacySubmitted, to: .reviewed)
        let legacyReviewed = try XCTUnwrap(draftStore.drafts.first { $0.id == legacy.id })
        _ = try draftStore.publish(legacyReviewed, store: store)

        let legacyProductID = try XCTUnwrap(
            draftStore.drafts.first { $0.id == legacy.id }?.publishedResult?.productID)
        let legacyKinds = events(for: legacyProductID).map(\.type)
        XCTAssertEqual(legacyKinds, [.stock], "旧现货草稿的 price 不得再被解释成预约价")
        XCTAssertEqual(events(for: legacyProductID).first?.price, 380)
    }
}
