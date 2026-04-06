import Foundation

enum OutfitSemanticCategory: String {
    case dress
    case outerwear
    case shoes
    case umbrella
    case accessory
    case other

    var displayName: String {
        switch self {
        case .dress: return "裙装"
        case .outerwear: return "外搭"
        case .shoes: return "鞋履"
        case .umbrella: return "伞具"
        case .accessory: return "配饰"
        case .other: return "其他"
        }
    }
}

enum OutfitLengthCategory: String {
    case extraShort = "超短"
    case short = "短款"
    case midi = "中长"
    case long = "长款"
    case floor = "拖地"
    case unknown = "未知"

    var hemRisk: Int {
        switch self {
        case .extraShort: return 2
        case .short: return 1
        case .midi: return 1
        case .long: return 2
        case .floor: return 3
        case .unknown: return 1
        }
    }
}

enum OutfitMaterialHint: String, CaseIterable, Hashable {
    case cotton = "棉"
    case linen = "麻"
    case chiffon = "雪纺"
    case knit = "针织"
    case wool = "羊毛"
    case velvet = "丝绒"
    case lace = "蕾丝"
    case satin = "缎面"
    case tweed = "粗花呢"
    case fleece = "抓绒"
    case leather = "皮革"
    case rainproof = "防水"

    var aliases: [String] {
        switch self {
        case .cotton:
            return ["棉", "纯棉", "全棉", "棉布"]
        case .linen:
            return ["麻", "亚麻", "苎麻"]
        case .chiffon:
            return ["雪纺", "欧根纱", "纱", "薄纱"]
        case .knit:
            return ["针织", "毛衣", "开衫", "毛线", "线衫"]
        case .wool:
            return ["羊毛", "毛呢", "呢", "羊绒", "羊仔毛"]
        case .velvet:
            return ["丝绒", "天鹅绒", "金丝绒", "灯芯绒", "绒"]
        case .lace:
            return ["蕾丝", "花边", "睫毛蕾丝"]
        case .satin:
            return ["缎", "缎面", "丝", "真丝", "仿真丝"]
        case .tweed:
            return ["粗花呢", "花呢", "斜纹", "格纹呢"]
        case .fleece:
            return ["抓绒", "加绒", "摇粒绒", "绒里"]
        case .leather:
            return ["皮", "皮革", "pu", "漆皮", "麂皮"]
        case .rainproof:
            return ["防水", "雨靴", "晴雨", "防雨", "涉水"]
        }
    }
}

enum OutfitSemanticColorFamily: String, Hashable {
    case pink
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case brown
    case neutral
    case metallic
    case multicolor
}

struct OutfitSemanticProfile {
    let searchableText: String
    let category: OutfitSemanticCategory
    let length: OutfitLengthCategory
    let warmthLevel: Int
    let rainSafetyLevel: Int
    let hemRiskLevel: Int
    let materials: Set<OutfitMaterialHint>
    let seasons: Set<Season>
    let occasions: Set<String>
    let colorFamilies: Set<OutfitSemanticColorFamily>
    let styleHints: Set<String>

    var featureTokens: [String] {
        var tokens: [String] = [category.displayName, "衣长:\(length.rawValue)", "保暖:\(warmthLevel)"]

        if !materials.isEmpty {
            tokens.append("材质:\(materials.map(\.rawValue).sorted().joined(separator: "、"))")
        }
        if !seasons.isEmpty {
            tokens.append("季节:\(seasons.map(\.displayName).sorted().joined(separator: "、"))")
        }
        if !occasions.isEmpty {
            tokens.append("场合:\(occasions.sorted().joined(separator: "、"))")
        }
        if !styleHints.isEmpty {
            tokens.append("风格:\(styleHints.sorted().joined(separator: "、"))")
        }
        if !colorFamilies.isEmpty {
            tokens.append("色系:\(colorFamilies.map(\.rawValue).sorted().joined(separator: "、"))")
        }
        if rainSafetyLevel >= 2 {
            tokens.append("雨天:稳妥")
        }

        return tokens
    }

