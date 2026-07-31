import XCTest

@testable import ItemManager

final class TimeHallCatalogValidationTests: XCTestCase {
  func testBundledSampleHasExpectedCountsAndPassesIntegrityChecks() throws {
    let catalog = try loadCatalog()
    let report = TimeHallCatalogStore.validate(catalog)

    XCTAssertTrue(report.isSampleValid, "Validation report: \(report)")
    XCTAssertEqual(report.dressCount, 20)
    XCTAssertEqual(report.accessoryCount, 10)
    XCTAssertEqual(report.catalogueCount, 2)
    XCTAssertEqual(report.timelineYearCount, 55)
    XCTAssertEqual(report.archiveCatalogueCount, 47)
    XCTAssertEqual(catalog.scope.startYear, 1972)
    XCTAssertNil(catalog.scope.endYear)
    XCTAssertEqual(catalog.timelineYears.map(\.year).sorted(), Array(1972...2026))
    XCTAssertEqual(Set(catalog.archiveCatalogues.map(\.year)), Set(2015...2026))
  }

  func testDuplicateIdentityFailsValidation() throws {
    let catalog = try loadCatalog()
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
      items: catalog.items + [try XCTUnwrap(catalog.items.first)]
    )

    let report = TimeHallCatalogStore.validate(duplicated)
    XCTAssertFalse(report.isSampleValid)
    XCTAssertEqual(report.duplicateItemIDs, ["ph24s-d01"])
    XCTAssertEqual(report.duplicateCanonicalKeys.count, 1)
  }

  func testEveryCatalogueAndItemImageIsBundled() throws {
    let catalog = try loadCatalog()
    let fileNames = Set(
      catalog.archiveCatalogues.map(\.coverImage)
        + catalog.catalogues.map(\.coverImage)
        + catalog.items.compactMap(\.coverImage)
    )

    XCTAssertEqual(fileNames.count, 69)
    for fileName in fileNames {
      XCTAssertNotNil(imageURL(named: fileName), "Missing bundled TimeHall image: \(fileName)")
    }
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

  private func loadCatalog() throws -> TimeHallCatalogDTO {
    let candidates = [
      Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "TimeHall"),
      Bundle.main.url(forResource: "catalog", withExtension: "json"),
      Bundle(for: Self.self).url(forResource: "catalog", withExtension: "json"),
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
