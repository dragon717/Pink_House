import Foundation

enum PetState: String, CaseIterable {
    case idle = "idle"
    case eating = "eating"
    case drinking = "drinking"
    case cleaning = "cleaning"
    case expecting = "expecting" // 期待状态
    case playing = "playing" // 玩耍状态
    case sleeping = "sleeping" // 睡觉状态
    case working = "working" // 工作状态
    case interacting = "interacting" // 互动状态 (点击反馈)
    
    // 对应的视频文件名（不含扩展名）
    func videoFileName(for job: PetJob = .none) -> String {
        switch self {
        case .idle: return "idle"
        case .eating: return "eat"
        case .drinking: return "eat" // 复用 eat 或 separate
        case .cleaning: return "clean"
        case .expecting: return "idle" // 暂时复用 idle，通过 UI 区分
        case .playing: return "playing" // 播放玩耍视频
        case .sleeping: return "idle" // 暂时复用 idle，后续添加 sleep 视频
        case .interacting: return "idle" // 由 ViewModel 动态控制
        case .working:
            switch job {
            case .none: return "idle"
            case .waiter: return "waiter"
            case .security: return "security"
            case .streamer: return "streamer"
            }
        }
    }
    
    // 兼容旧属性，默认不传 job
    var videoFileName: String {
        return videoFileName()
    }
    
    // 是否是循环动画
    var isLooping: Bool {
        switch self {
        case .idle, .expecting, .playing, .sleeping, .working: return true
        default: return false
        }
    }
    
    var id: String { rawValue }
}

// 萌宠货币类型
enum PetCurrency: String, CaseIterable, Identifiable {
    case meowCoin = "喵币"
    case fishCoin = "鱼币"
    case boneCoin = "骨头币"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .meowCoin: return "pawprint.circle.fill"
        case .fishCoin: return "fish.circle.fill"
        case .boneCoin: return "circle.fill" // 使用 circle.fill 作为背景，然后在 View 层叠加骨头图标，或者寻找更合适的组合。但用户要求“圈里面是骨头”。SF Symbols 没有直接的 circle.bone.fill。
        // 修正：实际上，我们可以直接在 UI 层使用 Overlay 组合。
        // 但为了保持接口一致性，这里返回 "bone.circle.fill" 如果有的话。
        // SF Symbols 查证：目前没有 bone.circle.fill。只有 bone.fill。
        // 所以我们暂时返回 "pawprint.circle.fill" 作为占位？不，用户明确要骨头。
        // 更好的做法是：在 View 层特殊处理 boneCoin，或者这里返回一个特殊的标识。
        // 暂时先返回 "bone.fill"，然后在 UI 层加圈。
        // 或者，我们可以使用 "circle.circle.fill" 这种？
        // 让我们看看 UI 代码。
        // UI 代码是 Image(systemName: type.iconName)
        
        // 如果我们想简单点，可以用 "dog.circle.fill" ? 不太对。
        // 鉴于系统限制，我们这里返回 "bone.fill"，然后在 UI 层检测如果是 boneCoin 就加个圈背景。
        // 或者，我们可以尝试 "dog.circle" ?
        
        // 既然用户明确说“圈里面是骨头icon”，最直接的办法是：
        // 1. 找一个近似的 symbol。
        // 2. 如果没有，就得改 UI 代码支持组合图标。
        
        // 让我们先试试直接返回 "bone.fill"，然后在 PetComponents.swift 里修改 UI。
        return "bone.fill"
        }
    }
    
    var color: String {
        switch self {
        case .meowCoin: return "yellow" // SwiftUI Color name or hex
        case .fishCoin: return "orange"
        case .boneCoin: return "brown"
        }
    }
}

// 道具类型 - 兼容旧代码，建议使用 PetItemDefinition
enum PetItemType: String, Codable, CaseIterable, Identifiable {
    // 食物
    case catRice = "猫饭"
    case cannedFood = "猫罐头"
    case catStrip = "猫条"
    case freezeDried = "冻干"
    case chickenBreast = "鸡胸肉"
    case rawMeat = "生骨肉"
    case catFood = "猫粮"
    
    // 水
    case warmWater = "温水"
    case boiledWater = "白开水"
    case goatMilk = "山羊奶"

    // 特殊道具
    case renameCard = "改名项圈"
    case energyPill = "精力药丸"
    
    var id: String { rawValue }
    
