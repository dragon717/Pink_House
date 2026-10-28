import XCTest
@testable import SharedCatalog

final class ShopCatalogProductImagesTests: XCTestCase {
    private let product = CatalogProduct(id: "bb-hat", shopID: "shop", seriesID: "series",
        name: "BB帽", category: "小物", images: ["group-photo"])

    func testEveryColorCanUseExplicitlySharedGroupPhoto() {
        let variants = ["粉色", "黄色", "蓝色"].map {
            CatalogProductVariant(id: $0, productID: product.id, color: $0, imageAssetID: "group-photo")
        }
        for color in ["粉色", "黄色", "蓝色"] {
            XCTAssertEqual(ShopCatalogProductImages.references(product: product, variants: variants,
                selectedColor: color, asset: { _ in nil }), ["group-photo"])
        }
    }

    func testSharedCanonicalAliasesRemainSelectedButExclusiveOtherColorDoesNot() {
        var product = product
        product.images = ["blue-only", "shared-alias", "detail"]
        let variants = [
            CatalogProductVariant(id: "pink", productID: product.id, color: "粉色", imageAssetID: "shared"),
            CatalogProductVariant(id: "blue", productID: product.id, color: "蓝色", imageAssetID: "shared-alias"),
            CatalogProductVariant(id: "blue-2", productID: product.id, color: "蓝色", imageAssetID: "blue-only"),
            CatalogProductVariant(id: "unbound", productID: product.id, color: "绿色")]
        let key = String(repeating: "a", count: 64)
        func asset(_ id: String) -> CatalogAsset? {
            guard ["shared", "shared-alias"].contains(id) else { return nil }
            return CatalogAsset(id: id, type: .productImage, originalURL: "", mediaKey: key)
        }
        XCTAssertEqual(ShopCatalogProductImages.references(product: product, variants: variants,
            selectedColor: " 粉色 ", asset: asset), ["shared", "detail"])
        XCTAssertEqual(ShopCatalogProductImages.references(product: product, variants: variants,
            selectedColor: "绿色", asset: asset), ["detail"])
        XCTAssertTrue(ShopCatalogProductImages.references(product: product, variants: variants,
            selectedColor: "不存在的配色", asset: asset).isEmpty)
    }
}
