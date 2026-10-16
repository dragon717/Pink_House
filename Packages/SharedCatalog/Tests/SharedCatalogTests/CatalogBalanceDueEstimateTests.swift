import XCTest
@testable import SharedCatalog

final class CatalogBalanceDueEstimateTests: XCTestCase {

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

    func testUpperDecadeDefaultsToNextMonthDay5() throws {
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "上旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 5))
    }

    func testMiddleDecadeDefaultsToNextMonthDay15() throws {
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "中旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 15))
    }

    func testMiddleLateDecadeDefaultsToNextMonthDay20() throws {
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "中下旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 20))
    }

    func testLowerDecadeDefaultsToNextMonthDay25() throws {
        // 10 月有 31 天
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "下旬", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(result, date(2026, 10, 25))
    }

    func testLowerDecadeUsesMidpointInThirtyDayMonth() throws {
        // 11 月有 30 天，下旬同样固定取 25 日。
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "下旬", anchor: date(2026, 10, 15), calendar: calendar))
        XCTAssertEqual(result, date(2026, 11, 25))
        XCTAssertEqual(day(of: result, in: calendar), 25)
    }

    func testMonthStartAndEndSynonyms() throws {
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "月初", anchor: date(2026, 9, 30), calendar: calendar)), date(2026, 10, 5))
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "月底", anchor: date(2026, 9, 30), calendar: calendar)), date(2026, 10, 31))
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "月末", anchor: date(2026, 9, 30), calendar: calendar)), date(2026, 10, 31))
    }

    func testYearRollover() throws {
        // 12 月 + 1 个月 = 次年 1 月
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "上旬", anchor: date(2026, 12, 20), calendar: calendar))
        XCTAssertEqual(result, date(2027, 1, 5))
    }

    // MARK: 2. 显式月份

    func testDecadeMidpointsStayFixedAcrossMonthLengths() throws {
        for (year, month) in [(2027, 1), (2027, 4), (2027, 2), (2028, 2)] {
            for (period, expectedDay) in [("上旬", 5), ("中旬", 15), ("下旬", 25)] {
                let actual = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
                    text: "\(year)年\(month)月\(period)", anchor: nil, calendar: calendar))
                XCTAssertEqual(actual, date(year, month, expectedDay))
            }
        }
    }

    func testExplicitArabicMonthOverridesAnchorMonth() throws {
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "11月上旬", anchor: date(2026, 9, 25), calendar: calendar))
        XCTAssertEqual(result, date(2026, 11, 5))
    }

    func testExplicitYearAndMonth() throws {
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "2027年3月中旬", anchor: date(2026, 9, 25), calendar: calendar))
        XCTAssertEqual(result, date(2027, 3, 15))
    }

    func testExplicitMonthAlreadyPassedRollsToNextYear() throws {
        // 锚点 11 月，「10月上旬」今年已过 → 明年 10 月
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "10月上旬", anchor: date(2026, 11, 20), calendar: calendar))
        XCTAssertEqual(result, date(2027, 10, 5))
    }

    func testExplicitChineseNumeralMonth() throws {
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "十月上旬", anchor: date(2026, 8, 15), calendar: calendar)), date(2026, 10, 5))
        XCTAssertEqual(try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "十二月下旬", anchor: date(2026, 8, 15), calendar: calendar)), date(2026, 12, 25))
    }

    // MARK: 3. 显式月份是硬约束；无显式月份的候选天然晚于锚点

    func testExplicitPassedMonthIsHardConstraintRollsToNextYear() throws {
        // 锚点已在 10 月，「9月下旬」（今年 9 月已过）→ 明年 9 月 25 日：
        // 显式月份不松绑成「最近一个满足旬的月末」，说 9 月就是 9 月
        let result = try XCTUnwrap(CatalogBalanceDueEstimate.estimatedDate(
            text: "9月下旬", anchor: date(2026, 10, 5), calendar: calendar))
        XCTAssertEqual(result, date(2027, 9, 25))
    }

    // MARK: 4. 确定性：同一输入 → 同一日期（不含 Date() 输入）

    func testEstimateIsDeterministicAcrossCalls() throws {
        let anchor = date(2026, 9, 30)
        let first = CatalogBalanceDueEstimate.estimatedDate(
            text: "上旬", anchor: anchor, calendar: calendar)
        // 间隔再算（真实场景 = 用户隔天同步重算），结果必须逐秒相同
        let second = CatalogBalanceDueEstimate.estimatedDate(
            text: "上旬", anchor: anchor, calendar: calendar)
        XCTAssertEqual(first, second, "估一次就固定：同一输入不允许漂移")
    }

    // MARK: 5. 缺依据就不猜

    func testTextWithoutDecadeKeywordReturnsNil() {
        XCTAssertNil(CatalogBalanceDueEstimate.estimatedDate(
            text: "大货到后 1 个月", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertNil(CatalogBalanceDueEstimate.estimatedDate(
            text: "发货前", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertNil(CatalogBalanceDueEstimate.estimatedDate(
            text: "   ", anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertNil(CatalogBalanceDueEstimate.estimatedDate(
            text: "", anchor: date(2026, 9, 30), calendar: calendar))
    }

    // MARK: 6. declaredWindow：系列声明 → 具体窗口

    func testExactDeclarationUsesDeclaredDatesDirectly() throws {
        let start = date(2026, 10, 15)
        let end = date(2026, 11, 15)
        let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(
            kind: .exact, text: nil, endText: nil,
            at: start, endAt: end,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(window.start, start)
        XCTAssertEqual(window.end, end)
        XCTAssertEqual(window.basis, "按运营声明的具体尾款时间")

        // 无结束时间 → 窗口退化为单日
        let single = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(
            kind: .exact, text: nil, endText: nil,
            at: start, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(single.end, start)
    }

    func testApproximateDeclarationEstimatesFixedWindow() throws {
        let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(
            kind: .approximate, text: "上旬", endText: "中下旬",
            at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(window.start, date(2026, 10, 5))
        XCTAssertEqual(window.end, date(2026, 10, 20))
        XCTAssertTrue(window.basis.contains("上旬"), "来源说明必须带上运营原文")
        XCTAssertTrue(window.basis.contains("约一个月"), "来源说明必须说清估算基准")
    }

    func testApproximateEndEarlierThanStartClampsToStart() throws {
        // 结束描述反而更早 → 收口到开始日（窗口不能为负）
        let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(
            kind: .approximate, text: "下旬", endText: "月初",
            at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        XCTAssertEqual(window.start, date(2026, 10, 25))
        XCTAssertEqual(window.end, date(2026, 10, 25))
    }

    func testDeclaredWindowReturnsNilWithoutBasis() {
        // 未声明
        XCTAssertNil(CatalogBalanceDueEstimate.declaredWindow(
            kind: nil, text: "上旬", endText: nil, at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        // 大致描述但缺锚点
        XCTAssertNil(CatalogBalanceDueEstimate.declaredWindow(
            kind: .approximate, text: "上旬", endText: nil, at: nil, endAt: nil,
            anchor: nil, calendar: calendar))
        // 大致描述但无旬关键词
        XCTAssertNil(CatalogBalanceDueEstimate.declaredWindow(
            kind: .approximate, text: "发货前", endText: nil, at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
        // 声明了 exact 却没给时间
        XCTAssertNil(CatalogBalanceDueEstimate.declaredWindow(
            kind: .exact, text: nil, endText: nil, at: nil, endAt: nil,
            anchor: date(2026, 9, 30), calendar: calendar))
    }
    func testExplicitYearMonthNeedsNoReservationEnd() throws {
        for (text, expected) in [("2027年1月上旬", date(2027, 1, 5)),
                                 ("2027年2月中旬", date(2027, 2, 15)),
                                 ("2027年3月下旬", date(2027, 3, 25)),
                                 ("2028年2月下旬", date(2028, 2, 25))] {
            let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(
                kind: .approximate, text: text, endText: nil, at: nil, endAt: nil,
                anchor: nil, calendar: calendar))
            XCTAssertEqual(window.start, expected)
            XCTAssertEqual(window.end, expected)
        }
    }

    func testExplicitPastYearMonthStaysAsDeclared() {
        XCTAssertEqual(CatalogBalanceDueEstimate.estimatedDate(text: "2026年1月上旬",
            anchor: date(2027, 10, 15), calendar: calendar), date(2026, 1, 5))
        XCTAssertEqual(CatalogBalanceDueEstimate.estimatedDate(text: "10月上旬",
            anchor: date(2026, 10, 15), calendar: calendar), date(2027, 10, 5))
    }

    func testMonthAndDecadeNeedNoReservationEndAfterAuthoring() throws {
        let reference = date(2026, 10, 15)
        let batch = CatalogReservationBatch(id: "early", name: "先行团", balanceDueKind: .approximate,
            balanceDueText: "1月上旬", balanceDueEndText: "2月中旬", balanceDueReferenceAt: reference)
        XCTAssertNil(batch.reservationEndAt)
        XCTAssertNil(CatalogReservationBatch.validationError(in: [batch]))
        let before = try XCTUnwrap(batch.estimatedWindow(calendar: calendar))
        XCTAssertEqual(before.start, date(2027, 1, 5))
        XCTAssertEqual(before.end, date(2027, 2, 15))
        let restored = try JSONDecoder().decode(CatalogReservationBatch.self,
            from: JSONEncoder().encode(batch))
        XCTAssertEqual(restored.estimatedWindow(anchor: date(2028, 10, 15), calendar: calendar), before)
        let series = CatalogSeries(id: "series", shopID: "shop", name: "系列", reservationBatches: [restored])
        let schedule = try XCTUnwrap(series.paymentSchedule(batchID: "early"))
        let actual = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(of: schedule,
            anchor: nil, calendar: calendar))
        XCTAssertEqual(actual.start, before.start)
        XCTAssertEqual(actual.end, before.end)
        XCTAssertNil(schedule.reservationEndAt)
        XCTAssertNil(schedule.balanceDueAt, "估算不伪装成运营公布的具体日期")
    }

    func testLegacyBatchWithoutReferenceStillDecodes() throws {
        let batch = try JSONDecoder().decode(CatalogReservationBatch.self,
            from: Data(#"{"id":"old","name":"一团","balanceDueKind":"approximate","balanceDueText":"上旬"}"#.utf8))
        XCTAssertNil(batch.balanceDueReferenceAt)
        XCTAssertNil(batch.estimatedWindow(calendar: calendar))
        XCTAssertEqual(batch.estimatedWindow(anchor: date(2026, 9, 30), calendar: calendar)?.start,
            date(2026, 10, 5))
    }

    func testDurationEndsFromEstimatedStartRatherThanReservationOrAuthoringDate() throws {
        for (text, expected) in [("十天", date(2026, 12, 29)), ("10天", date(2026, 12, 29)),
                                 ("十五天", date(2027, 1, 3)), (" 15 天 ", date(2027, 1, 3)),
                                 ("一个月", date(2027, 1, 19)), ("1个月", date(2027, 1, 19)),
                                 ("半个月", date(2027, 1, 3)), ("两周", date(2027, 1, 2)),
                                 ("三十天", date(2027, 1, 18))] {
            let batch = CatalogReservationBatch(id: "early", name: "先行团", balanceDueKind: .approximate,
                balanceDueText: "圣诞节前", balanceDueEndText: text, balanceDueReferenceAt: date(2026, 10, 15))
            let window = try XCTUnwrap(batch.estimatedWindow(anchor: date(2026, 9, 27), calendar: calendar))
            XCTAssertEqual(window.start, date(2026, 12, 19), text)
            XCTAssertEqual(window.end, expected, text)
            XCTAssertTrue(window.basis.contains("结束按开始后"))
            XCTAssertEqual(batch.balanceDueEndText, text, "保留运营原文")
            let restored = try JSONDecoder().decode(CatalogReservationBatch.self, from: JSONEncoder().encode(batch))
            XCTAssertEqual(restored.estimatedWindow(anchor: date(2029, 1, 1), calendar: calendar), window)
        }
    }

    func testDurationCalendarMonthClampsToMonthEndAndKeepsLeapYear() throws {
        for (start, expected) in [("2027年1月底", date(2027, 2, 28)),
                                  ("2028年1月底", date(2028, 2, 29)),
                                  ("2026年12月底", date(2027, 1, 31))] {
            let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(kind: .approximate,
                text: start, endText: "一个月", at: nil, endAt: nil, anchor: nil, calendar: calendar))
            XCTAssertEqual(window.end, expected)
        }
    }

    func testBlankOrUnsupportedDurationDoesNotInventAnEndDate() throws {
        for end in [nil, "", " ", "零天", "0天", "-10天", "10000天", "9999个月", "十十天", "大货到后一个月"] {
            let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(kind: .approximate,
                text: "2026年圣诞节前", endText: end, at: nil, endAt: nil, anchor: nil, calendar: calendar))
            XCTAssertEqual(window.end, window.start, end ?? "nil")
            XCTAssertFalse(window.basis.contains("结束按开始后"))
        }
        XCTAssertNil(CatalogBalanceDueEstimate.declaredWindow(kind: .approximate, text: "待公布",
            endText: "十五天", at: nil, endAt: nil, anchor: date(2026, 10, 15), calendar: calendar))
    }

    func testCalendarEndDescriptionIsNotMisreadAsDuration() throws {
        let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(kind: .approximate,
            text: "2026年9月上旬", endText: "十月上旬", at: nil, endAt: nil,
            anchor: date(2026, 8, 15), calendar: calendar))
        XCTAssertEqual(window.end, date(2026, 10, 5))
        XCTAssertFalse(window.basis.contains("结束按开始后"))
    }

}
