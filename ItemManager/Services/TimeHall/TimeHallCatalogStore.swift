import Combine
import Foundation
import ImageIO
import UIKit

/// Local V3 batch catalog. CloudKit public upload is documented in docs/TIME_HALL_CLOUDKIT_UPLOAD_PLAN.md.
@MainActor
final class TimeHallCatalogStore: ObservableObject {
  static let shared = TimeHallCatalogStore()

  @Published private(set) var catalog: TimeHallCatalogDTO?
  @Published private(set) var treasuredIDs: Set<String> = []
  @Published private(set) var validationReport = TimeHallValidationReport(
    dressCount: 0,
    clothingCount: 0,
    accessoryCount: 0,
    catalogueCount: 0,
    timelineYearCount: 0,
    archiveCatalogueCount: 0,
    commerceSnapshotCount: 0,
    commerceItemCount: 0,
    coordinateCount: 0,
    storyCount: 0,
    eventCount: 0,
    historyEntryCount: 0,
    importBatchCount: 0,
    catalogErrors: [],
    duplicateItemIDs: [],
    duplicateCatalogueIDs: [],
    duplicateArchiveCatalogueIDs: [],
    duplicateImportBatchIDs: [],
    duplicateCommerceSnapshotIDs: [],
    duplicateCommerceItemIDs: [],
    duplicateCommerceProductCodes: [],
    duplicateCoordinateIDs: [],
    duplicateStoryIDs: [],
    duplicateEventIDs: [],
    duplicateHistoryEntryIDs: [],
    duplicateTimelineYears: [],
    duplicateCanonicalKeys: [],
    duplicateCatalogueItemIDs: [],
    missingCatalogueItemIDs: [],
    orphanItemIDs: [],
    invalidCatalogueIDs: [],
    invalidArchiveCatalogueIDs: [],
    invalidImportBatchIDs: [],
    invalidCommerceSnapshotIDs: [],
    invalidCommerceItemIDs: [],
    invalidCoordinateIDs: [],
    invalidStoryIDs: [],
    invalidEventIDs: [],
    invalidHistoryEntryIDs: [],
    invalidTimelineYears: [],
    invalidItemIDs: []
  )

  private let treasureKey = "timeHall.treasured.v1"
  private let imageSubdir = "TimeHall/images"
  private let imageCache = NSCache<NSString, UIImage>()

