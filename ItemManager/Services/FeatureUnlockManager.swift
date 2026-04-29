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
    case redeemCode = "redeemCode"        // 兼容历史数据
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
        case .redeemCode: return "限时开放"
        case .manual: return "体验完成任务"
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
        case .redeemCode: return "sparkles"
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
        UnlockCondition(type: "meowCoin", requiredValue: amount, description: "累计消费 \(amount) 喵币后解锁")
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
    case customColorPersonalization = "customColorPersonalization"

    // 筛选功能
    case filterClassic = "filterClassic"  // 经典筛选/多维筛选
    case privacyDisplay = "privacyDisplay" // 隐私显示
    case tagBrandFieldDisplay = "tagBrandFieldDisplay" // 标签/品牌/裙装属性管理
    case spaceBook = "spaceBook"  // 空间手帐
    case batchEdit = "batchEdit"  // 批量编辑
    case localFileBackupRestore = "localFileBackupRestore" // 本地文件的备份与恢复
    case exportCSV = "exportCSV" // 导出表格
    case cloudFileBackupRestore = "cloudFileBackupRestore" // 云端的文件备份与恢复

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
            return "萌宠智能对话"
        case .customColorPersonalization:
            return "客制化配色和个性化"
        case .networkCommunity:
            return "联网社区"
        case .magicTasks:
            return "魔法任务"
        case .filterClassic:
            return "个性化偏好"
        case .privacyDisplay:
            return "隐私显示"
        case .tagBrandFieldDisplay:
            return "标签/品牌/裙装属性管理"
        case .spaceBook:
            return "空间手帐"
        case .batchEdit:
            return "批量编辑"
        case .localFileBackupRestore:
            return "本地文件的备份与恢复"
        case .exportCSV:
            return "导出表格"
        case .cloudFileBackupRestore:
            return "云端的文件备份与恢复"
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
            return "bubble.left.and.bubble.right.fill"
        case .customColorPersonalization:
            return "paintpalette"
        case .networkCommunity:
            return "network"
        case .magicTasks:
            return "sparkles"
        case .filterClassic:
            return "line.3.horizontal.decrease.circle.fill"
        case .privacyDisplay:
            return "eye.slash.circle.fill"
        case .tagBrandFieldDisplay:
            return "tag.circle.fill"
        case .spaceBook:
            return "cube.transparent.fill"
        case .batchEdit:
            return "square.and.pencil"
        case .localFileBackupRestore:
            return "externaldrive.badge.checkmark"
        case .exportCSV:
            return "tablecells"
        case .cloudFileBackupRestore:
            return "arrow.triangle.2.circlepath.icloud"
        }
    }

    // 默认解锁条件配置
    var defaultCondition: UnlockCondition {
        switch self {
        case .wardrobe, .finalPayment, .recycleBin:
            return .free()
        case .pet:
            // 萌宠默认开启
            return .free()
        case .ootd:
            return .clothingCount(5)
        case .ootdDefaultBook:
            return .clothingCount(3)
        case .wealth:
            return .loginDays(2)
        case .calendar:
            return .clothingCount(10)
        case .bigWorld:
            return .manual(description: "仍在认真开发和内测中，敬请期待～")
        case .perler:
            return .manual(description: "仍在认真开发和内测中，敬请期待～")
        case .dressStock:
            return .manual(description: "仍在认真开发和内测中，敬请期待～")
        case .dataBackup, .cloudSync:
            return .free()
        case .batchImport:
            return .clothingCount(1)
        case .themeCustomize:
            return .meowCoin(50)
        case .widgetCustomize:
            return .loginDays(3)
        case .aiAnalysis:
            return .vip()
        case .customColorPersonalization:
            return .manual(description: "体验客制化配色和个性化功能")
        case .networkCommunity:
            return .manual(description: "功能暂未开放，敬请期待～")
        case .magicTasks:
            return .free()
        case .filterClassic:
            return .manual(description: "体验个性化偏好功能")
        case .privacyDisplay:
            return .manual(description: "体验隐私显示功能")
        case .tagBrandFieldDisplay:
            return .manual(description: "体验标签、品牌与裙装属性管理")
        case .spaceBook:
            return .manual(description: "创建一个穿搭手账以及手账书页")
        case .batchEdit:
            return .manual(description: "体验批量编辑功能")
        case .localFileBackupRestore:
            return .manual(description: "体验本地文件的备份与恢复")
        case .exportCSV:
            return .manual(description: "体验导出到 CSV 功能")
        case .cloudFileBackupRestore:
            return .manual(description: "体验云端的文件备份与恢复与 iCloud 同步")
        }
    }

    // 是否默认隐藏
    var isHiddenByDefault: Bool {
        switch self {
        case .bigWorld, .perler, .dressStock:
            return true // 世界书、拼豆工坊、裙装股市默认隐藏
        case .networkCommunity:
            return true
        case .magicTasks:
            return false
        case .filterClassic, .privacyDisplay, .tagBrandFieldDisplay, .spaceBook, .batchEdit, .localFileBackupRestore, .exportCSV, .cloudFileBackupRestore, .customColorPersonalization:
            return false  // 这些功能默认显示，作为魔法任务可获取鱼币
        default:
            return false
        }
    }

    var isPublicUnlockTask: Bool {
        switch self {
        case .bigWorld, .perler, .dressStock, .networkCommunity:
            return false
        default:
            return true
        }
    }

    var isComingSoonFeature: Bool {
        switch self {
        case .bigWorld, .perler, .dressStock, .networkCommunity:
            return true
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
        case .dataBackup, .cloudSync, .batchImport, .themeCustomize, .widgetCustomize, .aiAnalysis, .localFileBackupRestore, .exportCSV, .cloudFileBackupRestore, .customColorPersonalization:
            return true
        default:
            return false
        }
    }

    /// 体验任务引导步数（用于鱼币奖励分档）
    var experienceGuideStepCount: Int? {
        switch self {
        case .filterClassic:
            return 5
        case .privacyDisplay:
            return 4
        case .tagBrandFieldDisplay:
            return 6
        case .spaceBook:
            return 7
        case .batchEdit:
            return 4
        case .localFileBackupRestore:
            return 4
        case .exportCSV:
            return 4
        case .cloudFileBackupRestore:
            return 5
        case .customColorPersonalization:
            return 5
        default:
            return nil
        }
    }

    /// 体验任务鱼币奖励：按引导步数分档
    var experienceFishCoinReward: Int? {
        guard let stepCount = experienceGuideStepCount else { return nil }
        switch stepCount {
        case ...2:
            return 66
        case 3...4:
            return 88
        case 5:
            return 100
        case 6:
            return 200
        case 7:
            return 300
        default:
            return 500
        }
    }
}

