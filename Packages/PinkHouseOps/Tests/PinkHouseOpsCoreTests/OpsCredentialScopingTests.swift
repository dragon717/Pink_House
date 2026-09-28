//
//  OpsCredentialScopingTests.swift
//  PinkHouseOpsCoreTests
//
//  **凭证按环境隔离**的回归锁（2026-09-28）。
//
//  ## 这份测试存在的理由
//
//  Mac 端要用同一套界面同时服务 Development 与 Production。而 CloudKit 的
//  server-to-server key 是**按环境注册**的：Development 的 key 打 Production 的
//  URL 只会 HTTP 401，且 401 的响应里看不出「这把 key 属于另一个环境」。
//  在改成「一份凭证文件打两个环境」之前，这个坑的表现就是：
//
//      Development 一切正常 → 切到 Production → 401 → 报「凭证不可用」→ 无解。
//
//  所以规则必须是：**凭证按环境分文件，且一个环境的凭证绝不能给另一个环境兜底**。
//  下面每一条都锁住这条规则的一个面。
//
//  ## 为什么这里能测，而不用点界面
//
//  凭证默认位置在**用户真实容器**里（`~/Library/Application Support/...`）。
//  为此 `OpsBridgeSettings` 留了 `credentialsDirectoryOverride` 注入口 ——
//  没有它，「有没有凭证」这条判定只能靠手工点界面验证，改坏了没人知道。
//

import XCTest
@testable import PinkHouseOpsCore
import SharedCatalog

final class OpsCredentialScopingTests: XCTestCase {

    private var root: URL!
    private var credentials: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ops-cred-scope-\(UUID().uuidString)", isDirectory: true)
        credentials = root.appendingPathComponent("credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: credentials, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ payload: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: credentials.appendingPathComponent(name))
    }

    private func exists(_ environment: String) -> Bool {
        OpsPublisherBridge.existingCredentialFile(
            environmentName: environment, credentialsDirectory: credentials) != nil
    }

    // MARK: - 按环境分文件

    /// 一个环境的凭证**不能**当作另一个环境的凭证用。
    func testCredentialOfOneEnvironmentIsNotVisibleToTheOther() throws {
        try write("cloudkit.development.json", [
            "keyID": "dev-key", "privateKey": "dev-pem",
            "containerID": "iCloud.bugod2.ItemManager", "environment": "development",
        ])
        XCTAssertTrue(exists("development"), "Development 应看得到自己的凭证")
        XCTAssertFalse(exists("production"),
                       "Production 绝不能拿 Development 的凭证兜底 —— 那正是 401 的来源")
    }

    /// 两个环境各自配好后互不影响。
    func testBothEnvironmentsCoexist() throws {
        try write("cloudkit.development.json", [
            "keyID": "dev-key", "privateKey": "p", "containerID": "iCloud.bugod2.ItemManager",
        ])
        try write("cloudkit.production.json", [
            "keyID": "prod-key", "privateKey": "p", "containerID": "iCloud.bugod2.ItemManager",
        ])
        XCTAssertTrue(exists("development"))
        XCTAssertTrue(exists("production"))
        XCTAssertEqual(
            OpsPublisherBridge.credentialSummary(
                environmentName: "production", credentialsDirectory: credentials)?.keyID,
            "prod-key",
            "Production 必须拿到自己的 keyID，而不是 Development 的")
    }

    /// 旧版那一份 `cloudkit.json` 仍要能用（**且只对 Development 生效**）。
    ///
    /// 不给它兜底会让已经配好的机器一升级就「凭证没了」；
    /// 给 Production 兜底则等于把 401 这个坑原样保留下来。
    func testLegacyFileStillWorksButOnlyForDevelopment() throws {
        try write("cloudkit.json", [
            "keyID": "legacy", "privateKey": "p", "containerID": "iCloud.bugod2.ItemManager",
        ])
        XCTAssertTrue(exists("development"), "旧配置不该无声失效")
        XCTAssertFalse(exists("production"),
                       "旧凭证给 Production 兜底 = 把 401 换个更隐蔽的位置")
    }

    // MARK: - 本机演练

    /// 本机演练走 filesystem 适配器，不联网 —— 不应该被要求配凭证。
    func testLocalFixtureRequiresNoCredential() {
        XCTAssertFalse(
            OpsPublisherBridge.requiresCredentialFile(
                environmentName: ShopCatalogPublishTargetEnvironment.localFixture.rawValue))
        XCTAssertTrue(
            OpsPublisherBridge.requiresCredentialFile(environmentName: "development"))
        XCTAssertTrue(
            OpsPublisherBridge.requiresCredentialFile(environmentName: "production"))
    }

    // MARK: - 摘要

