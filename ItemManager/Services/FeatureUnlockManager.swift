import Foundation
import SwiftUI
import Combine
import SwiftData

// MARK: - 解锁条件类型
enum UnlockConditionType: String, CaseIterable, Identifiable {
    case free = "free"                    // 免费，默认解锁
    case vip = "vip"                      // VIP 会员解锁
    case meowCoin = "meowCoin"            // 喵币解锁
    case clothingCount = "clothingCount"  // 衣物数量解锁
    case loginDays = "loginDays"          // 登录天数解锁
    case petLevel = "petLevel"            // 萌宠等级解锁
    case redeemCode = "redeemCode"        // 兑换码解锁（VIP界面输入）
    case manual = "manual"                // 手动控制（运营活动/限时开放）
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .free: return "免费"
        case .vip: return "VIP专属"
        case .meowCoin: return "喵币解锁"
        case .clothingCount: return "收集解锁"
        case .loginDays: return "签到解锁"
        case .petLevel: return "萌宠等级"
        case .redeemCode: return "兑换码解锁"
        case .manual: return "活动解锁"
        }
    }
    
    var icon: String {
        switch self {
        case .free: return "lock.open.fill"
        case .vip: return "crown.fill"
        case .meowCoin: return "dollarsign.circle.fill"
        case .clothingCount: return "tshirt.fill"
        case .loginDays: return "calendar.badge.clock"
        case .petLevel: return "pawprint.fill"
        case .redeemCode: return "key.fill"
        case .manual: return "sparkles"
        }
    }
}

// MARK: - 解锁条件配置
struct UnlockCondition: Codable, Equatable {
    var type: String           // UnlockConditionType.rawValue
    var requiredValue: Int     // 需要的数值（如喵币数量、衣物数量等）
    var description: String    // 解锁条件描述（展示给用户）
    
    static func free() -> UnlockCondition {
        UnlockCondition(type: "free", requiredValue: 0, description: "免费使用")
    }

    static func loginDays(_ days: Int) -> UnlockCondition {
        UnlockCondition(type: "loginDays", requiredValue: days, description: "累计登录 \(days) 天解锁")
    }
    
    static func vip() -> UnlockCondition {
        UnlockCondition(type: "vip", requiredValue: 0, description: "开通VIP即可解锁")
    }
    
    static func meowCoin(_ amount: Int) -> UnlockCondition {
        UnlockCondition(type: "meowCoin", requiredValue: amount, description: "消耗 \(amount) 喵币解锁")
    }
    
    static func clothingCount(_ count: Int) -> UnlockCondition {
        UnlockCondition(type: "clothingCount", requiredValue: count, description: "收集 \(count) 件衣物解锁")
    }
 
    
    static func petLevel(_ level: Int) -> UnlockCondition {
        UnlockCondition(type: "petLevel", requiredValue: level, description: "萌宠达到 \(level) 级解锁")
    }
    
    static func manual(description: String) -> UnlockCondition {
        UnlockCondition(type: "manual", requiredValue: 0, description: description)
    }
    
    static func redeemCode(_ code: String, description: String) -> UnlockCondition {
        UnlockCondition(type: "redeemCode", requiredValue: 0, description: description)
    }
}

// MARK: - 业务系统/功能项定义
enum FeatureItem: String, CaseIterable, Identifiable {
    // 核心功能（默认解锁）
    case wardrobe = "wardrobe"
    case finalPayment = "finalPayment"
    
    // House 功能
    case pet = "pet"
    case ootd = "ootd"
    case ootdDefaultBook = "ootdDefaultBook"
    case wealth = "wealth"
    case calendar = "calendar"
    case bigWorld = "bigWorld"
    case perler = "perler"
    case recycleBin = "recycleBin"
    case dressStock = "dressStock"
    
    // 设置中的子功能
    case dataBackup = "dataBackup"
    case cloudSync = "cloudSync"
    case batchImport = "batchImport"
    case themeCustomize = "themeCustomize"
    case widgetCustomize = "widgetCustomize"
    case aiAnalysis = "aiAnalysis"
    
