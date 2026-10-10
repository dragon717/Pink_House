import XCTest
@testable import SharedCatalog

final class ShopCatalogImageSourceTests: XCTestCase {
    func testAssetIDResolvesThroughResourceTable() {
        let asset = CatalogAsset(id: "cover-id", type: .productImage, originalURL: "local:封面.jpg")
        let source = ShopCatalogImageSource.resolve(" cover-id ", asset: { $0 == asset.id ? asset : nil })
        XCTAssertEqual(source.references, ["local:封面.jpg"])
        XCTAssertNil(source.mediaKey)
    }

    func testDirectReferencesRemainCompatible() {
        let hash = String(repeating: "a", count: 64)
        for reference in ["local:cover.png", "thmedia:\(hash)", "https://example.com/cover.jpg", "bundle:cover.jpg", "cover.jpg"] {
            let source = ShopCatalogImageSource.resolve(reference, asset: { _ in nil })
            XCTAssertEqual(source.references, [reference])
            XCTAssertEqual(source.mediaKey, reference.hasPrefix("thmedia:") ? hash : nil)
        }
    }

    func testCanonicalKeyWorksWithoutURLAndWinsOverLegacyReference() {
        let hash = String(repeating: "b", count: 64)
        let old = String(repeating: "a", count: 64)
        let asset = CatalogAsset(id: "cover", type: .productImage, originalURL: "thmedia:\(old)", mediaKey: hash)
        XCTAssertEqual(ShopCatalogImageSource.resolve("cover", asset: { _ in asset }).mediaKey, hash)
        var empty = asset
        empty.originalURL = ""
        let source = ShopCatalogImageSource.resolve("cover", asset: { _ in empty })
        XCTAssertTrue(source.references.isEmpty, "不能把资源 ID 再当成 Bundle 文件名")
        XCTAssertEqual(source.mediaKey, hash)
    }

    func testFallbackURLsAreCleanAndDeduplicated() {
        let asset = CatalogAsset(id: "cover", type: .productImage,
            thumbnailURL: " local:preview.png ", previewURL: "local:preview.png", originalURL: " ")
        XCTAssertEqual(ShopCatalogImageSource.resolve("cover", asset: { _ in asset }).references, ["local:preview.png"])
        XCTAssertTrue(ShopCatalogImageSource.resolve(nil, asset: { _ in nil }).references.isEmpty)
    }

    func testSameAssetIDWithNewMediaHasDifferentLoadingIdentity() {
        let old = CatalogAsset(id: "cover", type: .productImage, originalURL: "local:old.png")
        let new = CatalogAsset(id: "cover", type: .productImage, originalURL: "local:new.png")
        XCTAssertNotEqual(ShopCatalogImageSource.resolve("cover", asset: { _ in old }),
                          ShopCatalogImageSource.resolve("cover", asset: { _ in new }))
    }
}
