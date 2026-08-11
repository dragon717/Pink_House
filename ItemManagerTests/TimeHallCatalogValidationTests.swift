import CryptoKit
import XCTest
import UIKit

@testable import ItemManager

final class TimeHallCatalogValidationTests: XCTestCase {
  func testTimeHallUsesSharedFourTabMapping() {
    XCTAssertEqual(TimeHallMode.allCases.map(\.rawValue), [
      "chronicle", "styleSpray", "story", "coordinate",
    ])
    XCTAssertEqual(TimeHallMode.allCases.map(\.title), [
      "编年史".appLocalized,
      "图鉴手册".appLocalized,
      "珍选".appLocalized,
      "搭配".appLocalized,
    ])
  }

  func testCuratedBrandCatalogsDecodeAndBundleTheirImages() throws {
    let resourceNames = [
      "catalog-angelic-pretty",
      "catalog-baby-stars-shine-bright",
      "catalog-juliette-et-justine",
      "catalog-wunderwelt-fleur",
    ]

    for resourceName in resourceNames {
      let catalog = try loadCatalog(named: resourceName)
      let catalogueIDs = Set(catalog.catalogues.map(\.id))
      let itemIDs = Set(catalog.items.map(\.id))

      XCTAssertFalse(catalog.timelineYears.isEmpty, resourceName)
      XCTAssertFalse(catalog.catalogues.isEmpty, resourceName)
      XCTAssertFalse(catalog.items.isEmpty, resourceName)
      XCTAssertFalse(catalog.scope.labelZH.isEmpty, resourceName)
      XCTAssertTrue(
        Set(catalog.timelineYears.flatMap(\.catalogueIDs)).isSubset(of: catalogueIDs),
        resourceName
      )
      XCTAssertTrue(
        Set(catalog.catalogues.flatMap(\.itemIds)).isSubset(of: itemIDs),
        resourceName
      )
      XCTAssertTrue(
        Set(catalog.items.map(\.catalogueID)).isSubset(of: catalogueIDs),
        resourceName
      )
      XCTAssertTrue(
        itemIDs.isSubset(of: Set(catalog.catalogues.flatMap(\.itemIds))),
        resourceName
      )

      let imageNames = Set(
        [catalog.heroImage].compactMap { $0 }
          + catalog.catalogues.map(\.coverImage)
          + catalog.items.compactMap(\.coverImage)
          + catalog.commerceItems.map(\.coverImage)
          + catalog.coordinates.map(\.coverImage)
          + catalog.stories.map(\.coverImage)
      )
      XCTAssertTrue(catalog.commerceItems.allSatisfy { !$0.coverImage.isEmpty }, resourceName)
      for imageName in imageNames {
        XCTAssertNotNil(imageURL(named: imageName), "Missing \(resourceName) image: \(imageName)")
      }
    }

    for imageName in [
      "store-angelic-pretty-tokyo.png",
      "store-angelic-pretty-osaka.png",
      "store-angelic-pretty-paris.png",
      "store-baby-honten.png",
      "store-baby-osaka.png",
      "store-baby-yokohama.png",
    ] {
      let url = imageURL(named: imageName)
      XCTAssertNotNil(url, "Missing storefront image: \(imageName)")
      let alphaInfo = url.flatMap { UIImage(contentsOfFile: $0.path)?.cgImage?.alphaInfo }
      XCTAssertTrue(
        [.first, .last, .premultipliedFirst, .premultipliedLast].contains(alphaInfo),
        "Storefront image must contain alpha: \(imageName)"
      )
    }
  }

  func testBundledCatalogHasExpectedSixBatchesAndPassesIntegrityChecks() throws {
    let catalog = try loadCatalog()
    let report = TimeHallCatalogStore.validate(catalog)

    XCTAssertTrue(report.isCatalogValid, "Validation report: \(report)")
    XCTAssertEqual(report.dressCount, 29)
    XCTAssertEqual(report.clothingCount, 15)
    XCTAssertEqual(report.accessoryCount, 30)
    XCTAssertEqual(report.catalogueCount, 3)
    XCTAssertEqual(report.timelineYearCount, 55)
    XCTAssertEqual(report.archiveCatalogueCount, 47)
    XCTAssertEqual(report.commerceSnapshotCount, 1)
    XCTAssertEqual(report.commerceItemCount, 308)
    XCTAssertEqual(report.coordinateCount, 150)
    XCTAssertEqual(report.storyCount, 36)
    XCTAssertEqual(report.eventCount, 721)
    XCTAssertEqual(report.historyEntryCount, 6)
    XCTAssertEqual(report.importBatchCount, 6)
    XCTAssertEqual(catalog.scope.startYear, 1972)
    XCTAssertNil(catalog.scope.endYear)
    XCTAssertEqual(catalog.timelineYears.map(\.year).sorted(), Array(1972...2026))
    XCTAssertEqual(Set(catalog.archiveCatalogues.map(\.year)), Set(2015...2026))
  }

