import Foundation

enum PetChatTranscriptStore {
    private static let storageKey = "pet_chat_transcript_v3"
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

    static func load() -> [PetChatMessage] {
        let storedMessages = loadStoredMessages()
        let migratedMessages = migrateLegacyHistoryIfNeeded(existingMessages: storedMessages)
        return normalizedPersistedMessages(from: migratedMessages)
    }

    static func query(
        keyword: String? = nil,
        page: Int = 0,
        pageSize: Int = 20,
        onlyUserMessages: Bool = true
    ) -> [PetChatMessage] {
        let all = load()
        let base = onlyUserMessages ? all.filter(isReusableUserMessage) : all
        let trimmedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filtered: [PetChatMessage]
        if trimmedKeyword.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { message in
                message.text.localizedCaseInsensitiveContains(trimmedKeyword)
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

    static func count(onlyUserMessages: Bool = true) -> Int {
        if onlyUserMessages {
            return load().filter(isReusableUserMessage).count
        }
        return load().count
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: legacyImportFlagKey)
    }

    private static func loadStoredMessages() -> [PetChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PersistedPetChatMessage].self, from: data),
              !decoded.isEmpty else {
            return []
        }
        return decoded.map(\.message)
    }

    private static func migrateLegacyHistoryIfNeeded(existingMessages: [PetChatMessage]) -> [PetChatMessage] {
        let legacyMessages = loadLegacyMessages()
        guard !legacyMessages.isEmpty else { return existingMessages }

        let mergedMessages = mergeMessages(existingMessages, with: legacyMessages)
        let hasImportedLegacy = UserDefaults.standard.bool(forKey: legacyImportFlagKey)

        if !hasImportedLegacy || mergedMessages.count != existingMessages.count {
            let payload = normalizedPersistedMessages(from: mergedMessages).map(PersistedPetChatMessage.init)
            if let data = try? JSONEncoder().encode(Array(payload)) {
                UserDefaults.standard.set(data, forKey: storageKey)
                UserDefaults.standard.set(true, forKey: legacyImportFlagKey)
            }
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
            PetChatMessage(
                text: legacyMessage.isUser ? legacyMessage.text : sanitizeAssistantText(legacyMessage.text),
                isUser: legacyMessage.isUser,
                isUserAuthored: legacyMessage.isUser,
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
        let timestamp: Date
        let imageName: String?
        let isAIGenerated: Bool
        let typeRaw: String
        let widgets: [PetWidgetData]?

        private enum CodingKeys: String, CodingKey {
            case text
            case isUser
            case isUserAuthored
            case timestamp
            case imageName
            case isAIGenerated
            case typeRaw
            case widgets
        }

        init(message: PetChatMessage) {
            self.text = message.isUser ? message.text : sanitizeAssistantText(message.text)
            self.isUser = message.isUser
            self.isUserAuthored = message.isUserAuthored
            self.timestamp = message.timestamp
            self.imageName = message.imageName
            self.isAIGenerated = message.isAIGenerated
            self.typeRaw = PetChatTranscriptStore.encodeType(message.type)
            self.widgets = message.widgets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            isUser = try container.decode(Bool.self, forKey: .isUser)
            let fallbackAuthored = isUser && PetChatTranscriptStore.isLikelyManualUserText(text)
            isUserAuthored = try container.decodeIfPresent(Bool.self, forKey: .isUserAuthored) ?? fallbackAuthored
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
            isAIGenerated = try container.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? !isUser
            typeRaw = try container.decodeIfPresent(String.self, forKey: .typeRaw) ?? "text"
            widgets = try container.decodeIfPresent([PetWidgetData].self, forKey: .widgets)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encode(isUser, forKey: .isUser)
            try container.encode(isUserAuthored, forKey: .isUserAuthored)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encodeIfPresent(imageName, forKey: .imageName)
            try container.encode(isAIGenerated, forKey: .isAIGenerated)
            try container.encode(typeRaw, forKey: .typeRaw)
            try container.encodeIfPresent(widgets, forKey: .widgets)
        }

        var message: PetChatMessage {
            let displayText = isUser ? text : PetChatTranscriptStore.sanitizeAssistantText(text)
            return PetChatMessage(
                text: displayText,
                isUser: isUser,
                type: PetChatTranscriptStore.decodeType(typeRaw),
                isUserAuthored: isUserAuthored,
                imageName: imageName,
                isAIGenerated: isAIGenerated,
                timestamp: timestamp,
                widgets: widgets
            )
        }
    }

    private static func isReusableUserMessage(_ message: PetChatMessage) -> Bool {
        guard message.isUser, message.isUserAuthored else { return false }
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // 历史列表只展示自然语言，避免 JSON 透出到用户界面。
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return false
        }
        if !isLikelyManualUserText(trimmed) {
            return false
        }
        return true
    }

    private static func isLikelyManualUserText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let blockedCommands: Set<String> = [
            "今日打卡", "去打卡", "签到", "数钞票", "来财", "喂食"
        ]
        return !blockedCommands.contains(trimmed)
    }

    private static func sanitizeAssistantText(_ text: String) -> String {
        // 用户可见内容必须去掉 JSON/代码感。
        let humanized = PetResponseHumanizer.humanize(text)
        return humanized.isEmpty ? text : humanized
    }

    private struct PersistedMessageKey: Hashable {
        let text: String
        let isUser: Bool
        let timestampBucket: Int64

        init(message: PetChatMessage) {
            self.text = message.text
            self.isUser = message.isUser
            self.timestampBucket = Int64(message.timestamp.timeIntervalSince1970.rounded())
        }
    }
}