    /// 摘要里**只**放 containerID / keyID，私钥一个字都不能出现。
    func testSummaryExposesOnlyNonSecretFields() throws {
        try write("cloudkit.production.json", [
            "keyID": "prod-key", "privateKey": "SUPER-SECRET-PEM",
            "containerID": "iCloud.bugod2.ItemManager", "environment": "production",
        ])
        let summary = try XCTUnwrap(
            OpsPublisherBridge.credentialSummary(
                environmentName: "production", credentialsDirectory: credentials))
        XCTAssertEqual(summary.keyID, "prod-key")
        XCTAssertEqual(summary.containerID, "iCloud.bugod2.ItemManager")
        XCTAssertEqual(summary.declaredEnvironment, "production")
        XCTAssertTrue(summary.declaredEnvironmentMatches)
        XCTAssertNil(summary.parseError)
        // 私钥不进摘要（这条要是红了，说明有人把私钥接进了界面/日志链路）
        XCTAssertFalse(summary.displayText.contains("SUPER-SECRET"))
        XCTAssertFalse(summary.displayText.contains("privateKey"))
    }

    /// 凭证声明的环境与目标不一致时必须**标出来**（由调用方拦，见 `ensureReady`）。
    func testMismatchedDeclaredEnvironmentIsFlagged() throws {
        try write("cloudkit.production.json", [
            "keyID": "dev-key", "privateKey": "p",
            "containerID": "iCloud.bugod2.ItemManager", "environment": "development",
        ])
        let summary = try XCTUnwrap(
            OpsPublisherBridge.credentialSummary(
                environmentName: "production", credentialsDirectory: credentials))
        XCTAssertEqual(summary.declaredEnvironment, "development")
        XCTAssertFalse(summary.declaredEnvironmentMatches,
                       "拿 Development 的凭证发 Production 必须在跑之前就被标出来")
    }

    /// 文件在但**内容不对**时也要报出来 —— 返回 nil 会被当成「没配」，就一直没人管。
    func testUnparsableCredentialIsReportedNotSilentlyIgnored() throws {
        try "not json at all".write(
            to: credentials.appendingPathComponent("cloudkit.development.json"),
            atomically: true, encoding: .utf8)
        let summary = try XCTUnwrap(
            OpsPublisherBridge.credentialSummary(
                environmentName: "development", credentialsDirectory: credentials),
            "文件在但解析不了时必须返回一个带 parseError 的摘要")
        XCTAssertNotNil(summary.parseError)
    }

    /// 没配凭证 = 摘要为 nil（界面据此显示「未配置」）。
    func testMissingCredentialYieldsNoSummary() {
        XCTAssertNil(OpsPublisherBridge.credentialSummary(
            environmentName: "production", credentialsDirectory: credentials))
    }

    // MARK: - 缺凭证的错误文案

    /// 缺凭证的报错必须点明「这是哪个环境」与「s2s key 按环境注册」——
    /// 只说「凭证不可用」会把人引向「再选一次同一个文件」。
    func testCredentialMissingMessageNamesTheEnvironmentAndTheRule() {
        let text = OpsBridgeError.credentialMissing(environment: "production").errorDescription ?? ""
        XCTAssertTrue(text.contains("production"), "报错要点名是哪个环境：\(text)")
        XCTAssertTrue(text.contains("401"), "要说出混用的后果（401）：\(text)")
    }

    // MARK: - 设置注入不污染持久化

    /// 注入口默认是 nil —— 真实运行必须走容器内的默认位置，
    /// 否则「测试专用目录」会渗进生产路径。
    func testDefaultSettingsHaveNoCredentialOverride() {
        let settings = OpsBridgeSettings()
        XCTAssertNil(settings.credentialsDirectoryOverride)
        XCTAssertNil(settings.credentialsDirectoryOverrideURL)
    }

    /// 注入口能往返编解码（它存在是为了可测，但不能因此破坏持久化）。
    func testCredentialOverrideSurvivesCodableRoundTrip() throws {
        var settings = OpsBridgeSettings()
        settings.credentialsDirectoryOverride = "/tmp/ops-credentials"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(OpsBridgeSettings.self, from: data)
        XCTAssertEqual(decoded.credentialsDirectoryOverride, "/tmp/ops-credentials")
    }

    /// 旧存档（没有这个键）仍能解出来：新增字段必须是 Optional 才不会让老配置失效。
    func testLegacyStoredSettingsWithoutOverrideStillDecode() throws {
        let legacy = """
        {"repoRootPath":"/repo","timeoutSeconds":900}
        """
        let decoded = try JSONDecoder().decode(
            OpsBridgeSettings.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.credentialsDirectoryOverride)
        XCTAssertEqual(decoded.repoRootPath, "/repo")
    }
}
