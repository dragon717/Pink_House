//
//  ShopCatalogV11GapTests.swift
//  ItemManagerTests
//
//  V1.1 P0 缺口补齐验收（MVP 审计发现）：
//    · 差价百分比：CatalogPriceArchive.stockOverReservationDeltaPercent（V1.1 §1 P0 #4）
//    · 审核驳回保留原因：rejectReason 写入 / 空白归一 / 重新提交清空（V1.1 §4.1）
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogV11GapTests: XCTestCase {

    // MARK: 差价百分比（V1.1 §1 P0：展示预约‑现货差价及百分比）

    private func archive(reservation: Decimal?, stock: Decimal?) -> CatalogPriceArchive {
        var events: [CatalogSaleEvent] = []
        if let r = reservation {
            events.append(CatalogSaleEvent(id: "r", productID: "p", type: .reservation, price: r))
        }
        if let s = stock {
            events.append(CatalogSaleEvent(id: "s", productID: "p", type: .stock, price: s))
        }
        return CatalogPriceArchive(events: events)
    }

    func testDeltaPercentPositive() throws {
        let a = archive(reservation: 700, stock: 840)
        XCTAssertEqual(a.stockOverReservationDelta, 140)
        XCTAssertEqual(try XCTUnwrap(a.stockOverReservationDeltaPercent), 20, accuracy: 0.001)
    }

    func testDeltaPercentNegative() throws {
        let a = archive(reservation: 800, stock: 560)
        XCTAssertEqual(a.stockOverReservationDelta, -240)
        XCTAssertEqual(try XCTUnwrap(a.stockOverReservationDeltaPercent), -30, accuracy: 0.001)
    }

    func testDeltaPercentNilWhenReservationMissingOrZero() {
        // 现货缺失
        XCTAssertNil(archive(reservation: 700, stock: nil).stockOverReservationDeltaPercent)
        // 预约缺失（只有现货）
        XCTAssertNil(archive(reservation: nil, stock: 700).stockOverReservationDeltaPercent)
        // 预约价为 0：百分比无意义，返回 nil
        XCTAssertNil(archive(reservation: 0, stock: 700).stockOverReservationDeltaPercent)
    }

    // MARK: 审核驳回保留原因（V1.1 §4.1）

    private var draftStore: ShopCatalogDraftStore { ShopCatalogDraftStore.shared }

    override func setUp() {
        super.setUp()
        // 存储重定向到临时目录：测试不得触碰用户真实沙盒（2026-09-21 事故防线）
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    /// 提交一条 submitted 草稿（不发布），返回回读结果
    private func makeSubmittedDraft(name: String) throws -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.saleKind = .stock
        draft.price = 199
        try draftStore.upsert(draft)
        try draftStore.advance(draft, to: .submitted)
        return try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
    }

    func testRejectWritesReasonAndReturnsToDraft() throws {
        let draft = try makeSubmittedDraft(name: "驳回原因-样例")
        try draftStore.review(draft, approve: false, reason: "  尺码表缺失，补全后再提交  ")
        let back = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        XCTAssertEqual(back.status, .draft)
        XCTAssertEqual(back.rejectReason, "尺码表缺失，补全后再提交", "驳回原因去除首尾空白后保留")
    }

    func testRejectBlankReasonNormalizedToNil() throws {
        let draft = try makeSubmittedDraft(name: "驳回空原因-样例")
        try draftStore.review(draft, approve: false, reason: "   ")
        let back = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        XCTAssertEqual(back.status, .draft)
        XCTAssertNil(back.rejectReason, "空白原因归一为 nil")
    }

    func testResubmitClearsRejectReason() throws {
        var draft = try makeSubmittedDraft(name: "重新提交-样例")
        try draftStore.review(draft, approve: false, reason: "配色信息缺失")
        draft = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        XCTAssertEqual(draft.rejectReason, "配色信息缺失")

        // 补录后重新提交 → 原因清空（advance 状态机统一处理）
        try draftStore.advance(draft, to: .submitted)
        let resubmitted = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        XCTAssertEqual(resubmitted.status, .submitted)
        XCTAssertNil(resubmitted.rejectReason, "重新提交即视为已回应驳回意见")
    }

    func testRejectReasonDecodesFromOldJSONAsNil() throws {
        // 旧草稿 JSON 无 rejectReason → 解码自动兜底 nil（向后兼容）。
        // 用「编码当前草稿 → 剥离 rejectReason 键」构造旧格式，避免手写 JSON 漏字段。
        let current = try JSONEncoder().encode(CatalogProductDraft())
        var obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: current) as? [String: Any])
        obj.removeValue(forKey: "rejectReason")
        let oldFormat = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(CatalogProductDraft.self, from: oldFormat)
        XCTAssertNil(decoded.rejectReason)
    }
}
