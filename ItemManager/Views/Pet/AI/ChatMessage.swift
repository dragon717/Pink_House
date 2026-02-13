import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let imageName: String? // For bundled assets (e.g., [IMAGE:happy_cat])
    let imagePath: String? // For local file paths (e.g., analysis results)
    let isUser: Bool
    let timestamp: Date
    
    init(text: String, imageName: String? = nil, imagePath: String? = nil, isUser: Bool) {
        self.id = UUID()
        self.text = text
        self.imageName = imageName
        self.imagePath = imagePath
        self.isUser = isUser
        self.timestamp = Date()
    }
}
