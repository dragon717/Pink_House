//
//  ShopCatalogSeriesSalePhaseTests.swift
//  ItemManagerTests
//
//  需求二「系列发售阶段 + 预约时间管理」验收（2026-09-23）：
//    §二.1 发售阶段字段：预约中 / 预约已结束 / 现货（未设置 = 沿用销售记录）
//    §二.2 「预约中」必须给出预约结束时间；其它阶段不显示该输入框
//    §二.3 当前时间超过预约结束时间 → 自动流转为「预约已结束」
//    §二.4 **数据保留（最重要）**：预约结束后预约价 / 定金 / 尾款 / 现货价
//          必须完全保留，不清空不隐藏；且「定金 + 尾款」记账能力**不被剥夺**
//          （2026-09-23 用户拍板：结束只改变默认 UI 引导，主推全款）
//

import XCTest
import SwiftData
@testable import ItemManager

// MARK: - §二.3 自动流转（纯逻辑）

@MainActor
final class CatalogSeriesSalePhaseResolverTests: XCTestCase {

    /// 固定「当前时间」，避免用例跨秒抖动
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var oneHourAgo: Date { now.addingTimeInterval(-3600) }
    private var oneHourLater: Date { now.addingTimeInterval(3600) }

    private func phase(_ declared: CatalogSeriesSalePhase?,
                       end: Date?) -> CatalogSeriesSalePhase? {
        CatalogSeriesSalePhaseResolver.effectivePhase(
            declared: declared, reservationEndAt: end, now: now)
    }

    /// 带尾款时间的生效阶段（2026-09-24 需求三/四）
    private func phase(_ declared: CatalogSeriesSalePhase?,
                       end: Date?,
                       balanceKind: CatalogBalanceDueKind?,
                       balanceAt: Date?) -> CatalogSeriesSalePhase? {
        CatalogSeriesSalePhaseResolver.effectivePhase(
            declared: declared,
            reservationEndAt: end,
            balanceDueKind: balanceKind,
            balanceDueAt: balanceAt,
            now: now)
    }

    /// 未声明（旧数据）→ nil：**不替运营猜**，调用方回退档期推导
    func testUndeclaredPhaseStaysNil() {
        XCTAssertNil(phase(nil, end: nil))
        XCTAssertNil(phase(nil, end: oneHourAgo))
        XCTAssertNil(phase(nil, end: oneHourLater))
    }

    func testActiveBeforeEndStaysActive() {
        XCTAssertEqual(phase(.reservationActive, end: oneHourLater), .reservationActive)
    }

    /// §二.3 的核心：过了结束时间自动变成「预约已结束」
    func testActiveAfterEndAutoFlowsToEnded() {
        XCTAssertEqual(phase(.reservationActive, end: oneHourAgo), .reservationEnded)
    }

    /// 边界：`now == end` 仍算预约中（只有**严格超过**才流转，避免同秒抖动）
    func testBoundaryIsStrictlyAfterEnd() {
        XCTAssertEqual(phase(.reservationActive, end: now), .reservationActive)
    }

    /// 填了「预约中」却没给结束时间 → 保持预约中（缺依据就不猜）
    func testActiveWithoutEndTimeStaysActive() {
        XCTAssertEqual(phase(.reservationActive, end: nil), .reservationActive)
    }

    /// 已声明「预约已结束 / 现货」时，预约结束时间不再影响结果
    func testEndedAndInStockIgnoreReservationEndAt() {
        XCTAssertEqual(phase(.reservationEnded, end: oneHourLater), .reservationEnded)
        XCTAssertEqual(phase(.reservationEnded, end: oneHourAgo), .reservationEnded)
        XCTAssertEqual(phase(.inStock, end: oneHourLater), .inStock)
        XCTAssertEqual(phase(.inStock, end: oneHourAgo), .inStock)
    }