  private init() {
    imageCache.countLimit = 96
    imageCache.totalCostLimit = 80 * 1024 * 1024
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

  var clothing: [TimeHallItemDTO] {
    items.filter { $0.kind == .clothing }
  }

  var catalogues: [TimeHallCatalogueDTO] {
    catalog?.catalogues ?? []
  }

  var archiveCatalogues: [TimeHallArchiveCatalogueDTO] {
    catalog?.archiveCatalogues ?? []
  }

  var importBatches: [TimeHallImportBatchDTO] {
    (catalog?.importBatches ?? []).sorted { $0.order < $1.order }
  }

  var commerceSnapshots: [TimeHallCommerceSnapshotDTO] {
    (catalog?.commerceSnapshots ?? []).sorted { $0.observedAt > $1.observedAt }
  }

  var commerceItems: [TimeHallCommerceItemDTO] {
    catalog?.commerceItems ?? []
  }

  var coordinates: [TimeHallCoordinateDTO] {
    catalog?.coordinates ?? []
  }

  var stories: [TimeHallStoryDTO] {
    (catalog?.stories ?? []).sorted {
      ($0.publishedOn ?? "") > ($1.publishedOn ?? "")
    }
  }

  var events: [TimeHallEventDTO] {
    (catalog?.events ?? []).sorted { $0.publishedOn > $1.publishedOn }
  }

  func events(for year: Int) -> [TimeHallEventDTO] {
    events.filter { $0.publishedOn.hasPrefix("\(year)-") }
  }

  func historyEntries(for year: Int) -> [TimeHallHistoryEntryDTO] {
    (catalog?.historyEntries ?? []).filter { $0.year == year }
  }

  func commerceItems(in snapshot: TimeHallCommerceSnapshotDTO) -> [TimeHallCommerceItemDTO] {
    let itemByID = Dictionary(uniqueKeysWithValues: commerceItems.map { ($0.id, $0) })
    return snapshot.itemIDs.compactMap { itemByID[$0] }
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
    guard let url = imageURL(named: fileName), let image = UIImage(contentsOfFile: url.path) else {
      return nil
    }
    imageCache.setObject(image, forKey: fileName as NSString)
    return image
  }

  func loadImage(named fileName: String?) async -> UIImage? {
    guard let fileName, !fileName.isEmpty else { return nil }
    let cacheKey = fileName as NSString
    if let cached = imageCache.object(forKey: cacheKey) {
      return cached
    }
    guard let url = imageURL(named: fileName) else { return nil }
    let image = await Task.detached(priority: .userInitiated) {
      TimeHallImageDownsampler.load(url: url, maxPixelDimension: 1200)
    }.value
    guard let image, !Task.isCancelled else { return nil }
    let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
    imageCache.setObject(image, forKey: cacheKey, cost: cost)
    return image
  }

  private func imageURL(named fileName: String) -> URL? {
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
    return candidates.compactMap { $0 }.first
      ?? Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?.first {
        $0.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame
      }
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
      if report.isCatalogValid {
        print(
          "✅ TimeHallCatalogStore: \(decoded.timelineYears.count) years + \(decoded.archiveCatalogues.count) official catalogues + \(decoded.items.count) catalogue items + \(decoded.commerceItems.count) commerce items across \(decoded.importBatches.count) batches validated"
        )
      } else {
        print("❌ TimeHallCatalogStore: catalog validation failed \(report)")
      }
      assert(report.isCatalogValid, "TimeHall catalog must pass integrity and dedup validation")
    } catch {
      print("❌ TimeHallCatalogStore: decode failed \(error)")
    }
  }

