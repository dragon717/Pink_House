import XCTest
@testable import SharedCatalog

final class ShopCatalogThreeWayMergeTests: XCTestCase {
    private let base = CatalogShop(id: "shop", name: "原名")

    func testIndependentFieldEditsSurvive() throws {
        var local = base, remote = base
        local.name = "本地新名"
        remote.aliases = ["云端别名"]
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [local]), remote: ShopCatalog(shops: [remote]),
            baseline: ShopCatalog(shops: [base]))
        XCTAssertEqual(result.catalog.shops[0].name, local.name)
        XCTAssertEqual(result.catalog.shops[0].aliases, remote.aliases)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertFalse(ShopCatalogChangeSetCalculator.diff(
            baseline: ShopCatalog(shops: [remote]), current: result.catalog).strictScopeIDs.isEmpty)
    }

    func testSameFieldConflictIsReported() throws {
        var local = base, remote = base
        local.name = "本地名"; remote.name = "远端名"
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [local]), remote: ShopCatalog(shops: [remote]),
            baseline: ShopCatalog(shops: [base]))
        XCTAssertEqual(result.conflicts, ["shops.shop.name"])
        XCTAssertEqual(result.catalog.shops[0].name, "远端名")
    }

    func testExplicitLocalConflictChoiceRemainsPendingUpload() throws {
        var local = base, remote = base
        local.name = "本地名"; remote.name = "远端名"
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [local]), remote: ShopCatalog(shops: [remote]),
            baseline: ShopCatalog(shops: [base]), preferLocalOnConflict: true)
        XCTAssertEqual(result.catalog.shops[0].name, "本地名")
        XCTAssertEqual(result.conflicts, ["shops.shop.name"])
        XCTAssertTrue(ShopCatalogChangeSetCalculator.diff(
            baseline: ShopCatalog(shops: [remote]), current: result.catalog).strictScopeIDs.contains("shop"))
    }

    func testUnknownBaselineNeverPretendsConflictWasResolved() throws {
        var local = base; local.name = "本地名"
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [local]), remote: ShopCatalog(shops: [base]), baseline: nil)
        XCTAssertEqual(result.conflicts, ["shops.shop.name"])
    }

    func testLocalAndRemoteOnlyEntitiesAreBothKept() throws {
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [base]),
            remote: ShopCatalog(shops: [CatalogShop(id: "remote", name: "远端")]), baseline: nil)
        XCTAssertEqual(Set(result.catalog.shops.map(\.id)), ["shop", "remote"])
    }

    func testLocalImageDeletionSurvivesUnchangedRemote() throws {
        var original = base; original.logo = "thmedia:" + String(repeating: "a", count: 64)
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [base]), remote: ShopCatalog(shops: [original]),
            baseline: ShopCatalog(shops: [original]))
        XCTAssertNil(result.catalog.shops[0].logo)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testPublishedMediaRenameDoesNotTurnLocalDeletionIntoConflict() throws {
        let hash = String(repeating: "a", count: 64)
        var original = base, remote = base
        original.logo = "local:img-abc.jpg"
        remote.logo = "thmedia:" + hash
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [base]), remote: ShopCatalog(shops: [remote]),
            baseline: ShopCatalog(shops: [original]),
            mediaHashesByLocalReference: ["local:img-abc.jpg": hash])
        XCTAssertNil(result.catalog.shops[0].logo)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testRemoteOnlyChangeIsAppliedWithoutConflict() throws {
        var remote = base; remote.name = "线上新名"
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [base]), remote: ShopCatalog(shops: [remote]),
            baseline: ShopCatalog(shops: [base]))
        XCTAssertEqual(result.catalog.shops[0].name, remote.name)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testTombstoneDoesNotResurrectEntitiesOrChildren() throws {
        let product = CatalogProduct(id: "p", shopID: "shop", seriesID: "s", name: "商品", category: "JSK")
        let remote = ShopCatalog(shops: [base], series: [CatalogSeries(id: "s", shopID: "shop", name: "系列")],
                                 products: [product], saleEvents: [CatalogSaleEvent(id: "event", productID: "p", type: .stock, price: 10)])
        let result = try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(removedShopIDs: ["shop"]), remote: remote, baseline: remote)
        XCTAssertTrue(result.catalog.shops.isEmpty)
        XCTAssertTrue(result.catalog.series.isEmpty)
        XCTAssertTrue(result.catalog.products.isEmpty)
        XCTAssertTrue(result.catalog.saleEvents.isEmpty)
        XCTAssertEqual(result.catalog.removedProductIDs, ["p"])
        XCTAssertTrue(ShopCatalogCloudSyncValidator.structuralIssues(result.catalog, coverageStatus: "empty").isEmpty)
    }

    func testDuplicateIDsRefuseMerge() {
        XCTAssertThrowsError(try ShopCatalogThreeWayMerge.merge(
            local: ShopCatalog(shops: [base, base]), remote: ShopCatalog(), baseline: nil))
    }
}
