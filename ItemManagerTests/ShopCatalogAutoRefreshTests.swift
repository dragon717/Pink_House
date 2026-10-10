import XCTest
import CloudKit
@testable import ItemManager

@MainActor
final class ShopCatalogAutoRefreshTests: XCTestCase {
    func testForegroundChecksImmediatelyAndRepeatsWithoutReinstallingSubscription() async {
        var checks = 0
        var subscriptions = 0
        let refresher = ShopCatalogAutoRefresh(
            refresh: { checks += 1; await Task.yield() },
            installSubscription: { subscriptions += 1 },
            sleep: { if checks == 3 { throw CancellationError() } })
        await refresher.runWhileActive()
        XCTAssertEqual(checks, 3)
        XCTAssertEqual(subscriptions, 1)
    }

    func testSubscriptionFailureDoesNotStopRefreshAndRetriesAfterCooldown() async {
        var checks = 0
        var subscriptions = 0
        var clock = Date(timeIntervalSince1970: 1000)
        let refresher = ShopCatalogAutoRefresh(
            refresh: { checks += 1; await Task.yield() },
            installSubscription: {
                subscriptions += 1
                throw CKError(.notAuthenticated)
            },
            sleep: {
                clock.addTimeInterval(180)
                if checks == 4 { throw CancellationError() }
            }, now: { clock })
        await refresher.runWhileActive()
        XCTAssertEqual(checks, 4, "订阅受阻仍然能自动读取公开商品")
        XCTAssertEqual(subscriptions, 2, "失败订阅不能每 30 秒重试")
    }

    func testLeavingForegroundCancelsPolling() async {
        var checks = 0
        let waiting = expectation(description: "等待下一次检查")
        let refresher = ShopCatalogAutoRefresh(
            refresh: { checks += 1 }, installSubscription: {},
            sleep: {
                waiting.fulfill()
                try await Task.sleep(for: .seconds(60))
            })
        let running = Task { await refresher.runWhileActive() }
        await fulfillment(of: [waiting], timeout: 2)
        running.cancel()
        await running.value
        XCTAssertEqual(checks, 1)
    }

    func testReturningToForegroundChecksAgainImmediately() async {
        var checks = 0
        var subscriptions = 0
        let refresher = ShopCatalogAutoRefresh(
            refresh: { checks += 1; await Task.yield() },
            installSubscription: { subscriptions += 1 },
            sleep: { throw CancellationError() })
        await refresher.runWhileActive()
        await refresher.runWhileActive()
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(subscriptions, 1)
        refresher.accountDidChange()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(subscriptions, 2, "切换 iCloud 账户后重新安装订阅")
    }

    func testSubscriptionWatchesOnlyCommittedReleaseAndHasNoUserAlert() {
        let subscription = ShopCatalogReleaseNotifications.makeSubscription()
        XCTAssertEqual(subscription.recordType, "THRelease")
        XCTAssertEqual(subscription.subscriptionID, ShopCatalogReleaseNotifications.subscriptionID)
        XCTAssertTrue(subscription.querySubscriptionOptions.contains(.firesOnRecordCreation))
        XCTAssertTrue(subscription.querySubscriptionOptions.contains(.firesOnRecordUpdate))
        XCTAssertEqual(subscription.notificationInfo?.shouldSendContentAvailable, true)
        XCTAssertNil(subscription.notificationInfo?.alertBody)
        XCTAssertNil(subscription.notificationInfo?.soundName)
        XCTAssertEqual(subscription.notificationInfo?.shouldBadge, false)
        XCTAssertFalse(ShopCatalogReleaseNotifications.accepts(["aps": ["alert": "其他通知"]]))
    }

    func testReleaseNotificationRoutingIgnoresOtherSubscriptionsAndContainers() {
        func payload(subscription: String, container: String) -> [AnyHashable: Any] {
            ["ck": ["cid": container,
                    "qry": ["sid": subscription, "rid": "th.release.catalog-v1", "dbs": 1, "fo": 1]],
             "aps": ["content-available": 1]]
        }
        XCTAssertTrue(ShopCatalogReleaseNotifications.accepts(payload(
            subscription: ShopCatalogReleaseNotifications.subscriptionID,
            container: ShopCatalogReleaseNotifications.containerID)))
        XCTAssertFalse(ShopCatalogReleaseNotifications.accepts(payload(
            subscription: "another-subscription", container: ShopCatalogReleaseNotifications.containerID)))
        XCTAssertFalse(ShopCatalogReleaseNotifications.accepts(payload(
            subscription: ShopCatalogReleaseNotifications.subscriptionID, container: "iCloud.other")))
    }

    func testFrequentHeaderChecksExcludeAssets() {
        XCTAssertTrue(ShopCatalogPublicCloudReader.releaseHeaderKeys.contains("releaseSeq"))
        XCTAssertTrue(ShopCatalogPublicCloudReader.releaseHeaderKeys.contains("rootIndexHash"))
        XCTAssertFalse(ShopCatalogPublicCloudReader.releaseHeaderKeys.contains("rootIndexAsset"))
    }

    func testAutomaticChecksRespectServerRetryAfter() async {
        let gate = ShopCatalogCloudReadRetryGate()
        let start = Date(timeIntervalSince1970: 1000)
        await gate.recordRetry(after: 120, at: start)
        await gate.recordRetry(after: 10, at: start.addingTimeInterval(30))
        let remaining = await gate.remainingDelay(at: start.addingTimeInterval(30))
        let expired = await gate.remainingDelay(at: start.addingTimeInterval(121))
        XCTAssertEqual(remaining, 90, "后续错误不能缩短已知的服务端退避")
        XCTAssertEqual(expired, 0)
    }
}