    func testHasAutoFlowedOnlyWhenPastActiveReservation() {
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .reservationActive, reservationEndAt: oneHourAgo, now: now))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .reservationActive, reservationEndAt: oneHourLater, now: now))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .reservationEnded, reservationEndAt: oneHourAgo, now: now))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .reservationActive, reservationEndAt: nil, now: now))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: nil, reservationEndAt: oneHourAgo, now: now))
    }

    // MARK: §二 业务背景：加购引导（不是能力门禁）

    func testFullPaymentIsPreferredOnlyAfterReservationEnds() {
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.prefersFullPayment(.reservationEnded))
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.prefersFullPayment(.inStock))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.prefersFullPayment(.reservationActive))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.prefersFullPayment(nil))
    }

    func testRequiresReservationEndAtOnlyWhenActive() {
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.requiresReservationEndAt(.reservationActive))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.requiresReservationEndAt(.reservationEnded))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.requiresReservationEndAt(.inStock))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.requiresReservationEndAt(nil))
    }

    /// §二.1 选项与显示名（需求原文：预约中 / 预约已结束 / 现货）
    /// + 2026-09-24 需求三新增「尾款中」
    func testPhaseOptionsAndDisplayNames() {
        XCTAssertEqual(CatalogSeriesSalePhase.allCases.count, 4)
        XCTAssertEqual(CatalogSeriesSalePhase.reservationActive.displayName, "预约中")
        XCTAssertEqual(CatalogSeriesSalePhase.reservationEnded.displayName, "预约已结束")
        XCTAssertEqual(CatalogSeriesSalePhase.balancePending.displayName, "尾款中")
        XCTAssertEqual(CatalogSeriesSalePhase.inStock.displayName, "现货")
    }

    // MARK: 需求三「尾款中」的触发条件与流转（2026-09-24）

    /// 触发条件一：预约中 + 已过预约结束时间 + **具体**尾款时间已到 → 尾款中
    func testActivePastEndWithDueBalanceFlowsToBalancePending() {
        XCTAssertEqual(phase(.reservationActive, end: oneHourAgo,
                             balanceKind: .exact, balanceAt: oneHourAgo),
                       .balancePending)
    }

    /// 已过预约结束时间、但具体尾款时间还没到 → 停在「预约已结束」（等尾款）
    func testActivePastEndWithFutureBalanceStaysEnded() {
        XCTAssertEqual(phase(.reservationActive, end: oneHourAgo,
                             balanceKind: .exact, balanceAt: oneHourLater),
                       .reservationEnded)
    }

    /// 大致时间**不参与**自动流转（不是确定时刻，不拿它猜）
    func testApproximateBalanceNeverDrivesAutoFlow() {
        XCTAssertEqual(phase(.reservationActive, end: oneHourAgo,
                             balanceKind: .approximate, balanceAt: oneHourAgo),
                       .reservationEnded)
        XCTAssertEqual(phase(.reservationEnded, end: oneHourAgo,
                             balanceKind: .approximate, balanceAt: oneHourAgo),
                       .reservationEnded)
    }

    /// 触发条件二：声明「预约已结束」+ 具体尾款时间已到 → 尾款中
    /// （「预约中填过尾款时间、后来手动改成预约已结束」的系列也能按时进尾款中）
    func testEndedWithDueBalanceFlowsToBalancePending() {
        XCTAssertEqual(phase(.reservationEnded, end: nil,
                             balanceKind: .exact, balanceAt: oneHourAgo),
                       .balancePending)
        XCTAssertEqual(phase(.reservationEnded, end: nil,
                             balanceKind: .exact, balanceAt: oneHourLater),
                       .reservationEnded)
    }

    /// 边界：`now == balanceAt` 已算到尾款时间（收尾款从该时刻开始）
    func testBalanceBoundaryIsInclusive() {
        XCTAssertEqual(phase(.reservationEnded, end: nil,
                             balanceKind: .exact, balanceAt: now),
                       .balancePending)
    }

    /// 运营**显式声明**「尾款中 / 现货」时，时间不改写它（声明最优先）
    func testDeclaredPhasesAreNeverRewrittenByTime() {
        XCTAssertEqual(phase(.balancePending, end: oneHourAgo,
                             balanceKind: .exact, balanceAt: oneHourLater),
                       .balancePending)
        XCTAssertEqual(phase(.balancePending, end: oneHourLater,
                             balanceKind: .exact, balanceAt: oneHourLater),
                       .balancePending)
        XCTAssertEqual(phase(.inStock, end: oneHourAgo,
                             balanceKind: .exact, balanceAt: oneHourAgo),
                       .inStock)
    }

    /// 未声明 + 有尾款时间 → 仍然 nil（不替运营决定）
    func testUndeclaredStaysNilEvenWithBalanceTime() {
        XCTAssertNil(phase(nil, end: oneHourAgo,
                           balanceKind: .exact, balanceAt: oneHourAgo))
    }

    /// 尾款中的加购引导与「预约中」同族（补尾款 = 定金 + 尾款），不是主推全款
    func testBalancePendingPrefersDepositPlusBalanceGuidance() {
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.prefersFullPayment(.balancePending))
    }

    /// 尾款时间输入项的显示条件（需求四）：预约中必显；尾款中可修正；其余不显示
    func testBalanceInputVisibility() {
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.showsBalanceDueInput(.reservationActive))
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.showsBalanceDueInput(.balancePending))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.showsBalanceDueInput(.reservationEnded))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.showsBalanceDueInput(.inStock))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.showsBalanceDueInput(nil))
    }

    /// 「尾款中」的出口只能由运营声明（数据里没有「尾款是否收齐」的可判定依据）
    func testBalancePhaseExitsByDeclarationOnly() {
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.balancePhaseExitsByDeclarationOnly(.balancePending))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.balancePhaseExitsByDeclarationOnly(.inStock))
    }

    /// 自动流转提示：声明「预约中」但生效阶段已不是预约中（含流转到「尾款中」）
    func testHasAutoFlowedCoversBalancePending() {
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .reservationActive, reservationEndAt: oneHourAgo,
            balanceDueKind: .exact, balanceDueAt: oneHourAgo, now: now))
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .reservationEnded, reservationEndAt: oneHourAgo,
            balanceDueKind: .exact, balanceDueAt: oneHourAgo, now: now))
        XCTAssertFalse(CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: .balancePending, reservationEndAt: oneHourAgo,
            balanceDueKind: .exact, balanceDueAt: oneHourAgo, now: now),
            "已经是尾款中，就不算「自动流转」提示的对象")
    }

    // MARK: 旧数据兼容（两个新字段必须 Optional）

    /// 旧覆盖层 / 种子 JSON 里没有 `salePhase` / `reservationEndAt` 两个键。
    /// 合成 `Decodable` 对**非 Optional** 字段会直接抛错——那会让整个系列列表打不开。
    func testLegacySeriesJSONWithoutNewKeysDecodes() throws {
        let legacy = """
        { "id": "series-legacy", "shopID": "shop-1", "name": "旧数据系列", "year": 2025 }
        """
        let series = try JSONDecoder().decode(CatalogSeries.self, from: Data(legacy.utf8))
        XCTAssertEqual(series.name, "旧数据系列")
        XCTAssertNil(series.salePhase, "缺键必须解成 nil，而不是抛错")
        XCTAssertNil(series.reservationEndAt)
        XCTAssertNil(series.priceChart)
        // 未声明 → 生效阶段为 nil → 前端回退档期推导，行为与改动前一致
        XCTAssertNil(CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now))
    }
}

