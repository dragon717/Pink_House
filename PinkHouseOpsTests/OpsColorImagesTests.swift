import XCTest
@testable import PinkHouseOps

final class OpsColorImagesTests: XCTestCase {
    private func entry() -> OpsSeriesTypeEntry {
        OpsSeriesTypeEntry(category: "JSK", designName: "星月夜", stockPriceText: "680", colors: [
            OpsSeriesColorSKU(id: "pink", name: "粉色", imageAssetID: "old-pink", selectedSizes: ["S", "M"]),
            OpsSeriesColorSKU(id: "blue", name: "蓝色", imageAssetID: "old-blue", selectedSizes: ["L"]),
            OpsSeriesColorSKU(id: "white", name: "白色", imageAssetID: nil, selectedSizes: [])
        ])
    }

    func testBatchAssignmentChangesOnlyImagesAndSupportsSharedImage() {
        var target = entry()
        let original = target
        XCTAssertTrue(target.applyColorImages(colorIDs: ["pink", "blue"],
                                              assignments: ["pink": "new-image", "blue": "new-image"]))
        XCTAssertEqual(target.colors.map(\.imageAssetID), ["new-image", "new-image", nil])
        XCTAssertEqual(target.colors.map(\.selectedSizes), original.colors.map(\.selectedSizes))
        XCTAssertEqual(target.colors.map(\.name), original.colors.map(\.name))
        XCTAssertEqual(target.stockPriceText, original.stockPriceText)
        XCTAssertEqual(target.designName, original.designName)
    }

    func testClearingOneImagePreservesUnmanagedColors() {
        var target = entry()
        XCTAssertTrue(target.applyColorImages(colorIDs: ["pink"], assignments: [:]))
        XCTAssertNil(target.colors[0].imageAssetID)
        XCTAssertEqual(target.colors[1].imageAssetID, "old-blue")
    }

    func testDeletedOrUnknownColorRejectsEntireBatchWithoutPartialChanges() {
        var target = entry()
        let original = target
        XCTAssertFalse(target.applyColorImages(colorIDs: ["pink", "deleted"], assignments: ["pink": "new-image"]))
        XCTAssertEqual(target, original)
        XCTAssertFalse(target.applyColorImages(colorIDs: ["pink"], assignments: ["blue": "wrong-image"]))
        XCTAssertEqual(target, original)
    }

    func testAssignmentUsesStableIDAfterReorderAndDuplicateNames() {
        var target = entry()
        target.colors.reverse()
        target.colors[0].name = "同名"
        target.colors[2].name = "同名"
        XCTAssertTrue(target.applyColorImages(colorIDs: ["pink"], assignments: ["pink": "pink-image"]))
        XCTAssertEqual(target.colors.first { $0.id == "pink" }?.imageAssetID, "pink-image")
        XCTAssertNil(target.colors.first { $0.id == "white" }?.imageAssetID)
    }

    func testWorkingCopyDoesNotAlterOriginalAndConfirmedImagesPersist() throws {
        let original = entry()
        var working = original
        XCTAssertTrue(working.applyColorImages(colorIDs: ["pink"], assignments: ["pink": "new-image"]))
        XCTAssertEqual(original.colors[0].imageAssetID, "old-pink")
        let data = try JSONEncoder().encode(working)
        let restored = try JSONDecoder().decode(OpsSeriesTypeEntry.self, from: data)
        XCTAssertEqual(restored, working)
    }
}
