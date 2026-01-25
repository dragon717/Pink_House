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
        static let depositNotificationDaysBefore = "depositNotificationDaysBefore"
        static let depositNotificationTime = "depositNotificationTime"
    }
    
    // MARK: - Properties
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isDepositNotificationEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isDepositNotificationEnabled) }
    }
    
    var daysBefore: Int {
        get { UserDefaults.standard.integer(forKey: Keys.depositNotificationDaysBefore) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.depositNotificationDaysBefore) }
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
        guard isEnabled, clothing.isDepositPlan, let finalDate = clothing.finalPaymentDate else {
            // If conditions not met, ensure no notification exists
            cancelNotification(for: clothing)
            return
        }
        
        let center = UNUserNotificationCenter.current()
        
        // Calculate trigger date
        let calendar = Calendar.current
        
        // Adjust final date by subtracting daysBefore
        // Ensure we are working with the start of the day for finalDate to avoid time confusion
        let finalDateStart = calendar.startOfDay(for: finalDate)
        
        guard let targetDate = calendar.date(byAdding: .day, value: -daysBefore, to: finalDateStart) else { return }
        
        // Combine target date with notificationTime
        let timeComponents = calendar.dateComponents([.hour, .minute], from: notificationTime)
        
        var triggerComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
        triggerComponents.hour = timeComponents.hour
        triggerComponents.minute = timeComponents.minute
        
        guard let triggerDate = calendar.date(from: triggerComponents) else { return }
        
        // Don't schedule if in the past
        if triggerDate < Date() {
            // print("Skipping past notification for \(clothing.name) at \(triggerDate)")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "尾款支付提醒"
        
        var body = "您的 \"\(clothing.name)\" 需要支付尾款了"
        if daysBefore > 0 {
            body += " (还有 \(daysBefore) 天)"
        } else {
            body += " (今天是截止日)"
        }
        body += "\n预估时间: \(formatDate(finalDate))"
        
        content.body = body
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let request = UNNotificationRequest(identifier: clothing.id.uuidString, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Error scheduling notification for \(clothing.name): \(error)")
            } else {
                // print("Scheduled notification for \(clothing.name) at \(triggerDate)")
            }
        }
    }
    
    @MainActor
    func cancelNotification(for clothing: Clothing) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [clothing.id.uuidString])
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
