import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let rawText: String? // 保留原始模型文本，供生成式 UI 解析
    let imageName: String? // For bundled assets (e.g., [IMAGE:happy_cat])
    let imagePath: String? // For local file paths (e.g., analysis results)
    let isUser: Bool
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        text: String,
        rawText: String? = nil,
        imageName: String? = nil,
        imagePath: String? = nil,
        isUser: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.imageName = imageName
        self.imagePath = imagePath
        self.isUser = isUser
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case rawText
        case imageName
        case imagePath
        case isUser
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        let rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
        let imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
        let imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        let isUser = try container.decodeIfPresent(Bool.self, forKey: .isUser) ?? false
        let timestamp = Self.decodeTimestamp(from: container) ?? Date()

        self.init(
            id: id,
            text: text,
            rawText: rawText,
            imageName: imageName,
            imagePath: imagePath,
            isUser: isUser,
            timestamp: timestamp
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(rawText, forKey: .rawText)
        try container.encodeIfPresent(imageName, forKey: .imageName)
        try container.encodeIfPresent(imagePath, forKey: .imagePath)
        try container.encode(isUser, forKey: .isUser)
        try container.encode(timestamp, forKey: .timestamp)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if let date = try? container.decode(Date.self, forKey: .timestamp) {
            return date
        }
        if let unix = try? container.decode(Double.self, forKey: .timestamp) {
            // 兼容秒级和毫秒级时间戳
            if unix > 9_999_999_999 {
                return Date(timeIntervalSince1970: unix / 1000)
            }
            return Date(timeIntervalSince1970: unix)
        }
        if let text = try? container.decode(String.self, forKey: .timestamp) {
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: text) {
                return date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
