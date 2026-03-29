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
        context: ModelContext
    ) async throws -> ([Clothing], String, String, String) {
        // 过滤掉心愿尾款的裙装（只从非心愿尾款中选择）
        let availableClothings = clothings.filter { !$0.isDepositPlan }
        
        // 检查是否有足够的非心愿尾款裙装
        guard availableClothings.count >= 2 else {
            throw OutfitSuggestionError.insufficientNonDepositItems
        }
        
        // 1. 调用 AI 获取搭配建议
        let suggestion = try await fetchOutfitSuggestionFromAI(
            query: query,
            clothings: availableClothings
        )

        // 2. 获取推荐的裙装
        let matchedClothings = matchSelectedClothings(suggestion: suggestion, clothings: availableClothings)
        let selectedClothings = OutfitColorHarmonyEngine.refineSelection(
            matchedClothings,
            within: availableClothings
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
        context: ModelContext
    ) async throws -> [Clothing] {
        // 过滤掉心愿尾款的裙装（只从非心愿尾款中选择）
        let availableClothings = clothings.filter { !$0.isDepositPlan }
        
        // 检查是否有足够的非心愿尾款裙装
        guard availableClothings.count >= 2 else {
            throw OutfitSuggestionError.insufficientNonDepositItems
        }
        
        // 根据风格和场景对裙装进行评分排序
        let scoredClothings = availableClothings.map { clothing in
            (clothing: clothing, score: calculateOutfitScore(clothing: clothing, style: style, occasion: occasion))
        }.sorted { $0.score > $1.score }
        
        // 从高评分的裙装中选择
        var result: [Clothing] = []
        var usedCategories = Set<String>()
        
        // 先按类别分组
        let grouped = Dictionary(grouping: scoredClothings) { item -> String in
            let clothing = item.clothing
            let text = searchableText(for: clothing)
            if matchesAny(text, keywords: ["jsk", "op", "sk", "裙", "连衣", "吊带", "半裙"]) {
                return "裙装"
            } else if matchesAny(text, keywords: ["外套", "开衫", "罩衫", "针织", "披肩", "披风", "小外套", "短外套", "大衣", "斗篷", "风衣", "夹克", "西装", "西服", "毛衣", "卫衣", "上衣", "衬衫", "内搭", "打底", "马甲", "背心"]) {
                return "外套"
            } else if matchesAny(text, keywords: ["鞋", "皮鞋", "高跟", "玛丽珍", "乐福", "靴", "凉鞋", "单鞋"]) {
                return "鞋子"
            } else {
                return "配饰"
            }
        }
        
        // 优先选择裙装（选择评分最高的）
        if let dresses = grouped["裙装"], !dresses.isEmpty {
            let bestDress = dresses.max { $0.score < $1.score }!.clothing
            result.append(bestDress)
            usedCategories.insert("裙装")
        }
        
        // 选择外套（选择评分最高的且与裙装颜色和谐的）
        if let tops = grouped["外套"], !tops.isEmpty {
            let sortedTops = tops.sorted { $0.score > $1.score }
            if let bestTop = sortedTops.first?.clothing {
                result.append(bestTop)
                usedCategories.insert("外套")
            }
        }
        
        // 选择鞋子（选择评分最高的）
        if let shoes = grouped["鞋子"], !shoes.isEmpty {
            let sortedShoes = shoes.sorted { $0.score > $1.score }
            if let bestShoe = sortedShoes.first?.clothing {
                result.append(bestShoe)
                usedCategories.insert("鞋子")
            }
        }
        
        // 选择配饰（选择评分最高的 1-2 个）
        if let accessories = grouped["配饰"], !accessories.isEmpty {
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
            let remaining = availableClothings.filter { !result.contains($0) }
            result.append(contentsOf: remaining.shuffled().prefix(2 - result.count))
        }
        
        // 使用颜色和谐引擎优化
        result = OutfitColorHarmonyEngine.refineSelection(result, within: availableClothings)
        
        guard result.count >= 2 else {
            throw OutfitSuggestionError.insufficientItems
        }
        
        return result
    }
    
    /// 根据风格和场景计算裙装评分
    private func calculateOutfitScore(clothing: Clothing, style: String, occasion: String) -> Int {
        var score = 0
        let text = searchableText(for: clothing)
        
        // 风格关键词匹配
        let styleKeywords = getStyleKeywords(style)
        let matchedStyleKeywords = styleKeywords.filter { matchesAny(text, keywords: [$0]) }
        score += matchedStyleKeywords.count * 30
        
        // 场景关键词匹配
        let occasionKeywords = getOccasionKeywords(occasion)
        let matchedOccasionKeywords = occasionKeywords.filter { matchesAny(text, keywords: [$0]) }
        score += matchedOccasionKeywords.count * 25
        
        // 颜色匹配（根据风格偏好的颜色）
        let preferredColors = getPreferredColors(style)
        let matchedColors = preferredColors.filter { matchesAny(text, keywords: [$0]) }
        score += matchedColors.count * 20
        
        // 新品优先（按创建时间）
        let daysSinceCreation = Date().timeIntervalSince(clothing.createdAt) / 86400
        if daysSinceCreation < 7 {
            score += 15
        } else if daysSinceCreation < 30 {
            score += 5
        }
        
        // 基础加分
        score += 10
        
        return score
    }
    
    /// 获取裙装的可搜索文本
    private func searchableText(for clothing: Clothing) -> String {
        let tagNames = clothing.tags?.map(\.name).joined(separator: ",") ?? ""
        let accessoryNames = clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? ""

        return [
            clothing.name,
            clothing.types,
            clothing.colors,
            clothing.note,
            clothing.accessories,
            tagNames,
            accessoryNames
        ]
        .joined(separator: ",")
        .lowercased()
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

    // MARK: - 私有方法

    /// 从AI获取搭配建议
    private func fetchOutfitSuggestionFromAI(
        query: String,
        clothings: [Clothing]
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
            candidatesJSON: candidatesJSON
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
    private func buildOutfitPrompt(query: String, wardrobeSummary: String, candidatesJSON: String) -> String {
        let roleSuffix = currentCharacter == .maomao ? "汪~" : "喵~"
        return """
        需求：\(query)

        候选单品：
        \(candidatesJSON)

        请从候选中选2-4件搭配：
        - 按品类（裙装/外套/鞋子/配饰）筛选
        - 优先同色系/近色系，主色1-2种，不超3种
        - 优先JSK/OP，鞋子同色或黑白灰米棕
        - 用候选单品的标签/类型词汇

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
            for clothing in clothings.prefix(4) {
                if seen.insert(clothing.id).inserted {
                    selected.append(clothing)
                }
                if selected.count >= 2 {
                    break
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
        let text = searchableText(for: clothing)
        var families = Set<OutfitColorFamily>()

        if matchesAny(text, keywords: ["多色", "彩色", "拼色", "撞色", "multicolor"]) {
            families.insert(.multicolor)
        }
        if matchesAny(text, keywords: ["白", "米白", "奶白", "奶油", "象牙", "香槟", "灰", "黑", "银", "米色", "杏色", "beige", "cream", "white", "black", "grey", "gray"]) {
            families.insert(.neutral)
        }
        if matchesAny(text, keywords: ["金", "银", "metal", "metallic"]) {
            families.insert(.metallic)
        }
        if matchesAny(text, keywords: ["粉", "樱", "蜜桃", "桃", "rose", "pink"]) {
            families.insert(.pink)
        }
        if matchesAny(text, keywords: ["酒红", "红", "莓", "绯", "赤", "burgundy", "red"]) {
            families.insert(.red)
        }
        if matchesAny(text, keywords: ["橙", "杏黄", "珊瑚", "orange", "coral"]) {
            families.insert(.orange)
        }
        if matchesAny(text, keywords: ["黄", "鹅黄", "柠檬", "yellow"]) {
            families.insert(.yellow)
        }
        if matchesAny(text, keywords: ["若草", "薄荷", "牛油果", "绿", "mint", "green"]) {
            families.insert(.green)
        }
        if matchesAny(text, keywords: ["萨克斯", "sax", "绀", "藏青", "海军蓝", "天蓝", "水蓝", "蓝", "blue", "navy"]) {
            families.insert(.blue)
        }
        if matchesAny(text, keywords: ["薰衣草", "丁香", "紫", "lavender", "purple"]) {
            families.insert(.purple)
        }
        if matchesAny(text, keywords: ["棕", "咖", "巧克力", "驼", "卡其", "brown", "camel", "khaki"]) {
            families.insert(.brown)
        }

        return families
    }

    private static func pieceCategory(for clothing: Clothing) -> OutfitPieceCategory {
        let text = searchableText(for: clothing)

        if matchesAny(text, keywords: ["jsk", "op", "sk", "裙", "连衣", "吊带", "半裙"]) {
            return .dress
        }
        if matchesAny(text, keywords: ["外套", "开衫", "罩衫", "针织", "披肩", "披风", "小外套", "短外套", "大衣", "斗篷", "风衣", "夹克", "西装", "西服", "毛衣", "卫衣", "上衣", "衬衫", "内搭", "打底", "马甲", "背心"]) {
            return .outerwear
        }
        if matchesAny(text, keywords: ["鞋", "皮鞋", "高跟", "玛丽珍", "乐福", "靴", "凉鞋", "单鞋"]) {
            return .shoes
        }
        if matchesAny(text, keywords: ["发带", "kc", "头饰", "胸针", "包", "袜", "手袖", "腰带", "项链", "耳环", "手链", "发夹", "配饰", "小物"]) {
            return .accessory
        }
        return .other
    }

    private static func searchableText(for clothing: Clothing) -> String {
        let tagNames = clothing.tags?.map(\.name).joined(separator: ",") ?? ""
        let accessoryNames = clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? ""

        return [
            clothing.name,
            clothing.types,
            clothing.colors,
            clothing.note,
            clothing.accessories,
            tagNames,
            accessoryNames
        ]
        .joined(separator: ",")
        .lowercased()
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
            return PetDataManager.shared.getCurrentPetCharacter().localizedCatchphraseText("（蹭蹭）主人衣橱里已经到手的裙子还不够呢~ 至少要有 2 件才能智能搭配喵！那些还没补尾款的不算哦~")
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
