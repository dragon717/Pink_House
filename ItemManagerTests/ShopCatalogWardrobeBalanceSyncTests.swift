//
//  ShopCatalogWardrobeBalanceSyncTests.swift
//  ItemManagerTests
//
//  尾款阶段同步 + 加购尾款窗口 契约（2026-09-25 需求二/三）。
//
//  口径：
//    · 已选团次的待付记录随该团声明更新；未分团的系列仍仅在「尾款中」同步
//    · 窗口来源唯一：声明直接用（exact）/ 大致按约一个月基准估算成固定具体日期
//      （approximate，锚点 = series.reservationEndAt）
//    · 绝不碰金额；全款 / 已付清记录不动；商品已删 → 跳过（数据独立）
//    · 幂等：重复调用 updatedCount == 0，备注始终保持用户原文
//    · 测试隔离：一律 ShopCatalogStorage.useTemporaryForTesting()，context 来自
//      内存容器 —— 同步服务**没有**默认生产 context，必须显式传入（红线防线）
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogWardrobeBalanceSyncTests: XCTestCase {

    private let store = ShopCatalogSeedFixture.makeStore()
    private var retainedContainers: [ModelContainer] = []

    /// 固定锚点：系列预约结束时间（运营侧事实）
    private let reservationEnd = Date(timeIntervalSince1970: 1_788_000_000) // 2026-08-27 前后

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        store.reloadWithOverlay()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        store.reloadWithOverlay()
        super.tearDown()
    }

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Schema([Clothing.self, Brand.self, Tag.self]),
                                            configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    // MARK: 夹具

    private struct Fixture {
        var productID: String
        var seriesID: String
    }

    /// 建系列 + 商品 + 预约销售记录；`configure` 里声明发售阶段 / 尾款期
    @discardableResult
    private func makeFixture(configure: (inout CatalogSeries) -> Void = { _ in }) throws -> Fixture {
        let seriesID = "series-sync-01"
        let productID = "prod-sync-01"
        var series = CatalogSeries(id: seriesID, shopID: "shop-sync", name: "尾款同步系列")
        series.year = 2026
        series.reservationEndAt = reservationEnd
        configure(&series)
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)
        try ShopCatalogDraftStore.upsertEntity(
            CatalogProduct(id: productID, shopID: "shop-sync", seriesID: seriesID,
                           name: "尾款同步 JSK", category: "JSK"),
            keyPath: \.products)
        try ShopCatalogDraftStore.upsertEntity(
            CatalogSaleEvent(id: "sale-sync-resv", productID: productID, type: .reservation,
                             price: 428, deposit: 128, endAt: reservationEnd),
            keyPath: \.saleEvents)
        store.reloadWithOverlay()
        return Fixture(productID: productID, seriesID: seriesID)
    }

    /// 已付定金、等尾款的用户记录
    @discardableResult
    private func makeDepositClothing(context: ModelContext,
                                     productID: String,
                                     deposit: Decimal = 128,
                                     balance: Decimal = 300,
                                     isDepositPlan: Bool = true) -> Clothing {
        let clothing = Clothing(name: "尾款同步系列 尾款同步 JSK", types: "JSK", price: 428, stock: 1)
        clothing.catalogProductID = productID
        clothing.isDepositPlan = isDepositPlan
        clothing.deposit = deposit
        clothing.balance = balance
        clothing.finalPaymentDate = reservationEnd
        clothing.finalPaymentEndDate = reservationEnd
        context.insert(clothing)
        return clothing
    }

    // MARK: 1. exact 声明：直接同步到具体时间

    func testExactDeclarationSyncsWardrobeWindow() throws {
        let fixture = try makeFixture { series in
            series.salePhase = .balancePending
            series.balanceDueKind = .exact
            series.balanceDueAt = reservationEnd.addingTimeInterval(86_400 * 14)
            series.balanceDueEndAt = reservationEnd.addingTimeInterval(86_400 * 44)
        }
        let context = modelContext()
        let clothing = makeDepositClothing(context: context, productID: fixture.productID)

        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400 * 20))

        XCTAssertEqual(report.checkedCount, 1)
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(clothing.finalPaymentDate, reservationEnd.addingTimeInterval(86_400 * 14))
        XCTAssertEqual(clothing.finalPaymentEndDate, reservationEnd.addingTimeInterval(86_400 * 44))
        // 金额一个不动（2026-09-25 红线：同步只写窗口）
        XCTAssertEqual(clothing.deposit, 128)
        XCTAssertEqual(clothing.balance, 300)
        XCTAssertEqual(clothing.note, "", "同步不写用户备注")

        // 幂等：重算结果恒定 → 第二次零更新、备注不改写
        let second = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400 * 20))
        XCTAssertEqual(second.updatedCount, 0)
        XCTAssertEqual(clothing.note, "")
    }

    // MARK: 2. approximate 声明：估算成固定具体日期（拒绝模糊描述 / 加购当天）

    func testApproximateDeclarationBecomesFixedEstimatedDate() throws {
        let fixture = try makeFixture { series in
            series.salePhase = .balancePending
            series.balanceDueKind = .approximate
            series.balanceDueText = "10月上旬"
        }
        let context = modelContext()
        let clothing = makeDepositClothing(context: context, productID: fixture.productID)

        // now 换成别的时刻再同步：估算不能依赖「同步当天」
        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: Date(timeIntervalSince1970: 1_900_000_000))

        XCTAssertEqual(report.updatedCount, 1)
        let expected = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "10月上旬", anchor: reservationEnd))
        XCTAssertEqual(clothing.finalPaymentDate, expected, "估算必须与锚点绑定，与同步时刻无关")
        XCTAssertEqual(clothing.finalPaymentEndDate, expected)
        XCTAssertEqual(clothing.note, "", "估算依据在确认页展示，不写备注")

        var components = Calendar.current.dateComponents([.month, .day], from: expected)
        XCTAssertEqual(components.month, 10)
        components = Calendar.current.dateComponents([.day], from: expected)
        XCTAssertEqual(components.day, 5, "「上旬」取中间日 → 5 日")
    }

    // MARK: 3. 只有「尾款中」才同步

    func testReservationActiveSeriesIsNotSynced() throws {
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.balanceDueKind = .exact
            series.balanceDueAt = reservationEnd.addingTimeInterval(86_400 * 14)
        }
        let context = modelContext()
        let clothing = makeDepositClothing(context: context, productID: fixture.productID)
        let original = clothing.finalPaymentDate

        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400))

        XCTAssertEqual(report.updatedCount, 0)
        XCTAssertEqual(clothing.finalPaymentDate, original, "预约中阶段不动用户记录")
    }

    // MARK: 4. 数据独立：商品已删除 → 跳过，用户记录原样保留

    func testDeletedProductIsNotSynced() throws {
        // 只建 Clothing 引用，不建 Catalog 实体（等价于运营已删除/下架）
        let context = modelContext()
        let clothing = makeDepositClothing(context: context, productID: "prod-sync-gone")
        clothing.isDepositPlan = true
        let original = clothing.finalPaymentDate

        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400))

        XCTAssertEqual(report.updatedCount, 0)
        XCTAssertEqual(clothing.finalPaymentDate, original, "商品缺失时绝不改写用户数据")
    }

    // MARK: 5. 全款 / 已付清记录不动

    func testFullPaidAndCompletedRecordsAreNotSynced() throws {
        let fixture = try makeFixture { series in
            series.salePhase = .balancePending
            series.balanceDueKind = .exact
            series.balanceDueAt = reservationEnd.addingTimeInterval(86_400 * 14)
        }
        let context = modelContext()
        // 全款：balance == 0 → isFullPaymentReservation → 不在尾款流程里
        let fullPaid = makeDepositClothing(context: context, productID: fixture.productID,
                                           deposit: 428, balance: 0)
        // 已付清 / 普通拥有：isDepositPlan == false
        let completed = makeDepositClothing(context: context, productID: fixture.productID,
                                            isDepositPlan: false)

        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400))

        XCTAssertEqual(report.checkedCount, 0, "全款与已付清记录不进入扫描范围")
        XCTAssertEqual(fullPaid.finalPaymentDate, reservationEnd)
        XCTAssertEqual(completed.finalPaymentDate, reservationEnd)
    }

    // MARK: 6. 无锚点的 approximate → 跳过（缺依据不猜）

    func testApproximateWithoutAnchorIsSkipped() throws {
        let fixture = try makeFixture { series in
            series.salePhase = .balancePending
            series.balanceDueKind = .approximate
            series.balanceDueText = "上旬"
            series.reservationEndAt = nil
        }
        let context = modelContext()
        let clothing = makeDepositClothing(context: context, productID: fixture.productID)
        let original = clothing.finalPaymentDate

        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400))

        XCTAssertEqual(report.updatedCount, 0)
        XCTAssertEqual(clothing.finalPaymentDate, original)
    }

    // MARK: 7. 加购路径：声明优先、禁用加购当天

    func testInsertReservationDraftUsesDeclaredWindowNotAddDate() throws {
        let fixture = try makeFixture { series in
            // 预约中阶段即可填尾款时间（运营常在预约期公布）——阶段不限
            series.salePhase = .reservationActive
            series.balanceDueKind = .approximate
            series.balanceDueText = "10月上旬"
        }
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: fixture.productID,
                             priceMode: .reservation(depositPaid: 128)),
            store: store))

        let expected = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "10月上旬", anchor: reservationEnd))
        XCTAssertEqual(draft.finalPaymentDate, expected, "尾款时间 = 声明估算值，不是加购当天")
        XCTAssertEqual(draft.finalPaymentEndDate, expected)
        XCTAssertEqual(draft.note, "")

        // 心愿（未付定金）同样适用：不能用加购当天占位
        let wishDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: fixture.productID, priceMode: .wishlist),
            store: store))
        XCTAssertEqual(wishDraft.finalPaymentDate, expected)
        XCTAssertEqual(Decimal(wishDraft.balance), 428, "心愿金额口径不变（金额零手输红线不受影响）")
    }

    func testInsertWithoutDeclarationKeepsLegacyWindow() throws {
        // 完全无尾款声明 → 旧行为：预约结束 = 尾款开始（无声明不能猜日期）
        let fixture = try makeFixture()
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: fixture.productID,
                             priceMode: .reservation(depositPaid: 128)),
            store: store))
        XCTAssertEqual(draft.finalPaymentDate, reservationEnd)
        XCTAssertFalse(draft.note.contains("估算"))
    }

    func testMultiBatchEntryUsesSelectedWindowAndPersistsStableID() throws {
        let firstDate = reservationEnd.addingTimeInterval(86_400 * 10)
        let secondDate = reservationEnd.addingTimeInterval(86_400 * 40)
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.balanceDueKind = .exact
            series.balanceDueAt = firstDate
            series.reservationBatches = [
                CatalogReservationBatch(id: "first", name: "先行团", balanceDueKind: .exact,
                                        balanceDueAt: firstDate),
                CatalogReservationBatch(id: "second", name: "二团", balanceDueKind: .exact,
                                        balanceDueAt: secondDate, balanceDueEndAt: secondDate.addingTimeInterval(86_400))
            ]
        }
        XCTAssertNil(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: fixture.productID, priceMode: .reservation(depositPaid: 128)), store: store))
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
            priceMode: .reservation(depositPaid: 128), reservationBatchID: "second")
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        XCTAssertEqual(draft.finalPaymentDate, secondDate)
        XCTAssertEqual(draft.finalPaymentEndDate, secondDate.addingTimeInterval(86_400))
        XCTAssertEqual(draft.note, "")
        let context = modelContext()
        let clothing = try ShopCatalogWardrobeInserter.insert(draft: draft.with(note: "这是我的纪念款"),
            selection: selection, store: store, modelContext: context)
        XCTAssertEqual(clothing.catalogReservationBatchID, "second")
        XCTAssertEqual(clothing.note, "这是我的纪念款")
        var series = try XCTUnwrap(store.series(id: fixture.seriesID))
        series.salePhase = .balancePending
        series.reservationBatches?[1].name = "二团（更名）"
        series.reservationBatches?[1].balanceDueAt = secondDate.addingTimeInterval(86_400 * 2)
        series.reservationBatches?[1].balanceDueEndAt = secondDate.addingTimeInterval(86_400 * 3)
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)
        store.reloadWithOverlay()
        let legacy = makeDepositClothing(context: context, productID: fixture.productID)
        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context,
            now: secondDate.addingTimeInterval(86_400 * 5))
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(clothing.finalPaymentDate, secondDate.addingTimeInterval(86_400 * 2))
        XCTAssertEqual(clothing.note, "这是我的纪念款")
        XCTAssertEqual(legacy.finalPaymentDate, reservationEnd, "未选团的旧记录不能套用某一团")
    }

    func testConfirmedPRunChoiceCreatesItsOwnPaymentDateAndOnlyThatRunFollowsUpdates() throws {
        let first = reservationEnd.addingTimeInterval(86_400 * 10)
        let second = reservationEnd.addingTimeInterval(86_400 * 50)
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.reservationBatches = [
                .init(id: "p1", name: "1P", balanceDueKind: .exact, balanceDueAt: first),
                .init(id: "p2", name: "2P", balanceDueKind: .exact, balanceDueAt: second)
            ]
        }
        var series = try XCTUnwrap(store.series(id: fixture.seriesID))
        var choice = ShopCatalogPurchaseBatchSelection()
        XCTAssertTrue(choice.requiresSelection(for: [series]))
        choice.selectedIDs[series.id] = "p2"
        XCTAssertTrue(choice.canConfirm(for: [series]))
        let selected = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
            priceMode: .reservation(depositPaid: 128), reservationBatchID: choice.selectedIDs[series.id])
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selected, store: store))
        let context = modelContext()
        let clothing = try ShopCatalogWardrobeInserter.insert(draft: draft, selection: selected,
            store: store, modelContext: context)
        XCTAssertEqual(clothing.catalogReservationBatchID, "p2")
        XCTAssertEqual(clothing.finalPaymentDate, second)
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
        series.reservationBatches?[0].balanceDueAt = first.addingTimeInterval(86_400)
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)
        store.reloadWithOverlay()
        _ = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context, now: second)
        XCTAssertEqual(clothing.finalPaymentDate, second, "第一P日期变化不能串到第二P")
        series.reservationBatches?[1].balanceDueAt = second.addingTimeInterval(86_400 * 2)
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)
        store.reloadWithOverlay()
        _ = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context, now: second)
        XCTAssertEqual(clothing.finalPaymentDate, second.addingTimeInterval(86_400 * 2))
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
    }

    func testSelectedBatchUpdatesReminderBeforeReservationEndsWithoutChangingOtherBatch() throws {
        let firstDate = reservationEnd.addingTimeInterval(86_400 * 30)
        let secondDate = reservationEnd.addingTimeInterval(86_400 * 90)
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.reservationBatches = [
                .init(id: "first", name: "先行团", balanceDueKind: .exact, balanceDueAt: firstDate),
                .init(id: "second", name: "二团", balanceDueKind: .exact, balanceDueAt: secondDate)
            ]
        }
        let context = modelContext()
        var records: [Clothing] = []
        for id in ["first", "second"] {
            let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
                priceMode: .reservation(depositPaid: 128), reservationBatchID: id)
            let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
            records.append(try ShopCatalogWardrobeInserter.insert(draft: draft, selection: selection,
                store: store, modelContext: context))
        }
        let revised = secondDate.addingTimeInterval(86_400 * 10)
        var series = try XCTUnwrap(store.series(id: fixture.seriesID))
        series.reservationBatches?[1].balanceDueAt = revised
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)
        store.reloadWithOverlay()
        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context,
            now: reservationEnd.addingTimeInterval(-86_400))
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(records[0].finalPaymentDate, firstDate)
        XCTAssertEqual(records[1].finalPaymentDate, revised)
        XCTAssertEqual(ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context,
            now: reservationEnd.addingTimeInterval(-86_400)).updatedCount, 0)
    }

    func testHolidayBatchCreatesAndRefreshesEstimatedPaymentDateWithoutChangingRawAnnouncement() throws {
        let calendar = Calendar.current
        let authored = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 19, hour: 12)))
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.reservationBatches = [
                .init(id: "first", name: "先行团", balanceDueKind: .approximate,
                      balanceDueText: "圣诞节前", balanceDueReferenceAt: authored),
                .init(id: "second", name: "二团", balanceDueKind: .approximate,
                      balanceDueText: "2027年2月中旬", balanceDueReferenceAt: authored)
            ]
        }
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
            priceMode: .reservation(depositPaid: 128), reservationBatchID: "first")
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        XCTAssertEqual(draft.finalPaymentDate, expected)
        let context = modelContext()
        let clothing = try ShopCatalogWardrobeInserter.insert(draft: draft.with(note: "我的备注"),
            selection: selection, store: store, modelContext: context)
        XCTAssertEqual(clothing.catalogReservationBatchID, "first")
        XCTAssertEqual(clothing.finalPaymentDate, expected)
        clothing.finalPaymentDate = nil
        clothing.finalPaymentEndDate = nil
        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context, now: authored)
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(clothing.finalPaymentDate, expected)
        XCTAssertEqual(clothing.finalPaymentEndDate, expected)
        XCTAssertEqual(clothing.note, "我的备注")
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
        XCTAssertEqual(store.series(id: fixture.seriesID)?.reservationBatches?.first?.balanceDueText, "圣诞节前")
    }

    func testBatchDurationCreatesEndDateAndLaterSyncOnlyUpdatesSelectedBatch() throws {
        let calendar = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.reservationBatches = [
                .init(id: "early", name: "先行团", balanceDueKind: .approximate,
                    balanceDueText: "圣诞节前", balanceDueEndText: "一个月", balanceDueReferenceAt: date(2026, 10, 15)),
                .init(id: "later", name: "非圣诞先行团", balanceDueKind: .approximate,
                    balanceDueText: "2027年2月中旬", balanceDueEndText: "十五天")
            ]
        }
        let context = modelContext()
        var clothes: [Clothing] = []
        for id in ["early", "later"] {
            let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
                priceMode: .reservation(depositPaid: 128), reservationBatchID: id)
            let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
            clothes.append(try ShopCatalogWardrobeInserter.insert(draft: draft.with(note: "保留我的备注"),
                selection: selection, store: store, modelContext: context))
        }
        XCTAssertEqual(clothes[0].finalPaymentDate, date(2026, 12, 19))
        XCTAssertEqual(clothes[0].finalPaymentEndDate, date(2027, 1, 19))
        XCTAssertEqual(clothes[1].finalPaymentDate, date(2027, 2, 15))
        XCTAssertEqual(clothes[1].finalPaymentEndDate, date(2027, 3, 2))
        var series = try XCTUnwrap(store.series(id: fixture.seriesID))
        series.reservationBatches?[0].balanceDueEndText = "十天"
        try ShopCatalogDraftStore.upsertEntity(series, keyPath: \.series)
        store.reloadWithOverlay()
        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context,
            now: date(2030, 1, 1))
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(clothes[0].finalPaymentDate, date(2026, 12, 19))
        XCTAssertEqual(clothes[0].finalPaymentEndDate, date(2026, 12, 29))
        XCTAssertEqual(clothes[1].finalPaymentEndDate, date(2027, 3, 2), "其它团的截止时间不变")
        XCTAssertEqual(clothes.map(\.catalogReservationBatchID), ["early", "later"])
        XCTAssertTrue(clothes.allSatisfy { $0.pendingFinalPaymentAmount == 300 && $0.note == "保留我的备注" })
        XCTAssertEqual(store.series(id: fixture.seriesID)?.reservationBatches?.first?.balanceDueEndText, "十天")
        XCTAssertEqual(ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context).updatedCount, 0)
    }

    func testPublishedBatchIsRequiredAndSavedEvenWhenLegacyOverlayHasNoBatches() throws {
        let fixture = try makeFixture { series in
            series.salePhase = .reservationActive
            series.balanceDueKind = .approximate
            series.balanceDueText = "先行团圣诞节前，另团次年2月"
        }
        let calendar = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        var remote = try XCTUnwrap(store.catalog)
        let index = try XCTUnwrap(remote.series.firstIndex { $0.id == fixture.seriesID })
        remote.series[index].reservationBatches = [
            .init(id: "early", name: "先行团", balanceDueKind: .approximate,
                balanceDueText: "2026年圣诞节前", balanceDueEndText: "一个月"),
            .init(id: "later", name: "非圣诞先行团", balanceDueKind: .approximate,
                balanceDueText: "2027年2月中旬", balanceDueEndText: "十天")]
        var selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
            priceMode: .reservation(depositPaid: 128))
        let unsafeDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        store.installRemoteCatalog(remote)
        XCTAssertNil(store.series(id: fixture.seriesID)?.reservationBatches, "重现手机旧副本遮住云端团次")
        XCTAssertNil(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store), "未选公开团次不得跳过")
        let context = modelContext()
        XCTAssertThrowsError(try ShopCatalogWardrobeInserter.insert(draft: unsafeDraft,
            selection: selection, store: store, modelContext: context))
        selection.reservationBatchID = "later"
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        XCTAssertEqual(draft.finalPaymentDate, date(2027, 2, 15))
        XCTAssertEqual(draft.finalPaymentEndDate, date(2027, 2, 25))
        let clothing = try ShopCatalogWardrobeInserter.insert(draft: draft, selection: selection,
            store: store, modelContext: context)
        XCTAssertEqual(clothing.catalogReservationBatchID, "later")
        remote.series[index].reservationBatches?[1].balanceDueEndText = "十五天"
        store.installRemoteCatalog(remote)
        let report = ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: context)
        XCTAssertEqual(report.updatedCount, 1)
        XCTAssertEqual(clothing.finalPaymentEndDate, date(2027, 3, 2))
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
        XCTAssertNil(ShopCatalogDraftStore.loadOverlay()?.series.first { $0.id == fixture.seriesID }?.reservationBatches)
    }

    func testUnannouncedBatchDoesNotUseOtherBatchOrTodayAsDueDate() throws {
        let fixture = try makeFixture { series in
            series.balanceDueKind = .exact
            series.balanceDueAt = reservationEnd.addingTimeInterval(86_400 * 10)
            series.reservationBatches = [CatalogReservationBatch(id: "first", name: "一团")]
        }
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(productID: fixture.productID,
            priceMode: .reservation(depositPaid: 128), reservationBatchID: "first")
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store))
        let clothing = try ShopCatalogWardrobeInserter.insert(draft: draft, selection: selection,
            store: store, modelContext: modelContext())
        XCTAssertNil(clothing.finalPaymentDate)
        XCTAssertNil(clothing.finalPaymentEndDate)
        XCTAssertEqual(clothing.note, "")
    }

    func testBatchConfigSurvivesFormAndSnapshotRoundTrip() throws {
        var series = CatalogSeries(id: "series-form", shopID: "shop-form", name: "分团系列")
        series.reservationBatches = [CatalogReservationBatch(id: "stable", name: "一团",
            balanceDueKind: .approximate, balanceDueText: "11月上旬")]
        let form = ShopCatalogSeriesConfigForm(series: series)
        let decoded = try JSONDecoder().decode(ShopCatalogSeriesConfigForm.self, from: JSONEncoder().encode(form))
        XCTAssertNil(decoded.balanceDueValidationErrorText())
        XCTAssertEqual(decoded.apply(to: series).reservationBatches, series.reservationBatches)
        let data = try JSONEncoder().encode(form)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "reservationBatches")
        let legacy = try JSONDecoder().decode(ShopCatalogSeriesConfigForm.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.reservationBatches)
    }


    func testApproximateDatesUseEachSelectedBatchAnchor() throws {
        let secondAnchor = Calendar.current.date(byAdding: .month, value: 2, to: reservationEnd)!
        let fixture = try makeFixture { series in
            series.salePhase = .balancePending
            series.reservationBatches = [
                CatalogReservationBatch(id: "first", name: "一团", reservationEndAt: reservationEnd,
                                        balanceDueKind: .approximate, balanceDueText: "上旬"),
                CatalogReservationBatch(id: "second", name: "二团", reservationEndAt: secondAnchor,
                                        balanceDueKind: .approximate, balanceDueText: "上旬")
            ]
        }
        let first = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: .init(
            productID: fixture.productID, priceMode: .reservation(depositPaid: 128),
            reservationBatchID: "first"), store: store))
        let second = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(selection: .init(
            productID: fixture.productID, priceMode: .reservation(depositPaid: 128),
            reservationBatchID: "second"), store: store))
        let firstMonth = Calendar.current.component(.month, from: first.finalPaymentDate)
        let secondMonth = Calendar.current.component(.month, from: second.finalPaymentDate)
        XCTAssertEqual(firstMonth, 9)
        XCTAssertEqual(secondMonth, 11)
        XCTAssertEqual(Calendar.current.component(.day, from: second.finalPaymentDate), 5)
        XCTAssertEqual(first.note, "")
        XCTAssertEqual(second.note, "")
    }


    func testGroupedPhaseIgnoresDormantCommonDateAndResolvesSelectedGroup() {
        let now = reservationEnd.addingTimeInterval(86_400 * 20)
        var series = CatalogSeries(id: "grouped-phase", shopID: "shop", name: "分团阶段",
            salePhase: .reservationEnded, reservationEndAt: reservationEnd,
            balanceDueKind: .exact, balanceDueAt: reservationEnd,
            reservationBatches: [
                CatalogReservationBatch(id: "first", name: "一团", balanceDueKind: .exact,
                    balanceDueAt: reservationEnd.addingTimeInterval(86_400 * 30)),
                CatalogReservationBatch(id: "second", name: "二团", balanceDueKind: .exact,
                    balanceDueAt: reservationEnd.addingTimeInterval(86_400 * 60))
            ])
        XCTAssertEqual(CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now), .reservationEnded)
        XCTAssertFalse(CatalogSeriesBalanceDue.isDue(of: series, now: now))
        series.reservationBatches?[0].balanceDueAt = reservationEnd.addingTimeInterval(86_400 * 10)
        XCTAssertEqual(CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now), .balancePending)
        let second = series.paymentSchedule(batchID: "second")!
        XCTAssertEqual(CatalogSeriesSalePhaseResolver.effectivePhase(of: second, now: now), .reservationEnded)
        XCTAssertFalse(CatalogSeriesBalanceDue.isEnded(of: series, now: now))
    }

}
