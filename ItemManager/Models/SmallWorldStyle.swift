import Foundation

enum SmallWorldStyle: String, CaseIterable, Identifiable {
    case frenchRetro = "french_retro"
    case journalRoom = "journal_room"
    case rococo = "rococo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frenchRetro: return "法式复古轻奢写实"
        case .journalRoom: return "手帐房间（产品框架）"
        case .rococo: return "洛可可风格（等轴测图）"
        }
    }
}