// MARK: - 统一功能跳转路由（魔法任务/完成提示复用）
extension FeatureItem {
    /// 发送跳转通知：保持“任务完成卡片”与“魔法任务详情页”前往行为一致。
    func postNavigationFromMagicTask() {
        if let destination = destination {
            NotificationCenter.default.post(
                name: .navigateToSmallWorldDestination,
                object: nil,
                userInfo: ["destination": destination]
            )
        } else if self == .batchImport {
            NotificationCenter.default.post(
                name: .navigateToHomeTab,
                object: nil,
                userInfo: ["homeTab": "wardrobe"]
            )
        } else if self == .aiAnalysis {
            NotificationCenter.default.post(
                name: .navigateToPetChat,
                object: nil
            )
        } else if isSettingsFeature {
            NotificationCenter.default.post(
                name: .navigateToSettings,
                object: nil,
                userInfo: ["feature": rawValue]
            )
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
            } else if feature == .pet {
                // 萌宠改为默认开启：兼容历史用户旧配置
                unlockConditions[feature.rawValue] = defaultCondition
            } else if feature == .themeCustomize {
                // 魔法配色的喵币任务改为“累计消费”，强制覆盖旧版本的即时扣费文案/配置
                unlockConditions[feature.rawValue] = defaultCondition
            } else if [.bigWorld, .perler, .dressStock, .networkCommunity, .magicTasks].contains(feature) {
                // 对已下线/调整为正式能力的功能，强制覆盖历史条件配置
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

            if feature == .pet {
                var petStatus = getStatus(for: .pet)
                if !petStatus.isUnlocked {
                    petStatus.unlockedAt = petStatus.unlockedAt ?? Date()
                    petStatus.unlockedBy = petStatus.unlockedBy ?? "free"
                }
                petStatus.isUnlocked = true
                petStatus.isVisible = true
                featureStatuses[feature.rawValue] = petStatus
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

    /// 用于“VIP 期间临时开放，但已单独解锁时仍保持永久可用”的权益桥接。
    func hasEffectiveAccess(_ feature: FeatureItem) -> Bool {
        if isUnlocked(feature) {
            return true
        }

        switch feature {
        case .themeCustomize:
            return VIPManager.shared.isVIP
        default:
            return false
        }
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
            let totalSpent = StoreManager.synchronizedMeowCoinAccount().totalSpent
            let met = totalSpent >= condition.requiredValue
            return (met, met ? nil : "累计消费喵币: \(totalSpent)/\(condition.requiredValue)")

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
            // 历史数据兼容：当前版本不再提供该解锁入口
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

        guard UnlockConditionType(rawValue: condition.type) != nil else {
            return .conditionNotMet("未知的解锁条件")
        }

        // meowCoin 类型表示“累计消费达到条件”后可领取解锁，不在这里再次扣费

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

        // 发送通知（同时发送 rawValue 和 FeatureItem 对象以保持兼容性）
        NotificationCenter.default.post(
            name: Self.featureUnlockedNotification,
            object: nil,
            userInfo: [
                "feature": feature,
                "featureRawValue": feature.rawValue
            ]
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
            return condition.type != UnlockConditionType.free.rawValue &&
                   $0.isPublicUnlockTask
        }
    }

    // MARK: - 数据获取（需要接入实际数据源）

    private func getClothingCount() -> Int {
        return cachedClothingCount
    }

    private var cachedClothingCount: Int {
        UserDefaults.standard.integer(forKey: "clothingCount_cache")
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

    /// 使用 SwiftData 安全路径刷新衣物数量缓存。
    /// iOS 17.x 上 `ModelContext.fetchCount(_:)` 可能在 CoreData 层抛 Objective-C 异常导致 SIGABRT，
    /// 因此统一走 `fetch(_:)` 后本地 count，失败时保留并返回旧缓存，避免启动或编辑流程崩溃。
    @discardableResult
    func refreshClothingCountCache(from context: ModelContext, reason: String = "manual") -> Int {
        let clothingCount = fetchClothingCountSafely(from: context)
        updateClothingCount(clothingCount)
        print("👗 衣物数量缓存已刷新[\(reason)]: \(clothingCount)")
        return clothingCount
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

    // MARK: - 启动时刷新进度

    /// 刷新所有魔法任务的进度数据。
    /// 启动关键路径默认只使用缓存，避免 iOS 17.x 在 `fetchCount`/CoreData 计数路径上崩溃。
    func refreshMagicTaskProgress(modelContext: ModelContext? = nil, refreshClothingCount: Bool = true) {
        print("🔄 开始刷新魔法任务进度...")

        // 1. 更新衣物数量。启动阶段可传 refreshClothingCount=false，仅使用缓存完成解锁状态刷新。
        if refreshClothingCount, let context = modelContext {
            let clothingCount = refreshClothingCountCache(from: context, reason: "magic-task-progress")
            print("👗 衣物数量已更新: \(clothingCount)")
        } else {
            print("👗 衣物数量使用缓存: \(cachedClothingCount)")
        }

        // 2. 更新登录天数（这里可以接入实际的登录记录）
        // 暂时保持现有逻辑

        // 3. 检查所有未解锁的功能，看是否满足条件并自动解锁
        checkAndAutoUnlockFeatures()

        print("✅ 魔法任务进度刷新完成")
    }

    /// 从数据库获取衣物数量（排除已删除的）。
    /// 不使用 `fetchCount`：该 API 在部分 iOS 17.x + SwiftData/CoreData 组合上会绕过 Swift error
    /// handling，以 Objective-C exception 形式终止进程。
    private func fetchClothingCountSafely(from context: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.isDeleted == false })
            return try context.fetch(descriptor).count
        } catch {
            print("❌ 获取衣物数量失败，使用缓存: \(error)")
            return cachedClothingCount
        }
    }

    /// 检查并自动解锁满足条件的功能
    private func checkAndAutoUnlockFeatures() {
        let lockableFeatures = getLockableFeatures()

        for feature in lockableFeatures {
            // 跳过已解锁的功能
            guard !isUnlocked(feature) else { continue }

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

extension FeatureUnlockManager {
    func makeAlertItem(for feature: FeatureItem) -> FeatureUnlockAlert? {
        guard !isUnlocked(feature) else { return nil }

        let check = checkUnlockCondition(feature)
        let condition = getCondition(for: feature)
        return FeatureUnlockAlert(
            feature: feature,
            condition: condition,
            canUnlock: check.met,
            message: check.message
        )
    }
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
            return "限时"
        }
    }
}
