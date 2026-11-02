import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsCachedMediaLookupTests: XCTestCase {
    func testLookupDetectsReplacementRemovalAndNewDuplicate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("完整图片".utf8)
        let hash = ShopCatalogSyncProtocol.sha256Hex(bytes)
        let first = directory.appendingPathComponent(hash + ".jpg")
        let second = directory.appendingPathComponent(hash + ".png")
        let lookup = OpsCachedMediaLookup()
        XCTAssertNil(lookup.file(in: directory, hash: hash))
        try bytes.write(to: first)
        XCTAssertEqual(lookup.file(in: directory, hash: hash)?.resolvingSymlinksInPath(), first.resolvingSymlinksInPath())
        XCTAssertEqual(lookup.file(in: directory, hash: hash)?.resolvingSymlinksInPath(), first.resolvingSymlinksInPath())
        try Data("损坏后的新内容".utf8).write(to: first, options: .atomic)
        XCTAssertNil(lookup.file(in: directory, hash: hash))
        try bytes.write(to: second)
        XCTAssertEqual(lookup.file(in: directory, hash: hash)?.resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
        try FileManager.default.removeItem(at: second)
        XCTAssertNil(lookup.file(in: directory, hash: hash))
        // 严格发布核验仍不能接受缓存里曾经有效、如今已损坏的文件。
        XCTAssertTrue(OpsCachedMedia.files(in: directory).isEmpty)
    }
}
