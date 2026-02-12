import Foundation
import Combine
// import GoogleGenerativeAI

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

class PetAIService: ObservableObject {
    @Published var isProcessing: Bool = false
    
    // private let model: GenerativeModel
    // private var chat: Chat
    private let role: PetRole
    private let petName: String
    private let apiKey: String
    
    // Maintain simple history for DeepSeek
    private var history: [DSMessage] = []

    init(role: PetRole, petName: String, apiKey: String) {
        self.role = role
        self.petName = petName
        self.apiKey = apiKey
        
        /*
        // 注意：请确保你的 API Key 有权限访问该模型
        // 用户确认支持 "gemini-2.5-flash"
        self.model = GenerativeModel(
            name: "gemini-2.5-flash", 
            apiKey: apiKey,
            systemInstruction: ModelContent(role: "system", parts: [.text(role.systemPrompt(petName: petName))])
        )
        
        // 开启历史记录相关的配置
        let history = [
            ModelContent(role: "user", parts: [.text("你好，我是你的主人。")]),
            ModelContent(role: "model", parts: [.text("（蹭蹭你的手）主人好呀喵！[IMAGE:happy_cat]")])
        ]
        
        self.chat = model.startChat(history: history)
        */
        
        // Initialize DeepSeek History
        self.history = [
            DSMessage(role: "system", content: role.systemPrompt(petName: petName)),
            DSMessage(role: "user", content: "你好，我是你的主人。"),
            DSMessage(role: "assistant", content: "（蹭蹭你的手）主人好呀喵！[IMAGE:happy_cat]")
        ]
    }

    func sendMessage(_ text: String) async -> ChatMessage {
        print("🐾 [Debug] 准备发送消息给奶茶猫 (DeepSeek): \(text)")
        
        // 使用原子锁来防止多次 resume
        return await withCheckedContinuation { continuation in
            Task {
                await MainActor.run { self.isProcessing = true }
                
                // 标记是否已经 resume，防止多次调用
                var hasResumed = false
                let lock = NSLock()
                
                func safeResume(with result: ChatMessage) {
                    lock.lock()
                    defer { lock.unlock() }
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: result)
                    }
                }
                
                // 创建一个 30秒 的超时任务 (DeepSeek 可能比 Gemini 慢一点)
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    if !Task.isCancelled {
                        print("❌ [Debug] 请求超时 (30s)")
                        await MainActor.run { self.isProcessing = false }
                        safeResume(with: ChatMessage(text: "（打呼噜...）DeepSeek 好像有点慢喵...", imageName: "sleepy_cat", isUser: false))
                    }
                }
                
                do {
                    // 1. 构造请求
                    self.history.append(DSMessage(role: "user", content: text))
                    
                    let url = URL(string: "https://api.deepseek.com/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.addValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    // 只发送最近的 N 条历史，避免 token 溢出 (例如保留 System + 最近 10 条)
                    let messagesToSend = [self.history.first!] + self.history.suffix(10)
                    
                    let body = DSRequest(model: "deepseek-chat", messages: messagesToSend, stream: false)
                    request.httpBody = try JSONEncoder().encode(body)
                    
                    // 2. 发送请求
                    let (data, response) = try await URLSession.shared.data(for: request)
                    timeoutTask.cancel()
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw NSError(domain: "DeepSeekError", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                    }
                    
                    // 3. 解析响应
                    let dsResponse = try JSONDecoder().decode(DSResponse.self, from: data)
                    let replyContent = dsResponse.choices.first?.message.content ?? "（歪头摇尾巴，不知道你在说什么喵...）"
                    
                    print("✅ [Debug] 收到 DeepSeek 响应: \(replyContent)")
                    
                    // 更新历史
                    self.history.append(DSMessage(role: "assistant", content: replyContent))
                    
                    await MainActor.run { self.isProcessing = false }
                    
                    let (cleanText, imageName) = parseResponse(replyContent)
                    safeResume(with: ChatMessage(text: cleanText, imageName: imageName, isUser: false))
                    
                } catch {
                    timeoutTask.cancel()
                    print("❌ [Debug] 请求发生错误: \(error)")
                    
                    await MainActor.run { self.isProcessing = false }
                    safeResume(with: ChatMessage(text: "错误: \(error.localizedDescription) (请检查 DS_API_KEY)", isUser: false))
                }
            }
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
}
