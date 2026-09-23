//
//  ShopCatalogSeriesYearMonthTests.swift
//  ItemManagerTests
//
//  2026-09-24 需求回归：
//    · 「年份」→「年月」：录入同时支持 "2026-10" 与 "2026年10月"，
//      纯年份仍有效（存量系列回填后直接保存不能被校验拦下）；
//    · CatalogSeries.month 为新增 Optional 字段，旧 JSON 缺键自动置 nil（零迁移）；
//    · 预约价格表多图：CatalogPriceChart.sourceImages 同为新增 Optional，
//      旧 JSON 缺键置 nil；录入文本「每行一个引用」的拆分口径唯一。
//

import XCTest
@testable import ItemManager

@MainActor
final class CatalogYearMonthTextTests: XCTestCase {

    // MARK: 两种新格式

    func testParseDashFormat() throws {
        let parsed = try XCTUnwrap(CatalogYearMonthText.parse("2026-10"))
        XCTAssertEqual(parsed.year, 2026)
        XCTAssertEqual(parsed.month, 10)
    }

    func testParseChineseFormat() throws {
        let parsed = try XCTUnwrap(CatalogYearMonthText.parse("2026年10月"))
        XCTAssertEqual(parsed.year, 2026)
        XCTAssertEqual(parsed.month, 10)
    }

    func testParseChineseFormatSingleDigitMonth() throws {
        // 用户实际会顺手写的形态：个位月份不带前导零
        let parsed = try XCTUnwrap(CatalogYearMonthText.parse("2026年3月"))
        XCTAssertEqual(parsed.year, 2026)
        XCTAssertEqual(parsed.month, 3)
    }

    // MARK: 兼容旧数据（纯年份）

    func testParseYearOnlyStaysValid() throws {
        let parsed = try XCTUnwrap(CatalogYearMonthText.parse("2026"))
        XCTAssertEqual(parsed.year, 2026)
        XCTAssertNil(parsed.month, "纯年份 = 旧数据形态，month 必须为 nil")
    }

    // MARK: 清除与非法输入

    func testParseEmptyReturnsNilForClearing() {
        XCTAssertNil(CatalogYearMonthText.parse(""))
        XCTAssertNil(CatalogYearMonthText.parse("   "))
    }

    func testParseRejectsInvalidMonth() {
        XCTAssertNil(CatalogYearMonthText.parse("2026-13"))
        XCTAssertNil(CatalogYearMonthText.parse("2026-0"))
        XCTAssertNil(CatalogYearMonthText.parse("2026年13月"))
    }

    func testParseRejectsGarbageAndOutOfRangeYear() {
        XCTAssertNil(CatalogYearMonthText.parse("abc"))
        XCTAssertNil(CatalogYearMonthText.parse("2026年月"))
        XCTAssertNil(CatalogYearMonthText.parse("1800-01"))
        XCTAssertNil(CatalogYearMonthText.parse("2101-01"))
    }

    // MARK: 校验错误文案

    func testValidationErrorEmptyIsNil() {
        XCTAssertNil(CatalogYearMonthText.validationErrorText(for: ""))
    }

    func testValidationErrorForInvalidInputIsNotNil() {
        XCTAssertNotNil(CatalogYearMonthText.validationErrorText(for: "2026-13"))
        // 合法输入不该报错
        XCTAssertNil(CatalogYearMonthText.validationErrorText(for: "2026-10"))
        XCTAssertNil(CatalogYearMonthText.validationErrorText(for: "2026年10月"))
    }

    // MARK: 展示口径

    func testDisplayText() {
        XCTAssertEqual(CatalogYearMonthText.displayText(year: 2026, month: 10), "2026-10")
        XCTAssertEqual(CatalogYearMonthText.displayText(year: 2026, month: nil), "2026")
        XCTAssertNil(CatalogYearMonthText.displayText(year: nil, month: 10))
        XCTAssertNil(CatalogYearMonthText.displayText(year: nil, month: nil))
    }

    // MARK: CatalogSeries 兼容

    func testSeriesOldJSONWithoutMonthDecodesAsNil() throws {
        // 模拟旧覆盖层：只有 year，没有 month 键
        let json = """
        {"id":"s1","shopID":"shop1","name":"雪国来信","year":2026}
        """
        let series = try ShopCatalogJSONCoding.decoder()
            .decode(CatalogSeries.self, from: Data(json.utf8))
        XCTAssertEqual(series.year, 2026)
        XCTAssertNil(series.month)
        XCTAssertEqual(series.yearMonthText, "2026")
    }

    func testSeriesRoundTripKeepsMonth() throws {
        var series = CatalogSeries(id: "s2", shopID: "shop1", name: "雪国来信")
        series.year = 2026
        series.month = 10
        let data = try ShopCatalogJSONCoding.encoder().encode(series)
        let decoded = try ShopCatalogJSONCoding.decoder()
            .decode(CatalogSeries.self, from: data)
        XCTAssertEqual(decoded.year, 2026)
        XCTAssertEqual(decoded.month, 10)
        XCTAssertEqual(decoded.yearMonthText, "2026-10")
    }
}

@MainActor
final class CatalogPriceChartMultiImageTests: XCTestCase {

    // MARK: 录入文本拆分口径

    func testReferencesSplitByLineAndTrim() {
        let text = "local:img-a.jpg\n  local:img-b.jpg  \n\nlocal:img-c.jpg"
        XCTAssertEqual(
            CatalogPriceChartImageText.references(fromText: text),
            ["local:img-a.jpg", "local:img-b.jpg", "local:img-c.jpg"])
    }

    func testReferencesEmptyTextYieldsEmptyArray() {
        XCTAssertTrue(CatalogPriceChartImageText.references(fromText: "").isEmpty)
        XCTAssertTrue(CatalogPriceChartImageText.references(fromText: "\n \n").isEmpty)
    }

    // MARK: CatalogPriceChart 兼容

    func testOldJSONWithoutSourceImagesDecodesAsNil() throws {
        let json = """
        {"id":"pc1","seriesID":"s1","columns":["款式","预约价"],
         "rows":[{"label":"JSK","values":["428",null]}],"sourceImage":"local:img-a.jpg"}
        """
        let chart = try ShopCatalogJSONCoding.decoder()
            .decode(CatalogPriceChart.self, from: Data(json.utf8))
        XCTAssertNil(chart.sourceImages, "旧数据缺 sourceImages 键必须置 nil，不能抛错")
        XCTAssertEqual(chart.sourceImage, "local:img-a.jpg")
    }

    func testRoundTripKeepsMultipleImages() throws {
        var chart = CatalogPriceChart(id: "pc2", seriesID: "s1")
        chart.sourceImages = ["local:img-a.jpg", "local:img-b.jpg"]
        chart.sourceImage = "local:img-a.jpg"
        let data = try ShopCatalogJSONCoding.encoder().encode(chart)
        let decoded = try ShopCatalogJSONCoding.decoder()
            .decode(CatalogPriceChart.self, from: data)
        XCTAssertEqual(decoded.sourceImages, ["local:img-a.jpg", "local:img-b.jpg"])
        XCTAssertEqual(decoded.sourceImage, "local:img-a.jpg")
    }
}
