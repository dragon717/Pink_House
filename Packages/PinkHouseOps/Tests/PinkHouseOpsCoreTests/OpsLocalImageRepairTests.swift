import Foundation
import XCTest
@testable import PinkHouseOpsCore

final class OpsLocalImageRepairTests: XCTestCase {
    private var root: URL!
    private var source: URL { root.appendingPathComponent("原图交接", isDirectory: true) }
    private var staging: URL { root.appendingPathComponent("staging", isDirectory: true) }
    // 一张真实的 1×1 PNG。补图必须原字节落盘，不能经过有损重编码。
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testRestoresOnlyRequestedImagesWithOriginalNamesAndBytes() throws {
        let images = source.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try png.write(to: images.appendingPathComponent("img-chart.png"))
        try png.write(to: images.appendingPathComponent("unrelated.png"))
        let report = try OpsLocalImageRepair.restore(
            fileNames: ["img-chart.png", "img-missing.png"], from: source, to: staging)
        XCTAssertEqual(report.restored, ["img-chart.png"])
        XCTAssertEqual(report.missing, ["img-missing.png"])
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("img-chart.png")), png)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("unrelated.png").path))
    }

    func testExistingImagesAreNeverOverwrittenAndRepeatIsIdempotent() throws {
        try png.write(to: source.appendingPathComponent("img-a.png"))
        let first = try OpsLocalImageRepair.restore(fileNames: ["img-a.png"], from: source, to: staging)
        XCTAssertEqual(first.restored.count, 1)
        try Data("different source".utf8).write(to: source.appendingPathComponent("img-a.png"))
        let second = try OpsLocalImageRepair.restore(fileNames: ["img-a.png"], from: source, to: staging)
        XCTAssertEqual(second.alreadyPresent, ["img-a.png"])
        XCTAssertTrue(second.restored.isEmpty)
        XCTAssertEqual(try Data(contentsOf: staging.appendingPathComponent("img-a.png")), png)
    }

    func testAcceptsImagesFolderWithoutCatalogAndNestedPackage() throws {
        try png.write(to: source.appendingPathComponent("direct.png"))
        XCTAssertEqual(try OpsLocalImageRepair.restore(
            fileNames: ["direct.png"], from: source, to: staging).restored, ["direct.png"])
        let package = source.appendingPathComponent("整包")
        let images = package.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("old catalog must not be imported".utf8).write(to: package.appendingPathComponent("shop-catalog.json"))
        try png.write(to: images.appendingPathComponent("nested.png"))
        XCTAssertEqual(try OpsLocalImageRepair.restore(
            fileNames: ["nested.png"], from: source, to: staging).restored, ["nested.png"])
    }

    func testRejectsBadImageWithoutLosingSuccessfulPartialRepair() throws {
        try png.write(to: source.appendingPathComponent("good.png"))
        try Data("not an image".utf8).write(to: source.appendingPathComponent("broken.png"))
        let report = try OpsLocalImageRepair.restore(
            fileNames: ["good.png", "broken.png"], from: source, to: staging)
        XCTAssertEqual(report.restored, ["good.png"])
        XCTAssertNotNil(report.failures["broken.png"])
        XCTAssertTrue(report.missing.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("broken.png").path))
    }

    func testDoesNotFollowEscapingLinksOrInvalidFileNames() throws {
        let outside = root.appendingPathComponent("outside.png")
        try png.write(to: outside)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("linked.png"), withDestinationURL: outside)
        let report = try OpsLocalImageRepair.restore(
            fileNames: ["linked.png", "../outside.png"], from: source, to: staging)
        XCTAssertEqual(report.missing, ["linked.png"])
        XCTAssertNotNil(report.failures["../outside.png"])
        XCTAssertTrue(report.restored.isEmpty)
    }

    func testOldIncompletePackageReportsMissingInsteadOfSuccess() throws {
        let names = Set((0..<174).map { "img-\($0).jpg" })
        let report = try OpsLocalImageRepair.restore(fileNames: names, from: source, to: staging)
        XCTAssertEqual(Set(report.missing), names)
        XCTAssertTrue(report.restored.isEmpty)
    }
}
