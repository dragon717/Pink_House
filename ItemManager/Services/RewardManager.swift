
import SwiftUI
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
            return "添加新衣，鱼币 +\(rewardAmount)"
        case .payBalance:
            return "付完尾款啦！鱼币 +\(rewardAmount)"
        case .createOOTD(let count):
            return count >= 2 ? "搭配完成！鱼币 +\(rewardAmount)" : "新建搭配，鱼币 +\(rewardAmount)"
        case .firstTimeFeature:
            return "首次体验新功能，鱼币 +\(rewardAmount)"
        case .custom(_, let msg):
            return msg
        }
    }
}

class RewardManager: ObservableObject {
    static let shared = RewardManager()
    
    // 允许测试注入 UserDefaults
    var defaults: UserDefaults = .standard
    
    private let statusKey = "PetStatus_Data"
    
    // 发布奖励事件，UI 监听此发布者来显示气泡
    let rewardPublisher = PassthroughSubject<(Int, String), Never>()
    
    private init() {}
    
    func triggerReward(type: RewardType) {
        // 1. 对于首次功能，检查是否已触发过
        if case .firstTimeFeature(let featureName) = type {
            let key = "hasTriggeredFirstTime_\(featureName)"
            if defaults.bool(forKey: key) {
                return // 已经触发过，不再奖励
            }
            defaults.set(true, forKey: key)
        }
        
        let amount = type.rewardAmount
        let message = type.message
        
        // 2. 增加鱼币
        addFishCoin(amount: amount)
        
        // 3. 发送 UI 通知
        DispatchQueue.main.async {
            self.rewardPublisher.send((amount, message))
        }
    }
    
    private func addFishCoin(amount: Int) {
        // 读取 PetStatus
        if let data = defaults.data(forKey: statusKey),
           var status = try? JSONDecoder().decode(PetStatus.self, from: data) {
            
            // 每日上限检查
            checkDailyReset(status: &status)
            
            let remainingQuota = PetStatus.dailyFishCoinLimit - status.dailyFishCoinEarned
            let actualEarned = min(amount, remainingQuota)
            
            if actualEarned > 0 {
                status.fishCoin += actualEarned
                status.dailyFishCoinEarned += actualEarned
                
                // 保存
                if let newData = try? JSONEncoder().encode(status) {
                    defaults.set(newData, forKey: statusKey)
                    
                    // 通知 PetViewModel 刷新 (如果它在监听 UserDefaults 或者我们需要发送 Notification)
                    // PetViewModel 似乎没有自动监听 UserDefaults，所以我们发送一个 Notification
                    NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
                }
            }
        }
    }
    
    private func checkDailyReset(status: inout PetStatus) {
        let calendar = Calendar.current
        if !calendar.isDateInToday(status.lastDailyResetDate) {
            status.dailyFishCoinEarned = 0
            status.lastDailyResetDate = Date()
        }
    }
}
