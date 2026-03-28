import Foundation

struct PetGuidedChoice: Identifiable, Equatable {
    let id: String   // A / B / C
    let title: String
    let subtitle: String
    let icon: String
    let prompt: String
    
    static let defaults: [PetGuidedChoice] = [
        PetGuidedChoice(
            id: "A",
            title: "A 场景搭配",
            subtitle: "通勤/约会/出游",
            icon: "figure.walk",
            prompt: "我今天要出门，请按场景帮我搭配一套穿搭。"
        ),
        PetGuidedChoice(
            id: "B",
            title: "B 天气穿搭",
            subtitle: "外套+裙子+鞋子+伞",
            icon: "cloud.sun.rain.fill",
            prompt: "帮我看下天气，并结合衣橱推荐外套、裙子、鞋子和伞。"
        ),
        PetGuidedChoice(
            id: "C",
            title: "C 情绪陪伴",
            subtitle: "先聊聊心情",
            icon: "heart.text.square.fill",
            prompt: "我现在心情有点复杂，先陪我聊聊，再给我温柔一点的穿搭建议。"
        )
    ]
}

struct WeatherWardrobeSelection {
    let outerwears: [Clothing]
    let dresses: [Clothing]
    let shoes: [Clothing]
    let umbrellas: [Clothing]

    init(
        outerwears: [Clothing] = [],
        dresses: [Clothing],
        shoes: [Clothing],
        umbrellas: [Clothing]
    ) {
        self.outerwears = outerwears
        self.dresses = dresses
        self.shoes = shoes
        self.umbrellas = umbrellas
    }
    
    var combinedItems: [Clothing] {
        var seen = Set<UUID>()
        var merged: [Clothing] = []
        for item in outerwears + dresses + shoes + umbrellas {
            if seen.insert(item.id).inserted {
                merged.append(item)
            }
            if merged.count >= 6 {
                break
            }
        }
        return merged
    }
}

enum PetChatGuidanceEngine {
    private static let dressKeywords = ["jsk", "op", "sk", "裙", "连衣", "吊带", "半裙"]
    private static let outerwearKeywords = ["外套", "开衫", "罩衫", "针织", "针织衫", "披肩", "坎肩", "披风", "小外套", "短外套", "大衣", "斗篷", "风衣", "夹克", "西装", "西服", "毛衣", "卫衣", "上衣", "衬衫", "内搭", "打底", "马甲", "背心"]
    private static let shoeKeywords = ["鞋", "皮鞋", "高跟", "玛丽珍", "乐福", "靴", "凉鞋", "单鞋"]
    private static let umbrellaKeywords = ["伞", "雨伞", "晴雨伞", "折叠伞", "防晒伞"]
    
    static func pickWeatherOutfitItems(from clothings: [Clothing], stylePreference: String? = nil) -> WeatherWardrobeSelection {
        // 过滤掉心愿尾款的裙装（只从已到手单品中选择）
        let availableClothings = clothings.filter { !$0.isDepositPlan }
        
        // 根据风格偏好排序
        let ordered: [Clothing]
        if let stylePreference = stylePreference, !stylePreference.isEmpty {
            ordered = availableClothings.sorted { 
                let score1 = calculateStyleScore(for: $0, style: stylePreference)
                let score2 = calculateStyleScore(for: $1, style: stylePreference)
                if score1 != score2 {
                    return score1 > score2
                }
                return $0.createdAt > $1.createdAt
            }
        } else {
            ordered = availableClothings.sorted { $0.createdAt > $1.createdAt }
        }

        var outerwears: [Clothing] = []
        var dresses: [Clothing] = []
        var shoes: [Clothing] = []
        var umbrellas: [Clothing] = []

        for clothing in ordered {
            let searchable = buildSearchableText(for: clothing)

            if outerwears.count < 2, containsAny(in: searchable, keywords: outerwearKeywords) {
                outerwears.append(clothing)
            }
            if dresses.count < 3, containsAny(in: searchable, keywords: dressKeywords) {
                dresses.append(clothing)
            }
            if shoes.count < 2, containsAny(in: searchable, keywords: shoeKeywords) {
                shoes.append(clothing)
            }
            if umbrellas.count < 2, containsAny(in: searchable, keywords: umbrellaKeywords) {
                umbrellas.append(clothing)
            }

            if outerwears.count >= 2, dresses.count >= 3, shoes.count >= 2, umbrellas.count >= 2 {
                break
            }
        }

        if dresses.isEmpty {
            dresses = Array(ordered.prefix(min(3, ordered.count)))
        }

        return WeatherWardrobeSelection(outerwears: outerwears, dresses: dresses, shoes: shoes, umbrellas: umbrellas)
    }
    
