import XCTest
@testable import PinkHouseOpsCore

final class OpsSyncWorkflowTests: XCTestCase {
    func testInterruptedUploadPreservesDownloadAndRequiresConfirmation() throws {
        var report = OpsSyncReport(draftID: "draft", environment: "development")
        report.update(.download, state: .completed, detail: "已下载")
        report.update(.upload, state: .running, detail: "发送发布头")
        var restored = try JSONDecoder().decode(OpsSyncReport.self, from: JSONEncoder().encode(report))
        restored.recoverInterruptedRun()
        XCTAssertEqual(restored.steps.map(\.state), [.completed, .failed, .skipped])
        XCTAssertEqual(restored.steps.first?.progress, 1)
        XCTAssertTrue(restored.issues.first?.message.contains("先查询发布结果") == true)
        XCTAssertFalse(restored.isRunning)
        XCTAssertFalse(restored.isComplete)
        let recovered = restored
        restored.recoverInterruptedRun()
        XCTAssertEqual(restored, recovered)
    }

    @MainActor func testUploadFailureStillMergesDownloadedContent() async {
        var calls: [String] = []
        let result = await OpsSyncWorkflow.run(report: .init(draftID: "draft", environment: "development"),
            download: { calls.append("download"); return .init(.completed, "目录已下载") },
            upload: { calls.append("upload"); return .init(.failed, "网络失败") },
            merge: { calls.append("merge"); return .init(.completed, "下载内容已保存") }, changed: { _ in })
        XCTAssertEqual(calls, ["download", "upload", "merge"])
        XCTAssertEqual(result.steps.map(\.state), [.completed, .failed, .completed])
        XCTAssertEqual(result.title, "同步部分完成")
        XCTAssertFalse(result.isComplete)
    }

    @MainActor func testMissingLocalImagesBlockUploadOnly() async {
        let issue = OpsSyncIssue(id: "image", step: .upload, owner: "某尺码表", message: "缺少 img.jpg")
        let result = await OpsSyncWorkflow.run(report: .init(draftID: "draft", environment: "development"),
            download: { .init(.completed, "目录已下载") },
            upload: { .init(.blocked, "未发送发布请求", issues: [issue]) },
            merge: { .init(.completed, "已保存") }, changed: { _ in })
        XCTAssertEqual(result.steps.map(\.state), [.completed, .blocked, .completed])
        XCTAssertEqual(result.issues, [issue])
        XCTAssertTrue(result.summary.contains("某尺码表：缺少 img.jpg"),
                      "系列配置的同步反馈必须说明具体问题，不能只显示待修复数量")
    }

    @MainActor func testNoTrustedCatalogNeverAttemptsUpload() async {
        var called = false
        let result = await OpsSyncWorkflow.run(report: .init(draftID: "draft", environment: "development"),
            download: { .init(.failed, "根摘要不符", canContinue: false) },
            upload: { called = true; return .init(.completed, "不应执行") },
            merge: { called = true; return .init(.completed, "不应执行") }, changed: { _ in })
        XCTAssertFalse(called)
        XCTAssertEqual(result.steps.map(\.state), [.failed, .skipped, .skipped])
        XCTAssertEqual(result.title, "同步未完成")
    }

    @MainActor func testPartialMediaDownloadDoesNotUndoConfirmedUpload() async {
        let result = await OpsSyncWorkflow.run(report: .init(draftID: "draft", environment: "development"),
            download: { .init(.partial, "目录成功，1 张图未完成", progress: 0.75) },
            upload: { .init(.completed, "回读成功", releaseSeq: 6) },
            merge: { .init(.completed, "已保存") }, changed: { _ in })
        XCTAssertEqual(result.releaseSeq, 6)
        XCTAssertEqual(result.title, "同步部分完成")
        XCTAssertEqual(result.steps.first?.progress, 0.75)
    }

    @MainActor func testAllThreeCompletedIsTheOnlyOverallSuccess() async {
        var reports: [OpsSyncReport] = []
        let result = await OpsSyncWorkflow.run(report: .init(draftID: "draft", environment: "development"),
            download: { .init(.completed, "已下载") }, upload: { .init(.completed, "已上传", releaseSeq: 6) },
            merge: { .init(.completed, "已合并") }, changed: { reports.append($0) })
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.title, "同步完成")
        XCTAssertEqual(reports.filter(\.isRunning).first?.steps.first?.state, .running)
        XCTAssertEqual(result.steps.map(\.progress), [1, 1, 1])
    }

    @MainActor func testMergeDiskFailureCannotReportComplete() async throws {
        let result = await OpsSyncWorkflow.run(report: .init(draftID: "draft", environment: "development"),
            download: { .init(.completed, "已下载") }, upload: { .init(.completed, "已上传", releaseSeq: 6) },
            merge: { .init(.failed, "磁盘写失败") }, changed: { _ in })
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.steps.last?.state, .failed)
        let decoded = try JSONDecoder().decode(OpsSyncReport.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
    }
}
