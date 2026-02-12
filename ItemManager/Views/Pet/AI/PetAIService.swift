import Foundation
import GoogleGenerativeAI

class PetAIService {
    private let model: GenerativeModel
    private var chat: ChatSession
    private let role: PetRole
    private let petName: String

    init(role: PetRole, petName: String, apiKey: String) {
        self.role = role
        self.petName = petName
        
        // 注意：请确保你的 API Key 有权限访问该模型
        // 如果 "gemini-3-flash" 不可用，请尝试 "gemini-1.5-flash" 或 "gemini-2.0-flash-exp"
        self.model = GenerativeModel(
            name: "gemini-3-flash", // 修正为当前可用的稳定版本，如果确实有 gemini-3-flash 权限可修改
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
        do {
            let response = try await chat.sendMessage(text)
            let rawText = response.text ?? "（歪头摇尾巴，不知道你在说什么喵...）"
            
            let (cleanText, imageName) = parseResponse(rawText)
            return ChatMessage(text: cleanText, imageName: imageName, isUser: false)
            
        } catch {
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
