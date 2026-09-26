//
//  OpsBridgeSettingsTests.swift
//  PinkHouseOpsTests
//
//  桥接器**自检**的测试。
//
//  ## 为什么值得测
//
//  沙盒 App 读不到容器外的路径，所以「能不能跑发布」取决于用户有没有授权仓库目录、
//  解释器在不在。`OpsBridgeSettings.diagnosis()` 是运营**唯一**的自救线索 ——
//  它少报一条，「工具坏了」就会变成无从下手；多报一条，运营会去修一个不存在的问题。
//
//  这几条用例不依赖本机装了哪种 python：`pythonPath` 显式指到 `/bin/sh`
//  （一定存在），于是「解释器可用性」这一项变成确定的。
//

import XCTest
@testable import PinkHouseOpsCore
import SharedCatalog

final class OpsBridgeSettingsTests: XCTestCase {

    // MARK: - 解释器候选

    func testExplicitPythonPathWins() {
        let candidates = OpsBridgeSettings.pythonCandidates(explicit: "/custom/bin/python3")
        XCTAssertEqual(candidates.first, "/custom/bin/python3")
        XCTAssertTrue(candidates.contains("/usr/bin/python3"), "系统解释器应留在候选里兜底")
    }

    func testBlankExplicitPathIsIgnored() {
        let withoutExplicit = OpsBridgeSettings.pythonCandidates(explicit: nil)
        XCTAssertEqual(OpsBridgeSettings.pythonCandidates(explicit: ""), withoutExplicit)
    }

    /// ⭐ 回归锁：仓库内的 `.venv` 必须排在系统解释器**前面**。
    ///
    /// 为什么这条最贵（2026-09-27 探针实测）：本机既没有
    /// `/opt/homebrew/bin/python3`，也没有 `/usr/local/bin/python3`，于是旧顺序
    /// 会选中 `/usr/bin/python3` —— 而它在沙盒里子进程直接吐
    /// `xcrun: error: cannot be used within an App Sandbox.`。
    /// 也就是说旧顺序让「自动探测」在沙盒下 **100% 选错**，
    /// 而正确那个（装了 `cryptography` 的 venv）恰好就在仓库里。
    func testRepoVenvBeatsSystemPythons() {
        let publication = URL(fileURLWithPath: "/repo/tools/time_hall/publication", isDirectory: true)
        let candidates = OpsBridgeSettings.pythonCandidates(explicit: nil,
                                                            publicationDirectory: publication)
        let venv = "/repo/tools/time_hall/publication/.venv/bin/python3"
        XCTAssertEqual(candidates.first, venv, "venv 必须最先被看到：\(candidates)")
        let venvIndex = try? XCTUnwrap(candidates.firstIndex(of: venv))
        let systemIndex = try? XCTUnwrap(candidates.firstIndex(of: "/usr/bin/python3"))
        XCTAssertNotNil(venvIndex)
        XCTAssertNotNil(systemIndex)
        if let venvIndex, let systemIndex {
            XCTAssertLessThan(venvIndex, systemIndex, "venv 必须先于 /usr/bin/python3：\(candidates)")
        }
        XCTAssertTrue(candidates.contains("/usr/bin/python3"), "系统解释器仍要留在候选里兜底")
    }

    /// 显式设置永远第一，哪怕给出了仓库目录 —— 否则「用户手动指定」这句承诺就是假的。
    func testExplicitStillWinsOverRepoVenv() {
        let publication = URL(fileURLWithPath: "/repo/tools/time_hall/publication", isDirectory: true)
        let candidates = OpsBridgeSettings.pythonCandidates(explicit: "/custom/bin/python3",
                                                            publicationDirectory: publication)
        XCTAssertEqual(candidates.first, "/custom/bin/python3")
    }

    /// 不给仓库目录时不应凭空多出一个 `.venv` 候选（老调用点的行为必须逐字不变）。
    func testNoPublicationDirectoryMeansNoVenvCandidate() {
        let candidates = OpsBridgeSettings.pythonCandidates(explicit: nil,
                                                            publicationDirectory: nil)
        XCTAssertFalse(candidates.contains { $0.contains(".venv") }, "候选表：\(candidates)")
    }

    // MARK: - 可读性（存在性 ≠ 可读）

