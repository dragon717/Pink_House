import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let imageName: String?
    let isUser: Bool
    let timestamp = Date()
    
    init(text: String, imageName: String? = nil, isUser: Bool) {
        self.text = text
        self.imageName = imageName
        self.isUser = isUser
    }
}