    // 映射到新的配置 ID
    var configId: String {
        switch self {
        case .catRice: return "catRice"
        case .cannedFood: return "cannedFood"
        case .catStrip: return "catStrip"
        case .freezeDried: return "freezeDried"
        case .chickenBreast: return "chickenBreast"
        case .rawMeat: return "rawMeat"
        case .catFood: return "catFood"
        case .warmWater: return "warmWater"
        case .boiledWater: return "boiledWater"
        case .goatMilk: return "goatMilk"
        case .renameCard: return "renameCard"
        case .energyPill: return "energyPill"
        }
    }
    
    var price: Int {
        return PetConfigManager.shared.getItem(byId: configId)?.price ?? 0
    }
    
    var currency: PetCurrency {
        return PetConfigManager.shared.getItem(byId: configId)?.petCurrency ?? .fishCoin
    }
    
    var icon: String {
        return PetConfigManager.shared.getItem(byId: configId)?.icon ?? "questionmark"
    }
    
    var recoveryValue: Double {
        return PetConfigManager.shared.getItem(byId: configId)?.recoveryValue ?? 0
    }
    
    var isDrink: Bool {
        return PetConfigManager.shared.getItem(byId: configId)?.category == "water"
    }
}

// MARK: - New Config Models

struct PetCategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

struct PetItemDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let price: Int
    let currency: String // "fishCoin", "meowCoin", or "boneCoin"
    let recoveryValue: Double
    let energyCost: Int? // 消耗精力
    let icon: String
    let description: String
    let sortIndex: Int
    
    var petCurrency: PetCurrency {
        switch currency {
        case "meowCoin": return .meowCoin
        case "boneCoin": return .boneCoin
        default: return .fishCoin
        }
    }
    
    var isDrink: Bool {
        return category == "water"
    }
    
    var isToy: Bool {
        return category == "toy"
    }
}


// 宠物工作
enum PetJob: String, Codable, CaseIterable, Identifiable {
    case none = "啃老喵"
    case waiter = "猫咖喵"
    case security = "喵警长"
    case streamer = "直播喵"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .none: return "宠物正在啃老，状态消耗正常。"
        case .waiter: return "在猫咖被rua，赚取少量鱼币，稍微有点累。"
        case .security: return "负责巡逻抓老鼠，赚取大等鱼币，比较累。"
        case .streamer: return "在线卖萌直播，赚取巨量鱼币，非常累！"
        }
    }
    
    // 鱼币收益 (每分钟)
    var incomeRate: Int {
        switch self {
        case .none: return 0
        case .waiter: return 5
        case .security: return 10
        case .streamer: return 15
        }
    }
    
    // 饱食度/清洁度/精力/心情消耗倍率 (基于基础消耗)
    var consumptionMultiplier: Double {
        switch self {
        case .none: return 1.0
        case .waiter: return 1.5
        case .security: return 2.0
        case .streamer: return 3.0
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "zzz"
        case .waiter: return "cup.and.saucer.fill"
        case .security: return "shield.fill"
        case .streamer: return "video.fill"
        }
    }
}

struct PetItem: Codable, Identifiable {
    var id: UUID = UUID()
    var type: PetItemType
    var count: Int
}