  func testDuplicateIdentityFailsValidation() throws {
    let catalog = try loadCatalog()
    let duplicatedItem = try XCTUnwrap(catalog.items.first)
    let duplicated = TimeHallCatalogDTO(
      version: catalog.version,
      source: catalog.source,
      title: catalog.title,
      subtitle: catalog.subtitle,
      heroImage: catalog.heroImage,
      heroCaption: catalog.heroCaption,
      heroBody: catalog.heroBody,
      scope: catalog.scope,
      timelineYears: catalog.timelineYears,
      archiveCatalogues: catalog.archiveCatalogues,
      catalogues: catalog.catalogues,
      items: catalog.items + [duplicatedItem],
      commerceSnapshots: catalog.commerceSnapshots,
      commerceItems: catalog.commerceItems,
      coordinates: catalog.coordinates,
      stories: catalog.stories,
      events: catalog.events,
      historyEntries: catalog.historyEntries,
      importBatches: catalog.importBatches
    )

    let report = TimeHallCatalogStore.validate(duplicated)
    XCTAssertFalse(report.isCatalogValid)
    XCTAssertEqual(report.duplicateItemIDs, [duplicatedItem.id])
    XCTAssertEqual(report.duplicateCanonicalKeys.count, 1)
  }

  func testEveryTimeHallImageIsBundledAndContentIsUnique() throws {
    let catalog = try loadCatalog()
    let fileNames = Set(
      catalog.archiveCatalogues.map(\.coverImage)
        + catalog.catalogues.map(\.coverImage)
        + catalog.items.compactMap(\.coverImage)
        + catalog.items.flatMap(\.gallery)
        + catalog.commerceItems.map(\.coverImage)
        + catalog.commerceItems.compactMap(\.detailImage)
        + catalog.coordinates.map(\.coverImage)
        + catalog.stories.map(\.coverImage)
        + catalog.events.map(\.coverImage)
        + catalog.historyEntries.compactMap(\.coverImage)
    )

    XCTAssertEqual(fileNames.count, 843)
    var digests = Set<String>()
    for fileName in fileNames {
      let url = try XCTUnwrap(
        imageURL(named: fileName),
        "Missing bundled TimeHall image: \(fileName)"
      )
      let digest = SHA256.hash(data: try Data(contentsOf: url))
        .map { String(format: "%02x", $0) }
        .joined()
      XCTAssertTrue(digests.insert(digest).inserted, "Duplicate TimeHall image: \(fileName)")
    }
  }

  func testFirstImportBatchOwnsComplete2026SummerCatalogue() throws {
    let catalog = try loadCatalog()
    let batch = try XCTUnwrap(catalog.importBatches.first)
    XCTAssertEqual(batch.id, "catalogue-2026-summer")
    XCTAssertEqual(batch.order, 1)
    XCTAssertEqual(batch.catalogueIDs, ["pink-house-2026-summer"])
    XCTAssertTrue(batch.commerceSnapshotIDs.isEmpty)
    XCTAssertTrue(batch.coordinateIDs.isEmpty)
    XCTAssertTrue(batch.storyIDs.isEmpty)
    XCTAssertTrue(batch.eventIDs.isEmpty)
    XCTAssertTrue(batch.historyEntryIDs.isEmpty)
    XCTAssertEqual(batch.itemCount, 44)

    let catalogue = try XCTUnwrap(
      catalog.catalogues.first { $0.id == "pink-house-2026-summer" })
    XCTAssertEqual(catalogue.pageCount, 25)
    XCTAssertEqual(catalogue.itemIds.count, 44)

    let items = catalog.items.filter { $0.catalogueID == catalogue.id }
    XCTAssertEqual(items.count, 44)
    XCTAssertTrue(items.allSatisfy { !$0.gallery.isEmpty })
    XCTAssertTrue(items.allSatisfy { $0.cataloguePages?.contains($0.cataloguePage) == true })
    XCTAssertGreaterThan(items.compactMap(\.productCode).count, 20)
  }

