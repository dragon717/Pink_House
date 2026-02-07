import Foundation

enum PetState: String, CaseIterable {
    case idle = "idle"
    case eating = "eating"
    case drinking = "drinking"
    case cleaning = "cleaning"
    case expecting = "expecting" // 期待状态
    
    // 对应的视频文件名（不含扩展名）
    var videoFileName: String {
        switch self {
        case .idle: return "idle"
        case .eating: return "eat"
        case .drinking: return "eat" // 复用 eat 或 separate
        case .cleaning: return "clean"
        case .expecting: return "idle" // 暂时复用 idle，通过 UI 区分
        }
    }
    
    // 是否是循环动画
    var isLooping: Bool {
        switch self {
        case .idle, .expecting: return true
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

// 道具类型
enum PetItemType: String, Codable, CaseIterable, Identifiable {
    // 食物
    case catRice = "猫饭"
    case cannedFood = "猫罐头"
    case catStrip = "猫条"
    case freezeDried = "冻干"
    case chickenBreast = "鸡胸肉"
    
    // 水
    case warmWater = "温水"
    case boiledWater = "白开水"
    
    // 特殊道具
    case renameCard = "改名卡"
    
    var id: String { rawValue }
    
    var price: Int {
        switch self {
        case .catRice: return 100
        case .cannedFood: return 500
        case .catStrip: return 200
        case .freezeDried: return 800
        case .chickenBreast: return 1500
        case .warmWater: return 0
        case .boiledWater: return 0
        case .renameCard: return 10
        }
    }
    
    var currency: PetCurrency {
        switch self {
        case .renameCard: return .meowCoin
        default: return .fishCoin
        }
    }
    
    var icon: String {
        // SF Symbols 或自定义图片
        switch self {
        case .catRice: return "tray.fill" // Replaced bowl.fill to avoid crash
        case .cannedFood: return "circle.grid.cross.fill"
        case .catStrip: return "capsule.fill"
        case .freezeDried: return "snowflake"
        case .chickenBreast: return "bird.fill"
        case .warmWater: return "drop.fill"
        case .boiledWater: return "drop"
        case .renameCard: return "pencil.and.outline"
        }
    }
    
    var recoveryValue: Double {
        // 恢复饱食度或清洁度（这里简化为统一恢复，具体逻辑在 ViewModel 处理）
        switch self {
        case .catRice: return 10
        case .cannedFood: return 30
        case .catStrip: return 15
        case .freezeDried: return 40
        case .chickenBreast: return 50
        case .warmWater: return 10
        case .boiledWater: return 5
        case .renameCard: return 0
        }
    }
    
    var isDrink: Bool {
        return self == .warmWater || self == .boiledWater
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
        case .streamer: return 20
        }
    }
    
    // 饱食度/清洁度消耗倍率 (基于基础消耗)
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
    var inventory: [PetItemType: Int] = [:] // 存储物品数量
    
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