    // 联网功能
    case networkCommunity = "networkCommunity"
    
    // 魔法任务
    case magicTasks = "magicTasks"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .wardrobe: return "少女衣橱"
        case .finalPayment: return "心愿尾款"
        case .pet: return "萌宠"
        case .ootd: return "穿搭手帐"
        case .ootdDefaultBook: return "魔法贴纸"
        case .wealth: return "来财"
        case .calendar: return "梦裙日历"
        case .bigWorld: return "世界书"
        case .perler: return "拼豆工坊"
        case .recycleBin: return "回收站"
        case .dressStock: return "裙装股市"
        case .dataBackup: return "数据备份"
        case .cloudSync: return "iCloud同步"
        case .batchImport: return "批量导入"
        case .themeCustomize: return "魔法配色"
        case .widgetCustomize: return "小组件定制"
        case .aiAnalysis:
            return "AI智能分析"
        case .networkCommunity:
            return "联网社区"
        case .magicTasks:
            return "魔法任务"
        }
    }
    
    var icon: String {
        switch self {
        case .wardrobe: return "cabinet.fill"
        case .finalPayment: return "tag.fill"
        case .pet: return "pawprint.fill"
        case .ootd: return "book.closed.fill"
        case .ootdDefaultBook: return "book.pages.fill"
        case .wealth: return "yensign.circle.fill"
        case .calendar: return "calendar"
        case .bigWorld: return "globe.asia.australia"
        case .perler: return "circle.grid.2x2.fill"
        case .recycleBin: return "trash.fill"
        case .dressStock: return "chart.line.uptrend.xyaxis"
        case .dataBackup: return "arrow.clockwise.icloud.fill"
        case .cloudSync: return "icloud.fill"
        case .batchImport: return "square.and.arrow.down.on.square.fill"
        case .themeCustomize: return "paintpalette.fill"
        case .widgetCustomize: return "rectangle.grid.2x2.fill"
        case .aiAnalysis:
            return "brain.fill"
        case .networkCommunity:
            return "network"
        case .magicTasks:
            return "sparkles"
        }
    }
    
    // 默认解锁条件配置
    var defaultCondition: UnlockCondition {
        switch self {
        case .wardrobe, .finalPayment, .recycleBin:
            return .free()
        case .pet:
            // 萌宠：在VIP界面兑换码输入 "vip萌宠" 解锁
            return .redeemCode("vip萌宠", description: "仍在认真开发和内测中，敬请期待～")
        case .ootd:
            return .clothingCount(5)
        case .ootdDefaultBook:
            return .clothingCount(3)
        case .wealth:
            return .loginDays(3)
        case .calendar:
            return .clothingCount(10)
        case .bigWorld:
            // 世界书：在VIP界面兑换码输入 "vip世界书" 解锁
            return .redeemCode("vip世界书", description: "仍在认真开发和内测中，敬请期待～")
        case .perler:
            // 拼豆工坊：在VIP界面兑换码输入 "vip拼豆工坊" 解锁
            return .redeemCode("vip拼豆工坊", description: "仍在认真开发和内测中，敬请期待～")
        case .dressStock:
            // 裙装股市：在VIP界面兑换码输入 "vip裙装股市" 解锁
            return .redeemCode("vip裙装股市", description: "仍在认真开发和内测中，敬请期待～")
        case .dataBackup, .cloudSync:
            return .free()
        case .batchImport:
            return .clothingCount(1)
        case .themeCustomize:
            return .meowCoin(50)
        case .widgetCustomize:
            return .loginDays(7)
        case .aiAnalysis:
            return .vip()
        case .networkCommunity:
            // 联网设置：在VIP界面兑换码输入 "vip联网" 解锁
            return .redeemCode("vip联网", description: "仍在认真开发和内测中，敬请期待～")
        case .magicTasks:
            // 魔法任务：在VIP界面兑换码输入 "vip魔法任务" 解锁
            return .redeemCode("vip魔法任务", description: "仍在认真开发和内测中，敬请期待～")
        }
    }
    
    // 是否默认隐藏
    var isHiddenByDefault: Bool {
        switch self {
        case .pet, .bigWorld, .perler, .dressStock, .networkCommunity, .magicTasks:
            return true // 萌宠、世界书、拼豆工坊、裙装股市、联网社区、魔法任务默认隐藏
        default:
            return false
        }
    }
    
    // 映射到 SmallWorldDestination
    var destination: SmallWorldDestination? {
        switch self {
        case .wardrobe: return .wardrobe
        case .finalPayment: return .depositPlan
        case .pet: return .pet
        case .ootd: return .ootd
        case .ootdDefaultBook: return .ootdDefaultBook
        case .wealth: return .wealth(nil)
        case .calendar: return .calendar
        case .bigWorld: return .bigWorld
        case .perler: return .perler
        case .recycleBin: return .recycleBin
        case .dressStock: return .dressStock
        default: return nil
        }
    }
    
    /// 是否是设置中的子功能
    var isSettingsFeature: Bool {
        switch self {
        case .dataBackup, .cloudSync, .batchImport, .themeCustomize, .widgetCustomize, .aiAnalysis:
            return true
        default:
            return false
        }
    }
}

