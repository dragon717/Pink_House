import Foundation

enum PetState: String, CaseIterable {
    case idle = "idle"
    case eating = "eating"
    case cleaning = "cleaning"
    
    // 对应的视频文件名（不含扩展名）
    var videoFileName: String {
        switch self {
        case .idle: return "idle"
        case .eating: return "eat" // 假设文件名
        case .cleaning: return "clean" // 假设文件名
        }
    }
    
    // 是否是循环动画
    var isLooping: Bool {
        switch self {
        case .idle: return true
        default: return false
        }
    }
}

struct PetStatus: Codable {
    var hunger: Double = 100.0 // 饱食度 0-100
    var hygiene: Double = 100.0 // 清洁度 0-100
    var lastUpdateTime: Date = Date()
    
    // 衰减速率 (每秒减少多少)
    static let hungerDecayRate: Double = 10.0 / 3600.0 // 每小时减少10点
    static let hygieneDecayRate: Double = 5.0 / 3600.0 // 每小时减少5点
}