  nonisolated static func validate(_ catalog: TimeHallCatalogDTO) -> TimeHallValidationReport {
    let duplicateItemIDs = duplicateValues(catalog.items.map(\.id))
    let duplicateCatalogueIDs = duplicateValues(catalog.catalogues.map(\.id))
    let duplicateArchiveCatalogueIDs = duplicateValues(catalog.archiveCatalogues.map(\.id))
    let duplicateImportBatchIDs = duplicateValues(catalog.importBatches.map(\.id))
    let duplicateCommerceSnapshotIDs = duplicateValues(catalog.commerceSnapshots.map(\.id))
    let duplicateCommerceItemIDs = duplicateValues(catalog.commerceItems.map(\.id))
    let duplicateCommerceProductCodes = duplicateValues(catalog.commerceItems.map(\.productCode))
    let duplicateCoordinateIDs = duplicateValues(catalog.coordinates.map(\.id))
    let duplicateStoryIDs = duplicateValues(catalog.stories.map(\.id))
    let duplicateEventIDs = duplicateValues(catalog.events.map(\.id))
    let duplicateHistoryEntryIDs = duplicateValues(catalog.historyEntries.map(\.id))
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
    if catalog.catalogues.isEmpty { catalogErrors.append("catalogues") }
    if catalog.items.isEmpty { catalogErrors.append("items") }
    if catalog.importBatches.isEmpty { catalogErrors.append("importBatches") }

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

    let deepCatalogueIDs = Set(catalog.catalogues.map(\.id))
    let deepCatalogueByID = Dictionary(
      catalog.catalogues.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let commerceSnapshotIDs = Set(catalog.commerceSnapshots.map(\.id))
    let coordinateIDs = Set(catalog.coordinates.map(\.id))
    let storyIDs = Set(catalog.stories.map(\.id))
    let eventIDs = Set(catalog.events.map(\.id))
    let historyEntryIDs = Set(catalog.historyEntries.map(\.id))
    let commerceSnapshotByID = Dictionary(
      catalog.commerceSnapshots.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let invalidImportBatchIDs = Set(
      catalog.importBatches.compactMap { batch -> String? in
        let catalogueItemIDs = batch.catalogueIDs.flatMap { deepCatalogueByID[$0]?.itemIds ?? [] }
        let commerceItemIDs = batch.commerceSnapshotIDs.flatMap {
          commerceSnapshotByID[$0]?.itemIDs ?? []
        }
        let referencedCoordinateIDs = batch.coordinateIDs.filter { coordinateIDs.contains($0) }
        let referencedStoryIDs = batch.storyIDs.filter { storyIDs.contains($0) }
        let referencedEventIDs = batch.eventIDs.filter { eventIDs.contains($0) }
        let referencedHistoryEntryIDs = batch.historyEntryIDs.filter {
          historyEntryIDs.contains($0)
        }
        let referencedItemCount = Set(
          catalogueItemIDs + commerceItemIDs + referencedCoordinateIDs + referencedStoryIDs
            + referencedEventIDs
            + referencedHistoryEntryIDs
        ).count
        let ownsSupportedContent =
          !batch.catalogueIDs.isEmpty || !batch.commerceSnapshotIDs.isEmpty
          || !batch.coordinateIDs.isEmpty || !batch.storyIDs.isEmpty || !batch.eventIDs.isEmpty
          || !batch.historyEntryIDs.isEmpty
        let isValid =
          !batch.id.isEmpty
          && batch.order > 0
          && !batch.kind.isEmpty
          && !batch.titleZH.isEmpty
          && isISODate(batch.importedAt)
          && !batch.sourceURLs.isEmpty
          && batch.sourceURLs.allSatisfy(isOfficialSourceURL)
          && ownsSupportedContent
          && Set(batch.catalogueIDs).isSubset(of: deepCatalogueIDs)
          && Set(batch.commerceSnapshotIDs).isSubset(of: commerceSnapshotIDs)
          && Set(batch.coordinateIDs).isSubset(of: coordinateIDs)
          && Set(batch.storyIDs).isSubset(of: storyIDs)
          && Set(batch.eventIDs).isSubset(of: eventIDs)
          && Set(batch.historyEntryIDs).isSubset(of: historyEntryIDs)
          && batch.itemCount == referencedItemCount
        return isValid ? nil : batch.id
      }
    ).sorted()

    let commerceItemIDs = Set(catalog.commerceItems.map(\.id))
    let invalidCommerceSnapshotIDs = Set(
      catalog.commerceSnapshots.compactMap { snapshot -> String? in
        let ids = Set(snapshot.itemIDs)
        let currentIDs = Set(snapshot.currentItemIDs)
        let outletIDs = Set(snapshot.outletItemIDs)
        let isValid =
          !snapshot.id.isEmpty
          && !snapshot.titleZH.isEmpty
          && isISODate(snapshot.observedAt)
          && !snapshot.sourceURLs.isEmpty
          && snapshot.sourceURLs.allSatisfy(isOfficialSourceURL)
          && !ids.isEmpty
          && ids == currentIDs.union(outletIDs)
          && currentIDs.isDisjoint(with: outletIDs)
          && ids.isSubset(of: commerceItemIDs)
        return isValid ? nil : snapshot.id
      }
    ).sorted()

    let invalidCommerceItemIDs = Set(
      catalog.commerceItems.compactMap { item -> String? in
        let priceIsValid =
          item.regularPriceJPY > 0
          && (item.salePriceJPY.map { $0 > 0 && $0 <= item.regularPriceJPY } ?? true)
        let isValid =
          !item.id.isEmpty
          && !item.productCode.isEmpty
          && !item.category.isEmpty
          && !item.categoryZH.isEmpty
          && !item.name.isEmpty
          && !item.nameZH.isEmpty
          && item.brand == "PINK HOUSE"
          && !item.listingStatus.isEmpty
          && !item.styles.isEmpty
          && !item.stylesZH.isEmpty
          && !item.coverImage.isEmpty
          && !item.imageSourceURLs.isEmpty
          && item.imageSourceURLs.allSatisfy(isOfficialCommerceImageURL)
          && isOfficialURL(item.productPageURL)
          && isISODate(item.observedAt)
          && priceIsValid
        return isValid ? nil : item.id
      }
    ).sorted()

    let invalidCoordinateIDs = Set(
      catalog.coordinates.compactMap { coordinate -> String? in
        let publishedOnIsValid = coordinate.publishedOn.map(isISODate) ?? true
        let isValid =
          coordinate.id == "coordinate-\(coordinate.officialID)"
          && coordinate.officialID > 0
          && !coordinate.title.isEmpty
          && !coordinate.coordinatePoint.isEmpty
          && isOfficialURL(coordinate.sourceURL)
          && isOfficialCoordinateImageURL(coordinate.imageSourceURL)
          && !coordinate.coverImage.isEmpty
          && Set(coordinate.linkedCommerceItemIDs).isSubset(of: commerceItemIDs)
          && publishedOnIsValid
          && isISODate(coordinate.observedAt)
        return isValid ? nil : coordinate.id
      }
    ).sorted()

    let invalidStoryIDs = Set(
      catalog.stories.compactMap { story -> String? in
        let publishedOnIsValid = story.publishedOn.map(isISODate) ?? true
        let isValid =
          !story.id.isEmpty
          && !story.title.isEmpty
          && !story.summary.isEmpty
          && !story.content.isEmpty
          && isOfficialSourceURL(story.sourceURL)
          && !story.coverImage.isEmpty
          && !story.imageSourceURLs.isEmpty
          && story.imageSourceURLs.allSatisfy(isOfficialStoryImageURL)
          && Set(story.linkedCommerceItemIDs).isSubset(of: commerceItemIDs)
          && publishedOnIsValid
          && isISODate(story.observedAt)
        return isValid ? nil : story.id
      }
    ).sorted()

    let invalidEventIDs = Set(
      catalog.events.compactMap { event -> String? in
        let isValid =
          event.id == "news-\(event.officialID)"
          && event.officialID > 0
          && !event.title.isEmpty
          && isISODate(event.publishedOn)
          && !event.summary.isEmpty
          && !event.content.isEmpty
          && isOfficialURL(event.sourceURL)
          && !event.coverImage.isEmpty
          && !event.imageSourceURLs.isEmpty
          && event.imageSourceURLs.allSatisfy(isOfficialNewsImageURL)
          && Set(event.linkedCommerceItemIDs).isSubset(of: commerceItemIDs)
          && isISODate(event.observedAt)
        return isValid ? nil : event.id
      }
    ).sorted()

    let invalidHistoryEntryIDs = Set(
      catalog.historyEntries.compactMap { entry -> String? in
        let imagePairIsValid: Bool
        if let coverImage = entry.coverImage, let imageSourceURL = entry.imageSourceURL {
          imagePairIsValid = !coverImage.isEmpty && isOfficialHistoryImageURL(imageSourceURL)
        } else {
          imagePairIsValid = entry.coverImage == nil && entry.imageSourceURL == nil
        }
        let isValid =
          !entry.id.isEmpty
          && (1972...2026).contains(entry.year)
          && !entry.title.isEmpty
          && !entry.content.isEmpty
          && isOfficialSourceURL(entry.sourceURL)
          && imagePairIsValid
          && isISODate(entry.observedAt)
        return isValid ? nil : entry.id
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
        let cataloguePagesAreValid =
          item.cataloguePages.map {
            !$0.isEmpty
              && $0.contains(item.cataloguePage)
              && $0.allSatisfy { (1...catalogue.pageCount).contains($0) }
          } ?? true
        let productPageIsValid = item.productPageURL.map(isOfficialURL) ?? true
        let isValid =
          hasCoreFields
          && matchesCatalogue
          && cataloguePagesAreValid
          && productPageIsValid
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
      clothingCount: catalog.items.filter { $0.kind == .clothing }.count,
      accessoryCount: catalog.items.filter { $0.kind == .accessory }.count,
      catalogueCount: catalog.catalogues.count,
      timelineYearCount: catalog.timelineYears.count,
      archiveCatalogueCount: catalog.archiveCatalogues.count,
      commerceSnapshotCount: catalog.commerceSnapshots.count,
      commerceItemCount: catalog.commerceItems.count,
      coordinateCount: catalog.coordinates.count,
      storyCount: catalog.stories.count,
      eventCount: catalog.events.count,
      historyEntryCount: catalog.historyEntries.count,
      importBatchCount: catalog.importBatches.count,
      catalogErrors: catalogErrors.sorted(),
      duplicateItemIDs: duplicateItemIDs,
      duplicateCatalogueIDs: duplicateCatalogueIDs,
      duplicateArchiveCatalogueIDs: duplicateArchiveCatalogueIDs,
      duplicateImportBatchIDs: duplicateImportBatchIDs,
      duplicateCommerceSnapshotIDs: duplicateCommerceSnapshotIDs,
      duplicateCommerceItemIDs: duplicateCommerceItemIDs,
      duplicateCommerceProductCodes: duplicateCommerceProductCodes,
      duplicateCoordinateIDs: duplicateCoordinateIDs,
      duplicateStoryIDs: duplicateStoryIDs,
      duplicateEventIDs: duplicateEventIDs,
      duplicateHistoryEntryIDs: duplicateHistoryEntryIDs,
      duplicateTimelineYears: duplicateTimelineYears,
      duplicateCanonicalKeys: duplicateKeys,
      duplicateCatalogueItemIDs: duplicateValues(allReferencedIDs),
      missingCatalogueItemIDs: Array(referencedIDs.subtracting(itemIDs)).sorted(),
      orphanItemIDs: Array(itemIDs.subtracting(referencedIDs)).sorted(),
      invalidCatalogueIDs: invalidCatalogueIDs,
      invalidArchiveCatalogueIDs: invalidArchiveCatalogueIDs,
      invalidImportBatchIDs: invalidImportBatchIDs,
      invalidCommerceSnapshotIDs: invalidCommerceSnapshotIDs,
      invalidCommerceItemIDs: invalidCommerceItemIDs,
      invalidCoordinateIDs: invalidCoordinateIDs,
      invalidStoryIDs: invalidStoryIDs,
      invalidEventIDs: invalidEventIDs,
      invalidHistoryEntryIDs: invalidHistoryEntryIDs,
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

  nonisolated private static func isOfficialCommerceImageURL(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    return url.scheme == "https"
      && url.host == "pinkhouse-webshop.jp"
      && url.path.hasPrefix("/photo/")
      && url.pathExtension.lowercased() == "jpg"
  }

  nonisolated private static func isOfficialCoordinateImageURL(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    return url.scheme == "https"
      && url.host == "pinkhouse-webshop.jp"
      && url.path.hasPrefix("/photo/coordinate/")
      && url.pathExtension.lowercased() == "jpg"
  }

  nonisolated private static func isOfficialStoryImageURL(_ value: String) -> Bool {
    guard let url = URL(string: value), url.scheme == "https", let host = url.host else {
      return false
    }
    if host == "pinkhouse-webshop.jp" {
      return url.path.hasPrefix("/photo/")
    }
    return host == "www.melrose.co.jp"
      && url.path.hasPrefix("/wp-content/themes/melrose/assets/images/50th/")
  }

  nonisolated private static func isOfficialNewsImageURL(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    return url.scheme == "https"
      && url.host == "pinkhouse-webshop.jp"
      && url.path.hasPrefix("/photo/news/")
      && ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased())
  }

  nonisolated private static func isOfficialHistoryImageURL(_ value: String) -> Bool {
    guard let url = URL(string: value) else { return false }
    return url.scheme == "https"
      && url.host == "www.melrose.co.jp"
      && url.path.hasPrefix("/wp-content/themes/melrose/assets/images/about/history/")
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

private enum TimeHallImageDownsampler {
  nonisolated static func load(
    url: URL,
    maxPixelDimension: CGFloat
  ) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: image)
  }
}
