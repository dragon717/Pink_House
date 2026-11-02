import Foundation
import SwiftData
import SharedCatalog
import PinkHouseOpsCore
@testable import PinkHouseOps

/// 同一二进制比较旧调用方式与当前缓存路径，不接触正式库或网络。
@MainActor
enum OpsInteractionPerformance {
    static func run(into output: URL) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ops-perf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var hashes: [String] = []
        for n in 0..<656 {
            var bytes = Data(repeating: UInt8(n % 251), count: 65_536)
            bytes.append(Data(String(n).utf8))
            let hash = ShopCatalogSyncProtocol.sha256Hex(bytes)
            hashes.append(hash)
            try bytes.write(to: directory.appendingPathComponent(hash + ".jpg"))
        }
        var metrics: [String: [String: Double]] = [:]
        func measure(_ name: String, count: Int = 100, operation: () -> Void) {
            var elapsed: [Double] = []
            for _ in 0..<count {
                let start = ContinuousClock.now
                operation()
                let duration = start.duration(to: .now).components
                elapsed.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            }
            elapsed.sort()
            metrics[name] = ["p50_ms": elapsed[count / 2], "p95_ms": elapsed[min(count - 1, Int(Double(count) * 0.95))], "max_ms": elapsed.last!]
            print("PERF \(name): \(metrics[name]!)")
        }
        let lookup = OpsCachedMediaLookup()
        measure("media_cold", count: 1) { _ = lookup.file(in: directory, hash: hashes[320]) }
        measure("media_legacy") { _ = OpsCachedMedia.files(in: directory, hash: hashes[320])[hashes[320]] }
        measure("media_cached") { _ = lookup.file(in: directory, hash: hashes[320]) }
        let entries = (0..<32).map { n in
            OpsSeriesTypeEntry(category: "OP", designName: "款式\(n)",
                chartColumnsText: CatalogChartTemplate.SizeChart.columnsText,
                chartRowsText: CatalogChartTemplate.SizeChart.rowsText, stockPriceText: "200",
                colors: [OpsSeriesColorSKU(name: "粉", selectedSizes: CatalogChartTemplate.SizeChart.sizeLabels)])
        }
        let draft = OpsSeriesEntryDraft(newSeriesName: "测试", typeEntries: entries)
        let validation = OpsSeriesEntryValidationCache()
        for entry in entries { _ = validation.issues(for: entry) }
        measure("validation_legacy", count: 30) {
            for entry in entries { _ = OpsSeriesEntryValidator.validate(draft, catalog: ShopCatalog()).filter { $0.entryID == entry.id } }
        }
        measure("validation_cached") { for entry in entries { _ = validation.issues(for: entry) } }
        var edited = entries[0]
        measure("validation_single_edit") {
            edited.designName.append("字")
            _ = validation.issues(for: edited)
        }
        let schema = Schema([OpsCatalogDraftRecord.self, OpsSeriesPublishJob.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let workspace = OpsWorkspace(context: store.mainContext)
        workspace.catalog.products = (0..<431).map { CatalogProduct(id: "p\($0)", shopID: "s", seriesID: "series", name: "商品\($0)", category: "OP") }
        workspace.draft?.baselineCatalog = workspace.catalog
        _ = workspace.changeSet
        measure("changes_legacy", count: 30) {
            _ = ShopCatalogChangeSetCalculator.diff(baseline: workspace.draft?.baselineCatalog, current: workspace.catalog)
        }
        measure("changes_cached") { _ = workspace.changeSet }
        let data = try JSONSerialization.data(withJSONObject: [
            "scope": "in-process hot paths; excludes display refresh, disk save, network and cold decode",
            "fixture": ["mediaFiles": 656, "bytesPerFile": 65_536, "entries": 32, "products": 431],
            "metrics": metrics,
        ], options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
    }
}
