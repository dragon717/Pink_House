import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

/// 真起 Python 桥接器与 Swift 收集器，仅替换远端读取，覆盖此前漏测的接线。
final class OpsBaselineBridgeContractTests: XCTestCase {
    private func run(head: [String: Any]?, environment: String, failure: Bool = false) throws -> OpsBridgeRunResult {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let publication = repo.appendingPathComponent("tools/time_hall/publication")
        let python = publication.appendingPathComponent(".venv/bin/python3")
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: python.path), "本用例需要仓库发布器的 Python 环境")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shimDirectory = root.appendingPathComponent("tools/time_hall/publication")
        let credentials = root.appendingPathComponent("credentials")
        try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: credentials, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: credentials.appendingPathComponent("cloudkit.\(environment).json"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let sourcePath = String(decoding: try encoder.encode(publication.path), as: UTF8.self)
        let shim = """
        import json, sys
        sys.path.insert(0, \(sourcePath))
        import ops_publish_bridge as bridge
        request = json.load(open(sys.argv[sys.argv.index('--request') + 1], encoding='utf-8'))
        def read_head(_):
            if request['fixtureFailure']:
                raise bridge.CredentialError('fixture HTTP 401')
            return request.get('fixtureHead')
        bridge.read_head = read_head
        bridge.emit({'type': 'hello', 'schemaVersion': 1})
        sys.exit(bridge.run_baseline(request, True))
        """
        try shim.write(to: shimDirectory.appendingPathComponent("ops_publish_bridge.py"), atomically: true, encoding: .utf8)
        var request: [String: Any] = ["targetEnvironment": environment, "fixtureFailure": failure]
        if let head { request["fixtureHead"] = head }
        let requestURL = root.appendingPathComponent("request.json")
        try JSONSerialization.data(withJSONObject: request).write(to: requestURL)
        let bridge = OpsPublisherBridge(settings: .init(repoRootPath: root.path, pythonPath: python.path,
                                                       credentialsDirectoryOverride: credentials.path))
        return try bridge.run(mode: .baseline, requestPath: requestURL, environmentName: environment) { _ in }
    }

    func testDevelopmentBaselineProducesNativeConfirmedOutcomeAndExactHead() throws {
        let hash = String(repeating: "a", count: 64)
        let result = try run(head: ["releaseSeq": 21, "rootIndexHash": hash], environment: "development")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.outcome, .confirmed)
        XCTAssertEqual(result.onlineHead?.releaseSeq, 21)
        XCTAssertEqual(result.onlineHead?.rootIndexHash, hash)
        XCTAssertEqual(result.onlineHead?.environment, "development")
    }

    func testVerifiedEmptyProductionIsSuccessfulReadWithZeroSequence() throws {
        let result = try run(head: nil, environment: "production")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.outcome, .confirmed)
        XCTAssertEqual(result.onlineHead?.releaseSeq, 0)
        XCTAssertNil(result.onlineHead?.rootIndexHash)
        XCTAssertEqual(result.onlineHead?.environment, "production")
    }

    func testFailedReadNeverReturnsConfirmedOrEmptyBaseline() throws {
        let result = try run(head: nil, environment: "production", failure: true)
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.outcome, .refused)
        XCTAssertNil(result.onlineHead)
        XCTAssertTrue(result.outcomeMessage?.contains("401") == true)
    }
}
