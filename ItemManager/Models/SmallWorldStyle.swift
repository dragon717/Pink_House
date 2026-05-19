import Foundation

enum SmallWorldStyle: String, CaseIterable, Identifiable {
    case bookHouse = "book_house"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bookHouse: return "书本 House（默认）"
        }
    }
}
