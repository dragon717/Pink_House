import Foundation
import Combine

class VIPManager: ObservableObject {
    static let shared = VIPManager()
    
    // VIP Price (MeowCoin)
    static let monthlyPrice: Int = 66
    
    // Published properties for UI binding
    @Published var isVIP: Bool = false
    @Published var vipExpireDate: Date? = nil
    @Published var vipNumber: String? = nil
    @Published var cardStyle: VIPCardStyle = .blackGold
    
    private init() {
        // Initial load
        reloadStatus()
        
        // Listen for external updates
        NotificationCenter.default.addObserver(self, selector: #selector(reloadStatus), name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
    }
    
    @objc func reloadStatus() {
        let status = PetDataManager.shared.status
        self.isVIP = status.vipStatus.isActive && !status.vipStatus.isExpired
        self.vipExpireDate = status.vipStatus.expireDate
        self.vipNumber = status.vipStatus.vipNumber
        self.cardStyle = status.vipStatus.cardStyle
    }
    
    func updateCardStyle(_ style: VIPCardStyle) {
        var status = PetDataManager.shared.status
        status.vipStatus.cardStyle = style
        PetDataManager.shared.saveStatus(status)
        reloadStatus()
    }
    
    // Purchase or Renew VIP
    func purchaseVIP(months: Int = 1) -> (success: Bool, message: String) {
        var status = PetDataManager.shared.status
        
        let cost = months * VIPManager.monthlyPrice
        
        if status.meowCoin < cost {
            return (false, "喵币不足，需要 \(cost) 喵币")
        }
        
        // Deduct cost
        status.meowCoin -= cost
        
        // Update VIP Status
        var newExpireDate: Date
        if let currentExpire = status.vipStatus.expireDate, currentExpire > Date() {
            // Extend existing
            newExpireDate = Calendar.current.date(byAdding: .month, value: months, to: currentExpire) ?? Date()
        } else {
            // New subscription
            newExpireDate = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date()
        }
        
        status.vipStatus.isActive = true
        status.vipStatus.expireDate = newExpireDate
        
        // Generate Lucky Number if not exists
        if status.vipStatus.vipNumber == nil {
            status.vipStatus.vipNumber = generateLuckyNumber()
        }
        
        // Save
        PetDataManager.shared.saveStatus(status)
        
        // Update local state
        reloadStatus()
        
        return (true, "开通成功！有效期至 \(newExpireDate.formatted(date: .numeric, time: .omitted))")
    }
    
    // Generate a lucky number (6-8 digits, favoring 6, 8, 9, 0)
    private func generateLuckyNumber() -> String {
        let length = Int.random(in: 6...8)
        let luckyDigits = ["6", "8", "9", "0", "8", "6"] // Higher weight for 6 and 8
        let allDigits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        
        var result = ""
        // First digit shouldn't be 0 usually, but "007" is cool too. Let's allow it for "VIP No." style.
        
        for _ in 0..<length {
            if Int.random(in: 1...10) <= 7 { // 70% chance for lucky digit
                result += luckyDigits.randomElement()!
            } else {
                result += allDigits.randomElement()!
            }
        }
        
        return result
    }
}
