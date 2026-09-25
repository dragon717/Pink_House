//
//  ShopCatalogMediaJobMachineTests.swift
//
//  图片上传任务状态机。
//
//  ## 为什么状态机要有测试，而不是「看起来对」
//
//  计划 §7 对失败的处置有三条硬口径，全都是「不许静默」：
//    1. 网络失败 —— 任务不丢，退避后可重试；
//    2. **权限失败 —— 显示环境与角色，不盲目重试**（重试一万次也不会变）；
//    3. 图片已上传但发布头没切 —— 允许孤儿 `THMedia` 留在公共库，
//       下次按 hash 复用，所以 `verified` 是**可跨会话复用的终态**。
//
//  这三条一旦退化成「所有失败都进 retryable」，界面会永远转圈；
//  退化成「所有失败都进 failed」，一次网络抖动就让运营看到一片红。
//  所以转移表、重试预算、失败分类的映射必须逐条锁死。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogMediaJobMachineTests: XCTestCase {

    // MARK: 转移表

    func testAllowedTransitionsMatchPublishedFlow() {
        let allowed: [(MediaUploadJobState, MediaUploadJobState)] = [
            (.staged, .uploading),
            (.uploading, .verified),
            (.uploading, .failed),
            (.uploading, .retryable),
            (.retryable, .uploading),
            (.retryable, .failed),
            (.verified, .verified),      // 幂等复用
            (.uploading, .staged),       // 恢复用
        ]
        for (from, to) in allowed {
            XCTAssertTrue(
                MediaUploadJobMachine.canTransition(from: from, to: to),
                "\(from.rawValue) → \(to.rawValue) 应当允许")
        }
    }

    func testForbiddenTransitions() {
        // 终态不许自己乱跳：failed 只能由人处理后重新走流程
        XCTAssertFalse(MediaUploadJobMachine.canTransition(from: .failed, to: .uploading))
        XCTAssertFalse(MediaUploadJobMachine.canTransition(from: .failed, to: .verified))
        // 已核对通过的图不该被降级回待上传 / 待重试
        XCTAssertFalse(MediaUploadJobMachine.canTransition(from: .verified, to: .staged))
        XCTAssertFalse(MediaUploadJobMachine.canTransition(from: .verified, to: .retryable))
        // 不许跳过 uploading 直接从 staged 变成 verified（那就等于没核对 hash）
        XCTAssertFalse(MediaUploadJobMachine.canTransition(from: .staged, to: .verified))
        XCTAssertFalse(MediaUploadJobMachine.canTransition(from: .staged, to: .failed))
    }

    // MARK: 推进

    func testAdvanceToUploadingCountsAttemptAndClearsPreviousFailure() throws {
        var job = makeJob()
        job.failureKind = .network
        job.lastErrorMessage = "上一次的旧错误"
        job.state = .retryable

        try MediaUploadJobMachine.advance(&job, to: .uploading)

        XCTAssertEqual(job.state, .uploading)
        XCTAssertEqual(job.attemptCount, 1)
        XCTAssertNil(job.failureKind, "重试开始时要清掉旧失败原因，否则界面会一直挂着旧错误")
        XCTAssertNil(job.lastErrorMessage)
    }

    func testAdvanceToVerifiedStampsTimeAndIsIdempotent() throws {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        var job = makeJob()
        job.state = .uploading

        try MediaUploadJobMachine.advance(&job, to: .verified, now: moment)
        XCTAssertEqual(job.state, .verified)
        XCTAssertEqual(job.verifiedAt, moment)

        // 幂等复用：已上传的图再走一次流程，仍应确认是 verified
        try MediaUploadJobMachine.advance(&job, to: .verified, now: moment.addingTimeInterval(60))
        XCTAssertEqual(job.state, .verified)
        XCTAssertEqual(job.verifiedAt, moment.addingTimeInterval(60))
    }

    func testIllegalAdvanceThrowsAndLeavesJobUnchanged() {
        var job = makeJob()
        job.state = .staged
        let snapshot = job

        XCTAssertThrowsError(try MediaUploadJobMachine.advance(&job, to: .verified)) { error in
            guard case MediaUploadJobTransitionError.illegal(let from, let to) = error else {
                return XCTFail("期望 illegal，实际 \(error)")
            }
            XCTAssertEqual(from, .staged)
            XCTAssertEqual(to, .verified)
        }
        XCTAssertEqual(job, snapshot, "转移失败时不许改动入参，否则任务会被吞掉")
    }

    // MARK: 失败分类（计划 §7 的核心）

    func testPermissionFailureGoesStraightToFailedWithoutBurningRetries() throws {
        var job = makeJob()
        job.state = .uploading
        job.attemptCount = 1

        try MediaUploadJobMachine.recordFailure(
            &job, kind: .permission, message: "账号没有公共库写入权限")

        XCTAssertEqual(job.state, .failed, "权限失败重试无用，必须直接落到失败并让人看见")
        XCTAssertEqual(job.failureKind, .permission)
        XCTAssertEqual(job.lastErrorMessage, "账号没有公共库写入权限")
        XCTAssertFalse(MediaUploadFailureKind.permission.isRetryable)
    }

    func testValidationAndEnvironmentFailuresAlsoLandOnFailed() throws {
        for kind in [MediaUploadFailureKind.validation, .environment] {
            var job = makeJob()
            job.state = .uploading
            job.attemptCount = 1
            try MediaUploadJobMachine.recordFailure(&job, kind: kind, message: "x")
            XCTAssertEqual(job.state, .failed, "\(kind.rawValue) 不该自动重试")
        }
    }

    func testNetworkFailureBecomesRetryableWhileBudgetRemains() throws {
        var job = makeJob()
        job.state = .uploading
        job.attemptCount = 1

        try MediaUploadJobMachine.recordFailure(&job, kind: .network, message: "连接超时")

        XCTAssertEqual(job.state, .retryable)
        XCTAssertEqual(job.failureKind, .network)
        XCTAssertEqual(job.lastErrorMessage, "连接超时")
    }

    func testRetryBudgetExhaustionFallsToFailed() throws {
        var job = makeJob()
        job.state = .uploading
        job.attemptCount = MediaUploadJobMachine.maxAttempts

        try MediaUploadJobMachine.recordFailure(&job, kind: .network, message: "还是超时")

        XCTAssertEqual(job.state, .failed, "预算用尽必须落 failed —— 不允许无限重试把失败掩盖成转圈")
        XCTAssertEqual(job.attemptCount, MediaUploadJobMachine.maxAttempts)
    }

    func testUnknownFailureIsRetryableButConflictToo() {
        XCTAssertTrue(MediaUploadFailureKind.unknown.isRetryable)
        XCTAssertTrue(MediaUploadFailureKind.conflict.isRetryable)
        // 每种失败都必须给出人话处置建议，不许只显示一个红感叹号
        for kind in MediaUploadFailureKind.allCases {
            XCTAssertFalse(kind.guidance.isEmpty, "\(kind.rawValue) 缺少处置建议")
        }
    }

    // MARK: 退避

    func testRetryDelayIsExponentialAndCapped() {
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 0), 2)
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 1), 2)
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 2), 4)
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 3), 8)
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 4), 16)
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 5), 32)
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 6), 60, "2^6=64 要封顶到 60")
        XCTAssertEqual(MediaUploadJobMachine.retryDelay(forAttempt: 50), 60)
    }

    // MARK: 启动恢复

    func testRecoveredRollsUploadingBackToRetryable() {
        var job = makeJob()
        job.state = .uploading
        job.attemptCount = 2

        let restored = MediaUploadJobMachine.recovered(job)

        XCTAssertEqual(restored.state, .retryable, "进程被杀留下的 uploading 必须能继续推进")
        XCTAssertEqual(restored.attemptCount, 2, "恢复不改动重试预算")
    }

    func testRecoveredAlsoNormalizesStagedAndLeavesTerminalStatesAlone() {
        var staged = makeJob()
        staged.state = .staged
        XCTAssertEqual(MediaUploadJobMachine.recovered(staged).state, .retryable)

        var verified = makeJob()
        verified.state = .verified
        verified.verifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let untouched = MediaUploadJobMachine.recovered(verified)
        XCTAssertEqual(untouched, verified, "verified / failed 是可跨会话复用的终态，不许被恢复逻辑改写")
    }

    // MARK: 进度

    func testProgressCountsEachBucket() {
        var jobs: [MediaUploadJob] = []
        for index in 0..<6 {
            var job = makeJob(keySeed: index)
            job.state = [.staged, .uploading, .verified, .verified, .retryable, .failed][index]
            jobs.append(job)
        }

        let progress = MediaUploadJobMachine.progress(of: jobs)

        XCTAssertEqual(progress.total, 6)
        XCTAssertEqual(progress.verified, 2)
        XCTAssertEqual(progress.pending, 3, "staged / uploading / retryable 都还需要动作")
        XCTAssertEqual(progress.failed, 1)
        XCTAssertFalse(progress.isComplete)
        XCTAssertTrue(progress.hasFailures)
    }

    func testProgressIsCompleteOnlyWhenAllVerified() {
        var first = makeJob(keySeed: 1)
        first.state = .verified
        XCTAssertTrue(MediaUploadJobMachine.progress(of: [first]).isComplete)
        XCTAssertFalse(MediaUploadJobMachine.progress(of: []).isComplete, "空集合不算「全部完成」")
    }

    // MARK: 夹具

    private func makeJob(keySeed: Int = 0) -> MediaUploadJob {
        MediaUploadJob(
            mediaKey: String(format: "%064x", keySeed),
            stagedFileName: "\(String(format: "%064x", keySeed)).png",
            byteCount: 1024,
            mimeType: "image/png")
    }
}
