import Foundation

enum PetChatMessageType {
    case text
    case wardrobeCard
    case statistics
    case colorMatch
    case searchResults
    case thinking
    case outfitSuggestion
}

struct OutfitSuggestionData {
    let clothings: [Clothing]
    let description: String
    let style: String
    let occasion: String
    let layoutInfos: [LayoutInfo]?
}

struct PetChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let isUserAuthored: Bool
    let type: PetChatMessageType
    let timestamp: Date
    var clothing: Clothing?
    var searchResults: [Clothing]?
    var statistics: WardrobeStats?
    var colorRecommendation: ColorRecommendation?
    var imageName: String?
    var isAIGenerated: Bool
    var outfitSuggestion: OutfitSuggestionData?
    var widgets: [PetWidgetData]?

    init(text: String, isUser: Bool, type: PetChatMessageType = .text,
         isUserAuthored: Bool? = nil,
         clothing: Clothing? = nil, searchResults: [Clothing]? = nil,
         statistics: WardrobeStats? = nil, colorRecommendation: ColorRecommendation? = nil,
         imageName: String? = nil, isAIGenerated: Bool = false,
         timestamp: Date = Date(),
         outfitSuggestion: OutfitSuggestionData? = nil,
         widgets: [PetWidgetData]? = nil) {
        self.text = text
        self.isUser = isUser
        self.isUserAuthored = isUserAuthored ?? isUser
        self.type = type
        self.timestamp = timestamp
        self.clothing = clothing
        self.searchResults = searchResults
        self.statistics = statistics
        self.colorRecommendation = colorRecommendation
        self.imageName = imageName
        self.isAIGenerated = isAIGenerated
        self.outfitSuggestion = outfitSuggestion
        self.widgets = widgets
    }
}

struct WardrobeStats {
    let totalCount: Int
    let totalValue: Decimal
    let mostExpensiveItem: Clothing?
    let depositPlanCount: Int
    let totalDeposit: Decimal
    let totalBalance: Decimal
}

struct ColorRecommendation: Codable {
    let primaryColor: String
    let secondaryColor: String
    let accentColor: String
    let description: String
    let reasoning: String
}

enum PetChatExpressionMeaning: String {
    case happy
    case confused
    case thinking
    case sleepy
    case angry
    case neutral
}

extension PetCharacter {
    var confusedImageName: String {
        curiousImageName
    }

    var neutralImageName: String {
        quickOptionIconName
    }

    func chatExpressionImageName(for meaning: PetChatExpressionMeaning) -> String {
        switch meaning {
        case .happy:
            return happyImageName
        case .confused:
            return confusedImageName
        case .thinking:
            return thinkingImageName
        case .sleepy:
            return sleepyImageName
        case .angry:
            return angryImageName
        case .neutral:
            return neutralImageName
        }
    }
}

func detectPetChatExpressionMeaning(in text: String) -> PetChatExpressionMeaning? {
    let normalized = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    guard !normalized.isEmpty else { return nil }

    let angryKeywords = ["炸毛", "生气", "不可以", "不行", "余额不足", "不够", "别想", "拒绝"]
    if angryKeywords.contains(where: normalized.contains) {
        return .angry
    }

    let sleepyKeywords = ["困", "好累", "睡", "休息", "卡了一下", "等半分钟", "想太久", "太久啦"]
    if sleepyKeywords.contains(where: normalized.contains) {
        return .sleepy
    }

    let confusedKeywords = ["疑惑", "没听懂", "没懂", "理解错", "歪头", "挠头", "再想想", "再说一次", "卡壳", "不太确定"]
    if confusedKeywords.contains(where: normalized.contains) {
        return .confused
    }

    let thinkingKeywords = ["思考", "想想", "看看", "我来找", "我来想", "我来算", "分析", "整理"]
    if thinkingKeywords.contains(where: normalized.contains) {
        return .thinking
    }

    let happyKeywords = ["开心", "太棒", "好耶", "眼睛发亮", "蹭蹭", "抱抱", "抱住", "喜欢", "没问题", "好哒", "安排", "准备好了", "走吧"]
    if happyKeywords.contains(where: normalized.contains) {
        return .happy
    }

    return nil
}
