import Foundation
import SwiftData

// MARK: - 搭配建议响应结构
/// AI返回的搭配建议数据结构
struct OutfitSuggestionResponse {
    let description: String
    let selectedItemNames: [String]
    let selectedItemIDs: [UUID]
    let style: String
    let occasion: String
    let reasoning: String
}

// MARK: - 搭配建议服务
/// 处理AI搭配建议的完整流程：从LLM响应到创建Outfit
class OutfitSuggestionService {
    static let shared = OutfitSuggestionService()

    private init() {}

    private var currentCharacter: PetCharacter {
        PetDataManager.shared.getCurrentPetCharacter()
    }

    private func localizedCatchphraseText(_ text: String) -> String {
        currentCharacter.localizedCatchphraseText(text)
    }

    // MARK: - 主要流程

    /// 处理用户的搭配请求
    /// - Parameters:
    ///   - query: 用户输入（如"帮我搭配一套粉色系的出门装"）
    ///   - clothings: 用户衣橱中的所有裙装
    ///   - context: ModelContext 用于数据库操作
    /// - Returns: 推荐的裙装列表和响应文本
    func processOutfitRequest(
        query: String,
        clothings: [Clothing],
        context: ModelContext,
        weather: WeatherData? = nil
    ) async throws -> ([Clothing], String, String, String) {
        // 只从已到手、当前可穿的单品里推荐。
        let availableClothings = OutfitRecommendability.recommendableClothings(from: clothings)
        
        // 检查是否有足够的非心愿尾款裙装
        guard availableClothings.count >= 2 else {
            throw OutfitSuggestionError.insufficientNonDepositItems
        }

        let suggestionContext = OutfitRecommendationContext(
            query: query,
            weather: weather,
            season: OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: query),
            prioritizeWeather: weather != nil
        )
        let eligibleClothings = availableClothings.filter { OutfitRecommendationScorer.isEligible($0, in: suggestionContext) }
        let promptClothings = eligibleClothings.isEmpty ? availableClothings : eligibleClothings
        
        // 1. 调用 AI 获取搭配建议
        let suggestion = try await fetchOutfitSuggestionFromAI(
            query: query,
            clothings: promptClothings,
            weather: weather
        )

