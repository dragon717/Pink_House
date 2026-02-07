
import XCTest
@testable import ItemManager

class PetSimulationTests: XCTestCase {
    
    var viewModel: PetViewModel!
    
    override func setUp() {
        super.setUp()
        // Initialize ViewModel
        // We need to ensure we don't overwrite actual user data if we run this on device, 
        // but XCTest usually runs in a sandbox or we can mock UserDefaults.
        // For this script, we will just manually reset the status object after init.
        viewModel = PetViewModel()
    }
    
    func testPetSimulation() {
        let scenarios: [(name: String, interval: Int?)] = [
            ("高强度交互 (每15分钟)", 15 * 60),
            ("低强度交互 (每6小时)", 6 * 60 * 60),
            ("不交互", nil)
        ]
        
        let checkpoints: [Double] = [0.8, 1, 3, 8, 24, 72] // Hours
        
        print("| 场景 | 时间 | 饱食度 | 清洁度 | 精力 | 心情 | 状态 |")
        print("|---|---|---|---|---|---|---|")
        
        for scenario in scenarios {
            runSimulation(name: scenario.name, interactionInterval: scenario.interval, checkpoints: checkpoints)
        }
    }
    
    func runSimulation(name: String, interactionInterval: Int?, checkpoints: [Double]) {
        // Reset Status
        viewModel.status = PetStatus()
        viewModel.status.hunger = 100
        viewModel.status.hygiene = 100
        viewModel.status.energy = 100
        viewModel.status.mood = 100
        viewModel.status.fishCoin = 0
        viewModel.status.meowCoin = 0
        viewModel.currentState = .idle
        
        // Fix start time
        let startDate = Date()
        viewModel.status.lastUpdateTime = startDate
        viewModel.status.lastDailyResetDate = startDate
        
        // Convert checkpoints to seconds for easier comparison
        let checkpointSeconds = checkpoints.map { $0 * 3600 }
        var currentCheckpointIndex = 0
        
        let totalDuration = 72 * 3600 // 72 hours
        let step = 60 // 1 minute step
        
        for elapsedTime in stride(from: 0, to: totalDuration + step, by: step) {
            
            // Check if we hit a checkpoint
            if currentCheckpointIndex < checkpointSeconds.count && Double(elapsedTime) >= checkpointSeconds[currentCheckpointIndex] {
                let hour = checkpoints[currentCheckpointIndex]
                print("| \(name) | \(hour)h | \(format(viewModel.status.hunger)) | \(format(viewModel.status.hygiene)) | \(format(viewModel.status.energy)) | \(format(viewModel.status.mood)) | \(viewModel.currentState.rawValue) |")
                currentCheckpointIndex += 1
            }
            
            // Interaction
            if let interval = interactionInterval, elapsedTime > 0, elapsedTime % interval == 0 {
                // Simulate Petting
                viewModel.pet()
            }
            
            // Simulate Time Passage
            // Note: We use isOfflineSimulation = true to use the internal time calculation based on lastUpdateTime
            // We advance time by `step` seconds.
            viewModel.processTimePassage(timeInterval: Double(step), isOfflineSimulation: true)
        }
    }
    
    func format(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }
}
