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
  let commerceSnapshots: [TimeHallCommerceSnapshotDTO]
  let commerceItems: [TimeHallCommerceItemDTO]
  let coordinates: [TimeHallCoordinateDTO]
  let stories: [TimeHallStoryDTO]
  let events: [TimeHallEventDTO]
  let historyEntries: [TimeHallHistoryEntryDTO]
  let importBatches: [TimeHallImportBatchDTO]
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
    case .milestone: return "品牌纪事".appLocalized
    case .officialArchive: return "官网目录".appLocalized
    case .archiveGap: return "故事卡片".appLocalized
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
    case .officialHistory: return "官方品牌史".appLocalized
    case .officialCatalogue: return "官网 Catalogue".appLocalized
    case .archiveGap: return "档案待补证".appLocalized
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

struct TimeHallImportBatchDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let order: Int
  let kind: String
  let titleZH: String
  let importedAt: String
  let sourceURLs: [String]
  let catalogueIDs: [String]
  let commerceSnapshotIDs: [String]
  let coordinateIDs: [String]
  let storyIDs: [String]
  let eventIDs: [String]
  let historyEntryIDs: [String]
  let itemCount: Int
}

enum TimeHallCommerceSource: String, Codable, CaseIterable, Sendable {
  case current
  case outlet

  var labelZH: String {
    switch self {
    case .current: return "当前商品".appLocalized
    case .outlet: return "OUTLET"
    }
  }
}

struct TimeHallCommerceSnapshotDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let titleZH: String
  let observedAt: String
  let sourceURLs: [String]
  let itemIDs: [String]
  let currentItemIDs: [String]
  let outletItemIDs: [String]
}

struct TimeHallCommerceItemDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let productCode: String
  let kind: TimeHallItemKind
  let category: String
  let categoryZH: String
  let name: String
  let nameZH: String
  let brand: String
  let sourceKind: TimeHallCommerceSource
  let regularPriceJPY: Int
  let salePriceJPY: Int?
  let listingStatus: String
  let description: String
  let descriptionZH: String?
  let colors: [String]
  let sizes: [String]
  let material: String?
  let countryOfOrigin: String?
  let styles: [String]
  let stylesZH: [String]
  let coverImage: String
  let detailImage: String?
  let imageSourceURLs: [String]
  let productPageURL: String
  let observedAt: String
}

struct TimeHallCoordinateDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let officialID: Int
  let title: String
  let publishedOn: String?
  let coordinatePoint: String
  let sourceURL: String
  let coverImage: String
  let imageSourceURL: String
  let productCodes: [String]
  let linkedCommerceItemIDs: [String]
  let unlinkedItemNames: [String]
  let observedAt: String
}

enum TimeHallStoryKind: String, Codable, CaseIterable, Sendable {
  case feature
  case craft

  var labelZH: String {
    switch self {
    case .feature: return "官方专题".appLocalized
    case .craft: return "制作工艺".appLocalized
    }
  }

  var symbolName: String {
    switch self {
    case .feature: return "sparkles.rectangle.stack"
    case .craft: return "paintbrush.pointed.fill"
    }
  }
}

struct TimeHallStoryDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let kind: TimeHallStoryKind
  let title: String
  let publishedOn: String?
  let summary: String
  let content: String
  let sourceURL: String
  let coverImage: String
  let imageSourceURLs: [String]
  let productCodes: [String]
  let linkedCommerceItemIDs: [String]
  let observedAt: String
}

enum TimeHallEventKind: String, Codable, CaseIterable, Sendable {
  case information
  case event

  var labelZH: String {
    switch self {
    case .information: return "资讯".appLocalized
    case .event: return "活动".appLocalized
    }
  }
}

struct TimeHallEventDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let officialID: Int
  let kind: TimeHallEventKind
  let title: String
  let publishedOn: String
  let summary: String
  let content: String
  let sourceURL: String
  let coverImage: String
  let imageSourceURLs: [String]
  let productCodes: [String]
  let linkedCommerceItemIDs: [String]
  let observedAt: String
}

struct TimeHallHistoryEntryDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let year: Int
  let title: String
  let content: String
  let sourceURL: String
  let coverImage: String?
  let imageSourceURL: String?
  let observedAt: String
}

enum TimeHallItemKind: String, Codable, CaseIterable, Sendable {
  case dress
  case clothing
  case accessory

  var labelZH: String {
    switch self {
    case .dress: return "裙装".appLocalized
    case .clothing: return "服装".appLocalized
    case .accessory: return "小物".appLocalized
    }
  }

  var symbolName: String {
    switch self {
    case .dress: return "tshirt.fill"
    case .clothing: return "tshirt.fill"
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
  let productCode: String?
  let productPageURL: String?
  let cataloguePages: [Int]?
}

struct TimeHallStyleBubble: Identifiable, Hashable {
  let id: String
  let label: String
  let count: Int
}

struct TimeHallValidationReport: Equatable, Sendable {
  let dressCount: Int
  let clothingCount: Int
  let accessoryCount: Int
  let catalogueCount: Int
  let timelineYearCount: Int
  let archiveCatalogueCount: Int
  let commerceSnapshotCount: Int
  let commerceItemCount: Int
  let coordinateCount: Int
  let storyCount: Int
  let eventCount: Int
  let historyEntryCount: Int
  let importBatchCount: Int
  let catalogErrors: [String]
  let duplicateItemIDs: [String]
  let duplicateCatalogueIDs: [String]
  let duplicateArchiveCatalogueIDs: [String]
  let duplicateImportBatchIDs: [String]
  let duplicateCommerceSnapshotIDs: [String]
  let duplicateCommerceItemIDs: [String]
  let duplicateCommerceProductCodes: [String]
  let duplicateCoordinateIDs: [String]
  let duplicateStoryIDs: [String]
  let duplicateEventIDs: [String]
  let duplicateHistoryEntryIDs: [String]
  let duplicateTimelineYears: [Int]
  let duplicateCanonicalKeys: [String]
  let duplicateCatalogueItemIDs: [String]
  let missingCatalogueItemIDs: [String]
  let orphanItemIDs: [String]
  let invalidCatalogueIDs: [String]
  let invalidArchiveCatalogueIDs: [String]
  let invalidImportBatchIDs: [String]
  let invalidCommerceSnapshotIDs: [String]
  let invalidCommerceItemIDs: [String]
  let invalidCoordinateIDs: [String]
  let invalidStoryIDs: [String]
  let invalidEventIDs: [String]
  let invalidHistoryEntryIDs: [String]
  let invalidTimelineYears: [Int]
  let invalidItemIDs: [String]

  var isCatalogValid: Bool {
    catalogErrors.isEmpty
      && duplicateItemIDs.isEmpty
      && duplicateCatalogueIDs.isEmpty
      && duplicateArchiveCatalogueIDs.isEmpty
      && duplicateImportBatchIDs.isEmpty
      && duplicateCommerceSnapshotIDs.isEmpty
      && duplicateCommerceItemIDs.isEmpty
      && duplicateCommerceProductCodes.isEmpty
      && duplicateCoordinateIDs.isEmpty
      && duplicateStoryIDs.isEmpty
      && duplicateEventIDs.isEmpty
      && duplicateHistoryEntryIDs.isEmpty
      && duplicateTimelineYears.isEmpty
      && duplicateCanonicalKeys.isEmpty
      && duplicateCatalogueItemIDs.isEmpty
      && missingCatalogueItemIDs.isEmpty
      && orphanItemIDs.isEmpty
      && invalidCatalogueIDs.isEmpty
      && invalidArchiveCatalogueIDs.isEmpty
      && invalidImportBatchIDs.isEmpty
      && invalidCommerceSnapshotIDs.isEmpty
      && invalidCommerceItemIDs.isEmpty
      && invalidCoordinateIDs.isEmpty
      && invalidStoryIDs.isEmpty
      && invalidEventIDs.isEmpty
      && invalidHistoryEntryIDs.isEmpty
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
