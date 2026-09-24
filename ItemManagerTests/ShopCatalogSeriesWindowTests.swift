//
//  ShopCatalogSeriesWindowTests.swift
//  ItemManagerTests
//
//  2026-09-24 需求五验收：
//    ① 「其他系列都带有月份，为什么只有它不带月份」的**根源修复** ——
//       批次 / 草稿链路原先只承载 `newSeriesYear`，凡经「批量录入 → 批次归属 → 发布」
//       诞生的系列 `month` 恒为 nil。本套件钉住新通道、存量补全与指纹兼容；
//    ② 「『预约中』和『尾款中』都要同时包含开始时间和结束时间」——
//       预约期与尾款期两个区间口径的校验 / 存储 / 回填 / 展示。
//
//  ⚠️ `ShopCatalogDraftStore.shared.drafts / batches` 是跨套件累积的发布单例，
//  断言一律按 batchID / 名称收窄，或断言「前后快照相等」（2026-09-21 事故防线）。
//

import XCTest
@testable import ItemManager

// MARK: - ① 预约期（开始 + 结束）

@MainActor
final class CatalogSeriesReservationWindowTests: XCTestCase {

    /// 固定基准时间，避免用「现在」当输入（否则断言会随运行时刻漂移）
    private let start = Date(timeIntervalSince1970: 1_772_000_000)
    private var end: Date { start.addingTimeInterval(30 * 86_400) }

    private func short(_ date: Date) -> String { CatalogSeriesBalanceDue.shortDateText(date) }

    // MARK: 展示

    func testWindowTextShowsBothEnds() {
        XCTAssertEqual(CatalogSeriesReservationWindow.windowText(start: start, end: end),
                       "\(short(start)) — \(short(end))")
    }

    func testWindowTextWithEndOnlyDoesNotInventStart() {
        // 存量数据形态：只有结束时间（原先唯一的字段）→ 不许补一个假的开始
        XCTAssertEqual(CatalogSeriesReservationWindow.windowText(start: nil, end: end), short(end))
    }

    func testWindowTextWithStartOnly() {
        XCTAssertEqual(CatalogSeriesReservationWindow.windowText(start: start, end: nil), short(start))
    }

    func testWindowTextWithNothingIsNil() {
        XCTAssertNil(CatalogSeriesReservationWindow.windowText(start: nil, end: nil))
    }

    func testDisplayTextCarriesPrefix() {
        var series = CatalogSeries(id: "s-window", shopID: "shop-1", name: "区间测试系列")
        series.reservationStartAt = start
        series.reservationEndAt = end
        XCTAssertEqual(CatalogSeriesReservationWindow.displayText(of: series),
                       "预约期：" + "\(short(start)) — \(short(end))")
        // 未填 → 不渲染任何行
        series.reservationStartAt = nil
        series.reservationEndAt = nil
        XCTAssertNil(CatalogSeriesReservationWindow.displayText(of: series))
    }

    // MARK: 校验

    func testValidationRejectsStartAfterEnd() {
        let error = CatalogSeriesReservationWindow.validationErrorText(
            start: end.addingTimeInterval(60), end: end)
        XCTAssertNotNil(error, "开始晚于结束必须拦下")
        XCTAssertTrue((error ?? "").contains(short(end)), "错误文案要带上结束时间：\(error ?? "")")
    }

    func testValidationAllowsOrderedWindowAndEqualInstant() {
        XCTAssertNil(CatalogSeriesReservationWindow.validationErrorText(start: start, end: end))
        // 同一天 00:00 开、00:00 结是运营的真实写法，不拦
        XCTAssertNil(CatalogSeriesReservationWindow.validationErrorText(start: end, end: end))
    }

    func testValidationWithoutStartIsFine() {
        XCTAssertNil(CatalogSeriesReservationWindow.validationErrorText(start: nil, end: end),
                     "开始时间选填：存量系列打开表单直接保存不能被拦")
        XCTAssertNil(CatalogSeriesReservationWindow.validationErrorText(start: nil, end: nil))
    }

    // MARK: 区间判定（只用于提示）

    func testHasStartedWithoutStartIsTrue() {
        let now = Date()
        XCTAssertTrue(CatalogSeriesReservationWindow.hasStarted(start: nil, now: now),
                      "缺依据不猜：不能凭空说「预约还没开始」")
        XCTAssertFalse(CatalogSeriesReservationWindow.hasStarted(start: now.addingTimeInterval(3600),
                                                                 now: now))
        XCTAssertTrue(CatalogSeriesReservationWindow.hasStarted(start: now.addingTimeInterval(-3600),
                                                                now: now))
    }

