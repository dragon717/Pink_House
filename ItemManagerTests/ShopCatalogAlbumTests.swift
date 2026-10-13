import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogAlbumTests: XCTestCase {
    private func series(_ id: String, year: Int?, name: String = "同名系列") -> CatalogSeries {
        var value = CatalogSeries(id: id, shopID: "album-shop", name: name)
        value.year = year
        return value
    }

    func testYearRailIncludesAllDescendingYearsAndUnspecifiedWithoutDuplicates() {
        let entries = [series("a", year: 2025), series("b", year: nil), series("c", year: 2026), series("d", year: 2026)]
        XCTAssertEqual(ShopCatalogAlbumSelection.years(in: entries), [.all, .year(2026), .year(2025), .unspecified])
        XCTAssertEqual(ShopCatalogAlbumSelection().visibleSeries(entries).map(\.id), entries.map(\.id))
        XCTAssertEqual(ShopCatalogAlbumSelection.years(in: []), [.all])
    }

    func testSeriesNamesFilterByStableIDWithinYearAndChangingYearClearsSeries() {
        let entries = [series("new-a", year: 2026), series("new-b", year: 2026), series("old", year: 2025), series("unknown", year: nil)]
        var selection = ShopCatalogAlbumSelection()
        selection.selectYear(.year(2026))
        XCTAssertEqual(selection.seriesInYear(entries).map(\.id), ["new-a", "new-b"])
        selection.seriesID = "new-b"
        XCTAssertEqual(selection.visibleSeries(entries).map(\.id), ["new-b"])
        selection.selectYear(.year(2025))
        XCTAssertNil(selection.seriesID)
        XCTAssertEqual(selection.visibleSeries(entries).map(\.id), ["old"])
        selection.selectYear(.unspecified)
        XCTAssertEqual(selection.visibleSeries(entries).map(\.id), ["unknown"])
    }

    func testCatalogRefreshRepairsRemovedYearAndSeriesWithoutAnEmptyStaleSelection() {
        var selection = ShopCatalogAlbumSelection(year: .year(2026), seriesID: "removed")
        selection.reconcile(with: [series("remaining", year: 2026)])
        XCTAssertEqual(selection.year, .year(2026))
        XCTAssertNil(selection.seriesID)
        selection.seriesID = "remaining"
        selection.reconcile(with: [series("old", year: 2025)])
        XCTAssertEqual(selection.year, .all)
        XCTAssertNil(selection.seriesID)
        selection.reconcile(with: [])
        XCTAssertEqual(selection.visibleSeries([]), [])
    }

    func testAlbumUsesAllLiveSeriesIncludingEndedSalesAndExcludesOtherShopsAndArchives() throws {
        let json = #"""
        {"version":1,"shops":[{"id":"album-shop","name":"店铺时光册"}],
         "series":[
           {"id":"active","shopID":"album-shop","name":"在售系列","year":2026},
           {"id":"ended","shopID":"album-shop","name":"历史系列","year":2026},
           {"id":"unknown","shopID":"album-shop","name":"未标年份"},
           {"id":"archived","shopID":"album-shop","name":"已归档","year":2024,"archivedAt":"2026-01-01T00:00:00Z"},
           {"id":"other","shopID":"other-shop","name":"其他店家","year":2023}],
         "products":[
           {"id":"p-ended","shopID":"album-shop","seriesID":"ended","name":"历史款","category":"JSK","images":[]}],
         "variants":[],"sizeCharts":[],"assets":[],
         "saleEvents":[{"id":"ended-sale","productID":"p-ended","type":"stock","price":280,"endAt":"2026-01-01T00:00:00Z"}]}
        """#
        let catalog = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(json.utf8))
        let store = ShopCatalogStore(catalog: catalog)
        let entries = store.series(inShop: "album-shop")
        XCTAssertEqual(ShopCatalogAlbumSelection.years(in: entries), [.all, .year(2026), .unspecified])
        var selection = ShopCatalogAlbumSelection()
        selection.selectYear(.year(2026))
        XCTAssertEqual(Set(selection.visibleSeries(entries).map(\.id)), ["active", "ended"])
        XCTAssertEqual(store.productCount(inSeries: "ended"), 1)
        XCTAssertEqual(store.products(inSeries: "ended").first?.id, "p-ended")
    }
}
