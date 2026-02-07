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
    
    // 对应的视频文件名（不含扩展名）
    func videoFileName(for job: PetJob = .none) -> String {
        switch self {
        case .idle: return "idle"
        case .eating: return "eat"
        case .drinking: return "eat" // 复用 eat 或 separate
        case .cleaning: return "clean"
        case .expecting: return "idle" // 暂时复用 idle，通过 UI 区分
        case .playing: return "idle" // 暂时复用 idle，后续添加专属动画
        case .sleeping: return "idle" // 暂时复用 idle，后续添加 sleep 视频
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
}

// 萌宠货币类型
enum PetCurrency: String, CaseIterable, Identifiable {
    case meowCoin = "喵币"
    case fishCoin = "鱼币"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .meowCoin: return "pawprint.circle.fill"
        case .fishCoin: return "fish.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .meowCoin: return "yellow" // SwiftUI Color name or hex
        case .fishCoin: return "orange"
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

    // 特殊道具
    case renameCard = "改名项圈"
    
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
        case .renameCard: return "renameCard"
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
    let currency: String // "fishCoin" or "meowCoin"
    let recoveryValue: Double
    let energyCost: Int? // 消耗精力
    let icon: String
    let description: String
    let sortIndex: Int
    
    var petCurrency: PetCurrency {
        return currency == "meowCoin" ? .meowCoin : .fishCoin
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

struct PetStatus: Codable {
    var petName: String? // 萌宠名字
    var hunger: Double = 100.0 // 饱食度 0-100
    var hygiene: Double = 100.0 // 清洁度 0-100
    var energy: Double = 100.0 // 精力 0-100
    var mood: Double = 100.0 // 心情 0-100
    var lastUpdateTime: Date = Date()
    
    // 货币系统
    var meowCoin: Int = 0 // 喵币
    var fishCoin: Int = 1000 // 鱼币 (初始赠送一些)
    
    // 每日限制
    var dailyFishCoinEarned: Int = 0
    var lastDailyResetDate: Date = Date()
    
    // 背包系统
    var inventory: [String: Int] = [:] // 存储物品数量 (Key: Config ID)
    
    // 工作系统
    var currentJob: PetJob = .none
    var jobStartTime: Date?
    
    // 衰减速率 (每秒减少多少)
    static let hungerDecayRate: Double = 10.0 / 3600.0 // 每小时减少10点
    static let hygieneDecayRate: Double = 5.0 / 3600.0 // 每小时减少5点
    static let energyDecayRate: Double = 8.0 / 3600.0 // 每小时减少8点
    static let moodDecayRate: Double = 12.0 / 3600.0 // 每小时减少12点
    
    static let dailyFishCoinLimit: Int = 10000
}
