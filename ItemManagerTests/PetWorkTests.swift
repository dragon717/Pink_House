
import XCTest
@testable import ItemManager

class PetWorkTests: XCTestCase {
    
    var viewModel: PetViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = PetViewModel()
        // Reset status
        viewModel.status = PetStatus()
        // Ensure consistent base state
        viewModel.status.energy = 100
        viewModel.status.mood = 100
        viewModel.status.hunger = 100
        viewModel.status.hygiene = 100
    }
    
    func testWorkConsumptionRates() {
        let jobs: [PetJob] = [.waiter, .security, .streamer]
        
        print("| Job | Income/min | Multiplier | Energy Decay/h | Mood Decay/h | Hunger Decay/h | Hygiene Decay/h |")
        print("|---|---|---|---|---|---|---|")
        
        for job in jobs {
            // Setup
            viewModel.status.energy = 100
            viewModel.status.mood = 100
            viewModel.status.hunger = 100
            viewModel.status.hygiene = 100
            viewModel.status.currentJob = job
            
            // Simulate 1 hour (3600 seconds)
            // We use a loop of 60 minutes to ensure any minute-based logic (like income) triggers, 
            // though processTimePassage handles float timeInterval.
            // But let's just call it once with 3600 for decay calculation simplicity, 
            // assuming linear decay.
            viewModel.processTimePassage(timeInterval: 3600.0, isOfflineSimulation: true)
            
            let energyDecay = 100 - viewModel.status.energy
            let moodDecay = 100 - viewModel.status.mood
            let hungerDecay = 100 - viewModel.status.hunger
            let hygieneDecay = 100 - viewModel.status.hygiene
            
            print("| \(job.rawValue) | \(job.incomeRate) | \(job.consumptionMultiplier)x | \(format(energyDecay)) | \(format(moodDecay)) | \(format(hungerDecay)) | \(format(hygieneDecay)) |")
        }
    }
    
    func format(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }
}
