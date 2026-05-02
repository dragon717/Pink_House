import Foundation

enum PetChatIntent: Equatable {
    case wardrobeStats
    case outfitSuggestion
    case lastOutfitPrice
    case weatherGuidance
    case search
    case depositPlan
    case currencyOverview
    case petStatusOverview
    case petWork
    case secondPetAdoption
    case switchPetCompanion
    case meowCoinTopUp
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
        case .search:
            return .wardrobe
        case .depositPlan:
            return .wardrobe
        case .currencyOverview, .petStatusOverview, .petWork, .secondPetAdoption, .switchPetCompanion, .meowCoinTopUp:
            return .general
        case .moodSupport:
            return .mood
        case .generalChat:
            return .general
        }
    }

    // 越小优先级越高（用于同分时决策）
    var priorityRank: Int {
        switch self {
        case .meowCoinTopUp, .secondPetAdoption, .depositPlan:
            return 1
        case .switchPetCompanion:
            return 2
        case .petWork, .petStatusOverview, .currencyOverview:
            return 3
        case .weatherGuidance, .outfitSuggestion, .search, .wardrobeStats, .lastOutfitPrice:
            return 4
        case .moodSupport:
            return 5
        case .generalChat:
            return 6
        }
    }

    var guideTitle: String {
        switch self {
        case .wardrobeStats:
            return "我想看衣橱统计"
        case .outfitSuggestion:
            return "我想要一套穿搭"
        case .lastOutfitPrice:
            return "我想看上一套价格"
        case .weatherGuidance:
            return "我想看天气穿搭"
        case .search:
            return "我想找裙子"
        case .depositPlan:
            return "我想看尾款计划"
        case .currencyOverview:
            return "我想看三种货币余额"
        case .petStatusOverview:
            return "我想看萌宠状态"
        case .petWork:
            return "我想让萌宠打工"
        case .secondPetAdoption:
            return "我想领养二胎"
        case .switchPetCompanion:
            return "我想切换宠物管家"
        case .meowCoinTopUp:
            return "我想充值喵币"
        case .moodSupport:
            return "我想先被安慰一下"
        case .generalChat:
            return "我先随便聊聊"
        }
    }

    var guideCommand: String {
        switch self {
        case .outfitSuggestion:
            return "outfit_suggest"
        case .weatherGuidance:
            return "weather_guidance"
        case .search:
            return "search_prompt"
        case .moodSupport:
            return "mood_support"
        case .currencyOverview:
            return "pet_currency_panel"
        case .petStatusOverview:
            return "pet_status_panel"
        case .petWork:
            return "pet_work_panel"
        case .secondPetAdoption:
            return "pet_second_adopt"
        case .switchPetCompanion:
            return "pet_switch"
        case .meowCoinTopUp:
            return "pet_topup"
        case .wardrobeStats:
            return "ask:帮我看下衣橱统计"
        case .lastOutfitPrice:
            return "ask:帮我看上一套搭配价格"
        case .depositPlan:
            return "ask:帮我看尾款计划"
        case .generalChat:
            return "ask:我想聊聊"
        }
    }

    var guideIcon: String {
        switch self {
        case .wardrobeStats:
            return "chart.bar.fill"
        case .outfitSuggestion:
            return "wand.and.stars"
        case .lastOutfitPrice:
            return "tag.fill"
        case .weatherGuidance:
            return "cloud.sun.fill"
        case .search:
            return "magnifyingglass"
        case .depositPlan:
            return "creditcard.fill"
        case .currencyOverview:
            return "wallet.pass.fill"
        case .petStatusOverview:
            return "heart.text.square.fill"
        case .petWork:
            return "briefcase.fill"
        case .secondPetAdoption:
            return "pawprint.circle.fill"
        case .switchPetCompanion:
            return "arrow.triangle.2.circlepath"
        case .meowCoinTopUp:
            return "plus.circle.fill"
        case .moodSupport:
            return "face.smiling.fill"
        case .generalChat:
            return "bubble.left.and.bubble.right.fill"
        }
    }
}

enum PetChatIntentRouter {
    struct IntentCandidate: Equatable {
        let intent: PetChatIntent
        let score: Double
    }

