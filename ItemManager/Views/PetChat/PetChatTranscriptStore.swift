import Foundation

enum PetChatTranscriptStore {
    private static let storageKey = "pet_chat_transcript_v4"
    private static let legacyImportFlagKey = "pet_chat_transcript_v3_legacy_imported_v1"

    static func historyWindowSize() -> Int {
        let memoryInGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        if memoryInGB >= 6 { return 35 }
        if memoryInGB >= 4 { return 18 }
        return 10
    }

    static func save(messages: [PetChatMessage]) {
        let payload = normalizedPersistedMessages(from: messages).map(PersistedPetChatMessage.init)
        guard let data = try? JSONEncoder().encode(Array(payload)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// 加载历史消息，并支持通过 clothings 数组 enrich Clothing 对象引用
    static func load(enrichingWith clothings: [Clothing] = []) -> [PetChatMessage] {
        let lookup = makeClothingLookup(from: clothings)
        let storedMessages = loadStoredMessages(enrichingWith: lookup)
        let migratedMessages = migrateLegacyHistoryIfNeeded(existingMessages: storedMessages, clothings: clothings)
        let normalized = normalizedPersistedMessages(from: migratedMessages)
        return normalized.filter { message in
            if message.isUser && !message.isUserAuthored {
                return false
            }
            if message.isUser && message.isUserAuthored {
                let trimmed = sanitizeUserText(message.text).trimmingCharacters(in: .whitespacesAndNewlines)
                // 加强JSON过滤，防止JSON内容透出到用户界面
                if isJSONLikeContent(trimmed) {
                    return false
                }
                if !isLikelyManualUserText(trimmed) {
                    return false
                }
            }
            return true
        }
    }

    /// 查询历史消息（支持 enrich Clothing 对象）
    static func query(
        keyword: String? = nil,
        page: Int = 0,
        pageSize: Int = 20,
        onlyUserMessages: Bool = true,
        clothings: [Clothing] = []
    ) -> [PetChatMessage] {
        let all = load(enrichingWith: clothings)
        let base = onlyUserMessages ? all.filter(isReusableUserMessage) : all
        let trimmedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filtered: [PetChatMessage]
        if trimmedKeyword.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { message in
                // 搜索消息文本
                if message.text.localizedCaseInsensitiveContains(trimmedKeyword) {
                    return true
                }
                // 搜索 widgets 中的内容（标题、选项等）
                if let widgets = message.widgets {
                    for widget in widgets {
                        if let title = widget.title,
                           title.localizedCaseInsensitiveContains(trimmedKeyword) {
                            return true
                        }
                        if let subtitle = widget.subtitle,
                           subtitle.localizedCaseInsensitiveContains(trimmedKeyword) {
                            return true
                        }
                        for option in widget.options {
                            if option.title.localizedCaseInsensitiveContains(trimmedKeyword) {
                                return true
                            }
                        }
                    }
                }
                return false
            }
        }

        let newestFirst = Array(filtered.reversed())
        let normalizedPage = max(0, page)
        let normalizedSize = max(1, min(pageSize, 50))
        let start = normalizedPage * normalizedSize
        guard start < newestFirst.count else { return [] }
        let end = min(newestFirst.count, start + normalizedSize)
        return Array(newestFirst[start..<end])
    }

    static func count(onlyUserMessages: Bool = true, clothings: [Clothing] = []) -> Int {
        if onlyUserMessages {
            return load(enrichingWith: clothings).filter(isReusableUserMessage).count
        }
        return load(enrichingWith: clothings).count
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: legacyImportFlagKey)
    }

    // MARK: - Clothing Lookup Helper

    private static func makeClothingLookup(from clothings: [Clothing]) -> (UUID) -> Clothing? {
        let byID = Dictionary(clothings.compactMap { (id: $0.id, clothing: $0) }, uniquingKeysWith: { first, _ in first })
        return { byID[$0] }
    }

    // MARK: - Persisted Structures for Rich Content

    /// 持久化的衣橱统计数据（用 UUID 替代 Clothing 引用）
    private struct PersistedWardrobeStats: Codable {
        let totalCount: Int
        let totalValue: String
        let mostExpensiveItemID: UUID?
        let depositPlanCount: Int
        let totalDeposit: String
        let totalBalance: String

        init(from stats: WardrobeStats) {
            self.totalCount = stats.totalCount
            self.totalValue = NSDecimalNumber(decimal: stats.totalValue).stringValue
            self.mostExpensiveItemID = stats.mostExpensiveItem?.id
            self.depositPlanCount = stats.depositPlanCount
            self.totalDeposit = NSDecimalNumber(decimal: stats.totalDeposit).stringValue
            self.totalBalance = NSDecimalNumber(decimal: stats.totalBalance).stringValue
        }

