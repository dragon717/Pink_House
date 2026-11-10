#if targetEnvironment(simulator)
import StoreKit
import StoreKitTest
import XCTest
@testable import ItemManager

/// Creates local StoreKit transactions and checks the app's verified transaction listener.
@MainActor
final class ReleaseStoreKitTests: XCTestCase {
    func testSixProductsAndRepeatPurchase() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Pink House Store ") == true)
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ReleaseCoins", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        defer { withExtendedLifetime(session) {} }
        session.disableDialogs = true
        session.storefront = "USA"
        let store = StoreManager.shared
        XCTAssertFalse(IAPTestManager.shared.isTestMode)
        await store.fetchProducts()
        XCTAssertEqual(Set(store.coinProducts.map(\.id)), Set(IAPProductType.allProductIDs))
        XCTAssertTrue(store.coinProducts.allSatisfy { $0.type == .consumable })

        let product = try XCTUnwrap(store.coinProducts.first { $0.id == IAPProductType.meowCoin60.rawValue })
        // Product metadata may be cached from the storefront. SKTestSession alone
        // creates the transactions below and never presents a real purchase sheet.
        for _ in 0..<2 {
            let before = StoreManager.loadMeowCoinAccount()
            let expected = before.firstPurchaseCompletedByProduct[product.id] == true ? 66 : 120
            let existingIDs = Set(session.allTransactions().map(\.identifier))
            // This test-server API injects a verified transaction into Transaction.updates.
            // A personal Apple account and an interactive purchase sheet are out of scope.
            try session.buyProduct(productIdentifier: product.id)
            let deadline = Date().addingTimeInterval(12)
            while StoreManager.loadMeowCoinAccount().balance == before.balance && Date() < deadline {
                try await Task.sleep(for: .milliseconds(200))
            }
            let newTransactions = session.allTransactions().filter { !existingIDs.contains($0.identifier) }
            XCTAssertEqual(newTransactions.count, 1)
            XCTAssertEqual(StoreManager.loadMeowCoinAccount().balance - before.balance, expected)
            XCTAssertEqual(PetDataManager.shared.status.meowCoin, before.balance + expected)
            let latest = try XCTUnwrap(newTransactions.first)
            let data = try XCTUnwrap(UserDefaults.standard.data(forKey: IAPPurchaseRecord.storageKey))
            let history = try JSONDecoder().decode([IAPPurchaseRecord].self, from: data)
            let records = history.filter { $0.id == String(latest.identifier) }
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?.coinAmount, expected)
        }
    }

    func testInterruptedCreditRepairsBalanceAndHistoryOnlyOnce() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Pink House Store ") == true)
        let store = StoreManager.shared
        var account = StoreManager.loadMeowCoinAccount()
        let receipt = IAPPurchaseRecord(id: UUID().uuidString, productID: IAPProductType.meowCoin60.rawValue,
                                        purchaseDate: Date(), coinAmount: 66, subscriptionMonths: nil,
                                        isVerified: true, verificationDate: Date())
        account.balance += 66
        account.totalPurchased += 66
        account.pendingStoreCredit = receipt
        XCTAssertTrue(StoreManager.saveMeowCoinAccount(account))
        XCTAssertTrue(store.completePendingStoreCredit())
        XCTAssertTrue(store.completePendingStoreCredit())
        XCTAssertEqual(PetDataManager.shared.status.meowCoin, account.balance)
        let saved = StoreManager.loadMeowCoinAccount()
        XCTAssertNil(saved.pendingStoreCredit)
        XCTAssertEqual(saved.totalPurchased, account.totalPurchased)
        let history = try XCTUnwrap(UserDefaults.standard.data(forKey: IAPPurchaseRecord.storageKey))
        XCTAssertEqual(try JSONDecoder().decode([IAPPurchaseRecord].self, from: history).filter { $0.id == receipt.id }.count, 1)
    }

}
#endif
