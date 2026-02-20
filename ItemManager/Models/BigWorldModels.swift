//
//  BigWorldModels.swift
//  ItemManager
//
//  大世界 - Lolita茶会环球旅行数据模型
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - 地标类型
enum LandmarkType: String, CaseIterable, Codable {
    case glacier = "冰川"
    case canyon = "大峡谷"
    case oasis = "沙漠绿洲"
    case prairie = "大草原"
    case aurora = "极光之地"
    case castle = "古堡花园"
    case sakura = "樱花神社"
    case lavender = "薰衣草田"
    
    var icon: String {
        switch self {
        case .glacier: return "❄️"
        case .canyon: return "⛰️"
        case .oasis: return "💧"
        case .prairie: return "🌿"
        case .aurora: return "✨"
        case .castle: return "🏰"
        case .sakura: return "🌸"
        case .lavender: return "🪻"
        }
    }
    
    var themeColor: Color {
        switch self {
        case .glacier: return Color(red: 0.6, green: 0.85, blue: 0.95)
        case .canyon: return Color(red: 0.95, green: 0.6, blue: 0.4)
        case .oasis: return Color(red: 0.4, green: 0.8, blue: 0.6)
        case .prairie: return Color(red: 0.7, green: 0.9, blue: 0.4)
        case .aurora: return Color(red: 0.4, green: 0.9, blue: 0.8)
        case .castle: return Color(red: 0.9, green: 0.7, blue: 0.5)
        case .sakura: return Color(red: 1.0, green: 0.75, blue: 0.85)
        case .lavender: return Color(red: 0.75, green: 0.6, blue: 0.9)
        }
    }
    
    var ambientSound: String {
        switch self {
        case .glacier: return "glacier_wind"
        case .canyon: return "canyon_breeze"
        case .oasis: return "oasis_water"
        case .prairie: return "prairie_birds"
        case .aurora: return "aurora_mystic"
        case .castle: return "castle_chimes"
        case .sakura: return "sakura_petals"
        case .lavender: return "lavender_bees"
        }
    }
}

// MARK: - 地标目的地
struct Landmark: Identifiable, Codable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let type: LandmarkType
    let coordinate: CLLocationCoordinate2D
    let description: String
    let teaPartyTheme: String
    let imageName: String
    let badgeName: String
    let badgeDescription: String
    let requiredLevel: Int
    
    // 机场代码（用于登机牌显示）
    var code: String {
        // 根据地标的名称生成3位机场代码
        let prefix = String(name.prefix(3)).uppercased()
        return prefix
    }
    
    static func == (lhs: Landmark, rhs: Landmark) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 坐标编码支持
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: lat, longitude: lon)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

// MARK: - 徽章
struct TeaPartyBadge: Identifiable, Codable {
    let id = UUID()
    let name: String
    let description: String
    let landmarkType: LandmarkType
    let landmarkId: UUID
    let imageName: String
    let unlockDate: Date?
    let isLimited: Bool
    let specialEffect: BadgeEffect?
    let earnedDate: Date
    
    var isUnlocked: Bool {
        unlockDate != nil
    }
    
    // 计算属性：主题颜色
    var themeColor: Color {
        landmarkType.themeColor
    }
    
    // 计算属性：图标名称
    var iconName: String {
        landmarkType.icon
    }
}

// MARK: - 徽章特效
enum BadgeEffect: String, Codable {
    case shimmer = "闪烁"
    case glow = "发光"
    case particle = "粒子"
    case rainbow = "彩虹"
}

// MARK: - 飞行记录
struct FlightRecord: Identifiable, Codable {
    let id = UUID()
    let landmark: Landmark
    let departureLocation: String
    let flightDate: Date
    let flightDuration: TimeInterval
    let badgeEarned: TeaPartyBadge
    let seatNumber: String
    let isDepartureHidden: Bool
}

// MARK: - 成就
struct Achievement: Identifiable, Codable {
    let id = UUID()
    let title: String
    let description: String
    let requirement: Int
    let currentProgress: Int
    let iconName: String
    let rewardBadge: String?
    let isUnlocked: Bool
    let themeColorName: String? // 主题颜色名称
    
    // 计算属性：名称（兼容旧代码）
    var name: String {
        title
    }
    
    // 计算属性：进度（兼容旧代码，0.0-1.0）
    var progress: Double {
        progressPercentage
    }
    