        func toWardrobeStats(lookupClothing: (UUID) -> Clothing?) -> WardrobeStats {
            WardrobeStats(
                totalCount: totalCount,
                totalValue: Decimal(string: totalValue) ?? 0,
                mostExpensiveItem: mostExpensiveItemID.flatMap(lookupClothing),
                depositPlanCount: depositPlanCount,
                totalDeposit: Decimal(string: totalDeposit) ?? 0,
                totalBalance: Decimal(string: totalBalance) ?? 0
            )
        }
    }

    /// 持久化的穿搭建议数据（用 UUID 列表替代 [Clothing]）
    private struct PersistedOutfitSuggestionData: Codable {
        let clothingIDs: [UUID]
        let description: String
        let style: String
        let occasion: String

        init(from data: OutfitSuggestionData) {
            self.clothingIDs = data.clothings.map(\.id)
            self.description = data.description
            self.style = data.style
            self.occasion = data.occasion
        }

        func toOutfitSuggestionData(lookupClothing: (UUID) -> Clothing?) -> OutfitSuggestionData {
            let resolvedClothings = clothingIDs.compactMap(lookupClothing)
            return OutfitSuggestionData(
                clothings: resolvedClothings,
                description: description,
                style: style,
                occasion: occasion,
                layoutInfos: nil
            )
        }
    }