// MARK: - 功能项状态（持久化存储）
struct FeatureStatus: Codable {
    var isUnlocked: Bool       // 是否已解锁
    var isVisible: Bool        // 是否显示（可以解锁但不显示）
    var unlockedAt: Date?      // 解锁时间
    var unlockedBy: String?    // 解锁方式（用户手动/自动达成等）
}

// MARK: - 解锁结果
enum UnlockResult {
    case success               // 解锁成功
    case alreadyUnlocked       // 已经解锁
    case conditionNotMet(String) // 条件未满足，附带提示信息
    case insufficientResource(String, Int, Int) // 资源不足（类型、需要、当前）
}

// MARK: - 功能解锁管理器
final class FeatureUnlockManager: ObservableObject {
    static let shared = FeatureUnlockManager()
    
    // 发布状态供UI绑定
    @Published private(set) var featureStatuses: [String: FeatureStatus] = [:]
    @Published private(set) var unlockConditions: [String: UnlockCondition] = [:]
    
    // UserDefaults Keys
    private let statusKey = "featureUnlock.statuses"
    private let conditionKey = "featureUnlock.conditions"
    
    // 通知名称
    static let featureUnlockedNotification = Notification.Name("FeatureUnlocked")
    static let featureStatusChangedNotification = Notification.Name("FeatureStatusChanged")
    
    private init() {
        loadData()
        setupDefaultConditions()
    }
    
    // MARK: - 从磁盘重新加载（用于备份恢复后）
    func reloadFromDisk() {
        print("🔄 FeatureUnlockManager: Reloading from disk...")
        loadData()
        // 重新设置默认条件（如果有新功能）
        setupDefaultConditions()
        // 通知UI更新
        objectWillChange.send()
        print("✅ FeatureUnlockManager: Reload complete")
    }
    
    // MARK: - 数据持久化
    private func loadData() {
        // 加载状态
        if let data = UserDefaults.standard.data(forKey: statusKey),
           let decoded = try? JSONDecoder().decode([String: FeatureStatus].self, from: data) {
            featureStatuses = decoded
        }
        
        // 加载条件配置
        if let data = UserDefaults.standard.data(forKey: conditionKey),
           let decoded = try? JSONDecoder().decode([String: UnlockCondition].self, from: data) {
            unlockConditions = decoded
        }
    }
    
    private func saveStatuses() {
        if let encoded = try? JSONEncoder().encode(featureStatuses) {
            UserDefaults.standard.set(encoded, forKey: statusKey)
        }
    }
    
    private func saveConditions() {
        if let encoded = try? JSONEncoder().encode(unlockConditions) {
            UserDefaults.standard.set(encoded, forKey: conditionKey)
        }
    }
    
