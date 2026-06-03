import Foundation
import Combine
import os.lock
import UIKit

// AI Provider Enum
enum AIProvider {
    case deepSeek
    case minimax
}

// Minimax API Request/Response Structures (Anthropic Compatible)
struct MinimaxMessage: Codable {
    let role: String
    let content: String
}

struct MinimaxRequest: Codable {
    let model: String
    let messages: [MinimaxMessage]
    let max_tokens: Int
    let stream: Bool
    let system: String?
}

struct MinimaxResponse: Codable {
    let content: [MinimaxContentBlock]
}

struct MinimaxContentBlock: Codable {
    let type: String
    let text: String?
    let thinking: String?
}

// DeepSeek API Request/Response Structures
struct DSMessage: Codable {
    let role: String
    let content: String
}

struct DSRequest: Codable {
    let model: String
    let messages: [DSMessage]
    let stream: Bool
}

struct DSResponse: Codable {
    let choices: [DSChoice]
}

struct DSChoice: Codable {
    let message: DSMessage
}

// 定义超时错误
struct TimeoutError: Error {}

@MainActor
class PetAIService: ObservableObject {
    static let shared = PetAIService()
    
    @Published var isProcessing: Bool = false
    @Published var uiMessages: [ChatMessage] = [] // UI 展示用的消息历史 (分页加载)
    private var allMessages: [ChatMessage] = [] // 完整的本地聊天记录
    
    private var role: PetRole = .kitten
    @Published public private(set) var petName: String = "奶茶"
    private var apiKey: String = ""
    private var provider: AIProvider = .deepSeek
    
    // 公共属性：检查 API Key 是否可用
    var isAPIKeyAvailable: Bool {
        return !apiKey.isEmpty
    }
    
    // Maintain simple history for API context
    private var history: [DSMessage] = []
    
    // 用于取消 AI 请求的任务
    private var currentTask: Task<Void, Never>?
    
    // 停止生成标志
    private var shouldStopGeneration = false
    
    // 小内存设备优化：低内存保留10条，中档18条，高内存35条
    private var latestWindowSize: Int {
        let memoryInGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        if memoryInGB >= 6 { return 35 }
        if memoryInGB >= 4 { return 18 }
        return 10
    }
    private let historyPageSize = 10
    private var maxPersistedMessages: Int { latestWindowSize }
    private var isHistoryExpanded = false

    private var personaProfile: PetPersonaProfile {
        PetPersonaRegistry.profile(for: role, petName: petName)
    }

    private init() {
        // Initialize with placeholder history
        self.history = Self.makeInitialHistory()
        self.loadMessages()
    }

    private static func makeInitialHistory() -> [DSMessage] {
        [
            DSMessage(role: "system", content: ""),
            DSMessage(role: "user", content: "你好，我是你的主人。"),
            DSMessage(role: "assistant", content: "（蹭蹭你的手）主人好呀！[IMAGE:happy_cat]")
        ]
    }
    
    // MARK: - Persistence
    