        // 2. 获取推荐的裙装
        let matchedClothings = matchSelectedClothings(suggestion: suggestion, clothings: promptClothings)
        let colorRefined = OutfitColorHarmonyEngine.refineSelection(
            matchedClothings,
            within: promptClothings
        )
        let recommendationContext = OutfitRecommendationContext(
            query: query,
            style: suggestion.style,
            occasion: suggestion.occasion,
            weather: weather,
            season: OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: query),
            prioritizeWeather: weather != nil
        )
        let selectedClothings = reconcileSelection(
            preferred: colorRefined,
            fallbackPool: promptClothings,
            context: recommendationContext,
            minimumCount: 2,
            maximumCount: 4
        )

        guard !selectedClothings.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }

        // 3. 构建响应文本
        let responseText = buildResponseText(suggestion: suggestion, clothings: selectedClothings)

        return (selectedClothings, responseText, suggestion.style, suggestion.occasion)
    }

    /// 快速创建搭配（无需 AI，基于规则）
    /// - Parameters:
    ///   - style: 风格（甜美/优雅/哥特等）
    ///   - occasion: 场合（日常/约会/茶会等）
    ///   - clothings: 用户衣橱
    ///   - context: ModelContext
    /// - Returns: 推荐的裙装列表
    func createQuickOutfit(
        style: String,
        occasion: String,
        clothings: [Clothing],
        context: ModelContext,
        weather: WeatherData? = nil
    ) async throws -> [Clothing] {
        // 只从已到手、当前可穿的单品里推荐。
        let availableClothings = OutfitRecommendability.recommendableClothings(from: clothings)
        
        // 检查是否有足够的非心愿尾款裙装
        guard availableClothings.count >= 2 else {
            throw OutfitSuggestionError.insufficientNonDepositItems
        }
        
        // 根据风格和场景对裙装进行评分排序
        let rankingContext = OutfitRecommendationContext(
            style: style,
            occasion: occasion,
            weather: weather,
            season: OutfitRecommendationKnowledgeBase.inferredSeason(from: weather),
            prioritizeWeather: weather != nil
        )
        let eligible = availableClothings.filter { OutfitRecommendationScorer.isEligible($0, in: rankingContext) }
        let rankingPool = eligible.isEmpty ? availableClothings : eligible
        let scoredClothings = rankingPool.map { clothing in
            (clothing: clothing, score: calculateOutfitScore(clothing: clothing, context: rankingContext))
        }.sorted { $0.score > $1.score }
        
        // 从高评分的裙装中选择
        var result: [Clothing] = []
        
        // 先按类别分组
        let grouped = Dictionary(grouping: scoredClothings) { item -> OutfitSemanticCategory in
            ClothingSemanticAnalyzer.profile(for: item.clothing).category
        }
        
        // 优先选择裙装（选择评分最高的）
        if let dresses = grouped[.dress], !dresses.isEmpty {
            let bestDress = dresses.max { $0.score < $1.score }!.clothing
            result.append(bestDress)
        }
        
        // 选择外套（选择评分最高的且与裙装颜色和谐的）
        if let tops = grouped[.outerwear], !tops.isEmpty {
            let sortedTops = tops.sorted { $0.score > $1.score }
            if let bestTop = sortedTops.first?.clothing {
                result.append(bestTop)
            }
        }
        
        // 选择鞋子（选择评分最高的）
        if let shoes = grouped[.shoes], !shoes.isEmpty {
            let sortedShoes = shoes.sorted { $0.score > $1.score }
            if let bestShoe = sortedShoes.first?.clothing {
                result.append(bestShoe)
            }
        }
        
        // 选择配饰（选择评分最高的 1-2 个）
        if let accessories = grouped[.accessory], !accessories.isEmpty {
            let sortedAccessories = accessories.sorted { $0.score > $1.score }
            result.append(contentsOf: sortedAccessories.prefix(2).map { $0.clothing })
        }
        
        // 如果按分类选择后数量不足，从高评分列表中补充
        if result.count < 2 {
            let remaining = scoredClothings.filter { item in
                !result.contains { $0.id == item.clothing.id }
            }
            result.append(contentsOf: remaining.prefix(4 - result.count).map { $0.clothing })
        }
        
        // 如果还是不足，随机选择补充
        if result.count < 2 {
            let remaining = rankingPool.filter { !result.contains($0) }
            result.append(contentsOf: remaining.shuffled().prefix(2 - result.count))
        }
        
        // 使用颜色和谐引擎优化
        result = OutfitColorHarmonyEngine.refineSelection(result, within: rankingPool)
        
        guard result.count >= 2 else {
            throw OutfitSuggestionError.insufficientItems
        }
        
        return result
    }

    func extendOutfit(
        baseSuggestion: OutfitSuggestionData,
        query: String,
        clothings: [Clothing],
        weather: WeatherData? = nil
    ) throws -> ([Clothing], String) {
        let baseClothings = baseSuggestion.clothings
        guard !baseClothings.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }

        let baseIDs = Set(baseClothings.map(\.id))
        let season = inferredContinuationSeason(
            query: query,
            baseSuggestion: baseSuggestion,
            baseClothings: baseClothings,
            weather: weather
        )
        let context = OutfitRecommendationContext(
            query: query,
            style: baseSuggestion.style,
            occasion: baseSuggestion.occasion,
            weather: weather,
            season: season,
            prioritizeWeather: weather != nil
        )
        let desiredCategories = preferredAugmentCategories(
            from: query,
            baseClothings: baseClothings,
            season: season
        )
        let desiredColors = preferredAugmentColors(from: query)
        let baseProfiles = baseClothings.map { ClothingSemanticAnalyzer.profile(for: $0) }
        let existingCategories = Set(baseProfiles.map(\.category))
        let existingColors = baseProfiles.reduce(into: Set<OutfitSemanticColorFamily>()) { partialResult, profile in
            partialResult.formUnion(profile.colorFamilies)
        }
        let explicitCategories = Set(preferredReplaceCategories(from: query))

        let candidates = OutfitRecommendability
            .recommendableClothings(from: clothings)
            .filter { !baseIDs.contains($0.id) }

        guard !candidates.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }
        let eligibleCandidates = candidates.filter { OutfitRecommendationScorer.isEligible($0, in: context) }
        let rankingPoolBase = eligibleCandidates.isEmpty ? candidates : eligibleCandidates
        let rankingPool = try constrainAugmentCandidates(
            rankingPoolBase,
            query: query,
            explicitCategories: explicitCategories
        )

        let ordered = rankingPool.sorted { lhs, rhs in
            let left = augmentScore(
                clothing: lhs,
                context: context,
                desiredCategories: desiredCategories,
                desiredColors: desiredColors,
                existingCategories: existingCategories,
                existingColors: existingColors
            )
            let right = augmentScore(
                clothing: rhs,
                context: context,
                desiredCategories: desiredCategories,
                desiredColors: desiredColors,
                existingCategories: existingCategories,
                existingColors: existingColors
            )

            if left == right {
                return lhs.createdAt > rhs.createdAt
            }
            return left > right
        }

        guard let picked = ordered.first else {
            throw OutfitSuggestionError.noItemsAvailable
        }

        let updatedClothings = baseClothings + [picked]
        let response = buildAugmentResponse(
            picked: picked,
            updatedClothings: updatedClothings,
            style: baseSuggestion.style,
            occasion: baseSuggestion.occasion,
            query: query
        )
        return (updatedClothings, response)
    }

    func replaceOutfitItem(
        baseSuggestion: OutfitSuggestionData,
        query: String,
        clothings: [Clothing],
        weather: WeatherData? = nil
    ) throws -> ([Clothing], String) {
        let baseClothings = baseSuggestion.clothings
        guard !baseClothings.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }

        let explicitCategories = preferredReplaceCategories(from: query)
        let hasExplicitCategory = !explicitCategories.isEmpty
        let (replaceIndex, removedItem) = resolveReplacementTarget(
            from: baseClothings,
            explicitCategories: explicitCategories
        )

        let remainingClothings = baseClothings.enumerated()
            .filter { $0.offset != replaceIndex }
            .map(\.element)
        let removedProfile = ClothingSemanticAnalyzer.profile(for: removedItem)
        let desiredCategories = dedupeCategories(
            explicitCategories + [removedProfile.category, .outerwear, .accessory, .shoes, .umbrella, .dress, .other]
        )
        let desiredColors = preferredAugmentColors(from: query)
        let season = inferredContinuationSeason(
            query: query,
            baseSuggestion: baseSuggestion,
            baseClothings: baseClothings,
            weather: weather
        )
        let context = OutfitRecommendationContext(
            query: query,
            style: baseSuggestion.style,
            occasion: baseSuggestion.occasion,
            weather: weather,
            season: season,
            prioritizeWeather: weather != nil
        )
        let existingProfiles = remainingClothings.map { ClothingSemanticAnalyzer.profile(for: $0) }
        let existingCategories = Set(existingProfiles.map(\.category))
        let existingColors = existingProfiles.reduce(into: Set<OutfitSemanticColorFamily>()) { partialResult, profile in
            partialResult.formUnion(profile.colorFamilies)
        }
        let baseIDs = Set(baseClothings.map(\.id))
        let candidates = OutfitRecommendability
            .recommendableClothings(from: clothings)
            .filter { !baseIDs.contains($0.id) }

        guard !candidates.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }
        let eligibleCandidates = candidates.filter { OutfitRecommendationScorer.isEligible($0, in: context) }
        let rankingPoolBase = eligibleCandidates.isEmpty ? candidates : eligibleCandidates
        let rankingPool = try constrainReplaceCandidates(
            rankingPoolBase,
            query: query,
            explicitCategories: Set(explicitCategories)
        )

        let allowDressReplacement = hasExplicitCategory
            ? explicitCategories.contains(.dress)
            : removedProfile.category == .dress
        let ordered = rankingPool.sorted { lhs, rhs in
            let left = replacementScore(
                clothing: lhs,
                context: context,
                removedCategory: removedProfile.category,
                desiredCategories: desiredCategories,
                desiredColors: desiredColors,
                existingCategories: existingCategories,
                existingColors: existingColors,
                hasExplicitCategory: hasExplicitCategory,
                allowDressReplacement: allowDressReplacement
            )
            let right = replacementScore(
                clothing: rhs,
                context: context,
                removedCategory: removedProfile.category,
                desiredCategories: desiredCategories,
                desiredColors: desiredColors,
                existingCategories: existingCategories,
                existingColors: existingColors,
                hasExplicitCategory: hasExplicitCategory,
                allowDressReplacement: allowDressReplacement
            )

            if left == right {
                return lhs.createdAt > rhs.createdAt
            }
            return left > right
        }

        guard let picked = ordered.first else {
            throw OutfitSuggestionError.noItemsAvailable
        }

        var updatedClothings = baseClothings
        updatedClothings[replaceIndex] = picked
        let response = buildReplaceResponse(
            removed: removedItem,
            picked: picked,
            updatedClothings: updatedClothings,
            style: baseSuggestion.style,
            occasion: baseSuggestion.occasion,
            query: query
        )
        return (updatedClothings, response)
    }
    
    /// 根据风格和场景计算裙装评分
    private func calculateOutfitScore(clothing: Clothing, context: OutfitRecommendationContext) -> Int {
        OutfitRecommendationScorer.score(clothing, in: context)
    }

    private func reconcileSelection(
        preferred: [Clothing],
        fallbackPool: [Clothing],
        context: OutfitRecommendationContext,
        minimumCount: Int,
        maximumCount: Int
    ) -> [Clothing] {
        let pool = dedupeClothings(fallbackPool)
        let eligiblePool = pool.filter { OutfitRecommendationScorer.isEligible($0, in: context) }
        let basePool = eligiblePool.isEmpty ? pool : eligiblePool
        let baseIDs = Set(basePool.map(\.id))

        var result = dedupeClothings(
            preferred.filter { baseIDs.contains($0.id) && OutfitRecommendationScorer.isEligible($0, in: context) }
        )
        var used = Set(result.map(\.id))

        if result.count < minimumCount {
            let candidates = basePool
                .filter { !used.contains($0.id) }
                .sorted { lhs, rhs in
                    let left = OutfitRecommendationScorer.score(lhs, in: context)
                    let right = OutfitRecommendationScorer.score(rhs, in: context)
                    if left == right {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return left > right
                }

            for item in candidates where result.count < maximumCount {
                if used.insert(item.id).inserted {
                    result.append(item)
                }
                if result.count >= minimumCount {
                    break
                }
            }
        }

        if result.count > maximumCount {
            result = Array(
                result.sorted { lhs, rhs in
                    let left = OutfitRecommendationScorer.score(lhs, in: context)
                    let right = OutfitRecommendationScorer.score(rhs, in: context)
                    if left == right {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return left > right
                }
                .prefix(maximumCount)
            )
        }

        return result
    }

    private func dedupeClothings(_ clothings: [Clothing]) -> [Clothing] {
        var seen = Set<UUID>()
        return clothings.filter { seen.insert($0.id).inserted }
    }
    
    /// 获取裙装的可搜索文本
    private func searchableText(for clothing: Clothing) -> String {
        ClothingSemanticAnalyzer.searchableText(for: clothing)
    }
    
    /// 检查文本是否包含任意关键词
    private func matchesAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }
    
    /// 获取风格对应的关键词
    private func getStyleKeywords(_ style: String) -> [String] {
        let lowerStyle = style.lowercased()
        
        if lowerStyle.contains("甜美") || lowerStyle.contains("sweet") {
            return ["粉", "樱", "蜜桃", "桃", "玫瑰", "蕾丝", "蝴蝶结", "荷叶边", "蓬蓬", "可爱", "软妹", "甜", "洛丽塔", "lolita"]
        } else if lowerStyle.contains("优雅") || lowerStyle.contains("elegant") {
            return ["优雅", "精致", "缎面", "丝质", "珍珠", "古典", "cla", "classic", "姬袖", "长款", "端庄"]
        } else if lowerStyle.contains("哥特") || lowerStyle.contains("gothic") {
            return ["黑", "暗", "哥特", "gothic", "蕾丝", "十字架", "朋克", "酷", "暗黑"]
        } else if lowerStyle.contains("日常") || lowerStyle.contains("casual") {
            return ["日常", "休闲", "简单", "轻便", "舒适", "棉", "麻"]
        } else {
            return ["裙", "jsk", "op", "sk"]
        }
    }
    
    /// 获取场景对应的关键词
    private func getOccasionKeywords(_ occasion: String) -> [String] {
        let lowerOccasion = occasion.lowercased()
        
        if lowerOccasion.contains("约会") || lowerOccasion.contains("date") {
            return ["约会", "浪漫", "甜美", "可爱", "精致", "粉", "红"]
        } else if lowerOccasion.contains("茶会") || lowerOccasion.contains("tea") {
            return ["茶会", "优雅", "精致", "cla", "classic", "长款", "姬袖"]
        } else if lowerOccasion.contains("通勤") || lowerOccasion.contains("work") {
            return ["通勤", "日常", "简约", "干练", "西装", "衬衫"]
        } else if lowerOccasion.contains("出门") || lowerOccasion.contains("go out") {
            return ["日常", "休闲", "轻便", "舒适"]
        } else {
            return ["日常"]
        }
    }
    
    /// 获取风格偏好的颜色
    private func getPreferredColors(_ style: String) -> [String] {
        let lowerStyle = style.lowercased()
        
        if lowerStyle.contains("甜美") || lowerStyle.contains("sweet") {
            return ["粉", "樱", "蜜桃", "桃", "白", "米白", "奶白"]
        } else if lowerStyle.contains("优雅") || lowerStyle.contains("elegant") {
            return ["白", "米白", "奶白", "香槟", "绀", "藏青", "酒红", "棕", "灰"]
        } else if lowerStyle.contains("哥特") || lowerStyle.contains("gothic") {
            return ["黑", "暗", "酒红", "紫", "绀"]
        } else {
            return []
        }
    }

    private func preferredAugmentCategories(
        from query: String,
        baseClothings: [Clothing],
        season: Season
    ) -> [OutfitSemanticCategory] {
        let lower = query.lowercased()
        let existingCategories = Set(baseClothings.map { ClothingSemanticAnalyzer.profile(for: $0).category })
        var categories: [OutfitSemanticCategory] = []

        if matchesAny(lower, keywords: ["开衫", "外套", "罩衫", "披肩", "斗篷", "小外套", "内搭", "衬衫", "马甲"]) {
            categories.append(.outerwear)
        }
        if matchesAny(lower, keywords: ["小物", "配饰", "头饰", "发带", "包", "袜", "手袖"]) {
            categories.append(.accessory)
        }
        if matchesAny(lower, keywords: ["鞋", "鞋子", "玛丽珍", "凉鞋", "单鞋", "靴"]) {
            categories.append(.shoes)
        }
        if matchesAny(lower, keywords: ["伞", "雨伞", "晴雨伞"]) {
            categories.append(.umbrella)
        }
        if matchesAny(lower, keywords: ["裙", "jsk", "op", "sk"]) {
            categories.append(.dress)
        }

        if categories.isEmpty {
            let isGenericPlusOne = matchesAny(lower, keywords: [
                "+1", "＋1", "加1", "加一", "加一件", "再来一件", "补一件", "添一件"
            ])
            if isGenericPlusOne {
                // 对“+1”默认先补轻量单品，避免直接补冬季重外搭。
                if !existingCategories.contains(.accessory) { categories.append(.accessory) }
                if !existingCategories.contains(.shoes) { categories.append(.shoes) }
                if !existingCategories.contains(.outerwear) { categories.append(.outerwear) }
            } else if season == .summer {
                if !existingCategories.contains(.accessory) { categories.append(.accessory) }
                if !existingCategories.contains(.shoes) { categories.append(.shoes) }
                if !existingCategories.contains(.outerwear) { categories.append(.outerwear) }
            } else {
                if !existingCategories.contains(.outerwear) { categories.append(.outerwear) }
                if !existingCategories.contains(.accessory) { categories.append(.accessory) }
                if !existingCategories.contains(.shoes) { categories.append(.shoes) }
            }
        }

        categories.append(contentsOf: [.outerwear, .accessory, .shoes, .umbrella, .dress, .other])
        return dedupeCategories(categories)
    }

    private func inferredContinuationSeason(
        query: String,
        baseSuggestion: OutfitSuggestionData,
        baseClothings: [Clothing],
        weather: WeatherData?
    ) -> Season {
        let explicitSeasons = OutfitRecommendationKnowledgeBase.requestedSeasons(in: query)
        if !explicitSeasons.isEmpty {
            return OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: query)
        }

        let baseHintText = [
            baseSuggestion.description,
            baseSuggestion.style,
            baseSuggestion.occasion,
            baseClothings.map(\.name).joined(separator: " "),
            baseClothings.map(\.note).joined(separator: " ")
        ]
        .joined(separator: " ")
        let hintedSeasons = OutfitRecommendationKnowledgeBase.requestedSeasons(in: baseHintText)
        if !hintedSeasons.isEmpty {
            return OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: baseHintText)
        }

        if weather != nil {
            return OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: query)
        }

        var seasonFrequency: [Season: Int] = [:]
        for clothing in baseClothings {
            let profile = ClothingSemanticAnalyzer.profile(for: clothing)
            for season in profile.seasons {
                seasonFrequency[season, default: 0] += 1
            }
        }

        if let maxCount = seasonFrequency.values.max(), maxCount > 0 {
            let candidates = seasonFrequency
                .filter { $0.value == maxCount }
                .map(\.key)
            for season in [Season.summer, .spring, .autumn, .winter] where candidates.contains(season) {
                return season
            }
        }

        return OutfitRecommendationKnowledgeBase.inferredSeason(from: weather, query: query)
    }

    private func preferredAugmentColors(from query: String) -> Set<OutfitSemanticColorFamily> {
        let lower = query.lowercased()
        var result = Set<OutfitSemanticColorFamily>()

        if matchesAny(lower, keywords: ["粉", "樱", "蜜桃", "桃", "玫瑰", "pink"]) { result.insert(.pink) }
        if matchesAny(lower, keywords: ["红", "酒红", "莓", "red"]) { result.insert(.red) }
        if matchesAny(lower, keywords: ["橙", "珊瑚", "orange"]) { result.insert(.orange) }
        if matchesAny(lower, keywords: ["黄", "鹅黄", "奶油黄", "yellow"]) { result.insert(.yellow) }
        if matchesAny(lower, keywords: ["绿", "薄荷", "抹茶", "green"]) { result.insert(.green) }
        if matchesAny(lower, keywords: ["蓝", "天蓝", "水蓝", "藏青", "blue", "navy"]) { result.insert(.blue) }
        if matchesAny(lower, keywords: ["紫", "薰衣草", "lavender", "purple"]) { result.insert(.purple) }
        if matchesAny(lower, keywords: ["棕", "咖", "奶茶", "brown", "camel", "khaki"]) { result.insert(.brown) }
        if matchesAny(lower, keywords: ["白", "米白", "杏", "灰", "黑", "银", "neutral"]) { result.insert(.neutral) }
        if matchesAny(lower, keywords: ["金", "银", "metal", "metallic"]) { result.insert(.metallic) }
        if matchesAny(lower, keywords: ["彩色", "拼色", "撞色", "multicolor"]) { result.insert(.multicolor) }

        return result
    }

    private func constrainAugmentCandidates(
        _ candidates: [Clothing],
        query: String,
        explicitCategories: Set<OutfitSemanticCategory>
    ) throws -> [Clothing] {
        var pool = candidates
        let explicitWarm = isExplicitWarmOuterwearRequest(query)

        if explicitCategories.count == 1, explicitCategories.contains(.outerwear) {
            pool = pool.filter { ClothingSemanticAnalyzer.profile(for: $0).category == .outerwear }
        }

        if !explicitWarm {
            // 非明确保暖语义时，重外搭不进入补件候选（即使点击 +1 也不补大衣）。
            let filtered = pool.filter { clothing in
                let profile = ClothingSemanticAnalyzer.profile(for: clothing)
                guard profile.category == .outerwear else { return true }
                return !isHeavyOuterwear(profile: profile, text: profile.searchableText)
            }
            if !filtered.isEmpty {
                pool = filtered
            }
        }

        if isExplicitLightOuterwearRequest(query) {
            let lightOuterwear = pool.filter { clothing in
                let profile = ClothingSemanticAnalyzer.profile(for: clothing)
                let text = profile.searchableText
                return profile.category == .outerwear
                    && isLightweightOuterwear(profile: profile, text: text)
                    && !isHeavyOuterwear(profile: profile, text: text)
            }
            guard !lightOuterwear.isEmpty else {
                throw OutfitSuggestionError.noItemsAvailable
            }
            return lightOuterwear
        }

        if isExplicitWarmOuterwearRequest(query) {
            let warmOuterwear = pool.filter { clothing in
                let profile = ClothingSemanticAnalyzer.profile(for: clothing)
                let text = profile.searchableText
                return profile.category == .outerwear
                    && isHeavyOuterwear(profile: profile, text: text)
            }
            guard !warmOuterwear.isEmpty else {
                throw OutfitSuggestionError.noItemsAvailable
            }
            return warmOuterwear
        }

        guard !pool.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }
        return pool
    }

    private func constrainReplaceCandidates(
        _ candidates: [Clothing],
        query: String,
        explicitCategories: Set<OutfitSemanticCategory>
    ) throws -> [Clothing] {
        var pool = candidates
        let explicitWarm = isExplicitWarmOuterwearRequest(query)

        if explicitCategories.count == 1, explicitCategories.contains(.outerwear) {
            pool = pool.filter { ClothingSemanticAnalyzer.profile(for: $0).category == .outerwear }
        }

        if !explicitWarm {
            // 非明确保暖语义时，替换也不回退到重外搭。
            let filtered = pool.filter { clothing in
                let profile = ClothingSemanticAnalyzer.profile(for: clothing)
                guard profile.category == .outerwear else { return true }
                return !isHeavyOuterwear(profile: profile, text: profile.searchableText)
            }
            if !filtered.isEmpty {
                pool = filtered
            }
        }

        if isExplicitLightOuterwearRequest(query) {
            let lightOuterwear = pool.filter { clothing in
                let profile = ClothingSemanticAnalyzer.profile(for: clothing)
                let text = profile.searchableText
                return profile.category == .outerwear
                    && isLightweightOuterwear(profile: profile, text: text)
                    && !isHeavyOuterwear(profile: profile, text: text)
            }
            guard !lightOuterwear.isEmpty else {
                throw OutfitSuggestionError.noItemsAvailable
            }
            return lightOuterwear
        }

        if isExplicitWarmOuterwearRequest(query) {
            let warmOuterwear = pool.filter { clothing in
                let profile = ClothingSemanticAnalyzer.profile(for: clothing)
                let text = profile.searchableText
                return profile.category == .outerwear
                    && isHeavyOuterwear(profile: profile, text: text)
            }
            guard !warmOuterwear.isEmpty else {
                throw OutfitSuggestionError.noItemsAvailable
            }
            return warmOuterwear
        }

        guard !pool.isEmpty else {
            throw OutfitSuggestionError.noItemsAvailable
        }
        return pool
    }

    private func isExplicitLightOuterwearRequest(_ query: String) -> Bool {
        let lower = query.lowercased()
        return matchesAny(lower, keywords: [
            "开衫", "薄开衫", "薄外套", "轻薄", "防晒", "防晒衣", "罩衫", "空调衫", "背心", "马甲", "坎肩"
        ])
    }

    private func isExplicitWarmOuterwearRequest(_ query: String) -> Bool {
        let lower = query.lowercased()
        return matchesAny(lower, keywords: [
            "大衣", "厚外套", "保暖", "秋冬", "冬季", "呢子", "毛呢", "羽绒", "棉服", "夹克", "风衣", "卫衣", "毛衣"
        ])
    }

    private func isLightweightOuterwear(profile: OutfitSemanticProfile, text: String) -> Bool {
        matchesAny(text, keywords: [
            "薄", "轻薄", "透气", "防晒", "薄针织", "罩衫", "空调", "短外套", "短款开衫", "薄开衫", "背心", "马甲", "坎肩"
        ]) || profile.warmthLevel <= 1
    }

    private func isHeavyOuterwear(profile: OutfitSemanticProfile, text: String) -> Bool {
        matchesAny(text, keywords: [
            "大衣", "斗篷", "风衣", "夹克", "卫衣", "毛衣", "西装", "西服", "羽绒", "棉服", "毛呢", "呢子", "加厚", "秋冬"
        ]) || profile.warmthLevel >= 3
    }

    private func preferredReplaceCategories(from query: String) -> [OutfitSemanticCategory] {
        let lower = query.lowercased()
        var categories: [OutfitSemanticCategory] = []

        if matchesAny(lower, keywords: ["开衫", "外套", "罩衫", "披肩", "斗篷", "小外套", "内搭", "衬衫", "马甲"]) {
            categories.append(.outerwear)
        }
        if matchesAny(lower, keywords: ["小物", "配饰", "头饰", "发带", "包", "袜", "手袖", "kc"]) {
            categories.append(.accessory)
        }
        if matchesAny(lower, keywords: ["鞋", "鞋子", "玛丽珍", "凉鞋", "单鞋", "靴"]) {
            categories.append(.shoes)
        }
        if matchesAny(lower, keywords: ["伞", "雨伞", "晴雨伞"]) {
            categories.append(.umbrella)
        }
        if matchesAny(lower, keywords: ["主裙", "裙", "jsk", "op", "sk"]) {
            categories.append(.dress)
        }

        return dedupeCategories(categories)
    }

    private func resolveReplacementTarget(
        from baseClothings: [Clothing],
        explicitCategories: [OutfitSemanticCategory]
    ) -> (Int, Clothing) {
        let profiles = baseClothings.map { ClothingSemanticAnalyzer.profile(for: $0) }

        if let explicitCategory = explicitCategories.first,
           let explicitIndex = profiles.lastIndex(where: { $0.category == explicitCategory }) {
            return (explicitIndex, baseClothings[explicitIndex])
        }

        let preferredOrder: [OutfitSemanticCategory] = [.outerwear, .accessory, .shoes, .umbrella, .other, .dress]
        for category in preferredOrder {
            if let index = profiles.lastIndex(where: { $0.category == category }) {
                return (index, baseClothings[index])
            }
        }

        let fallbackIndex = max(0, baseClothings.count - 1)
        return (fallbackIndex, baseClothings[fallbackIndex])
    }

    private func augmentScore(
        clothing: Clothing,
        context: OutfitRecommendationContext,
        desiredCategories: [OutfitSemanticCategory],
        desiredColors: Set<OutfitSemanticColorFamily>,
        existingCategories: Set<OutfitSemanticCategory>,
        existingColors: Set<OutfitSemanticColorFamily>
    ) -> Int {
        let profile = ClothingSemanticAnalyzer.profile(for: clothing)
        var score = calculateOutfitScore(clothing: clothing, context: context)

        if let desiredIndex = desiredCategories.firstIndex(of: profile.category) {
            score += max(8, 32 - desiredIndex * 6)
        }

        if !desiredColors.isEmpty, !profile.colorFamilies.isDisjoint(with: desiredColors) {
            score += 18
        } else if !existingColors.isEmpty, !profile.colorFamilies.isDisjoint(with: existingColors) {
            score += 12
        }

        if profile.category == .dress, existingCategories.contains(.dress), !matchesAny(context.query.lowercased(), keywords: ["裙", "jsk", "op", "sk"]) {
            score -= 18
        }

        if profile.category == .outerwear, !existingCategories.contains(.outerwear) {
            score += 10
        }
        if profile.category == .accessory, !existingCategories.contains(.accessory) {
            score += 8
        }
        if profile.category == .shoes, !existingCategories.contains(.shoes) {
            score += 6
        }

        return score
    }

    private func replacementScore(
        clothing: Clothing,
        context: OutfitRecommendationContext,
        removedCategory: OutfitSemanticCategory,
        desiredCategories: [OutfitSemanticCategory],
        desiredColors: Set<OutfitSemanticColorFamily>,
        existingCategories: Set<OutfitSemanticCategory>,
        existingColors: Set<OutfitSemanticColorFamily>,
        hasExplicitCategory: Bool,
        allowDressReplacement: Bool
    ) -> Int {
        let profile = ClothingSemanticAnalyzer.profile(for: clothing)
        let lowerQuery = context.query.lowercased()
        var score = calculateOutfitScore(clothing: clothing, context: context)

        if profile.category == removedCategory {
            score += 24
        }
        if let desiredIndex = desiredCategories.firstIndex(of: profile.category) {
            score += max(10, 34 - desiredIndex * 7)
        } else if hasExplicitCategory {
            score -= 22
        }

        if !desiredColors.isEmpty {
            if !profile.colorFamilies.isDisjoint(with: desiredColors) {
                score += 16
            } else {
                score -= 8
            }
        } else if !existingColors.isEmpty, !profile.colorFamilies.isDisjoint(with: existingColors) {
            score += 10
        }

        if profile.category == .dress, !allowDressReplacement {
            score -= 24
        }
        if profile.category != removedCategory, !hasExplicitCategory {
            score -= 6
        }

        if !existingCategories.contains(profile.category) {
            score += 8
        }

        if matchesAny(lowerQuery, keywords: ["浅色", "淡色", "轻盈", "清爽"]),
           !profile.colorFamilies.isDisjoint(with: Set([.neutral, .pink, .blue, .yellow])) {
            score += 8
        }
        if matchesAny(lowerQuery, keywords: ["深色", "暗色", "沉稳"]),
           !profile.colorFamilies.isDisjoint(with: Set([.neutral, .brown, .blue, .purple, .red])) {
            score += 8
        }
        if matchesAny(lowerQuery, keywords: ["防雨", "下雨", "雨天"]), profile.rainSafetyLevel >= 2 {
            score += 14
        }

        return score
    }

    private func buildAugmentResponse(
        picked: Clothing,
        updatedClothings: [Clothing],
        style: String,
        occasion: String,
        query: String
    ) -> String {
        let profile = ClothingSemanticAnalyzer.profile(for: picked)
        let totalCount = updatedClothings.count
        let categoryText = profile.category.displayName
        let tone: String

        if matchesAny(query.lowercased(), keywords: ["浅色", "淡色", "清淡"]) {
            tone = "这样整体会更轻一点"
        } else if matchesAny(query.lowercased(), keywords: ["开衫", "外套", "罩衫"]) {
            tone = "层次感会更完整"
        } else if profile.category == .accessory {
            tone = "细节会更精致"
        } else {
            tone = "这套会更顺手一些"
        }

        return localizedCatchphraseText("（点点搭配魔法）已经帮你在这套\(style)\(occasion)搭配里补上「\(picked.name)」这件\(categoryText)啦，\(tone)~ 现在一共\(totalCount)件。")
    }

    private func buildReplaceResponse(
        removed: Clothing,
        picked: Clothing,
        updatedClothings: [Clothing],
        style: String,
        occasion: String,
        query: String
    ) -> String {
        let removedProfile = ClothingSemanticAnalyzer.profile(for: removed)
        let pickedProfile = ClothingSemanticAnalyzer.profile(for: picked)
        let lowerQuery = query.lowercased()
        let actionText: String

        if removedProfile.category == pickedProfile.category {
            actionText = "把「\(removed.name)」换成了「\(picked.name)」"
        } else {
            actionText = "把「\(removed.name)」替换成了「\(picked.name)」这件\(pickedProfile.category.displayName)"
        }

        let tone: String
        if matchesAny(lowerQuery, keywords: ["浅色", "淡色", "清爽"]) {
            tone = "这样整体会更清爽轻盈"
        } else if matchesAny(lowerQuery, keywords: ["防雨", "下雨", "雨天"]) {
            tone = "这样在雨天会更稳妥"
        } else if pickedProfile.category == .dress {
            tone = "主裙氛围会更集中"
        } else {
            tone = "搭配节奏会更顺"
        }

        return localizedCatchphraseText("（点点搭配魔法）已经\(actionText)啦，\(tone)~ 这套\(style)\(occasion)搭配现在还是\(updatedClothings.count)件。")
    }

    private func dedupeCategories(_ categories: [OutfitSemanticCategory]) -> [OutfitSemanticCategory] {
        var seen = Set<OutfitSemanticCategory>()
        return categories.filter { seen.insert($0).inserted }
    }

    // MARK: - 私有方法

    /// 从AI获取搭配建议
    private func fetchOutfitSuggestionFromAI(
        query: String,
        clothings: [Clothing],
        weather: WeatherData?
    ) async throws -> OutfitSuggestionResponse {
        let summary = WardrobeContextManager.shared.generateWardrobeSummary(
            clothings: clothings,
            includeItemList: false
        )
        let candidatesJSON = WardrobeContextManager.shared.generateRelevantItemsJSON(
            query: query,
            clothings: clothings,
            maxItems: 18
        )
        
        // 构建Prompt
        let prompt = buildOutfitPrompt(
            query: query,
            wardrobeSummary: summary,
            candidatesJSON: candidatesJSON,
            weather: weather
        )

        // 调用AI服务
        let aiMessage = await PetAIService.shared.sendMessage(
            prompt,
            displayText: query,
            enableVoice: false,
            responseMode: .raw
        )

        // 解析响应
        return try parseAIResponse(aiMessage.text, clothings: clothings)
    }

    /// 构建搭配专用Prompt
    private func buildOutfitPrompt(
        query: String,
        wardrobeSummary: String,
        candidatesJSON: String,
        weather: WeatherData?
    ) -> String {
        let roleSuffix = currentCharacter == .maomao ? "汪~" : "喵~"
        let season = OutfitRecommendationKnowledgeBase
            .inferredSeason(from: weather, query: query)
            .displayName
        let weatherLine: String
        if let weather {
            weatherLine = "当前天气：\(weather.city)，\(weather.condition.rawValue)，\(Int(weather.temperature.rounded()))°C，体感\(Int(weather.feelsLikeTemperature.rounded()))°C，风速\(String(format: "%.1f", weather.windSpeed))m/s"
        } else {
            weatherLine = "当前天气：未获取到实时天气，先按季节推断"
        }
        return """
        需求：\(query)

        当前季节：\(season)
        \(weatherLine)

        衣橱摘要：
        \(wardrobeSummary)

        候选单品：
        \(candidatesJSON)

        请从候选中选2-4件搭配：
        - 按品类（裙装/外套/鞋子/配饰）筛选
        - 结合候选里的长度/材质/季节/场合特征，优先选更符合当前季节和Lo裙语境的
        - 温度偏高（≥24°C）时避免厚重大衣、毛呢、棉服、羽绒类外搭
        - 优先同色系/近色系，主色1-2种，不超3种
        - 优先JSK/OP，鞋子同色或黑白灰米棕
        - 用候选单品的标签/类型词汇，不要编造不存在的单品

        返回JSON：
        {
          "description": "搭配描述，30字内，带\(roleSuffix)",
          "selectedItemNames": ["单品名1", "单品名2"],
          "style": "甜美/优雅/哥特/CLA/日常",
          "occasion": "日常/约会/茶会/通勤",
          "reasoning": "理由，50字内"
        }

        只返回JSON，不要额外解释。
        """
    }

    /// 解析AI响应
    private func parseAIResponse(_ response: String, clothings: [Clothing]) throws -> OutfitSuggestionResponse {
        // 提取JSON部分
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            throw OutfitSuggestionError.invalidJSONFormat
        }

        let jsonString = String(response[jsonStart...jsonEnd])

        // 解析JSON
        guard let data = jsonString.data(using: .utf8) else {
            throw OutfitSuggestionError.invalidJSONFormat
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let description = json["description"] as? String ?? localizedCatchphraseText("为你搭配了一套~喵")
                let selectedNames = (json["selectedItemNames"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let idStrings = json["selectedItemIDs"] as? [String] ?? []
                let style = json["style"] as? String ?? "日常"
                let occasion = json["occasion"] as? String ?? "日常"
                let reasoning = json["reasoning"] as? String ?? ""

                // 转换ID字符串为UUID
                let selectedIDs = idStrings.compactMap { UUID(uuidString: $0) }

                // 验证ID是否存在于衣橱中
                let validIDs = selectedIDs.filter { id in
                    clothings.contains { $0.id == id }
                }

                return OutfitSuggestionResponse(
                    description: description,
                    selectedItemNames: selectedNames,
                    selectedItemIDs: validIDs,
                    style: style,
                    occasion: occasion,
                    reasoning: reasoning
                )
            } else {
                throw OutfitSuggestionError.invalidJSONFormat
            }
        } catch {
            throw OutfitSuggestionError.parseError(error.localizedDescription)
        }
    }

    /// 获取建议对应的CutoutItem
    private func fetchCutoutsForSuggestion(
        suggestion: OutfitSuggestionResponse,
        context: ModelContext
    ) async throws -> [CutoutItem] {
        // 在主线程执行数据库查询
        return try await MainActor.run {
            var result: [CutoutItem] = []

            for clothingID in suggestion.selectedItemIDs {
                // 查找关联的CutoutItem
                let descriptor = FetchDescriptor<CutoutItem>(
                    predicate: #Predicate { $0.linkedClothingID == clothingID }
                )

                if let cutout = try context.fetch(descriptor).first {
                    result.append(cutout)
                }
            }

            return result
        }
    }

    /// 构建响应文本
    private func buildResponseText(suggestion: OutfitSuggestionResponse, clothings: [Clothing]) -> String {
        var text = suggestion.description

        if !suggestion.reasoning.isEmpty {
            text += "\n\n" + suggestion.reasoning
        }

        // 添加物品清单
        if !clothings.isEmpty {
            let names = clothings.map { $0.name }.joined(separator: "、")
            text += "\n\n包含：\(names)"
        }

        return text
    }
    
    private func matchSelectedClothings(
        suggestion: OutfitSuggestionResponse,
        clothings: [Clothing]
    ) -> [Clothing] {
        var selected: [Clothing] = []
        var seen = Set<UUID>()
        
        // 优先按名字匹配
        for rawName in suggestion.selectedItemNames {
            let name = rawName.lowercased()
            let exact = clothings.first { $0.name.lowercased() == name }
            let fuzzy = clothings.first { $0.name.lowercased().contains(name) || name.contains($0.name.lowercased()) }
            if let matched = exact ?? fuzzy, seen.insert(matched.id).inserted {
                selected.append(matched)
            }
        }
        
        // 兼容旧格式：按 ID 匹配
        if selected.count < 2 {
            for id in suggestion.selectedItemIDs {
                if let matched = clothings.first(where: { $0.id == id }),
                   seen.insert(matched.id).inserted {
                    selected.append(matched)
                }
            }
        }
        
        // 最小兜底：保障至少有两件可展示
        if selected.count < 2 {
            let fallbackContext = OutfitRecommendationContext(
                query: suggestion.description,
                style: suggestion.style,
                occasion: suggestion.occasion,
                season: OutfitRecommendationKnowledgeBase.inferredSeason(from: nil)
            )
            let rankedFallback = clothings
                .filter { !seen.contains($0.id) }
                .sorted {
                    let lhs = OutfitRecommendationScorer.score($0, in: fallbackContext)
                    let rhs = OutfitRecommendationScorer.score($1, in: fallbackContext)
                    if lhs == rhs {
                        return $0.createdAt > $1.createdAt
                    }
                    return lhs > rhs
                }
            for clothing in rankedFallback {
                guard selected.count < 2 else { break }
                if seen.insert(clothing.id).inserted {
                    selected.append(clothing)
                }
            }
        }
        
        return selected
    }
}

