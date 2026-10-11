import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogEntryDefaultsTests: XCTestCase {
    private func products(in store: ShopCatalogStore) throws -> [CatalogProduct] {
        try ["prod-ag-xueguo-kc", "prod-ag-xueguo-jsk", "prod-unniq-yunduo-op"]
            .map { try XCTUnwrap(store.product(id: $0)) }
    }

    private func drafts(_ selection: ShopCatalogWardrobeMergeSelection,
                        products: [CatalogProduct], store: ShopCatalogStore)
        throws -> [(draft: ClothingEditDraft, selection: ShopCatalogWardrobeDraftBuilder.Selection)] {
        try ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
            selections: selection.includedProducts(in: products).map { .init(productID: $0.id) },
            accessoryProductIDs: selection.includedAccessoryIDs, store: store,
            primaryProductID: selection.primaryID)
    }

    func testMainGarmentsDefaultSelectedAndAccessoriesExcludedFromDrafts() async throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let products = try products(in: store)
        var selection = ShopCatalogWardrobeMergeSelection()
        selection.initializePrimary(in: products)
        XCTAssertEqual(selection.primaryID, "prod-ag-xueguo-jsk")
        let result = try drafts(selection, products: products, store: store)
        XCTAssertEqual(result.map(\.selection.productID),
                       ["prod-ag-xueguo-jsk", "prod-unniq-yunduo-op"])
        XCTAssertTrue(result.allSatisfy { $0.draft.accessories.isEmpty })
        XCTAssertEqual(result.first?.draft.priceTotal, 568)
    }

    func testAccessoryOptInAndDeselectSurviveRepeatedAppearance() async throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let products = try products(in: store)
        var selection = ShopCatalogWardrobeMergeSelection()
        selection.initializePrimary(in: products)
        selection.accessoryIDs.insert("prod-ag-xueguo-kc")
        selection.initializePrimary(in: products)
        let included = try drafts(selection, products: products, store: store)
        XCTAssertEqual(included.first?.draft.accessories, "雪国来信 KC")
        XCTAssertEqual(included.first?.draft.priceTotal, 696)
        selection.accessoryIDs.removeAll()
        selection.initializePrimary(in: products)
        let excluded = try drafts(selection, products: products, store: store)
        XCTAssertEqual(excluded.first?.draft.priceTotal, 568)
        XCTAssertTrue(excluded.allSatisfy { $0.draft.accessories.isEmpty })
    }

    func testSingleAccessoryCanStillBeAddedAsItsOwnWardrobeRecord() async throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let accessory = try XCTUnwrap(store.product(id: "prod-ag-xueguo-kc"))
        var selection = ShopCatalogWardrobeMergeSelection()
        selection.initializePrimary(in: [accessory])
        let result = try drafts(selection, products: [accessory], store: store)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.selection.productID, accessory.id)
        XCTAssertEqual(result.first?.draft.priceTotal, 128)
        XCTAssertEqual(result.first?.draft.accessories, "")
    }

    func testChosenMainGarmentOwnsTheOptInAccessories() async throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let products = try products(in: store)
        var selection = ShopCatalogWardrobeMergeSelection()
        selection.initializePrimary(in: products)
        selection.primaryID = "prod-unniq-yunduo-op"
        selection.accessoryIDs.insert("prod-ag-xueguo-kc")
        let result = try drafts(selection, products: products, store: store)
        XCTAssertEqual(result.first?.selection.productID, selection.primaryID)
        XCTAssertEqual(result.first?.draft.accessories, "雪国来信 KC")
        XCTAssertTrue(result.last?.draft.accessories.isEmpty == true)
    }

    func testAccessoryChosenAsMainIsNotAlsoItsOwnAccessory() async throws {
        let store = ShopCatalogSeedFixture.makeStore()
        let products = try ["prod-ag-xueguo-kc", "prod-ag-xueguo-bag"]
            .map { try XCTUnwrap(store.product(id: $0)) }
        var selection = ShopCatalogWardrobeMergeSelection()
        selection.initializePrimary(in: products)
        selection.accessoryIDs.insert(products[1].id)
        selection.primaryID = products[1].id
        let result = try drafts(selection, products: products, store: store)
        XCTAssertEqual(result.first?.selection.productID, products[1].id)
        XCTAssertEqual(result.first?.draft.priceTotal, 238)
        XCTAssertEqual(result.first?.draft.accessories, "")
    }

    func testNewOperatorDraftAndStyleDefaultToCNY() async throws {
        XCTAssertEqual(CatalogProductDraft().currency, .cny)
        XCTAssertEqual(ShopCatalogDraftStyleForm.StyleInput().currency, .cny)
        let original = CatalogProductDraft(currency: .jpy)
        let decoded = try JSONDecoder().decode(CatalogProductDraft.self,
                                               from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.currency, .jpy)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "currency")
        let legacy = try JSONDecoder().decode(CatalogProductDraft.self,
                                              from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.currency, "历史缺币种数据的解码不能冒充换汇")
    }

    func testDefaultCurrencyIsPublishedOnBothReservationAndStockEvents() async throws {
        ShopCatalogStorage.useTemporaryForTesting()
        CreatorAccess.setTestOverride(.creator)
        defer {
            CreatorAccess.setTestOverride(nil)
            ShopCatalogStorage.restoreDefaultForTesting()
        }
        let store = ShopCatalogStore(catalog: ShopCatalog())
        let draftStore = ShopCatalogDraftStore.shared
        var draft = CatalogProductDraft()
        draft.name = "人民币默认发布测试"
        draft.category = "JSK"
        draft.price = 428
        draft.stockPrice = 568
        draft.newShopName = "默认币种测试店家"
        draft.newSeriesName = "默认币种测试系列"
        try draftStore.advance(draft, to: .submitted)
        draft = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(draft, to: .reviewed)
        draft = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(draft, store: store)
        let overlay = try XCTUnwrap(ShopCatalogDraftStore.loadOverlay())
        XCTAssertEqual(overlay.saleEvents.count, 2)
        XCTAssertTrue(overlay.saleEvents.allSatisfy { $0.currency == .cny })
    }
}
