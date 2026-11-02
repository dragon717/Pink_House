import XCTest
import AppKit
import SwiftData
@testable import PinkHouseOps

@MainActor
final class OpsInteractionPerformanceTests: XCTestCase {
    private func workspace() throws -> (ModelContainer, OpsWorkspace) {
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        return (store, OpsWorkspace(context: store.mainContext))
    }

    func testChangeCacheInvalidatesOnCatalogAndBaselineChanges() throws {
        let (store, workspace) = try workspace()
        _ = store
        workspace.catalog.products = [CatalogProduct(id: "p", shopID: "s", seriesID: "series", name: "原名", category: "OP")]
        workspace.draft?.baselineCatalog = workspace.catalog
        XCTAssertEqual(workspace.changeSet, ShopCatalogChangeSetCalculator.diff(baseline: workspace.baselineCatalog, current: workspace.catalog))
        workspace.catalog.products[0].name = "新名"
        XCTAssertEqual(workspace.changeSet, ShopCatalogChangeSetCalculator.diff(baseline: workspace.baselineCatalog, current: workspace.catalog))
        workspace.draft?.baselineCatalog = workspace.catalog
        XCTAssertEqual(workspace.changeSet, ShopCatalogChangeSetCalculator.diff(baseline: workspace.draft?.baselineCatalog, current: workspace.catalog))
        workspace.draft?.baselineCatalog = nil
        XCTAssertEqual(workspace.changeSet, ShopCatalogChangeSetCalculator.diff(baseline: nil, current: workspace.catalog))
    }

    func testColdPreviewResolvesInBackgroundAndNoticesRemoval() async throws {
        let (store, workspace) = try workspace()
        _ = store
        let directory = workspace.stagingDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("图片内容".utf8)
        let hash = ShopCatalogSyncProtocol.sha256Hex(bytes)
        let file = directory.appendingPathComponent(hash + ".png")
        try bytes.write(to: file)
        let reference = "thmedia:" + hash
        XCTAssertNil(workspace.previewFileURL(forReference: reference))
        for _ in 0..<100 {
            if workspace.previewFileURL(forReference: reference) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(workspace.previewFileURL(forReference: reference), file)
        XCTAssertEqual(workspace.stagedFileURL(forReference: reference), file)
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(workspace.previewFileURL(forReference: reference))
    }

    func testValidationCacheTracksChangesAndMatchesFullEntryValidation() {
        let cache = OpsSeriesEntryValidationCache()
        var entry = OpsSeriesTypeEntry(category: "OP")
        func expected(_ entry: OpsSeriesTypeEntry) -> [String] {
            var issues: [OpsSeriesEntryIssue] = []
            OpsSeriesEntryValidator.validateEntry(entry, into: &issues)
            return issues.map(\.message)
        }
        XCTAssertEqual(cache.issues(for: entry).map(\.message), expected(entry))
        entry.designName = "新款式"
        entry.usesSizeChart = false
        entry.stockPriceText = "200"
        entry.colors = [OpsSeriesColorSKU(name: "粉色")]
        XCTAssertEqual(cache.issues(for: entry).map(\.message), expected(entry))
        XCTAssertTrue(cache.issues(for: entry).isEmpty)
        entry.stockPriceText = "无效价格"
        XCTAssertEqual(cache.issues(for: entry).map(\.message), expected(entry))
        XCTAssertFalse(cache.issues(for: entry).isEmpty)
    }

    func testBackgroundImageLoadingDownsamplesAndRejectsReplacedOrMissingFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        let loader = OpsImageLoader()
        let first = await loader.load(file, pixels: 128)
        XCTAssertEqual(first?.image.width, 128)
        XCTAssertLessThanOrEqual(first?.image.height ?? 1000, 128)
        let cached = await loader.load(file, pixels: 128)
        // NSCache 可在内存压力下主动回收，正确性不依赖对象身份或必定命中缓存。
        XCTAssertEqual(cached?.image.width, first?.image.width)
        XCTAssertEqual(cached?.image.height, first?.image.height)
        try Data("损坏的图片".utf8).write(to: file, options: .atomic)
        let replaced = await loader.load(file, pixels: 128)
        XCTAssertNil(replaced)
        try FileManager.default.removeItem(at: file)
        let removed = await loader.load(file, pixels: 128)
        XCTAssertNil(removed)
    }
}