// MARK: - §二.4 数据保留 + 覆盖层持久化（真落盘）

/// 需求 §二.4 原文：「即使预约结束，该系列下的价格数据（预约价、定金、尾款、现货价）
/// 必须完全保留，不能清空、不能隐藏。用户在前端仍然可以看到『原预约价是 ¥318』，
/// 只是不能用预约价去进行『定金 + 尾款』的分期操作了。」
///
/// ⚠️ 2026-09-23 用户拍板补充：**只改引导、不剥夺能力**——
/// 「不能用预约价分期」落成「默认主推全款」，「定金 + 尾款」仍必须能记。
@MainActor
final class ShopCatalogSeriesSalePhaseStoreTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        // 测试隔离（2026-09-21 事故）：先重定向到临时目录，绝不碰用户真实沙盒
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

    /// 一个「预约价 318 = 定金 91 + 尾款 227、现货价 428」的系列 + 单品
    private func makeStore(seriesPhase: CatalogSeriesSalePhase?,
                           reservationEndAt: Date?) -> ShopCatalogStore {
        let series = CatalogSeries(id: "series-phase-test",
                                   shopID: "shop-phase-test",
                                   name: "预约阶段测试系列",
                                   salePhase: seriesPhase,
                                   reservationEndAt: reservationEndAt)
        let product = CatalogProduct(id: "prod-phase-test",
                                     shopID: "shop-phase-test",
                                     seriesID: "series-phase-test",
                                     name: "预约测试 JSK",
                                     category: "JSK",
                                     designName: "预约测试 JSK")
        return ShopCatalogStore(catalog: ShopCatalog(
            series: [series],
            products: [product],
            saleEvents: [
                CatalogSaleEvent(id: "ev-phase-resv", productID: "prod-phase-test",
                                 type: .reservation, price: 318, deposit: 91, balance: 227),
                CatalogSaleEvent(id: "ev-phase-stock", productID: "prod-phase-test",
                                 type: .stock, price: 428),
            ]
        ))
    }

    /// §二.4 核心断言：**自动流转**到「预约已结束」之后，四类价格一个都不能少
    func testAutoFlowToEndedKeepsAllPriceData() throws {
        let store = makeStore(seriesPhase: .reservationActive,
                              reservationEndAt: now.addingTimeInterval(-3600))
        let series = try XCTUnwrap(store.series(id: "series-phase-test"))

        // 声明是「预约中」，但时间已过 → 生效阶段是「预约已结束」
        XCTAssertEqual(CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now),
                       .reservationEnded)
        // 声明值本身**没有被改写**：没有任何后台任务偷偷回写存储
        XCTAssertEqual(series.salePhase, .reservationActive)
        XCTAssertNotNil(series.reservationEndAt)

        // 预约价 / 定金 / 尾款 / 现货价原样保留（不清空、不隐藏）
        let archive = store.priceArchive(forProduct: "prod-phase-test")
        XCTAssertEqual(archive.currentReservationPrice, 318, "原预约价必须仍然看得到")
        XCTAssertEqual(archive.currentDeposit, 91)
        XCTAssertEqual(archive.currentBalance, 227)
        XCTAssertEqual(archive.currentStockPrice, 428)
    }

    /// 用户拍板口径：预约已结束**不剥夺**记账能力——两种口径都必须还能出草稿
    func testEndedReservationStillAllowsBothEntryModes() throws {
        let store = makeStore(seriesPhase: .reservationEnded, reservationEndAt: nil)
        // 引导：主推全款
        XCTAssertTrue(CatalogSeriesSalePhaseResolver.prefersFullPayment(.reservationEnded))

        let context = modelContext()
        let depositDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-phase-test", priceMode: .reservation(depositPaid: 91)),
            store: store, modelContext: context))
        XCTAssertEqual(Decimal(depositDraft.balance), 227, "定金 + 尾款必须仍然可记")

        let fullDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-phase-test", priceMode: .fullReservation),
            store: store, modelContext: context))
        XCTAssertEqual(Decimal(fullDraft.priceTotal), 318)
        XCTAssertEqual(Decimal(fullDraft.balance), 0)
    }

    /// 保存发售阶段**不能**顺手把价格表清掉：走真实 upsertEntity 落盘后逐项核对
    func testSavingSalePhaseKeepsPriceChartOnDisk() throws {
        var series = CatalogSeries(id: "series-phase-persist",
                                   shopID: "shop-phase-test",
                                   name: "阶段持久化系列")
        var chart = CatalogPriceChart(id: "pricechart-series-phase-persist",
                                      seriesID: series.id)
        chart.columns = ["款式", "预约价", "定金", "尾款"]
        chart.rows = [CatalogSizeRow(label: "大蝴蝶结背心裙", values: ["318", "91", "227"])]
        series.priceChart = chart
        series.salePhase = .reservationActive
        series.reservationEndAt = now.addingTimeInterval(3600)

        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)

        // 直接读盘（绕过内存缓存）确认两个新字段落了、价格表没被清
        let data = try Data(contentsOf: ShopCatalogStorage.directory
            .appendingPathComponent("shop-catalog-override.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let list = (json?["series"] as? [[String: Any]]) ?? []
        let persisted = try XCTUnwrap(list.first { ($0["id"] as? String) == series.id },
                                      "系列应写入覆盖层")
        XCTAssertEqual(persisted["salePhase"] as? String, "reservation_active")
        XCTAssertNotNil(persisted["reservationEndAt"], "预约结束时间必须落盘")
        XCTAssertNotNil(persisted["priceChart"], "价格表**不能**因为保存发售阶段被清掉")

        ShopCatalogStore.shared.reloadWithOverlay()
        let reloaded = try XCTUnwrap(ShopCatalogStore.shared.series(id: series.id))
        XCTAssertEqual(reloaded.salePhase, .reservationActive)
        XCTAssertEqual(reloaded.reservationEndAt, series.reservationEndAt)
        XCTAssertEqual(reloaded.priceChart?.rows.first?.label, "大蝴蝶结背心裙")
    }

    // MARK: helpers

    /// 容器必须随用例保活：`ModelContext` 不强持有容器，容器先释放会让 `save()` 抛错
    private var retainedContainers: [ModelContainer] = []

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }
}
