import Foundation
import SwiftData

class WardrobeContextManager {
    static let shared = WardrobeContextManager()
    
    private init() {}
    
    private let dressHints = ["jsk", "op", "sk", "裙", "连衣", "半裙", "吊带"]
    private let shoeHints = ["鞋", "皮鞋", "玛丽珍", "乐福", "高跟", "靴", "凉鞋", "单鞋"]
    private let umbrellaHints = ["伞", "雨伞", "晴雨伞", "折叠伞", "防晒伞"]
    private let accessoryHints = ["小物", "配饰", "胸针", "项链", "发带", "发箍", "耳饰", "帽", "包", "袜", "手袖", "腰带"]
    private let weatherHints = ["天气", "温度", "下雨", "雨天", "降水", "风大", "出门", "体感"]
    private let depositHints = ["尾款", "定金", "补款", "预定"]

    private enum ContextFocus {
        case wardrobeCore
        case weatherOutfit
        case deposit
        case general
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
        let totalValue = clothings.reduce(Decimal(0)) { $0 + (($1.price + $1.accessoriesPrice) * Decimal($1.stock)) }

        // 2. 最贵单品 (包含小物)
        let mostExpensiveItem = clothings.max(by: { ($0.price + $0.accessoriesPrice) < ($1.price + $1.accessoriesPrice) })
        let mostExpensivePrice = mostExpensiveItem.map { $0.price + $0.accessoriesPrice } ?? 0

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
        
        return """
        用户问题：\(query)
        
        以下是衣橱摘要（仅供参考）：
        \(summary)
        
        以下是遴选后的候选单品（JSON，仅包含名字和特征）：
        \(relevantJSON)
        
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
            let block = composeContextBlock(summary: summary, relevantJSON: relevantJSON)
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
        let tokens = queryTokens(query)
        let focus = detectFocus(from: query)
        
        let scored = clothings.map { clothing -> (Clothing, Int) in
            let searchable = buildSearchableText(for: clothing)
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

        let focused = applyFocusFilter(focus, sortedClothings: sortedByScore)
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
    
    private func queryTokens(_ query: String) -> [String] {
        query
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "，。！？、,!?：:；; \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 1 }
    }
    
    private func buildSearchableText(for clothing: Clothing) -> String {
        let accessoryItems = clothing.accessoryItems?.map(\.name).joined(separator: ",") ?? ""
        return [
            clothing.name,
            clothing.types,
            clothing.colors,
            clothing.accessories,
            accessoryItems,
            clothing.note,
            clothing.brand?.name ?? ""
        ]
        .joined(separator: ",")
        .lowercased()
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
        if containsAny(in: lower, hints: dressHints + accessoryHints + shoeHints + umbrellaHints) {
            return .wardrobeCore
        }
        return .general
    }

    private func applyFocusFilter(_ focus: ContextFocus, sortedClothings: [Clothing]) -> [Clothing] {
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
                    containsAny(in: searchable, hints: accessoryHints) ||
                    containsAny(in: searchable, hints: shoeHints) ||
                    containsAny(in: searchable, hints: umbrellaHints) ||
                    !(clothing.accessoryItems ?? []).isEmpty
            }
            return core.isEmpty ? sortedClothings : core
        case .general:
            return []
        }
    }

    private func assembleWeatherOutfitItems(from sortedClothings: [Clothing]) -> [Clothing] {
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

        let dresses = sortedClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: dressHints) }
        let shoes = sortedClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: shoeHints) }
        let umbrellas = sortedClothings.filter { containsAny(in: buildSearchableText(for: $0), hints: umbrellaHints) }
        let accessories = sortedClothings.filter {
            let searchable = buildSearchableText(for: $0)
            return containsAny(in: searchable, hints: accessoryHints) || !(($0.accessoryItems ?? []).isEmpty)
        }

        append(Array(dresses.prefix(6)), limit: 6)
        append(Array(shoes.prefix(3)), limit: 3)
        append(Array(umbrellas.prefix(2)), limit: 2)
        append(Array(accessories.prefix(3)), limit: 3)

        if result.isEmpty {
            return sortedClothings
        }

        for item in sortedClothings where result.count < 12 {
            guard pickedIDs.insert(item.id).inserted else { continue }
            result.append(item)
        }

        return result
    }
    
    private func buildItemPayload(for clothing: Clothing) -> [String: Any] {
        var features: [String] = []
        let brand = clothing.brand?.name ?? "未知品牌"
        features.append("品牌:\(brand)")
        
        if !clothing.types.isEmpty {
            features.append("类型:\(clothing.types)")
        }
        if !clothing.colors.isEmpty {
            features.append("颜色:\(clothing.colors)")
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
        features = Array(features.prefix(4))
        
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

    private func composeContextBlock(summary: String, relevantJSON: String) -> String {
        """
        以下是衣橱摘要（仅供参考）：
        \(summary)

        以下是遴选后的候选单品（JSON，仅包含名字和特征）：
        \(relevantJSON)
        """
    }
    
    // 生成单品详细描述 (用于拖拽识别后)
    func generateItemDetail(clothing: Clothing) -> String {
        var detail = """
        【单品详情】
        名称：\(clothing.name)
        价格：¥\(NSDecimalNumber(decimal: clothing.price).stringValue)
        """
        
        if clothing.accessoriesPrice > 0 {
            detail += "\n小物总价：¥\(NSDecimalNumber(decimal: clothing.accessoriesPrice).stringValue)"
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
