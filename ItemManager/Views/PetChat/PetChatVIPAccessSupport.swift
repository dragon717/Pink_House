import Foundation

enum PetChatPremiumFeature {
    case remoteChat
    case outfitSuggestion
    case weatherGuidance
    case imageAnalysis

    var title: String {
        switch self {
        case .remoteChat:
            return "萌宠智能对话"
        case .outfitSuggestion:
            return "AI穿搭建议"
        case .weatherGuidance:
            return "天气穿搭"
        case .imageAnalysis:
            return "多模态图片分析"
        }
    }

    var subtitle: String {
        switch self {
        case .remoteChat:
            return "这部分会调用第三方模型，让我更认真地陪你聊天。"
        case .outfitSuggestion:
            return "这部分会调用第三方模型，帮你做更完整的穿搭推理。"
        case .weatherGuidance:
            return "这部分会结合实时天气和第三方智能能力给你更细的建议。"
        case .imageAnalysis:
            return "这部分会调用第三方模型做更完整的图片理解与追问。"
        }
    }

    func upsellText(petName: String) -> String {
        switch self {
        case .remoteChat:
            return "\(petName)当然愿意继续陪你聊呀，只是这种要认真开动大脑的高级聊天，得升级 VIP 我才能火力全开喵~"
        case .outfitSuggestion:
            return "我已经开始替你心动了喵，不过这种更会动脑筋的搭配建议，要升级 VIP 我才能认真替你挑整套呀~"
        case .weatherGuidance:
            return "我可以先陪你看本地信息喵，但这种更完整的天气穿搭建议，要升级 VIP 我才能帮你联动更厉害的智能能力~"
        case .imageAnalysis:
            return "我先帮你看到了图片里的大概内容喵，如果想让我继续认真分析、顺着图聊下去，就给我升个 VIP 吧~"
        }
    }
}

enum PetChatVIPAccessSupport {
    static func upgradeMessage(for feature: PetChatPremiumFeature, petName: String) -> PetChatMessage {
        let widget = PetWidgetData(
            type: .quickOptions,
            title: "\(feature.title) 是 VIP 权益",
            subtitle: feature.subtitle,
            options: [
                PetWidgetOption(title: "去升级VIP", command: "open_vip_center", icon: "crown.fill"),
                PetWidgetOption(title: "先看看权益", command: "open_vip_center", icon: "sparkles"),
                PetWidgetOption(title: "喵币不够？", command: "open_meow_store", icon: "cart.fill")
            ]
        )

        return PetChatMessage(
            text: feature.upsellText(petName: petName),
            isUser: false,
            isAIGenerated: true,
            widgets: [widget]
        )
    }
}