enum PetCharacter: String, Codable, CaseIterable, Identifiable {
    case naicha = "naicha"
    case maomao = "maomao"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .naicha: return "奶茶"
        case .maomao: return "毛毛"
        }
    }
    
    var description: String {
        switch self {
        case .naicha: return "一只喜欢喝奶茶的橘猫，\n性格温顺，最爱撒娇。"
        case .maomao: return "活泼可爱的金毛犬，\n精力充沛，忠诚粘人。"
        }
    }
    
    var portraitImageName: String {
        return "\(rawValue)_portrait"
    }

    var quickOptionIconName: String {
        switch self {
        case .naicha: return "cat"
        case .maomao: return "dog"
        }
    }

    var catchphraseSuffix: String {
        switch self {
        case .naicha: return "喵~"
        case .maomao: return "汪~"
        }
    }

    func localizedCatchphraseText(_ text: String) -> String {
        guard self == .maomao else { return text }

        return text
            .replacingOccurrences(of: "喵~", with: "汪~")
            .replacingOccurrences(of: "喵？", with: "汪？")
            .replacingOccurrences(of: "喵?", with: "汪?")
            .replacingOccurrences(of: "喵...", with: "汪...")
            .replacingOccurrences(of: "喵…", with: "汪…")
            .replacingOccurrences(of: "喵！", with: "汪！")
            .replacingOccurrences(of: "喵!", with: "汪!")
            .replacingOccurrences(of: "喵，", with: "汪，")
            .replacingOccurrences(of: "喵。", with: "汪。")
    }
    
    // 萌宠对话中使用的happy表情图片名
    var happyImageName: String {
        switch self {
        case .naicha: return "happy_cat"
        case .maomao: return "happy_dog"
        }
    }
    
    // 各种表情图片名称映射
    var angryImageName: String {
        switch self {
        case .naicha: return "angry_cat"
        case .maomao: return "angry_dog"
        }
    }
    
    var curiousImageName: String {
        switch self {
        case .naicha: return "curious_cat"
        case .maomao: return "curious_dog"
        }
    }
    
    var sleepyImageName: String {
        switch self {
        case .naicha: return "sleepy_cat"
        case .maomao: return "sleepy_dog"
        }
    }
    
    var thinkingImageName: String {
        switch self {
        case .naicha: return "thinking_cat"
        case .maomao: return "thinking_dog"
        }
    }
}

// MARK: - Pet Behavior Protocol
protocol PetBehavior {
    var character: PetCharacter { get }
    
    // 工作结束结果
    func getWorkFinishResult(job: PetJob, status: PetStatus) -> (video: String, message: String, success: Bool)
    
    // 工作强制中断视频
    func getWorkInterruptedVideo() -> String
    
    // 回音彩蛋 (返回视频路径)
    func getEchoEgg(text: String) -> String?
    
    // 喂食彩蛋 (返回视频路径)
    func getFeedingEgg(item: PetItemDefinition) -> String?
}

// 默认行为 (兼容旧逻辑/通用逻辑)
struct DefaultPetBehavior: PetBehavior {
    let character: PetCharacter
    
    func getWorkFinishResult(job: PetJob, status: PetStatus) -> (video: String, message: String, success: Bool) {
        // 默认逻辑：没有特殊视频，只返回文案
        return ("idle", "打工结束", true)
    }
    
    func getWorkInterruptedVideo() -> String {
        return "idle"
    }
    
    func getEchoEgg(text: String) -> String? {
        return nil
    }
    
    func getFeedingEgg(item: PetItemDefinition) -> String? {
        return nil
    }
}

// Naicha 专属行为
struct NaichaBehavior: PetBehavior {
    let character: PetCharacter = .naicha
    
    func getWorkFinishResult(job: PetJob, status: PetStatus) -> (video: String, message: String, success: Bool) {
        if status.energy > 50 {
            // 直接读取累积的打工收益
            let earned = status.currentJobEarnedFishCoin
            return (
                "work_success",
                "打工赚了 \(earned) 鱼币!",
                true
            )
        } else {
             return (
                "work_exhausted",
                "累死宝宝了...",
                false
            )
        }
    }
    
    func getWorkInterruptedVideo() -> String {
        return "work_exhausted"
    }
    
    func getEchoEgg(text: String) -> String? {
        // 关键词匹配（包含谐音）
        let keywords = ["登基", "登记", "等级", "登机", "灯基"]
        for keyword in keywords {
            if text.contains(keyword) {
                // 返回逻辑名，PetViewModel 会自动加上角色前缀 (e.g. naicha_coronation)
                return "coronation"
            }
        }
        return nil
    }
    
    func getFeedingEgg(item: PetItemDefinition) -> String? {
        // 5% 概率触发
        if Int.random(in: 1...100) <= 5 {
             return "eat_rush"
        }
        return nil
    }
}

// MARK: - VIP Status
enum VIPCardStyle: String, Codable, CaseIterable, Identifiable {
    case blackGold = "blackGold"
    case monicaPink = "monicaPink"
    case themeSkinAdaptive = "themeSkinAdaptive"
    case skyConcertTheme = "skyConcertTheme"
    case swanDreamTheme = "swanDreamTheme"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blackGold: return "黑金尊享"
        case .monicaPink: return "莫妮卡粉色萌梦幻"
        case .themeSkinAdaptive: return "跟随当前主题"
        case .skyConcertTheme: return "天空音乐会 VIP卡"
        case .swanDreamTheme: return "天鹅入梦 VIP卡"
        }
    }
}

