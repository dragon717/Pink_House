//
//  NotificationManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import UserNotifications
import SwiftUI
import SwiftData
import os

struct NotificationDebugSnapshot {
    let authorizationStatus: UNAuthorizationStatus
    let pendingCount: Int
    let deliveredCount: Int
    let depositPendingCount: Int
    let depositDeliveredCount: Int
    let applicationBadgeCount: Int
    let pendingRecordCount: Int
    let capturedRecordCount: Int
    let scheduledSystemLimit: Int
    let isMemoryConstrained: Bool
}

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    enum Config {
        static let maximumScheduledSystemNotifications = 20
        static let pendingSectionLimitNormal = 60
        static let pendingSectionLimitLowMemory = 30
        static let historyLimit = 50
        static let lowMemoryThresholdBytes: UInt64 = 3_500_000_000
        static let refreshCooldownNormal: TimeInterval = 15
        static let refreshCooldownLowMemory: TimeInterval = 30
        static let supportedReminderDays = [0, 1, 3, 7, 15, 30]
        static let legacyReminderDays = [2]

        static var isLowMemoryDevice: Bool {
            ProcessInfo.processInfo.physicalMemory <= lowMemoryThresholdBytes
        }

        static var refreshCooldown: TimeInterval {
            isLowMemoryDevice ? refreshCooldownLowMemory : refreshCooldownNormal
        }

        static var pendingSectionLimit: Int {
            isLowMemoryDevice ? pendingSectionLimitLowMemory : pendingSectionLimitNormal
        }
    }

    private struct PayloadKeys {
        static let clothingID = "depositNotificationClothingID"
        static let daysBefore = "depositNotificationDaysBefore"
        static let clothingName = "depositNotificationClothingName"
        static let kind = "depositNotificationKind"
    }

    private enum RecordSource {
        static let apple = "apple"
        static let scheduled = "scheduled"
        static let captured = "captured"
        static let legacyLocal = "local"
    }

    private struct NotificationCandidate {
        let clothing: Clothing
        let finalPaymentStart: Date
        let triggerDate: Date
        let daysBefore: Int
        let shouldCatchUpNow: Bool

        var scheduledDate: Date {
            triggerDate
        }

        var identifier: String {
            shouldCatchUpNow
                ? "\(clothing.id.uuidString)_\(daysBefore)_catchup"
                : "\(clothing.id.uuidString)_\(daysBefore)"
        }
    }

    private struct PendingRequestSyncStats {
        var removed = 0
        var added = 0
        var updated = 0
        var kept = 0
    }

    private struct PendingRecordSyncStats {
        var removed = 0
        var inserted = 0
        var updated = 0
        var kept = 0
    }

    private var lastRefreshSignature: String?
    private var lastRefreshAt: Date?
    private let logger = AppLogger.category("Notifications")
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        logger.info("initialized delegate_assigned=true low_memory=\(Config.isLowMemoryDevice)")
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            await reconcileNotificationRequest(notification.request)
        }
        // 在前台也显示通知 (Banner, Sound, Badge)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let request = response.notification.request
            await reconcileNotificationRequest(request)

            if let clothingID = extractClothingID(from: request) {
                TabNavigationManager.shared.navigateToDepositNotificationClothing(clothingID)
            }

            completionHandler()
        }
    }
    
    // MARK: - Settings Keys
    struct Keys {
        static let isDepositNotificationEnabled = "isDepositNotificationEnabled"
        static let depositNotificationDaysBefore = "depositNotificationDaysBefore" // Deprecated, kept for migration
        static let depositNotificationDaysList = "depositNotificationDaysList"
        static let depositNotificationTime = "depositNotificationTime"
        static let depositNotificationDaysSchemaVersion = "depositNotificationDaysSchemaVersion"
    }

    private let reminderDaysSchemaVersion = 2
    
    // MARK: - Properties
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isDepositNotificationEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isDepositNotificationEnabled) }
    }
    
    // Support multiple reminder days
    var daysBeforeList: [Int] {
        get {
            if UserDefaults.standard.integer(forKey: Keys.depositNotificationDaysSchemaVersion) < reminderDaysSchemaVersion {
                let migrated = migrateReminderDaysIfNeeded()
                UserDefaults.standard.set(reminderDaysSchemaVersion, forKey: Keys.depositNotificationDaysSchemaVersion)
                return migrated
            }

            if let list = UserDefaults.standard.array(forKey: Keys.depositNotificationDaysList) as? [Int] {
                let normalized = normalizedReminderDays(from: list)
                if normalized != list.sorted() {
                    UserDefaults.standard.set(normalized, forKey: Keys.depositNotificationDaysList)
                }
                return normalized.isEmpty ? Config.supportedReminderDays : normalized
            }
            // Migration: if old key exists, use it
            if UserDefaults.standard.object(forKey: Keys.depositNotificationDaysBefore) != nil {
                let oldDay = UserDefaults.standard.integer(forKey: Keys.depositNotificationDaysBefore)
                let normalized = normalizedReminderDays(from: [oldDay])
                UserDefaults.standard.set(normalized, forKey: Keys.depositNotificationDaysList)
                return normalized.isEmpty ? Config.supportedReminderDays : normalized
            }
            return Config.supportedReminderDays
        }
        set {
            let normalized = normalizedReminderDays(from: newValue)
            UserDefaults.standard.set(
                normalized.isEmpty ? Config.supportedReminderDays : normalized,
                forKey: Keys.depositNotificationDaysList
            )
            UserDefaults.standard.set(reminderDaysSchemaVersion, forKey: Keys.depositNotificationDaysSchemaVersion)
        }
    }
    
    // Compatibility property
    var daysBefore: Int {
        get { daysBeforeList.first ?? 0 }
        set { daysBeforeList = [newValue] }
    }
    
    var notificationTime: Date {
        get {
            if let date = UserDefaults.standard.object(forKey: Keys.depositNotificationTime) as? Date {
                return date
            }
            // Default to 9:00 AM
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.depositNotificationTime) }
    }
    
    // MARK: - Authorization
    func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        let settings = await center.notificationSettings()
        logger.info("request_authorization granted=\(granted) auth=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) badge=\(settings.badgeSetting.rawValue) sound=\(settings.soundSetting.rawValue)")
        return granted
    }
    
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        logger.info("authorization_status auth=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) badge=\(settings.badgeSetting.rawValue) sound=\(settings.soundSetting.rawValue)")
        return settings.authorizationStatus
    }
    
    // MARK: - Scheduling with Record Creation
    @MainActor
    func scheduleNotification(for clothing: Clothing, modelContext: ModelContext? = nil) {
        let context = modelContext ?? SharedPersistence.shared.sharedModelContainer.mainContext
        Task { @MainActor in
            await refreshAllKnownDepositNotifications(
                modelContext: context,
                force: false,
                reason: "single-update"
            )
        }
    }
    
    @MainActor
    func cancelNotification(for clothing: Clothing) {
        let center = UNUserNotificationCenter.current()
        
        // Remove legacy ID (exact match)
        center.removePendingNotificationRequests(withIdentifiers: [clothing.id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [clothing.id.uuidString])
        
        // Remove all potential variants
        let potentialDays = Config.supportedReminderDays + Config.legacyReminderDays
        let idsToRemove = potentialDays.map { "\(clothing.id.uuidString)_\($0)" }
        
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        center.removeDeliveredNotifications(withIdentifiers: idsToRemove)

        let prefix = clothing.id.uuidString
        center.getPendingNotificationRequests { requests in
            let dynamicIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !dynamicIDs.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: dynamicIDs)
        }

        center.getDeliveredNotifications { notifications in
            let dynamicIDs = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !dynamicIDs.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: dynamicIDs)
        }
    }
    
    @MainActor
    func rescheduleAllNotifications(clothings: [Clothing], modelContext: ModelContext? = nil) async {
        await refreshDepositNotifications(clothings: clothings, modelContext: modelContext)
    }

    @MainActor
    func refreshDepositNotifications(
        clothings: [Clothing],
        modelContext: ModelContext? = nil,
        force: Bool = false,
        reason: String = "default"
    ) async {
        let startedAt = Date()
        let signature = makeRefreshSignature(for: clothings)
        if !force,
           lastRefreshSignature == signature,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < Config.refreshCooldown {
            return
        }

        logger.info("refresh_start reason=\(reason, privacy: .public) clothing_count=\(clothings.count) enabled=\(self.isEnabled) force=\(force) low_memory=\(Config.isLowMemoryDevice)")
        let existingPendingRequests = await pendingDepositRequestsByIdentifier()

        guard isEnabled else {
            let requestStats = removePendingRequests(withIdentifiers: Array(existingPendingRequests.keys))
            var recordStats = PendingRecordSyncStats()
            if let context = modelContext {
                recordStats = syncPendingRecords(desiredCandidates: [], scheduledKeys: [], modelContext: context)
                try? context.save()
            }
            lastRefreshSignature = signature
            lastRefreshAt = Date()
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logger.info("refresh_finish reason=\(reason, privacy: .public) duration_ms=\(durationMs) disabled=true request_removed=\(requestStats.removed) record_removed=\(recordStats.removed)")
            return
        }

        let status = await checkAuthorizationStatus()
        guard hasSchedulingPermission(status) else {
            let requestStats = removePendingRequests(withIdentifiers: Array(existingPendingRequests.keys))
            var recordStats = PendingRecordSyncStats()
            if let context = modelContext {
                recordStats = syncPendingRecords(desiredCandidates: [], scheduledKeys: [], modelContext: context)
                try? context.save()
            }
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            logger.info("refresh_finish reason=\(reason, privacy: .public) duration_ms=\(durationMs) permission_blocked=true status=\(status.rawValue) request_removed=\(requestStats.removed) record_removed=\(recordStats.removed)")
            return
        }

        let candidates = buildCandidates(for: clothings, modelContext: modelContext)
        let scheduledCandidates = Array(candidates.prefix(Config.maximumScheduledSystemNotifications))
        let scheduledKeys = Set(scheduledCandidates.map(candidateKey(for:)))
        let capturedCount = max(0, candidates.count - scheduledCandidates.count)
        let requestStats = syncPendingRequests(
            desiredCandidates: scheduledCandidates,
            existingRequests: existingPendingRequests
        )

        var recordStats = PendingRecordSyncStats()
        if let context = modelContext {
            recordStats = syncPendingRecords(
                desiredCandidates: candidates,
                scheduledKeys: scheduledKeys,
                modelContext: context
            )
            try? context.save()
        }

        lastRefreshSignature = signature
        lastRefreshAt = Date()
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        logger.info(
            "refresh_finish reason=\(reason, privacy: .public) duration_ms=\(durationMs) candidates=\(candidates.count) scheduled=\(scheduledCandidates.count) captured=\(capturedCount) request_removed=\(requestStats.removed) request_added=\(requestStats.added) request_updated=\(requestStats.updated) request_kept=\(requestStats.kept) record_removed=\(recordStats.removed) record_inserted=\(recordStats.inserted) record_updated=\(recordStats.updated) record_kept=\(recordStats.kept)"
        )
    }

    @MainActor
    func refreshAllKnownDepositNotifications(
        modelContext: ModelContext,
        force: Bool = false,
        reason: String = "all-known"
    ) async {
        let descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate<Clothing> { clothing in
                clothing.isDepositPlan == true && clothing.deletedAt == nil
            }
        )
        let clothings = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.isFinalPaymentPlan }
        await refreshDepositNotifications(
            clothings: clothings,
            modelContext: modelContext,
            force: force,
            reason: reason
        )
    }
    
    // MARK: - Record Management
    
    /// 获取所有提醒记录
    @MainActor
    func getAllRecords(modelContext: ModelContext) -> [DepositNotificationRecord] {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            sortBy: [SortDescriptor(\.scheduledDate, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// 获取即将到期的提醒
    @MainActor
    func getUpcomingRecords(modelContext: ModelContext, days: Int = 7) -> [DepositNotificationRecord] {
        let calendar = Calendar.current
        let now = Date()
        guard let futureDate = calendar.date(byAdding: .day, value: days, to: now) else { return [] }

        let targetNow = now
        let targetFuture = futureDate
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.scheduledDate >= targetNow && record.scheduledDate <= targetFuture && !record.isTriggered
            },
            sortBy: [SortDescriptor(\.scheduledDate, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// 获取历史提醒（已触发）
    @MainActor
    func getTriggeredRecords(modelContext: ModelContext, limit: Int = 50) -> [DepositNotificationRecord] {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate { $0.isTriggered == true },
            sortBy: [SortDescriptor(\.scheduledDate, order: .reverse)]
        )
        var records = (try? modelContext.fetch(descriptor)) ?? []
        if records.count > limit {
            records = Array(records.prefix(limit))
        }
        return records
    }
    
    /// 清理过期记录（保留最近90天的记录）
    @MainActor
    func cleanupOldRecords(modelContext: ModelContext, daysToKeep: Int = 90) {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()

        let targetCutoff = cutoffDate
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.scheduledDate < targetCutoff && record.isTriggered
            }
        )

        if let oldRecords = try? modelContext.fetch(descriptor) {
            for record in oldRecords {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }
    }
    
    /// 根据设置生成所有提醒记录（用于历史补款多次显示）
    @MainActor
    func generateRecordsForDepositPlan(clothing: Clothing, modelContext: ModelContext) {
        guard clothing.isFinalPaymentPlan, let finalDate = clothing.finalPaymentDate else { return }

        let calendar = Calendar.current
        let finalDateStart = calendar.startOfDay(for: finalDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        let clothingID = clothing.id

        // 获取现有记录进行对比
        let allRecords = getAllRecords(modelContext: modelContext)
        let existingKeys = Set(allRecords.map { "\($0.clothingID.uuidString)_\($0.daysBefore)" })

        for days in daysBeforeList {
            guard let targetDate = calendar.date(byAdding: .day, value: -days, to: finalDateStart) else { continue }

            var triggerComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            triggerComponents.hour = timeComponents.hour
            triggerComponents.minute = timeComponents.minute

            guard let triggerDate = calendar.date(from: triggerComponents) else { continue }

            // 检查是否已存在相同记录
            let recordKey = "\(clothingID.uuidString)_\(days)"
            if existingKeys.contains(recordKey) {
                continue // 已存在，跳过
            }

            let record = DepositNotificationRecord(
                clothingID: clothingID,
                clothingName: clothing.name,
                scheduledDate: triggerDate,
                daysBefore: days
            )
            modelContext.insert(record)
        }

        try? modelContext.save()
    }
    
    // MARK: - 未读通知管理
    
    /// 获取未读的通知记录数量（用于小红点显示）
    @MainActor
    func getUnreadTriggeredCount(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate { $0.isTriggered == true && $0.isRead == false }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }
    
    /// 获取未读的通知记录列表
    @MainActor
    func getUnreadTriggeredRecords(modelContext: ModelContext) -> [DepositNotificationRecord] {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate { $0.isTriggered == true && $0.isRead == false },
            sortBy: [SortDescriptor(\.actualDate, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// 一键标记所有已触发通知为已读
    @MainActor
    func markAllTriggeredAsRead(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate { $0.isTriggered == true && $0.isRead == false }
        )
        
        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                record.markAsRead()
            }
            try? modelContext.save()
            updateApplicationBadge(modelContext: modelContext)
        }
    }
    
    /// 一键清除所有已读通知
    @MainActor
    func clearAllReadNotifications(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate { $0.isTriggered == true && $0.isRead == true }
        )
        
        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
            try? modelContext.save()
            updateApplicationBadge(modelContext: modelContext)
        }
    }

    @MainActor
    func deleteRecord(_ record: DepositNotificationRecord, modelContext: ModelContext) {
        removeNotificationsForRecord(record)
        modelContext.delete(record)
        try? modelContext.save()
        updateApplicationBadge(modelContext: modelContext)
    }

    /// 用户确认已付尾款后：已触发的提醒标记为已读，未触发的待提醒直接清理。
    @MainActor
    func handlePaymentConfirmed(for clothingID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.clothingID == clothingID
            }
        )

        guard let records = try? modelContext.fetch(descriptor) else { return }

        for record in records {
            if record.isTriggered {
                if !record.isRead {
                    record.markAsRead()
                }
            } else {
                modelContext.delete(record)
            }
        }
        try? modelContext.save()
        updateApplicationBadge(modelContext: modelContext)
    }
    
    /// 限制历史记录数量（保留最新的50条）
    @MainActor
    func enforceHistoryLimit(modelContext: ModelContext, limit: Int = 50) {
        // 获取所有已触发的记录，按时间倒序
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate { $0.isTriggered == true },
            sortBy: [SortDescriptor(\.actualDate, order: .reverse)]
        )
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { return }
        
        // 如果超过限制，删除多余的旧记录
        if allRecords.count > limit {
            let recordsToDelete = allRecords.suffix(from: limit)
            for record in recordsToDelete {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }
    }
    
    /// 添加历史记录（模拟Apple通知，用于测试或手动添加）
    @MainActor
    func addNotificationHistory(clothing: Clothing, daysBefore: Int, triggerDate: Date, modelContext: ModelContext) {
        let record = DepositNotificationRecord(
            clothingID: clothing.id,
            clothingName: clothing.name,
            scheduledDate: triggerDate,
            daysBefore: daysBefore,
            source: "apple"
        )
        record.markAsTriggered(source: "apple")
        modelContext.insert(record)
        
        // 添加后检查并限制数量
        enforceHistoryLimit(modelContext: modelContext)
        
        try? modelContext.save()
        updateApplicationBadge(modelContext: modelContext)
    }

    @MainActor
    func scheduleTestNotification(for clothing: Clothing, secondsFromNow: TimeInterval = 5) async throws {
        logger.info("schedule_test_notification clothing_name=\(clothing.name, privacy: .public) seconds=\(secondsFromNow)")
        let content = makeReminderContent(
            clothing: clothing,
            daysBefore: 0,
            finalDate: clothing.finalPaymentDate ?? Date(),
            title: "测试尾款提醒",
            isTest: true
        )
        content.body = "5 秒测试：点击后会直达「\(clothing.name)」详情页。"

        let identifier = "\(clothing.id.uuidString)_test_\(Int(Date().timeIntervalSince1970))"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, secondsFromNow), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
        logger.info("test_request_added identifier=\(identifier, privacy: .public)")
    }

    @MainActor
    func reconcileDeliveredNotifications(modelContext: ModelContext? = nil) async {
        let notifications = await deliveredNotifications()
        guard !notifications.isEmpty else { return }

        for notification in notifications {
            await reconcileNotificationRequest(notification.request, modelContext: modelContext)
        }

        logger.info("reconcile_delivered_batch count=\(notifications.count)")
    }

    @MainActor
    func updateApplicationBadge(modelContext: ModelContext? = nil) {
        let context = modelContext ?? SharedPersistence.shared.sharedModelContainer.mainContext
        let unreadCount = getUnreadTriggeredCount(modelContext: context)
        UIApplication.shared.applicationIconBadgeNumber = unreadCount
        logger.info("badge_updated unread=\(unreadCount)")
    }

    func debugSnapshot() async -> NotificationDebugSnapshot {
        let authorizationStatus = await checkAuthorizationStatus()
        let pending = await pendingRequests()
        let delivered = await deliveredNotifications()
        let depositPending = pending.filter { isDepositNotification($0) }
        let depositDelivered = delivered.filter { isDepositNotification($0.request) }
        let badgeCount = await MainActor.run { UIApplication.shared.applicationIconBadgeNumber }
        let pendingRecordStats = await MainActor.run { () -> (total: Int, captured: Int) in
            self.pendingRecordStats()
        }
        return NotificationDebugSnapshot(
            authorizationStatus: authorizationStatus,
            pendingCount: pending.count,
            deliveredCount: delivered.count,
            depositPendingCount: depositPending.count,
            depositDeliveredCount: depositDelivered.count,
            applicationBadgeCount: badgeCount,
            pendingRecordCount: pendingRecordStats.total,
            capturedRecordCount: pendingRecordStats.captured,
            scheduledSystemLimit: Config.maximumScheduledSystemNotifications,
            isMemoryConstrained: Config.isLowMemoryDevice
        )
    }

    private func makeReminderContent(
        clothing: Clothing,
        daysBefore: Int,
        finalDate: Date,
        title: String,
        isTest: Bool,
        isCatchUpDuringPaymentWindow: Bool = false
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title

        let paymentWindowText = reminderPaymentWindowText(
            finalDate: finalDate,
            finalPaymentEndDate: clothing.finalPaymentEndDate
        )
        let amountText = reminderAmountText(for: clothing)
        let body: String
        if isTest {
            body = "测试通知：点击后会打开「\(clothing.name)」详情页。\(paymentWindowText)。"
        } else if isCatchUpDuringPaymentWindow {
            body = "「\(clothing.name)」已进入尾款支付期：\(paymentWindowText)。\(amountText)，若尚未处理请尽快确认。"
        } else if daysBefore > 0 {
            body = "「\(clothing.name)」还有 \(daysBefore) 天开始付尾款：\(paymentWindowText)。\(amountText)，点击查看详情。"
        } else {
            body = "「\(clothing.name)」今天开始付尾款：\(paymentWindowText)。\(amountText)，请确认是否已处理。"
        }

        content.body = body
        content.sound = .default
        content.threadIdentifier = "deposit-plan-reminders"
        content.userInfo = [
            PayloadKeys.clothingID: clothing.id.uuidString,
            PayloadKeys.daysBefore: daysBefore,
            PayloadKeys.clothingName: clothing.name,
            PayloadKeys.kind: "depositPlan"
        ]
        return content
    }

    @MainActor
    private func reconcileNotificationRequest(_ request: UNNotificationRequest, modelContext: ModelContext? = nil) async {
        guard isDepositNotification(request) else { return }
        guard let clothingID = extractClothingID(from: request) else { return }

        let context = modelContext ?? SharedPersistence.shared.sharedModelContainer.mainContext
        let daysBefore = extractDaysBefore(from: request)
        let clothingName = extractClothingName(from: request) ?? request.content.title

        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.clothingID == clothingID && record.daysBefore == daysBefore
            },
            sortBy: [SortDescriptor(\.scheduledDate, order: .reverse)]
        )

        let records = (try? context.fetch(descriptor)) ?? []

        if let pendingRecord = records.first(where: { !$0.isTriggered }) {
            pendingRecord.clothingName = clothingName
            pendingRecord.markAsTriggered(source: RecordSource.apple)
        } else if let triggeredRecord = records.first(where: { $0.isTriggered }) {
            let shouldReuseTriggeredRecord: Bool
            if let actualDate = triggeredRecord.actualDate {
                shouldReuseTriggeredRecord = abs(actualDate.timeIntervalSinceNow) < 300
            } else {
                shouldReuseTriggeredRecord = false
            }

            if shouldReuseTriggeredRecord {
                if triggeredRecord.clothingName.isEmpty {
                    triggeredRecord.clothingName = clothingName
                }
            } else {
                let record = DepositNotificationRecord(
                    clothingID: clothingID,
                    clothingName: clothingName,
                    scheduledDate: Date(),
                    daysBefore: daysBefore,
                    source: RecordSource.apple
                )
                record.markAsTriggered(source: RecordSource.apple)
                context.insert(record)
            }
        } else {
            let record = DepositNotificationRecord(
                clothingID: clothingID,
                clothingName: clothingName,
                scheduledDate: Date(),
                daysBefore: daysBefore,
                source: RecordSource.apple
            )
            record.markAsTriggered(source: RecordSource.apple)
            context.insert(record)
        }

        enforceHistoryLimit(modelContext: context)
        try? context.save()
        updateApplicationBadge(modelContext: context)
        logger.info("reconciled_delivered_notification clothing_id=\(clothingID.uuidString, privacy: .public) days_before=\(daysBefore)")
    }

    private func extractClothingID(from request: UNNotificationRequest) -> UUID? {
        if let uuidString = request.content.userInfo[PayloadKeys.clothingID] as? String,
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }

        let firstComponent = request.identifier.components(separatedBy: "_").first ?? ""
        return UUID(uuidString: firstComponent)
    }

    private func extractDaysBefore(from request: UNNotificationRequest) -> Int {
        if let days = request.content.userInfo[PayloadKeys.daysBefore] as? Int {
            return days
        }

        let components = request.identifier.components(separatedBy: "_")
        if components.count > 1, let days = Int(components[1]) {
            return days
        }

        return 0
    }

    private func extractClothingName(from request: UNNotificationRequest) -> String? {
        request.content.userInfo[PayloadKeys.clothingName] as? String
    }

    private func isTestDepositNotification(_ request: UNNotificationRequest) -> Bool {
        let components = request.identifier.components(separatedBy: "_")
        return components.count > 1 && components[1] == "test"
    }

    private func isDepositNotification(_ request: UNNotificationRequest) -> Bool {
        if let kind = request.content.userInfo[PayloadKeys.kind] as? String {
            return kind == "depositPlan"
        }

        let components = request.identifier.components(separatedBy: "_")
        guard let first = components.first, UUID(uuidString: first) != nil else {
            return false
        }

        guard components.count > 1 else { return false }
        return Int(components[1]) != nil || components[1] == "test"
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func pendingDepositRequestsByIdentifier() async -> [String: UNNotificationRequest] {
        Dictionary(
            uniqueKeysWithValues: await pendingRequests()
                .filter { isDepositNotification($0) && !isTestDepositNotification($0) }
                .map { ($0.identifier, $0) }
        )
    }

    private func removePendingRequests(withIdentifiers identifiers: [String]) -> PendingRequestSyncStats {
        guard !identifiers.isEmpty else { return PendingRequestSyncStats() }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        var stats = PendingRequestSyncStats()
        stats.removed = identifiers.count
        return stats
    }

    private func removeNotificationsForRecord(_ record: DepositNotificationRecord) {
        let center = UNUserNotificationCenter.current()
        let baseIdentifier = "\(record.clothingID.uuidString)_\(record.daysBefore)"
        let identifiers = [baseIdentifier, "\(baseIdentifier)_catchup"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func hasSchedulingPermission(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func scheduleSystemNotification(for candidate: NotificationCandidate) {
        let content = makeReminderContent(
            clothing: candidate.clothing,
            daysBefore: candidate.daysBefore,
            finalDate: candidate.finalPaymentStart,
            title: "尾款支付提醒",
            isTest: false,
            isCatchUpDuringPaymentWindow: candidate.shouldCatchUpNow
        )

        let triggerComponents = desiredCalendarTriggerDateComponents(for: candidate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let request = UNNotificationRequest(identifier: candidate.identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("schedule_failed clothing_name=\(candidate.clothing.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func syncPendingRequests(
        desiredCandidates: [NotificationCandidate],
        existingRequests: [String: UNNotificationRequest]
    ) -> PendingRequestSyncStats {
        var stats = PendingRequestSyncStats()
        let desiredIdentifiers = Set(desiredCandidates.map(\.identifier))
        let staleIdentifiers = Array(Set(existingRequests.keys).subtracting(desiredIdentifiers))
        if !staleIdentifiers.isEmpty {
            stats.removed += removePendingRequests(withIdentifiers: staleIdentifiers).removed
        }

        for candidate in desiredCandidates {
            if let existingRequest = existingRequests[candidate.identifier] {
                if requestMatches(existingRequest, candidate: candidate) {
                    stats.kept += 1
                    continue
                }

                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [candidate.identifier])
                stats.updated += 1
            } else {
                stats.added += 1
            }

            scheduleSystemNotification(for: candidate)
        }

        return stats
    }

    @MainActor
    private func buildCandidates(for clothings: [Clothing], modelContext: ModelContext?) -> [NotificationCandidate] {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        let now = Date()
        let triggeredTodayClothingIDs = triggeredTodayDayZeroClothingIDs(modelContext: modelContext)

        return clothings
            .compactMap { clothing -> [(NotificationCandidate)]? in
                guard clothing.isFinalPaymentPlan, let finalPaymentStart = clothing.finalPaymentDate else {
                    return nil
                }

                let paymentWindowStart = calendar.startOfDay(for: finalPaymentStart)
                let paymentWindowEndBase = clothing.finalPaymentEndDate ?? finalPaymentStart
                let paymentWindowEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: paymentWindowEndBase) ?? paymentWindowEndBase
                let isWithinPaymentWindow = now >= paymentWindowStart && now <= paymentWindowEnd

                if isWithinPaymentWindow {
                    guard let nextReminderDate = nextReminderDateWithinPaymentWindow(
                        now: now,
                        paymentWindowEnd: paymentWindowEnd,
                        timeComponents: timeComponents,
                        alreadyTriggeredToday: triggeredTodayClothingIDs.contains(clothing.id)
                    ) else {
                        return nil
                    }
                    return [
                        NotificationCandidate(
                            clothing: clothing,
                            finalPaymentStart: finalPaymentStart,
                            triggerDate: nextReminderDate,
                            daysBefore: 0,
                            shouldCatchUpNow: true
                        )
                    ]
                }

                return daysBeforeList.compactMap { days in
                    guard let targetDate = calendar.date(byAdding: .day, value: -days, to: paymentWindowStart) else {
                        return nil
                    }

                    var triggerComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
                    triggerComponents.hour = timeComponents.hour
                    triggerComponents.minute = timeComponents.minute

                    guard let triggerDate = calendar.date(from: triggerComponents) else {
                        return nil
                    }

                    guard triggerDate >= now else {
                        return nil
                    }

                    return NotificationCandidate(
                        clothing: clothing,
                        finalPaymentStart: finalPaymentStart,
                        triggerDate: triggerDate,
                        daysBefore: days,
                        shouldCatchUpNow: false
                    )
                }
            }
            .flatMap { $0 }
            .sorted { lhs, rhs in
                if lhs.scheduledDate == rhs.scheduledDate {
                    return lhs.clothing.createdAt < rhs.clothing.createdAt
                }
                return lhs.scheduledDate < rhs.scheduledDate
            }
    }

    @MainActor
    private func triggeredTodayDayZeroClothingIDs(modelContext: ModelContext?) -> Set<UUID> {
        guard let modelContext else { return [] }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }

        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.isTriggered == true && record.daysBefore == 0
            },
            sortBy: [SortDescriptor(\.actualDate, order: .reverse)]
        )

        let records = (try? modelContext.fetch(descriptor)) ?? []
        var clothingIDs = Set<UUID>()
        for record in records {
            guard let actualDate = record.actualDate else { continue }
            if actualDate >= startOfToday && actualDate < startOfTomorrow {
                clothingIDs.insert(record.clothingID)
            }
        }
        return clothingIDs
    }

    private func nextReminderDateWithinPaymentWindow(
        now: Date,
        paymentWindowEnd: Date,
        timeComponents: DateComponents,
        alreadyTriggeredToday: Bool
    ) -> Date? {
        let calendar = Calendar.current

        func reminderDate(for day: Date) -> Date? {
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            return calendar.date(from: components)
        }

        let todayReminder = reminderDate(for: now)
        if !alreadyTriggeredToday,
           let todayReminder,
           todayReminder >= now,
           todayReminder <= paymentWindowEnd {
            return todayReminder
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextReminder = reminderDate(for: tomorrow),
              nextReminder <= paymentWindowEnd else {
            return nil
        }

        return nextReminder
    }

    @MainActor
    private func syncPendingRecords(
        desiredCandidates: [NotificationCandidate],
        scheduledKeys: Set<String>,
        modelContext: ModelContext
    ) -> PendingRecordSyncStats {
        var stats = PendingRecordSyncStats()
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.isTriggered == false
            }
        )

        guard let records = try? modelContext.fetch(descriptor) else { return stats }

        var existingByKey: [String: DepositNotificationRecord] = [:]
        for record in records {
            let key = "\(record.clothingID.uuidString)_\(record.daysBefore)"
            if let existing = existingByKey[key] {
                if existing.createdAt <= record.createdAt {
                    modelContext.delete(record)
                } else {
                    modelContext.delete(existing)
                    existingByKey[key] = record
                }
                stats.removed += 1
            } else {
                existingByKey[key] = record
            }
        }

        let desiredKeys = Set(desiredCandidates.map(candidateKey(for:)))
        let staleKeys = existingByKey.keys.filter { !desiredKeys.contains($0) }
        for key in staleKeys {
            guard let record = existingByKey.removeValue(forKey: key) else { continue }
            modelContext.delete(record)
            stats.removed += 1
        }

        for candidate in desiredCandidates {
            let key = candidateKey(for: candidate)
            let source = scheduledKeys.contains(key) ? RecordSource.scheduled : RecordSource.captured
            if let existing = existingByKey[key] {
                let desiredScheduledDate = candidate.scheduledDate
                let needsDateUpdate =
                    abs(existing.scheduledDate.timeIntervalSince(desiredScheduledDate)) >= 1
                let needsUpdate =
                    existing.clothingName != candidate.clothing.name ||
                    existing.source != source ||
                    needsDateUpdate

                if needsUpdate {
                    existing.clothingName = candidate.clothing.name
                    existing.scheduledDate = desiredScheduledDate
                    existing.source = source
                    existing.lastModified = Date()
                    stats.updated += 1
                } else {
                    stats.kept += 1
                }
                continue
            }

            let record = DepositNotificationRecord(
                clothingID: candidate.clothing.id,
                clothingName: candidate.clothing.name,
                scheduledDate: candidate.scheduledDate,
                daysBefore: candidate.daysBefore,
                source: source
            )
            modelContext.insert(record)
            stats.inserted += 1
        }

        return stats
    }

    private func candidateKey(for candidate: NotificationCandidate) -> String {
        "\(candidate.clothing.id.uuidString)_\(candidate.daysBefore)"
    }

    private func requestMatches(_ request: UNNotificationRequest, candidate: NotificationCandidate) -> Bool {
        guard isDepositNotification(request) else { return false }
        guard extractClothingName(from: request) == candidate.clothing.name else { return false }
        guard extractDaysBefore(from: request) == candidate.daysBefore else { return false }

        let expectedContent = makeReminderContent(
            clothing: candidate.clothing,
            daysBefore: candidate.daysBefore,
            finalDate: candidate.finalPaymentStart,
            title: "尾款支付提醒",
            isTest: false,
            isCatchUpDuringPaymentWindow: candidate.shouldCatchUpNow
        )
        guard request.content.title == expectedContent.title,
              request.content.body == expectedContent.body else {
            return false
        }

        guard let existingTrigger = request.trigger as? UNCalendarNotificationTrigger else {
            return false
        }

        let existingComponents = existingTrigger.dateComponents
        let desiredComponents = desiredCalendarTriggerDateComponents(for: candidate)
        return existingComponents.year == desiredComponents.year &&
            existingComponents.month == desiredComponents.month &&
            existingComponents.day == desiredComponents.day &&
            existingComponents.hour == desiredComponents.hour &&
            existingComponents.minute == desiredComponents.minute
    }

    private func desiredCalendarTriggerDateComponents(for candidate: NotificationCandidate) -> DateComponents {
        var triggerComponents = Calendar.current.dateComponents([.year, .month, .day], from: candidate.triggerDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        triggerComponents.hour = timeComponents.hour
        triggerComponents.minute = timeComponents.minute
        return triggerComponents
    }

    private func normalizedReminderDays(from values: [Int]) -> [Int] {
        let uniqueValues = Array(Set(values)).sorted()
        let filteredValues = uniqueValues.filter { Config.supportedReminderDays.contains($0) }
        let containsLegacyValues = uniqueValues.contains { !Config.supportedReminderDays.contains($0) }
        if filteredValues.isEmpty || containsLegacyValues {
            return Config.supportedReminderDays
        }
        return filteredValues
    }

    private func migrateReminderDaysIfNeeded() -> [Int] {
        let storedList = UserDefaults.standard.array(forKey: Keys.depositNotificationDaysList) as? [Int]
        let normalizedStoredList = storedList.map { normalizedReminderDays(from: $0) }

        if let normalizedStoredList {
            let isLegacyDefault =
                normalizedStoredList == [0] ||
                normalizedStoredList == [1, 2, 30] ||
                normalizedStoredList == [1, 30]
            let migrated = isLegacyDefault ? Config.supportedReminderDays : normalizedStoredList
            UserDefaults.standard.set(migrated, forKey: Keys.depositNotificationDaysList)
            return migrated
        }

        if UserDefaults.standard.object(forKey: Keys.depositNotificationDaysBefore) != nil {
            let oldDay = UserDefaults.standard.integer(forKey: Keys.depositNotificationDaysBefore)
            let migrated = normalizedReminderDays(from: [oldDay])
            UserDefaults.standard.set(migrated, forKey: Keys.depositNotificationDaysList)
            return migrated
        }

        UserDefaults.standard.set(Config.supportedReminderDays, forKey: Keys.depositNotificationDaysList)
        return Config.supportedReminderDays
    }

    @MainActor
    private func pendingRecordStats() -> (total: Int, captured: Int) {
        let context = SharedPersistence.shared.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<DepositNotificationRecord>(
            predicate: #Predicate<DepositNotificationRecord> { record in
                record.isTriggered == false
            }
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let captured = records.filter { $0.source == RecordSource.captured || $0.source == RecordSource.legacyLocal }.count
        return (records.count, captured)
    }

    private func makeRefreshSignature(for clothings: [Clothing]) -> String {
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        let clothingSignature = clothings
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { clothing in
                let updatedAt = clothing.updatedAt.timeIntervalSince1970
                let start = clothing.finalPaymentDate?.timeIntervalSince1970 ?? 0
                let end = clothing.finalPaymentEndDate?.timeIntervalSince1970 ?? 0
                return "\(clothing.id.uuidString)|\(updatedAt)|\(start)|\(end)|\(clothing.isFinalPaymentPlan)"
            }
            .joined(separator: ";")

        return [
            isEnabled ? "1" : "0",
            daysBeforeList.map(String.init).joined(separator: ","),
            "\(timeComponents.hour ?? 0):\(timeComponents.minute ?? 0)",
            clothingSignature
        ].joined(separator: "#")
    }
    
    private func reminderPaymentWindowText(finalDate: Date, finalPaymentEndDate: Date?) -> String {
        if let finalPaymentEndDate,
           Calendar.current.startOfDay(for: finalPaymentEndDate) > Calendar.current.startOfDay(for: finalDate) {
            return "支付期 \(formatDate(finalDate)) 至 \(formatDate(finalPaymentEndDate))"
        }

        return "尾款日 \(formatDate(finalDate))"
    }

    private func reminderAmountText(for clothing: Clothing) -> String {
        guard clothing.totalBalance > 0 else {
            return "尾款金额待确认"
        }

        return "待付尾款 ¥\(NSDecimalNumber(decimal: clothing.totalBalance).stringValue)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
