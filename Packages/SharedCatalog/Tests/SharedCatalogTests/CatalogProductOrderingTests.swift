import XCTest
@testable import SharedCatalog

final class CatalogProductOrderingTests: XCTestCase {
    private func product(_ id: String, _ category: String, _ order: Int? = nil) -> CatalogProduct {
        .init(id: id, shopID: "shop", seriesID: "series", name: "同名款式", category: category, displayOrder: order)
    }

    func testOldCatalogUsesOperatorTypeOrderAndKeepsCustomTypes() {
        let input = [product("bag", "包"), product("jsk", "JSK"), product("custom", "定制款"),
                     product("op", "OP"), product("other", "其他"), product("sk", "SK"), product("shirt", "衬衫")]
        XCTAssertEqual(CatalogProductOrdering.ordered(input).map(\.id), ["op", "jsk", "sk", "shirt", "bag", "custom", "other"])
    }

    func testExplicitOperatorOrderWinsOverNameArrayAndPresetOrder() {
        let input = [product("op-a", "OP", 2), product("custom", "定制款", 0),
                     product("jsk", "JSK", 3), product("op-b", "OP", 1)]
        XCTAssertEqual(CatalogProductOrdering.categories(in: input), ["定制款", "OP", "JSK"])
        XCTAssertEqual(CatalogProductOrdering.ordered(input).map(\.id), ["custom", "op-b", "op-a", "jsk"])
        XCTAssertEqual(CatalogProductOrdering.ordered(input.reversed()).map(\.id), ["custom", "op-b", "op-a", "jsk"])
    }

    func testTiesMissingAndInvalidRanksStayStableWithoutDroppingProducts() {
        let input = [product("missing", "OP"), product("a", "OP", 1), product("b", "OP", 1), product("invalid", "OP", -1)]
        XCTAssertEqual(CatalogProductOrdering.ordered(input).map(\.id), ["a", "b", "missing", "invalid"])
    }

    func testPublishedOrderSurvivesJSONRoundTripAndOldMissingKey() throws {
        let item = product("op", "OP", 7)
        let decoded = try ShopCatalogJSONCoding.decoder().decode(CatalogProduct.self, from: ShopCatalogJSONCoding.encoder().encode(item))
        XCTAssertEqual(decoded.displayOrder, 7)
        let old = #"{"id":"old","shopID":"shop","seriesID":"series","name":"旧商品","category":"OP"}"#
        XCTAssertNil(try ShopCatalogJSONCoding.decoder().decode(CatalogProduct.self, from: Data(old.utf8)).displayOrder)
    }

    func testMergeAndMediaRewriteCannotUndoPublishedOrder() throws {
        let original = ShopCatalog(products: [product("a", "OP"), product("b", "OP")])
        var local = original
        local.products[0].displayOrder = 1
        local.products[1].displayOrder = 0
        let result = try ShopCatalogThreeWayMerge.merge(local: local, remote: original, baseline: original)
        XCTAssertEqual(result.conflicts, [])
        XCTAssertEqual(CatalogProductOrdering.ordered(result.catalog.products).map(\.id), ["b", "a"])
        XCTAssertEqual(result.catalog.products.map(\.id), ["a", "b"], "发布合并可能沿用远端数组顺序，展示仍按明确顺序")
        XCTAssertEqual(CatalogProductOrdering.publicationOrder(result.catalog.products).map(\.id), ["b", "a"],
                       "发布包还必须兼容只按数组顺序显示的旧客户端")
    }

    func testPublicationOrderPreservesOtherSeriesSlotsAndUnrankedCatalogs() {
        var other = product("other", "JSK", 0); other.seriesID = "other-series"
        var legacyA = product("legacy-a", "JSK"); legacyA.seriesID = "legacy"
        var legacyB = product("legacy-b", "OP"); legacyB.seriesID = "legacy"
        let input = [product("second", "JSK", 1), other, legacyA, product("first", "JSK", 0), legacyB]
        let output = CatalogProductOrdering.publicationOrder(input)
        XCTAssertEqual(output.map(\.id), ["first", "other", "legacy-a", "second", "legacy-b"])
        XCTAssertEqual(CatalogProductOrdering.publicationOrder(output), output)
        XCTAssertEqual(Set(output), Set(input), "只重排数组，不改任何商品业务字段")
    }
}
