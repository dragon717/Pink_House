import SwiftUI

enum PetChatSkinTheme: String, CaseIterable, Codable, Identifiable {
    case classic
    case magic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典皮肤"
        case .magic: return "魔法皮肤"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "保留原有粉白气泡风格"
        case .magic: return "玻璃感 + 魔法渐变 + 更灵动的对话气泡"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .classic: return 20
        case .magic: return 24
        }
    }

    var userBubbleColors: [Color] {
        switch self {
        case .classic:
            return [.pink, .pink]
        case .magic:
            return [
                Color(red: 1.00, green: 0.51, blue: 0.82),
                Color(red: 0.96, green: 0.44, blue: 0.59)
            ]
        }
    }

    var assistantStrokeColors: [Color] {
        switch self {
        case .classic:
            return [Color.clear, Color.clear]
        case .magic:
            return [
                Color(red: 1.0, green: 0.74, blue: 0.86).opacity(0.75),
                Color(red: 0.93, green: 0.80, blue: 1.0).opacity(0.65)
            ]
        }
    }

    var previewBackgroundColors: [Color] {
        switch self {
        case .classic:
            return [
                Color(red: 1.0, green: 0.95, blue: 0.98),
                Color(red: 1.0, green: 0.98, blue: 0.98)
            ]
        case .magic:
            return [
                Color(red: 0.98, green: 0.92, blue: 1.0),
                Color(red: 0.93, green: 0.96, blue: 1.0),
                Color(red: 1.0, green: 0.93, blue: 0.97)
            ]
        }
    }
}
