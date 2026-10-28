import XCTest
import SharedCatalog

final class SharedProductRenameTests: XCTestCase {
    func testExplicitDesignNameWithColorWordsRemainsExactAndMigratesProfile() {
        let blue = CatalogProduct(id: "blue", shopID: "shop", seriesID: "series", name: "蓝色旧款",
            category: "JSK", images: [], designName: "旧款")
        let pink = CatalogProduct(id: "pink", shopID: "shop", seriesID: "series", name: "旧款粉色",
            category: "JSK", images: [], designName: "旧款")
        let profile = CatalogStyleProfile(id: "series|JSK|旧款", seriesID: "series",
            category: "JSK", designName: "旧款", fabric: "棉")
        let plan = ShopCatalogProductRename.plan(edited: blue, basedOn: blue,
            among: [blue, pink], profiles: [profile], explicitDesignName: "蓝色童话")
        XCTAssertEqual(plan.designNameAfter, "蓝色童话")
        XCTAssertEqual(plan.products.map(\.designName), ["蓝色童话", "蓝色童话"])
        XCTAssertEqual(plan.products[1].name, "蓝色童话粉色")
        XCTAssertEqual(plan.styleProfile.upserts.first?.id, "series|JSK|蓝色童话")
        XCTAssertEqual(plan.styleProfile.upserts.first?.fabric, "棉")
    }

    func testProfileCollisionKeepsTargetFieldsAndFillsMissingSourceFields() {
        let product = CatalogProduct(id: "p", shopID: "shop", seriesID: "series", name: "旧款",
            category: "JSK", images: [], designName: "旧款")
        let profiles = [
            CatalogStyleProfile(id: "series|JSK|旧款", seriesID: "series", category: "JSK",
                designName: "旧款", fabric: "棉", styleDescription: "原款描述"),
            CatalogStyleProfile(id: "series|JSK|新款", seriesID: "series", category: "JSK",
                designName: "新款", fabric: "提花")
        ]
        let plan = ShopCatalogProductRename.plan(product: product, newName: "新款",
            newCategory: "JSK", among: [product], profiles: profiles)
        XCTAssertEqual(plan.styleProfile.removals, [profiles[0].id])
        XCTAssertEqual(plan.styleProfile.upserts.first?.fabric, "提花")
        XCTAssertEqual(plan.styleProfile.upserts.first?.styleDescription, "原款描述")
    }
}
