//
//  ShopCatalogPublishProtocolTests.swift
//  SharedCatalogTests
//
//  发布协议与执行状态机（方案 §5.2 / §6.2 / R09 / T12）。
//
//  ## 这份测试要防的是什么
//
//  发布链路上最贵的错误是「**把结果不明当成可以重发**」：
//  发布头可能已经切成功、只是响应丢了。这时换一个发布号重发会造成
//  重复发布，甚至用旧内容回写已经前进的线上版本。
//
//  所以这里把状态机的**反向断言**也钉死：
//    · `switchingHead → retryableFailure` **必须不被允许**；
//    · `pendingConfirmation` **不得允许直接重提**（必须先查询）；
//    · 任何「说不清」的结论都必须落到 `pendingConfirmation`，不得落到 `confirmed`。
//
//  另一条同样重要：**幂等键必须只由「冻结快照」决定**。
//  同一份快照重复点提交要复用同一个 requestID；内容一变就必须换新号。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogPublishProtocolTests: XCTestCase {

    private let mediaHash = String(repeating: "7f", count: 32)

    // MARK: 幂等键

    func testSameFrozenSnapshotReusesRequestKey() {
        let first = ShopCatalogPublishRequestKey.make(
            draftID: "draft-1", draftRevision: 7, payloadHash: mediaHash,
            targetEnvironment: .development, releaseSeq: 5)
        let second = ShopCatalogPublishRequestKey.make(
            draftID: "draft-1", draftRevision: 7, payloadHash: mediaHash,
            targetEnvironment: .development, releaseSeq: 5)

        XCTAssertEqual(first, second, "同一冻结快照重复提交必须复用同一个请求号")
    }

    func testChangingContentChangesRequestKey() {
        let base = ShopCatalogPublishRequestKey.make(
            draftID: "draft-1", draftRevision: 7, payloadHash: mediaHash,
            targetEnvironment: .development, releaseSeq: 5)

        XCTAssertNotEqual(
            base,
            ShopCatalogPublishRequestKey.make(
                draftID: "draft-1", draftRevision: 8, payloadHash: mediaHash,
                targetEnvironment: .development, releaseSeq: 5),
            "改了内容（版本 +1）必须是新请求")
        XCTAssertNotEqual(
            base,
            ShopCatalogPublishRequestKey.make(
                draftID: "draft-1", draftRevision: 7, payloadHash: String(repeating: "9a", count: 32),
                targetEnvironment: .development, releaseSeq: 5),
            "产物摘要变了必须是新请求")
        XCTAssertNotEqual(
            base,
            ShopCatalogPublishRequestKey.make(
                draftID: "draft-1", draftRevision: 7, payloadHash: mediaHash,
                targetEnvironment: .production, releaseSeq: 5),
            "换了环境必须是新请求（否则回执会张冠李戴）")
        XCTAssertNotEqual(
            base,
            ShopCatalogPublishRequestKey.make(
                draftID: "draft-1", draftRevision: 7, payloadHash: mediaHash,
                targetEnvironment: .development, releaseSeq: 6),
            "显式改了发布号也是新请求")
    }

    // MARK: 执行状态机

    func testHeadSwitchCannotFallBackToRetryable() {
        XCTAssertFalse(
            ShopCatalogPublishExecutionState.canTransition(from: .switchingHead, to: .retryableFailure),
            "切头之后绝不允许直接判「可重试」—— 那正是重复发布的成因")
        XCTAssertTrue(
            ShopCatalogPublishExecutionState.canTransition(from: .switchingHead, to: .pendingConfirmation))
        XCTAssertTrue(
            ShopCatalogPublishExecutionState.canTransition(from: .switchingHead, to: .confirmed))
    }

    func testPendingConfirmationMustBeQueriedBeforeResubmit() {
        let state = ShopCatalogPublishExecutionState.pendingConfirmation
        XCTAssertFalse(state.allowsResubmit, "结果待确认时不得直接重提")
        XCTAssertTrue(state.requiresResultQuery)
        XCTAssertTrue(state.isTerminal)

        // 查询出来的三种结论都必须可达
        XCTAssertTrue(ShopCatalogPublishExecutionState.canTransition(from: .pendingConfirmation, to: .confirmed))
        XCTAssertTrue(ShopCatalogPublishExecutionState.canTransition(from: .pendingConfirmation, to: .replaced))
        XCTAssertTrue(ShopCatalogPublishExecutionState.canTransition(from: .pendingConfirmation, to: .retryableFailure))
        // 但「待确认 → 待确认」不是合法推进（那等于什么都没查）
        XCTAssertFalse(ShopCatalogPublishExecutionState.canTransition(from: .pendingConfirmation, to: .pendingConfirmation))
    }

    func testBeforeHeadSwitchFailuresAreRetryable() {
        for state in [ShopCatalogPublishExecutionState.building, .uploading, .verifying] {
            XCTAssertTrue(
                ShopCatalogPublishExecutionState.canTransition(from: state, to: .retryableFailure),
                "\(state.rawValue) 在切头前失败，线上仍是旧版本，应可安全重试")
        }
    }

    func testOnlyConfirmedCountsAsLive() {
        for state in ShopCatalogPublishExecutionState.allCases where state != .confirmed {
            XCTAssertFalse(state.isLive, "只有 confirmed 能说「已对用户生效」，\(state.rawValue) 不行")
        }
        XCTAssertTrue(ShopCatalogPublishExecutionState.confirmed.isLive)
        XCTAssertFalse(ShopCatalogPublishExecutionState.verifying.isLive, "「回读核对通过」不等于「已生效」")
    }

    func testOutcomeMappingNeverOptimistic() {
        XCTAssertEqual(ShopCatalogPublishOutcome.confirmed.executionState, .confirmed)
        XCTAssertEqual(ShopCatalogPublishOutcome.pendingConfirmation.executionState, .pendingConfirmation)
        XCTAssertEqual(ShopCatalogPublishOutcome.conflict.executionState, .conflict)
        XCTAssertEqual(ShopCatalogPublishOutcome.replaced.executionState, .replaced)
        XCTAssertEqual(ShopCatalogPublishOutcome.refused.executionState, .refused)
        XCTAssertEqual(
            ShopCatalogPublishOutcome.failed.executionState, .retryableFailure,
            "普通失败（切头前）才映射成可重试")
    }

    // MARK: 阶段与七步顺序

    func testStagesBeforeHeadSwitchAreMarkedAsSuch() {
        XCTAssertTrue(ShopCatalogPublishStage.readBack.isBeforeHeadSwitch)
        XCTAssertTrue(ShopCatalogPublishStage.uploadMedia.isBeforeHeadSwitch)
        XCTAssertFalse(ShopCatalogPublishStage.switchHead.isBeforeHeadSwitch)
        XCTAssertFalse(ShopCatalogPublishStage.confirmHead.isBeforeHeadSwitch)
        XCTAssertTrue(ShopCatalogPublishStage.switchHead.changesLiveVersion)
        XCTAssertFalse(ShopCatalogPublishStage.uploadPacks.changesLiveVersion)
    }

    // MARK: 事件解码

    func testDecodesStageEventLine() throws {
        let line = #"{"type":"stage","stage":"uploadMedia","state":"started","stepOrdinal":3,"completed":1,"total":4}"#
        let event = try XCTUnwrap(ShopCatalogPublishEvent.decoded(fromLine: line))

        XCTAssertEqual(event.type, "stage")
        XCTAssertEqual(event.stage, .uploadMedia)
        XCTAssertEqual(event.state, .started)
        XCTAssertEqual(event.stepOrdinal, 3)
        XCTAssertEqual(event.completed, 1)
        XCTAssertEqual(event.total, 4)
        XCTAssertNotNil(event.displayLine)
    }

    func testDecodesUnknownEventTypeWithoutLosingLine() throws {
        // 桥接器升级后多出一种 type：老 App 必须能解出来并保留原文，
        // 不能整行解不出来（那会让界面停在「上传中」且无从定位）
        let line = #"{"type":"future_thing","message":"新协议字段","unknownField":123}"#
        let event = try XCTUnwrap(ShopCatalogPublishEvent.decoded(fromLine: line))
        XCTAssertEqual(event.type, "future_thing")
        XCTAssertEqual(event.message, "新协议字段")
    }

    func testNonJSONLineIsRejected() {
        XCTAssertNil(ShopCatalogPublishEvent.decoded(fromLine: "[3/7] 上传缺失媒体"))
        XCTAssertNil(ShopCatalogPublishEvent.decoded(fromLine: ""))
    }

    // MARK: 请求 / 回执往返

    func testRequestRoundTripKeepsFrozenFacts() throws {
        let request = ShopCatalogPublishRequest(
            requestID: "req-1",
            jobID: "job-1",
            draftID: "draft-1",
            draftRevision: 12,
            baseReleaseSeq: 4,
            baseRootIndexHash: mediaHash,
            baselineAcknowledged: true,
            targetEnvironment: .development,
            releaseSeq: 5,
            inputDirectory: "/tmp/in",
            archivePath: "/tmp/in/catalog.tar",
            outputDirectory: "/tmp/out",
            receiptPath: "/tmp/out/receipt.json",
            filesystemRoot: "/tmp/fs",
            dryRun: false,
            payloadHash: mediaHash)

        let decoded = try ShopCatalogPublishRequest.decoded(from: try request.encoded())
        XCTAssertEqual(decoded.requestID, "req-1")
        XCTAssertEqual(decoded.draftRevision, 12)
        XCTAssertEqual(decoded.baseReleaseSeq, 4)
        XCTAssertEqual(decoded.baselineAcknowledged, true)
        XCTAssertEqual(decoded.targetEnvironment, .development)
        // 适配器不再由环境派生（两个环境都走 CloudKit）：不显式传就是 cloudkit。
        XCTAssertEqual(decoded.adapter, .cloudkit)
        XCTAssertEqual(decoded.filesystemRoot, "/tmp/fs")
    }

    func testReceiptSummaryDoesNotClaimLiveWithoutApply() {
        let rehearsal = ShopCatalogPublishReceipt(
            adapter: "cloudkit", environment: "development", applied: false, releaseSeq: 5,
            readBackConfirmed: true)
        XCTAssertTrue(rehearsal.summaryText.contains("演练"))

        let unconfirmed = ShopCatalogPublishReceipt(
            adapter: "cloudkit", environment: "development", applied: true, releaseSeq: 5,
            readBackConfirmed: false)
        XCTAssertTrue(unconfirmed.summaryText.contains("未回读确认"))
    }

    func testEnvironmentsAreOnlyRealRemotes() {
        // 环境派生适配器的那套（`localFixture` → filesystem）已随本机演练一并移除：
        // 现在**只有**两个真实远端，面板上不会再出现「点了也不联网」的选项。
        XCTAssertEqual(ShopCatalogPublishTargetEnvironment.allCases.map(\.rawValue),
                       ["development", "production"])
    }
}
