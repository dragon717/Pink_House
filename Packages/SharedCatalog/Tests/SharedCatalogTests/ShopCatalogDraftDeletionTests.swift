import XCTest
@testable import SharedCatalog

final class ShopCatalogDraftDeletionTests: XCTestCase {
    private func fixture() -> ShopCatalog {
        let products = [
            CatalogProduct(id: "p1", shopID: "shop1", seriesID: "series1", name: "白色", category: "OP"),
            CatalogProduct(id: "p2", shopID: "shop1", seriesID: "series1", name: "黑色", category: "OP",
                           archivedAt: Date(timeIntervalSince1970: 1)),
            CatalogProduct(id: "p3", shopID: "shop1", seriesID: "series2", name: "裙子", category: "JSK"),
            CatalogProduct(id: "p4", shopID: "shop2", seriesID: "series3", name: "其他店商品", category: "OP")
        ]
        return ShopCatalog(
            shops: [CatalogShop(id: "shop1", name: "测试店家"), CatalogShop(id: "shop2", name: "其他店")],
            series: [CatalogSeries(id: "series1", shopID: "shop1", name: "系列一"),
                     CatalogSeries(id: "series2", shopID: "shop1", name: "系列二"),
                     CatalogSeries(id: "series3", shopID: "shop2", name: "其他系列")],
            products: products,
            variants: products.map { CatalogProductVariant(id: "v-\($0.id)", productID: $0.id) },
            sizeCharts: products.map { CatalogSizeChart(id: "size-\($0.id)", productID: $0.id) },
            saleEvents: products.map {
                CatalogSaleEvent(id: "sale-\($0.id)", productID: $0.id, type: .stock, price: 200)
            },
            assets: [CatalogAsset(id: "shared-image", type: .productImage, originalURL: "https://example.com/image.png")],
            styleProfiles: ["series1", "series2", "series3"].map {
                CatalogStyleProfile(id: "style-\($0)", seriesID: $0, category: "OP", designName: "裙子")
            })
    }

    func testSeriesDeletionIncludesArchivedProductsAndAllDependentRecords() throws {
        var catalog = fixture()
        let original = catalog
        let summary = try XCTUnwrap(ShopCatalogDraftDeletion.removeSeries(id: "series1", from: &catalog))

        XCTAssertEqual(summary.seriesCount, 1)
        XCTAssertEqual(summary.productCount, 2)
        XCTAssertEqual(catalog.shops, original.shops)
        XCTAssertEqual(catalog.series.map(\.id), ["series2", "series3"])
        XCTAssertEqual(catalog.products.map(\.id), ["p3", "p4"])
        XCTAssertEqual(catalog.variants.map(\.productID), ["p3", "p4"])
        XCTAssertEqual(catalog.sizeCharts.map(\.productID), ["p3", "p4"])
        XCTAssertEqual(catalog.saleEvents.map(\.productID), ["p3", "p4"])
        XCTAssertEqual(catalog.styleProfiles.map(\.seriesID), ["series2", "series3"])
        XCTAssertEqual(catalog.assets, original.assets)
        XCTAssertEqual(catalog.removedShopIDs, [])
        XCTAssertEqual(catalog.removedSeriesIDs, ["series1"])
        XCTAssertEqual(catalog.removedProductIDs, ["p1", "p2"])
    }

    func testShopDeletionPreservesOtherShopAndSharedAssets() throws {
        var catalog = fixture()
        let original = catalog
        let summary = try XCTUnwrap(ShopCatalogDraftDeletion.removeShop(id: "shop1", from: &catalog))

        XCTAssertEqual(summary.seriesCount, 2)
        XCTAssertEqual(summary.productCount, 3)
        XCTAssertEqual(catalog.shops, [original.shops[1]])
        XCTAssertEqual(catalog.series, [original.series[2]])
        XCTAssertEqual(catalog.products, [original.products[3]])
        XCTAssertEqual(catalog.variants, [original.variants[3]])
        XCTAssertEqual(catalog.sizeCharts, [original.sizeCharts[3]])
        XCTAssertEqual(catalog.saleEvents, [original.saleEvents[3]])
        XCTAssertEqual(catalog.styleProfiles, [original.styleProfiles[2]])
        XCTAssertEqual(catalog.assets, original.assets)
        XCTAssertEqual(catalog.removedShopIDs, ["shop1"])
        XCTAssertEqual(catalog.removedSeriesIDs, ["series1", "series2"])
        XCTAssertEqual(catalog.removedProductIDs, ["p1", "p2", "p3"])
    }

    func testShopDeletionUsesBothShopAndSeriesOwnershipForLegacyProducts() throws {
        var catalog = fixture()
        // 挂在目标系列但 shopID 错误，仍需随店家删除。
        catalog.products[0].shopID = "shop2"
        // 直接挂在目标店家但系列字段失效，也不能漏删。
        catalog.products[2].seriesID = "missing-series"
        let summary = try XCTUnwrap(ShopCatalogDraftDeletion.removeShop(id: "shop1", from: &catalog))
        XCTAssertEqual(summary.productCount, 3)
        XCTAssertEqual(catalog.products.map(\.id), ["p4"])
        XCTAssertEqual(catalog.removedProductIDs, ["p1", "p2", "p3"])
    }

