//
//  CatalogBalanceDueApproximationTests.swift
//  ItemManagerTests
//
//  大致尾款时间 → 固定具体日期 估算契约（2026-09-25 需求三）。
//
//  口径（与实现文件头一致）：
//    · 上旬/月初 → 10 日；中旬 → 20 日；中下旬 → 25 日；下旬/月末/月底 → 当月最后一天
//    · 显式月份优先；未带 → 锚点所在月 + 1（约一个月为基准）
//    · 估算只向后看（候选早于锚点 → 整月推进）
//    · 同一输入 → 同一日期（不掺 Date()）；无旬关键词 → nil（缺依据不猜）
//
//  纯逻辑测试：固定日历 + 显式日期，不碰任何存储。
//

import XCTest
@testable import ItemManager

final class CatalogBalanceDueApproximationTests: XCTestCase {

    /// 固定时区日历：结果可断言到具体年月日，不受测试机时区影响
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func day(of date: Date, in calendar: Calendar) -> Int {
        calendar.component(.day, from: date)
    }

    // MARK: 1. 无显式月份：锚点 + 1 个月，旬定日

    func testUpperDecadeDefaultsToNextMonthDay10() throws {
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "上旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 10))
    }

    func testMiddleDecadeDefaultsToNextMonthDay20() throws {
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "中旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 20))
    }

    func testMiddleLateDecadeDefaultsToNextMonthDay25() throws {
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "中下旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 25))
    }

    func testLowerDecadeDefaultsToLastDayOfNextMonth() throws {
        // 10 月有 31 天
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "下旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 31))
    }

