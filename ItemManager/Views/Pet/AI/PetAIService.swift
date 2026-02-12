import Foundation
import Combine
import GoogleGenerativeAI

class PetAIService: ObservableObject {
    @Published var isProcessing: Bool = false
    
    private let model: GenerativeModel
    private var chat: Chat
    private let role: PetRole
    private let petName: String

    init(role: PetRole, petName: String, apiKey: String) {
        self.role = role
        self.petName = petName
        
        // 注意：请确保你的 API Key 有权限访问该模型
        // 目前稳定版本是 "gemini-1.5-flash"
        self.model = GenerativeModel(
            name: "gemini-1.5-flash", 
            apiKey: apiKey,
            systemInstruction: ModelContent(role: "system", parts: [.text(role.systemPrompt(petName: petName))])
        )
        
        // 开启历史记录相关的配置
        let history = [
            ModelContent(role: "user", parts: [.text("你好，我是你的主人。")]),
            ModelContent(role: "model", parts: [.text("（蹭蹭你的手）主人好呀喵！[IMAGE:happy_cat]")])
        ]
        
        self.chat = model.startChat(history: history)
    }

    func sendMessage(_ text: String) async -> ChatMessage {
        print("🐾 [Debug] 准备发送消息给大橘: \(text)")
        await MainActor.run { self.isProcessing = true }
        defer { Task { await MainActor.run { self.isProcessing = false } } }
        
        do {
            let response = try await chat.sendMessage(text)
            print("✅ [Debug] 收到 Gemini 响应: \(response.text ?? "空内容")")
            let rawText = response.text ?? "（歪头摇尾巴，不知道你在说什么喵...）"
            
            let (cleanText, imageName) = parseResponse(rawText)
            return ChatMessage(text: cleanText, imageName: imageName, isUser: false)
            
        } catch {
            print("❌ [Debug] 请求发生错误: \(error)")
            return ChatMessage(text: "错误: \(error.localizedDescription) (请检查网络或API Key)", isUser: false)
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
