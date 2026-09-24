//
//  CatalogSeriesBalanceDueTests.swift
//  ItemManagerTests
//
//  2026-09-24 需求四「尾款时间」验收：
//    校验规则 / 存储方式（两种粒度分开存、切换即清另一种）/ 展示口径 /
//    到期判定（只有具体时间能驱动自动流转）/ 表单回填与组装 / 旧 JSON 兼容。
//

import XCTest
@testable import ItemManager

// MARK: - 纯逻辑：校验 / 归一 / 到期 / 展示

@MainActor
final class CatalogSeriesBalanceDueTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var reservationEnd: Date { now.addingTimeInterval(86_400) }   // 预约结束后一天

    // MARK: 校验规则

    /// 未填写 = 通过：非必填，且是「清除已填尾款时间」的合法表达
    func testNilKindPassesValidation() {
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: nil, text: "", exactAt: now, reservationEndAt: reservationEnd))
    }

    func testApproximateRequiresNonEmptyText() {
        XCTAssertNotNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .approximate, text: "   ", exactAt: now, reservationEndAt: nil))
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .approximate, text: "大货到后 1 个月", exactAt: now, reservationEndAt: nil))
    }

    func testApproximateRejectsTooLongText() {
        let tooLong = String(repeating: "长", count: CatalogSeriesBalanceDue.maxTextLength + 1)
        let atLimit = String(repeating: "长", count: CatalogSeriesBalanceDue.maxTextLength)
        XCTAssertNotNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .approximate, text: tooLong, exactAt: now, reservationEndAt: nil))
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .approximate, text: atLimit, exactAt: now, reservationEndAt: nil))
    }

    /// 具体时间必须**严格晚于**预约结束时间（业务上尾款不可能在预约结束前开始收）
    func testExactMustBeAfterReservationEnd() {
        XCTAssertNotNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", exactAt: reservationEnd, reservationEndAt: reservationEnd),
            "同一时刻也算「不晚于」，必须拦下")
        XCTAssertNotNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", exactAt: now, reservationEndAt: reservationEnd))
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", exactAt: reservationEnd.addingTimeInterval(60),
            reservationEndAt: reservationEnd))
    }

    /// 没有预约结束时间就没有比对基准 → 不拦（缺依据就不猜）
    func testExactWithoutBaselinePasses() {
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", exactAt: now, reservationEndAt: nil))
    }

    /// 具体时间已过**不拦**：那表示尾款已经开始收，读完即流转为「尾款中」
    func testExactInThePastIsNotBlocked() {
        XCTAssertNil(CatalogSeriesBalanceDue.validationErrorText(
            kind: .exact, text: "", exactAt: now.addingTimeInterval(-86_400),
            reservationEndAt: now.addingTimeInterval(-172_800)),
            "已过但不早于预约结束时间 → 通过（保存后生效阶段自然变成「尾款中」）")
    }

    // MARK: 存储方式（两种粒度分开存，切换即清另一种）

    func testStoredClearsTheOtherGranularity() {
        let approximate = CatalogSeriesBalanceDue.stored(kind: .approximate,
                                                        text: " 大货到后 1 个月 ", exactAt: now)
        XCTAssertEqual(approximate.kind, .approximate)
        XCTAssertEqual(approximate.text, "大货到后 1 个月")
        XCTAssertNil(approximate.at, "大致粒度下不允许残留具体时刻")

        let exact = CatalogSeriesBalanceDue.stored(kind: .exact, text: "大货到后 1 个月", exactAt: now)
        XCTAssertEqual(exact.kind, .exact)
        XCTAssertNil(exact.text, "具体粒度下不允许残留大致文本")
        XCTAssertEqual(exact.at, now)

        let cleared = CatalogSeriesBalanceDue.stored(kind: nil, text: "旧文本", exactAt: now)
        XCTAssertNil(cleared.kind)
        XCTAssertNil(cleared.text)
        XCTAssertNil(cleared.at)
    }

    func testStoredApproximateWithBlankTextKeepsKindButNilText() {
        let stored = CatalogSeriesBalanceDue.stored(kind: .approximate, text: "   ", exactAt: now)
        XCTAssertEqual(stored.kind, .approximate)
        XCTAssertNil(stored.text)
        XCTAssertNil(stored.at)
    }

    // MARK: 到期判定（自动流转的唯一依据）

    func testIsDueOnlyForExactAndInclusiveBoundary() {
        XCTAssertTrue(CatalogSeriesBalanceDue.isDue(kind: .exact, at: now, now: now),
                      "now == at 已算到点（含边界）")
        XCTAssertTrue(CatalogSeriesBalanceDue.isDue(kind: .exact,
                                                    at: now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(CatalogSeriesBalanceDue.isDue(kind: .exact,
                                                     at: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(CatalogSeriesBalanceDue.isDue(kind: .exact, at: nil, now: now))
        XCTAssertFalse(CatalogSeriesBalanceDue.isDue(kind: .approximate, at: now, now: now),
                       "大致时间没有确定时刻，恒不驱动流转")
        XCTAssertFalse(CatalogSeriesBalanceDue.isDue(kind: nil, at: now, now: now))
    }

    func testIsPresentCoversBothGranularities() {
        XCTAssertFalse(CatalogSeriesBalanceDue.isPresent(kind: nil, text: "x", at: now))
        XCTAssertTrue(CatalogSeriesBalanceDue.isPresent(kind: .approximate, text: "春节前", at: nil))
        XCTAssertFalse(CatalogSeriesBalanceDue.isPresent(kind: .approximate, text: "  ", at: nil))
        XCTAssertTrue(CatalogSeriesBalanceDue.isPresent(kind: .exact, text: nil, at: now))
        XCTAssertFalse(CatalogSeriesBalanceDue.isPresent(kind: .exact, text: nil, at: nil))
    }

    // MARK: 展示

    func testValueTextForBothGranularities() {
        let approximate = CatalogSeriesBalanceDue.valueText(
            kind: .approximate, text: "大货到后 1 个月", at: nil, locale: Locale(identifier: "zh_CN"))
        XCTAssertEqual(approximate, "大货到后 1 个月（大致）")

        let exact = CatalogSeriesBalanceDue.valueText(
            kind: .exact, text: nil, at: now, locale: Locale(identifier: "zh_CN"))
        XCTAssertNotNil(exact)
        XCTAssertTrue(exact?.contains("2027") == true, "具体时间要带年份：\(exact ?? "nil")")

        XCTAssertNil(CatalogSeriesBalanceDue.valueText(
            kind: nil, text: nil, at: now, locale: Locale(identifier: "zh_CN")))
        XCTAssertNil(CatalogSeriesBalanceDue.valueText(
            kind: .exact, text: nil, at: nil, locale: Locale(identifier: "zh_CN")))
    }

    // MARK: 旧数据兼容

    func testLegacySeriesJSONWithoutBalanceKeysDecodes() throws {
        let legacy = """
        { "id": "series-bd-legacy", "shopID": "shop-1", "name": "旧系列", "salePhase": "reservation_active" }
        """
        let series = try JSONDecoder().decode(CatalogSeries.self, from: Data(legacy.utf8))
        XCTAssertNil(series.balanceDueKind)
        XCTAssertNil(series.balanceDueText)
        XCTAssertNil(series.balanceDueAt)
        // 没有尾款时间 → 阶段流转只按既有规则（不会凭空出现「尾款中」）
        XCTAssertEqual(CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now),
                       .reservationActive)
    }
}

// MARK: - 共用表单：回填 / 组装 / 边界

@MainActor
final class ShopCatalogSeriesConfigFormTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSeries() -> CatalogSeries {
        var chart = CatalogPriceChart(id: "pricechart-form", seriesID: "series-form")
        chart.columns = ["款式", "预约价", "定金", "尾款"]
        chart.rows = [CatalogSizeRow(label: "大蝴蝶结背心裙", values: ["318", "91", "227"])]
        chart.sourceImages = ["local:a.jpg", "local:b.jpg"]
        return CatalogSeries(id: "series-form",
                             shopID: "shop-1",
                             name: "表单系列",
                             year: 2026,
                             month: 4,
                             season: "冬",
                             cover: "local:cover.jpg",
                             description: "系列简介",
                             priceChart: chart,
                             salePhase: .reservationActive,
                             reservationEndAt: now.addingTimeInterval(86_400),
                             balanceDueKind: .exact,
                             balanceDueAt: now.addingTimeInterval(172_800))
    }

    /// 回填 → 组装 必须是无损往返（多图价格表按行回填、再原样写回）
    func testFormRoundTripIsLossless() {
        let series = makeSeries()
        let form = ShopCatalogSeriesConfigForm(series: series)
        XCTAssertEqual(form.salePhase, .reservationActive)
        XCTAssertEqual(form.balanceDueKind, .exact)
        XCTAssertEqual(form.balanceDueAt, series.balanceDueAt)
        XCTAssertEqual(form.priceChartImageText, "local:a.jpg\nlocal:b.jpg")

        let updated = form.apply(to: series)
        XCTAssertEqual(updated.salePhase, series.salePhase)
        XCTAssertEqual(updated.reservationEndAt, series.reservationEndAt)
        XCTAssertEqual(updated.balanceDueKind, .exact)
        XCTAssertEqual(updated.balanceDueAt, series.balanceDueAt)
        XCTAssertEqual(updated.balanceDueText, nil)
        XCTAssertEqual(updated.cover, series.cover)
        XCTAssertEqual(updated.description, series.description)
        XCTAssertEqual(updated.priceChart?.sourceImages, ["local:a.jpg", "local:b.jpg"])
        XCTAssertEqual(updated.priceChart?.sourceImage, "local:a.jpg")
        XCTAssertEqual(updated.priceChart?.rows.first?.label, "大蝴蝶结背心裙")
    }

    /// `apply` **只写自己负责的字段**：名称 / 年月 / 季节 / 归档状态一律不动
    /// （否则批次详情页保存配置会把系列基础信息一起覆盖掉）
    func testApplyDoesNotTouchBasicInfo() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.salePhase = .balancePending
        form.balanceDueKind = .approximate
        form.balanceDueText = "大货到后 1 个月"

        let updated = form.apply(to: series)
        XCTAssertEqual(updated.id, series.id)
        XCTAssertEqual(updated.name, series.name)
        XCTAssertEqual(updated.year, series.year)
        XCTAssertEqual(updated.month, series.month)
        XCTAssertEqual(updated.season, series.season)
        XCTAssertEqual(updated.archivedAt, series.archivedAt)
        XCTAssertEqual(updated.shopID, series.shopID)
        // 尾款时间：切到「大致」→ 具体时刻被清掉，文本写入
        XCTAssertEqual(updated.balanceDueKind, .approximate)
        XCTAssertEqual(updated.balanceDueText, "大货到后 1 个月")
        XCTAssertNil(updated.balanceDueAt)
    }

    /// 选「未填写」= 清除已填尾款时间（显式可撤路径）
    func testSelectingNotFilledClearsBalanceDue() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.balanceDueKind = nil
        let updated = form.apply(to: series)
        XCTAssertNil(updated.balanceDueKind)
        XCTAssertNil(updated.balanceDueText)
        XCTAssertNil(updated.balanceDueAt)
    }

    /// 切到非「预约中」阶段不清除预约结束时间（那是事实，不是表单草稿）
    func testSwitchingAwayFromActiveKeepsReservationEnd() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.salePhase = .inStock
        let updated = form.apply(to: series)
        XCTAssertEqual(updated.reservationEndAt, series.reservationEndAt)
    }

    /// 封面 / 简介 空白 → nil（不是空串，避免详情页出现空区块）
    func testBlankCoverAndDescriptionBecomeNil() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.cover = "   "
        form.descriptionText = "\n"
        let updated = form.apply(to: series)
        XCTAssertNil(updated.cover)
        XCTAssertNil(updated.description)
    }

    /// 价格表三件套全空 → 清成 nil（可撤路径）
    func testEmptyPriceChartClearsChart() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.priceChartImageText = ""
        form.priceChartColumnsText = ""
        form.priceChartRowsText = ""
        form.priceChartUnitText = ""
        XCTAssertNil(form.apply(to: series).priceChart)
    }

    /// 表单校验与需求四口径同源：预约中时具体尾款时间必须晚于预约结束时间
    func testFormValidationUsesReservationEndAsBaselineWhenActive() {
        let series = makeSeries()
        var form = ShopCatalogSeriesConfigForm(series: series)
        form.balanceDueKind = .exact
        form.balanceDueAt = form.reservationEndAt.addingTimeInterval(-60)
        XCTAssertNotNil(form.balanceDueValidationErrorText())

        form.balanceDueAt = form.reservationEndAt.addingTimeInterval(60)
        XCTAssertNil(form.balanceDueValidationErrorText())

        // 非「预约中」阶段没有可比对的基准 → 不拦
        form.salePhase = .balancePending
        form.balanceDueAt = form.reservationEndAt.addingTimeInterval(-60)
        XCTAssertNil(form.balanceDueValidationErrorText())
    }
}

