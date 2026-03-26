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

struct ColorRecommendation {
    let primaryColor: String
    let secondaryColor: String
    let accentColor: String
    let description: String
    let reasoning: String
}
