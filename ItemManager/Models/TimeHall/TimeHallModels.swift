import Foundation

struct TimeHallCatalogDTO: Codable, Sendable {
    let version: Int
    let source: String
    let title: String
    let subtitle: String
    let heroImage: String
    let heroCaption: String
    let heroBody: String
    let collections: [TimeHallCollectionDTO]
    let dresses: [TimeHallDressDTO]
}

struct TimeHallCollectionDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let year: Int
    let season: String
    let seasonLabel: String
    let title: String
    let titleZH: String
    let summary: String
    let summaryZH: String
    let heroImage: String
    let dressIds: [String]
}

struct TimeHallDressDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let nameZH: String
    let brand: String
    let year: Int
    let season: String
    let storeLimit: String
    let storeLimitZH: String
    let styles: [String]
    let stylesZH: [String]
    let coverImage: String
    let gallery: [String]
    let note: String
    let noteZH: String
}

struct TimeHallStyleBubble: Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int
}

enum TimeHallSeason: String, CaseIterable {
    case spring, summer, autumn, winter

    var labelZH: String {
        switch self {
        case .spring: return "春"
        case .summer: return "夏"
        case .autumn: return "秋"
        case .winter: return "冬"
        }
    }
}