    // MARK: - 初始化默认条件
    private func setupDefaultConditions() {
        for feature in FeatureItem.allCases {
            // 设置默认解锁条件
            let defaultCondition = feature.defaultCondition
            if unlockConditions[feature.rawValue] == nil {
                unlockConditions[feature.rawValue] = defaultCondition
            } else if defaultCondition.type == UnlockConditionType.redeemCode.rawValue {
                // 对于兑换码解锁的功能，强制更新描述文字（用于文案调整）
                unlockConditions[feature.rawValue] = defaultCondition
            }
            
            // 设置默认显示状态（首次安装时）
            if featureStatuses[feature.rawValue] == nil {
                var status = FeatureStatus(
                    isUnlocked: false,
                    isVisible: !feature.isHiddenByDefault, // 默认隐藏指定功能
                    unlockedAt: nil,
                    unlockedBy: nil
                )
                
                // 免费功能默认解锁
                let condition = unlockConditions[feature.rawValue] ?? defaultCondition
                if condition.type == UnlockConditionType.free.rawValue {
                    status.isUnlocked = true
                }
                
                featureStatuses[feature.rawValue] = status
            }
        }
        saveConditions()
        saveStatuses()
    }
    
    // MARK: - 查询方法
    
    /// 获取功能项的解锁条件
    func getCondition(for feature: FeatureItem) -> UnlockCondition {
        return unlockConditions[feature.rawValue] ?? feature.defaultCondition
    }
    
    /// 更新解锁条件（用于动态调整）
    func updateCondition(for feature: FeatureItem, condition: UnlockCondition) {
        unlockConditions[feature.rawValue] = condition
        saveConditions()
    }
    
    /// 获取功能项当前状态
    func getStatus(for feature: FeatureItem) -> FeatureStatus {
        return featureStatuses[feature.rawValue] ?? FeatureStatus(
            isUnlocked: false,
            isVisible: true,
            unlockedAt: nil,
            unlockedBy: nil
        )
    }
    
    /// 是否已解锁
    func isUnlocked(_ feature: FeatureItem) -> Bool {
        // 免费功能直接返回true
        let condition = getCondition(for: feature)
        if condition.type == UnlockConditionType.free.rawValue {
            return true
        }
        return getStatus(for: feature).isUnlocked
    }
    
    /// 是否显示
    func isVisible(_ feature: FeatureItem) -> Bool {
        let status = getStatus(for: feature)
        return status.isVisible
    }
    
    /// 是否可以访问（已解锁且显示）
    func canAccess(_ feature: FeatureItem) -> Bool {
        return isUnlocked(feature) && isVisible(feature)
    }
    
    // MARK: - 解锁检查
    
    /// 检查是否满足解锁条件
    func checkUnlockCondition(_ feature: FeatureItem) -> (met: Bool, message: String?) {
        let condition = getCondition(for: feature)
        
        // 免费直接通过
        if condition.type == UnlockConditionType.free.rawValue {
            return (true, nil)
        }
        
        // 已解锁直接通过
        if isUnlocked(feature) {
            return (true, nil)
        }
        
        guard let conditionType = UnlockConditionType(rawValue: condition.type) else {
            return (false, "未知的解锁条件")
        }
        
        switch conditionType {
        case .free:
            return (true, nil)
            
        case .vip:
            let isVIP = VIPManager.shared.isVIP
            return (isVIP, isVIP ? nil : condition.description)
            
        case .meowCoin:
            let currentCoins = PetDataManager.shared.status.meowCoin
            let met = currentCoins >= condition.requiredValue
            return (met, met ? nil : "当前喵币: \(currentCoins)/\(condition.requiredValue)")
            
        case .clothingCount:
            // 需要通过外部传入或从数据库查询
            let currentCount = getClothingCount()
            let met = currentCount >= condition.requiredValue
            return (met, met ? nil : "当前衣物: \(currentCount)/\(condition.requiredValue)")
            
        case .loginDays:
            let currentDays = getLoginDays()
            let met = currentDays >= condition.requiredValue
            return (met, met ? nil : "累计登录: \(currentDays)/\(condition.requiredValue) 天")
            
        case .petLevel:
            // 萌宠等级暂时返回0，因为PetStatus没有level属性
            let currentLevel = 0
            let met = currentLevel >= condition.requiredValue
            return (met, met ? nil : "萌宠等级: \(currentLevel)/\(condition.requiredValue)")
            
        case .manual:
            // 手动控制，默认不满足
            return (false, condition.description)
            
        case .redeemCode:
            // 兑换码解锁，需要在VIP界面输入正确兑换码
            // 这里返回false，实际解锁逻辑在 redeemCode 方法中处理
            return (false, condition.description)
        }
    }
    
