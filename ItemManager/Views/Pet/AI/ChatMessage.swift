import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let rawText: String? // 保留原始模型文本，供生成式 UI 解析
    let imageName: String? // For bundled assets (e.g., [IMAGE:happy_cat])
    let imagePath: String? // For local file paths (e.g., analysis results)
    let isUser: Bool
    let timestamp: Date
    
    init(text: String, rawText: String? = nil, imageName: String? = nil, imagePath: String? = nil, isUser: Bool) {
        self.id = UUID()
        self.text = text
        self.rawText = rawText
        self.imageName = imageName
        self.imagePath = imagePath
        self.isUser = isUser
        self.timestamp = Date()
    }
}
