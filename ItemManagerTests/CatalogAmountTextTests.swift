//
//  CatalogAmountTextTests.swift
//  ItemManagerTests
//
//  金额文本口径（2026-09-24 需求）：补录草稿价格组的
//  「尾款自动计算 + 非数字提示 + 定金大于预约价拦截」唯一口径。
//

import XCTest
@testable import ItemManager

final class CatalogAmountTextTests: XCTestCase {

    // MARK: 解析

    func testParseNormal() {
        XCTAssertEqual(CatalogAmountText.parse("88"), 88)
        XCTAssertEqual(CatalogAmountText.parse("88.5"), 88.5)
        XCTAssertEqual(CatalogAmountText.parse(" 71 "), 71)
        XCTAssertNil(CatalogAmountText.parse(""), "空 = 未填（合法）")
        XCTAssertNil(CatalogAmountText.parse("   "), "纯空白 = 未填（合法）")
    }

    func testParseFullWidthSeparators() {
        // 中文键盘常见：全角点 / 全角逗号当小数点
        XCTAssertEqual(CatalogAmountText.parse("88。5"), 88.5)
        XCTAssertEqual(CatalogAmountText.parse("88，5"), 88.5)
    }

    func testParseInvalid() {
        XCTAssertNil(CatalogAmountText.parse("八十八"), "中文数字必须解析失败")
        XCTAssertNil(CatalogAmountText.parse("88元"), "带单位必须解析失败")
        XCTAssertNil(CatalogAmountText.parse("8.8.8"), "多小数点必须解析失败")
        XCTAssertNil(CatalogAmountText.parse("abc"), "字母必须解析失败")
    }

    // MARK: 校验提示

    func testValidationErrorText() {
        XCTAssertNil(CatalogAmountText.validationErrorText(for: "", label: "预约价"),
                     "未填不给提示")
        XCTAssertNil(CatalogAmountText.validationErrorText(for: "88", label: "预约价"),
                     "合法数字不给提示")
        XCTAssertEqual(
            CatalogAmountText.validationErrorText(for: "八十八", label: "预约价"),
            "「预约价」需为数字（当前输入：八十八）")
    }

    // MARK: 尾款派生（尾款 = 预约价 − 定金，自动计算）

    func testBalanceDerivedFromReservationAndDeposit() {
        XCTAssertEqual(CatalogAmountText.balance(reservation: 88, deposit: 17), 71)
        XCTAssertEqual(CatalogAmountText.balance(reservation: 88, deposit: 0), 88)
        XCTAssertEqual(CatalogAmountText.balance(reservation: 88, deposit: nil), 88,
                       "定金未填按 0")
        XCTAssertNil(CatalogAmountText.balance(reservation: nil, deposit: 17),
                     "未填预约价没有对账基准，尾款无从谈起")
        XCTAssertNil(CatalogAmountText.balance(reservation: nil, deposit: nil))
        // 定金大于预约价 → 负尾款（由视图层红字提示 + 保存拦截，口径本身如实派生）
        XCTAssertEqual(CatalogAmountText.balance(reservation: 17, deposit: 88), -71)
    }

    // MARK: 回填展示

    func testDisplayText() {
        XCTAssertEqual(CatalogAmountText.displayText(88), "88", "整数不带 .0")
        XCTAssertEqual(CatalogAmountText.displayText(88.5), "88.5")
        XCTAssertEqual(CatalogAmountText.displayText(0), "0")
    }
}