    var featureBadges: [String] {
        var badges: [String] = []

        if !materials.isEmpty {
            badges.append("材质:\(materials.map(\.rawValue).sorted().prefix(2).joined(separator: "、"))")
        }
        if length != .unknown {
            badges.append("衣长:\(length.rawValue)")
        }
        if !seasons.isEmpty {
            badges.append("季节:\(seasons.map(\.displayName).sorted().prefix(2).joined(separator: "、"))")
        }
        if !occasions.isEmpty {
            badges.append("场合:\(occasions.sorted().prefix(2).joined(separator: "、"))")
        }
        if rainSafetyLevel >= 2 {
            badges.append("雨天稳妥")
        }
        if warmthLevel >= 4 {
            badges.append("偏厚实")
        } else if warmthLevel <= 1 {
            badges.append("偏轻薄")
        }

        return badges
    }
}

struct OutfitRecommendationContext {
    let query: String
    let style: String?
    let occasion: String?
    let weather: WeatherData?
    let season: Season
    let prioritizeWeather: Bool

    init(
        query: String = "",
        style: String? = nil,
        occasion: String? = nil,
        weather: WeatherData? = nil,
        season: Season? = nil,
        prioritizeWeather: Bool = false
    ) {
        self.query = query
        self.style = style
        self.occasion = occasion
        self.weather = weather
        self.season = season ?? OutfitRecommendationKnowledgeBase.inferredSeason(from: weather)
        self.prioritizeWeather = prioritizeWeather
    }
}

enum ClothingSemanticAnalyzer {
    static func searchableText(for clothing: Clothing) -> String {
        let accessoryNames = clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? ""
        let tagNames = clothing.tags?.map(\.name).joined(separator: ",") ?? ""

        return [
            clothing.name,
            clothing.types,
            clothing.colors,
            clothing.length,
            clothing.accessories,
            clothing.note,
            clothing.brand?.name ?? "",
            tagNames,
            accessoryNames
        ]
        .joined(separator: ",")
        .lowercased()
    }

    static func profile(for clothing: Clothing) -> OutfitSemanticProfile {
        let text = searchableText(for: clothing)
        let category = detectCategory(from: text)
        let length = detectLength(from: clothing, text: text, category: category)
        let materials = detectMaterials(in: text)
        let colorFamilies = detectColorFamilies(in: text)
        let styleHints = detectStyleHints(in: text)
        let occasions = detectOccasions(in: text)
        let warmthLevel = detectWarmthLevel(in: text, category: category, materials: materials)
        let seasons = detectSeasons(
            in: text,
            category: category,
            materials: materials,
            warmthLevel: warmthLevel,
            colorFamilies: colorFamilies
        )
        let rainSafetyLevel = detectRainSafetyLevel(
            in: text,
            category: category,
            materials: materials,
            length: length
        )

        return OutfitSemanticProfile(
            searchableText: text,
            category: category,
            length: length,
            warmthLevel: warmthLevel,
            rainSafetyLevel: rainSafetyLevel,
            hemRiskLevel: length.hemRisk,
            materials: materials,
            seasons: seasons,
            occasions: occasions,
            colorFamilies: colorFamilies,
            styleHints: styleHints
        )
    }

    private static func detectCategory(from text: String) -> OutfitSemanticCategory {
        if text.containsAnyKeyword(["雨伞", "晴雨伞", "折叠伞", "防晒伞", "伞"]) {
            return .umbrella
        }
        if text.containsAnyKeyword(["jsk", "op", "sk", "裙", "连衣", "吊带", "半裙"]) {
            return .dress
        }
        if text.containsAnyKeyword([
            "外套", "开衫", "罩衫", "针织", "披肩", "披风", "小外套", "短外套",
            "大衣", "斗篷", "风衣", "夹克", "西装", "西服", "毛衣", "卫衣",
            "上衣", "衬衫", "内搭", "打底", "马甲", "背心", "bolero"
        ]) {
            return .outerwear
        }
        if text.containsAnyKeyword(["鞋", "皮鞋", "高跟", "玛丽珍", "乐福", "靴", "凉鞋", "单鞋", "雨靴"]) {
            return .shoes
        }
        if text.containsAnyKeyword([
            "kc", "头饰", "发带", "发箍", "发夹", "帽", "包", "袜", "手袖",
            "胸针", "项链", "耳饰", "耳环", "腰带", "配饰", "小物"
        ]) {
            return .accessory
        }
        return .other
    }

