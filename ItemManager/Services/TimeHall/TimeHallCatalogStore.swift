import Combine
import Foundation
import UIKit

/// Local-only V1 catalog. CloudKit public upload is documented in docs/TIME_HALL_CLOUDKIT_UPLOAD_PLAN.md.
@MainActor
final class TimeHallCatalogStore: ObservableObject {
  static let shared = TimeHallCatalogStore()

  @Published private(set) var catalog: TimeHallCatalogDTO?
  @Published private(set) var treasuredIDs: Set<String> = []
  @Published private(set) var validationReport = TimeHallValidationReport(
    dressCount: 0,
    accessoryCount: 0,
    catalogueCount: 0,
    timelineYearCount: 0,
    archiveCatalogueCount: 0,
    catalogErrors: [],
    duplicateItemIDs: [],
    duplicateCatalogueIDs: [],
    duplicateArchiveCatalogueIDs: [],
    duplicateTimelineYears: [],
    duplicateCanonicalKeys: [],
    duplicateCatalogueItemIDs: [],
    missingCatalogueItemIDs: [],
    orphanItemIDs: [],
    invalidCatalogueIDs: [],
    invalidArchiveCatalogueIDs: [],
    invalidTimelineYears: [],
    invalidItemIDs: []
  )

  private let treasureKey = "timeHall.treasured.v1"
  private let imageSubdir = "TimeHall/images"
  private let imageCache = NSCache<NSString, UIImage>()

  private init() {
    loadCatalog()
    treasuredIDs = Set(UserDefaults.standard.stringArray(forKey: treasureKey) ?? [])
  }

  var items: [TimeHallItemDTO] {
    catalog?.items ?? []
  }

  var dresses: [TimeHallItemDTO] {
    items.filter { $0.kind == .dress }
  }

  var accessories: [TimeHallItemDTO] {
    items.filter { $0.kind == .accessory }
  }

  var catalogues: [TimeHallCatalogueDTO] {
    catalog?.catalogues ?? []
  }

  var archiveCatalogues: [TimeHallArchiveCatalogueDTO] {
    catalog?.archiveCatalogues ?? []
  }

  var timelineYears: [TimeHallYearRecordDTO] {
    (catalog?.timelineYears ?? []).sorted { $0.year > $1.year }
  }

  var years: [Int] {
    timelineYears.map(\.year)
  }

  func yearRecord(for year: Int) -> TimeHallYearRecordDTO? {
    timelineYears.first { $0.year == year }
  }

  func archiveCatalogues(for year: Int) -> [TimeHallArchiveCatalogueDTO] {
    archiveCatalogues.filter { $0.year == year }
  }

  func items(in catalogue: TimeHallCatalogueDTO) -> [TimeHallItemDTO] {
    let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    return catalogue.itemIds.compactMap { map[$0] }
  }

  func catalogues(for year: Int) -> [TimeHallCatalogueDTO] {
    catalogues.filter { $0.year == year }
  }