    struct IntentDecision: Equatable {
        let primaryIntent: PetChatIntent
        let candidates: [IntentCandidate]
        let shouldDisambiguate: Bool
    }

    private static let disambiguationDelta: Double = 0.75
    private static let activationThreshold: Double = 0.9

    private static let wardrobeStatKeywords = ["统计", "多少", "价值", "几件", "总数", "衣橱有多少"]
    private static let outfitKeywords = ["ootd", "造型", "穿搭", "怎么穿", "搭一套", "搭配一套", "推荐一套"]
    private static let lastOutfitPriceKeywords = [
        "刚刚搭配", "上一套搭配", "刚才那套", "三件衣服", "价格多少", "总价多少", "那套多少钱",
        "推荐清单", "推荐列表", "列表总价", "清单总价", "这套总价", "这几件多少钱", "推荐单品"
    ]
    private static let weatherKeywords = ["天气", "温度", "下雨", "雨伞", "风大", "降温", "升温", "今天冷吗"]
    private static let searchKeywords = ["找", "搜索", "有没有", "帮我找", "查一下"]
    private static let depositKeywords = ["尾款", "定金", "补款", "尾款计划"]
    private static let moodKeywords = [
        "难过", "焦虑", "压力", "委屈", "心情", "心情怎么样", "情绪", "情绪不好",
        "安慰", "陪陪我", "emo", "emo了", "有点累", "低落", "烦躁", "心里堵"
    ]
    private static let currencyKeywords = ["喵币", "鱼币", "骨头币", "余额", "还有钱吗", "货币", "钱包", "财务"]
    private static let statusKeywords = [
        "状态", "状态怎么样", "状态如何", "饱食", "饮水", "清洁", "心情",
        "亲密度", "桃心", "它现在怎么样", "现在怎么样", "还好吗"
    ]
    private static let workKeywords = [
        "打工", "上班", "下班", "工作状态", "工作面板", "赚钱", "去赚", "赚", "挣币",
        "赚鱼币", "赚骨头币", "鱼币打工", "骨头币打工", "自动打工", "结束打工", "停止打工"
    ]
    private static let secondPetKeywords = ["领养", "收养", "二胎", "再养一只", "领养第二只", "再来一只", "再养个", "养一只", "领个宠物"]
    private static let switchPetKeywords = ["切换", "换一只", "换一个宠物", "换个宠物", "换只宠物", "换宠物", "切换宠物", "换奶茶", "换毛毛"]
    private static let switchVerbPrefixes = ["我要", "我想要", "我要换", "我想换", "我要切", "我想切", "换成", "切到", "切换到", "换到", "用", "给我", "来个"]
    private static let topUpKeywords = ["充值", "充币", "充点喵币", "买币", "氪金", "加点喵币"]
    private static let multiIntentJoiners = ["顺便", "同时", "然后", "再", "和", "并且", "还想"]

    static func detect(from text: String) -> PetChatIntent {
        decide(from: text).primaryIntent
    }

    static func decide(from text: String) -> IntentDecision {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return IntentDecision(primaryIntent: .generalChat, candidates: [], shouldDisambiguate: false)
        }

        var scored: [IntentCandidate] = []
        scored.append(.init(intent: .wardrobeStats, score: score(normalized, keywords: wardrobeStatKeywords)))
        scored.append(.init(intent: .outfitSuggestion, score: score(normalized, keywords: outfitKeywords)))
        scored.append(.init(intent: .lastOutfitPrice, score: score(normalized, keywords: lastOutfitPriceKeywords)))
        scored.append(.init(intent: .weatherGuidance, score: score(normalized, keywords: weatherKeywords)))
        scored.append(.init(intent: .search, score: score(normalized, keywords: searchKeywords)))
        scored.append(.init(intent: .depositPlan, score: score(normalized, keywords: depositKeywords)))
        scored.append(.init(intent: .currencyOverview, score: score(normalized, keywords: currencyKeywords)))
        scored.append(.init(intent: .petStatusOverview, score: score(normalized, keywords: statusKeywords)))
        scored.append(.init(intent: .petWork, score: score(normalized, keywords: workKeywords)))
        scored.append(.init(intent: .secondPetAdoption, score: score(normalized, keywords: secondPetKeywords)))
        scored.append(.init(intent: .switchPetCompanion, score: score(normalized, keywords: switchPetKeywords)))
        scored.append(.init(intent: .meowCoinTopUp, score: score(normalized, keywords: topUpKeywords)))
        scored.append(.init(intent: .moodSupport, score: score(normalized, keywords: moodKeywords)))
        applyOutfitPriceContextBoost(normalized: normalized, scored: &scored)

