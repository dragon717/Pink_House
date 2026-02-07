
import XCTest
@testable import ItemManager

final class RewardManagerTests: XCTestCase {
    
    var defaults: UserDefaults!
    var initialFishCoin = 1000
    let statusKey = "PetStatus_Data"
    
    override func setUp() {
        super.setUp()
        // Use a temporary suite for testing
        defaults = UserDefaults(suiteName: "RewardManagerTests")
        defaults.removePersistentDomain(forName: "RewardManagerTests")
        
        // Inject into RewardManager
        RewardManager.shared.defaults = defaults
        
        // Seed initial PetStatus
        var status = PetStatus()
        status.fishCoin = initialFishCoin
        status.dailyFishCoinEarned = 0
        status.lastDailyResetDate = Date()
        
        if let data = try? JSONEncoder().encode(status) {
            defaults.set(data, forKey: statusKey)
        }
    }
    
    override func tearDown() {
        defaults.removePersistentDomain(forName: "RewardManagerTests")
        super.tearDown()
    }
    
    // Helper to get current status
    func getCurrentStatus() -> PetStatus? {
        guard let data = defaults.data(forKey: statusKey) else { return nil }
        return try? JSONDecoder().decode(PetStatus.self, from: data)
    }
    
    func testFirstTimeFeatures() {
        print("--- Testing First Time Features ---")
        
        // 1. First time "ViewLayoutChange"
        RewardManager.shared.triggerReward(type: .firstTimeFeature("ViewLayoutChange"))
        
        var status = getCurrentStatus()
        XCTAssertEqual(status?.fishCoin, initialFishCoin + 100, "First time ViewLayoutChange should add 100 coins")
        print("First trigger: +100 OK")
        
        // 2. Second time "ViewLayoutChange"
        RewardManager.shared.triggerReward(type: .firstTimeFeature("ViewLayoutChange"))
        status = getCurrentStatus()
        XCTAssertEqual(status?.fishCoin, initialFishCoin + 100, "Second time ViewLayoutChange should NOT add coins")
        print("Second trigger: +0 OK")
        
        // 3. First time "OOTDSidebar"
        RewardManager.shared.triggerReward(type: .firstTimeFeature("OOTDSidebar"))
        status = getCurrentStatus()
        XCTAssertEqual(status?.fishCoin, initialFishCoin + 200, "First time OOTDSidebar should add another 100 coins")
        print("Another feature trigger: +100 OK")
    }
    
    func testDailyLimit() {
        print("--- Testing Daily Limit ---")
        // Limit is 10000
        let limit = PetStatus.dailyFishCoinLimit
        let rewardPerAction = 200 // payBalance
        let actionsNeeded = (limit / rewardPerAction) + 5 // Exceed limit
        
        print("Simulating \(actionsNeeded) actions...")
        for _ in 0..<actionsNeeded {
            RewardManager.shared.triggerReward(type: .payBalance)
        }
        
        let status = getCurrentStatus()
        XCTAssertEqual(status?.dailyFishCoinEarned, limit, "Daily earned should be capped at limit")
        XCTAssertEqual(status?.fishCoin, initialFishCoin + limit, "Total coins should increase by limit")
        print("Limit reached: \(status?.dailyFishCoinEarned ?? 0)/\(limit) OK")
    }
    
    func testHighIntensityScenario() {
        print("--- Testing High Intensity Scenario ---")
        // High Intensity: 50 new clothes, 10 balance payments, 5 OOTDs, 3 first-time features
        // New Clothes: 50 * 50 = 2500
        // Balance: 10 * 200 = 2000
        // OOTD: 5 * 100 = 500
        // First Time: 3 * 100 = 300
        // Total Expected: 5300
        
        print("Adding 50 clothes...")
        for _ in 0..<50 {
            RewardManager.shared.triggerReward(type: .addClothing)
        }
        
        print("Paying 10 balances...")
        for _ in 0..<10 {
            RewardManager.shared.triggerReward(type: .payBalance)
        }
        
        print("Creating 5 OOTDs...")
        for _ in 0..<5 {
            RewardManager.shared.triggerReward(type: .createOOTD(itemCount: 3))
        }
        
        print("Triggering 3 first-time features...")
        RewardManager.shared.triggerReward(type: .firstTimeFeature("F1"))
        RewardManager.shared.triggerReward(type: .firstTimeFeature("F2"))
        RewardManager.shared.triggerReward(type: .firstTimeFeature("F3"))
        
        let status = getCurrentStatus()
        let expectedEarned = 2500 + 2000 + 500 + 300
        
        print("Expected: \(expectedEarned), Actual: \(status?.dailyFishCoinEarned ?? 0)")
        
        XCTAssertEqual(status?.dailyFishCoinEarned, expectedEarned)
        XCTAssertEqual(status?.fishCoin, initialFishCoin + expectedEarned)
    }
    
    func testMediumIntensityScenario() {
        print("--- Testing Medium Intensity Scenario ---")
        // Medium: 5 new clothes, 1 OOTD
        // Clothes: 5 * 50 = 250
        // OOTD: 1 * 100 = 100
        // Total: 350
        
        for _ in 0..<5 {
            RewardManager.shared.triggerReward(type: .addClothing)
        }
        
        RewardManager.shared.triggerReward(type: .createOOTD(itemCount: 2))
        
        let status = getCurrentStatus()
        print("Expected: 350, Actual: \(status?.dailyFishCoinEarned ?? 0)")
        XCTAssertEqual(status?.dailyFishCoinEarned, 350)
        XCTAssertEqual(status?.fishCoin, initialFishCoin + 350)
    }
    
    func testLowIntensityScenario() {
        print("--- Testing Low Intensity Scenario ---")
        // Low: Just 1 first time feature
        // Total: 100
        
        RewardManager.shared.triggerReward(type: .firstTimeFeature("LowIntensity"))
        
        let status = getCurrentStatus()
        print("Expected: 100, Actual: \(status?.dailyFishCoinEarned ?? 0)")
        XCTAssertEqual(status?.dailyFishCoinEarned, 100)
        XCTAssertEqual(status?.fishCoin, initialFishCoin + 100)
    }
}
