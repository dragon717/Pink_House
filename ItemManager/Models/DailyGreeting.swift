import Foundation

// MARK: - 时间段类型
enum TimeOfDay: String, Codable, CaseIterable {
    case dawn       // 凌晨 (0-5点)
    case morning    // 清晨/早晨 (5-12点)
    case noon       // 中午 (12-14点)
    case afternoon  // 下午 (14-18点)
    case evening    // 晚上 (18-22点)
    case night      // 深夜 (22-24点)
    
    /// 根据小时数获取时间段
    static func from(hour: Int) -> TimeOfDay {
        switch hour {
        case 0..<5:   return .dawn
        case 5..<12:  return .morning
        case 12..<14: return .noon
        case 14..<18: return .afternoon
        case 18..<22: return .evening
        default:      return .night
        }
    }
    
    /// 当前时间段
    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        return from(hour: hour)
    }
    
    /// 时间段显示名称
    var displayName: String {
        switch self {
        case .dawn:      return "凌晨"
        case .morning:   return "清晨"
        case .noon:      return "中午"
        case .afternoon: return "下午"
        case .evening:   return "晚上"
        case .night:     return "深夜"
        }
    }
    
    /// 问候语前缀（用于AI生成提示）
    var greetingPrefix: String {
        switch self {
        case .dawn:
            return "凌晨时分，万籁俱寂"
        case .morning:
            return "晨光熹微，新的一天开始"
        case .noon:
            return "正午阳光正好"
        case .afternoon:
            return "午后时光，悠闲惬意"
        case .evening:
            return "夜幕降临，华灯初上"
        case .night:
            return "夜深人静，星光点点"
        }
    }
}

// MARK: - 每日问候语数据
struct DailyGreeting: Codable, Identifiable {
    let id: String
    let date: Date
    let timeOfDay: TimeOfDay
    let messages: [String] // 3条问候语，带•符号
    let source: String // 来源：cloudkit/ai/local
    let createdAt: Date

    var localizedMessages: [String] {
        guard source == "local" else { return messages }
        return messages.map { $0.appLocalized }
    }
    
    /// 获取第一条问候语作为主问候
    var primaryMessage: String {
        localizedMessages.first?
            .replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
    
    /// 获取格式化的完整问候语（用于分享等）
    var formattedMessages: String {
        return localizedMessages.joined(separator: "\n\n")
    }
}

// MARK: - AI生成的问候语响应结构
struct GreetingAIResponse: Codable {
    let messages: [String] // 3条问候语数组
    
    /// 确保每条问候语都有•符号前缀
    var formattedMessages: [String] {
        return messages.map { message in
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("•") {
                return trimmed
            } else {
                return "• \(trimmed)"
            }
        }
    }
}

// MARK: - 本地问候语模板（AI失败时的回退）
struct GreetingTemplates {
    /// 按时间段分类的文艺哲理问候语模板（每时段10条，确保每天都不一样）
    static let templates: [TimeOfDay: [String]] = [
        .dawn: [
            "• 星光不问赶路人，时光不负有心人。",
            "• 黎明前的黑暗，孕育着最美的光。",
            "• 世界还在沉睡，而你已在路上。",
            "• 日出之前，是最深的宁静。",
            "• 每一个清晨，都是世界的新生。",
            "• 早起的人，配得上最美的朝阳。",
            "• 夜色褪去时，梦想开始发芽。",
            "• 凌晨的风，吹散昨日的疲惫。",
            "• 天快亮了，愿你被温柔唤醒。",
            "• 新的一天，从这一刻开始。"
        ],
        .morning: [
            "• 心有山海，静而无边。",
            "• 晨光熹微，万物可期。",
            "• 每一天都是余生中最年轻的一天。",
            "• 向阳而生，逐光而行。",
            "• 生活明朗，万物可爱。",
            "• 凡是过往，皆为序章。",
            "• 保持热爱，奔赴山海。",
            "• 今日份的美好，正在派送中。",
            "• 愿你眼里有光，心中有爱。",
            "• 早安世界，今天也要加油呀。"
        ],
        .noon: [
            "• 阳光正好，不负韶华。",
            "• 正午的阳光，是生活最热烈的告白。",
            "• 忙碌的日子里，也要记得停下来看看云。",
            "• 午间小憩，是给灵魂的礼物。",
            "• 阳光洒满窗台，心情也要晒晒太阳。",
            "• 正午时分，愿你有片刻宁静。",
            "• 生活再忙，也要记得好好吃饭。",
            "• 午后的风，会带来好消息。",
            "• 阳光正好，适合想念。",
            "• 愿你被这世界温柔以待。"
        ],
        .afternoon: [
            "• 午后时光慢，岁月静好处。",
            "• 温柔半两，从容一生。",
            "• 慢下来，才能看见生活的诗意。",
            "• 下午茶时间，适合与自己对话。",
            "• 阳光斜斜地照进来，像一封旧信。",
            "• 慵懒的午后，是生活的小确幸。",
            "• 时光不语，却回答了所有问题。",
            "• 愿你的烦恼，都随风而去。",
            "• 午后阳光，是金色的温柔。",
            "• 静享此刻，便是最好的时光。"
        ],
        .evening: [
            "• 岁月漫长，然而值得等待。",
            "• 今夜月色真美，风也温柔。",
            "• 星河滚烫，你是人间理想。",
            "• 夜幕降临，愿你被世界温柔以待。",
            "• 晚风很温柔，像你一样。",
            "• 今夜星光为你守护。",
            "• 月亮不睡，我不睡，我是人间小美味。",
            "• 愿你的梦里，有星辰大海。",
            "• 夜色很美，但你更美。",
            "• 把今天的疲惫，都交给夜晚。"
        ],
        .night: [
            "• 愿你的生活，一半烟火，一半清欢。",
            "• 夜深人静时，适合与自己和解。",
            "• 梦里不知身是客，一晌贪欢。",
            "• 深夜的星光，是宇宙的情书。",
            "• 愿你的梦境，如诗如画。",
            "• 睡吧，明天又是新的一天。",
            "• 夜深人静，只有星星在值班。",
            "• 愿你醒来时，阳光正好。",
            "• 把思念装进梦里，等你去打开。",
            "• 晚安，愿好梦如约而至。"
        ]
    ]
    
    /// 获取指定日期和时间段的问候语（确保每天都不一样）
    static func template(for date: Date, timeOfDay: TimeOfDay) -> [String] {
        guard let dayTemplates = templates[timeOfDay], !dayTemplates.isEmpty else {
            return ["• 岁月漫长，然而值得等待。"]
        }
        
        // 使用日期作为种子，确保同一天同一时段总是返回相同的问候语
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let year = calendar.component(.year, from: date)
        
        // 根据日期计算索引，确保每天不同
        let index = (dayOfYear + year) % dayTemplates.count
        return [dayTemplates[index]]
    }
}
