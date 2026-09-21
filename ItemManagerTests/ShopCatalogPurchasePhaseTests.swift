//
//  ShopCatalogPurchasePhaseTests.swift
//  ItemManagerTests
//
//  商品详情操作区按预约状态条件渲染（运营口径）：
//    · 预约中 → 【加入心愿】（心愿尾款跟进定金/尾款）
//    · 预约未开始 → 【加入心愿】（实际作用 = 开售提醒）
//    · 现货在售 → 【加入少女衣橱】，不提供加入心愿
//    · 预约已结束 → 置灰【预约已结束】标签；有现货则引导购现货
//  验证 ShopCatalogPurchasePhase.resolve 的状态推导与优先级。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogPurchasePhaseTests: XCTestCase {

    // MARK: 预约中（Active）→ 加入心愿

    func testReservationWindowOpenYieldsReservationActive() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [.open], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: true
            ),
            .reservationActive
        )
    }

    /// 不设时间窗口的长期预约（ongoing）同样视为预约中
    func testReservationWindowOngoingYieldsReservationActive() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [.ongoing], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: true
            ),
            .reservationActive
        )
    }

    // MARK: 预约未开始（Upcoming）→ 加入心愿（= 开售提醒）

    func testReservationWindowUpcomingYieldsReservationUpcoming() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [.upcoming], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: false
            ),
            .reservationUpcoming
        )
    }

    // MARK: 现货在售（In Stock）→ 加入衣橱、不提供加入心愿

    func testStockWindowOpenWithoutReservationYieldsInStock() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [], stockWindowOpen: true,
                hasStockPrice: true, hasReservationPrice: false
            ),
            .inStock
        )
    }

    /// 无现货窗口但价格档案含现货价 → 仍按现货在售处理
    func testStockPriceArchiveWithoutWindowsYieldsInStock() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [], stockWindowOpen: false,
                hasStockPrice: true, hasReservationPrice: false
            ),
            .inStock
        )
    }

    // MARK: 预约已结束（Ended）→ 置灰标签；有现货则引导购现货

    func testReservationEndedYieldsReservationEnded() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [.ended], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: true
            ),
            .reservationEnded
        )
    }

    /// 预约已结束 + 现货在售：仍判为已结束（UI 层再按 hasStock 引导购现货），
    /// 而不是漏掉「已结束」提示让用户误以为还能预约
    func testReservationEndedWithStockStillEnded() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [.ended], stockWindowOpen: true,
                hasStockPrice: true, hasReservationPrice: true
            ),
            .reservationEnded
        )
    }

    // MARK: 优先级

    /// 同时存在进行中与未开始的预约窗口 → 预约中优先
    func testActiveWinsOverUpcoming() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [.upcoming, .open], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: true
            ),
            .reservationActive
        )
    }

    // MARK: 兜底

    /// 无任何窗口、无价格档案 → neutral（仅保留入库入口）
    func testNoInformationYieldsNeutral() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: false
            ),
            .neutral
        )
    }

    /// 只剩历史预约价（无窗口）→ 预约期已过，判为已结束
    func testReservationPriceOnlyYieldsReservationEnded() {
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [], stockWindowOpen: false,
                hasStockPrice: false, hasReservationPrice: true
            ),
            .reservationEnded
        )
    }
}
