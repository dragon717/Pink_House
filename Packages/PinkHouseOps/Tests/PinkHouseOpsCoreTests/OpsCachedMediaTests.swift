import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsCachedMediaTests: XCTestCase {
    func testJPEGAndUppercaseExtensionsEnterThePublicationArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for ext in ["jpeg", "HEIC", "PNG"] {
            let bytes = Data(("已下载的图片" + ext).utf8)
            let hash = ShopCatalogSyncProtocol.sha256Hex(bytes)
            let url = directory.appendingPathComponent(hash + "." + ext)
            try bytes.write(to: url)
            let cached = OpsCachedMedia.files(in: directory, hash: hash)
            XCTAssertEqual(cached[hash]?.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
            let references = Set(cached.values.map { "local:" + $0.lastPathComponent })
            let (entries, missing) = ShopCatalogExportArchive.imageEntries(
                forLocalReferences: references, imageDirectory: directory)
            XCTAssertTrue(missing.isEmpty)
            XCTAssertEqual(entries.first?.data, bytes)
            XCTAssertEqual(entries.first?.name, "images/" + url.lastPathComponent)
        }
    }

    func testCorruptDuplicateDoesNotHideVerifiedCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("完整图片".utf8), corrupt = Data("损坏".utf8)
        let hash = ShopCatalogSyncProtocol.sha256Hex(bytes)
        try corrupt.write(to: directory.appendingPathComponent(hash + ".jpg"))
        let valid = directory.appendingPathComponent(hash + ".jpeg")
        try bytes.write(to: valid)
        XCTAssertEqual(OpsCachedMedia.files(in: directory)[hash]?.resolvingSymlinksInPath(), valid.resolvingSymlinksInPath())
        try corrupt.write(to: valid)
        XCTAssertTrue(OpsCachedMedia.files(in: directory).isEmpty)
    }
}