struct VIPStatus: Codable {
    var isActive: Bool = false
    var expireDate: Date? = nil
    var vipNumber: String? = nil // 特殊编号
    var cardStyle: VIPCardStyle = .monicaPink // Default style
    
    // VIP试用期相关字段
    var trialUsed: Bool = false // 是否已使用过试用期
    var trialStartDate: Date? = nil // 试用期开始时间
    var trialExpireDate: Date? = nil // 试用期结束时间
    
    var isExpired: Bool {
        guard let date = expireDate else { return true }
        return date < Date()
    }
    
    // 是否正在试用期中
    var isInTrialPeriod: Bool {
        guard let trialExpire = trialExpireDate else { return false }
        return trialExpire > Date()
    }
    
    // 是否可以显示试用期弹窗（未使用试用期且当前不是VIP）
    var canShowTrialOffer: Bool {
        return !trialUsed && !isActive
    }
}

struct PetStatus: Codable {
    var petNames: [String: String] = [:] // 萌宠名字集合 (Key: PetID, Value: Name)
    var selectedPetId: String? = nil // 当前选择的宠物角色 ID
    
    // VIP Status
    var vipStatus: VIPStatus = VIPStatus()
    
    // 兼容旧属性，计算属性
    var petName: String? {
        get {
            guard let id = selectedPetId else { return nil }
            return petNames[id]
        }
        set {
            guard let id = selectedPetId else { return }
            petNames[id] = newValue
        }
    }
    
    // 供 UI 显示用的名字（经过清洗）
    // 如果用户没有给宠物起名，则使用宠物类型名（如"奶茶"、"毛毛"）作为默认显示名
    var displayName: String {
        guard let name = petName else {
            // 没有自定义名字时，返回宠物类型名
            guard let id = selectedPetId, let character = PetCharacter(rawValue: id) else { return "小伙伴" }
            return character.displayName
        }
        let clean = name.replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果用户起的名字为空，则使用宠物类型名
        if clean.isEmpty {
            guard let id = selectedPetId, let character = PetCharacter(rawValue: id) else { return "小伙伴" }
            return character.displayName
        }
        return clean
    }
    
    var ownedPetIds: [String] = [] // 已拥有的宠物列表，默认为空，进入领养流程
    var hunger: Double = 100.0 // 饱食度 0-100
    var hygiene: Double = 100.0 // 清洁度 0-100
    var energy: Double = 100.0 // 精力 0-100
    var mood: Double = 100.0 // 心情 0-100
    var intimacy: Double = 0.0 // 亲密度 0-100（对话/互动成长）
    var lastUpdateTime: Date = Date()
    
    // 货币系统
    var meowCoin: Int = 0 // 喵币 (通用高级货币)
    var fishCoin: Int = 1000 // 鱼币 (猫专用/通用基础货币)
    var boneCoin: Int = 0 // 骨头币 (狗专用基础货币)
    
    // 每日限制
    var dailyFishCoinEarned: Int = 0
    var lastDailyResetDate: Date = Date()
    
    // 背包系统
    var inventory: [String: Int] = [:] // 存储物品数量 (Key: Config ID)
    
    // 工作系统
    var currentJob: PetJob = .none
    var jobStartTime: Date?
    var currentJobEarnedFishCoin: Int = 0 // 本次打工累计赚取的鱼币（需要持久化，避免备份/恢复或跨端同步后丢失）
    
    // 衰减速率 (每秒减少多少)
    static let hungerDecayRate: Double = 10.0 / 3600.0 // 每小时减少10点
    static let hygieneDecayRate: Double = 5.0 / 3600.0 // 每小时减少5点
    static let energyDecayRate: Double = 8.0 / 3600.0 // 每小时减少8点
    static let moodDecayRate: Double = 12.0 / 3600.0 // 每小时减少12点
    
    static let dailyFishCoinLimit: Int = 10000
    
    // MARK: - Initialization
    init() {
        // Default init (new user)
    }
    
