import XCTest
@testable import ItemManager

final class SwiftUIModernizationTests: XCTestCase {
    func testSelectionFollowsAssetWhenSlidesAreReordered() {
        let a = slide("asset-a")
        let b = slide("asset-b")
        XCTAssertEqual(ShopCatalogCarouselSlide.selectedID(b.id, in: [a, b]), b.id)
        XCTAssertEqual(ShopCatalogCarouselSlide.selectedID(b.id, in: [b, a]), b.id)
    }

    func testURLRefreshDoesNotReplaceSelectedAsset() {
        let refreshed = ShopCatalogCarouselSlide(id: "asset-a", ref: "https://example.com/new.jpg",
                                                 mediaKey: "media-a", colorLabel: "粉色")
        XCTAssertEqual(ShopCatalogCarouselSlide.selectedID("asset-a", in: [refreshed]), "asset-a")
    }

    func testRemovedSelectionFallsBackAndEmptyGalleryClearsSelection() {
        XCTAssertEqual(ShopCatalogCarouselSlide.selectedID("removed", in: [slide("first")]), "first")
        XCTAssertNil(ShopCatalogCarouselSlide.selectedID("removed", in: []))
    }

    func testImageHeightFitsShortFoldedAndSplitWindows() {
        for size in [CGSize(width: 820, height: 300), CGSize(width: 360, height: 450),
                     CGSize(width: 800, height: 700), CGSize(width: 600, height: 900)] {
            let height = DetailImageLayout.height(in: size)
            XCTAssertGreaterThan(height, 0)
            XCTAssertLessThanOrEqual(height, size.height * 0.7)
        }
        XCTAssertEqual(DetailImageLayout.height(in: CGSize(width: 402, height: 820)), 400)
        XCTAssertEqual(DetailImageLayout.height(in: CGSize(width: 1366, height: 980)), 686)
    }

    private func slide(_ id: String) -> ShopCatalogCarouselSlide {
        ShopCatalogCarouselSlide(id: id, ref: "\(id).jpg", mediaKey: nil, colorLabel: nil)
    }
}
