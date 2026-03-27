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
    let moodKeywords = [
        "心情怎么样", "心情咋样", "你现在心情", "情绪怎么样", "情绪如何",
        "开心吗", "高兴吗", "还开心吗", "不开心吗", "emo", "emo了", "郁闷",
        "低落", "委屈", "烦躁", "难过", "心里难受", "状态好吗", "还好吗"
    ]
    let intentMarkers = [
        petName.lowercased(), "你", "它", "萌宠", "宠物", "宝宝", "崽崽", "小家伙", "管家",
        "状态", "要不要", "该不该", "是不是", "看起来", "感觉"
    ]
    let directQuestionKeywords = [
        "饿了吗", "饿了没", "饿不饿", "饿吗",
        "渴了吗", "渴了没", "渴不渴", "渴吗",
        "心情怎么样", "情绪怎么样", "开心吗", "还好吗"
    ]

    let hungerIndex = petChatFirstMatchedKeywordIndex(in: text, keywords: hungerKeywords)
    let hydrationIndex = petChatFirstMatchedKeywordIndex(in: text, keywords: hydrationKeywords)
    let moodIndex = petChatFirstMatchedKeywordIndex(in: text, keywords: moodKeywords)
    guard hungerIndex != nil || hydrationIndex != nil || moodIndex != nil else { return nil }

    let hasIntentMarker = petChatContainsAnyKeyword(text, keywords: intentMarkers)
        || petChatContainsAnyKeyword(text, keywords: directQuestionKeywords)
    guard hasIntentMarker else { return nil }

    let candidates: [(PetStatusPanelKind, String.Index)] = [
        hungerIndex.map { (.hunger, $0) },
        hydrationIndex.map { (.hydration, $0) },
        moodIndex.map { (.mood, $0) }
    ].compactMap { $0 }

    return candidates.min { $0.1 < $1.1 }?.0
}

func contextualStatusReply(
    for kind: PetStatusPanelKind,
    status: PetStatus,
    sourceText: String?
) -> (message: String, subtitle: String?) {
    let defaultMessage = kind == .all
        ? "这是我现在的全部状态。"
        : "我把我的\(kind.title)单独拿出来给你看啦。"

    guard sourceText != nil else {
        return (defaultMessage, nil)
    }

    switch kind {
    case .hunger:
        let summary: String
        let subtitle: String
        switch status.hunger {
        case 75...:
            summary = "我现在还挺有饱腹感的"
            subtitle = "我现在不太饿，想让我继续稳稳的，可以先帮我备点吃的。"
        case 40..<75:
            summary = "我有点想加餐啦"
            subtitle = "我有一点点饿，点下面按钮就能马上喂我。"
        default:
            summary = "我真的有点饿啦，最好先让我吃一口"
            subtitle = "我现在饱食偏低，先打开背包喂我，或者带我去商店补货都可以。"
        }
        return (
            "你这么一问我就懂啦，我先把我现在的饱食情况给你看看，\(summary)。",
            subtitle
        )
    case .hydration:
        let summary: String
        let subtitle: String
        switch status.energy {
        case 75...:
            summary = "我现在的饮水状态还挺稳"
            subtitle = "我现在不太渴，想提前照顾我也可以点下面按钮。"
        case 40..<75:
            summary = "我有点渴了"
            subtitle = "我现在有点缺水，点下面就能马上给我补水。"
        default:
            summary = "我现在挺渴的，最好快点给我补水"
            subtitle = "我现在饮水偏低，先打开背包喂我喝点东西吧。"
        }
        return (
            "这个你问得特别及时，我先把我现在的饮水情况给你看看，\(summary)。",
            subtitle
        )
    case .mood:
        if petChatShouldShowSleepyExpression(status: status) {
            return (
                "我这会儿有点困困的，像在强撑着打哈欠。",
                "我现在更需要休息或者放松一下，先别给我太强的刺激哦。"
            )
        }

        let summary: String
        let subtitle: String
        switch status.mood {
        case 80...:
            summary = "我现在情绪很在线，整只都在发光"
            subtitle = "我现在心情超好，正适合多夸夸我。"
        case 55..<80:
            summary = "我状态还不错，就是有点想你多陪陪"
            subtitle = "我整体心情还算稳定，陪我聊两句会更开心。"
        case 30..<55:
            summary = "我有点蔫蔫的，像在等你安慰"
            subtitle = "我现在心情有点低，先陪我聊聊或者玩一会儿吧。"
        default:
            summary = "我明显有点低落，最好先多关注我一下"
            subtitle = "我现在心情不太好，先安慰我会更合适。"
        }
        return (
            "我懂你在担心我，我先把我现在的心情摊开给你看，\(summary)。",
            subtitle
        )
    default:
        return (defaultMessage, nil)
    }
}