    private var messagesFileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("chat_history.json")
    }
    
    private var isHistoryLoaded = false // 标记历史记录是否成功加载，防止覆盖旧数据

    private func saveMessages() {
        // 如果历史记录从未成功加载，且文件存在（说明解析失败），则不要覆盖，以免丢失数据
        if !isHistoryLoaded && FileManager.default.fileExists(atPath: messagesFileURL.path) {
            print("⚠️ [PetAIService] History load failed previously. Skipping save to prevent data loss.")
            return
        }
        
        do {
            trimPersistedMessagesIfNeeded()
            let sanitizedMessages = allMessages.map(Self.sanitizePersistedMessage)
            syncSanitizedMessages(sanitizedMessages)
            let data = try JSONEncoder().encode(sanitizedMessages)
            try data.write(to: messagesFileURL)
        } catch {
            print("Failed to save chat history: \(error)")
        }
    }
    
    // Public reload for restore
    func reloadHistory() {
        self.isHistoryLoaded = false
        self.loadMessages()
    }

    func clearPersistedHistory() {
        currentTask?.cancel()
        shouldStopGeneration = false
        isProcessing = false
        allMessages = []
        uiMessages = []
        isHistoryExpanded = false
        isHistoryLoaded = true
        history = Self.makeInitialHistory()

        do {
            if FileManager.default.fileExists(atPath: messagesFileURL.path) {
                try FileManager.default.removeItem(at: messagesFileURL)
            }
        } catch {
            print("❌ [PetAIService] Failed to clear chat history file: \(error)")
        }

        let corruptedURL = messagesFileURL.deletingPathExtension().appendingPathExtension("corrupted.json")
        if FileManager.default.fileExists(atPath: corruptedURL.path) {
            try? FileManager.default.removeItem(at: corruptedURL)
        }
    }
    
    private func loadMessages() {
        guard FileManager.default.fileExists(atPath: messagesFileURL.path) else {
            isHistoryLoaded = true // 文件不存在，视为新用户，允许保存
            return
        }
        
        do {
            let data = try Data(contentsOf: messagesFileURL)
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
                .map(Self.sanitizePersistedMessage)
            if messages.count > maxPersistedMessages {
                self.allMessages = Array(messages.suffix(maxPersistedMessages))
            } else {
                self.allMessages = messages
            }
            loadLatestMessagesToUI()
            
            isHistoryLoaded = true
            print("✅ [PetAIService] Successfully loaded \(allMessages.count) messages.")
        } catch {
            print("❌ [PetAIService] Failed to load chat history: \(error)")
            
            // 尝试备份损坏的数据，以便后续分析
            let backupURL = messagesFileURL.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.copyItem(at: messagesFileURL, to: backupURL)
            print("⚠️ [PetAIService] Corrupted data backed up to: \(backupURL.lastPathComponent)")
            
            // 在这里我们可以选择：
            // 1. 依然设为 true，允许用户重新开始（旧数据已备份）
            // 2. 保持 false，禁止保存（保护旧文件，但用户无法使用聊天功能）
            // 考虑到已备份，设为 true 让用户能继续使用可能更好，但为了安全起见，我们先保持 false 并让用户知道。
            // 或者，我们可以尝试用更宽松的方式解析？
            
            // 临时策略：不标记为 loaded，防止 saveMessages 覆盖原文件。
            // 但这样会导致新消息无法保存。
            // 改进策略：既然已经备份了，那就允许重置。
            isHistoryLoaded = true 
        }
    }
    
    // 加载更多历史记录 (分页)
    @discardableResult
    func loadMoreHistory(pageSize: Int? = nil) -> Int {
        isHistoryExpanded = true
        let perPage = max(1, pageSize ?? historyPageSize)
        let currentCount = uiMessages.count
        let totalCount = allMessages.count
        
        guard currentCount < totalCount else { return 0 }
        
        let remaining = totalCount - currentCount
        let loadCount = min(perPage, remaining)
        
        let endIndex = totalCount - currentCount
        let startIndex = endIndex - loadCount
        
        let newMessages = Array(allMessages[startIndex..<endIndex])
        
        // 插入到开头
        self.uiMessages.insert(contentsOf: newMessages, at: 0)
        return loadCount
    }

    // 进入分页历史模式（仅加载最新若干条，后续上滑再分页补齐）
    func activatePagedHistoryMode(initialVisibleCount: Int = 10) {
        isHistoryExpanded = true
        let count = allMessages.count
        guard count > 0 else {
            uiMessages = []
            return
        }
        let visibleCount = min(max(1, initialVisibleCount), count)
        let startIndex = count - visibleCount
        uiMessages = Array(allMessages[startIndex..<count])
    }
    
    var hasMoreHistoryToLoad: Bool {
        uiMessages.count < allMessages.count
    }
    
    // 重置 UI 显示为最新窗口（默认 30 条，用于退出页面时释放内存）
    func resetToLatest() {
        loadLatestMessagesToUI()
    }

    // 持久化历史查询（支持分页和关键词）
    func queryPersistedHistory(
        keyword: String? = nil,
        page: Int = 0,
        pageSize: Int = 20,
        onlyUserMessages: Bool = false
    ) -> [ChatMessage] {
        let normalizedPage = max(0, page)
        let normalizedSize = max(1, min(pageSize, 50))
        let baseMessages = onlyUserMessages ? allMessages.filter(\.isUser) : allMessages
        let filtered: [ChatMessage]
        
        if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = baseMessages.filter {
                $0.text.localizedCaseInsensitiveContains(keyword) ||
                ($0.rawText?.localizedCaseInsensitiveContains(keyword) ?? false)
            }
        } else {
            filtered = baseMessages
        }
        
        let newestFirst = Array(filtered.reversed())
        let start = normalizedPage * normalizedSize
        guard start < newestFirst.count else { return [] }
        let end = min(newestFirst.count, start + normalizedSize)
        return Array(newestFirst[start..<end])
    }
    
    func persistedHistoryCount(onlyUserMessages: Bool = false) -> Int {
        if onlyUserMessages {
            return allMessages.filter(\.isUser).count
        }
        return allMessages.count
    }
    
    private func loadLatestMessagesToUI() {
        isHistoryExpanded = false
        let count = allMessages.count
        guard count > 0 else {
            uiMessages = []
            return
        }
        let loadCount = min(count, latestWindowSize)
        let startIndex = count - loadCount
        uiMessages = Array(allMessages[startIndex..<count])
    }
    
    private func appendToHistory(_ message: ChatMessage, appendToUI: Bool = true) {
        let sanitizedMessage = Self.sanitizePersistedMessage(message)
        allMessages.append(sanitizedMessage)
        if appendToUI {
            uiMessages.append(sanitizedMessage)
            // 默认窗口模式下限制 30 条，避免常驻内存增长
            if !isHistoryExpanded, uiMessages.count > latestWindowSize {
                uiMessages.removeFirst(uiMessages.count - latestWindowSize)
            }
        }
    }
    
    private func trimPersistedMessagesIfNeeded() {
        guard allMessages.count > maxPersistedMessages else { return }
        let removeCount = allMessages.count - maxPersistedMessages
        allMessages.removeFirst(removeCount)
        let validIDs = Set(allMessages.map(\.id))
        uiMessages = uiMessages.filter { validIDs.contains($0.id) }
        if !isHistoryExpanded, uiMessages.count > latestWindowSize {
            uiMessages.removeFirst(uiMessages.count - latestWindowSize)
        }
    }

    private func syncSanitizedMessages(_ sanitizedMessages: [ChatMessage]) {
        allMessages = sanitizedMessages
        let sanitizedByID = Dictionary(uniqueKeysWithValues: sanitizedMessages.map { ($0.id, $0) })
        uiMessages = uiMessages.compactMap { sanitizedByID[$0.id] }
    }

    private static func sanitizePersistedMessage(_ message: ChatMessage) -> ChatMessage {
        let sanitizedText: String
        
        if message.isUser {
            sanitizedText = PetGenerativePromptBuilder.recoverUserFacingText(from: message.text)
        } else {
            sanitizedText = PetGenerativePromptBuilder.sanitizeMessageText(message.text)
        }
        
        guard sanitizedText != message.text else { return message }

        return ChatMessage(
            id: message.id,
            text: sanitizedText,
            rawText: message.rawText,
            imageName: message.imageName,
            imagePath: message.imagePath,
            isUser: message.isUser,
            timestamp: message.timestamp
        )
    }
    
    private func saveImageToDisk(image: UIImage) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent(fileName)
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            do {
                try data.write(to: fileURL)
                return fileName
            } catch {
                print("Error saving image: \(error)")
                return nil
            }
        }
        return nil
    }
    
    func updateConfiguration(role: PetRole, petName: String, apiKey: String, provider: AIProvider = .deepSeek, wardrobeContext: String) {
        self.role = role
        self.petName = petName
        
        // 清洗 API Key (移除可能的 Bearer 前缀和空白)
        var cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.lowercased().hasPrefix("bearer ") {
            cleanKey = String(cleanKey.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.apiKey = cleanKey
        
        self.provider = provider
        self.updateSystemContext(wardrobeContext: wardrobeContext)
        
        print("🔧 [PetAIService] Config Updated - Provider: \(provider), Role: \(role), KeyLen: \(cleanKey.count)")
        if !cleanKey.isEmpty {
            print("🔑 [PetAIService] Key Prefix: \(cleanKey.prefix(4))...")
        } else {
            print("⚠️ [PetAIService] Warning: API Key is empty!")
        }
    }
    
    // 动态更新上下文 (例如衣橱数据变化或识别了新图片)
    func updateSystemContext(wardrobeContext: String) {
        let persona = personaProfile
        let fullPrompt = """
        你是\(persona.displayName)（\(persona.species)）。
        角色风格：\(persona.stylePrompt)
        禁止词：\(persona.forbiddenWords.joined(separator: "、"))

        你不仅是宠物，也是主人的衣橱管家。
        当问题与衣橱有关时，仅基于给定数据回答，不编造。
        请保持口语化、拟人化、自然，不要机械重复。

        当前衣橱摘要：
        \(wardrobeContext)
        """
        
        // 更新历史中的第一条 (System Prompt)
        if !self.history.isEmpty {
            self.history[0] = DSMessage(role: "system", content: fullPrompt)
        }
    }
    
    // 确保已配置 (用于在关键操作前进行防御性检查)
    func ensureConfiguration(role: PetRole, petName: String, wardrobeContext: String) {
        if self.apiKey.isEmpty {
            print("⚠️ [PetAIService] API Key is empty. Attempting to reload from AIConfigManager...")
            AIConfigManager.shared.reloadConfig()
            
            // 读取用户设置的优先级
            let priorityString = UserDefaults.standard.string(forKey: "textModelPriority") ?? "DeepSeek,Minimax"
            let priorityList = priorityString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            
            for model in priorityList {
                switch model {
                case "DeepSeek":
                    if let key = AIConfigManager.shared.dsApiKey, !key.isEmpty {
                        self.updateConfiguration(role: role, petName: petName, apiKey: key, provider: .deepSeek, wardrobeContext: wardrobeContext)
                        return
                    }
                case "Minimax":
                    if let key = AIConfigManager.shared.minimaxApiKey, !key.isEmpty {
                        self.updateConfiguration(role: role, petName: petName, apiKey: key, provider: .minimax, wardrobeContext: wardrobeContext)
                        return
                    }
                default: break
                }
            }
        }
    }
    
    func sendImageAnalysisRequest(text: String, imageContext: String, image: UIImage? = nil) async -> ChatMessage {
        // 防御性检查：确保配置已加载
        // 由于 PetAIService 是单例，我们可能丢失了当前的 role/petName 上下文
        // 但我们可以使用当前的 self.role 和 self.petName (如果不为空)
        // 或者使用默认值
        if self.apiKey.isEmpty {
             print("⚠️ [PetAIService] sendImageAnalysisRequest: Key is empty, trying to reload...")
             self.ensureConfiguration(role: self.role, petName: self.petName, wardrobeContext: "")
        }
        
        var imagePath: String?
        if let image = image {
            imagePath = saveImageToDisk(image: image)
        }
        
        // 将图片识别结果作为临时上下文插入，或者直接作为用户消息的一部分
        // 强制强调角色设定和字数限制
        // 使用 role 特定的提醒
        let reminder = role.visionAnalysisReminder
        
        let messageWithContext = """
        \(imageContext)
        
        用户问题：\(text)
        
        \(reminder)
        """
        // Pass 'text' as displayText so the UI shows the clean question, not the prompt dump
        return await sendMessage(messageWithContext, userImagePath: imagePath, displayText: text)
    }

    // MARK: - 停止生成
    func stopGeneration() {
        shouldStopGeneration = true
        currentTask?.cancel()
        isProcessing = false
        print("🛑 [PetAIService] 用户停止生成")
    }
    
    func sendMessage(
        _ text: String,
        userImagePath: String? = nil,
        displayText: String? = nil,
        enableVoice: Bool = true,
        responseMode: AIResponseMode = .humanized
    ) async -> ChatMessage {
        print("🐾 [PetAIService] sendMessage length=\(text.count)")
        let historyUserText = PetGenerativePromptBuilder.recoverUserFacingText(from: displayText ?? text)
        if let displayText,
           !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           displayText != "..." {
            let module = PetChatIntentRouter.detect(from: displayText).module
            PetConversationMemoryStore.shared.recordUserSignal(
                query: displayText,
                role: role,
                module: module
            )
        }
        
        // 重置停止标志
        shouldStopGeneration = false
        
        // 1. 记录用户消息 (Use displayText if available, otherwise raw text)
        let userMsg = ChatMessage(text: historyUserText, imagePath: userImagePath, isUser: true)
        appendToHistory(userMsg)
        self.saveMessages()
        
        self.isProcessing = true
        defer { 
            if !shouldStopGeneration {
                self.isProcessing = false 
            }
        }
        
        // 捕获必要的上下文以传递给后台任务
        let currentHistory = self.history
        let apiKey = self.apiKey
        let provider = self.provider
        let historyLimit = historyMessageLimit(forPromptLength: text.count)
        let fallbackCharacter: PetCharacter = role == .goldenRetriever ? .maomao : .naicha
        let fallbackUnknownReply = fallbackCharacter.localizedCatchphraseText("（歪头摇尾巴，不知道你在说什么喵...）")
        
        print("🔍 [PetAIService] 发送请求 - Provider: \(provider)")
        if apiKey.isEmpty {
            print("❌ [PetAIService] Error: API Key is empty! Cannot send request.")
            let errorMsg = ChatMessage(
                text: personaProfile.keyMissingReply,
                imageName: defaultErrorImageName(),
                isUser: false
            )
            appendToHistory(errorMsg)
            self.saveMessages()
            return errorMsg
        }
        print("🔑 [PetAIService] API Key ready")
        
        do {
            // ... (TaskGroup logic)
            // 使用 TaskGroup 实现并发和超时控制，避免 unsafeForcedSync
            let replyContent = try await withThrowingTaskGroup(of: String.self) { group in
                // 1. 网络请求任务
                group.addTask {
                    if provider == .minimax {
                        // Minimax (Anthropic Compatible)
                        print("🚀 [PetAIService] Using Minimax (Anthropic) Provider")
                        // 确保 URL 正确，Minimax 的 Anthropic 兼容接口需要严格匹配
                        let url = URL(string: "https://api.minimaxi.com/anthropic/v1/messages")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
                        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") // 同时添加 Bearer 头作为兼容
                        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                        
                        // Extract system prompt
                        let systemPrompt = currentHistory.first { $0.role == "system" }?.content
                        
                        // Filter history (exclude system) and map to MinimaxMessage
                        // DeepSeek history uses "assistant", Anthropic uses "assistant" too.
                        var messagesToSend = currentHistory
                            .filter { $0.role != "system" }
                            .suffix(historyLimit)
                            .map { MinimaxMessage(role: $0.role, content: $0.content) }
                        
                        messagesToSend.append(MinimaxMessage(role: "user", content: text))
                        
                        let body = MinimaxRequest(
                            model: "MiniMax-M2.5",
                            messages: messagesToSend,
                            max_tokens: 1000,
                            stream: false,
                            system: systemPrompt // Optional
                        )
                        
                        let bodyData = try JSONEncoder().encode(body)
                        print("📡 [PetAIService] Minimax payload bytes: \(bodyData.count)")
                        request.httpBody = bodyData
                        
                        let (data, response) = try await URLSession.shared.data(for: request)
                        
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                            print("❌ [PetAIService] Minimax Error: \(errorMsg)")
                            throw NSError(domain: "MinimaxError", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                        }
                        
                        // print("Minimax Response: \(String(data: data, encoding: .utf8) ?? "")") // Debug log
                        
                        let mmResponse = try JSONDecoder().decode(MinimaxResponse.self, from: data)
                        // Prefer text content
                        let textBlock = mmResponse.content.first { $0.type == "text" }
                        return textBlock?.text ?? fallbackUnknownReply
                        
                    } else if provider == .deepSeek {
                        // DeepSeek Logic
                        print("🚀 [PetAIService] Using DeepSeek Provider")
                        // 构造请求
                        // ...
                        var historyToSend = currentHistory
                        historyToSend.append(DSMessage(role: "user", content: text))
                        
                        let url = URL(string: "https://api.deepseek.com/chat/completions")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                        
                        // 只发送最近的 N 条历史
                        let messagesToSend = [historyToSend.first!] + historyToSend.suffix(historyLimit)
                        
                        let body = DSRequest(model: "deepseek-chat", messages: messagesToSend, stream: false)
                        let bodyData = try JSONEncoder().encode(body)
                        print("📡 [PetAIService] DeepSeek payload bytes: \(bodyData.count)")
                        request.httpBody = bodyData
                        
                        // 发送请求
                        let (data, response) = try await URLSession.shared.data(for: request)
                        
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                            print("❌ [PetAIService] DeepSeek Error: \(errorMsg)")
                            throw NSError(domain: "DeepSeekError", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                        }
                        
                        // 解析响应
                        let dsResponse = try JSONDecoder().decode(DSResponse.self, from: data)
                        return dsResponse.choices.first?.message.content ?? fallbackUnknownReply
                    } else {
                        throw NSError(domain: "PetAIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported AI Provider: \(provider)"])
                    }
                }
                
                // 2. 超时任务 (30s)
                group.addTask {
                    try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    throw TimeoutError()
                }
                
                // 等待第一个完成的任务（成功或抛出异常）
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            // 成功处理 (回到 MainActor)
            print("✅ [PetAIService] 收到响应，长度=\(replyContent.count)")
            
            // 更新历史
            self.history.append(DSMessage(role: "user", content: historyUserText))
            self.history.append(DSMessage(role: "assistant", content: replyContent))
            
            let (cleanText, imageName) = parseResponse(replyContent)
            let recentAssistantReplies = uiMessages
                .filter { !$0.isUser }
                .suffix(4)
                .map(\.text)

            let displayResponse: String
            switch responseMode {
            case .raw:
                displayResponse = cleanText
            case .humanized:
                displayResponse = PetResponseHumanizer.humanize(
                    cleanText,
                    persona: personaProfile,
                    recentAssistantReplies: recentAssistantReplies
                )
            }
            PetConversationMemoryStore.shared.recordAssistantSignal(reply: displayResponse, role: role)

            // 触发语音朗读 (TTS) - 仅在启用语音时播放
            if enableVoice {
                PetVoiceManager.shared.speak(displayResponse, for: self.role)
            }

            let aiMsg = ChatMessage(
                text: displayResponse,
                rawText: cleanText,
                imageName: imageName,
                isUser: false
            )
            appendToHistory(aiMsg)
            self.saveMessages()
            return aiMsg
            
        } catch is TimeoutError {
            print("❌ [Debug] 请求超时 (30s)")
            let errorMsg = ChatMessage(
                text: personaProfile.timeoutReplies.randomElement() ?? "我稍微卡了一下，换个稳定网络我们再试一次。",
                imageName: defaultTimeoutImageName(),
                isUser: false
            )
            appendToHistory(errorMsg)
            self.saveMessages()
            return errorMsg
        } catch {
            print("❌ [Debug] 请求发生错误: \(error)")
            let errorMsg = ChatMessage(
                text: personaProfile.errorReplies.randomElement() ?? "我刚刚失手了，咱们再试一次。",
                imageName: defaultErrorImageName(),
                isUser: false
            )
            appendToHistory(errorMsg)
            self.saveMessages()
            return errorMsg
        }
    }
    
    private func parseResponse(_ text: String) -> (String, String?) {
        // 匹配 [IMAGE:xxx] 格式
        let pattern = "\\[IMAGE:(\\w+)\\]"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, nil)
        }
        
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var imageName: String? = nil
        var cleanText = text
        
        if !results.isEmpty {
            for match in results where match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                let candidate = nsString.substring(with: range)
                if let safeImageName = PetConversationToolbox.sanitizeActionIdentifier(candidate, role: role) {
                    imageName = safeImageName
                    break
                }
            }

            cleanText = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (cleanText, imageName)
    }

    private func defaultTimeoutImageName() -> String {
        switch role {
        case .kitten: return "sleepy_cat"
        case .goldenRetriever: return "sleepy_dog"
        }
    }

    private func defaultErrorImageName() -> String {
        switch role {
        case .kitten: return "curious_cat"
        case .goldenRetriever: return "curious_dog"
        }
    }

    private func historyMessageLimit(forPromptLength length: Int) -> Int {
        switch length {
        case ..<900:
            return 10
        case 900..<1800:
            return 8
        default:
            return 6
        }
    }
    
    func deleteMessages(ids: Set<UUID>) {
        allMessages.removeAll { ids.contains($0.id) }
        uiMessages.removeAll { ids.contains($0.id) }
        saveMessages()
    }
}
