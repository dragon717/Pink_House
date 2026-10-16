import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsCatalogEditSyncTests: XCTestCase {
    private func request(_ revision: Int, draft: String = "draft", environment: String = "production") -> OpsCatalogEditSyncQueue.Request {
        .init(id: "save-\(revision)", draftID: draft, revision: revision, environment: environment)
    }

    @MainActor func testRapidSavesCoalesceToLatestRevision() async {
        var pending: OpsCatalogEditSyncQueue.Request? = request(1)
        var calls: [Int] = []
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { false }, publish: {
            calls.append($0.revision); return .confirmed(10)
        }, finished: { _, _ in pending = nil }, debounce: {})
        queue.resume()
        pending = request(2)
        queue.resume()
        await queue.waitUntilIdle()
        XCTAssertEqual(calls, [2])
    }

    @MainActor func testSaveDuringPublishIsNotLost() async {
        var pending: OpsCatalogEditSyncQueue.Request? = request(1)
        var calls: [Int] = []
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { false }, publish: {
            calls.append($0.revision)
            if $0.revision == 1 { pending = self.request(2) }
            return .confirmed(10)
        }, finished: { request, _ in if pending == request { pending = nil } }, debounce: {})
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, [1, 2])
    }

    @MainActor func testFailedRequestPausesAndNewExplicitSaveCanProceed() async {
        var pending: OpsCatalogEditSyncQueue.Request? = request(1)
        var calls: [Int] = []
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { false }, publish: {
            calls.append($0.revision); return .failed("结果不确定")
        }, finished: { _, _ in }, debounce: {})
        queue.resume(); await queue.waitUntilIdle()
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, [1])
        pending = request(2)
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, [1, 2])
    }

    @MainActor func testExternalPublishBusyPreservesPendingRequest() async {
        var busy = true
        var pending: OpsCatalogEditSyncQueue.Request? = request(1)
        var calls = 0
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { busy }, publish: { _ in
            calls += 1; return .confirmed(10)
        }, finished: { _, _ in pending = nil }, debounce: {})
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, 0); XCTAssertNotNil(pending)
        busy = false
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testExplicitRetryKeepsSameRequestAndDoesNotStartAnAutomaticFailureLoop() async {
        let original = request(1)
        var pending: OpsCatalogEditSyncQueue.Request? = original
        var calls: [OpsCatalogEditSyncQueue.Request] = []
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { false }, publish: {
            calls.append($0)
            return calls.count == 1 ? .failed("结果待确认") : .confirmed(24)
        }, finished: { _, result in if case .confirmed = result { pending = nil } }, debounce: {})
        queue.resume(); await queue.waitUntilIdle()
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, [original])
        queue.retryFailedRequest(); await queue.waitUntilIdle()
        XCTAssertEqual(calls, [original, original])
        XCTAssertNil(pending)
    }

    @MainActor func testSwitchingDraftDuringDebounceUsesNewOwner() async {
        var pending: OpsCatalogEditSyncQueue.Request? = request(1)
        var owners: [String] = []
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { false }, publish: {
            owners.append($0.draftID); return .confirmed(10)
        }, finished: { _, _ in pending = nil }, debounce: {})
        queue.resume(); pending = request(2, draft: "other")
        await queue.waitUntilIdle()
        XCTAssertEqual(owners, ["other"])
    }

    @MainActor func testUnclearedConfirmedRequestDoesNotLoop() async {
        let pending = request(1)
        var count = 0
        let queue = OpsCatalogEditSyncQueue(pending: { pending }, isBusy: { false }, publish: { _ in
            count += 1; return .confirmed(10)
        }, finished: { _, _ in }, debounce: {})
        queue.resume(); await queue.waitUntilIdle()
        XCTAssertEqual(count, 1)
    }

    func testUndeclaredPhasePreservesBothDateIntervals() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let input = OpsSeriesSalePhaseInput(declaresPhase: false, phase: .reservationActive,
            reservationStartAt: start, reservationEndAt: end,
            balanceDueKind: .exact, balanceDueText: "旧描述",
            balanceDueAt: start, balanceDueEndAt: end)
        XCTAssertNil(input.phase)
        XCTAssertEqual(input.reservationStartAt, start)
        XCTAssertEqual(input.reservationEndAt, end)
        XCTAssertEqual(input.balanceDueKind, .exact)
        XCTAssertEqual(input.balanceDueAt, start)
        XCTAssertEqual(input.balanceDueEndAt, end)
        XCTAssertNil(input.balanceDueText)
    }

    func testApproximateDescriptionIndependentOfDeclaration() {
        let input = OpsSeriesSalePhaseInput(declaresPhase: false, phase: .reservationActive,
            reservationStartAt: nil, reservationEndAt: nil,
            balanceDueKind: .approximate, balanceDueText: "  大货后一个月  ",
            balanceDueAt: Date(), balanceDueEndAt: Date())
        XCTAssertEqual(input.balanceDueText, "大货后一个月")
        XCTAssertEqual(input.balanceDueKind, .approximate)
        XCTAssertNil(input.balanceDueAt); XCTAssertNil(input.balanceDueEndAt)
    }

    func testEmptyOptionalBalanceDoesNotManufactureInvalidDate() {
        for kind in [CatalogBalanceDueKind.exact, .approximate] {
            let input = OpsSeriesSalePhaseInput(declaresPhase: true, phase: .reservationActive,
                reservationStartAt: nil, reservationEndAt: Date(),
                balanceDueKind: kind, balanceDueText: " ", balanceDueAt: nil, balanceDueEndAt: nil)
            XCTAssertEqual(input.phase, .reservationActive)
            XCTAssertNil(input.balanceDueKind)
        }
    }
}
