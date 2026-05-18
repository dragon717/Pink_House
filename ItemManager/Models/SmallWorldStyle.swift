import Foundation

enum SmallWorldStyle: String, CaseIterable, Identifiable {
    case rococo = "rococo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rococo: return "洛可可风格（等轴测图）"
        }
    }
}