    private static func detectLength(
        from clothing: Clothing,
        text: String,
        category: OutfitSemanticCategory
    ) -> OutfitLengthCategory {
        let explicit = clothing.length.lowercased()
        let combined = [explicit, text].joined(separator: ",")

        if combined.containsAnyKeyword(["拖地", "及地", "曳地"]) {
            return .floor
        }
        if combined.containsAnyKeyword(["超短", "迷你", "mini"]) {
            return .extraShort
        }
        if combined.containsAnyKeyword(["短款", "短裙", "短"]) && category != .outerwear {
            return .short
        }
        if combined.containsAnyKeyword(["长款", "长裙", "及踝", "过膝", "及小腿"]) {
            return .long
        }
        if combined.containsAnyKeyword(["中长", "及膝", "膝下", "中裙"]) {
            return .midi
        }

        if let numericLength = extractNumericLength(from: explicit) {
            switch numericLength {
            case ..<45:
                return .extraShort
            case 45..<80:
                return .short
            case 80..<105:
                return .midi
            case 105..<120:
                return .long
            default:
                return .floor
            }
        }

        return .unknown
    }

    private static func extractNumericLength(from text: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let lengthRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Double(text[lengthRange])
    }

    private static func detectMaterials(in text: String) -> Set<OutfitMaterialHint> {
        var materials = Set<OutfitMaterialHint>()
        for material in OutfitMaterialHint.allCases where text.containsAnyKeyword(material.aliases) {
            materials.insert(material)
        }
        return materials
    }

    private static func detectColorFamilies(in text: String) -> Set<OutfitSemanticColorFamily> {
        var families = Set<OutfitSemanticColorFamily>()

        if text.containsAnyKeyword(["多色", "彩色", "拼色", "撞色", "multicolor"]) {
            families.insert(.multicolor)
        }
        if text.containsAnyKeyword(["白", "米白", "奶白", "奶油", "象牙", "香槟", "灰", "黑", "银", "米色", "杏色"]) {
            families.insert(.neutral)
        }
        if text.containsAnyKeyword(["金", "银", "metal", "metallic"]) {
            families.insert(.metallic)
        }
        if text.containsAnyKeyword(["粉", "樱", "蜜桃", "桃", "rose", "pink"]) {
            families.insert(.pink)
        }
        if text.containsAnyKeyword(["酒红", "红", "莓", "绯", "赤", "burgundy", "red"]) {
            families.insert(.red)
        }
        if text.containsAnyKeyword(["橙", "杏黄", "珊瑚", "orange", "coral"]) {
            families.insert(.orange)
        }
        if text.containsAnyKeyword(["黄", "鹅黄", "柠檬", "yellow"]) {
            families.insert(.yellow)
        }
        if text.containsAnyKeyword(["若草", "薄荷", "牛油果", "绿", "mint", "green"]) {
            families.insert(.green)
        }
        if text.containsAnyKeyword(["萨克斯", "sax", "绀", "藏青", "海军蓝", "天蓝", "水蓝", "蓝", "blue", "navy"]) {
            families.insert(.blue)
        }
        if text.containsAnyKeyword(["薰衣草", "丁香", "紫", "lavender", "purple"]) {
            families.insert(.purple)
        }
        if text.containsAnyKeyword(["棕", "咖", "巧克力", "驼", "卡其", "brown", "camel", "khaki"]) {
            families.insert(.brown)
        }

        return families
    }

