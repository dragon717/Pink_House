import Foundation

enum PetGenerativePromptBuilder {
    struct PromptInput {
        let userQuery: String
        let wardrobeContextBlock: String?
        let persona: PetPersonaProfile
        let module: PetConversationModule
        let recentAssistantReplies: [String]
    }

    static func buildPrompt(input: PromptInput) -> String {
        let roleCard = PetRoleCardRegistry.card(for: input.persona.role, petName: input.persona.displayName)
        PetConversationMemoryStore.shared.recordUserSignal(
            query: input.userQuery,
            role: input.persona.role,
            module: input.module
        )
        let memorySummary = PetConversationMemoryStore.shared.summary(for: input.persona.role)
        let outfitPriceSummary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: input.persona.role)
        let hasWardrobeContext = (input.wardrobeContextBlock?.isEmpty == false)
        let toolsInstruction = PetConversationToolbox.buildToolsInstruction(
            module: input.module,
            hasWardrobeContext: hasWardrobeContext,
            role: input.persona.role
        )

        var parts: [String] = []
        parts.append("你正在扮演：\(input.persona.displayName)（\(input.persona.species)）")
        parts.append("风格要求：\(input.persona.stylePrompt)")
        parts.append(
            """
            角色卡：
            - 性格：\(roleCard.temperament)
            - 说话风格：\(roleCard.speechStyle)
            - 喜欢：\(roleCard.likes.joined(separator: "、"))
            - 不喜欢：\(roleCard.dislikes.joined(separator: "、"))
            - 行为准则：\(roleCard.behaviorRules.joined(separator: "；"))
            """
        )
        parts.append("模块目标：\(input.persona.modulePrompts[input.module] ?? "自然聊天，优先解决用户需求。")")
        parts.append("禁用词：\(input.persona.forbiddenWords.joined(separator: "、"))")
        parts.append(PetConversationToolbox.buildPetStateHint())
        if let memorySummary, !memorySummary.isEmpty {
            parts.append("历史记忆（只作参考，优先听当前用户表达）：\n\(memorySummary)")
        }
        if shouldIncludeOutfitPriceHint(query: input.userQuery),
           let outfitPriceSummary,
           !outfitPriceSummary.isEmpty {
            parts.append("最近搭配价格快照（可用于回答“刚刚那套多少钱”）：\n- \(outfitPriceSummary)")
        }
        parts.append(toolsInstruction)

        if !input.recentAssistantReplies.isEmpty {
            let recent = input.recentAssistantReplies
                .suffix(2)
                .map { "- \($0)" }
                .joined(separator: "\n")
            parts.append("最近你刚说过：\n\(recent)\n请避免重复句式和重复口头禅。")
        }

        parts.append("用户原始问题：\(input.userQuery)")

        if let wardrobeContextBlock = input.wardrobeContextBlock, !wardrobeContextBlock.isEmpty {
            parts.append(wardrobeContextBlock)
        }

        parts.append(outputProtocol)
        return parts.joined(separator: "\n\n")
    }

    // 兼容旧调用，便于增量迁移。
    static func buildPrompt(
        userQuery: String,
        wardrobeContextBlock: String?
    ) -> String {
        let fallbackPersona = PetPersonaRegistry.profile(for: .kitten, petName: "奶茶")
        return buildPrompt(
            input: PromptInput(
                userQuery: userQuery,
                wardrobeContextBlock: wardrobeContextBlock,
                persona: fallbackPersona,
                module: .general,
                recentAssistantReplies: []
            )
        )
    }

    static func recentAssistantReplies<Message>(
        from messages: [Message],
        limit: Int = 4,
        isUser: (Message) -> Bool,
        text: (Message) -> String
    ) -> [String] {
        messages
            .filter { !isUser($0) }
            .suffix(limit)
            .map(text)
    }

    private static func shouldIncludeOutfitPriceHint(query: String) -> Bool {
        let lower = query.lowercased()
        return (lower.contains("刚刚搭配") || lower.contains("上一套") || lower.contains("刚才那套") || lower.contains("三件衣服")) &&
            (lower.contains("价格") || lower.contains("总价") || lower.contains("多少钱"))
    }

    private static let outputProtocol = """
    【输出协议（必须遵守）】
    1) 仅输出 JSON 对象，不要 Markdown，不要代码块。
    2) JSON 结构固定：
    {"text":"...","widgets":[{"type":"quick_options","title":"...","options":[{"title":"A. ...","command":"..."},{"title":"B. ...","command":"..."},{"title":"C. ...","command":"..."}]}]}
    3) text 要口语化、拟人化，可撒娇安抚；严禁出现模型名、服务商名或“JSON对象”等技术词。
    4) widgets 最多 2 个；每个 options 最多 3 个；command 仅可用：
       outfit_suggest / weather_guidance / search_prompt / mood_support / ask:具体问题
    5) 若本轮与衣橱无关，不要编造衣橱数据；若与穿搭相关，优先基于给定候选单品给建议。
    """
}
