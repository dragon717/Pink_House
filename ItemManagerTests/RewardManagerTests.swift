import XCTest
@testable import ItemManager

final class RewardManagerTests: XCTestCase {
    @MainActor
    func testOldPetPageSavePreservesPreviouslyGrantedRewardHistory() async {
        var latest = PetStatus()
        latest.claimedOperationRewards = ["wardrobe-add:1"]
        var stalePage = PetStatus()
        stalePage.claimedOperationRewards = ["guide:1"]
        stalePage.hunger = 45
        let saved = PetDataManager.statusForOrdinarySave(stalePage, previous: latest)
        XCTAssertEqual(saved.claimedOperationRewards, ["wardrobe-add:1", "guide:1"])
        XCTAssertEqual(saved.hunger, 45)
    }

    @MainActor
    private func withLedger(_ body: (RewardManager, UserDefaults) throws -> Void) rethrows {
        let name = "RewardManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var status = PetStatus()
        status.fishCoin = 1000
        status.dailyFishCoinEarned = 0
        status.lastDailyResetDate = Date()
        defaults.set(try! JSONEncoder().encode(status), forKey: "PetStatus_Data")
        try body(RewardManager(defaults: defaults), defaults)
    }

    @MainActor
    private func status(_ defaults: UserDefaults) -> PetStatus {
        try! JSONDecoder().decode(PetStatus.self, from: defaults.data(forKey: "PetStatus_Data")!)
    }

    @MainActor
    func testFirstTimeFeatures() async {
        withLedger { manager, defaults in
            XCTAssertEqual(manager.grant(type: .firstTimeFeature("Layout")).actualAmount, 100)
            XCTAssertEqual(manager.grant(type: .firstTimeFeature("Layout")).status, .duplicate)
            XCTAssertEqual(manager.grant(type: .firstTimeFeature("Stats")).actualAmount, 100)
            XCTAssertEqual(status(defaults).fishCoin, 1200)
        }
    }

    @MainActor
    func testDailyLimitAndActualReceipt() async {
        withLedger { manager, defaults in
            var initial = status(defaults)
            initial.dailyFishCoinEarned = PetStatus.dailyFishCoinLimit - 20
            defaults.set(try! JSONEncoder().encode(initial), forKey: "PetStatus_Data")
            let receipt = manager.grant(type: .addClothing, operationID: "new:1")
            XCTAssertEqual(receipt.requestedAmount, 50)
            XCTAssertEqual(receipt.actualAmount, 20)
            XCTAssertTrue(receipt.isLimited)
            XCTAssertEqual(status(defaults).fishCoin, 1020)
            XCTAssertEqual(manager.grant(type: .payBalance).actualAmount, 0)
            XCTAssertEqual(status(defaults).dailyFishCoinEarned, PetStatus.dailyFishCoinLimit)
        }
    }

    @MainActor
    func testIdempotenceSurvivesNewManagerAndDailyReset() async {
        withLedger { manager, defaults in
            XCTAssertEqual(manager.grant(type: .addClothing, operationID: "clothing:1").actualAmount, 50)
            var saved = status(defaults)
            saved.lastDailyResetDate = Date().addingTimeInterval(-172800)
            defaults.set(try! JSONEncoder().encode(saved), forKey: "PetStatus_Data")
            let restored = RewardManager(defaults: defaults)
            XCTAssertEqual(restored.grant(type: .addClothing, operationID: "clothing:1").status, .duplicate)
            XCTAssertEqual(restored.grant(type: .addClothing, operationID: "clothing:2").actualAmount, 50)
            XCTAssertEqual(status(defaults).fishCoin, 1100)
            XCTAssertEqual(status(defaults).dailyFishCoinEarned, 50)
        }
    }

    @MainActor
    func testInvalidAndUnavailableRewardsDoNotConsumeFirstTime() async {
        withLedger { manager, defaults in
            XCTAssertEqual(manager.grant(type: .custom(amount: -50, message: "x")).status, .invalid)
            XCTAssertEqual(status(defaults).fishCoin, 1000)
            defaults.set(Data("broken".utf8), forKey: "PetStatus_Data")
            XCTAssertEqual(manager.grant(type: .firstTimeFeature("A")).status, .unavailable)
            XCTAssertFalse(defaults.bool(forKey: "hasTriggeredFirstTime_A"))
            defaults.removeObject(forKey: "PetStatus_Data")
            XCTAssertEqual(manager.grant(type: .addClothing).status, .unavailable)
        }
    }

    @MainActor
    func testCappedOperationCannotClaimAgainTomorrow() async {
        withLedger { manager, defaults in
            var saved = status(defaults)
            saved.dailyFishCoinEarned = PetStatus.dailyFishCoinLimit
            defaults.set(try! JSONEncoder().encode(saved), forKey: "PetStatus_Data")
            XCTAssertEqual(manager.grant(type: .addClothing, operationID: "capped").actualAmount, 0)
            saved = status(defaults)
            saved.lastDailyResetDate = Date().addingTimeInterval(-172800)
            defaults.set(try! JSONEncoder().encode(saved), forKey: "PetStatus_Data")
            XCTAssertEqual(manager.grant(type: .addClothing, operationID: "capped").status, .duplicate)
            XCTAssertEqual(status(defaults).fishCoin, 1000)
        }
    }

    @MainActor
    func testOldSnapshotWithoutRewardLedgerStillDecodes() async throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PetStatus())) as! [String: Any]
        object.removeValue(forKey: "claimedOperationRewards")
        let decoded = try JSONDecoder().decode(PetStatus.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.claimedOperationRewards.isEmpty)
    }

    @MainActor
    func testHighIntensityScenarioAndOtherCurrenciesUnchanged() async {
        withLedger { manager, defaults in
            for _ in 0..<50 { manager.grant(type: .addClothing) }
            for _ in 0..<10 { manager.grant(type: .payBalance) }
            for _ in 0..<5 { manager.grant(type: .createOOTD(itemCount: 3)) }
            for feature in ["A", "B", "C"] { manager.grant(type: .firstTimeFeature(feature)) }
            XCTAssertEqual(status(defaults).fishCoin, 6300)
            XCTAssertEqual(status(defaults).dailyFishCoinEarned, 5300)
            XCTAssertEqual(status(defaults).meowCoin, 0)
            XCTAssertEqual(status(defaults).boneCoin, 0)
        }
    }
}