  func testSecondImportBatchOwnsCurrentAndOutletSnapshot() throws {
    let catalog = try loadCatalog()
    let batch = try XCTUnwrap(catalog.importBatches.first { $0.order == 2 })
    XCTAssertEqual(batch.id, "commerce-current-outlet")
    XCTAssertEqual(batch.kind, "commerceSnapshot")
    XCTAssertTrue(batch.catalogueIDs.isEmpty)
    XCTAssertEqual(batch.itemCount, 308)
    XCTAssertEqual(batch.commerceSnapshotIDs, ["commerce-2026-08-01"])
    XCTAssertTrue(batch.coordinateIDs.isEmpty)
    XCTAssertTrue(batch.storyIDs.isEmpty)
    XCTAssertTrue(batch.eventIDs.isEmpty)
    XCTAssertTrue(batch.historyEntryIDs.isEmpty)

    let snapshot = try XCTUnwrap(
      catalog.commerceSnapshots.first { $0.id == batch.commerceSnapshotIDs[0] })
    XCTAssertEqual(snapshot.currentItemIDs.count, 295)
    XCTAssertEqual(snapshot.outletItemIDs.count, 13)
    XCTAssertEqual(snapshot.itemIDs.count, 308)

    XCTAssertEqual(catalog.commerceItems.count, 308)
    XCTAssertEqual(Set(catalog.commerceItems.map(\.productCode)).count, 308)
    XCTAssertEqual(catalog.commerceItems.filter { $0.salePriceJPY != nil }.count, 49)
    XCTAssertTrue(catalog.commerceItems.allSatisfy { !$0.description.isEmpty })
    XCTAssertTrue(catalog.commerceItems.allSatisfy { !$0.imageSourceURLs.isEmpty })
    XCTAssertTrue(catalog.commerceItems.allSatisfy { $0.detailImage != nil })
  }

  func testThirdImportBatchOwnsOfficialCoordinateArchive() throws {
    let catalog = try loadCatalog()
    let batch = try XCTUnwrap(catalog.importBatches.first { $0.order == 3 })
    XCTAssertEqual(batch.id, "coordinate-current")
    XCTAssertEqual(batch.kind, "coordinate")
    XCTAssertEqual(batch.itemCount, 150)
    XCTAssertEqual(batch.coordinateIDs.count, 150)
    XCTAssertTrue(batch.catalogueIDs.isEmpty)
    XCTAssertTrue(batch.commerceSnapshotIDs.isEmpty)
    XCTAssertTrue(batch.storyIDs.isEmpty)
    XCTAssertTrue(batch.eventIDs.isEmpty)
    XCTAssertTrue(batch.historyEntryIDs.isEmpty)

    XCTAssertEqual(catalog.coordinates.count, 150)
    XCTAssertEqual(Set(catalog.coordinates.map(\.officialID)).count, 150)
    XCTAssertEqual(catalog.coordinates.flatMap(\.productCodes).count, 131)
    XCTAssertEqual(catalog.coordinates.filter { !$0.linkedCommerceItemIDs.isEmpty }.count, 28)
    XCTAssertTrue(catalog.coordinates.allSatisfy { !$0.coordinatePoint.isEmpty })
    XCTAssertTrue(catalog.coordinates.allSatisfy { !$0.coverImage.isEmpty })
  }

  func testFourthImportBatchOwnsFeatureAndCraftStories() throws {
    let catalog = try loadCatalog()
    let batch = try XCTUnwrap(catalog.importBatches.first { $0.order == 4 })
    XCTAssertEqual(batch.id, "feature-craft")
    XCTAssertEqual(batch.kind, "story")
    XCTAssertEqual(batch.itemCount, 36)
    XCTAssertEqual(batch.storyIDs.count, 36)
    XCTAssertTrue(batch.catalogueIDs.isEmpty)
    XCTAssertTrue(batch.commerceSnapshotIDs.isEmpty)
    XCTAssertTrue(batch.coordinateIDs.isEmpty)
    XCTAssertTrue(batch.eventIDs.isEmpty)
    XCTAssertTrue(batch.historyEntryIDs.isEmpty)

    XCTAssertEqual(catalog.stories.filter { $0.kind == .feature }.count, 35)
    XCTAssertEqual(catalog.stories.filter { $0.kind == .craft }.count, 1)
    XCTAssertEqual(catalog.stories.flatMap(\.imageSourceURLs).count, 525)
    XCTAssertTrue(catalog.stories.allSatisfy { !$0.content.isEmpty })
    XCTAssertTrue(catalog.stories.allSatisfy { !$0.coverImage.isEmpty })
    let craft = try XCTUnwrap(catalog.stories.first { $0.kind == .craft })
    XCTAssertTrue(craft.content.contains("13〜15版"))
    XCTAssertTrue(craft.content.contains("1200種類"))
  }

