//
//  NotificationManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import UserNotifications
import SwiftUI

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
                return list
            }
            // Migration: if old key exists, use it
            if UserDefaults.standard.object(forKey: Keys.depositNotificationDaysBefore) != nil {
                let oldDay = UserDefaults.standard.integer(forKey: Keys.depositNotificationDaysBefore)
                return [oldDay]
            }
            return [0] // Default
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.depositNotificationDaysList)
        }
    }
    
    // Compatibility property (optional, but good to keep basic logic working if accessed elsewhere)
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
    
    // MARK: - Scheduling
    @MainActor
    func scheduleNotification(for clothing: Clothing) {
        // Cancel existing first (synchronously removes all potential variants)
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
        }
    }
    
    @MainActor
    func cancelNotification(for clothing: Clothing) {
        let center = UNUserNotificationCenter.current()
        
        // Remove legacy ID (exact match)
        center.removePendingNotificationRequests(withIdentifiers: [clothing.id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [clothing.id.uuidString])
        
        // Remove all potential variants based on supported options
        // Ideally we should fetch pending requests to be sure, but that's async.
        // For now, we iterate through all possible options provided in UI.
        let potentialDays = [0, 1, 3, 7, 15, 30]
        let idsToRemove = potentialDays.map { "\(clothing.id.uuidString)_\($0)" }
        
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
    }
    
    @MainActor
    func rescheduleAllNotifications(clothings: [Clothing]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        guard isEnabled else { return }
        
        // Check permission first
        let status = await checkAuthorizationStatus()
        if status != .authorized {
            return
        }
        
        for clothing in clothings {
            scheduleNotification(for: clothing)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
