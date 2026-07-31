import Foundation

struct TimeHallCatalogDTO: Codable, Sendable {
  let version: Int
  let source: String
  let title: String
  let subtitle: String
  let heroImage: String?
  let heroCaption: String
  let heroBody: String
  let scope: TimeHallCatalogScopeDTO
  let timelineYears: [TimeHallYearRecordDTO]
  let archiveCatalogues: [TimeHallArchiveCatalogueDTO]
  let catalogues: [TimeHallCatalogueDTO]
  let items: [TimeHallItemDTO]
}

struct TimeHallCatalogScopeDTO: Codable, Equatable, Sendable {
  let startYear: Int
  let endYear: Int?
  let labelZH: String
  let sampleYears: [Int]
}

enum TimeHallYearRecordKind: String, Codable, Sendable {
  case milestone
  case officialArchive
  case archiveGap

  var labelZH: String {
    switch self {
    case .milestone: return "品牌纪事"
    case .officialArchive: return "官网目录"
    case .archiveGap: return "故事卡片"
    }
  }

  var symbolName: String {
    switch self {
    case .milestone: return "sparkles"
    case .officialArchive: return "photo.on.rectangle.angled"
    case .archiveGap: return "book.pages"
    }
  }
}

enum TimeHallEvidenceLevel: String, Codable, Sendable {
  case officialHistory
  case officialCatalogue
  case archiveGap

  var labelZH: String {
    switch self {
    case .officialHistory: return "官方品牌史"
    case .officialCatalogue: return "官网 Catalogue"
    case .archiveGap: return "档案待补证"
    }
  }
}

struct TimeHallYearRecordDTO: Codable, Identifiable, Hashable, Sendable {
  var id: Int { year }
  let year: Int
  let kind: TimeHallYearRecordKind
  let titleZH: String
  let storyZH: String
  let evidenceLevel: TimeHallEvidenceLevel
  let sourceURLs: [String]
  let catalogueIDs: [String]
}

struct TimeHallArchiveCatalogueDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let officialID: Int
  let year: Int
  let title: String
  let seasonLabelZH: String
  let sourceURL: String
  let coverImage: String
  let imageSourceURL: String
}

struct TimeHallCatalogueDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let year: Int
  let season: String
  let seasonLabel: String
  let title: String
  let titleZH: String
  let summaryZH: String
  let sourceURL: String
  let coverImage: String
  let imageSourceURL: String
  let pageCount: Int
  let itemIds: [String]
}

enum TimeHallItemKind: String, Codable, CaseIterable, Sendable {
  case dress
  case accessory

  var labelZH: String {
    switch self {
    case .dress: return "裙装"
    case .accessory: return "小物"
    }
  }

  var symbolName: String {
    switch self {
    case .dress: return "tshirt.fill"
    case .accessory: return "handbag.fill"
    }
  }
}

struct TimeHallItemDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let canonicalKey: String
  let kind: TimeHallItemKind
  let category: String
  let categoryZH: String
  let name: String
  let nameZH: String
  let brand: String
  let year: Int
  let season: String
  let catalogueID: String
  let cataloguePage: Int
  let priceJPY: Int
  let listingStatus: String
  let styles: [String]
  let stylesZH: [String]
  let coverImage: String?
  let gallery: [String]
  let imageSourceURL: String
  let sourceURL: String
  let observedAt: String
  let datePrecision: String
  let noteZH: String
}

struct TimeHallStyleBubble: Identifiable, Hashable {
  let id: String
  let label: String
  let count: Int
}

struct TimeHallValidationReport: Equatable, Sendable {
  let dressCount: Int
  let accessoryCount: Int
  let catalogueCount: Int
  let timelineYearCount: Int
  let archiveCatalogueCount: Int
  let catalogErrors: [String]
  let duplicateItemIDs: [String]
  let duplicateCatalogueIDs: [String]
  let duplicateArchiveCatalogueIDs: [String]
  let duplicateTimelineYears: [Int]
  let duplicateCanonicalKeys: [String]
  let duplicateCatalogueItemIDs: [String]
  let missingCatalogueItemIDs: [String]
  let orphanItemIDs: [String]
  let invalidCatalogueIDs: [String]
  let invalidArchiveCatalogueIDs: [String]
  let invalidTimelineYears: [Int]
  let invalidItemIDs: [String]

  var isSampleValid: Bool {
    dressCount == 20
      && accessoryCount == 10
      && catalogueCount == 2
      && timelineYearCount == 55
      && archiveCatalogueCount == 47
      && catalogErrors.isEmpty
      && duplicateItemIDs.isEmpty
      && duplicateCatalogueIDs.isEmpty
      && duplicateArchiveCatalogueIDs.isEmpty
      && duplicateTimelineYears.isEmpty
      && duplicateCanonicalKeys.isEmpty
      && duplicateCatalogueItemIDs.isEmpty
      && missingCatalogueItemIDs.isEmpty
      && orphanItemIDs.isEmpty
      && invalidCatalogueIDs.isEmpty
      && invalidArchiveCatalogueIDs.isEmpty
      && invalidTimelineYears.isEmpty
      && invalidItemIDs.isEmpty
  }
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
