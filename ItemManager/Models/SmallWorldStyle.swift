import Foundation

enum SmallWorldStyle: String, CaseIterable, Identifiable {
    case frenchRetro = "french_retro"
    case rococo = "rococo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frenchRetro: return "法式复古轻奢写实"
        case .rococo: return "洛可可风格（等轴测图）"
        }
    }
}