private enum OutfitPieceCategory: Int {
    case dress
    case outerwear
    case shoes
    case accessory
    case other

    var isMajorPiece: Bool {
        switch self {
        case .dress, .outerwear, .other:
            return true
        case .shoes, .accessory:
            return false
        }
    }

    var allowsAdjacentHue: Bool {
        switch self {
        case .outerwear, .accessory, .other:
            return true
        case .dress, .shoes:
            return false
        }
    }
}

private enum OutfitColorFamily: String, Hashable {
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

    var isNeutralLike: Bool {
        self == .neutral || self == .metallic
    }

    func isAdjacent(to other: OutfitColorFamily) -> Bool {
        if self == other {
            return true
        }

        switch (self, other) {
        case (.pink, .red), (.red, .pink),
             (.pink, .purple), (.purple, .pink),
             (.red, .orange), (.orange, .red),
             (.orange, .yellow), (.yellow, .orange),
             (.yellow, .green), (.green, .yellow),
             (.green, .blue), (.blue, .green),
             (.brown, .orange), (.orange, .brown),
             (.brown, .red), (.red, .brown):
            return true
        default:
            return false
        }
    }
}

enum OutfitColorHarmonyEngine {
    static func refineSelection(_ selected: [Clothing], within pool: [Clothing]) -> [Clothing] {
        let uniquePool = uniqueClothings(pool)
        let preferred = uniqueClothings(selected)

        guard let anchor = chooseAnchor(from: preferred, pool: uniquePool) else {
            return Array(preferred.prefix(4))
        }

        var result: [Clothing] = [anchor]
        var used = Set([anchor.id])
        let preferredIDs = Set(preferred.map(\.id))

        var desiredCategories = preferred
            .filter { $0.id != anchor.id }
            .map { pieceCategory(for: $0) }
            .reduce(into: [OutfitPieceCategory]()) { partialResult, category in
                if !partialResult.contains(category) {
                    partialResult.append(category)
                }
            }

        for category in [OutfitPieceCategory.outerwear, .shoes, .accessory, .other] where !desiredCategories.contains(category) {
            desiredCategories.append(category)
        }

        for category in desiredCategories {
            guard result.count < 4 else { break }
            if let candidate = bestCandidate(
                for: category,
                anchor: anchor,
                current: result,
                preferredIDs: preferredIDs,
                pool: uniquePool,
                used: used,
                minimumScore: 20
            ) {
                result.append(candidate)
                used.insert(candidate.id)
            }
        }

        while result.count < 2 {
            guard let candidate = bestFallbackCandidate(
                anchor: anchor,
                current: result,
                preferredIDs: preferredIDs,
                pool: uniquePool,
                used: used
            ) else {
                break
            }
            result.append(candidate)
            used.insert(candidate.id)
        }

        return Array(result.prefix(4))
    }

