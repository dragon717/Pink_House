import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsEnvironmentPromotionTests: XCTestCase {
    private let shop = CatalogShop(id: "shop", name: "店家")
    private let series = CatalogSeries(id: "series", shopID: "shop", name: "系列")
    private func product(_ id: String, name: String = "商品") -> CatalogProduct {
        CatalogProduct(id: id, shopID: "shop", seriesID: "series", name: name, category: "JSK")
    }

    func testUnionKeepsProductionOnlyProductsAndSales() throws {
        let source = ShopCatalog(shops: [shop], series: [series], products: [product("new")])
        let target = ShopCatalog(shops: [shop], series: [series], products: [product("old")],
            saleEvents: [.init(id: "event", productID: "old", type: .stock, price: 100, currency: .cny)])
        let plan = try OpsEnvironmentPromotion.plan(development: source, production: target, choice: .development)
        XCTAssertEqual(Set(plan.catalog.products.map(\.id)), ["new", "old"])
        XCTAssertEqual(plan.catalog.saleEvents, target.saleEvents)
        XCTAssertEqual(plan.added, 1)
        XCTAssertEqual(plan.rows.first { $0.kind == .product }?.retained, 1)
        XCTAssertTrue(ShopCatalogCloudSyncValidator.structuralIssues(plan.catalog, coverageStatus: "complete").isEmpty)
    }

    func testSameIDDifferenceUsesExplicitChoice() throws {
        let source = ShopCatalog(shops: [CatalogShop(id: "shop", name: "开发名称")])
        let target = ShopCatalog(shops: [shop])
        let incoming = try OpsEnvironmentPromotion.plan(development: source, production: target, choice: .development)
        let keeping = try OpsEnvironmentPromotion.plan(development: source, production: target, choice: .production)
        XCTAssertEqual(incoming.catalog.shops[0].name, "开发名称")
        XCTAssertEqual(incoming.updated, 1)
        XCTAssertEqual(incoming.differences, ["shops.shop.name"])
        XCTAssertEqual(incoming.differenceDescriptions, ["店家「开发名称」名称：线上 店家 → 开发 开发名称"])
        XCTAssertEqual(keeping.catalog, target)
        XCTAssertFalse(keeping.hasChanges)
    }

    func testRepeatedPromotionHasNoChangesOrDuplicateEntities() throws {
        let source = ShopCatalog(shops: [shop], series: [series], products: [product("p")])
        let once = try OpsEnvironmentPromotion.plan(development: source, production: ShopCatalog(), choice: .development)
        let twice = try OpsEnvironmentPromotion.plan(development: source, production: once.catalog, choice: .development)
        XCTAssertFalse(twice.hasChanges)
        XCTAssertTrue(twice.differences.isEmpty)
        XCTAssertEqual(twice.catalog.products.count, 1)
    }

    func testDevelopmentDeletionCannotRemoveProductionContent() throws {
        let target = ShopCatalog(shops: [shop], series: [series], products: [product("p")])
        let source = ShopCatalog(removedShopIDs: ["shop"], removedProductIDs: ["p"])
        let plan = try OpsEnvironmentPromotion.plan(development: source, production: target, choice: .development)
        XCTAssertEqual(plan.catalog, target)
        XCTAssertFalse(plan.hasChanges)
    }

    func testProductionTombstoneCannotBeResurrectedByDevelopment() throws {
        let source = ShopCatalog(shops: [shop], series: [series], products: [product("p")])
        let target = ShopCatalog(shops: [shop], series: [series], removedProductIDs: ["p"])
        let plan = try OpsEnvironmentPromotion.plan(development: source, production: target, choice: .development)
        XCTAssertTrue(plan.catalog.products.isEmpty)
        XCTAssertEqual(plan.catalog.removedProductIDs, ["p"])
    }

    func testProductionDeletionDoesNotRepeatedlyMigrateUnpublishableSourceSales() throws {
        let source = ShopCatalog(shops: [shop], series: [series], products: [product("p")],
            saleEvents: [.init(id: "new-history", productID: "p", type: .stock, price: 100)])
        let target = ShopCatalog(shops: [shop], series: [series], removedProductIDs: ["p"])
        let plan = try OpsEnvironmentPromotion.plan(development: source, production: target, choice: .development)
        XCTAssertTrue(plan.catalog.saleEvents.isEmpty)
        XCTAssertFalse(plan.hasChanges)
        var withHistory = target
        withHistory.saleEvents = [.init(id: "old-history", productID: "p", type: .stock, price: 90)]
        let keeping = try OpsEnvironmentPromotion.plan(development: source, production: withHistory, choice: .development)
        XCTAssertEqual(keeping.catalog.saleEvents, withHistory.saleEvents)
        XCTAssertFalse(keeping.hasChanges)
    }

    func testJSONDatePrecisionDoesNotCountAsAnUpdateOnRepeatedPromotion() throws {
        var event = CatalogSaleEvent(id: "history", productID: "p", type: .stock, price: 100)
        event.startAt = Date(timeIntervalSince1970: 1_000.123456)
        let source = ShopCatalog(shops: [shop], series: [series], products: [product("p")], saleEvents: [event])
        let plan = try OpsEnvironmentPromotion.plan(development: source, production: source, choice: .development)
        XCTAssertFalse(plan.hasChanges)
        XCTAssertTrue(plan.differences.isEmpty)
    }

    func testPersistedDecimalValuesDoNotCountAsRepeatedUpdatesButEditsStillDo() throws {
        let events = [0.1, 25.3, 378.9, 189.99, 888.88].enumerated().map { index, price in
            CatalogSaleEvent(id: "event-\(index)", productID: "p", type: .stock, price: price)
        }
        let source = ShopCatalog(shops: [shop], series: [series], products: [product("p")], saleEvents: events)
        let repeated = try OpsEnvironmentPromotion.plan(development: source, production: source, choice: .development)
        XCTAssertFalse(repeated.hasChanges)
        var edited = source
        edited.saleEvents[0].price = 101
        let change = try OpsEnvironmentPromotion.plan(development: edited, production: source, choice: .development)
        XCTAssertEqual(change.updated, 1)
    }

    func testDuplicateIDsStopPromotion() {
        XCTAssertThrowsError(try OpsEnvironmentPromotion.plan(
            development: ShopCatalog(shops: [shop, shop]), production: ShopCatalog(), choice: .development))
    }

    func testOnlyNewMediaNeedsDownloadingAndArchiveVerifiesBytes() throws {
        let data = Data("图片内容".utf8)
        let hash = ShopCatalogSyncProtocol.sha256Hex(data)
        let targetHash = String(repeating: "a", count: 64)
        var sourceShop = shop
        sourceShop.logo = "thmedia:" + hash
        var targetShop = CatalogShop(id: "target", name: "线上独有店家")
        targetShop.logo = "thmedia:" + targetHash
        let plan = try OpsEnvironmentPromotion.plan(development: ShopCatalog(shops: [sourceShop]),
            production: ShopCatalog(shops: [targetShop]), choice: .development)
        XCTAssertEqual(plan.requiredSourceMedia, [hash])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try OpsEnvironmentPromotion.archive(plan: plan, mediaDirectory: directory))
        let image = directory.appendingPathComponent(hash + ".png")
        try data.write(to: image)
        let archive = try OpsEnvironmentPromotion.archive(plan: plan, mediaDirectory: directory)
        XCTAssertTrue(archive.range(of: Data(("images/" + hash + ".png").utf8)) != nil)
        let duplicate = directory.appendingPathComponent(hash + ".jpg")
        try Data("损坏副本".utf8).write(to: duplicate)
        XCTAssertNoThrow(try OpsEnvironmentPromotion.archive(plan: plan, mediaDirectory: directory))
        try Data("损坏".utf8).write(to: image)
        XCTAssertThrowsError(try OpsEnvironmentPromotion.archive(plan: plan, mediaDirectory: directory))
        let repeated = try OpsEnvironmentPromotion.plan(development: plan.catalog, production: plan.catalog, choice: .development)
        XCTAssertTrue(repeated.requiredSourceMedia.isEmpty)
    }

    func testLegacyLocalImageReferenceStopsPublication() throws {
        var sourceShop = shop; sourceShop.logo = "local:old.png"
        let plan = try OpsEnvironmentPromotion.plan(development: ShopCatalog(shops: [sourceShop]),
            production: ShopCatalog(), choice: .development)
        XCTAssertThrowsError(try OpsEnvironmentPromotion.archive(plan: plan, mediaDirectory: URL(fileURLWithPath: "/tmp")))
    }

    func testChineseEnvironmentNamesKeepProtocolRawValues() {
        XCTAssertEqual(ShopCatalogPublishTargetEnvironment.development.displayName, "开发环境 Development")
        XCTAssertEqual(ShopCatalogPublishTargetEnvironment.production.displayName, "线上环境 Production")
        XCTAssertEqual(ShopCatalogPublishTargetEnvironment.development.rawValue, "development")
        XCTAssertEqual(ShopCatalogPublishTargetEnvironment.production.rawValue, "production")
    }
}