    func testIsOpenWithoutEndIsTrue() {
        let now = Date()
        XCTAssertTrue(CatalogSeriesReservationWindow.isOpen(end: nil, now: now))
        XCTAssertTrue(CatalogSeriesReservationWindow.isOpen(end: now.addingTimeInterval(3600), now: now))
        XCTAssertFalse(CatalogSeriesReservationWindow.isOpen(end: now.addingTimeInterval(-3600), now: now))
    }
}

// MARK: - ② 尾款期（开始 + 结束）

@MainActor
final class CatalogSeriesBalanceWindowTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_772_000_000)
    private var end: Date { start.addingTimeInterval(14 * 86_400) }
    private let locale = Locale(identifier: "zh_CN")

    // MARK: 存储归一

    func testApproximateKeepsBothTextsAndClearsDates() {
        let stored = CatalogSeriesBalanceDue.stored(kind: .approximate,
                                                    text: "  大货到后 1 个月  ",
                                                    endText: " 大货到后 2 个月 ",
                                                    exactAt: start,
                                                    endAt: end,
                                                    endDeclared: true)
        XCTAssertEqual(stored.kind, .approximate)
        XCTAssertEqual(stored.text, "大货到后 1 个月")
        XCTAssertEqual(stored.endText, "大货到后 2 个月")
        XCTAssertNil(stored.at, "大致粒度不写日期")
        XCTAssertNil(stored.endAt)
    }

    func testApproximateKeepsMissingEndTextAsNil() {
        let stored = CatalogSeriesBalanceDue.stored(kind: .approximate,
                                                    text: "春节前",
                                                    endText: "   ",
                                                    exactAt: start,
                                                    endAt: end,
                                                    endDeclared: true)
        XCTAssertEqual(stored.text, "春节前")
        XCTAssertNil(stored.endText, "空白的结束描述 = 未声明，不写空串")
    }

    func testExactStoresEndOnlyWhenDeclared() {
        let withEnd = CatalogSeriesBalanceDue.stored(kind: .exact, text: "", endText: "",
                                                     exactAt: start, endAt: end, endDeclared: true)
        XCTAssertEqual(withEnd.at, start)
        XCTAssertEqual(withEnd.endAt, end)
        XCTAssertNil(withEnd.text)
        XCTAssertNil(withEnd.endText)

        let withoutEnd = CatalogSeriesBalanceDue.stored(kind: .exact, text: "", endText: "",
                                                        exactAt: start, endAt: end, endDeclared: false)
        XCTAssertEqual(withoutEnd.at, start)
        XCTAssertNil(withoutEnd.endAt, "开关关闭 = 明确不声明结束时间")
    }

    func testNoneClearsAllFiveFields() {
        let stored = CatalogSeriesBalanceDue.stored(kind: nil, text: "春节前", endText: "元宵前",
                                                    exactAt: start, endAt: end, endDeclared: true)
        XCTAssertNil(stored.kind)
        XCTAssertNil(stored.text)
        XCTAssertNil(stored.endText)
        XCTAssertNil(stored.at)
        XCTAssertNil(stored.endAt)
    }

    // MARK: 回填

    func testFormValuesRoundTripKeepsHasEnd() {
        let filled = CatalogSeriesBalanceDue.formValues(kind: .exact, text: nil, endText: nil,
                                                        at: start, endAt: end,
                                                        fallbackExactAt: start)
        XCTAssertEqual(filled.exactAt, start)
        XCTAssertEqual(filled.endAt, end)
        XCTAssertTrue(filled.hasEnd, "有结束时间 → 开关打开")

        let empty = CatalogSeriesBalanceDue.formValues(kind: .exact, text: nil, endText: nil,
                                                       at: start, endAt: nil,
                                                       fallbackExactAt: start)
        XCTAssertFalse(empty.hasEnd, "没有结束时间 → 开关关闭，且不伪造一个日期")
        XCTAssertEqual(empty.endAt, start, "关闭态也要给 DatePicker 一个可编辑起点")
    }

    // MARK: 校验

    func testValidationRejectsEndBeforeStart() {
        let error = CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", endText: "",
            exactAt: start, endAt: start.addingTimeInterval(-60), endDeclared: true,
            reservationEndAt: nil)
        XCTAssertNotNil(error)
        XCTAssertTrue((error ?? "").contains("不能早于"), "实际文案：\(error ?? "")")
    }

    func testValidationAllowsEndEqualToStartAndUnset() {
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", endText: "",
            exactAt: start, endAt: start, endDeclared: true, reservationEndAt: nil))
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", endText: "",
            exactAt: start, endAt: start.addingTimeInterval(-60), endDeclared: false,
            reservationEndAt: nil),
            "没声明结束时间时不该拿它报错")
    }

    func testValidationStillRejectsStartNotAfterReservationEnd() {
        let error = CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", endText: "",
            exactAt: start, endAt: end, endDeclared: true,
            reservationEndAt: start.addingTimeInterval(3600))
        XCTAssertNotNil(error, "既有口径不变：尾款开始必须晚于预约结束")
    }

    func testValidationLimitsEndTextLengthForApproximate() {
        let tooLong = String(repeating: "长", count: CatalogSeriesBalanceDue.maxTextLength + 1)
        let error = CatalogSeriesBalanceDue.validationErrorText(
            kind: .approximate, text: "春节前", endText: tooLong,
            exactAt: start, endAt: end, endDeclared: true, reservationEndAt: nil)
        XCTAssertNotNil(error)
        XCTAssertTrue((error ?? "").contains("尾款结束"), "实际文案：\(error ?? "")")
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .approximate, text: "春节前", endText: "",
            exactAt: start, endAt: end, endDeclared: true, reservationEndAt: nil))
    }

    // MARK: 流转口径（结束时间不驱动任何阶段变化）

    func testEndTimeNeverDrivesFlow() {
        let past = Date(timeIntervalSinceNow: -86_400)
        XCTAssertTrue(CatalogSeriesBalanceDue.isEnded(kind: .exact, at: past, now: Date()),
                      "过了结束时间 → 提示用 true")
        XCTAssertFalse(CatalogSeriesBalanceDue.isDue(kind: .exact, at: nil, now: Date()),
                       "开始时间未声明时永远不到期（结束时间不能顶替开始时间）")
        XCTAssertFalse(CatalogSeriesBalanceDue.isEnded(kind: .approximate, at: past, now: Date()),
                       "大致粒度不是时间点，不参与判定")
    }

    // MARK: 展示

    func testValueTextRendersRangeForExact() {
        let text = CatalogSeriesBalanceDue.valueText(
            kind: .exact, text: nil, endText: nil, at: start, endAt: end, locale: locale) ?? ""
        XCTAssertTrue(text.contains("—"), "区间要有分隔符：\(text)")
        let single = CatalogSeriesBalanceDue.valueText(
            kind: .exact, text: nil, endText: nil, at: start, endAt: nil, locale: locale) ?? ""
        XCTAssertFalse(single.contains("—"), "没声明结束就不该出现分隔符：\(single)")
    }

    func testValueTextRendersRangeForApproximate() {
        XCTAssertEqual(CatalogSeriesBalanceDue.valueText(kind: .approximate,
                                                         text: "大货到后 1 个月",
                                                         endText: "大货到后 2 个月",
                                                         at: start, endAt: end,
                                                         locale: locale),
                       "大货到后 1 个月 — 大货到后 2 个月（大致）")
        XCTAssertEqual(CatalogSeriesBalanceDue.valueText(kind: .approximate,
                                                         text: "大货到后 1 个月",
                                                         endText: nil,
                                                         at: start, endAt: end,
                                                         locale: locale),
                       "大货到后 1 个月（大致）")
    }

    func testDisplayTextPrefixFollowsDeclaredEnd() {
        var series = CatalogSeries(id: "s-due", shopID: "shop-1", name: "尾款测试系列")
        series.balanceDueKind = .exact
        series.balanceDueAt = start
        XCTAssertEqual(CatalogSeriesBalanceDue.displayText(of: series)?.hasPrefix("尾款时间："), true)
        series.balanceDueEndAt = end
        XCTAssertEqual(CatalogSeriesBalanceDue.displayText(of: series)?.hasPrefix("尾款期："), true)
    }

    // MARK: 旧 JSON 零迁移

    func testOldJSONWithoutWindowFieldsDecodesAsNil() throws {
        var series = CatalogSeries(id: "s-old", shopID: "shop-1", name: "旧数据系列")
        series.balanceDueKind = .exact
        series.balanceDueAt = start
        let data = try ShopCatalogJSONCoding.encoder().encode(series)

        // 模拟旧覆盖层：真实编码后删掉本次新增的三个键
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "reservationStartAt")
        object.removeValue(forKey: "balanceDueEndAt")
        object.removeValue(forKey: "balanceDueEndText")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ShopCatalogJSONCoding.decoder().decode(CatalogSeries.self, from: legacy)
        XCTAssertNil(decoded.reservationStartAt)
        XCTAssertNil(decoded.balanceDueEndAt)
        XCTAssertNil(decoded.balanceDueEndText)
        XCTAssertEqual(decoded.balanceDueAt, start, "既有尾款时间字段不受影响")
    }
}

