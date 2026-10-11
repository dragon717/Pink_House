
import Foundation
import Combine

enum RewardType {
    case addClothing
    case payBalance
    case createOOTD(itemCount: Int)
    case firstTimeFeature(String)
    case custom(amount: Int, message: String)
    
    var rewardAmount: Int {
        switch self {
        case .addClothing:
            return 50
        case .payBalance:
            return 200
        case .createOOTD(let count):
            return count >= 2 ? 100 : 20
        case .firstTimeFeature:
            return 100
        case .custom(let amount, _):
            return amount
        }
    }
    
    var message: String {
        switch self {
        case .addClothing:
            return "添加新衣"
        case .payBalance:
            return "付完尾款啦！"
        case .createOOTD(let count):
            return count >= 2 ? "搭配完成！" : "新建搭配"
        case .firstTimeFeature:
            return "首次体验新功能"
        case .custom(_, let msg):
            return msg
        }
    }
}

/// 奖励到账回执；展示层不能从 RewardType.rewardAmount 推测实际到账数量。
struct FishCoinRewardReceipt: Equatable {
    enum Status { case granted, limited, duplicate, unavailable, invalid }
    let requestedAmount: Int
    let actualAmount: Int
    let status: Status
    var isLimited: Bool { status == .limited }
}

@MainActor
final class RewardManager: ObservableObject {
    static let shared = RewardManager()
    /// 独立实例允许测试注入，不改写 shared 或真实钱包。
    let defaults: UserDefaults
    private let usesPetDataManager: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usesPetDataManager = defaults === UserDefaults.standard
    }

    @discardableResult
    func grant(type: RewardType, operationID: String? = nil) -> FishCoinRewardReceipt {
        let requested = type.rewardAmount
        func receipt(_ amount: Int, _ status: FishCoinRewardReceipt.Status) -> FishCoinRewardReceipt {
            FishCoinRewardReceipt(requestedAmount: requested, actualAmount: amount, status: status)
        }
        guard requested > 0 else { return receipt(0, .invalid) }
        var firstTimeKey: String?
        var identity = operationID
        if case .firstTimeFeature(let feature) = type {
            firstTimeKey = "hasTriggeredFirstTime_\(feature)"
            identity = "first-feature:\(feature)"
            if defaults.bool(forKey: firstTimeKey!) { return receipt(0, .duplicate) }
        }
        var status: PetStatus
        if usesPetDataManager {
            // 使用内存中的最新状态，避免连续奖励读到尚未异步写盘的旧余额。
            status = PetDataManager.shared.status
        } else {
            guard let data = defaults.data(forKey: "PetStatus_Data"),
                  let decoded = try? JSONDecoder().decode(PetStatus.self, from: data) else {
                return receipt(0, .unavailable)
            }
            status = decoded
        }
        if let identity, status.claimedOperationRewards.contains(identity) {
            return receipt(0, .duplicate)
        }
        if !Calendar.current.isDateInToday(status.lastDailyResetDate) {
            status.dailyFishCoinEarned = 0
            status.dailyBoneCoinEarned = 0
            status.lastDailyResetDate = Date()
        }
        let quota = max(0, PetStatus.dailyFishCoinLimit - max(0, status.dailyFishCoinEarned))
        let actual = min(requested, quota)
        guard status.fishCoin <= Int.max - actual else { return receipt(0, .invalid) }
        status.fishCoin += actual
        status.dailyFishCoinEarned = max(0, status.dailyFishCoinEarned) + actual
        // 已成功的业务操作即使触顶也消费幂等标识；首次体验则允许之后补领。
        if let identity, firstTimeKey == nil || actual > 0 {
            status.claimedOperationRewards.insert(identity)
        }
        if usesPetDataManager {
            guard PetDataManager.shared.persistOperationReward(status) else {
                return receipt(0, .unavailable)
            }
        } else {
            guard let data = try? JSONEncoder().encode(status) else { return receipt(0, .unavailable) }
            defaults.set(data, forKey: "PetStatus_Data")
        }
        if let firstTimeKey, actual > 0 { defaults.set(true, forKey: firstTimeKey) }
        return receipt(actual, actual < requested ? .limited : .granted)
    }

    /// 旧功能入口也走统一展示，不再依赖视图生命周期中的 Publisher 订阅。
    @discardableResult
    func triggerReward(type: RewardType, operationID: String? = nil) -> FishCoinRewardReceipt {
        let result = grant(type: type, operationID: operationID)
        guard result.status != .duplicate, result.status != .invalid else { return result }
        OperationFeedbackCenter.shared.show(type.message.appLocalized,
            kind: result.status == .unavailable ? .warning : .success,
            fishCoins: result.actualAmount,
            detail: result.isLimited ? "已达到今日鱼币奖励上限".appLocalized
                : result.status == .unavailable ? "奖励暂未到账".appLocalized : nil,
            duration: 3)
        return result
    }
}