    private static func detectStyleHints(in text: String) -> Set<String> {
        var hints = Set<String>()
        let mappings: [(String, [String])] = [
            ("甜美", ["甜", "樱", "花嫁", "蝴蝶结", "荷叶边", "软妹", "可爱"]),
            ("优雅", ["优雅", "古典", "cla", "classic", "珍珠", "姬袖", "端庄"]),
            ("哥特", ["哥特", "暗黑", "十字架", "修女", "黑系"]),
            ("华丽", ["华丽", "舞会", "重工", "宫廷", "刺绣"]),
            ("清新", ["清新", "薄荷", "铃兰", "花园", "田园"])
        ]

        for (style, keywords) in mappings where text.containsAnyKeyword(keywords) {
            hints.insert(style)
        }

        return hints
    }

    private static func detectOccasions(in text: String) -> Set<String> {
        var occasions = Set<String>()
        let mappings: [(String, [String])] = [
            ("日常", ["日常", "通学", "散步", "出门"]),
            ("约会", ["约会", "见面", "拍照", "甜点店"]),
            ("茶会", ["茶会", "下午茶", "聚会", "茶聚"]),
            ("通勤", ["通勤", "上班", "办公", "会议"]),
            ("出游", ["出游", "旅行", "踏青", "度假"]),
            ("正式", ["婚礼", "宴会", "典礼", "舞会"])
        ]

        for (occasion, keywords) in mappings where text.containsAnyKeyword(keywords) {
            occasions.insert(occasion)
        }

        return occasions
    }

    private static func detectWarmthLevel(
        in text: String,
        category: OutfitSemanticCategory,
        materials: Set<OutfitMaterialHint>
    ) -> Int {
        var warmth = 1

        if category == .outerwear {
            warmth += 1
        }
        if materials.contains(.wool) || materials.contains(.fleece) {
            warmth += 2
        }
        if materials.contains(.knit) || materials.contains(.velvet) || materials.contains(.tweed) {
            warmth += 1
        }
        if materials.contains(.linen) || materials.contains(.chiffon) {
            warmth -= 1
        }
        if text.containsAnyKeyword(["厚", "加厚", "保暖", "冬", "秋冬", "毛绒"]) {
            warmth += 1
        }
        if text.containsAnyKeyword(["薄", "轻薄", "透气", "夏", "春夏"]) {
            warmth -= 1
        }

        return max(0, min(5, warmth))
    }

    private static func detectSeasons(
        in text: String,
        category: OutfitSemanticCategory,
        materials: Set<OutfitMaterialHint>,
        warmthLevel: Int,
        colorFamilies: Set<OutfitSemanticColorFamily>
    ) -> Set<Season> {
        var seasons = Set<Season>()

        if text.containsAnyKeyword(["春", "春日", "春夏"]) {
            seasons.insert(.spring)
        }
        if text.containsAnyKeyword(["夏", "夏日", "盛夏"]) {
            seasons.insert(.summer)
        }
        if text.containsAnyKeyword(["秋", "秋日", "秋冬"]) {
            seasons.insert(.autumn)
        }
        if text.containsAnyKeyword(["冬", "冬日", "严冬"]) {
            seasons.insert(.winter)
        }

        if materials.contains(.linen) || materials.contains(.chiffon) {
            seasons.formUnion([.spring, .summer])
        }
        if materials.contains(.wool) || materials.contains(.fleece) {
            seasons.formUnion([.autumn, .winter])
        }
        if materials.contains(.knit) && !materials.contains(.linen) {
            seasons.formUnion([.spring, .autumn, .winter])
        }

        if warmthLevel >= 4 {
            seasons.formUnion([.autumn, .winter])
        } else if warmthLevel <= 1 {
            seasons.formUnion([.spring, .summer])
        }

        if category == .shoes, colorFamilies.contains(.brown) || colorFamilies.contains(.red) {
            seasons.insert(.autumn)
        }

        return seasons
    }

    private static func detectRainSafetyLevel(
        in text: String,
        category: OutfitSemanticCategory,
        materials: Set<OutfitMaterialHint>,
        length: OutfitLengthCategory
    ) -> Int {
        var score = 1

        if category == .umbrella {
            return 3
        }
        if materials.contains(.rainproof) || text.containsAnyKeyword(["防水", "雨靴", "晴雨"]) {
            score += 2
        }
        if materials.contains(.leather) && text.containsAnyKeyword(["麂皮"]) {
            score -= 2
        }
        if materials.contains(.velvet) || materials.contains(.chiffon) {
            score -= 1
        }
        if category == .dress && length == .floor {
            score -= 1
        }
        if text.containsAnyKeyword(["浅色", "奶白", "白色"]) && category == .shoes {
            score -= 1
        }

        return max(0, min(3, score))
    }
}