    // 计算属性：奖励积分
    var rewardPoints: Int {
        requirement * 10
    }
    
    var progressPercentage: Double {
        min(Double(currentProgress) / Double(requirement), 1.0)
    }
    
    // 计算属性：主题颜色（参考梦裙日历主题）
    var themeColor: Color {
        switch themeColorName {
        case "monica": // 莫妮卡 - 少女粉紫
            return Color(red: 0.85, green: 0.75, blue: 0.85)
        case "cinderella": // 灰姑娘 - 水蓝色
            return Color(red: 0.53, green: 0.81, blue: 0.92)
        case "matcha": // 抹茶 - 清新绿
            return Color(red: 0.60, green: 0.98, blue: 0.60)
        case "gothic": // 哥特 - 暗红
            return Color(red: 0.5, green: 0.0, blue: 0.0)
        case "gold": // 定金标记色 - 金色
            return Color(red: 1.0, green: 0.84, blue: 0.0)
        case "hotpink": // 尾款标记色 - 热粉
            return Color(red: 1.0, green: 0.41, blue: 0.71)
        default:
            return Color(red: 0.85, green: 0.75, blue: 0.85) // 默认莫妮卡色
        }
    }
}

// MARK: - 飞行状态
enum FlightStatus {
    case idle
    case selecting
    case boarding(seatNumber: String)
    case flying(progress: Double, narrative: String)
    case arrived(landmark: Landmark)
    case checkedIn(record: FlightRecord)
}

extension FlightStatus: Equatable {
    static func == (lhs: FlightStatus, rhs: FlightStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.selecting, .selecting):
            return true
        case (.boarding(let lhsSeat), .boarding(let rhsSeat)):
            return lhsSeat == rhsSeat
        case (.flying(let lhsProgress, _), .flying(let rhsProgress, _)):
            return lhsProgress == rhsProgress
        case (.arrived(let lhsLandmark), .arrived(let rhsLandmark)):
            return lhsLandmark.id == rhsLandmark.id
        case (.checkedIn(let lhsRecord), .checkedIn(let rhsRecord)):
            return lhsRecord.id == rhsRecord.id
        default:
            return false
        }
    }
}

// MARK: - 虚拟机票
struct BoardingPass {
    let passengerName: String
    let from: String
    let to: String
    let flightDate: Date
    let seatNumber: String
    let gate: String
    let boardingTime: Date
    let qrCodeData: String
    let stampImage: String
    let isDepartureHidden: Bool
    
    var formattedFlightNumber: String {
        "LOLITA-\(String(format: "%03d", Int.random(in: 100...999)))"
    }
}

