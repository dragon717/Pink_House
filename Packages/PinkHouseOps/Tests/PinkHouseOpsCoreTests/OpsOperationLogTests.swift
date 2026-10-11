import XCTest
@testable import PinkHouseOpsCore

final class OpsOperationLogTests: XCTestCase {
    func testProgressIsReadableBeforeTheBridgeOrOperationFinishes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = try OpsOperationLog(directory: directory, title: "迁移")
        try log.append("下载开发环境图片 · 37/630 张")
        let running = try String(contentsOf: log.url, encoding: .utf8)
        XCTAssertTrue(running.contains("37/630 张"))
        XCTAssertFalse(running.contains("最终结果"))
        try log.append("确认线上更新结果")
        try log.finish("已回读确认 seq 12")
        let finished = try String(contentsOf: log.url, encoding: .utf8)
        XCTAssertTrue(finished.hasPrefix(running))
        XCTAssertTrue(finished.contains("最终结果：已回读确认 seq 12"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [log.url.lastPathComponent])
    }

    func testMultipleCallsAndFailureProduceOneCompleteUTF8Log() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = try OpsOperationLog(directory: directory, title: "开发环境 → 线上环境")
        let longOutput = (1...500).map { "下载图片 \($0)" }.joined(separator: "\n")
        try log.append("开发环境读取成功：seq 21")
        try log.append("线上环境读取成功：seq 11\n" + longOutput)
        try log.finish("构建失败，未写线上")
        let content = try String(contentsOf: log.url, encoding: .utf8)
        XCTAssertTrue(content.contains("开发环境读取成功：seq 21"))
        XCTAssertTrue(content.contains("线上环境读取成功：seq 11"))
        XCTAssertTrue(content.contains(longOutput))
        XCTAssertTrue(content.contains("最终结果：构建失败，未写线上"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }
}
