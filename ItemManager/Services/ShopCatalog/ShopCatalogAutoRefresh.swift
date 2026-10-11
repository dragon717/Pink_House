import CloudKit
import Foundation

/// 发布头提交才代表发布成功。只订阅 THRelease，素材或草稿写入不会触发更新。
enum ShopCatalogReleaseNotifications {
    static let containerID = "iCloud.bugod2.ItemManager"
    static let subscriptionID = "shop-catalog-release-v1"

    static func makeSubscription() -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: "THRelease", predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        return subscription
    }

    static func accepts(_ payload: [AnyHashable: Any]) -> Bool {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: payload),
              notification.notificationType == .query,
              notification.subscriptionID == subscriptionID else { return false }
        // APNs 裁剪大载荷时可能去掉 containerIdentifier；专用 subscriptionID 仍可识别。
        return notification.containerIdentifier == nil || notification.containerIdentifier == containerID
    }

    static func install() async throws {
        let database = CKContainer(identifier: containerID).publicCloudDatabase
        do {
            _ = try await database.subscription(for: subscriptionID)
        } catch let error as CKError where error.code == .unknownItem {
            _ = try await database.save(makeSubscription())
        }
    }
}

/// 全 App 前台运行，不依赖用户进入商品页。静默推送可能被系统延迟，
/// 因而前台每 5 分钟查一次发布头；回到前台先检查，再等待下一轮。
@MainActor
final class ShopCatalogAutoRefresh {
    static let shared = ShopCatalogAutoRefresh()
    static let foregroundInterval: Duration = .seconds(5 * 60)
    // 单测通过注入的实例驱动调度，不让宿主启动时访问真实云端或写测试缓存。
    static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }

    private let refresh: @MainActor () async -> Void
    private let installSubscription: @MainActor () async throws -> Void
    private let sleep: @MainActor () async throws -> Void
    private let now: () -> Date
    private var subscriptionTask: Task<Void, Never>?
    private var subscriptionInstalled = false
    private var nextSubscriptionAttempt = Date.distantPast

    init(
        refresh: @escaping @MainActor () async -> Void = {
            await ShopCatalogCloudSyncService.shared.syncIfNeeded()
        },
        installSubscription: @escaping @MainActor () async throws -> Void = {
            try await ShopCatalogReleaseNotifications.install()
        },
        sleep: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: foregroundInterval)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.refresh = refresh
        self.installSubscription = installSubscription
        self.sleep = sleep
        self.now = now
    }

    func runWhileActive() async {
        while !Task.isCancelled {
            requestSubscriptionIfNeeded()
            await refresh()
            do { try await sleep() } catch { return }
        }
    }

    /// iCloud 账户切换后订阅属于新账户，需要重新确认。公共库读取继续照常工作。
    func accountDidChange() {
        subscriptionInstalled = false
        nextSubscriptionAttempt = .distantPast
        subscriptionTask?.cancel()
        subscriptionTask = nil
        requestSubscriptionIfNeeded()
    }

    private func requestSubscriptionIfNeeded() {
        guard !subscriptionInstalled, subscriptionTask == nil,
              now() >= nextSubscriptionAttempt else { return }
        nextSubscriptionAttempt = now().addingTimeInterval(5 * 60)
        subscriptionTask = Task { [self] in
            do {
                try await installSubscription()
                if !Task.isCancelled { subscriptionInstalled = true }
            } catch {
                // 未登录 iCloud 也必须能读公共商品库；订阅失败不阻断前台自动刷新。
                print("[ShopCatalogAutoRefresh] 发布通知订阅暂不可用：\(error.localizedDescription)")
            }
            if !Task.isCancelled { subscriptionTask = nil }
        }
    }
}
