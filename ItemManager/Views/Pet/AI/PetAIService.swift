import Foundation
import Combine
import os.lock
import UIKit

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
    static let shared = PetAIService(role: .kitten, petName: "奶茶", apiKey: AIConfigManager.shared.dsApiKey ?? "") // Default init
    
    @Published var isProcessing: Bool = false
    @Published var uiMessages: [ChatMessage] = [] // UI 展示用的消息历史 (分页加载)
    private var allMessages: [ChatMessage] = [] // 完整的本地聊天记录
    
    private var role: PetRole
    private var petName: String
    private var apiKey: String
    
    // Maintain simple history for DeepSeek
    private var history: [DSMessage] = []
    
    private init(role: PetRole, petName: String, apiKey: String, wardrobeContext: String = "") {
        self.role = role
        self.petName = petName
        self.apiKey = apiKey
        
        // Initialize with placeholder history
        self.history = [
            DSMessage(role: "system", content: ""),
            DSMessage(role: "user", content: "你好，我是你的主人。"),
            DSMessage(role: "assistant", content: "（蹭蹭你的手）主人好呀喵！[IMAGE:happy_cat]")
        ]
        
        self.updateSystemContext(wardrobeContext: wardrobeContext)
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
    
    func updateConfiguration(role: PetRole, petName: String, apiKey: String, wardrobeContext: String) {
        self.role = role
        self.petName = petName
        self.apiKey = apiKey
        self.updateSystemContext(wardrobeContext: wardrobeContext)
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
        4. 依然保持宠物的口癖（喵/汪），但在讨论裙子时可以表现得更专业一点（懂Lo圈黑话）。
        """
        
        // 更新历史中的第一条 (System Prompt)
        if !self.history.isEmpty {
            self.history[0] = DSMessage(role: "system", content: fullPrompt)
        }
    }
    
    func sendImageAnalysisRequest(text: String, imageContext: String, image: UIImage? = nil) async -> ChatMessage {
        var imagePath: String?
        if let image = image {
            imagePath = saveImageToDisk(image: image)
        }
        
        // 将图片识别结果作为临时上下文插入，或者直接作为用户消息的一部分
        // 强制强调角色设定和字数限制
        let messageWithContext = """
        \(imageContext)
        
        用户问题：\(text)
        
        (重要提示：请务必保持萌宠的角色设定（喵/汪），不要只是枯燥地描述图片。
        1. 用主人的贴心闺蜜的口吻，字数严格控制在50字以内！
        2. 请结合【视觉描述】回答用户的问题。
        3. 可以参考【猜你想问】中的问题，在回复末尾自然地抛出一个相关话题，引导主人继续聊天。
        4. 请不要出现"根据图片"、"AI"、"视觉分析"等字眼。)
        """
        // Pass 'text' as displayText so the UI shows the clean question, not the prompt dump
        return await sendMessage(messageWithContext, userImagePath: imagePath, displayText: text)
    }

    func sendMessage(_ text: String, userImagePath: String? = nil, displayText: String? = nil) async -> ChatMessage {
        print("🐾 [Debug] 准备发送消息给奶茶猫 (DeepSeek): \(text)")
        
        // 1. 记录用户消息 (Use displayText if available, otherwise raw text)
        let userMsg = ChatMessage(text: displayText ?? text, imagePath: userImagePath, isUser: true)
        self.allMessages.append(userMsg)
        self.uiMessages.append(userMsg)
        self.saveMessages()
        
        self.isProcessing = true
        defer { self.isProcessing = false }
        
        // 捕获必要的上下文以传递给后台任务
        let currentHistory = self.history
        let apiKey = self.apiKey
        let role = self.role
        
        do {
            // ... (TaskGroup logic)
            // 使用 TaskGroup 实现并发和超时控制，避免 unsafeForcedSync
            let replyContent = try await withThrowingTaskGroup(of: String.self) { group in
                // 1. 网络请求任务
                group.addTask {
                    // 构造请求
                    // 注意：这里是在后台线程执行，不能访问 self 上的可变属性
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
                    request.httpBody = try JSONEncoder().encode(body)
                    
                    // 发送请求
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw NSError(domain: "DeepSeekError", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                    }
                    
                    // 解析响应
                    let dsResponse = try JSONDecoder().decode(DSResponse.self, from: data)
                    return dsResponse.choices.first?.message.content ?? "（歪头摇尾巴，不知道你在说什么喵...）"
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
            print("✅ [Debug] 收到 DeepSeek 响应: \(replyContent)")
            
            // 更新历史
            self.history.append(DSMessage(role: "user", content: text))
            self.history.append(DSMessage(role: "assistant", content: replyContent))
            
            let (cleanText, imageName) = parseResponse(replyContent)
            
            // 触发语音朗读 (TTS)
            PetVoiceManager.shared.speak(cleanText, for: self.role)
            
            let aiMsg = ChatMessage(text: cleanText, imageName: imageName, isUser: false)
            self.allMessages.append(aiMsg)
            self.uiMessages.append(aiMsg)
            self.saveMessages()
            return aiMsg
            
        } catch is TimeoutError {
            print("❌ [Debug] 请求超时 (30s)")
            let errorMsg = ChatMessage(text: "（打呼噜...）DeepSeek 好像有点慢喵...", imageName: "sleepy_cat", isUser: false)
            self.allMessages.append(errorMsg)
            self.uiMessages.append(errorMsg)
            self.saveMessages()
            return errorMsg
        } catch {
            print("❌ [Debug] 请求发生错误: \(error)")
            let errorMsg = ChatMessage(text: "错误: \(error.localizedDescription) (请检查 DS_API_KEY)", isUser: false)
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