    func testDeletingEmptyParentsStillRecordsTombstones() throws {
        var catalog = ShopCatalog(
            shops: [CatalogShop(id: "empty-shop", name: "空店家")],
            series: [CatalogSeries(id: "empty-series", shopID: "empty-shop", name: "空系列")])
        let series = try XCTUnwrap(ShopCatalogDraftDeletion.removeSeries(id: "empty-series", from: &catalog))
        XCTAssertEqual(series.productCount, 0)
        let shop = try XCTUnwrap(ShopCatalogDraftDeletion.removeShop(id: "empty-shop", from: &catalog))
        XCTAssertEqual(shop.seriesCount, 0)
        XCTAssertEqual(shop.productCount, 0)
        XCTAssertEqual(catalog.removedShopIDs, ["empty-shop"])
        XCTAssertEqual(catalog.removedSeriesIDs, ["empty-series"])
    }

    func testRepeatedOrMissingDeletionDoesNotChangeCatalogOrDuplicateTombstones() throws {
        var catalog = fixture()
        catalog.removedProductIDs = ["previous-product"]
        catalog.removedSeriesIDs = ["previous-series"]
        catalog.removedShopIDs = ["previous-shop"]
        XCTAssertTrue(ShopCatalogDraftDeletion.removeProduct(id: "p1", from: &catalog))
        XCTAssertNotNil(ShopCatalogDraftDeletion.removeSeries(id: "series1", from: &catalog))
        XCTAssertNotNil(ShopCatalogDraftDeletion.removeShop(id: "shop1", from: &catalog))
        XCTAssertEqual(catalog.removedProductIDs, ["previous-product", "p1", "p2", "p3"])
        XCTAssertEqual(catalog.removedSeriesIDs, ["previous-series", "series1", "series2"])
        XCTAssertEqual(catalog.removedShopIDs, ["previous-shop", "shop1"])
        let before = try ShopCatalogJSONCoding.encoder().encode(catalog)
        XCTAssertNil(ShopCatalogDraftDeletion.removeShop(id: "shop1", from: &catalog))
        XCTAssertNil(ShopCatalogDraftDeletion.removeSeries(id: "series1", from: &catalog))
        XCTAssertFalse(ShopCatalogDraftDeletion.removeProduct(id: "p1", from: &catalog))
        XCTAssertNil(ShopCatalogDraftDeletion.removeShop(id: "missing", from: &catalog))
        XCTAssertNil(ShopCatalogDraftDeletion.removeSeries(id: "missing", from: &catalog))
        XCTAssertEqual(try ShopCatalogJSONCoding.encoder().encode(catalog), before)
    }

    func testDeletingShopWithoutSeriesStillRemovesDirectProducts() throws {
        var catalog = fixture()
        catalog.series.removeAll { $0.shopID == "shop1" }
        let summary = try XCTUnwrap(ShopCatalogDraftDeletion.removeShop(id: "shop1", from: &catalog))
        XCTAssertEqual(summary.seriesCount, 0)
        XCTAssertEqual(summary.productCount, 3)
        XCTAssertEqual(catalog.products.map(\.id), ["p4"])
    }

    func testProductDeletionPreservesParentsAndSiblingRecords() {
        var catalog = fixture()
        let original = catalog
        XCTAssertTrue(ShopCatalogDraftDeletion.removeProduct(id: "p1", from: &catalog))
        XCTAssertEqual(catalog.shops, original.shops)
        XCTAssertEqual(catalog.series, original.series)
        XCTAssertEqual(catalog.styleProfiles, original.styleProfiles)
        XCTAssertEqual(catalog.products.map(\.id), ["p2", "p3", "p4"])
        XCTAssertEqual(catalog.variants.map(\.productID), ["p2", "p3", "p4"])
        XCTAssertEqual(catalog.sizeCharts.map(\.productID), ["p2", "p3", "p4"])
        XCTAssertEqual(catalog.saleEvents.map(\.productID), ["p2", "p3", "p4"])
        XCTAssertEqual(catalog.removedProductIDs, ["p1"])
    }

    func testDeletionSurvivesJSONRoundTripAndMergeWithUndeletedRemote() throws {
        let remote = fixture()
        for deleteShop in [false, true] {
            var local = remote
            if deleteShop {
                XCTAssertNotNil(ShopCatalogDraftDeletion.removeShop(id: "shop1", from: &local))
            } else {
                XCTAssertNotNil(ShopCatalogDraftDeletion.removeSeries(id: "series1", from: &local))
            }
            let data = try ShopCatalogJSONCoding.encoder().encode(local)
            local = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data)
            let merged = try ShopCatalogThreeWayMerge.merge(local: local, remote: remote, baseline: remote)
            XCTAssertEqual(merged.conflicts, [])
            XCTAssertEqual(merged.catalog.shops, local.shops)
            XCTAssertEqual(merged.catalog.series, local.series)
            XCTAssertEqual(merged.catalog.products, local.products)
            XCTAssertEqual(merged.catalog.variants, local.variants)
            XCTAssertEqual(merged.catalog.sizeCharts, local.sizeCharts)
            XCTAssertEqual(merged.catalog.saleEvents, local.saleEvents)
            XCTAssertEqual(merged.catalog.styleProfiles, local.styleProfiles)
            XCTAssertEqual(merged.catalog.removedShopIDs, local.removedShopIDs)
            XCTAssertEqual(merged.catalog.removedSeriesIDs, local.removedSeriesIDs)
            XCTAssertEqual(merged.catalog.removedProductIDs, local.removedProductIDs)
        }
    }
}
