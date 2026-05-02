import XCTest
@testable import ItemManager

final class PetStatusCodableTests: XCTestCase {
    func testRoundTripPreservesPetStatusFields() throws {
        var status = PetStatus()
        status.petNames = ["naicha": "奶盖", "maomao": "毛球"]
        status.selectedPetId = "maomao"
        status.ownedPetIds = ["naicha", "maomao"]
        status.hunger = 66
        status.hygiene = 77
        status.energy = 55
        status.mood = 88
        status.intimacy = 23
        status.meowCoin = 12
        status.fishCoin = 345
        status.boneCoin = 67
        status.dailyFishCoinEarned = 890
        status.dailyBoneCoinEarned = 120
        status.inventory = ["catFood": 2, "renameCard": 1]
        status.currentJob = .streamer
        status.jobStartTime = Date(timeIntervalSince1970: 1_700_000_000)
        status.currentJobEarnedFishCoin = 456
        status.currentJobEarnedAmount = 789
        status.currentJobRewardCurrency = .boneCoin
        status.currentJobStartedAutomatically = true
        status.isAutoWorkEnabled = true
        status.autoWorkStrategy = .ambitious
        status.autoWorkRewardMode = .followPet
        status.vipStatus.isActive = true
        status.vipStatus.vipNumber = "668899"

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(PetStatus.self, from: encoded)

        XCTAssertEqual(decoded.petNames["naicha"], "奶盖")
        XCTAssertEqual(decoded.selectedPetId, "maomao")
        XCTAssertEqual(decoded.ownedPetIds, ["naicha", "maomao"])
        XCTAssertEqual(decoded.hunger, 66)
        XCTAssertEqual(decoded.hygiene, 77)
        XCTAssertEqual(decoded.energy, 55)
        XCTAssertEqual(decoded.mood, 88)
        XCTAssertEqual(decoded.intimacy, 23)
        XCTAssertEqual(decoded.meowCoin, 12)
        XCTAssertEqual(decoded.fishCoin, 345)
        XCTAssertEqual(decoded.boneCoin, 67)
        XCTAssertEqual(decoded.dailyFishCoinEarned, 890)
        XCTAssertEqual(decoded.dailyBoneCoinEarned, 120)
        XCTAssertEqual(decoded.inventory["catFood"], 2)
        XCTAssertEqual(decoded.currentJob, .streamer)
        XCTAssertEqual(decoded.jobStartTime, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(decoded.currentJobEarnedFishCoin, 456)
        XCTAssertEqual(decoded.currentJobEarnedAmount, 789)
        XCTAssertEqual(decoded.currentJobRewardCurrency, .boneCoin)
        XCTAssertTrue(decoded.currentJobStartedAutomatically)
        XCTAssertTrue(decoded.isAutoWorkEnabled)
        XCTAssertEqual(decoded.autoWorkStrategy, .ambitious)
        XCTAssertEqual(decoded.autoWorkRewardMode, .followPet)
        XCTAssertTrue(decoded.vipStatus.isActive)
        XCTAssertEqual(decoded.vipStatus.vipNumber, "668899")
    }
}
