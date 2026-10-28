import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class WardrobeOwnershipFilterTests: XCTestCase {
    private var containers: [ModelContainer] = []

    override func tearDownWithError() throws { containers = [] }

    func testOwnedNeverIncludesUnpaidWishlistFullReservationOrSoldRecords() {
        let items = fixtures()
        let owned = ClothingFilterService.filterByDepositStatus(items, filter: .owned)
        XCTAssertEqual(owned.map(\.name), ["已拥有"])
        XCTAssertEqual(items.count, 5, "筛选不得修改原始衣物或付款状态")
        XCTAssertTrue(items[1].isFinalPaymentPlan)
        XCTAssertTrue(items[2].isFinalPaymentPlan)
    }

    func testEveryStatusAgreesAcrossServiceSnapshotAndDisplayedCache() {
        let items = fixtures()
        let expected: [DepositStatusFilter: [String]] = [
            .all: items.map(\.name), .owned: ["已拥有"], .depositPlan: ["已付定金", "心愿未付款"],
            .fullPaymentReservation: ["全款预约"], .sold: ["售出的尾款记录"]]
        for filter in DepositStatusFilter.allCases {
            let direct = ClothingFilterService.filter(items, config: .init(depositStatusFilter: filter))
            let displayedCache = ClothingFilterService.filterByDepositStatus(items, filter: filter)
            let snapshotIDs = result(items, filter: filter).ids
            XCTAssertEqual(Set(direct.map(\.name)), Set(expected[filter]!))
            XCTAssertEqual(displayedCache.map(\.id), direct.map(\.id))
            XCTAssertEqual(Set(snapshotIDs), Set(direct.map(\.id)))
        }
    }

    func testOwnedCountsAndValuesExcludeUnpaidGarmentsAndAccessories() {
        let owned = Clothing(name: "已拥有", types: "JSK", price: 100, accessoriesPrice: 20,
                             shippingFee: 5, stock: 2)
        let unpaid = Clothing(name: "待补尾款", types: "JSK", price: 500, deposit: 100,
                              balance: 400, isDepositPlan: true, stock: 4)
        let accessory = AccessoryItem(name: "未付的小物", price: 30, deposit: 5, balance: 25)
        unpaid.accessoryItems = [accessory]
        let filtered = result([owned, unpaid], filter: .owned)
        XCTAssertEqual(filtered.ids, [owned.id])
        XCTAssertEqual(filtered.stats.styleCount, 1)
        XCTAssertEqual(filtered.stats.totalCount, 2)
        XCTAssertEqual(filtered.stats.dressValue, 200)
        XCTAssertEqual(filtered.stats.totalValue, 225)
    }

    func testSwitchingStatusFiltersOldCachedRowsAndStatsImmediately() {
        let oldCache = fixtures()
        XCTAssertEqual(result(oldCache, filter: .all).stats.styleCount, 4)
        let displayed = ClothingFilterService.filterByDepositStatus(oldCache, filter: .owned)
        let stats = WardrobeFilterEngine.statsSummary(for: displayed.map(WardrobeClothingSnapshot.init(clothing:)))
        XCTAssertEqual(displayed.map(\.name), ["已拥有"])
        XCTAssertEqual(stats.styleCount, 1)
        XCTAssertEqual(stats.totalCount, 1)
        XCTAssertFalse(displayed.contains { $0.isFinalPaymentPlan })
    }

    func testPayoffEntersOwnedWhileHistoricalBalanceRemainsIntact() throws {
        let context = try context()
        let clothing = Clothing(name: "付尾款测试", types: "JSK", price: 638, deposit: 127,
                                balance: 511, isDepositPlan: true)
        context.insert(clothing)
        try context.save()
        let oldCache = [clothing]
        let cachedCard = WardrobeCellSnapshot(clothing: clothing)
        XCTAssertTrue(cachedCard.statusTags.contains(.depositPaid))
        XCTAssertTrue(result(oldCache, filter: .owned).ids.isEmpty)
        XCTAssertEqual(result(oldCache, filter: .depositPlan).ids, [clothing.id])

        let paid = try XCTUnwrap(WealthSavingLedger.recordFinalPayment(
            amount: 511, for: clothing, context: context))
        XCTAssertTrue(paid.paidOff)
        XCTAssertEqual(clothing.balance, 511, "历史尾款金额保留，不能靠 balance > 0 判断仍未付款")
        XCTAssertEqual(clothing.reservationKind, .owned)
        XCTAssertEqual(ClothingFilterService.filterByDepositStatus(oldCache, filter: .owned).map(\.id), [clothing.id])
        XCTAssertEqual(result(oldCache, filter: .owned).ids, [clothing.id])
        XCTAssertTrue(result(oldCache, filter: .depositPlan).ids.isEmpty)
        let currentCard = WardrobeCellSnapshot.current(clothing: clothing, cached: cachedCard)
        XCTAssertFalse(currentCard.statusTags.contains(.depositPaid))
        XCTAssertFalse(currentCard.isDepositPlan)
        XCTAssertEqual(currentCard.inventoryTotalPrice, 638)
        XCTAssertEqual(result(oldCache, filter: .owned).stats.totalValue, 638)
    }

    func testSavingsPartialAndVoidedPaymentsDoNotCountAsPaidOffOwnership() throws {
        let context = try context()
        let clothing = Clothing(name: "尚未付清", types: "JSK", price: 638, deposit: 127,
                                balance: 511, isDepositPlan: true)
        context.insert(clothing)
        let savings = WealthSavingEntry(amount: 638, clothingID: clothing.id, entryKind: .saving)
        let partial = WealthSavingEntry(amount: 200, clothingID: clothing.id, entryKind: .finalPayment)
        let voided = WealthSavingEntry(amount: 511, clothingID: clothing.id, entryKind: .finalPayment)
        voided.voidedAt = Date()
        let entries = [savings, partial, voided]
        entries.forEach { context.insert($0) }
        try context.save()
        XCTAssertEqual(WealthSavingLedger.reconcilePaidFinalPayments(
            clothings: [clothing], entries: entries, context: context), 0)
        XCTAssertTrue(clothing.isFinalPaymentPlan)
        XCTAssertTrue(result([clothing], filter: .owned).ids.isEmpty)
        XCTAssertEqual(result([clothing], filter: .depositPlan).ids, [clothing.id])
    }

    func testReopenedUnpaidStateCannotStayInOwnedDisplayCache() {
        let clothing = Clothing(name: "状态被编辑的裙装", types: "JSK", price: 638)
        let oldCache = [clothing]
        let cachedCard = WardrobeCellSnapshot(clothing: clothing)
        XCTAssertEqual(result(oldCache, filter: .owned).ids, [clothing.id])
        clothing.deposit = 127
        clothing.balance = 511
        clothing.isDepositPlan = true
        XCTAssertTrue(ClothingFilterService.filterByDepositStatus(oldCache, filter: .owned).isEmpty)
        XCTAssertTrue(result(oldCache, filter: .owned).ids.isEmpty)
        XCTAssertEqual(result(oldCache, filter: .depositPlan).ids, [clothing.id])
        XCTAssertTrue(WardrobeCellSnapshot.current(clothing: clothing, cached: cachedCard)
            .statusTags.contains(.depositPaid))
    }

    func testEditingCacheDropsUnpaidAndRestoresRecordsWhenFilterChanges() {
        let items = fixtures()
        let ownedIDs = result(items, filter: .owned).ids
        let allIDs = items.map(\.id)
        let narrowed = WardrobeFilterEngine.displayOrder(existingIDs: Array(allIDs.reversed()), filteredIDs: ownedIDs)
        XCTAssertEqual(narrowed, [items[0].id])
        let restored = WardrobeFilterEngine.displayOrder(existingIDs: narrowed, filteredIDs: allIDs)
        XCTAssertEqual(restored, allIDs)
        let reordered = WardrobeFilterEngine.displayOrder(existingIDs: [allIDs[1], allIDs[0]], filteredIDs: allIDs)
        XCTAssertEqual(Array(reordered.prefix(2)), [allIDs[1], allIDs[0]], "保留用户已经拖动的顺序")
    }

    private func fixtures() -> [Clothing] {
        [Clothing(name: "已拥有", types: "JSK", price: 638),
         Clothing(name: "已付定金", types: "JSK", price: 638, deposit: 127, balance: 511, isDepositPlan: true),
         Clothing(name: "心愿未付款", types: "JSK", price: 638, balance: 638, isDepositPlan: true),
         Clothing(name: "全款预约", types: "JSK", price: 638, deposit: 638, isDepositPlan: true),
         Clothing(name: "售出的尾款记录", types: "JSK", price: 638, deposit: 127, balance: 511,
                  isDepositPlan: true, status: .offShelf)]
    }

    private func result(_ clothings: [Clothing], filter: DepositStatusFilter) -> WardrobeFilterResult {
        WardrobeFilterEngine.evaluate(WardrobeFilterInput(
            snapshots: clothings.map(WardrobeClothingSnapshot.init(clothing:)), searchText: "",
            selectedTagIDs: [], selectedBrandIDs: [], selectedTypes: [], selectedColors: [],
            selectedSizes: [], selectedLengths: [], selectedConditions: [], selectedAccessories: [],
            depositStatusFilterRawValue: filter.rawValue, sortOptionRawValue: ""))
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Clothing.self, Brand.self, Tag.self, WealthSavingEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        containers.append(container)
        return ModelContext(container)
    }
}
