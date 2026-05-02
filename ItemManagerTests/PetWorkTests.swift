
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

    func testAutoWorkStartsWhenIdleAndStatusIsHealthy() {
        viewModel.status.isAutoWorkEnabled = true
        viewModel.status.autoWorkStrategy = .balanced
        viewModel.status.autoWorkRewardMode = .fishCoin
        viewModel.status.fishCoin = 0
        viewModel.status.dailyFishCoinEarned = 0
        viewModel.status.lastDailyResetDate = safeWorkStartDate()
        viewModel.status.lastUpdateTime = safeWorkStartDate()

        viewModel.processTimePassage(timeInterval: 60, isOfflineSimulation: true)

        XCTAssertEqual(viewModel.status.currentJob, .security)
        XCTAssertTrue(viewModel.status.currentJobStartedAutomatically)
        XCTAssertEqual(viewModel.status.currentJobRewardCurrency, .fishCoin)
        XCTAssertEqual(viewModel.status.fishCoin, 10)
        XCTAssertEqual(viewModel.status.dailyFishCoinEarned, 10)
        XCTAssertEqual(viewModel.status.currentJobEarnedAmount, 10)
    }

    func testAutoWorkFollowPetCanEarnBoneCoin() {
        viewModel.status.ownedPetIds = [PetCharacter.maomao.rawValue]
        viewModel.status.selectedPetId = PetCharacter.maomao.rawValue
        viewModel.status.isAutoWorkEnabled = true
        viewModel.status.autoWorkStrategy = .balanced
        viewModel.status.autoWorkRewardMode = .followPet
        viewModel.status.boneCoin = 0
        viewModel.status.dailyBoneCoinEarned = 0
        viewModel.status.lastDailyResetDate = safeWorkStartDate()
        viewModel.status.lastUpdateTime = safeWorkStartDate()

        viewModel.processTimePassage(timeInterval: 60, isOfflineSimulation: true)

        XCTAssertEqual(viewModel.status.currentJob, .security)
        XCTAssertEqual(viewModel.status.currentJobRewardCurrency, .boneCoin)
        XCTAssertEqual(viewModel.status.boneCoin, 10)
        XCTAssertEqual(viewModel.status.dailyBoneCoinEarned, 10)
        XCTAssertEqual(viewModel.status.currentJobEarnedAmount, 10)
    }

    func testAutoWorkDoesNotStartWhenStatusIsBelowThreshold() {
        viewModel.status.isAutoWorkEnabled = true
        viewModel.status.autoWorkStrategy = .balanced
        viewModel.status.mood = 45
        viewModel.status.lastDailyResetDate = safeWorkStartDate()
        viewModel.status.lastUpdateTime = safeWorkStartDate()

        viewModel.processTimePassage(timeInterval: 60, isOfflineSimulation: true)

        XCTAssertEqual(viewModel.status.currentJob, .none)
        XCTAssertFalse(viewModel.status.currentJobStartedAutomatically)
    }

    func testChatWorkCommandStartsManualFishCoinJob() {
        let previous = PetDataManager.shared.status
        addTeardownBlock {
            PetDataManager.shared.saveStatus(previous)
        }
        PetDataManager.shared.saveStatus(healthyStatus())

        let result = applyPetWorkCommand("pet_work_start:waiter:fishCoin")
        let status = PetDataManager.shared.status

        XCTAssertTrue(result.didChangeStatus)
        XCTAssertEqual(status.currentJob, .waiter)
        XCTAssertFalse(status.currentJobStartedAutomatically)
        XCTAssertEqual(status.currentJobRewardCurrency, .fishCoin)
        XCTAssertEqual(status.currentJobEarnedAmount, 0)
    }

    func testChatWorkCommandStopsJobAndKeepsSettlementAmount() {
        let previous = PetDataManager.shared.status
        addTeardownBlock {
            PetDataManager.shared.saveStatus(previous)
        }
        var status = healthyStatus()
        status.currentJob = .security
        status.currentJobRewardCurrency = .boneCoin
        status.currentJobEarnedAmount = 25
        PetDataManager.shared.saveStatus(status)

        let result = applyPetWorkCommand("pet_work_stop")
        let saved = PetDataManager.shared.status

        XCTAssertTrue(result.didChangeStatus)
        XCTAssertEqual(saved.currentJob, .none)
        XCTAssertEqual(saved.currentJobEarnedAmount, 25)
        XCTAssertTrue(result.feedback?.contains("25") == true)
        XCTAssertTrue(result.feedback?.contains("骨头币") == true)
    }

    func testChatWorkCommandDoesNotResetExistingJob() {
        let previous = PetDataManager.shared.status
        addTeardownBlock {
            PetDataManager.shared.saveStatus(previous)
        }
        var status = healthyStatus()
        status.currentJob = .waiter
        status.currentJobRewardCurrency = .fishCoin
        status.currentJobEarnedAmount = 30
        PetDataManager.shared.saveStatus(status)

        let result = applyPetWorkCommand("pet_work_start:streamer:boneCoin")
        let saved = PetDataManager.shared.status

        XCTAssertFalse(result.didChangeStatus)
        XCTAssertEqual(saved.currentJob, .waiter)
        XCTAssertEqual(saved.currentJobRewardCurrency, .fishCoin)
        XCTAssertEqual(saved.currentJobEarnedAmount, 30)
    }

    func testChatWorkCommandUpdatesAutoWorkSettings() {
        let previous = PetDataManager.shared.status
        addTeardownBlock {
            PetDataManager.shared.saveStatus(previous)
        }
        PetDataManager.shared.saveStatus(healthyStatus())

        XCTAssertTrue(applyPetWorkCommand("pet_work_auto:on").didChangeStatus)
        XCTAssertTrue(applyPetWorkCommand("pet_work_strategy:ambitious").didChangeStatus)
        XCTAssertTrue(applyPetWorkCommand("pet_work_reward:boneCoin").didChangeStatus)

        let status = PetDataManager.shared.status
        XCTAssertTrue(status.isAutoWorkEnabled)
        XCTAssertEqual(status.autoWorkStrategy, .ambitious)
        XCTAssertEqual(status.autoWorkRewardMode, .boneCoin)
    }

    func testFixedSleepSuspendsWorkWithoutCancellingJob() {
        viewModel.status.currentJob = .waiter
        viewModel.status.currentJobRewardCurrency = .fishCoin
        viewModel.status.energy = 80
        viewModel.status.lastUpdateTime = fixedSleepStartDate()

        viewModel.processTimePassage(timeInterval: 60, isOfflineSimulation: true)

        XCTAssertEqual(viewModel.status.currentJob, .waiter)
        XCTAssertEqual(viewModel.status.currentJobEarnedAmount, 0)
        XCTAssertGreaterThan(viewModel.status.energy, 80)
    }

    func testAutoWorkStopsAtDailyQuota() {
        viewModel.status.isAutoWorkEnabled = true
        viewModel.status.autoWorkStrategy = .balanced
        viewModel.status.autoWorkRewardMode = .fishCoin
        viewModel.status.currentJob = .security
        viewModel.status.currentJobStartedAutomatically = true
        viewModel.status.currentJobRewardCurrency = .fishCoin
        viewModel.status.dailyFishCoinEarned = PetStatus.dailyFishCoinLimit
        viewModel.status.lastDailyResetDate = safeWorkStartDate()
        viewModel.status.lastUpdateTime = safeWorkStartDate()

        viewModel.processTimePassage(timeInterval: 60, isOfflineSimulation: true)

        XCTAssertEqual(viewModel.status.currentJob, .none)
        XCTAssertFalse(viewModel.status.currentJobStartedAutomatically)
    }

    func format(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }

    private func healthyStatus() -> PetStatus {
        var status = PetStatus()
        status.selectedPetId = PetCharacter.naicha.rawValue
        status.ownedPetIds = [PetCharacter.naicha.rawValue]
        status.energy = 100
        status.mood = 100
        status.hunger = 100
        status.hygiene = 100
        status.fishCoin = 0
        status.boneCoin = 0
        status.dailyFishCoinEarned = 0
        status.dailyBoneCoinEarned = 0
        return status
    }

    private func safeWorkStartDate() -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 10
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }

    private func fixedSleepStartDate() -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 10
        components.minute = 45
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
}