enum OutfitRecommendationKnowledgeBase {
    static func inferredSeason(
        from weather: WeatherData?,
        query: String? = nil,
        referenceDate: Date = Date()
    ) -> Season {
        if let explicitSeason = primaryRequestedSeason(in: query) {
            return explicitSeason
        }

        let month = Calendar.current.component(.month, from: referenceDate)

        if let weather {
            let feelsLike = weather.feelsLikeTemperature
            switch feelsLike {
            case ..<10:
                return .winter
            case 10..<20:
                return (3...5).contains(month) ? .spring : .autumn
            case 20..<28:
                if (6...8).contains(month) {
                    return .summer
                }
                if (9...11).contains(month) {
                    return .autumn
                }
                return .spring
            default:
                return .summer
            }
        }

        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    private static func primaryRequestedSeason(in text: String?) -> Season? {
        guard let normalized = text?.lowercased(), !normalized.isEmpty else {
            return nil
        }

        if normalized.containsAnyKeyword(["春", "春天", "春季", "春日", "春夏"]) {
            return .spring
        }
        if normalized.containsAnyKeyword(["夏", "夏天", "夏季", "夏日", "盛夏", "春夏"]) {
            return .summer
        }
        if normalized.containsAnyKeyword(["秋", "秋天", "秋季", "秋日", "秋冬", "初秋"]) {
            return .autumn
        }
        if normalized.containsAnyKeyword(["冬", "冬天", "冬季", "冬日", "严冬", "秋冬"]) {
            return .winter
        }

        return nil
    }

    static func requestedSeasons(in text: String?) -> Set<Season> {
        guard let text = text?.lowercased(), !text.isEmpty else {
            return []
        }

        var seasons = Set<Season>()
        if text.containsAnyKeyword(["春", "春天", "春季", "春日", "春夏"]) {
            seasons.insert(.spring)
        }
        if text.containsAnyKeyword(["夏", "夏天", "夏季", "夏日", "盛夏", "春夏"]) {
            seasons.insert(.summer)
        }
        if text.containsAnyKeyword(["秋", "秋天", "秋季", "秋日", "秋冬", "初秋"]) {
            seasons.insert(.autumn)
        }
        if text.containsAnyKeyword(["冬", "冬天", "冬季", "冬日", "严冬", "秋冬"]) {
            seasons.insert(.winter)
        }
        return seasons
    }

    static func preferredColors(for season: Season) -> [String] {
        season.recommendedColors
    }

    static func weatherColors(for weather: WeatherData?) -> [String] {
        guard let weather else { return [] }
        return weather.condition.recommendedColors + weather.temperatureColors
    }

    static func styleKeywords(for style: String?) -> [String] {
        guard let style else { return [] }
        let lower = style.lowercased()

        if lower.contains("甜美") || lower.contains("sweet") {
            return ["粉", "樱", "蜜桃", "桃", "蕾丝", "蝴蝶结", "荷叶边", "可爱"]
        }
        if lower.contains("优雅") || lower.contains("elegant") || lower.contains("classic") || lower.contains("cla") {
            return ["优雅", "古典", "珍珠", "姬袖", "缎面", "端庄", "长款"]
        }
        if lower.contains("哥特") || lower.contains("gothic") {
            return ["黑", "暗", "酒红", "哥特", "十字架", "修女", "蕾丝"]
        }
        if lower.contains("防雨") || lower.contains("rain") || lower.contains("稳妥") {
            return ["防水", "雨", "厚", "稳", "藏青", "黑", "灰"]
        }

        return []
    }

    static func occasionKeywords(for occasion: String?) -> [String] {
        guard let occasion else { return [] }
        let lower = occasion.lowercased()

        if lower.contains("约会") || lower.contains("date") {
            return ["约会", "甜美", "浪漫", "精致", "花"]
        }
        if lower.contains("茶会") || lower.contains("tea") {
            return ["茶会", "优雅", "古典", "经典", "姬袖", "长款"]
        }
        if lower.contains("通勤") || lower.contains("work") {
            return ["通勤", "简约", "衬衫", "西装", "低调"]
        }
        if lower.contains("出游") || lower.contains("旅行") {
            return ["出游", "轻便", "舒适", "防晒", "耐走"]
        }

        return ["日常", "舒适", "出门"]
    }
}

enum OutfitRecommendationScorer {
    static func isEligible(_ clothing: Clothing, in context: OutfitRecommendationContext) -> Bool {
        let profile = ClothingSemanticAnalyzer.profile(for: clothing)
        let requestedSeasons = OutfitRecommendationKnowledgeBase.requestedSeasons(in: context.query)
        let lowerQuery = context.query.lowercased()
        let targetsSummer = requestedSeasons.contains(.summer) || (requestedSeasons.isEmpty && context.season == .summer)

        if !requestedSeasons.isEmpty {
            if !profile.seasons.isEmpty, requestedSeasons.isDisjoint(with: profile.seasons) {
                return false
            }
        }

        if targetsSummer,
           profile.warmthLevel >= 3,
           (profile.category == .dress || profile.category == .outerwear) {
            return false
        }

        if targetsSummer, profile.category == .outerwear {
            let text = profile.searchableText
            let explicitlyRequestedOuterwear = lowerQuery.containsAnyKeyword([
                "外套", "开衫", "罩衫", "披肩", "防晒", "防晒衣", "空调衫", "薄外套", "薄开衫", "小外套", "背心", "马甲"
            ])
            let lightweightOuterwear = isLightweightOuterwear(profile: profile, text: text)
            let heavyOuterwear = isHeavyOuterwear(profile: profile, text: text)

            // 夏季下不推荐冬季大衣类重外搭，即使用户只说“+1”或“加外套”也优先轻外搭。
            if heavyOuterwear {
                return false
            }
            // 未明确要求外搭时，只允许轻外搭进入候选池。
            if !explicitlyRequestedOuterwear && !lightweightOuterwear {
                return false
            }
        }

        if requestedSeasons.contains(.winter),
           profile.warmthLevel <= 1,
           (profile.category == .dress || profile.category == .outerwear) {
            return false
        }

        guard let weather = context.weather, context.prioritizeWeather else {
            return true
        }

        let feelsLike = weather.feelsLikeTemperature
        let isRainy = rainy(weather)

        if isRainy && profile.category == .shoes && profile.rainSafetyLevel == 0 {
            return false
        }
        if feelsLike >= 30 && profile.warmthLevel >= 4 && (profile.category == .dress || profile.category == .outerwear) {
            return false
        }
        if weather.windSpeed >= 9, profile.category == .dress, profile.hemRiskLevel >= 3 {
            return false
        }

        return true
    }

