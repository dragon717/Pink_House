import Foundation
import Combine
import os.lock

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
    @Published var isProcessing: Bool = false
    
    private let role: PetRole
    private let petName: String
    private let apiKey: String
    
    // Maintain simple history for DeepSeek
    private var history: [DSMessage] = []
    
    init(role: PetRole, petName: String, apiKey: String) {
        self.role = role
        self.petName = petName
        self.apiKey = apiKey
        
        // Initialize DeepSeek History
        self.history = [
            DSMessage(role: "system", content: role.systemPrompt(petName: petName)),
            DSMessage(role: "user", content: "你好，我是你的主人。"),
            DSMessage(role: "assistant", content: "（蹭蹭你的手）主人好呀喵！[IMAGE:happy_cat]")
        ]
    }

    func sendMessage(_ text: String) async -> ChatMessage {
        print("🐾 [Debug] 准备发送消息给奶茶猫 (DeepSeek): \(text)")
        
        self.isProcessing = true
        defer { self.isProcessing = false }
        
        // 捕获必要的上下文以传递给后台任务
        let currentHistory = self.history
        let apiKey = self.apiKey
        let role = self.role
        
        do {
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
            
            return ChatMessage(text: cleanText, imageName: imageName, isUser: false)
            
        } catch is TimeoutError {
            print("❌ [Debug] 请求超时 (30s)")
            return ChatMessage(text: "（打呼噜...）DeepSeek 好像有点慢喵...", imageName: "sleepy_cat", isUser: false)
        } catch {
            print("❌ [Debug] 请求发生错误: \(error)")
            return ChatMessage(text: "错误: \(error.localizedDescription) (请检查 DS_API_KEY)", isUser: false)
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
