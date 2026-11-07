import XCTest
import SwiftData
@testable import ItemManager

/// Makes a separate offline demo store for product photography on a simulator.
/// The regular app store and CloudKit are never destinations of this exporter.
final class StoreScreenshotFixtureTests: XCTestCase {
    @MainActor
    func testExportWardrobeFixture() throws {
        #if targetEnvironment(simulator)
        let documents = URL.documentsDirectory
        let folder = documents.appendingPathComponent("StoreScreenshotExport")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: folder.path))
        let url = folder.appendingPathComponent("wardrobe.store")
        try XCTSkipIf(FileManager.default.fileExists(atPath: url.path))
        let schema = SharedPersistence.sharedModelContainer.schema
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let names = ["Rose Thé", "Bluebell", "Herbier", "Nuit Marine"]
        for (i, name) in names.enumerated() {
            let amount = Decimal([328, 268, 398, 358][i])
            let planned = i >= 2
            let item = Clothing(name: name, types: i == 1 ? "JSK" : "OP",
                                sizes: "M", imagePaths: ["atelier-\(i).jpg"],
                                originalPrice: amount, price: amount,
                                deposit: planned ? 100 : 0, balance: planned ? amount - 100 : 0,
                                depositDate: planned ? Date() : nil, isDepositPlan: planned,
                                finalPaymentDate: planned ? Calendar.current.date(byAdding: .day, value: i * 3, to: Date()) : nil)
            item.sortIndex = i
            context.insert(item)
        }
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Clothing>()), 4)
        #else
        throw XCTSkip("Simulator screenshot fixture")
        #endif
    }
}