    static func dominantNonNeutralFamilyNames(in items: [Clothing]) -> Set<String> {
        Set(
            items
                .flatMap { nonNeutralFamilies(for: $0) }
                .map(\.rawValue)
        )
    }

    private static func chooseAnchor(from selected: [Clothing], pool: [Clothing]) -> Clothing? {
        let combined = uniqueClothings(selected + pool)
        return combined.max { lhs, rhs in
            anchorScore(lhs, preferredIDs: Set(selected.map(\.id))) < anchorScore(rhs, preferredIDs: Set(selected.map(\.id)))
        }
    }

    private static func anchorScore(_ clothing: Clothing, preferredIDs: Set<UUID>) -> Int {
        var score = 0
        let category = pieceCategory(for: clothing)

        if preferredIDs.contains(clothing.id) {
            score += 80
        }
        if category == .dress {
            score += 120
        } else if category == .other {
            score += 40
        }
        if !nonNeutralFamilies(for: clothing).isEmpty {
            score += 25
        }
        if !clothing.colors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 12
        }

        return score
    }

    private static func bestCandidate(
        for category: OutfitPieceCategory,
        anchor: Clothing,
        current: [Clothing],
        preferredIDs: Set<UUID>,
        pool: [Clothing],
        used: Set<UUID>,
        minimumScore: Int
    ) -> Clothing? {
        let candidates = pool.filter { !used.contains($0.id) && pieceCategory(for: $0) == category }
        guard !candidates.isEmpty else { return nil }

        let ranked = candidates
            .map { ($0, compatibilityScore($0, anchor: anchor, current: current, preferredIDs: preferredIDs)) }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.createdAt > $1.0.createdAt
                }
                return $0.1 > $1.1
            }

        guard let best = ranked.first, best.1 >= minimumScore else {
            return nil
        }

        return best.0
    }

    private static func bestFallbackCandidate(
        anchor: Clothing,
        current: [Clothing],
        preferredIDs: Set<UUID>,
        pool: [Clothing],
        used: Set<UUID>
    ) -> Clothing? {
        pool
            .filter { !used.contains($0.id) }
            .map { ($0, compatibilityScore($0, anchor: anchor, current: current, preferredIDs: preferredIDs)) }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.createdAt > $1.0.createdAt
                }
                return $0.1 > $1.1
            }
            .first?
            .0
    }

    private static func compatibilityScore(
        _ candidate: Clothing,
        anchor: Clothing,
        current: [Clothing],
        preferredIDs: Set<UUID>
    ) -> Int {
        let category = pieceCategory(for: candidate)
        let anchorFamilies = nonNeutralFamilies(for: anchor)
        let candidateFamilies = nonNeutralFamilies(for: candidate)
        let currentMajorFamilies = dominantNonNeutralFamilies(
            in: current.filter { pieceCategory(for: $0).isMajorPiece }
        )
        let currentAllFamilies = dominantNonNeutralFamilies(in: current)

        var score = 0

        if preferredIDs.contains(candidate.id) {
            score += 50
        }

        if category == .shoes {
            score += 20
        } else if category == .outerwear {
            score += 15
        } else if category == .accessory {
            score += 8
        }

        if candidateFamilies.isEmpty {
            score += category == .shoes ? 32 : 22
        } else if anchorFamilies.isEmpty {
            score += 8
        } else if !candidateFamilies.isDisjoint(with: anchorFamilies) {
            score += 38
        } else if category.allowsAdjacentHue && candidateFamilies.contains(where: { family in
            anchorFamilies.contains(where: { $0.isAdjacent(to: family) })
        }) {
            score += 18
        } else if category == .shoes {
            score -= 75
        } else {
            score -= 60
        }

        if candidateFamilies.contains(.multicolor) {
            score -= category.isMajorPiece ? 26 : 12
        }

        if category.isMajorPiece {
            let resultingMajorFamilies = currentMajorFamilies.union(candidateFamilies)
            if resultingMajorFamilies.count > 2 {
                score -= (resultingMajorFamilies.count - 2) * 40
            }
        }

        let resultingAllFamilies = currentAllFamilies.union(candidateFamilies)
        if resultingAllFamilies.count > 2 {
            score -= (resultingAllFamilies.count - 2) * 25
        }

        if !candidateFamilies.isEmpty &&
            currentAllFamilies.count >= 2 &&
            resultingAllFamilies.count > currentAllFamilies.count {
            score -= 35
        }

        if category == .accessory && current.contains(where: { pieceCategory(for: $0) == .accessory }) {
            score -= 18
        }

        return score
    }

    private static func uniqueClothings(_ clothings: [Clothing]) -> [Clothing] {
        var seen = Set<UUID>()
        return clothings.filter { seen.insert($0.id).inserted }
    }

    private static func dominantNonNeutralFamilies(in items: [Clothing]) -> Set<OutfitColorFamily> {
        Set(items.flatMap { nonNeutralFamilies(for: $0) })
    }

    private static func nonNeutralFamilies(for clothing: Clothing) -> Set<OutfitColorFamily> {
        Set(colorFamilies(for: clothing).filter { !$0.isNeutralLike })
    }

    private static func colorFamilies(for clothing: Clothing) -> Set<OutfitColorFamily> {
        let semanticFamilies = ClothingSemanticAnalyzer.profile(for: clothing).colorFamilies
        return Set(semanticFamilies.compactMap { family in
            switch family {
            case .pink: return .pink
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .blue: return .blue
            case .purple: return .purple
            case .brown: return .brown
            case .neutral: return .neutral
            case .metallic: return .metallic
            case .multicolor: return .multicolor
            }
        })
    }

    private static func pieceCategory(for clothing: Clothing) -> OutfitPieceCategory {
        switch ClothingSemanticAnalyzer.profile(for: clothing).category {
        case .dress:
            return .dress
        case .outerwear:
            return .outerwear
        case .shoes:
            return .shoes
        case .accessory, .umbrella:
            return .accessory
        case .other:
            return .other
        }
    }

    private static func searchableText(for clothing: Clothing) -> String {
        ClothingSemanticAnalyzer.searchableText(for: clothing)
    }

    private static func matchesAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }
}

