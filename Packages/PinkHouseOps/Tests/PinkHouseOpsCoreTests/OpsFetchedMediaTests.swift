//
//  OpsFetchedMediaTests.swift
//  PinkHouseOpsTests
//
//  「从远端下载图片字节」（双向同步的「下载」那一档）的产物模型回归锁。
//
//  ## 为什么这几个用例值得存在
//
//  这一档最容易错的地方**不在网络**，而在「怎么解读结果」：
//
//    · 把 `missing`（远端确实没有）与「桥接器没跑到那一步」混成一句
//      「下载了 0 张」—— 前者是正常的，后者是失败；
//    · 把 `corrupt` / `unrecognizedFormat` 吞进「下载了 N 张」里 ——
//      那两类是**要看一眼的问题**，静默吞掉等于把坏图混进公共库；
//    · manifest 读不出来时回落成「0 张」而不是「没有结果」。
//
//  三种都不会崩、都不会报错，只会让人**信一个错的事实**。所以在这里钉死。
//

import XCTest
@testable import PinkHouseOpsCore

final class OpsFetchedMediaTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OpsFetchedMediaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func writeManifest(_ json: String) throws {
        try json.write(
            to: directory.appendingPathComponent("fetch-manifest.json"),
            atomically: true,
            encoding: .utf8)
    }

    private let hashA = String(repeating: "a", count: 64)
    private let hashB = String(repeating: "b", count: 64)

    func testPartialDownloadPreservesPendingInsteadOfCallingItMissing() throws {
        try writeManifest("""
        {"requested": 2, "downloaded": [{"contentHash":"\(hashA)", "fileName":"\(hashA).jpg"}],
         "missing": [], "pending": ["\(hashB)"]}
        """)
        let result = try XCTUnwrap(OpsFetchedMedia.load(directory: directory.path, environment: "development"))
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.pending, [hashB])
        XCTAssertTrue(result.hasAnomalies)
        XCTAssertTrue(result.missing.isEmpty)
        XCTAssertTrue(result.summaryText.contains("未完成 1 张"))
    }

    // MARK: - 读 manifest

    func testLoadReadsEveryBucket() throws {
        try writeManifest("""
        {
          "requested": 3,
          "downloaded": [{"contentHash": "\(hashA)", "fileName": "\(hashA).jpg", "byteCount": 12}],
          "missing": ["\(hashB)"],
          "corrupt": [],
          "unrecognizedFormat": []
        }
        """)
        let fetched = try XCTUnwrap(OpsFetchedMedia.load(directory: directory.path,
                                                         environment: "development"))
        XCTAssertEqual(fetched.requested, 3)
        XCTAssertEqual(fetched.files.map(\.contentHash), [hashA])
        XCTAssertEqual(fetched.missing, [hashB])
        XCTAssertFalse(fetched.hasAnomalies)
    }

    /// 读不出 manifest 必须返回 nil —— 不能回落成「下载了 0 张」
    /// （那会让人以为远端没有图）。
    func testLoadReturnsNilWhenManifestIsAbsent() {
        XCTAssertNil(OpsFetchedMedia.load(directory: directory.path, environment: "development"))
    }

    func testLoadReturnsNilWhenManifestIsNotJSON() throws {
        try writeManifest("not json at all")
        XCTAssertNil(OpsFetchedMedia.load(directory: directory.path, environment: "development"))
    }

    /// 桥接器新增字段时 App 不能解不开（只取认识的字段，其余忽略）。
    func testIgnoresUnknownManifestFields() throws {
        try writeManifest("""
        {
          "requested": 1,
          "downloaded": [{"contentHash": "\(hashA)", "fileName": "\(hashA).png"}],
          "someBrandNewField": {"nested": true}
        }
        """)
        let fetched = try XCTUnwrap(OpsFetchedMedia.load(directory: directory.path,
                                                         environment: "production"))
        XCTAssertEqual(fetched.files.count, 1)
        // 缺省的三个桶必须是空数组，不能是「有值但说不清」
        XCTAssertTrue(fetched.missing.isEmpty)
        XCTAssertTrue(fetched.corrupt.isEmpty)
        XCTAssertTrue(fetched.unrecognizedFormat.isEmpty)
    }

    // MARK: - 异常必须出声

    func testCorruptAndUnrecognizedCountAsAnomalies() {
        let fetched = OpsFetchedMedia(
            directory: "/tmp/x", environment: "development",
            requested: 3, files: [OpsFetchedMediaFile(contentHash: hashA, fileName: "\(hashA).jpg")],
            corrupt: [hashB])
        XCTAssertTrue(fetched.hasAnomalies, "摘要不符属于要看一眼的问题")
        XCTAssertTrue(fetched.summaryText.contains("摘要不符 1 张"))
    }

    /// 远端没有**不算**异常：那是正常结果（那一版发布时图就没上传）。
    func testMissingIsNotAnAnomaly() {
        let fetched = OpsFetchedMedia(
            directory: "/tmp/x", environment: "development",
            requested: 2, files: [], missing: [hashA, hashB])
        XCTAssertFalse(fetched.hasAnomalies)
        XCTAssertTrue(fetched.summaryText.contains("远端没有 2 张"))
    }

    // MARK: - 桥接结果

    func testFromResultNeedsAPath() {
        var result = OpsBridgeRunResult(exitCode: 0, events: [], nonJSONLines: [],
                                        executablePath: "/usr/bin/python3",
                                        scriptPath: "/repo/ops_publish_bridge.py")
        XCTAssertNil(OpsFetchedMedia.from(result: result, environment: "development"))
        result.fetchedMediaPath = ""
        XCTAssertNil(OpsFetchedMedia.from(result: result, environment: "development"),
                     "空路径也算「没拿到」，不能当成当前目录")
    }

    /// 模式名是带连字符的 `fetch-media`：靠枚举名默认推导会变成 `fetchMedia`，
    /// 而桥接器根本不认那个词。
    func testModeRawValueMatchesBridge() {
        XCTAssertEqual(OpsBridgeMode.fetchMedia.rawValue, "fetch-media")
        XCTAssertEqual(OpsBridgeMode.pullCatalog.rawValue, "pull-catalog")
    }
}