    static func score(_ clothing: Clothing, in context: OutfitRecommendationContext) -> Int {
        let profile = ClothingSemanticAnalyzer.profile(for: clothing)
        let text = profile.searchableText
        let lowerQuery = context.query.lowercased()
        let requestedSeasons = OutfitRecommendationKnowledgeBase.requestedSeasons(in: lowerQuery)
        var score = 10

        for token in queryTokens(lowerQuery) where !token.isEmpty {
            if text.contains(token) {
                score += 4
            }
            if clothing.name.lowercased().contains(token) {
                score += 6
            }
        }

        for keyword in OutfitRecommendationKnowledgeBase.styleKeywords(for: context.style) where text.contains(keyword.lowercased()) {
            score += 9
        }
        for keyword in OutfitRecommendationKnowledgeBase.occasionKeywords(for: context.occasion) where text.contains(keyword.lowercased()) {
            score += 8
        }

        if profile.category == .dress && text.containsAnyKeyword(["jsk", "op", "sk"]) {
            score += 12
        }

        if profile.seasons.contains(context.season) {
            score += 18
        } else if !profile.seasons.isEmpty {
            score -= 6
        }

        if !requestedSeasons.isEmpty {
            if !profile.seasons.isEmpty {
                if !requestedSeasons.isDisjoint(with: profile.seasons) {
                    score += 16
                } else {
                    score -= 18
                }
            } else if requestedSeasons.contains(.summer) {
                score += profile.warmthLevel <= 2 ? 10 : -12
            } else if requestedSeasons.contains(.winter) {
                score += profile.warmthLevel >= 3 ? 10 : -10
            } else if requestedSeasons.contains(.autumn) || requestedSeasons.contains(.spring) {
                if (1...3).contains(profile.warmthLevel) {
                    score += 8
                }
            }
        }

        if context.season == .summer, profile.category == .outerwear {
            let text = profile.searchableText
            if isHeavyOuterwear(profile: profile, text: text) {
                score -= 42
            } else if isLightweightOuterwear(profile: profile, text: text) {
                score += 12
            } else {
                score -= 18
            }
        }

        let seasonColors = OutfitRecommendationKnowledgeBase.preferredColors(for: context.season)
        if text.containsAnyKeyword(seasonColors) {
            score += 10
        }

        if let weather = context.weather {
            let feelsLike = weather.feelsLikeTemperature
            let isRainy = rainy(weather)
            let weatherColors = OutfitRecommendationKnowledgeBase.weatherColors(for: weather)

            if text.containsAnyKeyword(weatherColors) {
                score += 8
            }

            switch feelsLike {
            case ..<10:
                score += profile.warmthLevel >= 4 ? 24 : -10
            case 10..<18:
                if (2...4).contains(profile.warmthLevel) {
                    score += 18
                } else if profile.warmthLevel == 0 {
                    score -= 10
                }
            case 18..<25:
                if (1...3).contains(profile.warmthLevel) {
                    score += 14
                }
            case 25..<30:
                score += profile.warmthLevel <= 2 ? 16 : -16
            default:
                score += profile.warmthLevel <= 1 ? 22 : -22
            }

            if isRainy {
                if profile.category == .umbrella {
                    score += 35
                }
                score += profile.rainSafetyLevel * 10
                if profile.category == .shoes && profile.rainSafetyLevel <= 1 {
                    score -= 20
                }
                if profile.category == .dress && profile.hemRiskLevel >= 2 {
                    score -= 12
                }
            }

            if weather.windSpeed >= 6 {
                if profile.category == .outerwear {
                    score += 14
                }
                if profile.category == .dress {
                    score -= profile.hemRiskLevel * 4
                }
            }
        }

        let daysSinceCreation = Date().timeIntervalSince(clothing.createdAt) / 86_400
        if daysSinceCreation < 7 {
            score += 8
        } else if daysSinceCreation < 30 {
            score += 3
        }

        return score
    }

