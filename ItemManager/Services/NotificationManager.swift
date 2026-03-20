//
//  NotificationManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import UserNotifications
import SwiftUI
import SwiftData

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 在前台也显示通知 (Banner, Sound, Badge)
        completionHandler([.banner, .sound, .badge])
    }
    
    // MARK: - Settings Keys
    struct Keys {
        static let isDepositNotificationEnabled = "isDepositNotificationEnabled"
        static let depositNotificationDaysBefore = "depositNotificationDaysBefore" // Deprecated, kept for migration
        static let depositNotificationDaysList = "depositNotificationDaysList"
        static let depositNotificationTime = "depositNotificationTime"
    }
    
    // MARK: - Properties
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isDepositNotificationEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isDepositNotificationEnabled) }
    }
    
    // Support multiple reminder days
    var daysBeforeList: [Int] {
        get {
            if let list = UserDefaults.standard.array(forKey: Keys.depositNotificationDaysList) as? [Int] {
                return list.sorted()
            }
            // Migration: if old key exists, use it
            if UserDefaults.standard.object(forKey: Keys.depositNotificationDaysBefore) != nil {
                let oldDay = UserDefaults.standard.integer(forKey: Keys.depositNotificationDaysBefore)
                return [oldDay]
            }
            return [0] // Default: 当天
        }
        set {
            UserDefaults.standard.set(newValue.sorted(), forKey: Keys.depositNotificationDaysList)
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
        return granted
    }
    
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Scheduling with Record Creation
    @MainActor
    func scheduleNotification(for clothing: Clothing, modelContext: ModelContext? = nil) {
        // Cancel existing first
        cancelNotification(for: clothing)
        
        guard isEnabled, clothing.isDepositPlan, let finalDate = clothing.finalPaymentDate else {
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let finalDateStart = calendar.startOfDay(for: finalDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        
        for days in daysBeforeList {
            guard let targetDate = calendar.date(byAdding: .day, value: -days, to: finalDateStart) else { continue }
            
            var triggerComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            triggerComponents.hour = timeComponents.hour
            triggerComponents.minute = timeComponents.minute
            
            guard let triggerDate = calendar.date(from: triggerComponents) else { continue }
            
            if triggerDate < Date() { continue }
            
            let content = UNMutableNotificationContent()
            content.title = "尾款支付提醒"
            
            var body = "您的 \"\(clothing.name)\" 需要支付尾款了"
            if days > 0 {
                body += " (还有 \(days) 天)"
            } else {
                body += " (今天是截止日)"
            }
            body += "\n预估时间: \(formatDate(finalDate))"
            
            content.body = body
            content.sound = .default
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            
            // ID format: UUID_days
            let identifier = "\(clothing.id.uuidString)_\(days)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification for \(clothing.name): \(error)")
                }
            }
            
            // 创建提醒记录
            if let context = modelContext {
                let record = DepositNotificationRecord(
                    clothingID: clothing.id,
                    clothingName: clothing.name,
                    scheduledDate: triggerDate,
                    daysBefore: days
                )
                context.insert(record)
            }
        }
    }
    
    @MainActor
    func cancelNotification(for clothing: Clothing) {
        let center = UNUserNotificationCenter.current()
        
        // Remove legacy ID (exact match)
        center.removePendingNotificationRequests(withIdentifiers: [clothing.id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [clothing.id.uuidString])
        
        // Remove all potential variants
        let potentialDays = [0, 1, 3, 7, 15, 30]
        let idsToRemove = potentialDays.map { "\(clothing.id.uuidString)_\($0)" }
        
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
    }
    
    @MainActor
    func rescheduleAllNotifications(clothings: [Clothing], modelContext: ModelContext? = nil) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        guard isEnabled else { return }
        
        // Check permission first
        let status = await checkAuthorizationStatus()
        if status != .authorized {
            return
        }
        
        for clothing in clothings {
            scheduleNotification(for: clothing, modelContext: modelContext)
        }
        
        // Save context if provided
        if let context = modelContext {
            try? context.save()
        }
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
        guard clothing.isDepositPlan, let finalDate = clothing.finalPaymentDate else { return }

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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