    // MARK: - 解锁操作
    
    /// 尝试解锁功能
    func unlock(_ feature: FeatureItem, force: Bool = false) -> UnlockResult {
        // 已解锁
        if isUnlocked(feature) {
            return .alreadyUnlocked
        }
        
        let condition = getCondition(for: feature)
        
        // 免费直接解锁
        if condition.type == UnlockConditionType.free.rawValue {
            performUnlock(feature, by: "free")
            return .success
        }
        
        // 强制解锁（用于测试或运营活动）
        if force {
            performUnlock(feature, by: "force")
            return .success
        }
        
        // 检查条件
        let check = checkUnlockCondition(feature)
        if !check.met {
            return .conditionNotMet(check.message ?? condition.description)
        }
        
        // 检查是否需要消耗资源
        guard let conditionType = UnlockConditionType(rawValue: condition.type) else {
            return .conditionNotMet("未知的解锁条件")
        }
        
        // 需要消耗喵币的，执行扣除
        if conditionType == .meowCoin {
            let currentCoins = PetDataManager.shared.status.meowCoin
            if currentCoins < condition.requiredValue {
                return .insufficientResource("喵币", condition.requiredValue, currentCoins)
            }
            
            // 扣除喵币
            var status = PetDataManager.shared.status
            status.meowCoin -= condition.requiredValue
            PetDataManager.shared.saveStatus(status)
        }
        
        performUnlock(feature, by: condition.type)
        return .success
    }
    
    /// 执行解锁
    private func performUnlock(_ feature: FeatureItem, by: String) {
        var status = getStatus(for: feature)
        status.isUnlocked = true
        status.unlockedAt = Date()
        status.unlockedBy = by
        
        featureStatuses[feature.rawValue] = status
        saveStatuses()
        
        // 发送通知
        NotificationCenter.default.post(
            name: Self.featureUnlockedNotification,
            object: nil,
            userInfo: ["feature": feature.rawValue]
        )
        NotificationCenter.default.post(
            name: Self.featureStatusChangedNotification,
            object: nil,
            userInfo: ["feature": feature.rawValue]
        )
        
        // 添加到常驻任务完成提示（在主线程）
        // 使用卡片堆叠方式显示，不再显示大卡片弹窗
        DispatchQueue.main.async {
            MagicTaskCompletionManager.shared.addCompletion(feature: feature)
        }
    }
    
    // MARK: - 显示控制
    
    /// 设置功能是否显示
    func setVisible(_ feature: FeatureItem, visible: Bool) {
        var status = getStatus(for: feature)
        status.isVisible = visible
        featureStatuses[feature.rawValue] = status
        saveStatuses()
        
        NotificationCenter.default.post(
            name: Self.featureStatusChangedNotification,
            object: nil,
            userInfo: ["feature": feature.rawValue]
        )
    }
    
    /// 锁定功能（重置解锁状态）
    func lock(_ feature: FeatureItem) {
        var status = getStatus(for: feature)
        status.isUnlocked = false
        status.unlockedAt = nil
        status.unlockedBy = nil
        featureStatuses[feature.rawValue] = status
        saveStatuses()
        
        NotificationCenter.default.post(
            name: Self.featureStatusChangedNotification,
            object: nil,
            userInfo: ["feature": feature.rawValue]
        )
    }
    
    // MARK: - 辅助方法
    
    /// 获取所有可见的功能（用于菜单显示）
    func getVisibleFeatures() -> [FeatureItem] {
        return FeatureItem.allCases.filter { isVisible($0) }
    }
    
    /// 获取所有已解锁的功能
    func getUnlockedFeatures() -> [FeatureItem] {
        return FeatureItem.allCases.filter { isUnlocked($0) }
    }
    