    private static func rainy(_ weather: WeatherData) -> Bool {
        switch weather.condition {
        case .lightRain, .moderateRain, .heavyRain, .thunderstorm:
            return true
        default:
            return false
        }
    }

    private static func isLightweightOuterwear(profile: OutfitSemanticProfile, text: String) -> Bool {
        text.containsAnyKeyword([
            "薄", "轻薄", "透气", "防晒", "薄针织", "罩衫", "空调", "短外套", "短款开衫", "薄开衫", "背心", "马甲", "坎肩"
        ]) || profile.warmthLevel <= 1
    }

    private static func isHeavyOuterwear(profile: OutfitSemanticProfile, text: String) -> Bool {
        text.containsAnyKeyword([
            "大衣", "斗篷", "风衣", "夹克", "卫衣", "毛衣", "西装", "西服", "羽绒", "棉服", "毛呢", "呢子", "加厚", "秋冬"
        ]) || profile.warmthLevel >= 3
    }

    private static func queryTokens(_ query: String) -> [String] {
        query
            .components(separatedBy: CharacterSet(charactersIn: "，。！？、,!?：:；; \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    func containsAnyKeyword(_ keywords: [String]) -> Bool {
        keywords.contains { keyword in
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && contains(trimmed.lowercased())
        }
    }
}