  func testFifthImportBatchOwnsCompleteOfficialNewsTimeline() throws {
    let catalog = try loadCatalog()
    let batch = try XCTUnwrap(catalog.importBatches.first { $0.order == 5 })
    XCTAssertEqual(batch.id, "news-timeline")
    XCTAssertEqual(batch.kind, "news")
    XCTAssertEqual(batch.itemCount, 721)
    XCTAssertEqual(batch.eventIDs.count, 721)
    XCTAssertTrue(batch.historyEntryIDs.isEmpty)

    XCTAssertEqual(catalog.events.count, 721)
    XCTAssertEqual(catalog.events.filter { $0.kind == .information }.count, 140)
    XCTAssertEqual(catalog.events.filter { $0.kind == .event }.count, 581)
    XCTAssertEqual(catalog.events.flatMap(\.imageSourceURLs).count, 2634)
    XCTAssertEqual(catalog.events.map(\.publishedOn).min(), "2020-11-04")
    XCTAssertEqual(catalog.events.map(\.publishedOn).max(), "2026-07-31")
    XCTAssertTrue(catalog.events.allSatisfy { !$0.content.isEmpty })
  }

  func testSixthImportBatchOwnsOfficialHistoryEvidence() throws {
    let catalog = try loadCatalog()
    let batch = try XCTUnwrap(catalog.importBatches.first { $0.order == 6 })
    XCTAssertEqual(batch.id, "history-evidence")
    XCTAssertEqual(batch.kind, "history")
    XCTAssertEqual(batch.itemCount, 6)
    XCTAssertEqual(batch.historyEntryIDs.count, 6)

    XCTAssertEqual(catalog.historyEntries.map(\.year), [1972, 1982, 1983, 1985, 2004, 2011])
    XCTAssertEqual(catalog.historyEntries.compactMap(\.coverImage).count, 3)
    XCTAssertTrue(catalog.historyEntries.allSatisfy { !$0.content.isEmpty })
  }

  func testYearsWithoutOfficialImagesUseExplicitStoryCards() throws {
    let catalog = try loadCatalog()
    let recordsByYear = Dictionary(
      uniqueKeysWithValues: catalog.timelineYears.map { ($0.year, $0) })

    let gap = try XCTUnwrap(recordsByYear[1997])
    XCTAssertEqual(gap.kind, .archiveGap)
    XCTAssertEqual(gap.evidenceLevel, .archiveGap)
    XCTAssertTrue(gap.catalogueIDs.isEmpty)
    XCTAssertTrue(gap.sourceURLs.isEmpty)

    let origin = try XCTUnwrap(recordsByYear[1972])
    XCTAssertEqual(origin.kind, .milestone)
    XCTAssertEqual(origin.evidenceLevel, .officialHistory)
    XCTAssertFalse(origin.sourceURLs.isEmpty)

    let current = try XCTUnwrap(recordsByYear[2026])
    XCTAssertEqual(current.kind, .officialArchive)
    XCTAssertEqual(current.catalogueIDs.count, 3)
  }

  private func loadCatalog(named resourceName: String = "catalog") throws -> TimeHallCatalogDTO {
    let candidates = [
      Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: "TimeHall"),
      Bundle.main.url(forResource: resourceName, withExtension: "json"),
      Bundle(for: Self.self).url(forResource: resourceName, withExtension: "json"),
    ]
    let url = try XCTUnwrap(candidates.compactMap { $0 }.first)
    return try JSONDecoder().decode(TimeHallCatalogDTO.self, from: Data(contentsOf: url))
  }

  private func imageURL(named fileName: String) -> URL? {
    let candidates = [
      Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "TimeHall/images"),
      Bundle.main.url(forResource: fileName, withExtension: nil),
      Bundle(for: Self.self).url(forResource: fileName, withExtension: nil),
    ]
    return candidates.compactMap { $0 }.first
  }
}