    /// 获取所有可访问的功能（已解锁且显示）
    func getAccessibleFeatures() -> [FeatureItem] {
        return FeatureItem.allCases.filter { canAccess($0) }
    }
    
    /// 获取需要解锁的功能列表（用于设置页面展示）
    func getLockableFeatures() -> [FeatureItem] {
        return FeatureItem.allCases.filter {
            let condition = getCondition(for: $0)
            // 免费功能和兑换码功能不在魔法任务界面显示
            // 兑换码功能需要在VIP界面输入兑换码解锁
            return condition.type != UnlockConditionType.free.rawValue &&
                   condition.type != UnlockConditionType.redeemCode.rawValue
        }
    }
    
    // MARK: - 数据获取（需要接入实际数据源）
    
    private func getClothingCount() -> Int {
        // 这里需要从 Clothing 数据获取
        // 暂时返回一个模拟值，实际使用时需要传入 ModelContext 查询
        return UserDefaults.standard.integer(forKey: "clothingCount_cache")
    }
    
    private func getLoginDays() -> Int {
        // 从登录记录获取
        return UserDefaults.standard.integer(forKey: "loginDays")
    }
    
    /// 更新衣物数量缓存
    func updateClothingCount(_ count: Int) {
        // 检查更新前是否有满足条件的任务
        let previouslyUnlockableFeatures = getUnlockableFeatures()
        
        UserDefaults.standard.set(count, forKey: "clothingCount_cache")
        
        // 更新后再次检查，找出新达到可解锁状态的任务
        let currentlyUnlockableFeatures = getUnlockableFeatures()
        let newlyUnlockableFeatures = currentlyUnlockableFeatures.filter { !previouslyUnlockableFeatures.contains($0) }
        
        // 显示可解锁提示
        for feature in newlyUnlockableFeatures {
            print("🔓 新达到可解锁状态: \(feature.displayName)")
            DispatchQueue.main.async {
                MagicTaskCompletionManager.shared.addUnlockable(feature: feature)
            }
        }
    }
    
    /// 获取当前可解锁的功能列表（满足条件但未解锁）
    func getUnlockableFeatures() -> [FeatureItem] {
        return getLockableFeatures().filter { feature in
            guard !isUnlocked(feature) else { return false }
            let check = checkUnlockCondition(feature)
            return check.met
        }
    }
    
    /// 更新登录天数
    func updateLoginDays(_ days: Int) {
        UserDefaults.standard.set(days, forKey: "loginDays")
    }
    
    // MARK: - 兑换码解锁
    
    /// 验证兑换码并解锁对应功能
    /// - Parameter code: 用户输入的兑换码
    /// - Returns: (是否成功, 解锁的功能, 提示信息)
    func redeemCode(_ code: String) -> (success: Bool, feature: FeatureItem?, message: String) {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 定义兑换码与功能的映射
        let codeMapping: [String: FeatureItem] = [
            "vip萌宠": .pet,
            "vip世界书": .bigWorld,
            "vip拼豆工坊": .perler,
            "vip裙装股市": .dressStock,
            "vip联网": .networkCommunity,
            "vip魔法任务": .magicTasks
        ]

        // 查找对应的功能
        guard let feature = codeMapping[trimmedCode] else {
            return (false, nil, "兑换码无效，请检查后重试")
        }

        // 检查是否已解锁
        if isUnlocked(feature) {
            return (false, feature, "\(feature.displayName) 已经解锁了")
        }

        // 执行解锁
        performUnlock(feature, by: "redeemCode:\(trimmedCode)")

        // 解锁后自动显示
        setVisible(feature, visible: true)

        return (true, feature, "\(feature.displayName) 解锁成功！")
    }

    /// 获取所有兑换码解锁的功能列表
    func getRedeemCodeFeatures() -> [FeatureItem] {
        return [.pet, .bigWorld, .perler, .dressStock, .networkCommunity, .magicTasks]
    }
    
    // MARK: - 启动时刷新进度
    