// MARK: - 落盘 + 阶段生效（真写覆盖层）

@MainActor
final class CatalogSeriesBalanceDuePersistenceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        ShopCatalogStore.shared.reloadWithOverlay()
        super.tearDown()
    }

    /// 尾款时间落盘 → 读到的是同一份；且到点后生效阶段为「尾款中」
    func testBalanceDuePersistsAndDrivesBalancePhase() throws {
        var series = CatalogSeries(id: "series-bd-persist",
                                   shopID: "shop-bd",
                                   name: "尾款时间系列",
                                   salePhase: .reservationActive,
                                   reservationEndAt: now.addingTimeInterval(-3600))
        let form = ShopCatalogSeriesConfigForm(series: series)
        var edited = form
        edited.balanceDueKind = .exact
        edited.balanceDueAt = now.addingTimeInterval(-60)
        series = edited.apply(to: series)
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)

        // 读盘核对（绕过内存缓存，确认三个字段真的落进 JSON）
        let data = try Data(contentsOf: ShopCatalogStorage.directory
            .appendingPathComponent("shop-catalog-override.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let list = (json?["series"] as? [[String: Any]]) ?? []
        let persisted = try XCTUnwrap(list.first { ($0["id"] as? String) == series.id })
        XCTAssertEqual(persisted["balanceDueKind"] as? String, "exact")
        XCTAssertNotNil(persisted["balanceDueAt"])

        ShopCatalogStore.shared.reloadWithOverlay()
        let reloaded = try XCTUnwrap(ShopCatalogStore.shared.series(id: series.id))
        XCTAssertEqual(reloaded.balanceDueKind, .exact)
        // 预约结束时间已过 + 具体尾款时间已到 → 生效阶段「尾款中」
        XCTAssertEqual(CatalogSeriesSalePhaseResolver.effectivePhase(of: reloaded, now: now),
                       .balancePending)
    }
}
