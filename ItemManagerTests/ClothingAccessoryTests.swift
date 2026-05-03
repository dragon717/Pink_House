
import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ClothingAccessoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema([
            Clothing.self, WealthSavingEntry.self, Brand.self, Tag.self, StoredImage.self, CutoutItem.self, Outfit.self, OutfitItem.self, AccessoryItem.self
        ]), configurations: config)
        context = container.mainContext
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
    }
    
    func testAccessoryItemCreationAndCalculation() throws {
        // 1. 创建 Clothing
        let clothing = Clothing(name: "Test Dress")
        context.insert(clothing)
        
        // 2. 创建 AccessoryItem
        let acc1 = AccessoryItem(name: "Bow", price: 100.0, deposit: 30.0, balance: 70.0, sortIndex: 0)
        let acc2 = AccessoryItem(name: "Socks", price: 50.0, deposit: 0.0, balance: 0.0, sortIndex: 1)
        
        clothing.accessoryItems = [acc1, acc2]
        try context.save()
        
        // 3. 验证数据持久化
        let fetchedClothing = try context.fetch(FetchDescriptor<Clothing>()).first
        XCTAssertNotNil(fetchedClothing)
        XCTAssertEqual(fetchedClothing?.accessoryItems?.count, 2)
        
        let fetchedAcc1 = fetchedClothing?.accessoryItems?.first(where: { $0.name == "Bow" })
        XCTAssertEqual(fetchedAcc1?.price, 100.0)
        XCTAssertEqual(fetchedAcc1?.deposit, 30.0)
        XCTAssertEqual(fetchedAcc1?.balance, 70.0)
        
        // 4. 模拟 UI 中的自动计算逻辑 (虽然这是 ViewModel/View 的逻辑，但也值得在这里验证数据模型是否支持)
        if let acc = fetchedAcc1 {
            let newDeposit: Decimal = 40.0
            let newBalance: Decimal = 60.0
            acc.deposit = newDeposit
            acc.balance = newBalance
            // UI逻辑: price = deposit + balance
            acc.price = newDeposit + newBalance
            
            XCTAssertEqual(acc.price, 100.0)
        }
    }

    func testResolvedAccessoriesPricePrefersAccessoryItemsSum() throws {
        let clothing = Clothing(name: "Berry JSK", price: 500.0, accessoriesPrice: 10.0, stock: 2)
        let acc1 = AccessoryItem(name: "KC", price: 80.0, sortIndex: 0)
        let acc2 = AccessoryItem(name: "袜子", price: 20.0, sortIndex: 1)

        clothing.accessoryItems = [acc1, acc2]
        context.insert(clothing)

        XCTAssertEqual(clothing.resolvedAccessoriesPrice, 100.0)
        XCTAssertEqual(clothing.unitTotalPrice, 600.0)
        XCTAssertEqual(clothing.inventoryTotalPrice, 1100.0)
    }

    func testInventoryTotalIncludesShippingOnce() throws {
        let clothing = Clothing(name: "Shipping JSK", price: 500.0, accessoriesPrice: 100.0, shippingFee: 30.0, stock: 2)
        context.insert(clothing)

        XCTAssertEqual(clothing.unitTotalPrice, 600.0)
        XCTAssertEqual(clothing.inventoryTotalPrice, 1130.0)
    }

    func testOriginalPriceJPYConvertsToCNYForStatisticsSource() throws {
        let clothing = Clothing(
            name: "JPY OP",
            originalPrice: 100.0,
            originalPriceJPY: 2100.0,
            originalPriceCurrencyCode: ClothingPriceCurrency.jpy.rawValue,
            originalPriceExchangeRateJPY: 21.0
        )
        context.insert(clothing)

        XCTAssertEqual(clothing.originalPriceCurrency, .jpy)
        XCTAssertEqual(clothing.originalPrice, 100.0)
        XCTAssertEqual(clothing.originalPriceJPY, 2100.0)
    }

    func testWealthSavingMultipleEntriesAccumulateForClothing() throws {
        let clothing = Clothing(name: "Saving JSK", price: 1000, stock: 1)
        context.insert(clothing)

        try WealthSavingLedger.addSaving(amount: 120, clothingID: clothing.id, context: context)
        try WealthSavingLedger.addSaving(amount: 80, clothingID: clothing.id, context: context)

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 200)
        XCTAssertEqual(WealthSavingLedger.activeUnassignedTotal(in: entries), 0)
    }

    func testUnassignedWealthSavingDoesNotAffectClothingProgress() throws {
        let clothing = Clothing(name: "Target OP", price: 1000)
        context.insert(clothing)

        try WealthSavingLedger.addSaving(amount: 300, clothingID: nil, context: context)

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(WealthSavingLedger.activeTotal(in: entries), 300)
        XCTAssertEqual(WealthSavingLedger.progressNumerator(for: clothing, entries: entries), 0)
    }

    func testDepositPlanProgressIncludesDepositAndCanExceedTarget() throws {
        let clothing = Clothing(name: "Deposit OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)

        try WealthSavingLedger.addSaving(amount: 900, clothingID: clothing.id, context: context)

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(WealthSavingLedger.progressNumerator(for: clothing, entries: entries), 1100)
        XCTAssertGreaterThan(WealthSavingLedger.progressRatio(for: clothing, entries: entries), 1.0)
    }

    func testDepositPlanAssignableCapUsesRemainingPayableIncludingShipping() throws {
        let clothing = Clothing(
            name: "Shipping Deposit OP",
            price: 1000,
            deposit: 200,
            balance: 800,
            shippingFee: 50,
            isDepositPlan: true
        )
        context.insert(clothing)

        XCTAssertEqual(WealthSavingLedger.purchaseTarget(for: clothing), 1050)
        XCTAssertEqual(WealthSavingLedger.assignableSavingCap(for: clothing), 850)
        XCTAssertEqual(WealthSavingLedger.remainingAssignableAmount(for: clothing, entries: []), 850)
    }

    func testClampedClothingSavingOnlyAddsRemainingAssignableAmount() throws {
        let clothing = Clothing(name: "Almost Full OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 780, clothingID: clothing.id, context: context)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let entry = try WealthSavingLedger.addSaving(
            amount: 100,
            for: clothing,
            entries: beforeEntries,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(entry?.amount, 20)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 800)
    }

    func testTransferUnassignedSavingsFillsTargetWithoutExceedingCap() throws {
        let clothing = Clothing(name: "Fill Target OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 1000, clothingID: nil, context: context)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let transferred = try WealthSavingLedger.transferUnassignedSavings(
            to: clothing,
            entries: beforeEntries,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(transferred, 800)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.activeUnassignedTotal(in: entries), 200)
    }

    func testTransferUnassignedSavingsDoesNothingWhenTargetIsFull() throws {
        let clothing = Clothing(name: "Full Target OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 800, clothingID: clothing.id, context: context)
        try WealthSavingLedger.addSaving(amount: 200, clothingID: nil, context: context)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let transferred = try WealthSavingLedger.transferUnassignedSavings(
            to: clothing,
            entries: beforeEntries,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(transferred, 0)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.activeUnassignedTotal(in: entries), 200)
    }

    func testMoveOverflowToUnassignedKeepsActiveTotalStable() throws {
        let clothing = Clothing(name: "Overflow OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 900, clothingID: clothing.id, context: context)
        try WealthSavingLedger.addSaving(amount: 20, clothingID: nil, context: context)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let beforeTotal = WealthSavingLedger.activeTotal(in: beforeEntries)
        let moved = try WealthSavingLedger.moveOverflowToUnassigned(
            for: clothing,
            entries: beforeEntries,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(moved, 100)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.activeUnassignedTotal(in: entries), 120)
        XCTAssertEqual(WealthSavingLedger.activeTotal(in: entries), beforeTotal)
    }

    func testMarkSavingsUsedRemovesFromActiveTotals() throws {
        let clothing = Clothing(name: "Paid OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 500, clothingID: clothing.id, context: context)

        try WealthSavingLedger.markActiveSavingsUsed(for: clothing.id, context: context)

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 0)
        XCTAssertNotNil(entries.first?.usedAt)
    }

    func testLegacyFinalPaymentSavedMigratesOnce() throws {
        let clothing = Clothing(name: "Legacy OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        clothing.isFinalPaymentSavedToWealth = true
        clothing.finalPaymentSavedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(clothing)

        WealthSavingLedger.migrateLegacySavedFinalPayments(clothings: [clothing], entries: [], context: context)
        let firstEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        WealthSavingLedger.migrateLegacySavedFinalPayments(clothings: [clothing], entries: firstEntries, context: context)
        let secondEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())

        XCTAssertEqual(secondEntries.count, 1)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: secondEntries), clothing.totalBalance)
    }

    func testOneTimeFinalPaymentConsumesVaultAndCompletesDepositPlan() throws {
        let clothing = Clothing(name: "One Time OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 300, clothingID: clothing.id, context: context)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let result = try WealthSavingLedger.recordFinalPayment(
            amount: 800,
            for: clothing,
            entries: beforeEntries,
            mode: .oneTime,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(result?.paidAmount, 800)
        XCTAssertEqual(result?.deductedFromVault, 300)
        XCTAssertEqual(result?.externalPaymentAmount, 500)
        XCTAssertEqual(result?.paidOff, true)
        XCTAssertFalse(clothing.isDepositPlan)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 0)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: entries).count, 1)
    }

    func testInstallmentFinalPaymentDoesNotCompleteUntilCumulativePaidOff() throws {
        let clothing = Clothing(name: "Installment OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let first = try WealthSavingLedger.recordFinalPayment(
            amount: 300,
            for: clothing,
            entries: beforeEntries,
            mode: .installment,
            installmentCount: 3,
            context: context
        )

        var entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(first?.paidOff, false)
        XCTAssertTrue(clothing.isDepositPlan)
        XCTAssertEqual(clothing.finalPaymentInstallmentCount, 3)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 300)
        XCTAssertEqual(WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: entries), 500)

        _ = try WealthSavingLedger.recordFinalPayment(
            amount: 500,
            for: clothing,
            entries: entries,
            mode: .installment,
            installmentCount: 3,
            context: context
        )

        entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertFalse(clothing.isDepositPlan)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: entries), 0)
    }

    func testExistingVaultSavingIsDeductibleButNotHistoricalPayment() throws {
        let clothing = Clothing(name: "Deductible OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        try WealthSavingLedger.addSaving(amount: 200, clothingID: clothing.id, context: context)

        var entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 200)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 0)

        _ = try WealthSavingLedger.recordFinalPayment(
            amount: 500,
            for: clothing,
            entries: entries,
            mode: .installment,
            installmentCount: 2,
            context: context
        )

        entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let payment = WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: entries).first
        XCTAssertEqual(payment?.vaultDeductionAmount, 200)
        XCTAssertEqual(payment?.externalPaymentAmount, 300)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 0)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 500)
    }

}