    /// 刷新所有魔法任务的进度数据
    /// 在App启动时调用，用于更新衣物数量、登录天数等数据
    func refreshMagicTaskProgress(modelContext: ModelContext? = nil) {
        print("🔄 开始刷新魔法任务进度...")
        
        // 1. 更新衣物数量
        if let context = modelContext {
            let clothingCount = fetchClothingCount(from: context)
            updateClothingCount(clothingCount)
            print("👗 衣物数量已更新: \(clothingCount)")
        }
        
        // 2. 更新登录天数（这里可以接入实际的登录记录）
        // 暂时保持现有逻辑
        
        // 3. 检查所有未解锁的功能，看是否满足条件并自动解锁
        checkAndAutoUnlockFeatures()
        
        print("✅ 魔法任务进度刷新完成")
    }
    
    /// 从数据库获取衣物数量（排除已删除的）
    private func fetchClothingCount(from context: ModelContext) -> Int {
        do {
            // 只统计未删除的衣物
            let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.isDeleted == false })
            let count = try context.fetchCount(descriptor)
            return count
        } catch {
            print("❌ 获取衣物数量失败: \(error)")
            return UserDefaults.standard.integer(forKey: "clothingCount_cache")
        }
    }
    
    /// 检查并自动解锁满足条件的功能
    private func checkAndAutoUnlockFeatures() {
        let lockableFeatures = getLockableFeatures()
        
        for feature in lockableFeatures {
            // 跳过已解锁的功能
            guard !isUnlocked(feature) else { continue }
            
            // 跳过兑换码解锁的功能（需要手动输入兑换码）
            let condition = getCondition(for: feature)
            guard condition.type != UnlockConditionType.redeemCode.rawValue else { continue }
            
            // 检查是否满足解锁条件
            let check = checkUnlockCondition(feature)
            
            if check.met {
                print("🎉 自动解锁功能: \(feature.displayName)")
                _ = unlock(feature)
            }
        }
    }
}

// MARK: - 解锁提示弹窗
struct FeatureUnlockAlert: Identifiable {
    let id = UUID()
    let feature: FeatureItem
    let condition: UnlockCondition
    let canUnlock: Bool
    let message: String?
}

// MARK: - SmallWorldDestination 扩展
extension SmallWorldDestination {
    /// 映射到对应的功能项
    var featureItem: FeatureItem? {
        switch self {
        case .wardrobe: return .wardrobe
        case .depositPlan: return .finalPayment
        case .pet: return .pet
        case .ootd: return .ootd
        case .ootdDefaultBook: return .ootdDefaultBook
        case .wealth(_): return .wealth
        case .calendar: return .calendar
        case .bigWorld: return .bigWorld
        case .perler: return .perler
        case .recycleBin: return .recycleBin
        case .dressStock: return .dressStock
        case .menu: return nil
        }
    }
    
    /// 检查该目的地是否已解锁
    var isUnlocked: Bool {
        guard let feature = featureItem else { return true }
        return FeatureUnlockManager.shared.isUnlocked(feature)
    }
    
    /// 检查该目的地是否可见
    var isVisible: Bool {
        guard let feature = featureItem else { return true }
        return FeatureUnlockManager.shared.isVisible(feature)
    }
    
    /// 检查该目的地是否可以访问
    var canAccess: Bool {
        guard let feature = featureItem else { return true }
        return FeatureUnlockManager.shared.canAccess(feature)
    }
}

// MARK: - View 扩展
extension View {
    /// 根据功能解锁状态条件显示
    @ViewBuilder
    func featureVisible(_ feature: FeatureItem) -> some View {
        if FeatureUnlockManager.shared.isVisible(feature) {
            self
        }
    }
    
    /// 根据功能可访问状态条件显示
    @ViewBuilder
    func featureAccessible(_ feature: FeatureItem) -> some View {
        if FeatureUnlockManager.shared.canAccess(feature) {
            self
        }
    }
}

// MARK: - 解锁按钮组件
struct FeatureUnlockButton: View {
    let feature: FeatureItem
    let action: () -> Void
    
