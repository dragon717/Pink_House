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
    static func pickWeatherOutfitItems(
        from clothings: [Clothing],
        weather: WeatherData? = nil,
        stylePreference: String? = nil
    ) -> WeatherWardrobeSelection {
        let availableClothings = OutfitRecommendability.recommendableClothings(from: clothings)
        let context = OutfitRecommendationContext(
            query: stylePreference ?? "",
            style: stylePreference,
            weather: weather,
            season: OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: stylePreference),
            prioritizeWeather: true
        )

        let eligible = availableClothings.filter { OutfitRecommendationScorer.isEligible($0, in: context) }
        let source = eligible.isEmpty ? availableClothings : eligible
        let ordered = source.sorted {
            let lhs = OutfitRecommendationScorer.score($0, in: context)
            let rhs = OutfitRecommendationScorer.score($1, in: context)
            if lhs == rhs {
                return $0.createdAt > $1.createdAt
            }
            return lhs > rhs
        }

        let outerwears = selectItems(from: ordered, category: .outerwear, limit: 2)
        var dresses = selectItems(from: ordered, category: .dress, limit: 3)
        let shoes = selectItems(from: ordered, category: .shoes, limit: 2)
        let umbrellas = selectItems(from: ordered, category: .umbrella, limit: 2)

        if dresses.isEmpty {
            dresses = Array(ordered.prefix(min(3, ordered.count)))
        }

        return WeatherWardrobeSelection(
            outerwears: outerwears,
            dresses: dresses,
            shoes: shoes,
            umbrellas: umbrellas
        )
    }
    
    static func buildWeatherAdvice(weather: WeatherData?, selection: WeatherWardrobeSelection) -> String {
        var lines: [String] = []
        
        if let weather {
            let feelsLike = Int(weather.feelsLikeTemperature.rounded())
            let windText = String(format: "%.1f", weather.windSpeed)
            let season = OutfitRecommendationKnowledgeBase.inferredSeason(from: weather)
            let colorHint = OutfitRecommendationKnowledgeBase.preferredColors(for: season)
                .prefix(2)
                .joined(separator: "、")
            lines.append("\(weather.city)现在\(weather.condition.rawValue)，气温\(Int(weather.temperature.rounded()))°C，体感大约\(feelsLike)°C，风速\(windText)m/s。")
            lines.append(weatherExplanation(weather))
            lines.append("这次我会优先看\(season.displayName)更合适的\(colorHint)这类颜色。")
        } else {
            lines.append("我先按稳妥方案给你搭一版。")
        }

        let availableCount =
            min(selection.outerwears.count, 1) +
            min(selection.dresses.count, 1) +
            min(selection.shoes.count, 1) +
            min(selection.umbrellas.count, 1)

        if availableCount > 0 {
            let pickedSummary = summarize(selection: selection)
            if !pickedSummary.isEmpty {
                lines.append(pickedSummary)
            }
            lines.append("我把可选单品整理在下面了，你可以左右滑动看看。")
        } else {
            lines.append("我先给你一个稳妥方向，下面点开天气卡片看详情。")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func selectItems(
        from ordered: [Clothing],
        category: OutfitSemanticCategory,
        limit: Int
    ) -> [Clothing] {
        Array(
            ordered
                .filter { ClothingSemanticAnalyzer.profile(for: $0).category == category }
                .prefix(limit)
        )
    }

    private static func summarize(selection: WeatherWardrobeSelection) -> String {
        var parts: [String] = []

        if let outerwear = selection.outerwears.first {
            parts.append("外套：\(outerwear.name)")
        }
        if let dress = selection.dresses.first {
            parts.append("裙子：\(dress.name)")
        }
        if let shoe = selection.shoes.first {
            parts.append("鞋子：\(shoe.name)")
        }
        if let umbrella = selection.umbrellas.first {
            parts.append("伞：\(umbrella.name)")
        }

        return parts.joined(separator: "\n")
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
