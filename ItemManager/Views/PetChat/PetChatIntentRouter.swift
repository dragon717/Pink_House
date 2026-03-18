import Foundation

enum PetChatIntent: Equatable {
    case wardrobeStats
    case outfitSuggestion
    case lastOutfitPrice
    case weatherGuidance
    case colorMatch
    case search
    case depositPlan
    case moodSupport
    case generalChat

    var module: PetConversationModule {
        switch self {
        case .wardrobeStats:
            return .wardrobe
        case .outfitSuggestion:
            return .outfit
        case .lastOutfitPrice:
            return .wardrobe
        case .weatherGuidance:
            return .weather
        case .colorMatch:
            return .outfit
        case .search:
            return .wardrobe
        case .depositPlan:
            return .wardrobe
        case .moodSupport:
            return .mood
        case .generalChat:
            return .general
        }
    }
}

enum PetChatIntentRouter {
    private static let statKeywords = ["统计", "多少", "价值", "几件"]
    private static let outfitKeywords = ["ootd", "造型", "穿搭", "怎么穿"]
    private static let outfitComboKeywords = ["搭配"]
    private static let outfitScenarioKeywords = ["一套", "出门", "今天"]
    private static let lastOutfitPriceKeywords = ["刚刚搭配", "上一套搭配", "刚才那套", "三件衣服", "价格多少", "总价多少", "那套多少钱"]
    private static let weatherKeywords = ["天气", "温度", "下雨", "雨伞", "风大"]
    private static let colorKeywords = ["搭配", "颜色", "穿什么", "推荐"]
    private static let searchKeywords = ["找", "搜索", "有没有"]
    private static let depositKeywords = ["尾款", "定金", "补款"]
    private static let moodKeywords = ["难过", "焦虑", "压力", "委屈", "心情", "安慰", "陪陪我", "emo", "emo了"]

    static func detect(from text: String) -> PetChatIntent {
        let lower = text.lowercased()

        if containsAny(statKeywords, in: lower) {
            return .wardrobeStats
        }
        if containsAny(lastOutfitPriceKeywords, in: lower),
           containsAny(["价格", "总价", "多少钱"], in: lower) {
            return .lastOutfitPrice
        }
        if containsAny(outfitKeywords, in: lower) {
            return .outfitSuggestion
        }
        if containsAny(outfitComboKeywords, in: lower),
           containsAny(outfitScenarioKeywords, in: lower) {
            return .outfitSuggestion
        }
        if containsAny(weatherKeywords, in: lower) {
            return .weatherGuidance
        }
        if containsAny(colorKeywords, in: lower) {
            return .colorMatch
        }
        if containsAny(searchKeywords, in: lower) {
            return .search
        }
        if containsAny(depositKeywords, in: lower) {
            return .depositPlan
        }
        if containsAny(moodKeywords, in: lower) {
            return .moodSupport
        }
        return .generalChat
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
