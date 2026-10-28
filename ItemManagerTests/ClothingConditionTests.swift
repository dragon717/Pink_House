import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ClothingConditionTests: XCTestCase {
    private var containers: [ModelContainer] = []

    override func tearDownWithError() throws { containers = [] }

    func testConditionOptionsContainOnlyPhysicalCondition() {
        XCTAssertEqual(ClothingCondition.options, ["全新", "非全新"])
        XCTAssertEqual(SuggestionManager.shared.orderedDefaults(for: SuggestionField.condition), ["全新", "非全新"])
        XCTAssertEqual(SuggestionManager.shared.getAllConditions(), ["全新", "非全新"])
        SuggestionManager.shared.addData(field: .condition, value: "待付尾款")
        XCTAssertTrue(SuggestionManager.shared.getSuggestions(for: .condition, query: "待付").isEmpty)
    }

    func testLegacyWearDescriptionsStayStoredButDisplayAsNotNew() {
        for raw in ["非全新", "仅试穿", "99新", "95新", "9成新", "有瑕疵", "战斗成色"] {
            let clothing = Clothing(name: raw, condition: raw)
            XCTAssertEqual(clothing.physicalCondition, "非全新")
            XCTAssertFalse(clothing.repairLegacyPurchaseCondition())
            XCTAssertEqual(clothing.condition, raw)
        }
        for raw in ["", "全新", " 全新\n", "全新带吊牌", "待付尾款", "未到货"] {
            XCTAssertEqual(ClothingCondition.resolve(raw), .new)
        }
    }

    func testPayoffRepairsLegacyConditionAndPersistsOwnedState() throws {
        let context = try context()
        let clothing = Clothing(name: "截图尾款", condition: "待付尾款", price: 589,
                                deposit: 113, balance: 476, isDepositPlan: true)
        context.insert(clothing)
        try context.save()
        let result = try XCTUnwrap(WealthSavingLedger.recordFinalPayment(amount: 476, for: clothing, context: context))
        XCTAssertTrue(result.paidOff)
        XCTAssertEqual(clothing.condition, "全新")
        XCTAssertEqual(clothing.reservationKind, .owned)
        XCTAssertEqual(clothing.balance, 476, "保留历史尾款金额")
        XCTAssertEqual(clothing.price, 589)
        XCTAssertEqual(WealthSavingLedger.unpaidFinalPaymentAmount(for: clothing), 0)
        XCTAssertFalse(WealthSavingLedger.shouldShowFinalPaymentPayoffAction(for: clothing))
        let reload = ModelContext(try XCTUnwrap(containers.last))
        let saved = try XCTUnwrap(reload.fetch(FetchDescriptor<Clothing>()).first)
        XCTAssertEqual(saved.condition, "全新")
        XCTAssertEqual(saved.reservationKind, .owned)
    }

    func testPayoffAndPurchaseStateTransitionsPreserveNotNewCondition() throws {
        let context = try context()
        for condition in ["全新", "非全新", "仅试穿"] {
            let clothing = Clothing(name: condition, condition: condition, price: 589)
            context.insert(clothing)
            clothing.isDepositPlan = true
            clothing.deposit = 113
            clothing.balance = 476
            XCTAssertEqual(clothing.condition, condition)
            _ = try WealthSavingLedger.recordFinalPayment(amount: 476, for: clothing, context: context)
            XCTAssertEqual(clothing.condition, condition)
            XCTAssertEqual(clothing.reservationKind, .owned)
            clothing.status = .offShelf
            XCTAssertEqual(clothing.condition, condition)
        }
    }

    func testRepairHandlesPaidUnpaidAndLaterCloudRecordsIdempotently() throws {
        let context = try context()
        let paid = Clothing(name: "已付清旧记录", condition: "待付尾款", price: 589, deposit: 113, balance: 476)
        let unpaid = Clothing(name: "未付清旧记录", condition: "待付尾款", price: 589,
                             deposit: 113, balance: 476, isDepositPlan: true)
        let worn = Clothing(name: "二手", condition: "非全新")
        let deleted = Clothing(name: "回收站", condition: "待付尾款")
        deleted.isDeleted = true
        deleted.deletedAt = Date()
        [paid, unpaid, worn, deleted].forEach { context.insert($0) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ClothingConditionRepair.repair(context: context, at: date), 2)
        XCTAssertEqual(paid.condition, "全新")
        XCTAssertEqual(unpaid.condition, "全新")
        XCTAssertEqual(unpaid.reservationKind, .depositPlan)
        XCTAssertEqual(unpaid.totalBalance, 476)
        XCTAssertEqual(paid.reservationKind, .owned)
        XCTAssertEqual(worn.condition, "非全新")
        XCTAssertEqual(deleted.condition, "待付尾款")
        XCTAssertEqual(ClothingConditionRepair.repair(context: context, at: date.addingTimeInterval(10)), 0)
        XCTAssertEqual(paid.lastModified, date)

        let delayed = Clothing(name: "稍后同步的全款预约", condition: " 未到货\n",
                               price: 589, deposit: 589, isDepositPlan: true)
        context.insert(delayed)
        XCTAssertEqual(ClothingConditionRepair.repair(context: context), 1)
        XCTAssertEqual(delayed.condition, "全新")
        XCTAssertEqual(delayed.reservationKind, .fullPaymentReservation)
    }

    func testOutstandingAmountDoesNotDependOnPhysicalCondition() {
        let clothing = Clothing(name: "只有总价的历史心愿", condition: "待付尾款",
                                price: 589, accessoriesPrice: 20, shippingFee: 5, isDepositPlan: true, stock: 2)
        let due = clothing.totalBalance
        XCTAssertEqual(due, 1203)
        clothing.repairLegacyPurchaseCondition()
        XCTAssertEqual(clothing.totalBalance, due)
        clothing.physicalCondition = "非全新"
        XCTAssertEqual(clothing.totalBalance, due)
        XCTAssertEqual(clothing.wardrobeListTotalBalance, due)
        XCTAssertEqual(WealthSavingLedger.unpaidFinalPaymentAmount(for: clothing), due)
        clothing.deposit = 589
        XCTAssertEqual(clothing.reservationKind, .fullPaymentReservation)
        XCTAssertEqual(clothing.totalBalance, 0)
    }

    func testSynchronousAndSnapshotFiltersUseSamePhysicalCondition() {
        let new = Clothing(name: "全新尾款", condition: "待付尾款", price: 589,
                           deposit: 113, balance: 476, isDepositPlan: true)
        let worn = Clothing(name: "试穿", condition: "仅试穿", price: 500)
        let items = [new, worn]
        for condition in ClothingCondition.options {
            let direct = ClothingFilterService.filter(items, config: .init(selectedConditions: [condition]))
            let result = WardrobeFilterEngine.evaluate(WardrobeFilterInput(
                snapshots: items.map(WardrobeClothingSnapshot.init(clothing:)), searchText: "",
                selectedTagIDs: [], selectedBrandIDs: [], selectedTypes: [], selectedColors: [],
                selectedSizes: [], selectedLengths: [], selectedConditions: [condition], selectedAccessories: [],
                depositStatusFilterRawValue: DepositStatusFilter.all.rawValue, sortOptionRawValue: ""))
            XCTAssertEqual(result.ids, direct.map(\.id))
            XCTAssertEqual(direct.map(\.id), condition == "全新" ? [new.id] : [worn.id])
            XCTAssertEqual(result.conditionOptions, ["全新", "非全新"])
        }
    }

    func testLedgerReconciliationRepairsConditionWithoutOverwritingWear() throws {
        let context = try context()
        let items = ["待付尾款", "非全新"].map {
            Clothing(name: $0, condition: $0, price: 589, deposit: 113, balance: 476, isDepositPlan: true)
        }
        items.forEach { context.insert($0) }
        let entries = items.map { WealthSavingEntry(amount: 476, clothingID: $0.id, entryKind: .finalPayment) }
        entries.forEach { context.insert($0) }
        XCTAssertEqual(WealthSavingLedger.reconcilePaidFinalPayments(clothings: items, entries: entries, context: context), 2)
        XCTAssertEqual(items.map(\.condition), ["全新", "非全新"])
        XCTAssertEqual(items.map(\.reservationKind), [.owned, .owned])
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Clothing.self, Brand.self, Tag.self, WealthSavingEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        containers.append(container)
        return ModelContext(container)
    }
}