    @StateObject private var manager = FeatureUnlockManager.shared
    @State private var showAlert = false
    @State private var alertItem: FeatureUnlockAlert?
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            content
        }
        .alert(item: $alertItem) { alert in
            if alert.canUnlock {
                return Alert(
                    title: Text("解锁 \(alert.feature.displayName)"),
                    message: Text("\(alert.condition.description)\n\n确定要解锁吗？"),
                    primaryButton: .default(Text("解锁")) {
                        unlockFeature()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            } else {
                return Alert(
                    title: Text("尚未满足解锁条件"),
                    message: Text(alert.message ?? alert.condition.description),
                    dismissButton: .default(Text("知道了"))
                )
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        let isUnlocked = manager.isUnlocked(feature)
        let condition = manager.getCondition(for: feature)
        
        HStack {
            Image(systemName: feature.icon)
                .foregroundColor(isUnlocked ? .pink : .gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.system(size: 16, weight: isUnlocked ? .medium : .regular))
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                
                if !isUnlocked {
                    Text(condition.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func handleTap() {
        let isUnlocked = manager.isUnlocked(feature)
        
        if isUnlocked {
            // 已解锁，直接执行操作
            action()
        } else {
            // 未解锁，检查条件并显示提示
            let check = manager.checkUnlockCondition(feature)
            let condition = manager.getCondition(for: feature)
            alertItem = FeatureUnlockAlert(
                feature: feature,
                condition: condition,
                canUnlock: check.met,
                message: check.message
            )
        }
    }
    
    private func unlockFeature() {
        let result = manager.unlock(feature)
        
        switch result {
        case .success:
            action()
        case .alreadyUnlocked:
            action()
        case .conditionNotMet(let message):
            // 条件不满足，显示提示
            print("解锁失败: \(message)")
        case .insufficientResource(let type, let required, let current):
            print("\(type)不足，需要\(required)，当前\(current)")
        }
    }
}

// MARK: - 功能项行组件（用于设置等列表）
struct FeatureRow: View {
    let feature: FeatureItem
    var showLockStatus: Bool = true
    var action: (() -> Void)?
    
    @StateObject private var manager = FeatureUnlockManager.shared
    
    var body: some View {
        HStack {
            Image(systemName: feature.icon)
                .frame(width: 24)
                .foregroundColor(iconColor)
            
            Text(feature.displayName)
                .foregroundColor(textColor)
            
            Spacer()
            
            if showLockStatus {
                lockStatusView
            }
            
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
    
    private var iconColor: Color {
        if manager.canAccess(feature) {
            return .pink
        } else if manager.isUnlocked(feature) {
            return .gray // 已解锁但不显示
        } else {
            return .gray
        }
    }
    
    private var textColor: Color {
        if manager.canAccess(feature) {
            return .primary
        } else {
            return .secondary
        }
    }
    
    @ViewBuilder
    private var lockStatusView: some View {
        let isUnlocked = manager.isUnlocked(feature)
        let isVisible = manager.isVisible(feature)
        
        if isUnlocked && !isVisible {
            // 已解锁但不显示
            Text("已隐藏")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        } else if !isUnlocked {
            let condition = manager.getCondition(for: feature)
            HStack(spacing: 4) {
                Image(systemName: conditionIcon(for: condition))
                    .font(.caption)
                Text(conditionShortText(for: condition))
                    .font(.caption)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)
        }
    }
    
    private func conditionIcon(for condition: UnlockCondition) -> String {
        guard let type = UnlockConditionType(rawValue: condition.type) else {
            return "lock.fill"
        }
        return type.icon
    }
    
    private func conditionShortText(for condition: UnlockCondition) -> String {
        guard let type = UnlockConditionType(rawValue: condition.type) else {
            return "锁定"
        }
        
        switch type {
        case .free:
            return "免费"
        case .vip:
            return "VIP"
        case .meowCoin:
            return "\(condition.requiredValue)币"
        case .clothingCount:
            return "\(condition.requiredValue)件"
        case .loginDays:
            return "\(condition.requiredValue)天"
        case .petLevel:
            return "Lv.\(condition.requiredValue)"
        case .manual:
            return "活动"
        case .redeemCode:
            return "兑换码"
        }
    }
}