// MARK: - 错误类型

enum OutfitSuggestionError: Error, LocalizedError {
    case noItemsAvailable
    case insufficientItems
    case insufficientNonDepositItems
    case invalidJSONFormat
    case parseError(String)
    case aiServiceError(String)

    var errorDescription: String? {
        switch self {
        case .noItemsAvailable:
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（歪头）主人衣橱里好像没有合适的裙子呢，要不要先添置几件新的呀？喵~")
        case .insufficientItems:
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（蹭蹭）主人衣橱里的裙子还不够呢，至少要有 2 件才能帮我搭配喵~")
        case .insufficientNonDepositItems:
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（蹭蹭）主人衣橱里现在已经到手、能直接穿的单品还不够呢~ 至少要有 2 件才能智能搭配喵！心愿尾款和还没发货的先不算哦~")
        case .invalidJSONFormat:
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（挠头）我刚刚有点晕，没听懂主人的意思，可以再说一次喵？")
        case .parseError:
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（歪头）我好像理解错了，让我再想想喵...")
        case .aiServiceError:
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（蹭蹭）刚刚网络好像卡了一下下，主人再试一次好不好喵？")
        }
    }
}

// MARK: - 便捷扩展

extension OutfitSuggestionService {
    /// 检查是否可以进行搭配建议
    /// - Parameter context: ModelContext
    /// - Returns: 是否可以搭配
    func canSuggestOutfit(context: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<CutoutItem>()
            let count = try context.fetch(descriptor).count
            return count >= 2
        } catch {
            return false
        }
    }

    /// 获取可用于搭配的CutoutItem数量
    func availableCutoutCount(context: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<CutoutItem>()
            return try context.fetch(descriptor).count
        } catch {
            return 0
        }
    }
}
