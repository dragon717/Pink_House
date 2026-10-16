import XCTest
@testable import SharedCatalog

final class CatalogHolidayEstimateTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func estimate(_ text: String, anchor: Date? = nil) -> Date? {
        CatalogBalanceDueEstimate.estimatedDate(text: text, anchor: anchor, calendar: calendar)
    }

    func testChristmasBeforeUsesSixDaysAndAcceptsNormalPhrasings() {
        for text in ["圣诞节前", "圣诞前", "圣诞节之前", "圣诞节以前", "圣诞节前夕", "聖誕節前"] {
            XCTAssertEqual(estimate(text, anchor: date(2026, 10, 15)), date(2026, 12, 19), text)
        }
        XCTAssertEqual(estimate("2026年圣诞节前"), date(2026, 12, 19))
        XCTAssertEqual(estimate("2027 年圣诞节前"), date(2027, 12, 19))
        XCTAssertEqual(estimate("平安夜前", anchor: date(2026, 10, 15)), date(2026, 12, 18))
    }

    func testFixedDateHolidaysUseTheSameLeadTime() {
        for (text, month, day) in [("2026年国庆节前", 9, 25), ("2026年五一前", 4, 25),
                                    ("2026年儿童节前", 5, 26), ("2026年妇女节前", 3, 2),
                                    ("2026年情人节前", 2, 8)] {
            XCTAssertEqual(estimate(text), date(2026, month, day), text)
        }
    }

    func testLunarHolidaysMatchObservatory2026And2027ConversionTables() {
        // 香港天文台公历/农历对照表：春节 2026-02-17 / 2027-02-06，
        // 端午 2026-06-19，中秋 2026-09-25 / 2027-09-15；各提前六天。
        for (text, year, month, day) in [("2026年春节前", 2026, 2, 11),
                                        ("2027年春节前", 2027, 1, 31),
                                        ("2026年端午节前", 2026, 6, 13),
                                        ("2026年中秋节前", 2026, 9, 19),
                                        ("2027年中秋节前", 2027, 9, 9),
                                        ("2027年除夕前", 2027, 1, 30)] {
            XCTAssertEqual(estimate(text), date(year, month, day), text)
        }
    }

    func testQixiIsNotMistakenForFebruaryValentinesDay() {
        XCTAssertEqual(estimate("2026年七夕情人节前"), date(2026, 8, 13))
    }

    func testPassedHolidayRollsButExplicitYearAndApproachingHolidayStayFixed() {
        XCTAssertEqual(estimate("春节前", anchor: date(2026, 10, 15)), date(2027, 1, 31))
        XCTAssertEqual(estimate("圣诞节前", anchor: date(2026, 12, 26)), date(2027, 12, 19))
        XCTAssertEqual(estimate("圣诞节前", anchor: date(2026, 12, 22)), date(2026, 12, 19),
                       "节日尚未到来，不能因为估算日已过就挪到次年")
        XCTAssertEqual(estimate("2026年圣诞节前", anchor: date(2028, 10, 15)), date(2026, 12, 19))
        XCTAssertEqual(estimate("今年春节前", anchor: date(2026, 10, 15)), date(2026, 2, 11))
        XCTAssertEqual(estimate("明年春节前", anchor: date(2026, 10, 15)), date(2027, 1, 31))
        XCTAssertEqual(estimate("去年圣诞节前", anchor: date(2026, 10, 15)), date(2025, 12, 19))
        XCTAssertEqual(estimate("前年圣诞节前", anchor: date(2026, 10, 15)), date(2024, 12, 19))
    }

    func testNewYearPinsFestivalYearRatherThanPreviousYearOfEstimate() throws {
        let text = CatalogBalanceDueEstimate.yearQualifiedText("元旦前", reference: date(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(text, "2027年元旦前")
        XCTAssertEqual(estimate(try XCTUnwrap(text)), date(2026, 12, 26))
        XCTAssertEqual(CatalogBalanceDueEstimate.yearQualifiedText("明年元旦前", reference: date(2026, 10, 15), calendar: calendar),
                       "2027年元旦前")
    }

    func testAuthoringReferenceKeepsHolidayEstimateStableAfterRestoreAndLateEntry() throws {
        let batch = CatalogReservationBatch(id: "early", name: "先行团", balanceDueKind: .approximate,
            balanceDueText: "圣诞节前", balanceDueReferenceAt: date(2026, 10, 15))
        let restored = try JSONDecoder().decode(CatalogReservationBatch.self, from: JSONEncoder().encode(batch))
        let expected = date(2026, 12, 19)
        XCTAssertEqual(restored.estimatedWindow(calendar: calendar)?.start, expected)
        XCTAssertEqual(restored.estimatedWindow(anchor: date(2028, 10, 15), calendar: calendar)?.start, expected)
        let series = CatalogSeries(id: "series", shopID: "shop", name: "系列", reservationBatches: [restored])
        let schedule = try XCTUnwrap(series.paymentSchedule(batchID: "early"))
        XCTAssertEqual(CatalogBalanceDueEstimate.declaredWindow(of: schedule, anchor: nil, calendar: calendar)?.start, expected)
        XCTAssertEqual(restored.balanceDueText, "圣诞节前", "目录保留原文")
        XCTAssertNil(schedule.balanceDueAt, "估算不冒充已公布的具体日期")
    }

    func testHolidayWindowReportsItsActualEstimationBasis() throws {
        let window = try XCTUnwrap(CatalogBalanceDueEstimate.declaredWindow(kind: .approximate,
            text: "圣诞节前", endText: "元旦前", at: nil, endAt: nil,
            anchor: date(2026, 10, 15), calendar: calendar))
        XCTAssertEqual(window.start, date(2026, 12, 19))
        XCTAssertEqual(window.end, date(2026, 12, 26))
        XCTAssertTrue(window.basis.contains("圣诞节前6天估算"))
        XCTAssertFalse(window.basis.contains("约一个月"))
    }

    func testLunarCivilDateIsStableAcrossUserTimeZones() {
        for zone in ["Asia/Shanghai", "Asia/Tokyo", "America/Los_Angeles"] {
            var calendar = self.calendar
            calendar.timeZone = TimeZone(identifier: zone)!
            XCTAssertEqual(CatalogBalanceDueEstimate.estimatedDate(text: "2027年春节前", anchor: nil, calendar: calendar),
                           date(2027, 1, 31, calendar: calendar), zone)
        }
    }

    func testMissingYearUnsupportedHolidayAndOtherDirectionsRemainUnresolved() {
        XCTAssertNil(estimate("圣诞节前"))
        for text in ["圣诞节后", "圣诞节前后", "圣诞节前一个月", "圣诞节前5天", "圣诞节", "节前", "发货前", "某某节前", "春节前或圣诞节前"] {
            XCTAssertNil(estimate(text, anchor: date(2026, 10, 15)), text)
        }
    }
}
