import Foundation
import Combine

class VIPManager: ObservableObject {
    static let shared = VIPManager()
    static let versionDefaultCardStyle: VIPCardStyle = .monicaPink
    static let cardStyleMigrationKey = "VIPCardStyleDefaultApplied_2026_04_MonicaPink"
    
    // VIP Price (MeowCoin)
    static let monthlyPrice: Int = 66
    static let quarterlyPrice: Int = 188
    static let petShopDiscountRate: Double = 0.6
    static let themeSkinShopDiscountRate: Double = 0.9
    static let quarterlyDiscountText: String = "-5% OFF"
    static let petShopDiscountText: String = "-40% OFF"
    static let themeSkinDiscountText: String = "-10% OFF"
    
    // Published properties for UI binding
    @Published var isVIP: Bool = false
    @Published var vipExpireDate: Date? = nil
    @Published var vipNumber: String? = nil
    @Published var cardStyle: VIPCardStyle = .monicaPink
    
    private init() {
        applyVersionDefaultCardStyleIfNeeded()
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
        guard VIPThemeSkinSupport.isSelectable(style) else { return }
        var status = PetDataManager.shared.status
        status.vipStatus.cardStyle = style
        PetDataManager.shared.saveStatus(status)
        reloadStatus()
    }

    var preferredVisualTheme: VIPVisualTheme {
        if isVIP {
            switch cardStyle {
            case .monicaPink, .themeSkinAdaptive:
                return .monicaPink
            case .blackGold, .skyConcertTheme, .swanDreamTheme:
                return .black
            }
        }
        return Self.versionDefaultCardStyle == .monicaPink ? .monicaPink : .deepBlue
    }

    private func applyVersionDefaultCardStyleIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.cardStyleMigrationKey) else { return }

        var status = PetDataManager.shared.status
        status.vipStatus.cardStyle = Self.versionDefaultCardStyle
        PetDataManager.shared.saveStatus(status)
        UserDefaults.standard.set(true, forKey: Self.cardStyleMigrationKey)
    }

    var availablePlans: [VIPPlan] {
        [
            VIPPlan(
                id: "monthly",
                title: "一个月".appLocalized,
                subtitle: "%d喵币".appLocalized(Self.monthlyPrice),
                months: 1,
                meowCoins: Self.monthlyPrice,
                badgeText: nil
            ),
            VIPPlan(
                id: "quarterly",
                title: "三个月".appLocalized,
                subtitle: "%d喵币".appLocalized(Self.quarterlyPrice),
                months: 3,
                meowCoins: Self.quarterlyPrice,
                badgeText: Self.quarterlyDiscountText
            )
        ]
    }
    
    // Exchange or extend VIP
    func purchaseVIP(months: Int = 1, costOverride: Int? = nil) -> (success: Bool, message: String) {
        var status = PetDataManager.shared.status
        
        let cost = costOverride ?? months * VIPManager.monthlyPrice
        
        if status.meowCoin < cost {
            return (false, "喵币不足，需要 %d 喵币".appLocalized(cost))
        }
        
        guard StoreManager.spendMeowCoins(cost, in: &status) else {
            return (false, "喵币不足，需要 %d 喵币".appLocalized(cost))
        }
        
        // Update VIP Status
        var newExpireDate: Date
        if let currentExpire = status.vipStatus.expireDate, currentExpire > Date() {
            // Extend existing
            newExpireDate = Calendar.current.date(byAdding: .month, value: months, to: currentExpire) ?? Date()
        } else {
            // New VIP activation
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
        
        return (true, "开通成功！有效期至 %@".appLocalized(Self.localizedDateText(newExpireDate)))
    }

    func purchaseVIP(plan: VIPPlan) -> (success: Bool, message: String) {
        purchaseVIP(months: plan.months, costOverride: plan.meowCoins)
    }

    func petShopPrice(for basePrice: Int) -> Int {
        guard isVIP else { return basePrice }
        return Self.discountedPrice(basePrice, rate: Self.petShopDiscountRate)
    }

    func petShopDiscountText(for basePrice: Int) -> String? {
        guard isVIP else { return nil }
        let discounted = petShopPrice(for: basePrice)
        guard discounted < basePrice else { return nil }
        return "\(basePrice) → \(discounted)"
    }

    static func discountedPrice(_ basePrice: Int, rate: Double) -> Int {
        max(1, Int((Double(basePrice) * rate).rounded()))
    }
    
    // MARK: - VIP试用期相关方法
    
    /// 是否可以显示试用期弹窗
    var canShowTrialOffer: Bool {
        let status = PetDataManager.shared.status
        return status.vipStatus.canShowTrialOffer
    }
    
    /// 是否正在试用期中
    var isInTrialPeriod: Bool {
        let status = PetDataManager.shared.status
        return status.vipStatus.isInTrialPeriod
    }
    
    /// 开始VIP试用期（3天）
    func startTrialPeriod() -> (success: Bool, message: String) {
        var status = PetDataManager.shared.status
        
        // 检查是否已使用过试用期
        guard !status.vipStatus.trialUsed else {
            return (false, "您已经使用过试用期了".appLocalized)
        }
        
        // 检查当前是否已经是VIP
        guard !status.vipStatus.isActive || status.vipStatus.isExpired else {
            return (false, "您已经是VIP会员了".appLocalized)
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // 设置试用期为3天
        guard let trialExpireDate = calendar.date(byAdding: .day, value: 3, to: now) else {
            return (false, "系统错误，请稍后重试".appLocalized)
        }
        
        // 更新VIP状态
        status.vipStatus.trialUsed = true
        status.vipStatus.trialStartDate = now
        status.vipStatus.trialExpireDate = trialExpireDate
        status.vipStatus.isActive = true
        status.vipStatus.expireDate = trialExpireDate
        
        // 生成VIP编号
        if status.vipStatus.vipNumber == nil {
            status.vipStatus.vipNumber = generateLuckyNumber()
        }
        
        // 保存
        PetDataManager.shared.saveStatus(status)
        
        // 更新本地状态
        reloadStatus()
        
        return (true, "试用期已开启！有效期至 %@".appLocalized(Self.localizedDateText(trialExpireDate, template: "MMMdd")))
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

    private static func localizedDateText(_ date: Date, template: String = "yMMMd") -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