    /// 根据风格计算单品评分
    private static func calculateStyleScore(for clothing: Clothing, style: String) -> Int {
        var score = 0
        let searchable = buildSearchableText(for: clothing)
        let lowerStyle = style.lowercased()
        
        // 甜美风格关键词
        if lowerStyle.contains("甜美") || lowerStyle.contains("sweet") {
            let sweetKeywords = ["粉", "樱", "蜜桃", "桃", "玫瑰", "蕾丝", "蝴蝶结", "荷叶边", "蓬蓬", "可爱", "软妹", "甜"]
            for keyword in sweetKeywords where containsAny(in: searchable, keywords: [keyword]) {
                score += 10
            }
        }
        
        // 优雅风格关键词
        if lowerStyle.contains("优雅") || lowerStyle.contains("elegant") {
            let elegantKeywords = ["优雅", "精致", "缎面", "丝质", "珍珠", "古典", "cla", "classic", "姬袖", "长款", "端庄"]
            for keyword in elegantKeywords where containsAny(in: searchable, keywords: [keyword]) {
                score += 10
            }
        }
        
        // 防雨风格关键词
        if lowerStyle.contains("防雨") || lowerStyle.contains("rain") || lowerStyle.contains("稳妥") {
            let rainKeywords = ["防水", "雨", "厚", "保暖", "稳妥", "安全", "深色", "黑", "灰", "藏青", "绀"]
            for keyword in rainKeywords where containsAny(in: searchable, keywords: [keyword]) {
                score += 10
            }
        }
        
        return score
    }
    
    static func buildWeatherAdvice(weather: WeatherData?, selection: WeatherWardrobeSelection) -> String {
        var lines: [String] = []
        
        if let weather {
            let feelsLike = Int(weather.feelsLikeTemperature.rounded())
            let windText = String(format: "%.1f", weather.windSpeed)
            lines.append("\(weather.city)现在\(weather.condition.rawValue)，气温\(Int(weather.temperature.rounded()))°C，体感\(feelsLike)°C，风速\(windText)m/s。")
            lines.append(weatherExplanation(weather))
        } else {
            lines.append("我先按稳妥方案给你搭一版。")
        }

        let availableCount =
            min(selection.outerwears.count, 1) +
            min(selection.dresses.count, 1) +
            min(selection.shoes.count, 1) +
            min(selection.umbrellas.count, 1)

        if availableCount > 0 {
            lines.append("我把可选单品整理在下面了，你可以左右滑动看看。")
        } else {
            lines.append("我先给你一个稳妥方向，下面点开天气卡片看详情。")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func buildSearchableText(for clothing: Clothing) -> String {
        let accessoryNames = clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? ""
        let tagNames = clothing.tags?.map(\.name).joined(separator: ",") ?? ""
        return [
            clothing.name,
            clothing.types,
            clothing.colors,
            clothing.accessories,
            clothing.note,
            accessoryNames,
            clothing.brand?.name ?? "",
            tagNames
        ]
        .joined(separator: ",")
        .lowercased()
    }
    
    private static func containsAny(in text: String, keywords: [String]) -> Bool {
        for keyword in keywords where text.contains(keyword.lowercased()) {
            return true
        }
        return false
    }
    
    private static func isRainy(_ condition: WeatherCondition?) -> Bool {
        guard let condition else { return false }
        switch condition {
        case .lightRain, .moderateRain, .heavyRain, .thunderstorm:
            return true
        default:
            return false
        }
    }
    
    private static func weatherExplanation(_ weather: WeatherData) -> String {
        let feelsLike = weather.feelsLikeTemperature
        let rainClause = isRainy(weather.condition) ? "，雨天鞋子和伞也尽量选稳一点" : ""

        switch feelsLike {
        case ..<12:
            return "今天偏冷，最好带外套\(rainClause)。"
        case 12..<18:
            return "今天偏凉，薄外套或开衫会更舒服\(rainClause)。"
        case 18..<24:
            if weather.windSpeed >= 5 {
                return "风有点明显，带件薄外套会更安心\(rainClause)。"
            }
            return "体感还算舒服，常规裙装就可以\(rainClause)。"
        default:
            if weather.windSpeed < 4, !isRainy(weather.condition) {
                return "今天偏暖，通常不用特地带外套。"
            }
            return "虽然温度高一点，但带件轻薄外搭会更灵活\(rainClause)。"
        }
    }
}
