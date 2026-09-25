//
//  ShopCatalogWardrobeBalanceSyncTests.swift
//  ItemManagerTests
//
//  尾款阶段同步 + 加购尾款窗口 契约（2026-09-25 需求二/三）。
//
//  口径：
//    · 只有「尾款中」（effectivePhase == .balancePending）系列才同步用户衣橱条目
//    · 窗口来源唯一：声明直接用（exact）/ 大致按约一个月基准估算成固定具体日期
//      （approximate，锚点 = series.reservationEndAt）
//    · 绝不碰金额；全款 / 已付清记录不动；商品已删 → 跳过（数据独立）
//    · 幂等：重复调用 updatedCount == 0，备注不重复追加
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
        // 备注留痕
        XCTAssertTrue(clothing.note.contains("尾款阶段同步"))

        // 幂等：重算结果恒定 → 第二次零更新、备注不重复
        let second = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
            store: store, modelContext: context, now: reservationEnd.addingTimeInterval(86_400 * 20))
        XCTAssertEqual(second.updatedCount, 0)
        XCTAssertEqual(clothing.note.components(separatedBy: "尾款阶段同步").count - 1, 1)
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
        XCTAssertTrue(clothing.note.contains("10月上旬"), "备注必须留估算依据")

        var components = Calendar.current.dateComponents([.month, .day], from: expected)
        XCTAssertEqual(components.month, 10)
        components = Calendar.current.dateComponents([.day], from: expected)
        XCTAssertEqual(components.day, 10, "「上旬」→ 10 日")
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
            store: store, modelContext: context))

        let expected = try XCTUnwrap(CatalogBalanceDueApproximation.estimatedDate(
            text: "10月上旬", anchor: reservationEnd))
        XCTAssertEqual(draft.finalPaymentDate, expected, "尾款时间 = 声明估算值，不是加购当天")
        XCTAssertEqual(draft.finalPaymentEndDate, expected)
        XCTAssertTrue(draft.note.contains("估算"), "备注必须留痕「这是估算」")

        // 心愿（未付定金）同样适用：不能用加购当天占位
        let wishDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: fixture.productID, priceMode: .wishlist),
            store: store, modelContext: context))
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
            store: store, modelContext: context))
        XCTAssertEqual(draft.finalPaymentDate, reservationEnd)
        XCTAssertFalse(draft.note.contains("估算"))
    }
}