    // MARK: - Codable Implementation for Backward Compatibility
    enum CodingKeys: String, CodingKey {
        case petName, petNames, selectedPetId, ownedPetIds
        case hunger, hygiene, energy, mood, intimacy, lastUpdateTime
        case meowCoin, fishCoin, boneCoin
        case dailyFishCoinEarned, lastDailyResetDate
        case inventory
        case currentJob, jobStartTime, currentJobEarnedFishCoin
        case vipStatus
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Basic properties (some might be missing in very old versions, provide defaults)
        let legacyPetName = try container.decodeIfPresent(String.self, forKey: .petName)
        hunger = try container.decodeIfPresent(Double.self, forKey: .hunger) ?? 100.0
        hygiene = try container.decodeIfPresent(Double.self, forKey: .hygiene) ?? 100.0
        energy = try container.decodeIfPresent(Double.self, forKey: .energy) ?? 100.0
        mood = try container.decodeIfPresent(Double.self, forKey: .mood) ?? 100.0
        intimacy = try container.decodeIfPresent(Double.self, forKey: .intimacy) ?? 0.0
        lastUpdateTime = try container.decodeIfPresent(Date.self, forKey: .lastUpdateTime) ?? Date()
        
        // Currency & Inventory
        meowCoin = try container.decodeIfPresent(Int.self, forKey: .meowCoin) ?? 0
        fishCoin = try container.decodeIfPresent(Int.self, forKey: .fishCoin) ?? 1000
        boneCoin = try container.decodeIfPresent(Int.self, forKey: .boneCoin) ?? 0
        dailyFishCoinEarned = try container.decodeIfPresent(Int.self, forKey: .dailyFishCoinEarned) ?? 0
        lastDailyResetDate = try container.decodeIfPresent(Date.self, forKey: .lastDailyResetDate) ?? Date()
        inventory = try container.decodeIfPresent([String: Int].self, forKey: .inventory) ?? [:]
        
        // Job
        currentJob = try container.decodeIfPresent(PetJob.self, forKey: .currentJob) ?? .none
        jobStartTime = try container.decodeIfPresent(Date.self, forKey: .jobStartTime)
        currentJobEarnedFishCoin = try container.decodeIfPresent(Int.self, forKey: .currentJobEarnedFishCoin) ?? 0
        
        // VIP
        vipStatus = try container.decodeIfPresent(VIPStatus.self, forKey: .vipStatus) ?? VIPStatus()
        
        // Compatibility Logic for Pet IDs
        // 旧版本没有 ownedPetIds，默认只有一只奶茶
        if let ids = try container.decodeIfPresent([String].self, forKey: .ownedPetIds) {
            ownedPetIds = ids
            selectedPetId = try container.decodeIfPresent(String.self, forKey: .selectedPetId)
        } else {
            // 这是旧版本数据！
            ownedPetIds = [PetCharacter.naicha.rawValue]
            // 如果旧版本有 selectedPetId 就用，没有就默认奶茶
            selectedPetId = try container.decodeIfPresent(String.self, forKey: .selectedPetId) ?? PetCharacter.naicha.rawValue
        }
        
        // Decode petNames or migrate
        if let names = try container.decodeIfPresent([String: String].self, forKey: .petNames) {
            petNames = names
        } else {
            petNames = [:]
            // Migration: If we have a legacy name and a selected pet ID, map it
            if let oldName = legacyPetName, let id = selectedPetId {
                petNames[id] = oldName
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(petName, forKey: .petName) // Store current name for legacy compat
        try container.encode(petNames, forKey: .petNames)
        try container.encode(selectedPetId, forKey: .selectedPetId)
        try container.encode(ownedPetIds, forKey: .ownedPetIds)
        try container.encode(hunger, forKey: .hunger)
        try container.encode(hygiene, forKey: .hygiene)
        try container.encode(energy, forKey: .energy)
        try container.encode(mood, forKey: .mood)
        try container.encode(intimacy, forKey: .intimacy)
        try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
        try container.encode(meowCoin, forKey: .meowCoin)
        try container.encode(fishCoin, forKey: .fishCoin)
        try container.encode(boneCoin, forKey: .boneCoin)
        try container.encode(dailyFishCoinEarned, forKey: .dailyFishCoinEarned)
        try container.encode(lastDailyResetDate, forKey: .lastDailyResetDate)
        try container.encode(inventory, forKey: .inventory)
        try container.encode(currentJob, forKey: .currentJob)
        try container.encodeIfPresent(jobStartTime, forKey: .jobStartTime)
        try container.encode(currentJobEarnedFishCoin, forKey: .currentJobEarnedFishCoin)
        try container.encode(vipStatus, forKey: .vipStatus)
    }
}
