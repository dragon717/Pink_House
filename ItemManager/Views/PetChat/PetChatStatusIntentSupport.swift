import Foundation

private func petChatContainsAnyKeyword(_ text: String, keywords: [String]) -> Bool {
    keywords.contains { text.contains($0) }
}

private func petChatFirstMatchedKeywordIndex(in text: String, keywords: [String]) -> String.Index? {
    keywords.compactMap { keyword in
        text.range(of: keyword)?.lowerBound
    }.min()
}

func detectFuzzyStatusPanelKind(from text: String, petName: String) -> PetStatusPanelKind? {
    let hungerKeywords = [
        "饿了吗", "饿不饿", "饿吗", "饿了没", "有点饿", "是不是饿",
        "要不要吃点", "该喂了", "吃了吗", "吃东西了吗", "肚子饿", "饱食"
    ]
    let hydrationKeywords = [
        "渴了吗", "渴不渴", "渴吗", "渴了没", "有点渴", "是不是渴",
        "要不要喝点", "该喝水了", "喝水了吗", "喝了吗", "想喝水", "口渴", "饮水", "没水了"
    ]
    let intentMarkers = [
        petName.lowercased(), "你", "它", "萌宠", "宠物", "宝宝", "崽崽", "小家伙", "管家",
        "状态", "要不要", "该不该", "是不是", "看起来", "感觉"
    ]
    let directQuestionKeywords = ["饿了吗", "饿了没", "饿不饿", "饿吗", "渴了吗", "渴了没", "渴不渴", "渴吗"]

    let hungerIndex = petChatFirstMatchedKeywordIndex(in: text, keywords: hungerKeywords)
    let hydrationIndex = petChatFirstMatchedKeywordIndex(in: text, keywords: hydrationKeywords)
    guard hungerIndex != nil || hydrationIndex != nil else { return nil }

    let hasIntentMarker = petChatContainsAnyKeyword(text, keywords: intentMarkers)
        || petChatContainsAnyKeyword(text, keywords: directQuestionKeywords)
    guard hasIntentMarker else { return nil }

    switch (hungerIndex, hydrationIndex) {
    case let (.some(hunger), .some(hydration)):
        return hunger <= hydration ? .hunger : .hydration
    case (.some, nil):
        return .hunger
    case (nil, .some):
        return .hydration
    default:
        return nil
    }
}

func contextualStatusReply(
    for kind: PetStatusPanelKind,
    status: PetStatus,
    sourceText: String?
) -> (message: String, subtitle: String?) {
    let defaultMessage = kind == .all
        ? "这是\(status.displayName)现在的全部状态。"
        : "我把\(status.displayName)的\(kind.title)单独拎出来给你看啦。"

    guard sourceText != nil else {
        return (defaultMessage, nil)
    }

    switch kind {
    case .hunger:
        let summary: String
        let subtitle: String
        switch status.hunger {
        case 75...:
            summary = "它现在还挺有饱腹感的"
            subtitle = "\(status.displayName)目前不太饿，想维持状态可以先备点吃的。"
        case 40..<75:
            summary = "它有点想加餐啦"
            subtitle = "\(status.displayName)有一点饿，点下面按钮就能马上喂它。"
        default:
            summary = "它明显饿了，建议优先喂一口"
            subtitle = "\(status.displayName)当前饱食偏低，建议先开背包喂食或去商店补货。"
        }
        return (
            "你这么一问我就懂啦，我先给你看看\(status.displayName)现在的饱食情况，\(summary)。",
            subtitle
        )
    case .hydration:
        let summary: String
        let subtitle: String
        switch status.energy {
        case 75...:
            summary = "它现在的饮水状态还挺稳"
            subtitle = "\(status.displayName)目前不太渴，想提前照顾也可以点下面按钮。"
        case 40..<75:
            summary = "它有点渴了"
            subtitle = "\(status.displayName)现在有点缺水，点下面就能补水。"
        default:
            summary = "它现在挺渴的，最好尽快补水"
            subtitle = "\(status.displayName)当前饮水偏低，建议先开背包喂点喝的。"
        }
        return (
            "这个你问得特别及时，我先给你看看\(status.displayName)现在的饮水情况，\(summary)。",
            subtitle
        )
    default:
        return (defaultMessage, nil)
    }
}