  func styleBubbles() -> [TimeHallStyleBubble] {
    var counts: [String: Int] = [:]
    for item in items {
      for tag in item.stylesZH where !tag.isEmpty {
        counts[tag, default: 0] += 1
      }
    }
    return
      counts
      .map { TimeHallStyleBubble(id: $0.key, label: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.label < rhs.label
      }
  }

  func items(withStyle label: String) -> [TimeHallItemDTO] {
    items.filter { $0.stylesZH.contains(label) || $0.styles.contains(label) }
  }

  func isTreasured(_ id: String) -> Bool {
    treasuredIDs.contains(id)
  }

  func toggleTreasure(_ id: String) {
    if treasuredIDs.contains(id) {
      treasuredIDs.remove(id)
    } else {
      treasuredIDs.insert(id)
    }
    UserDefaults.standard.set(Array(treasuredIDs), forKey: treasureKey)
  }

  func image(named fileName: String?) -> UIImage? {
    guard let fileName, !fileName.isEmpty else { return nil }
    if let cached = imageCache.object(forKey: fileName as NSString) {
      return cached
    }
    let ns = fileName as NSString
    let base = ns.deletingPathExtension
    let ext = ns.pathExtension.isEmpty ? nil : ns.pathExtension
    let candidates: [URL?] = [
      Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: imageSubdir),
      Bundle.main.url(forResource: base, withExtension: ext, subdirectory: imageSubdir),
      Bundle.main.url(
        forResource: fileName, withExtension: nil, subdirectory: "Resources/\(imageSubdir)"),
      Bundle.main.url(forResource: base, withExtension: ext),
      Bundle.main.url(forResource: fileName, withExtension: nil),
    ]
    for url in candidates.compactMap({ $0 }) {
      if let image = UIImage(contentsOfFile: url.path) {
        imageCache.setObject(image, forKey: fileName as NSString)
        return image
      }
    }
    if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil),
      let match = urls.first(where: {
        $0.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame
      })
    {
      if let image = UIImage(contentsOfFile: match.path) {
        imageCache.setObject(image, forKey: fileName as NSString)
        return image
      }
    }
    return nil
  }

  private func loadCatalog() {
    let candidates: [URL?] = [
      Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "TimeHall"),
      Bundle.main.url(
        forResource: "catalog", withExtension: "json", subdirectory: "Resources/TimeHall"),
      Bundle.main.url(forResource: "catalog", withExtension: "json"),
    ]
    guard let url = candidates.compactMap({ $0 }).first else {
      print("❌ TimeHallCatalogStore: catalog.json missing")
      return
    }
    do {
      let decoded = try JSONDecoder().decode(TimeHallCatalogDTO.self, from: Data(contentsOf: url))
      let report = Self.validate(decoded)
      catalog = decoded
      validationReport = report
      if report.isSampleValid {
        print(
          "✅ TimeHallCatalogStore: 55 years + 47 official catalogues + 30 sample items validated")
      } else {
        print("❌ TimeHallCatalogStore: sample validation failed \(report)")
      }
      assert(report.isSampleValid, "TimeHall sample catalog must pass count and dedup validation")
    } catch {
      print("❌ TimeHallCatalogStore: decode failed \(error)")
    }
  }

  nonisolated static func validate(_ catalog: TimeHallCatalogDTO) -> TimeHallValidationReport {
    let duplicateItemIDs = duplicateValues(catalog.items.map(\.id))
    let duplicateCatalogueIDs = duplicateValues(catalog.catalogues.map(\.id))
    let duplicateArchiveCatalogueIDs = duplicateValues(catalog.archiveCatalogues.map(\.id))
    let duplicateTimelineYears = Dictionary(grouping: catalog.timelineYears.map(\.year), by: { $0 })
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    let groupedKeys = Dictionary(grouping: catalog.items, by: \.canonicalKey)
    let duplicateKeys =
      groupedKeys
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()

    var catalogErrors: [String] = []
    if catalog.version != 3 { catalogErrors.append("version") }
    if !isOfficialURL(catalog.source) { catalogErrors.append("source") }
    if catalog.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      catalogErrors.append("title")
    }
    if catalog.scope.startYear != 1972 || catalog.scope.endYear != nil {
      catalogErrors.append("scope")
    }
    let actualSampleYears = Array(Set(catalog.catalogues.map(\.year))).sorted()
    if Array(Set(catalog.scope.sampleYears)).sorted() != actualSampleYears {
      catalogErrors.append("sampleYears")
    }

    let expectedTimelineYears = Array(1972...2026)
    if catalog.timelineYears.map(\.year).sorted() != expectedTimelineYears {
      catalogErrors.append("timelineCoverage")
    }
    let expectedArchiveYears = Set(2015...2026)
    if Set(catalog.archiveCatalogues.map(\.year)) != expectedArchiveYears {
      catalogErrors.append("archiveCoverage")
    }

    let archiveCatalogueIDs = Set(catalog.archiveCatalogues.map(\.id))
    let invalidArchiveCatalogueIDs = Set(
      catalog.archiveCatalogues.compactMap { catalogue -> String? in
        let isValid =
          !catalogue.id.isEmpty
          && catalogue.id == "official-catalog-\(catalogue.officialID)"
          && (2015...2026).contains(catalogue.year)
          && !catalogue.title.isEmpty
          && !catalogue.seasonLabelZH.isEmpty
          && !catalogue.coverImage.isEmpty
          && isOfficialURL(catalogue.sourceURL)
          && isOfficialImageURL(catalogue.imageSourceURL)
        return isValid ? nil : catalogue.id
      }
    ).sorted()

    let invalidTimelineYears = Set(
      catalog.timelineYears.compactMap { record -> Int? in
        let hasCoreFields =
          (1972...2026).contains(record.year)
          && !record.titleZH.isEmpty
          && !record.storyZH.isEmpty
          && record.sourceURLs.allSatisfy(isOfficialSourceURL)
          && Set(record.catalogueIDs).isSubset(of: archiveCatalogueIDs)
        let kindIsValid: Bool
        switch record.kind {
        case .archiveGap:
          kindIsValid =
            record.evidenceLevel == .archiveGap
            && record.sourceURLs.isEmpty
            && record.catalogueIDs.isEmpty
        case .officialArchive:
          kindIsValid =
            record.evidenceLevel == .officialCatalogue
            && !record.catalogueIDs.isEmpty
        case .milestone:
          kindIsValid =
            record.evidenceLevel == .officialHistory
            && !record.sourceURLs.isEmpty
        }
        return hasCoreFields && kindIsValid ? nil : record.year
      }
    ).sorted()

    let invalidCatalogueIDs = Set(
      catalog.catalogues.compactMap { catalogue -> String? in
        let hasCoreFields =
          !catalogue.id.isEmpty
          && !catalogue.title.isEmpty
          && !catalogue.titleZH.isEmpty
          && !catalogue.summaryZH.isEmpty
          && !catalogue.season.isEmpty
          && !catalogue.seasonLabel.isEmpty
          && !catalogue.coverImage.isEmpty
        let isValid =
          hasCoreFields
          && catalogue.year >= catalog.scope.startYear
          && catalogue.pageCount > 0
          && !catalogue.itemIds.isEmpty
          && isOfficialURL(catalogue.sourceURL)
          && isOfficialImageURL(catalogue.imageSourceURL)
        return isValid ? nil : catalogue.id
      }
    ).sorted()

    let catalogueByID = Dictionary(
      catalog.catalogues.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let invalidItemIDs = Set(
      catalog.items.compactMap { item -> String? in
        guard let catalogue = catalogueByID[item.catalogueID] else { return item.id }
        let expectedCanonicalKey = "pink-house|\(item.year)-\(item.season)|\(item.name)"
        let hasCoreFields =
          !item.id.isEmpty
          && !item.canonicalKey.isEmpty
          && !item.category.isEmpty
          && !item.categoryZH.isEmpty
          && !item.name.isEmpty
          && !item.nameZH.isEmpty
          && item.brand == "PINK HOUSE"
          && !item.listingStatus.isEmpty
          && !item.styles.isEmpty
          && !item.stylesZH.isEmpty
          && !item.noteZH.isEmpty
          && !(item.coverImage ?? "").isEmpty
        let matchesCatalogue =
          item.year == catalogue.year
          && item.season == catalogue.season
          && item.sourceURL == catalogue.sourceURL
          && catalogue.itemIds.contains(item.id)
          && (1...catalogue.pageCount).contains(item.cataloguePage)
        let isValid =
          hasCoreFields
          && matchesCatalogue
          && item.canonicalKey == expectedCanonicalKey
          && item.priceJPY > 0
          && item.datePrecision == "season"
          && isOfficialURL(item.sourceURL)
          && isOfficialImageURL(item.imageSourceURL)
          && isISODate(item.observedAt)
        return isValid ? nil : item.id
      }
    ).sorted()

    let itemIDs = Set(catalog.items.map(\.id))
    let allReferencedIDs = catalog.catalogues.flatMap(\.itemIds)
    let referencedIDs = Set(allReferencedIDs)
    return TimeHallValidationReport(
      dressCount: catalog.items.filter { $0.kind == .dress }.count,
      accessoryCount: catalog.items.filter { $0.kind == .accessory }.count,
      catalogueCount: catalog.catalogues.count,
      timelineYearCount: catalog.timelineYears.count,
      archiveCatalogueCount: catalog.archiveCatalogues.count,
      catalogErrors: catalogErrors.sorted(),
      duplicateItemIDs: duplicateItemIDs,
      duplicateCatalogueIDs: duplicateCatalogueIDs,
      duplicateArchiveCatalogueIDs: duplicateArchiveCatalogueIDs,
      duplicateTimelineYears: duplicateTimelineYears,
      duplicateCanonicalKeys: duplicateKeys,
      duplicateCatalogueItemIDs: duplicateValues(allReferencedIDs),
      missingCatalogueItemIDs: Array(referencedIDs.subtracting(itemIDs)).sorted(),
      orphanItemIDs: Array(itemIDs.subtracting(referencedIDs)).sorted(),
      invalidCatalogueIDs: invalidCatalogueIDs,
      invalidArchiveCatalogueIDs: invalidArchiveCatalogueIDs,
      invalidTimelineYears: invalidTimelineYears,
      invalidItemIDs: invalidItemIDs
    )
  }

  nonisolated private static func duplicateValues(_ values: [String]) -> [String] {
    Dictionary(grouping: values, by: { $0 })
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
  }

  nonisolated private static func isOfficialURL(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    return url.scheme == "https" && url.host == "pinkhouse-webshop.jp"
  }

  nonisolated private static func isOfficialSourceURL(_ value: String) -> Bool {
    guard let url = URL(string: value), url.scheme == "https", let host = url.host else {
      return false
    }
    return host == "pinkhouse-webshop.jp" || host == "www.melrose.co.jp"
  }

  nonisolated private static func isOfficialImageURL(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    return url.scheme == "https"
      && url.host == "pinkhouse-webshop.jp"
      && url.path.hasPrefix("/photo/catalog/")
      && url.pathExtension.lowercased() == "jpg"
  }

  nonisolated private static func isISODate(_ value: String) -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter.date(from: value) != nil
  }
}
