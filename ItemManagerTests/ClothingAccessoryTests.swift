
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

    func testFinancialDataSanitizerClampsMoneyAndStock() throws {
        XCTAssertEqual(FinancialDataSanitizer.money(Decimal.nan), 0)
        XCTAssertEqual(FinancialDataSanitizer.money(Decimal(-1)), 0)
        XCTAssertEqual(FinancialDataSanitizer.money(Double.nan), 0)
        XCTAssertEqual(FinancialDataSanitizer.money(Double.infinity), 0)
        XCTAssertEqual(FinancialDataSanitizer.money(Decimal(1_000_000_000)), FinancialDataSanitizer.maxMoney)
        XCTAssertEqual(FinancialDataSanitizer.stock(-3), 1)
        XCTAssertEqual(FinancialDataSanitizer.stock(1_000), 999)
    }

    func testModelInitializersSanitizeNegativeFinancialValues() throws {
        let clothing = Clothing(
            name: "Dirty Init JSK",
            originalPrice: -1,
            originalPriceJPY: -2,
            originalPriceExchangeRateJPY: -3,
            price: -10,
            deposit: -20,
            balance: -30,
            accessoriesPrice: -40,
            shippingFee: -50,
            shippingFeeJPY: -60,
            shippingExchangeRateJPY: -70,
            stock: -5
        )
        let accessory = AccessoryItem(name: "Dirty Accessory", price: -10, deposit: -20, balance: -30)
        let savingEntry = WealthSavingEntry(amount: -10)

        XCTAssertEqual(clothing.originalPrice, 0)
        XCTAssertEqual(clothing.originalPriceJPY, 0)
        XCTAssertEqual(clothing.originalPriceExchangeRateJPY, 0)
        XCTAssertEqual(clothing.price, 0)
        XCTAssertEqual(clothing.deposit, 0)
        XCTAssertEqual(clothing.balance, 0)
        XCTAssertEqual(clothing.accessoriesPrice, 0)
        XCTAssertEqual(clothing.shippingFee, 0)
        XCTAssertEqual(clothing.shippingFeeJPY, 0)
        XCTAssertEqual(clothing.shippingExchangeRateJPY, 0)
        XCTAssertEqual(clothing.stock, 1)
        XCTAssertEqual(accessory.price, 0)
        XCTAssertEqual(accessory.deposit, 0)
        XCTAssertEqual(accessory.balance, 0)
        XCTAssertEqual(savingEntry.amount, 0)
    }

    func testNegativeHistoricalFinancialValuesDoNotMakeTotalsNegative() throws {
        let clothing = Clothing(
            name: "Dirty Historical JSK",
            price: 100,
            deposit: 40,
            balance: 60,
            accessoriesPrice: 20,
            shippingFee: 10,
            stock: 1
        )
        let accessory = AccessoryItem(name: "Dirty Accessory", price: 10, deposit: 5, balance: 5)
        clothing.accessoryItems = [accessory]

        clothing.price = -100
        clothing.deposit = -40
        clothing.balance = -60
        clothing.accessoriesPrice = -20
        clothing.shippingFee = -10
        clothing.stock = -3
        accessory.price = -10
        accessory.deposit = -5
        accessory.balance = -5

        XCTAssertEqual(clothing.resolvedAccessoriesPrice, 0)
        XCTAssertEqual(clothing.unitTotalPrice, 0)
        XCTAssertEqual(clothing.inventoryTotalPrice, 0)
        XCTAssertEqual(clothing.totalDeposit, 0)
        XCTAssertEqual(clothing.totalBalance, 0)
    }

    func testNegativeWealthSavingEntryAmountDoesNotContributeToActiveTotal() throws {
        let clothing = Clothing(name: "Saving Dirty JSK", price: 100)
        let dirtyEntry = WealthSavingEntry(amount: 50, clothingID: clothing.id)
        let validEntry = WealthSavingEntry(amount: 30, clothingID: clothing.id)

        dirtyEntry.amount = -50

        XCTAssertEqual(WealthSavingLedger.activeTotal(in: [dirtyEntry, validEntry]), 30)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: [dirtyEntry, validEntry]), 30)
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

    func testLegacyFinalPaymentSavedFlagIsClearedWithoutCreatingSavingEntry() throws {
        let clothing = Clothing(name: "Legacy OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        clothing.isFinalPaymentSavedToWealth = true
        clothing.finalPaymentSavedAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(clothing)

        WealthSavingLedger.migrateLegacySavedFinalPayments(clothings: [clothing], entries: [], context: context)
        let firstEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        WealthSavingLedger.migrateLegacySavedFinalPayments(clothings: [clothing], entries: firstEntries, context: context)
        let secondEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())

        XCTAssertEqual(secondEntries.count, 0)
        XCTAssertFalse(clothing.isFinalPaymentSavedToWealth)
        XCTAssertNil(clothing.finalPaymentSavedAt)
    }

    func testOneTimeFinalPaymentCompletesDepositPlanWithoutUsingLegacySavings() throws {
        let clothing = Clothing(name: "One Time OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        context.insert(WealthSavingEntry(amount: 300, clothingID: clothing.id))
        try context.save()

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let result = try WealthSavingLedger.recordFinalPayment(
            amount: 800,
            for: clothing,
            entries: beforeEntries,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(result?.paidAmount, 800)
        XCTAssertEqual(result?.paidOff, true)
        XCTAssertFalse(clothing.isDepositPlan)
        XCTAssertEqual(clothing.finalPaymentInstallmentCount, 0)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 300)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: entries).count, 1)
    }

    func testOneTimeFinalPaymentRecordsFullDecimalRemainder() throws {
        let clothing = Clothing(name: "Decimal OP", price: Decimal(string: "1.004")!, deposit: 0, balance: Decimal(string: "1.004")!, isDepositPlan: true)
        context.insert(clothing)

        let result = try WealthSavingLedger.recordFinalPayment(
            amount: 1,
            for: clothing,
            entries: [],
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(result?.paidAmount, Decimal(string: "1.004")!)
        XCTAssertEqual(result?.remainingAmount, 0)
        XCTAssertEqual(WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: entries), 0)
        XCTAssertFalse(clothing.isDepositPlan)
    }

    func testFinalPaymentRecordPaysFullRemainingBalance() throws {
        let clothing = Clothing(name: "Final Payment OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)

        let beforeEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let first = try WealthSavingLedger.recordFinalPayment(
            amount: 300,
            for: clothing,
            entries: beforeEntries,
            context: context
        )

        let entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let payment = WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: entries).first
        XCTAssertEqual(first?.paidOff, true)
        XCTAssertFalse(clothing.isDepositPlan)
        XCTAssertEqual(clothing.finalPaymentInstallmentCount, 0)
        XCTAssertEqual(payment?.kind, .finalPayment)
        XCTAssertEqual(payment?.amount, 800)
        XCTAssertNil(payment?.finalPaymentMode)
        XCTAssertEqual(payment?.installmentIndex, 0)
        XCTAssertEqual(payment?.installmentCount, 0)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 800)
        XCTAssertEqual(WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: entries), 0)
    }

    func testExistingLegacySavingIsIgnoredByFinalPaymentRecord() throws {
        let clothing = Clothing(name: "Legacy Saving OP", price: 1000, deposit: 200, balance: 800, isDepositPlan: true)
        context.insert(clothing)
        context.insert(WealthSavingEntry(amount: 200, clothingID: clothing.id))
        try context.save()

        var entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 200)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 0)

        _ = try WealthSavingLedger.recordFinalPayment(
            amount: 500,
            for: clothing,
            entries: entries,
            context: context
        )

        entries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let payment = WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: entries).first
        XCTAssertEqual(payment?.amount, 800)
        XCTAssertEqual(WealthSavingLedger.activeTotal(for: clothing.id, in: entries), 200)
        XCTAssertEqual(WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: entries), 800)
    }

}
