
import XCTest
@testable import ItemManager

class PetOfflineLogicTests: XCTestCase {
    
    var viewModel: PetViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = PetViewModel()
        // Reset status
        viewModel.status = PetStatus()
        viewModel.status.energy = 100
        viewModel.status.mood = 100
        viewModel.status.hunger = 100
        viewModel.status.hygiene = 100
        viewModel.status.fishCoin = 0
        viewModel.status.dailyFishCoinEarned = 0
    }
    
    // Test 1: Short duration offline work (No forced sleep)
    // Scenario: Working for 30 mins within a safe hour range (e.g., 10:00 - 10:30)
    func testShortTermOfflineWork() {
        print("\n=== Test 1: Short Term Offline Work ===")
        
        // Setup start time: 10:00 AM
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 10
        components.minute = 0
        components.second = 0
        guard let startTime = calendar.date(from: components) else {
            XCTFail("Failed to create start time")
            return
        }
        
        viewModel.status.lastUpdateTime = startTime
        viewModel.status.currentJob = .waiter // Income: 5/min
        viewModel.status.energy = 100
        
        // Simulate 30 minutes
        let duration: TimeInterval = 30 * 60
        
        // Manually trigger offline decay logic
        // We need to trick the viewModel into thinking 'now' is startTime + 30m
        // Since calculateOfflineDecay uses Date(), we can't easily mock it without dependency injection.
        // However, we can call processTimePassage manually in a loop to simulate the behavior of calculateOfflineDecay,
        // or we can modify calculateOfflineDecay to accept a 'now' parameter.
        // For this test, let's use the loop approach which mimics calculateOfflineDecay's core logic.
        
        var simulationTime = startTime
        let endTime = startTime.addingTimeInterval(duration)
        let step: TimeInterval = 60
        
        while simulationTime < endTime {
            // Update lastUpdateTime before calling process because process uses it as base
            viewModel.status.lastUpdateTime = simulationTime
            viewModel.processTimePassage(timeInterval: step, isOfflineSimulation: true)
            simulationTime = simulationTime.addingTimeInterval(step)
        }
        
        // Assertions
        // Expected Income: 30 mins * 5 coins/min = 150 coins
        let expectedIncome = 30 * 5
        print("Expected Income: \(expectedIncome), Actual: \(viewModel.status.fishCoin)")
        XCTAssertEqual(viewModel.status.fishCoin, expectedIncome, accuracy: 5, "Income calculation mismatch")
        
        // Energy should decrease
        XCTAssertLessThan(viewModel.status.energy, 100, "Energy should decrease after working")
    }
    
    // Test 2: Work crossing forced sleep time
    // Scenario: Working from 10:30 to 11:00 (30 mins)
    // 10:30 - 10:45 (15 mins): Working -> Income
    // 10:45 - 11:00 (15 mins): Forced Sleep -> No Income, Energy Recovery
    func testWorkThroughForcedSleep() {
        print("\n=== Test 2: Work Through Forced Sleep ===")
        
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 10
        components.minute = 30
        components.second = 0
        guard let startTime = calendar.date(from: components) else { return }
        
        viewModel.status.lastUpdateTime = startTime
        viewModel.status.currentJob = .waiter // Income: 5/min
        viewModel.status.energy = 80 // Start with some energy consumed
        
        // Simulate 30 minutes (10:30 -> 11:00)
        let duration: TimeInterval = 30 * 60
        
        var simulationTime = startTime
        let endTime = startTime.addingTimeInterval(duration)
        let step: TimeInterval = 60
        
        while simulationTime < endTime {
            viewModel.status.lastUpdateTime = simulationTime
            viewModel.processTimePassage(timeInterval: step, isOfflineSimulation: true)
            simulationTime = simulationTime.addingTimeInterval(step)
            print("Time: \(simulationTime), Wallet: \(viewModel.status.fishCoin), Daily: \(viewModel.status.dailyFishCoinEarned)")
        }
        
        // Expected Income:
        // 10:30 - 10:45 (15 mins) = 15 * 5 = 75
        // 10:45 - 11:00 (15 mins) = 0 (Sleeping)
        // Total = 75
        
        print("Expected Income: 75, Actual: \(viewModel.status.fishCoin)")
        XCTAssertEqual(viewModel.status.fishCoin, 75, accuracy: 5, "Income should only be generated during working hours")
        
        // Job should NOT be cancelled
        XCTAssertNotEqual(viewModel.status.currentJob, .none, "Job should persist through forced sleep")
        
        // Energy check: Should be higher than if worked full 30 mins
        // We don't assert exact value, just that it's reasonable
        print("Final Energy: \(viewModel.status.energy)")
    }
    
    // Test 3: Daily Reset during offline (Complex)
    // Scenario: 23:43 -> 00:01 (18 mins)
    // 23:43 - 23:44 (1 min): Working. Minute 44. Earn 5. Daily -> Limit. Wallet -> 5.
    // 23:44 - 23:45 (1 min): Sleep starts at Minute 45. So 23:45 is Sleep.
    // ... Sleeping until 23:59 ...
    // 23:59 - 00:00 (1 min): Reset at 00:00. Work starts. Earn 5. Wallet -> 10.
    // 00:00 - 00:01 (1 min): Work. Earn 5. Wallet -> 15.
    func testDailyResetOffline() {
        print("\n=== Test 3: Daily Reset Offline (Complex) ===")
        
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 23
        components.minute = 43
        components.second = 0
        guard let startTime = calendar.date(from: components) else { return }
        
        viewModel.status.lastUpdateTime = startTime
        viewModel.status.lastDailyResetDate = startTime
        viewModel.status.currentJob = .waiter // 5/min
        
        // Set Day 1 quota almost full (Space for 5 coins only)
        let limit = PetStatus.dailyFishCoinLimit
        viewModel.status.dailyFishCoinEarned = limit - 5
        viewModel.status.fishCoin = 0
        
        let duration: TimeInterval = 18 * 60
        var simulationTime = startTime
        let endTime = startTime.addingTimeInterval(duration)
        let step: TimeInterval = 60
        
        var stepCount = 0
        while simulationTime < endTime {
            stepCount += 1
            viewModel.status.lastUpdateTime = simulationTime
            viewModel.processTimePassage(timeInterval: step, isOfflineSimulation: true)
            simulationTime = simulationTime.addingTimeInterval(step)
            print("Step \(stepCount): Time \(simulationTime), Wallet \(viewModel.status.fishCoin), Daily \(viewModel.status.dailyFishCoinEarned)")
        }
        
        XCTAssertEqual(viewModel.status.fishCoin, 15, "Wallet calculation failed")
        XCTAssertEqual(viewModel.status.dailyFishCoinEarned, 10, "Daily earned for Day 2 incorrect (Should be 10)")
    }
}