// MARK: - 预定义地标数据
extension Landmark {
    static let allLandmarks: [Landmark] = [
        // 冰川 - 极地之星
        Landmark(
            name: "冰岛·蓝冰洞",
            subtitle: "极地之星茶会",
            type: .glacier,
            coordinate: CLLocationCoordinate2D(latitude: 64.9631, longitude: -19.0208),
            description: "在千年蓝冰的环抱中，品尝热可可与马卡龙的甜蜜",
            teaPartyTheme: "冰雪奇缘·蓝白洛丽塔",
            imageName: "landmark_glacier",
            badgeName: "极地之星",
            badgeDescription: "在冰川深处参加茶会的勇者",
            requiredLevel: 1
        ),
        
        // 大峡谷 - 孤高蔷薇
        Landmark(
            name: "大峡谷·落日祭坛",
            subtitle: "孤高蔷薇茶会",
            type: .canyon,
            coordinate: CLLocationCoordinate2D(latitude: 36.1069, longitude: -112.1129),
            description: "悬崖边的下午茶，与落日共舞的华丽时刻",
            teaPartyTheme: "西部玫瑰·红棕洛丽塔",
            imageName: "landmark_canyon",
            badgeName: "孤高蔷薇",
            badgeDescription: "在峡谷之巅绽放的玫瑰",
            requiredLevel: 1
        ),
        
        // 沙漠绿洲 - 沙海蜃楼
        Landmark(
            name: "撒哈拉·翡翠绿洲",
            subtitle: "沙海蜃楼茶会",
            type: .oasis,
            coordinate: CLLocationCoordinate2D(latitude: 23.4162, longitude: 25.6628),
            description: "棕榈影下的波斯地毯，泉水声中的甜点心语",
            teaPartyTheme: "沙漠玫瑰·金绿洛丽塔",
            imageName: "landmark_oasis",
            badgeName: "沙海蜃楼",
            badgeDescription: "在沙漠中找到绿洲的旅人",
            requiredLevel: 1
        ),
        
        // 大草原 - 原野牧歌
        Landmark(
            name: "蒙古·无垠草原",
            subtitle: "原野牧歌茶会",
            type: .prairie,
            coordinate: CLLocationCoordinate2D(latitude: 46.8625, longitude: 103.8467),
            description: "漫山遍野的小碎花，风车转动中的野餐时光",
            teaPartyTheme: "草原牧歌·田园洛丽塔",
            imageName: "landmark_prairie",
            badgeName: "原野牧歌",
            badgeDescription: "在草原上自由歌唱的精灵",
            requiredLevel: 1
        ),
        
        // 极光之地
        Landmark(
            name: "挪威·极光之境",
            subtitle: "极光舞会茶会",
            type: .aurora,
            coordinate: CLLocationCoordinate2D(latitude: 69.6492, longitude: 18.9553),
            description: "在舞动极光下，与星辰共饮花茶",
            teaPartyTheme: "极光幻想·紫绿洛丽塔",
            imageName: "landmark_aurora",
            badgeName: "极光舞者",
            badgeDescription: "与极光共舞的幸运儿",
            requiredLevel: 2
        ),
        
        // 古堡花园
        Landmark(
            name: "法国·香波堡",
            subtitle: "皇家花园茶会",
            type: .castle,
            coordinate: CLLocationCoordinate2D(latitude: 47.6160, longitude: 1.5170),
            description: "文艺复兴的华丽殿堂，皇室般的下午茶体验",
            teaPartyTheme: "皇家宫廷·古典洛丽塔",
            imageName: "landmark_castle",
            badgeName: "宫廷贵族",
            badgeDescription: "在古堡中品味优雅的贵族",
            requiredLevel: 2
        ),
        
        // 樱花神社
        Landmark(
            name: "京都·千本鸟居",
            subtitle: "樱花纷飞茶会",
            type: .sakura,
            coordinate: CLLocationCoordinate2D(latitude: 34.9671, longitude: 135.7727),
            description: "飘落的樱花瓣中，和服与洛丽塔的优雅邂逅",
            teaPartyTheme: "和风樱花·和风洛丽塔",
            imageName: "landmark_sakura",
            badgeName: "樱花姬",
            badgeDescription: "在樱花雨中起舞的公主",
            requiredLevel: 3
        ),
        
        // 薰衣草田
        Landmark(
            name: "普罗旺斯·薰衣草田",
            subtitle: "紫色梦境茶会",
            type: .lavender,
            coordinate: CLLocationCoordinate2D(latitude: 43.9352, longitude: 6.0679),
            description: "紫色花海中的浪漫午后，法式优雅的极致体验",
            teaPartyTheme: "紫色梦幻·法式洛丽塔",
            imageName: "landmark_lavender",
            badgeName: "紫色梦境",
            badgeDescription: "在薰衣草田中沉醉的诗人",
            requiredLevel: 3
        )
    ]
}

// MARK: - AI 飞行叙事
struct FlightNarrative {
    static let boardingMessages: [String] = [
        "欢迎乘坐洛丽塔专机，您的茶会礼裙已准备就绪",
        "请系好安全带，我们即将启程前往梦幻之地",
        "今天的航班将带您穿越云海，抵达奇妙的茶会现场",
        "洛丽塔专机即将起飞，请确认您的蕾丝边安全带"
    ]
    
    static func inFlightMessages(to landmark: Landmark) -> [String] {
        [
            "正在穿过太平洋上空的粉色积云...",
            "前方即将到达\(landmark.name)，请准备好您的茶杯...",
            "机长提示：目的地天气晴朗，非常适合户外茶会...",
            "我们的空乘正在准备\(landmark.teaPartyTheme)主题的欢迎仪式...",
            "预计还有几分钟即可抵达\(landmark.subtitle)...",
            "您即将成为获得「\(landmark.badgeName)」徽章的幸运儿..."
        ]
    }
    
    static let arrivalMessages: [String] = [
        "欢迎抵达目的地，茶会即将开始",
        "您已到达梦幻茶会现场，请享受这美好时光",
        "目的地到达！快去打卡获得专属徽章吧",
        "茶会主人正在等待您的到来，请前往主会场"
    ]
}