    /// ⭐ 回归锁：判据必须是**真读**。
    ///
    /// 沙盒下 `fileExists` 与 `open` 走两套判定（实测：`fileExists`=true 而
    /// `Data(contentsOf:)`=`Operation not permitted`），所以桥接器如果只用
    /// `fileExists` 放行，就会在「用户还没授权」这个最常见场景下一路跑到
    /// `process.run()`，最后报「退出码 1、没有输出」——把「没权限」说成「脚本坏了」。
    func testIsReadableFileDistinguishesMissingFromPresent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinkhouse-readable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("ops_publish_bridge.py")
        try Data("#!/bin/sh\n".utf8).write(to: file)

        XCTAssertTrue(OpsBridgeSettings.isReadableFile(file), "存在且可读 → true")
        XCTAssertFalse(OpsBridgeSettings.isReadableFile(directory.appendingPathComponent("nope.py")),
                       "不存在 → false")
        XCTAssertFalse(OpsBridgeSettings.isReadableFile(directory), "目录（不是文件）→ false")
    }

    /// 空文件算「可读」：这里判的是权限，不是内容。
    /// （若判成不可读，一个被 `: >` 截空的脚本会给出「没有权限」这种完全错的指引。）
    func testEmptyFileIsReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinkhouse-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("empty.py")
        try Data().write(to: file)
        XCTAssertTrue(OpsBridgeSettings.isReadableFile(file))
    }

    // MARK: - 授权作用域

    /// 没有 bookmark 时必须**如实**报 `accessed = false` 且 `stop` 可安全调用。
    ///
    /// 探针靠这个布尔值区分「授权拿到了」与「设置里只有路径」——而后者在沙盒下
    /// 必然读不到仓库。若这里撒谎说 `true`，探针的整条对照链就失去意义。
    func testScopeWithoutBookmarkReportsNotAccessedAndStopsSafely() {
        let settings = OpsBridgeSettings(repoRootPath: "/tmp", repoRootBookmark: nil)
        let access = settings.beginAuthorizedRepoRootScope()
        XCTAssertFalse(access.accessed)
        access.stop()
        access.stop()   // 重复调用必须无害（diagnosis 每次刷新都会走一对）
    }

    /// 坏 bookmark 不能崩，也不能谎报拿到了授权。
    func testBrokenBookmarkReportsNotAccessed() {
        let settings = OpsBridgeSettings(repoRootPath: "/tmp", repoRootBookmark: Data([0x00, 0x01]))
        let access = settings.beginAuthorizedRepoRootScope()
        XCTAssertFalse(access.accessed)
        access.stop()
    }

    // MARK: - 自检

    func testDiagnosisReportsMissingAuthorization() {
        var settings = OpsBridgeSettings()
        settings.repoRootPath = nil
        let problems = settings.diagnosis()
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("授权"), "应说清是「还没授权目录」：\(problems)")
    }

    func testDiagnosisIsEmptyWhenEverythingIsReady() throws {
        let root = try makeRepoFixture(withScript: true)
        var settings = OpsBridgeSettings()
        settings.repoRootPath = root.path
        settings.pythonPath = "/bin/sh"
        XCTAssertEqual(settings.diagnosis(), [], "仓库与解释器都就绪时不该报任何问题")
    }

    func testDiagnosisReportsMissingScript() throws {
        let root = try makeRepoFixture(withScript: false)
        var settings = OpsBridgeSettings()
        settings.repoRootPath = root.path
        settings.pythonPath = "/bin/sh"
        let problems = settings.diagnosis()
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("找不到桥接脚本"), "问题描述应点名脚本缺失：\(problems)")
        XCTAssertTrue(problems[0].contains("ops_publish_bridge.py"),
                      "应给出具体路径，方便运营自己去看：\(problems)")
    }

    // MARK: - 夹具

    /// 造一个「像仓库」的目录：`tools/time_hall/publication/ops_publish_bridge.py`。
    private func makeRepoFixture(withScript: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinkhouse-settings-\(UUID().uuidString)", isDirectory: true)
        let publication = root.appendingPathComponent("tools/time_hall/publication", isDirectory: true)
        try FileManager.default.createDirectory(at: publication, withIntermediateDirectories: true)
        if withScript {
            try Data("#!/bin/sh\n".utf8)
                .write(to: publication.appendingPathComponent("ops_publish_bridge.py"))
        }
        return root
    }
}
