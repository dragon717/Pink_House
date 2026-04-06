import Foundation
import SwiftData

struct WardrobeSearchResolution {
    let normalizedQuery: String
    let results: [Clothing]
    let matchedTerms: [String]
    let suggestedPrompt: String
}

class WardrobeContextManager {
    static let shared = WardrobeContextManager()
    
    private init() {}
    
    private let dressHints = ["jsk", "op", "sk", "裙", "连衣", "半裙", "吊带"]
    private let outerwearHints = ["外套", "开衫", "罩衫", "斗篷", "披肩", "针织", "坎肩", "披风", "小外套", "短外套", "薄外套", "薄开衫"]
    private let topHints = ["上衣", "衬衫", "内搭", "打底", "马甲", "背心", "短袖", "长袖", "t恤", "blouse", "tee"]
    private let shoeHints = ["鞋", "皮鞋", "玛丽珍", "乐福", "高跟", "靴", "凉鞋", "单鞋"]
    private let umbrellaHints = ["伞", "雨伞", "晴雨伞", "折叠伞", "防晒伞"]
    private let accessoryHints = ["小物", "配饰", "胸针", "项链", "发带", "发箍", "耳饰", "帽", "包", "袜", "手袖", "腰带"]
    private let weatherHints = ["天气", "温度", "下雨", "雨天", "降水", "风大", "出门", "体感"]
    private let depositHints = ["尾款", "定金", "补款", "预定"]
    private let outfitIntentHints = ["穿搭", "搭配", "怎么穿", "ootd", "造型", "推荐一套", "搭一套", "搭配一套"]

    private enum ContextFocus {
        case wardrobeCore
        case weatherOutfit
        case deposit
        case general
    }

    private enum VocabularyCategory: String, CaseIterable {
        case dress
        case outerwear
        case top
        case shoe
        case umbrella
        case accessory
    }
    
    func generateWardrobeSummary(
        clothings: [Clothing],
        includeItemList: Bool = false,
        maxItems: Int = 12
    ) -> String {
        guard !clothings.isEmpty else {
            return "用户的衣橱目前是空的。"
        }

        // 1. 基础统计
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }

        // 2. 最贵单品 (包含小物)
        let mostExpensiveItem = clothings.max(by: { $0.inventoryTotalPrice < $1.inventoryTotalPrice })
        let mostExpensivePrice = mostExpensiveItem.map(\.inventoryTotalPrice) ?? 0

