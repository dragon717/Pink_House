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
            subtitle: "裙子+鞋子+伞",
            icon: "cloud.sun.rain.fill",
            prompt: "帮我看下天气，并结合衣橱推荐裙子、鞋子和伞。"
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
    let dresses: [Clothing]
    let shoes: [Clothing]
    let umbrellas: [Clothing]
    
    var combinedItems: [Clothing] {
        var seen = Set<UUID>()
        var merged: [Clothing] = []
        for item in dresses + shoes + umbrellas {
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
    private static let shoeKeywords = ["鞋", "皮鞋", "高跟", "玛丽珍", "乐福", "靴", "凉鞋", "单鞋"]
    private static let umbrellaKeywords = ["伞", "雨伞", "晴雨伞", "折叠伞", "防晒伞"]
    
    static func pickWeatherOutfitItems(from clothings: [Clothing]) -> WeatherWardrobeSelection {
        // 过滤掉心愿尾款的裙装（只从已到手单品中选择）
        let availableClothings = clothings.filter { !$0.isDepositPlan }
        let ordered = availableClothings.sorted { $0.createdAt > $1.createdAt }

        var dresses: [Clothing] = []
        var shoes: [Clothing] = []
        var umbrellas: [Clothing] = []

        for clothing in ordered {
            let searchable = buildSearchableText(for: clothing)

            if dresses.count < 3, containsAny(in: searchable, keywords: dressKeywords) {
                dresses.append(clothing)
            }
            if shoes.count < 2, containsAny(in: searchable, keywords: shoeKeywords) {
                shoes.append(clothing)
            }
            if umbrellas.count < 2, containsAny(in: searchable, keywords: umbrellaKeywords) {
                umbrellas.append(clothing)
            }

            if dresses.count >= 3, shoes.count >= 2, umbrellas.count >= 2 {
                break
            }
        }

        if dresses.isEmpty {
            dresses = Array(ordered.prefix(min(3, ordered.count)))
        }

        return WeatherWardrobeSelection(dresses: dresses, shoes: shoes, umbrellas: umbrellas)
    }
    
    static func buildWeatherAdvice(weather: WeatherData?, selection: WeatherWardrobeSelection) -> String {
        var lines: [String] = []
        
        if let weather {
            lines.append("我查到\(weather.city)现在\(weather.condition.rawValue)，\(Int(weather.temperature))°C。")
            lines.append(temperatureHint(weather.temperature))
            
            if isRainy(weather.condition) {
                lines.append("今天有降水风险，建议优先防水鞋并带伞。")
            } else if weather.condition == .sunny {
                lines.append("阳光较强，浅色系穿搭会更清爽，记得做好防晒。")
            }
        } else {
            lines.append("我暂时没拿到实时天气，先按稳妥方案给你推荐。")
        }
        
        lines.append("裙子：\(itemNames(selection.dresses, fallback: "先从你最喜欢的主裙入手"))")
        lines.append("鞋子：\(itemNames(selection.shoes, fallback: "可以搭配玛丽珍鞋或浅色单鞋"))")
        
        let umbrellaFallback = isRainy(weather?.condition) ? "建议备一把透明雨伞" : "可选防晒伞或晴雨伞"
        lines.append("伞具：\(itemNames(selection.umbrellas, fallback: umbrellaFallback))")
        lines.append("要不要告诉我你是通勤、约会还是散步？我再帮你细化一版。")
        
        return lines.joined(separator: "\n")
    }
    
    private static func buildSearchableText(for clothing: Clothing) -> String {
        let accessoryNames = clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? ""
        return [
            clothing.name,
            clothing.types,
            clothing.accessories,
            clothing.note,
            accessoryNames
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
    
    private static func itemNames(_ items: [Clothing], fallback: String) -> String {
        guard !items.isEmpty else { return fallback }
        return items.prefix(3).map(\.name).joined(separator: "、")
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
    
    private static func temperatureHint(_ temperature: Double) -> String {
        switch temperature {
        case ..<8:
            return "气温偏低，建议加外套和厚袜。"
        case 8..<18:
            return "温度偏凉，薄外套会更舒适。"
        case 18..<28:
            return "温度舒适，常规裙装就很好看。"
        default:
            return "天气偏热，尽量选轻薄透气面料。"
        }
    }
}
