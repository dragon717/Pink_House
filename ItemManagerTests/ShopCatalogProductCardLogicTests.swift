//
//  ShopCatalogProductCardLogicTests.swift
//  ItemManagerTests
//
//  点菜式选购「商品卡片」纯逻辑契约（2026-09-22 V1.3）：
//    A. 同款合并（ShopCatalogSameDesignGrouper）
//       1. 仅颜色词差异 → 同款名，合并为一张卡
//       2. 长颜色词优先剥离（酒红色 不残留「酒」）
//       3. 颜色嵌进款名（樱花粉跳跃类）保守不合并 —— 剥离后回退
//       4. 无颜色词 → 颜色标签回退整名（卡片退化为单品）
//    B. 价格阶段（ShopCatalogCardPricePhase）
//       1. 双价 + 预约窗口进行中 → reservationOpen，默认预约价
//       2. 双价 + 窗口已结束 → chooseAfterEnded，可自选、默认现货
//       3. 仅预约价 / 仅现货价 / 无价
//

import XCTest
@testable import ItemManager

final class ShopCatalogProductCardLogicTests: XCTestCase {

    // MARK: A. 同款合并

    func testSameDesignDifferentColorsShareBaseName() {
        let a = ShopCatalogSameDesignGrouper.baseName(for: "夜莺 红色")
        let b = ShopCatalogSameDesignGrouper.baseName(for: "夜莺 黑色")
        XCTAssertEqual(a, "夜莺")
        XCTAssertEqual(a, b, "仅颜色词不同的商品应合并为同一张卡片")
    }

    func testCompoundColorWordStrippedBeforeShortWord() {
        XCTAssertEqual(ShopCatalogSameDesignGrouper.baseName(for: "夜莺 酒红色"), "夜莺",
                       "长颜色词优先，不能残留「酒」")
        XCTAssertEqual(ShopCatalogSameDesignGrouper.baseName(for: "夜莺 浅蓝色"), "夜莺")
    }

    func testColorEmbeddedInDesignNameStaysConservative() {
        // 「樱花粉跳跃」里的「粉色」不是独立颜色词，剥离后款名变化会误伤 —— 保守回退
        let base = ShopCatalogSameDesignGrouper.baseName(for: "樱花粉跳跃")
        XCTAssertEqual(base, "樱花粉跳跃", "颜色嵌进款名的命名不做剥离")
    }

    func testColorLabelFallsBackToFullName() {
        XCTAssertEqual(ShopCatalogSameDesignGrouper.colorLabel(for: "夜莺 红色"), "红色")
        XCTAssertEqual(ShopCatalogSameDesignGrouper.colorLabel(for: "无颜色词商品"),
                       "无颜色词商品", "无颜色词时标签回退整名")
    }

    func testBaseNameNeverEmpty() {
        XCTAssertEqual(ShopCatalogSameDesignGrouper.baseName(for: "红色"),
                       "红色", "整名都是颜色词时剥离后回退原名，避免空款名")
    }

    // MARK: B. 价格阶段

    func testBothPricesDuringReservationDefaultsToReservation() {
        let phase = ShopCatalogCardPricePhase.of(
            stockPrice: Decimal(string: "399"),
            reservationPrice: Decimal(string: "99"),
            reservationOpen: true)
        XCTAssertEqual(phase, .reservationOpen)
        XCTAssertFalse(phase.allowsChoice, "预约期间不允许自选，直接按预约价加入")
        XCTAssertEqual(phase.defaultChoice, .reservation)
    }

    func testBothPricesAfterReservationAllowsChoiceDefaultingToStock() {
        let phase = ShopCatalogCardPricePhase.of(
            stockPrice: Decimal(string: "399"),
            reservationPrice: Decimal(string: "99"),
            reservationOpen: false)
        XCTAssertEqual(phase, .chooseAfterEnded)
        XCTAssertTrue(phase.allowsChoice, "预约结束双价并存应允许用户自选")
        XCTAssertEqual(phase.defaultChoice, .stock)
    }

    func testReservationOnlyPhase() {
        let phase = ShopCatalogCardPricePhase.of(
            stockPrice: nil,
            reservationPrice: Decimal(string: "99"),
            reservationOpen: false)
        XCTAssertEqual(phase, .reservationOnly)
        XCTAssertFalse(phase.allowsChoice)
        XCTAssertEqual(phase.defaultChoice, .reservation)
    }

    func testSpotOnlyAndNoPricePhases() {
        XCTAssertEqual(ShopCatalogCardPricePhase.of(
            stockPrice: Decimal(string: "399"),
            reservationPrice: nil,
            reservationOpen: false), .spotOnly)
        XCTAssertEqual(ShopCatalogCardPricePhase.of(
            stockPrice: nil,
            reservationPrice: nil,
            reservationOpen: false), .noPrice)
        XCTAssertEqual(ShopCatalogCardPricePhase.of(
            stockPrice: Decimal(string: "399"),
            reservationPrice: nil,
            reservationOpen: true).defaultChoice, .stock)
    }
}
