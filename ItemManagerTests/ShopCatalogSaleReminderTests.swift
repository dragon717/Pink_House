//
//  ShopCatalogSaleReminderTests.swift
//  ItemManagerTests
//
//  开售提醒（预约未开始 → 加入心愿 = 到点通知）纯逻辑验收：
//    · upcomingSaleStart：只挑未来预约窗口的最早 startAt；未定档 / 已开始 / 非预约记录不挑
//    · identifier：同商品幂等（重复加入覆盖，不堆积）
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogSaleReminderTests: XCTestCase {

    private func event(
        id: String = "e1",
        type: CatalogSaleEventType = .reservation,
        start: Date?,
        end: Date? = nil
    ) -> CatalogSaleEvent {
        CatalogSaleEvent(id: id, productID: "p1", type: type, price: 100,
                         deposit: nil, balance: nil, startAt: start, endAt: end)
    }

    // MARK: upcomingSaleStart

    /// 单个未来预约窗口 → 取其 startAt
    func testUpcomingReservationStartIsPicked() throws {
        let now = Date()
        let start = now.addingTimeInterval(86_400)
        let fire = ShopCatalogSaleReminder.upcomingSaleStart(events: [event(start: start)], now: now)
        XCTAssertEqual(fire, start)
    }

    /// 多个未来窗口 → 取最早的一个
    func testEarliestUpcomingStartWins() throws {
        let now = Date()
        let later = now.addingTimeInterval(86_400 * 7)
        let earlier = now.addingTimeInterval(86_400)
        let fire = ShopCatalogSaleReminder.upcomingSaleStart(events: [
            event(id: "e-late", start: later),
            event(id: "e-early", start: earlier)
        ], now: now)
        XCTAssertEqual(fire, earlier)
    }

    /// 已开始 / 已结束的窗口不提醒
    func testStartedOrEndedWindowsIgnored() {
        let now = Date()
        let events = [
            event(id: "e-open", start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(3_600)),
            event(id: "e-ended", start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-3_600))
        ]
        XCTAssertNil(ShopCatalogSaleReminder.upcomingSaleStart(events: events, now: now))
    }

    /// 未定档（startAt == nil）不提醒
    func testUndatedWindowIgnored() {
        let now = Date()
        XCTAssertNil(ShopCatalogSaleReminder.upcomingSaleStart(events: [event(start: nil)], now: now))
    }

    /// 现货 / 再贩记录不触发开售提醒（语义只针对预约开始）
    func testNonReservationTypesIgnored() {
        let now = Date()
        let events = [
            event(id: "e-stock", type: .stock, start: now.addingTimeInterval(86_400)),
            event(id: "e-rerelease", type: .rerelease, start: now.addingTimeInterval(86_400))
        ]
        XCTAssertNil(ShopCatalogSaleReminder.upcomingSaleStart(events: events, now: now))
    }

    /// 未来预约窗口与已开始的现货并存 → 仍提醒预约开始
    func testUpcomingReservationAmongStockEvents() throws {
        let now = Date()
        let start = now.addingTimeInterval(86_400)
        let events = [
            event(id: "e-stock", type: .stock, start: now.addingTimeInterval(-600)),
            event(id: "e-res", start: start)
        ]
        XCTAssertEqual(ShopCatalogSaleReminder.upcomingSaleStart(events: events, now: now), start)
    }

    // MARK: identifier 幂等

    func testIdentifierStablePerProduct() {
        XCTAssertEqual(
            ShopCatalogSaleReminder.identifier(for: "prod-ag-xueguo-jsk"),
            ShopCatalogSaleReminder.identifier(for: "prod-ag-xueguo-jsk")
        )
        XCTAssertNotEqual(
            ShopCatalogSaleReminder.identifier(for: "prod-a"),
            ShopCatalogSaleReminder.identifier(for: "prod-b")
        )
        XCTAssertTrue(ShopCatalogSaleReminder.identifier(for: "p1")
            .hasPrefix(ShopCatalogSaleReminder.identifierPrefix))
    }

    // MARK: 文案

    func testContentBodyComposesSeriesAndProduct() {
        XCTAssertEqual(
            ShopCatalogSaleReminder.contentBody(productName: "雪国来信 JSK", seriesName: "雪国来信"),
            "「雪国来信·雪国来信 JSK」预约已开始，记得去店家下单"
        )
        XCTAssertEqual(
            ShopCatalogSaleReminder.contentBody(productName: "孤品", seriesName: nil),
            "「孤品」预约已开始，记得去店家下单"
        )
    }
}