        // 3. 心愿尾款统计
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }

        // 构建 Context String
        var summary = """
        【衣橱数据概览】
        - 总件数：\(totalCount) 件
        - 衣橱总价值：¥\(NSDecimalNumber(decimal: totalValue).stringValue)
        """

        if let maxItem = mostExpensiveItem {
            summary += "\n- 最贵单品：\(maxItem.name) (¥\(NSDecimalNumber(decimal: mostExpensivePrice).stringValue))"
        }

        if !depositPlans.isEmpty {
            summary += """
            \n- 心愿尾款（预定中）：\(depositPlans.count) 款
            - 已付定金总额：¥\(NSDecimalNumber(decimal: totalDeposit).stringValue)
            - 待付尾款总额：¥\(NSDecimalNumber(decimal: totalBalance).stringValue)
            """
        }

        guard includeItemList else {
            return summary
        }

        summary += "\n\n【可用单品列表】\n"
        for item in clothings.prefix(maxItems) {
            let brandName = item.brand?.name ?? "未知品牌"
            summary += "- 名称: \(item.name) | 品牌: \(brandName) | 价格: ¥\(NSDecimalNumber(decimal: item.price).stringValue)\n"
        }
        return summary
    }
    
    func shouldAttachWardrobeContext(for query: String) -> Bool {
        let lower = query.lowercased()
        let triggers = [
            "衣橱", "裙", "穿搭", "搭配", "风格", "怎么穿",
            "颜色", "小物", "配饰", "尾款", "定金", "补款",
            "鞋", "伞", "找", "搜索", "有没有"
        ]
        return triggers.contains { lower.contains($0) }
    }
    
    func buildPromptWithRelevantWardrobeContext(
        query: String,
        clothings: [Clothing],
        maxItems: Int = 12
    ) -> String {
        guard shouldAttachWardrobeContext(for: query) else {
            return query
        }
        
        let summary = generateWardrobeSummary(clothings: clothings, includeItemList: false)
        let relevantJSON = generateRelevantItemsJSON(query: query, clothings: clothings, maxItems: maxItems)
        let vocabularyBlock = buildVocabularyLearningBlock(query: query, clothings: clothings)
        
        return """
        用户问题：\(query)
        
        \(composeContextBlock(summary: summary, relevantJSON: relevantJSON, vocabularyBlock: vocabularyBlock))
        
        请用自然口语回答，不要复述 JSON 键名，不要输出代码块。
        """
    }

    func buildWardrobeContextBlockIfNeeded(
        query: String,
        clothings: [Clothing],
        maxItems: Int = 12
    ) -> String? {
        buildWardrobeContextBlockIfNeeded(
            query: query,
            clothings: clothings,
            module: nil,
            maxItems: maxItems
        )
    }

    func buildWardrobeContextBlockIfNeeded(
        query: String,
        clothings: [Clothing],
        module: PetConversationModule?,
        maxItems: Int = 12
    ) -> String? {
        if let module {
            guard shouldAttachWardrobeContext(for: module, query: query) else {
                return nil
            }
        } else {
            guard shouldAttachWardrobeContext(for: query) else {
                return nil
            }
        }

        let summary = generateWardrobeSummary(clothings: clothings, includeItemList: false)
        let safeMax = max(1, min(maxItems, 12))
        let budgets = [safeMax, 8, 6, 4]
        let uniqueBudgets = Array(Set(budgets)).sorted(by: >)
        let blockCharLimit = 2400
        var fallbackBlock = ""
        
        for budget in uniqueBudgets {
            let relevantJSON = generateRelevantItemsJSON(query: query, clothings: clothings, maxItems: budget)
            let vocabularyBlock = buildVocabularyLearningBlock(query: query, clothings: clothings)
            let block = composeContextBlock(
                summary: summary,
                relevantJSON: relevantJSON,
                vocabularyBlock: vocabularyBlock
            )
            fallbackBlock = block
            if block.count <= blockCharLimit {
                return block
            }
        }
        
        if fallbackBlock.count <= blockCharLimit {
            return fallbackBlock
        }
        
        return String(fallbackBlock.prefix(blockCharLimit))
    }

    func shouldAttachWardrobeContext(for module: PetConversationModule, query: String) -> Bool {
        switch module {
        case .wardrobe, .outfit, .weather:
            return true
        case .mood:
            return false
        case .general:
            // 通用聊天默认不附带大块衣橱数据，降低 token 占用。
            return shouldAttachWardrobeContext(for: query)
        }
    }
    
    func generateRelevantItemsJSON(query: String, clothings: [Clothing], maxItems: Int = 12) -> String {
        guard !clothings.isEmpty else {
            return "{\"items\":[]}"
        }
        
        let ranked = rankClothings(for: query, clothings: clothings)
        let selected = Array(ranked.prefix(maxItems))
        let payload: [String: Any] = [
            "items": selected.map { clothing in
                buildItemPayload(for: clothing)
            }
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"items\":[]}"
        }
        return text
    }
    
    private func rankClothings(for query: String, clothings: [Clothing]) -> [Clothing] {
        let lowerQuery = query.lowercased()
        let tokens = rankingTerms(for: lowerQuery, clothings: clothings)
        let focus = detectFocus(from: lowerQuery)
        let requestedCategories = requestedCategories(for: lowerQuery)
        let requestedSeasons = OutfitRecommendationKnowledgeBase.requestedSeasons(in: lowerQuery)
        
        let scored = clothings.map { clothing -> (Clothing, Int) in
            let searchable = buildSearchableText(for: clothing)
            let profile = ClothingSemanticAnalyzer.profile(for: clothing)
            var score = 0
            
            for token in tokens where !token.isEmpty {
                if searchable.contains(token) {
                    score += 2
                }
                if clothing.name.lowercased().contains(token) {
                    score += 3
                }
            }
            
            if containsAny(in: searchable, hints: dressHints) {
                score += 1
            }
            if containsAny(in: searchable, hints: accessoryHints) {
                score += 1
            }
            if requestedCategories.contains(.dress), containsAny(in: searchable, hints: dressHints) {
                score += 6
            }
            if requestedCategories.contains(.outerwear) || requestedCategories.contains(.top) {
                if containsAny(in: searchable, hints: outerwearHints) || containsAny(in: searchable, hints: topHints) {
                    score += 7
                }
            }
            if requestedCategories.contains(.shoe), containsAny(in: searchable, hints: shoeHints) {
                score += 5
            }
            if requestedCategories.contains(.umbrella), containsAny(in: searchable, hints: umbrellaHints) {
                score += 5
            }
            if requestedCategories.contains(.accessory) {
                if containsAny(in: searchable, hints: accessoryHints) || !(clothing.accessoryItems ?? []).isEmpty {
                    score += 5
                }
            }
            if !requestedSeasons.isEmpty {
                if !profile.seasons.isEmpty {
                    if !requestedSeasons.isDisjoint(with: profile.seasons) {
                        score += 8
                    } else {
                        score -= 6
                    }
                } else if requestedSeasons.contains(.summer), profile.warmthLevel <= 2 {
                    score += 6
                } else if requestedSeasons.contains(.winter), profile.warmthLevel >= 3 {
                    score += 6
                }
            }
            if clothing.isDepositPlan, (query.contains("尾款") || query.contains("定金")) {
                score += 3
            }
            
            return (clothing, score)
        }
        
        let sortedByScore = scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.createdAt > rhs.0.createdAt
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)

        let focused = applyFocusFilter(focus, query: lowerQuery, sortedClothings: sortedByScore)
        if !focused.isEmpty {
            return focused
        }
        
        if let firstScore = scored.map(\.1).max(), firstScore > 0 {
            return sortedByScore
        }
        
        // 没有明确命中时：优先返回裙装 + 最近录入项
        let dressFirst = clothings.sorted { lhs, rhs in
            let l = containsAny(in: buildSearchableText(for: lhs), hints: dressHints)
            let r = containsAny(in: buildSearchableText(for: rhs), hints: dressHints)
            if l == r {
                return lhs.createdAt > rhs.createdAt
            }
            return l && !r
        }
        return dressFirst
    }

    func resolveSearch(query: String, clothings: [Clothing], maxResults: Int = 24) -> WardrobeSearchResolution {
        let normalizedQuery = normalizeSearchQuery(query)
        let learnedTerms = learnedVocabularyTerms(from: clothings)
        let topLearnedTerms = Array(
            learnedTerms.values
                .flatMap { $0 }
                .uniqued()
                .prefix(6)
        )

        guard !normalizedQuery.isEmpty else {
            return WardrobeSearchResolution(
                normalizedQuery: normalizedQuery,
                results: [],
                matchedTerms: topLearnedTerms,
                suggestedPrompt: defaultSearchPrompt(clothings: clothings)
            )
        }

        let expandedTerms = expandedSearchTerms(for: normalizedQuery, clothings: clothings)
        let scored = clothings.compactMap { clothing -> (Clothing, Int)? in
            let score = scoreSearchMatch(for: clothing, query: normalizedQuery, expandedTerms: expandedTerms)
            guard score > 0 else { return nil }
            return (clothing, score)
        }

        let sortedResults = scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.createdAt > rhs.0.createdAt
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)

        let matchedTerms = expandedTerms.filter { term in
            sortedResults.contains { clothing in
                buildSearchableText(for: clothing).contains(term)
            }
        }

        let results = Array(sortedResults.prefix(maxResults))
        let suggestedPrompt = buildSuggestedPrompt(
            query: normalizedQuery,
            matchedTerms: matchedTerms.isEmpty ? topLearnedTerms : matchedTerms
        )

        return WardrobeSearchResolution(
            normalizedQuery: normalizedQuery,
            results: results,
            matchedTerms: Array((matchedTerms.isEmpty ? topLearnedTerms : matchedTerms).prefix(6)),
            suggestedPrompt: suggestedPrompt
        )
    }

    func defaultSearchPrompt(clothings: [Clothing]) -> String {
        let learnedTerms = Array(
            learnedVocabularyTerms(from: clothings)
                .values
                .flatMap { $0 }
                .uniqued()
                .prefix(5)
        )

        if learnedTerms.isEmpty {
            return "帮我按我衣橱里的标签、类型和备注找衣服，名字不完全一样也一起匹配"
        }

        return "帮我按我衣橱里的标签和类型找衣服，比如\(learnedTerms.joined(separator: "、"))，名字不完全一样也一起匹配"
    }
    
    private func queryTokens(_ query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "，。！？、,!?：:；; \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 1 }
    }
    
    private func buildSearchableText(for clothing: Clothing) -> String {
        ClothingSemanticAnalyzer.searchableText(for: clothing)
    }
    
    private func containsAny(in text: String, hints: [String]) -> Bool {
        for hint in hints where text.contains(hint) {
            return true
        }
        return false
    }

    private func detectFocus(from query: String) -> ContextFocus {
        let lower = query.lowercased()
        if containsAny(in: lower, hints: depositHints) {
            return .deposit
        }
        if containsAny(in: lower, hints: weatherHints) {
            return .weatherOutfit
        }
        if containsAny(in: lower, hints: outfitIntentHints + dressHints + outerwearHints + topHints + accessoryHints + shoeHints + umbrellaHints) {
            return .wardrobeCore
        }
        return .general
    }

    private func applyFocusFilter(_ focus: ContextFocus, query: String, sortedClothings: [Clothing]) -> [Clothing] {
        switch focus {
        case .deposit:
            let depositItems = sortedClothings.filter { $0.isDepositPlan }
            if !depositItems.isEmpty {
                return depositItems + sortedClothings.filter { !$0.isDepositPlan }
            }
            return sortedClothings
        case .weatherOutfit:
            return assembleWeatherOutfitItems(from: sortedClothings)
        case .wardrobeCore:
            let core = sortedClothings.filter { clothing in
                let searchable = buildSearchableText(for: clothing)
                return containsAny(in: searchable, hints: dressHints) ||
                    containsAny(in: searchable, hints: outerwearHints) ||
                    containsAny(in: searchable, hints: topHints) ||
                    containsAny(in: searchable, hints: accessoryHints) ||
                    containsAny(in: searchable, hints: shoeHints) ||
                    containsAny(in: searchable, hints: umbrellaHints) ||
                    !(clothing.accessoryItems ?? []).isEmpty
            }
            let prioritizedSource = core.isEmpty ? sortedClothings : core
            return assembleWardrobeCoreItems(from: prioritizedSource, query: query)
        case .general:
            return []
        }
    }

    private func assembleWeatherOutfitItems(from sortedClothings: [Clothing]) -> [Clothing] {
        // 只从已到手、当前可穿的单品里做天气搭配。
        let availableClothings = OutfitRecommendability.recommendableClothings(from: sortedClothings)

        var pickedIDs = Set<UUID>()
        var result: [Clothing] = []

        func append(_ candidates: [Clothing], limit: Int) {
            var appended = 0
            for item in candidates where result.count < 12 {
                guard pickedIDs.insert(item.id).inserted else { continue }
                result.append(item)
                appended += 1
                if appended >= limit { break }
            }
        }

        let dresses = availableClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: dressHints) }
        let tops = availableClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: topHints) }
        let outerwears = availableClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: outerwearHints) }
        let shoes = availableClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: shoeHints) }
        let umbrellas = availableClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: umbrellaHints) }
        let accessories = availableClothings.filter {
            let searchable = buildSearchableText(for: $0)
            return containsAny(in: searchable, hints: accessoryHints) || !(($0.accessoryItems ?? []).isEmpty)
        }

        append(Array(dresses.prefix(4)), limit: 4)
        append(Array(tops.prefix(3)), limit: 3)
        append(Array(outerwears.prefix(2)), limit: 2)
        append(Array(shoes.prefix(2)), limit: 2)
        append(Array(umbrellas.prefix(2)), limit: 2)
        append(Array(accessories.prefix(2)), limit: 2)

        if result.isEmpty {
            return availableClothings
        }

        for item in availableClothings where result.count < 12 {
            guard pickedIDs.insert(item.id).inserted else { continue }
            result.append(item)
        }

        return result
    }

    private func assembleWardrobeCoreItems(from sortedClothings: [Clothing], query: String) -> [Clothing] {
        let requested = requestedCategories(for: query)
        let isOutfitLike = query.containsAnyKeyword(outfitIntentHints)
        var pickedIDs = Set<UUID>()
        var result: [Clothing] = []

        func append(limit: Int, where predicate: (Clothing) -> Bool) {
            var appended = 0
            for item in sortedClothings where predicate(item) {
                guard pickedIDs.insert(item.id).inserted else { continue }
                result.append(item)
                appended += 1
                if appended >= limit {
                    break
                }
            }
        }

        let matchesDress: (Clothing) -> Bool = { self.containsAny(in: self.buildSearchableText(for: $0), hints: self.dressHints) }
        let matchesTop: (Clothing) -> Bool = {
            let searchable = self.buildSearchableText(for: $0)
            return self.containsAny(in: searchable, hints: self.topHints)
        }
        let matchesOuterwear: (Clothing) -> Bool = {
            let searchable = self.buildSearchableText(for: $0)
            return self.containsAny(in: searchable, hints: self.outerwearHints)
        }
        let matchesShoe: (Clothing) -> Bool = { self.containsAny(in: self.buildSearchableText(for: $0), hints: self.shoeHints) }
        let matchesUmbrella: (Clothing) -> Bool = { self.containsAny(in: self.buildSearchableText(for: $0), hints: self.umbrellaHints) }
        let matchesAccessory: (Clothing) -> Bool = {
            let searchable = self.buildSearchableText(for: $0)
            return self.containsAny(in: searchable, hints: self.accessoryHints) || !(($0.accessoryItems ?? []).isEmpty)
        }

        if requested.contains(.top) {
            append(limit: isOutfitLike ? 4 : 6, where: matchesTop)
        }
        if requested.contains(.outerwear) {
            append(limit: isOutfitLike ? 4 : 6, where: matchesOuterwear)
        }
        if requested.contains(.dress) {
            append(limit: isOutfitLike ? 4 : 6, where: matchesDress)
        }
        if requested.contains(.shoe) {
            append(limit: 4, where: matchesShoe)
        }
        if requested.contains(.umbrella) {
            append(limit: 3, where: matchesUmbrella)
        }
        if requested.contains(.accessory) {
            append(limit: isOutfitLike ? 4 : 6, where: matchesAccessory)
        }

        if isOutfitLike {
            if requested.isEmpty {
                append(limit: 4, where: matchesDress)
                append(limit: 3, where: matchesTop)
                append(limit: 2, where: matchesOuterwear)
                append(limit: 2, where: matchesShoe)
                append(limit: 3, where: matchesAccessory)
            } else {
                if !(requested.contains(.dress)) {
                    append(limit: 4, where: matchesDress)
                }
                if !requested.contains(.top) {
                    append(limit: 3, where: matchesTop)
                }
                if !requested.contains(.outerwear) {
                    append(limit: 2, where: matchesOuterwear)
                }
                if !requested.contains(.shoe) {
                    append(limit: 2, where: matchesShoe)
                }
                if !requested.contains(.accessory) {
                    append(limit: 3, where: matchesAccessory)
                }
            }
        }

        if result.isEmpty {
            return sortedClothings
        }

        for item in sortedClothings {
            guard pickedIDs.insert(item.id).inserted else { continue }
            result.append(item)
        }

        return result
    }
    
    private func buildItemPayload(for clothing: Clothing) -> [String: Any] {
        var features: [String] = []
        let brand = clothing.brand?.name ?? "未知品牌"
        let semantic = ClothingSemanticAnalyzer.profile(for: clothing)
        features.append("品牌:\(brand)")
        
        if !clothing.types.isEmpty {
            features.append("类型:\(clothing.types)")
        }
        let tagNames = clothing.tags?.map(\.name).filter { !$0.isEmpty } ?? []
        if !tagNames.isEmpty {
            features.append("标签:\(tagNames.prefix(3).joined(separator: "、"))")
        }
        if !clothing.colors.isEmpty {
            features.append("颜色:\(clothing.colors)")
        }
        if !clothing.length.isEmpty {
            features.append("衣长:\(clothing.length)")
        }
        if !clothing.condition.isEmpty {
            features.append("状态:\(clothing.condition)")
        }
        
        if clothing.isDepositPlan {
            features.append("心愿尾款:是")
        }

        if !clothing.note.isEmpty {
            features.append("备注:\(String(clothing.note.prefix(24)))")
        }
        features.append(contentsOf: semantic.featureBadges)
        features = Array(features.uniqued().prefix(7))
        
        let accessoryCandidates = collectAccessories(for: clothing)
        let accessoryPayload = accessoryCandidates.prefix(6).map { name in
            ["name": name, "feature": "裙子关联小物"]
        }
        
        var payload: [String: Any] = [
            "name": clothing.name,
            "features": features
        ]
        if !accessoryPayload.isEmpty {
            payload["accessories"] = accessoryPayload
        }
        return payload
    }
    
    private func collectAccessories(for clothing: Clothing) -> [String] {
        let freeText = clothing.accessories
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let relationItems = clothing.accessoryItems?
            .map(\.name)
            .filter { !$0.isEmpty } ?? []
        
        var seen = Set<String>()
        var merged: [String] = []
        for name in freeText + relationItems {
            if seen.insert(name).inserted {
                merged.append(name)
            }
        }
        return merged
    }

    private func composeContextBlock(summary: String, relevantJSON: String, vocabularyBlock: String?) -> String {
        var parts: [String] = [
            """
            以下是衣橱摘要（仅供参考）：
            \(summary)
            """,
            """
            以下是遴选后的候选单品（JSON，仅包含名字和特征）：
            \(relevantJSON)
            """
        ]

        if let vocabularyBlock, !vocabularyBlock.isEmpty {
            parts.append(vocabularyBlock)
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildVocabularyLearningBlock(query: String, clothings: [Clothing]) -> String? {
        let learnedTerms = learnedVocabularyTerms(from: clothings)
        var lines: [String] = []

        if query.containsAnyKeyword(outerwearHints + topHints) {
            let outerwearTerms = (learnedTerms[.outerwear] ?? []) + (learnedTerms[.top] ?? [])
            if !outerwearTerms.isEmpty {
                lines.append("外套/上装常用词：\(Array(outerwearTerms.uniqued().prefix(6)).joined(separator: "、"))")
            }
        }

        if query.containsAnyKeyword(dressHints), let dressTerms = learnedTerms[.dress], !dressTerms.isEmpty {
            lines.append("裙装常用词：\(Array(dressTerms.prefix(6)).joined(separator: "、"))")
        }

        if query.containsAnyKeyword(accessoryHints), let accessoryTerms = learnedTerms[.accessory], !accessoryTerms.isEmpty {
            lines.append("小物常用词：\(Array(accessoryTerms.prefix(6)).joined(separator: "、"))")
        }

        if query.containsAnyKeyword(shoeHints), let shoeTerms = learnedTerms[.shoe], !shoeTerms.isEmpty {
            lines.append("鞋类常用词：\(Array(shoeTerms.prefix(4)).joined(separator: "、"))")
        }

        if lines.isEmpty {
            let generalTerms = Array(
                learnedTerms.values
                    .flatMap { $0 }
                    .uniqued()
                    .prefix(8)
            )
            if !generalTerms.isEmpty {
                lines.append("用户常用标签/类型：\(generalTerms.joined(separator: "、"))")
            }
        }

        guard !lines.isEmpty else { return nil }
        return """
        用户衣橱词汇偏好（很重要：优先按这些真实标签、类型和备注词理解，不要硬套通用类目）：
        - \(lines.joined(separator: "\n- "))
        """
    }

    private func learnedVocabularyTerms(from clothings: [Clothing]) -> [VocabularyCategory: [String]] {
        var buckets: [VocabularyCategory: [String]] = [:]

        func append(_ value: String, to category: VocabularyCategory) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return }
            var values = buckets[category] ?? []
            guard !values.contains(trimmed) else { return }
            values.append(trimmed)
            buckets[category] = Array(values.prefix(8))
        }

        for clothing in clothings {
            let searchable = buildSearchableText(for: clothing)
            let explicitTerms = explicitTerms(for: clothing)

            for alias in dressHints where searchable.contains(alias) {
                append(alias, to: .dress)
            }
            for alias in outerwearHints where searchable.contains(alias) {
                append(alias, to: .outerwear)
            }
            for alias in topHints where searchable.contains(alias) {
                append(alias, to: .top)
            }
            for alias in shoeHints where searchable.contains(alias) {
                append(alias, to: .shoe)
            }
            for alias in umbrellaHints where searchable.contains(alias) {
                append(alias, to: .umbrella)
            }
            for alias in accessoryHints where searchable.contains(alias) {
                append(alias, to: .accessory)
            }

            for term in explicitTerms {
                let lower = term.lowercased()
                if containsAny(in: lower, hints: dressHints) {
                    append(term, to: .dress)
                }
                if containsAny(in: lower, hints: outerwearHints) {
                    append(term, to: .outerwear)
                }
                if containsAny(in: lower, hints: topHints) {
                    append(term, to: .top)
                }
                if containsAny(in: lower, hints: shoeHints) {
                    append(term, to: .shoe)
                }
                if containsAny(in: lower, hints: umbrellaHints) {
                    append(term, to: .umbrella)
                }
                if containsAny(in: lower, hints: accessoryHints) {
                    append(term, to: .accessory)
                }
            }
        }

        return buckets
    }

    private func explicitTerms(for clothing: Clothing) -> [String] {
        let rawTerms = queryTokens(clothing.types) +
            queryTokens(clothing.length) +
            queryTokens(clothing.accessories) +
            queryTokens(clothing.note) +
            (clothing.tags?.map(\.name) ?? []) +
            (clothing.accessoryItems?.map(\.name) ?? [])

        return rawTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
            .uniqued()
    }

    private func requestedCategories(for query: String) -> Set<VocabularyCategory> {
        let lower = query.lowercased()
        var categories = Set<VocabularyCategory>()

        if lower.containsAnyKeyword(dressHints) {
            categories.insert(.dress)
        }
        if lower.containsAnyKeyword(outerwearHints) {
            categories.insert(.outerwear)
        }
        if lower.containsAnyKeyword(topHints) {
            categories.insert(.top)
        }
        if lower.containsAnyKeyword(shoeHints) {
            categories.insert(.shoe)
        }
        if lower.containsAnyKeyword(umbrellaHints) {
            categories.insert(.umbrella)
        }
        if lower.containsAnyKeyword(accessoryHints) {
            categories.insert(.accessory)
        }

        return categories
    }

    private func rankingTerms(for query: String, clothings: [Clothing]) -> [String] {
        let learnedTerms = learnedVocabularyTerms(from: clothings)
        let requested = requestedCategories(for: query)
        var terms = queryTokens(query)

        if !query.isEmpty {
            terms.append(query)
        }

        if query.containsAnyKeyword(outfitIntentHints) {
            terms.append(contentsOf: ["穿搭", "搭配", "ootd"])
        }

        if requested.contains(.dress) {
            terms.append(contentsOf: dressHints)
            terms.append(contentsOf: learnedTerms[.dress] ?? [])
        }
        if requested.contains(.outerwear) || requested.contains(.top) {
            terms.append(contentsOf: outerwearHints)
            terms.append(contentsOf: topHints)
            terms.append(contentsOf: learnedTerms[.outerwear] ?? [])
            terms.append(contentsOf: learnedTerms[.top] ?? [])
        }
        if requested.contains(.shoe) {
            terms.append(contentsOf: shoeHints)
            terms.append(contentsOf: learnedTerms[.shoe] ?? [])
        }
        if requested.contains(.umbrella) {
            terms.append(contentsOf: umbrellaHints)
            terms.append(contentsOf: learnedTerms[.umbrella] ?? [])
        }
        if requested.contains(.accessory) {
            terms.append(contentsOf: accessoryHints)
            terms.append(contentsOf: learnedTerms[.accessory] ?? [])
        }

        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func normalizeSearchQuery(_ query: String) -> String {
        query
            .replacingOccurrences(of: "帮我找", with: "")
            .replacingOccurrences(of: "我想找", with: "")
            .replacingOccurrences(of: "搜索", with: "")
            .replacingOccurrences(of: "有没有", with: "")
            .replacingOccurrences(of: "查一下", with: "")
            .replacingOccurrences(of: "查查", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func expandedSearchTerms(for query: String, clothings: [Clothing]) -> [String] {
        let learnedTerms = learnedVocabularyTerms(from: clothings)
        var terms = queryTokens(query)
        if !query.isEmpty {
            terms.append(query)
        }

        let categoryMap: [(VocabularyCategory, [String])] = [
            (.dress, dressHints),
            (.outerwear, outerwearHints),
            (.top, topHints),
            (.shoe, shoeHints),
            (.umbrella, umbrellaHints),
            (.accessory, accessoryHints)
        ]

        for (category, aliases) in categoryMap where query.containsAnyKeyword(aliases) {
            terms.append(contentsOf: aliases)
            terms.append(contentsOf: learnedTerms[category] ?? [])
        }

        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func scoreSearchMatch(for clothing: Clothing, query: String, expandedTerms: [String]) -> Int {
        let lowerName = clothing.name.lowercased()
        let lowerBrand = clothing.brand?.name.lowercased() ?? ""
        let lowerTypes = clothing.types.lowercased()
        let lowerLength = clothing.length.lowercased()
        let lowerAccessories = clothing.accessories.lowercased()
        let lowerNote = clothing.note.lowercased()
        let lowerTags = (clothing.tags?.map(\.name).joined(separator: ",") ?? "").lowercased()
        let lowerAccessoryItems = (clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? "").lowercased()
        let semanticText = ClothingSemanticAnalyzer.profile(for: clothing).featureTokens.joined(separator: ",").lowercased()

        var score = 0

        for term in expandedTerms {
            if lowerName.contains(term) {
                score += 7
            }
            if lowerTags.contains(term) {
                score += 6
            }
            if lowerTypes.contains(term) {
                score += 5
            }
            if lowerLength.contains(term) {
                score += 5
            }
            if lowerAccessories.contains(term) || lowerAccessoryItems.contains(term) {
                score += 4
            }
            if lowerBrand.contains(term) {
                score += 3
            }
            if lowerNote.contains(term) {
                score += 2
            }
            if semanticText.contains(term) {
                score += 4
            }
        }

        if lowerName.contains(query) || lowerTags.contains(query) || lowerTypes.contains(query) || lowerLength.contains(query) || semanticText.contains(query) {
            score += 4
        }

        return score
    }

    private func buildSuggestedPrompt(query: String, matchedTerms: [String]) -> String {
        let trimmedTerms = Array(matchedTerms.prefix(5))
        guard !trimmedTerms.isEmpty else {
            return "帮我按我衣橱里的标签、类型、备注和小物一起找衣服，如果名字不完全一样也帮我匹配"
        }

        return "帮我找适合“\(query)”的单品，优先参考这些标签/类型：\(trimmedTerms.joined(separator: "、"))，如果名字不完全一样也结合备注和小物一起找"
    }
    
    // 生成单品详细描述 (用于拖拽识别后)
    func generateItemDetail(clothing: Clothing) -> String {
        var detail = """
        【单品详情】
        名称：\(clothing.name)
        价格：¥\(NSDecimalNumber(decimal: clothing.price).stringValue)
        """
        
        if clothing.resolvedAccessoriesPrice > 0 {
            detail += "\n小物总价：¥\(NSDecimalNumber(decimal: clothing.resolvedAccessoriesPrice).stringValue)"
        }
        
        if !clothing.types.isEmpty {
            detail += "\n类型：\(clothing.types)"
        }
        
        if clothing.isDepositPlan {
            detail += "\n状态：预定中 (定金 ¥\(NSDecimalNumber(decimal: clothing.deposit).stringValue), 尾款 ¥\(NSDecimalNumber(decimal: clothing.balance).stringValue))"
            if let finalDate = clothing.finalPaymentDate {
                let dateStr = finalDate.formatted(date: .abbreviated, time: .omitted)
                detail += "\n补款时间：\(dateStr)"
            }
        }
        
        return detail
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    func containsAnyKeyword(_ keywords: [String]) -> Bool {
        let lower = lowercased()
        return keywords.contains { lower.contains($0.lowercased()) }
    }
}