// MARK: - ③ 配置表单：两个区间的回填与落库

@MainActor
final class ShopCatalogSeriesConfigWindowFormTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_772_000_000)
    private var start: Date { now.addingTimeInterval(-10 * 86_400) }
    private var reservationEnd: Date { now.addingTimeInterval(20 * 86_400) }
    private var balanceStart: Date { now.addingTimeInterval(30 * 86_400) }
    private var balanceEnd: Date { now.addingTimeInterval(45 * 86_400) }

    private func makeSeries() -> CatalogSeries {
        var series = CatalogSeries(id: "s-form", shopID: "shop-1", name: "表单区间系列")
        series.salePhase = .reservationActive
        series.reservationStartAt = start
        series.reservationEndAt = reservationEnd
        series.balanceDueKind = .exact
        series.balanceDueAt = balanceStart
        series.balanceDueEndAt = balanceEnd
        return series
    }

    func testFormBackfillsBothWindows() {
        let form = ShopCatalogSeriesConfigForm(series: makeSeries(), now: now)
        XCTAssertTrue(form.reservationHasStart)
        XCTAssertEqual(form.reservationStartAt, start)
        XCTAssertEqual(form.reservationEndAt, reservationEnd)
        XCTAssertEqual(form.balanceDueKind, .exact)
        XCTAssertEqual(form.balanceDueAt, balanceStart)
        XCTAssertTrue(form.balanceDueHasEnd)
        XCTAssertEqual(form.balanceDueEndAt, balanceEnd)
        XCTAssertNil(form.reservationValidationErrorText())
        XCTAssertNil(form.balanceDueValidationErrorText())
    }

    func testFormDefaultsMissingStartToClosedSwitch() {
        var series = makeSeries()
        series.reservationStartAt = nil
        series.balanceDueEndAt = nil
        let form = ShopCatalogSeriesConfigForm(series: series, now: now)
        XCTAssertFalse(form.reservationHasStart, "存量系列没有开始时间 → 开关关闭")
        XCTAssertFalse(form.balanceDueHasEnd)
    }

    func testApplyWritesBothWindows() {
        var series = makeSeries()
        series.reservationStartAt = nil
        series.balanceDueEndAt = nil
        var form = ShopCatalogSeriesConfigForm(series: series, now: now)
        form.reservationHasStart = true
        form.reservationStartAt = start
        form.balanceDueHasEnd = true
        form.balanceDueEndAt = balanceEnd

        let updated = form.apply(to: series)
        XCTAssertEqual(updated.reservationStartAt, start)
        XCTAssertEqual(updated.reservationEndAt, reservationEnd)
        XCTAssertEqual(updated.balanceDueEndAt, balanceEnd)
        XCTAssertEqual(updated.balanceDueKind, .exact)
    }

    func testApplyWithSwitchOffClearsStartExplicitly() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series, now: now)
        form.reservationHasStart = false
        let updated = form.apply(to: series)
        XCTAssertNil(updated.reservationStartAt, "开关关掉 = 明确撤销开始时间（唯一一条显式清除路径）")
        XCTAssertEqual(updated.reservationEndAt, reservationEnd, "结束时间是自动流转依据，不受开关影响")
    }

    func testApplyKeepsDatesOutOfApproximateGranularity() {
        var series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series, now: now)
        form.balanceDueKind = .approximate
        form.balanceDueText = "大货到后 1 个月"
        form.balanceDueEndText = "大货到后 2 个月"
        let updated = form.apply(to: series)
        XCTAssertEqual(updated.balanceDueText, "大货到后 1 个月")
        XCTAssertEqual(updated.balanceDueEndText, "大货到后 2 个月")
        XCTAssertNil(updated.balanceDueAt, "切到大致粒度必须清掉具体日期，避免两份真值")
        XCTAssertNil(updated.balanceDueEndAt)
        series = updated

        // 再切回具体：文本清空、日期回来（表单里 DatePicker 仍有值）
        var back = ShopCatalogSeriesConfigForm(series: series, now: now)
        back.balanceDueKind = .exact
        back.balanceDueHasEnd = true
        back.balanceDueAt = balanceStart
        back.balanceDueEndAt = balanceEnd
        let final = back.apply(to: series)
        XCTAssertNil(final.balanceDueText)
        XCTAssertNil(final.balanceDueEndText)
        XCTAssertEqual(final.balanceDueAt, balanceStart)
        XCTAssertEqual(final.balanceDueEndAt, balanceEnd)
    }

    func testReservationValidationOnlyAppliesWhileReservationActive() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series, now: now)
        form.reservationStartAt = reservationEnd.addingTimeInterval(86_400)   // 开始晚于结束
        XCTAssertNotNil(form.reservationValidationErrorText())

        form.salePhase = .inStock
        XCTAssertNil(form.reservationValidationErrorText(),
                     "非预约中阶段不显示预约期字段，也就不做这项校验")
        // 其余阶段保存也不该写预约期（事实保留，表单只是隐藏）
        let updated = form.apply(to: series)
        XCTAssertEqual(updated.reservationEndAt, series.reservationEndAt)
    }
}