    func testLowerDecadeClampsToMonthEnd() throws {
        // 11 月只有 30 天 → 「下旬」落在 11-30，而不是溢出到 12-01
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "下旬", anchor: date(2026, 10, 15), calendar: calendar))
        XCTAssertEqual(result, date(2026, 11, 30))
        XCTAssertEqual(day(of: result, in: calendar), 30)
    }

    func testMonthStartAndEndSynonyms() throws {
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "月初", anchor: date(2026, 9, 30), calendar: calendar)), date(2026, 10, 10))
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "月底", anchor: date(2026, 9, 30), calendar: calendar)), date(2026, 10, 31))
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "月末", anchor: date(2026, 9, 30), calendar: calendar)), date(2026, 10, 31))
    }

    func testYearRollover() throws {
        // 12 月 + 1 个月 = 次年 1 月
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "上旬", anchor: date(2026, 12, 20), calendar: calendar))
        XCTAssertEqual(result, date(2027, 1, 10))
    }

    // MARK: 2. 显式月份

    func testExplicitArabicMonthOverridesAnchorMonth() throws {
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "11月上旬", anchor: date(2026, 9, 25), calendar: calendar))
        XCTAssertEqual(result, date(2026, 11, 10))
    }

    func testExplicitYearAndMonth() throws {
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "2027年3月中旬", anchor: date(2026, 9, 25), calendar: calendar))
        XCTAssertEqual(result, date(2027, 3, 20))
    }

    func testExplicitMonthAlreadyPassedRollsToNextYear() throws {
        // 锚点 11 月，「10月上旬」今年已过 → 明年 10 月
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "10月上旬", anchor: date(2026, 11, 20), calendar: calendar))
        XCTAssertEqual(result, date(2027, 10, 10))
    }

    func testExplicitChineseNumeralMonth() throws {
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "十月上旬", anchor: date(2026, 8, 15), calendar: calendar)), date(2026, 10, 10))
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "十二月下旬", anchor: date(2026, 8, 15), calendar: calendar)), date(2026, 12, 31))
    }

    // MARK: 3. 显式月份是硬约束；无显式月份的候选天然晚于锚点

    func testExplicitPassedMonthIsHardConstraintRollsToNextYear() throws {
        // 锚点已在 10 月，「9月下旬」（今年 9 月已过）→ 明年 9 月 30 日：
        // 显式月份不松绑成「最近一个满足旬的月末」，说 9 月就是 9 月
        let result = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "9月下旬", anchor: date(2026, 10, 5), calendar: calendar))
        XCTAssertEqual(result, date(2027, 9, 30))
    }

    // MARK: 4. 确定性：同一输入 → 同一日期（不含 Date() 输入）

    func testEstimateIsDeterministicAcrossCalls() throws {
        let anchor = date(2026, 9, 30)
        let first = CatalogBalanceDueApproximation.estimatedDate(
            text: "上旬", anchor: anchor, calendar: calendar)
        // 间隔再算（真实场景 = 用户隔天同步重算），结果必须逐秒相同
        let second = CatalogBalanceDueApproximation.estimatedDate(
            text: "上旬", anchor: anchor, calendar: calendar)
        XCTAssertEqual(first, second, "估一次就固定：同一输入不允许漂移")
    }

    // MARK: 5. 缺依据就不猜

    func testTextWithoutDecadeKeywordReturnsNil() {
        XCTAssertNil(CatalogBalanceDueApproximation.estimatedDate(
            text: "大货到后 1 个月", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertNil(CatalogBalanceDueApproximation.estimatedDate(
            text: "春节前", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertNil(CatalogBalanceDueApproximation.estimatedDate(
            text: "   ", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertNil(CatalogBalanceDueApproximation.estimatedDate(
            text: "", anchor: date(2026, 9, 30), calendar: calendar))
    }

    // MARK: 6. declaredWindow：系列声明 → 具体窗口

    func testExactDeclarationUsesDeclaredDatesDirectly() throws {
        let start = date(2026, 10, 15)
        let end = date(2026, 11, 15)
        let window = try XCTUnwrap(CatalogBalanceDueApproximation.declaredWindow(
            kind: .exact, text: nil, endText: nil,
            at: start, endAt: end,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(window.start, start)
        XCTAssertEqual(window.end, end)
        XCTAssertEqual(window.basis, "按运营声明的具体尾款时间")

        // 无结束时间 → 窗口退化为单日
        let single = try XCTUnwrap(CatalogBalanceDueApproximation.declaredWindow(
            kind: .exact, text: nil, endText: nil,
            at: start, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(single.end, start)
    }

    func testApproximateDeclarationEstimatesFixedWindow() throws {
        let window = try XCTUnwrap(CatalogBalanceDueApproximation.declaredWindow(
            kind: .approximate, text: "上旬", endText: "中下旬",
            at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(window.start, date(2026, 10, 10))
        XCTAssertEqual(window.end, date(2026, 10, 25))
        XCTAssertTrue(window.basis.contains("上旬"), "来源说明必须带上运营原文")
        XCTAssertTrue(window.basis.contains("约一个月"), "来源说明必须说清估算基准")
    }

    func testApproximateEndEarlierThanStartClampsToStart() throws {
        // 结束描述反而更早 → 收口到开始日（窗口不能为负）
        let window = try XCTUnwrap(CatalogBalanceDueApproximation.declaredWindow(
            kind: .approximate, text: "下旬", endText: "月初",
            at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(window.start, date(2026, 10, 31))
        XCTAssertEqual(window.end, date(2026, 10, 31))
    }

    func testDeclaredWindowReturnsNilWithoutBasis() {
        // 未声明
        XCTAssertNil(CatalogBalanceDueApproximation.declaredWindow(
            kind: nil, text: "上旬", endText: nil, at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        // 大致描述但缺锚点
        XCTAssertNil(CatalogBalanceDueApproximation.declaredWindow(
            kind: .approximate, text: "上旬", endText: nil, at: nil, endAt: nil,
            anchor: nil, calendar: calendar))
        // 大致描述但无旬关键词
        XCTAssertNil(CatalogBalanceDueApproximation.declaredWindow(
            kind: .approximate, text: "春节前", endText: nil, at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        // 声明了 exact 却没给时间
        XCTAssertNil(CatalogBalanceDueApproximation.declaredWindow(
            kind: .exact, text: nil, endText: nil, at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
    }
}