    private static func loadStoredMessages(enrichingWith lookupClothing: (UUID) -> Clothing?) -> [PetChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PersistedPetChatMessage].self, from: data),
              !decoded.isEmpty else {
            return []
        }
        return decoded.map { $0.message(lookupClothing: lookupClothing) }
    }

    private static func migrateLegacyHistoryIfNeeded(existingMessages: [PetChatMessage], clothings: [Clothing]) -> [PetChatMessage] {
        let legacyMessages = loadLegacyMessages()
        guard !legacyMessages.isEmpty else { return existingMessages }

        let mergedMessages = mergeMessages(existingMessages, with: legacyMessages)
        let hasImportedLegacy = UserDefaults.standard.bool(forKey: legacyImportFlagKey)

        if !hasImportedLegacy || mergedMessages.count != existingMessages.count {
            save(messages: mergedMessages)
            UserDefaults.standard.set(true, forKey: legacyImportFlagKey)
        }

        return mergedMessages
    }

    private static func loadLegacyMessages() -> [PetChatMessage] {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyURL = documents.appendingPathComponent("chat_history.json")

        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL),
              let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data),
              !decoded.isEmpty else {
            return []
        }

        return decoded.map { legacyMessage in
            let sanitizedUserText = sanitizeUserText(legacyMessage.text)
            return PetChatMessage(
                text: legacyMessage.isUser ? sanitizedUserText : sanitizeAssistantText(legacyMessage.text),
                isUser: legacyMessage.isUser,
                isUserAuthored: legacyMessage.isUser && isLikelyManualUserText(sanitizedUserText),
                imageName: legacyMessage.imageName,
                isAIGenerated: !legacyMessage.isUser,
                timestamp: legacyMessage.timestamp
            )
        }
    }

    private static func mergeMessages(_ currentMessages: [PetChatMessage], with legacyMessages: [PetChatMessage]) -> [PetChatMessage] {
        var seen = Set<PersistedMessageKey>()
        let sortedMessages = (currentMessages + legacyMessages).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                if lhs.isUser != rhs.isUser {
                    return lhs.isUser && !rhs.isUser
                }
                return lhs.text < rhs.text
            }
            return lhs.timestamp < rhs.timestamp
        }

        let merged = sortedMessages.filter { message in
            seen.insert(PersistedMessageKey(message: message)).inserted
        }

        return normalizedPersistedMessages(from: merged)
    }

    private static func normalizedPersistedMessages(from messages: [PetChatMessage]) -> [PetChatMessage] {
        let maxPersistedMessages = historyWindowSize()
        if messages.count > maxPersistedMessages {
            return Array(messages.suffix(maxPersistedMessages))
        }
        return messages
    }

    private static func encodeType(_ type: PetChatMessageType) -> String {
        switch type {
        case .text: return "text"
        case .wardrobeCard: return "wardrobeCard"
        case .statistics: return "statistics"
        case .colorMatch: return "colorMatch"
        case .searchResults: return "searchResults"
        case .thinking: return "thinking"
        case .outfitSuggestion: return "outfitSuggestion"
        }
    }

    private static func decodeType(_ raw: String) -> PetChatMessageType {
        switch raw {
        case "text": return .text
        case "wardrobeCard": return .wardrobeCard
        case "statistics": return .statistics
        case "colorMatch": return .colorMatch
        case "searchResults": return .searchResults
        case "thinking": return .thinking
        case "outfitSuggestion": return .outfitSuggestion
        default: return .text
        }
    }

    private struct PersistedPetChatMessage: Codable {
        let text: String
        let isUser: Bool
        let isUserAuthored: Bool
        let speakerPetID: String?
        let timestamp: Date
        let imageName: String?
        let isAIGenerated: Bool
        let typeRaw: String
        let widgets: [PetWidgetData]?

        // 新增：结构化内容持久化（用 UUID 替代 Clothing 对象）
        let clothingID: UUID?
        let searchResultIDs: [UUID]?
        let persistedStats: PersistedWardrobeStats?
        let colorRecommendation: ColorRecommendation?
        let persistedOutfit: PersistedOutfitSuggestionData?

        private enum CodingKeys: String, CodingKey {
            case text
            case isUser
            case isUserAuthored
            case speakerPetID
            case timestamp
            case imageName
            case isAIGenerated
            case typeRaw
            case widgets
            case clothingID
            case searchResultIDs
            case persistedStats
            case colorRecommendation
            case persistedOutfit
        }

        init(message: PetChatMessage) {
            self.text = message.isUser ? sanitizeUserText(message.text) : sanitizeAssistantText(message.text)
            self.isUser = message.isUser
            self.isUserAuthored = message.isUserAuthored
            self.speakerPetID = message.speakerPetID
            self.timestamp = message.timestamp
            self.imageName = message.imageName
            self.isAIGenerated = message.isAIGenerated
            self.typeRaw = PetChatTranscriptStore.encodeType(message.type)
            self.widgets = message.widgets

            // 保存结构化数据
            self.clothingID = message.clothing?.id
            self.searchResultIDs = message.searchResults?.map(\.id)
            self.persistedStats = message.statistics.map(PersistedWardrobeStats.init)
            self.colorRecommendation = message.colorRecommendation
            self.persistedOutfit = message.outfitSuggestion.map(PersistedOutfitSuggestionData.init)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            isUser = try container.decode(Bool.self, forKey: .isUser)
            let fallbackAuthored = isUser && PetChatTranscriptStore.isLikelyManualUserText(text)
            isUserAuthored = try container.decodeIfPresent(Bool.self, forKey: .isUserAuthored) ?? fallbackAuthored
            imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
            speakerPetID = try container.decodeIfPresent(String.self, forKey: .speakerPetID)
                ?? (isUser ? nil : PetChatMessage.inferSpeakerPetID(from: text, imageName: imageName))
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            isAIGenerated = try container.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? !isUser
            typeRaw = try container.decodeIfPresent(String.self, forKey: .typeRaw) ?? "text"
            widgets = try container.decodeIfPresent([PetWidgetData].self, forKey: .widgets)
            clothingID = try container.decodeIfPresent(UUID.self, forKey: .clothingID)
            searchResultIDs = try container.decodeIfPresent([UUID].self, forKey: .searchResultIDs)
            persistedStats = try container.decodeIfPresent(PersistedWardrobeStats.self, forKey: .persistedStats)
            colorRecommendation = try container.decodeIfPresent(ColorRecommendation.self, forKey: .colorRecommendation)
            persistedOutfit = try container.decodeIfPresent(PersistedOutfitSuggestionData.self, forKey: .persistedOutfit)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encode(isUser, forKey: .isUser)
            try container.encode(isUserAuthored, forKey: .isUserAuthored)
            try container.encodeIfPresent(speakerPetID, forKey: .speakerPetID)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encodeIfPresent(imageName, forKey: .imageName)
            try container.encode(isAIGenerated, forKey: .isAIGenerated)
            try container.encode(typeRaw, forKey: .typeRaw)
            try container.encodeIfPresent(widgets, forKey: .widgets)
            try container.encodeIfPresent(clothingID, forKey: .clothingID)
            try container.encodeIfPresent(searchResultIDs, forKey: .searchResultIDs)
            try container.encodeIfPresent(persistedStats, forKey: .persistedStats)
            try container.encodeIfPresent(colorRecommendation, forKey: .colorRecommendation)
            try container.encodeIfPresent(persistedOutfit, forKey: .persistedOutfit)
        }

        func message(lookupClothing: (UUID) -> Clothing?) -> PetChatMessage {
            let displayText = isUser ? PetChatTranscriptStore.sanitizeUserText(text) : PetChatTranscriptStore.sanitizeAssistantText(text)
            return PetChatMessage(
                text: displayText,
                isUser: isUser,
                type: PetChatTranscriptStore.decodeType(typeRaw),
                isUserAuthored: isUserAuthored,
                speakerPetID: speakerPetID,
                clothing: clothingID.flatMap(lookupClothing),
                searchResults: searchResultIDs?.compactMap(lookupClothing),
                statistics: persistedStats?.toWardrobeStats(lookupClothing: lookupClothing),
                colorRecommendation: colorRecommendation,
                imageName: imageName,
                isAIGenerated: isAIGenerated,
                timestamp: timestamp,
                outfitSuggestion: persistedOutfit?.toOutfitSuggestionData(lookupClothing: lookupClothing),
                widgets: widgets
            )
        }
    }

    private static func isReusableUserMessage(_ message: PetChatMessage) -> Bool {
        guard message.isUser, message.isUserAuthored else { return false }
        let trimmed = sanitizeUserText(message.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 历史列表只展示自然语言，避免 JSON 透出到用户界面。
        if isJSONLikeContent(trimmed) {
            return false
        }
        if PetGenerativePromptBuilder.containsInternalPromptLeak(trimmed) {
            return false
        }
        if !isLikelyManualUserText(trimmed) {
            return false
        }
        return true
    }

    /// 检测内容是否为JSON格式或类似代码的内容
    private static func isJSONLikeContent(_ text: String) -> Bool {
        // 基本JSON结构检测
        if (text.hasPrefix("{") && text.hasSuffix("}")) ||
            (text.hasPrefix("[") && text.hasSuffix("]")) {
            return true
        }

        // 检测常见JSON关键字和模式
        let jsonIndicators = [
            "\"name\":", "\"type\":", "\"id\":", "\"value\":",
            "\"content\":", "\"message\":", "\"data\":", "\"result\":",
            "\"status\":", "\"code\":", "\"error\":",
            "function_call", "tool_call", "\"role\":", "\"system\"",
            "\"user\":", "\"assistant\":", "\"model\":"
        ]

        let lowercased = text.lowercased()
        var jsonIndicatorCount = 0
        for indicator in jsonIndicators {
            if lowercased.contains(indicator) {
                jsonIndicatorCount += 1
                // 如果包含多个JSON关键字，大概率是JSON
                if jsonIndicatorCount >= 2 {
                    return true
                }
            }
        }

        // 检测嵌套大括号或中括号（可能是复杂JSON）
        let openBraces = text.filter { $0 == "{" }.count
        let closeBraces = text.filter { $0 == "}" }.count
        let openBrackets = text.filter { $0 == "[" }.count
        let closeBrackets = text.filter { $0 == "]" }.count

        // 如果包含成对的JSON括号，且内容较长，认为是JSON
        if (openBraces > 0 && openBraces == closeBraces) ||
            (openBrackets > 0 && openBrackets == closeBrackets) {
            // 如果包含冒号后跟引号的模式（JSON键值对特征）
            if text.contains("\":\"") || text.contains("\": ") {
                return true
            }
        }

        return false
    }

    private static func isLikelyManualUserText(_ text: String) -> Bool {
        let trimmed = sanitizeUserText(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if PetGenerativePromptBuilder.containsInternalPromptLeak(trimmed) {
            return false
        }
        let blockedCommands: Set<String> = [
            "今日打卡", "去打卡", "签到", "数钞票", "来财", "喂食",
            "智能搭配", "快速搭配", "甜美约会", "优雅茶会", "日常出门",
            "统计裙子", "查看萌宠状态", "切换萌宠", "改名",
            "看看我的背包", "带我逛逛商店", "查看天气穿搭",
            "尾款提醒", WealthExperienceCopy.PetChat.quickMoneyLabel, WealthExperienceCopy.PetChat.quickFortuneLabel, "今日心愿提醒",
            "查找衣柜", "历史消息查询", "帮我搭配一套"
        ]
        return !blockedCommands.contains(trimmed)
    }

    private static func sanitizeUserText(_ text: String) -> String {
        PetGenerativePromptBuilder.recoverUserFacingText(from: text)
    }

    private static func sanitizeAssistantText(_ text: String) -> String {
        // 用户可见内容必须去掉 JSON/代码感。
        var cleaned = PetGenerativePromptBuilder.sanitizeMessageText(text)
        let humanized = PetResponseHumanizer.humanize(cleaned)
        let result = humanized.isEmpty ? cleaned : humanized
        return PetGenerativePromptBuilder.sanitizeMessageText(result)
    }

    private struct PersistedMessageKey: Hashable {
        let text: String
        let isUser: Bool
        let speakerPetID: String?
        let timestampBucket: Int64

        init(message: PetChatMessage) {
            self.text = message.isUser ? PetChatTranscriptStore.sanitizeUserText(message.text) : PetChatTranscriptStore.sanitizeAssistantText(message.text)
            self.isUser = message.isUser
            self.speakerPetID = message.speakerPetID
            self.timestampBucket = Int64(message.timestamp.timeIntervalSince1970.rounded())
        }
    }
}
