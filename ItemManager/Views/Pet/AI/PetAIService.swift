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
    
    private init() {
        // Initialize with placeholder history
        self.history = [
            DSMessage(role: "system", content: ""),
            DSMessage(role: "user", content: "你好，我是你的主人。"),
            DSMessage(role: "assistant", content: "（蹭蹭你的手）主人好呀喵！[IMAGE:happy_cat]")
        ]
        self.loadMessages()
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
            let data = try JSONEncoder().encode(allMessages)
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
    
    private func loadMessages() {
        guard FileManager.default.fileExists(atPath: messagesFileURL.path) else {
            isHistoryLoaded = true // 文件不存在，视为新用户，允许保存
            return
        }
        
        do {
            let data = try Data(contentsOf: messagesFileURL)
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            self.allMessages = messages
            
            // 初始只加载最后 2 条，提升进入速度
            let count = messages.count
            let loadCount = min(count, 2)
            let startIndex = count - loadCount
            self.uiMessages = Array(messages[startIndex..<count])
            
            isHistoryLoaded = true
            print("✅ [PetAIService] Successfully loaded \(count) messages.")
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
    func loadMoreHistory() {
        let currentCount = uiMessages.count
        let totalCount = allMessages.count
        
        guard currentCount < totalCount else { return }
        
        let remaining = totalCount - currentCount
        let pageSize = 20
        let loadCount = min(pageSize, remaining)
        
        let endIndex = totalCount - currentCount
        let startIndex = endIndex - loadCount
        
        let newMessages = Array(allMessages[startIndex..<endIndex])
        
        // 插入到开头
        self.uiMessages.insert(contentsOf: newMessages, at: 0)
    }
    
    // 重置 UI 显示为最新的 2 条 (用于退出页面时释放内存)
    func resetToLatest() {
        let count = allMessages.count
        let loadCount = min(count, 2)
        let startIndex = count - loadCount
        self.uiMessages = Array(allMessages[startIndex..<count])
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
        // 重新构建 System Prompt
        let basePrompt = role.systemPrompt(petName: petName)
        let fullPrompt = """
        \(basePrompt)
        
        【衣橱管家模式】
        你不仅是宠物，还是主人的贴心闺蜜和衣橱大管家。
        你对主人的衣橱了如指掌，以下是衣橱的最新数据：
        \(wardrobeContext)
        
        回复策略：
        1. 当主人问及“最贵”、“多少钱”等问题时，请基于上述数据精准回答。
        2. 满足主人的虚荣心，夸赞她的眼光，但不要太露骨，要像闺蜜一样真诚。
        3. 如果主人展示了图片（通过[视觉输入]），请结合衣橱数据进行点评。
        4. 依然保持宠物的口癖（喵/汪），但在讨论裙装时可以表现得更专业一点（懂Lo圈黑话）。
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
            // 尝试重新加载配置
            // 这里我们无法直接获取 PetViewModel 的逻辑 (因为它在 ViewModel 层)
            // 但我们可以尝试从 ConfigManager 获取 Key
            
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
    
    func sendMessage(_ text: String, userImagePath: String? = nil, displayText: String? = nil, enableVoice: Bool = true) async -> ChatMessage {
        print("🐾 [Debug] 准备发送消息给奶茶猫 (DeepSeek): \(text)")
        
        // 重置停止标志
        shouldStopGeneration = false
        
        // 1. 记录用户消息 (Use displayText if available, otherwise raw text)
        let userMsg = ChatMessage(text: displayText ?? text, imagePath: userImagePath, isUser: true)
        self.allMessages.append(userMsg)
        self.uiMessages.append(userMsg)
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
        let role = self.role
        let provider = self.provider
        
        print("🔍 [PetAIService] 发送请求 - Provider: \(provider)")
        if apiKey.isEmpty {
            print("❌ [PetAIService] Error: API Key is empty! Cannot send request.")
            let errorMsg = ChatMessage(text: "配置错误：API Key 为空。请检查 GenerativeAI-Info.plist。", isUser: false)
            self.allMessages.append(errorMsg)
            self.uiMessages.append(errorMsg)
            self.saveMessages()
            return errorMsg
        }
        print("🔑 [PetAIService] API Key (Masked): \(apiKey.prefix(6))...\(apiKey.suffix(4))")
        
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
                            .suffix(10)
                            .map { MinimaxMessage(role: $0.role, content: $0.content) }
                        
                        messagesToSend.append(MinimaxMessage(role: "user", content: text))
                        
                        let body = MinimaxRequest(
                            model: "MiniMax-M2.5",
                            messages: messagesToSend,
                            max_tokens: 1000,
                            stream: false,
                            system: systemPrompt // Optional
                        )
                        
                        print("📡 [PetAIService] Minimax Request Body: \(String(data: try JSONEncoder().encode(body), encoding: .utf8) ?? "")")
                        
                        request.httpBody = try JSONEncoder().encode(body)
                        
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
                        return textBlock?.text ?? "（歪头摇尾巴，不知道你在说什么喵...）"
                        
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
                        let messagesToSend = [historyToSend.first!] + historyToSend.suffix(10)
                        
                        let body = DSRequest(model: "deepseek-chat", messages: messagesToSend, stream: false)
                        print("📡 [PetAIService] DeepSeek Request Body: \(String(data: try JSONEncoder().encode(body), encoding: .utf8) ?? "")")
                        
                        request.httpBody = try JSONEncoder().encode(body)
                        
                        // 发送请求
                        let (data, response) = try await URLSession.shared.data(for: request)
                        
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                            print("❌ [PetAIService] DeepSeek Error: \(errorMsg)")
                            throw NSError(domain: "DeepSeekError", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                        }
                        
                        // 解析响应
                        let dsResponse = try JSONDecoder().decode(DSResponse.self, from: data)
                        return dsResponse.choices.first?.message.content ?? "（歪头摇尾巴，不知道你在说什么喵...）"
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
            print("✅ [Debug] 收到 \(provider) 响应: \(replyContent)")
            
            // 更新历史
            self.history.append(DSMessage(role: "user", content: text))
            self.history.append(DSMessage(role: "assistant", content: replyContent))
            
            let (cleanText, imageName) = parseResponse(replyContent)

            // 触发语音朗读 (TTS) - 仅在启用语音时播放
            if enableVoice {
                PetVoiceManager.shared.speak(cleanText, for: self.role)
            }

            let aiMsg = ChatMessage(text: cleanText, imageName: imageName, isUser: false)
            self.allMessages.append(aiMsg)
            self.uiMessages.append(aiMsg)
            self.saveMessages()
            return aiMsg
            
        } catch is TimeoutError {
            print("❌ [Debug] 请求超时 (30s)")
            let errorMsg = ChatMessage(text: "（打呼噜...）\(provider) 好像有点慢喵...", imageName: "sleepy_cat", isUser: false)
            self.allMessages.append(errorMsg)
            self.uiMessages.append(errorMsg)
            self.saveMessages()
            return errorMsg
        } catch {
            print("❌ [Debug] 请求发生错误: \(error)")
            let errorMsg = ChatMessage(text: "错误: \(error.localizedDescription) (请检查 \(provider) API_KEY)", isUser: false)
            self.allMessages.append(errorMsg)
            self.uiMessages.append(errorMsg)
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
        
        // 如果找到匹配项
        if let match = results.first {
            // 提取图片名称 (捕获组 1)
            if match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                imageName = nsString.substring(with: range)
            }
            
            // 从文本中移除指令
            // 注意：这里只处理了第一个匹配项，如果可能有多个，建议用循环或替换
            cleanText = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return (cleanText, imageName)
    }
    
    func deleteMessages(ids: Set<UUID>) {
        allMessages.removeAll { ids.contains($0.id) }
        uiMessages.removeAll { ids.contains($0.id) }
        saveMessages()
    }
}