        let active = scored
            .filter { $0.score >= activationThreshold }
            .sorted {
                if $0.score == $1.score {
                    return $0.intent.priorityRank < $1.intent.priorityRank
                }
                return $0.score > $1.score
            }

        guard let primary = active.first else {
            return IntentDecision(primaryIntent: .generalChat, candidates: [], shouldDisambiguate: false)
        }

        let topCandidates = Array(active.prefix(3))
        let shouldDisambiguate = needsDisambiguation(normalized: normalized, topCandidates: topCandidates)

        return IntentDecision(
            primaryIntent: primary.intent,
            candidates: topCandidates,
            shouldDisambiguate: shouldDisambiguate
        )
    }

    static func detectSwitchTarget(from text: String, status: PetStatus) -> PetCharacter? {
        let normalized = normalizeAlias(text)
        guard !normalized.isEmpty else { return nil }

        var customAliasHit: PetCharacter?

        for pet in PetCharacter.allCases {
            let defaultAliases = Set([
                normalizeAlias(pet.displayName),
                normalizeAlias(pet.rawValue)
            ])

            var aliases = defaultAliases
            if let customAlias = cleanedCustomAlias(status.petNames[pet.id]) {
                aliases.insert(customAlias)
            }

            for alias in aliases where !alias.isEmpty {
                if isDirectSwitchExpression(text: normalized, alias: alias) {
                    return pet
                }

                let isCustomAlias = !defaultAliases.contains(alias)
                if isCustomAlias && normalized.contains(alias) {
                    customAliasHit = pet
                }
            }
        }

        return customAliasHit
    }

    private static func needsDisambiguation(normalized: String, topCandidates: [IntentCandidate]) -> Bool {
        guard topCandidates.count >= 2 else { return false }
        let first = topCandidates[0]
        let second = topCandidates[1]

        let hardConflict = Set([first.intent, second.intent]) == Set([.meowCoinTopUp, .secondPetAdoption])
        if hardConflict { return true }

        let closeScore = abs(first.score - second.score) < disambiguationDelta
        let hasJoiner = containsAny(multiIntentJoiners, in: normalized)
        return closeScore && hasJoiner
    }

    private static func score(_ text: String, keywords: [String]) -> Double {
        var result: Double = 0
        for keyword in keywords where text.contains(keyword) {
            if keyword.count >= 3 {
                result += 1.2
            } else {
                result += 1.0
            }
        }
        return result
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func applyOutfitPriceContextBoost(normalized: String, scored: inout [IntentCandidate]) {
        guard isOutfitPriceQuery(normalized) else { return }
        guard let index = scored.firstIndex(where: { $0.intent == .lastOutfitPrice }) else { return }
        let boosted = IntentCandidate(intent: .lastOutfitPrice, score: scored[index].score + 2.4)
        scored[index] = boosted
    }

    private static func isOutfitPriceQuery(_ text: String) -> Bool {
        let hasPriceSignal = containsAny(["价格", "总价", "合计", "一共", "多少钱"], in: text)
        guard hasPriceSignal else { return false }
        return containsAny(["搭配", "推荐", "清单", "列表", "单品", "这套", "那套", "这几件", "刚刚", "上一套", "衣服"], in: text)
    }

    private static func cleanedCustomAlias(_ alias: String?) -> String? {
        guard let alias else { return nil }
        let cleaned = normalizeAlias(alias.replacingOccurrences(of: "\"", with: ""))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalizeAlias(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }

    private static func isDirectSwitchExpression(text: String, alias: String) -> Bool {
        guard !alias.isEmpty else { return false }
        if switchPetKeywords.contains(where: { text.contains($0) }) && text.contains(alias) {
            return true
        }
        return switchVerbPrefixes.contains { prefix in
            text.contains(prefix + alias)
        }
    }
}
