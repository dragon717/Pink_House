//
//  DepositNotificationRecord.swift
//  ItemManager
//
//  补款提醒记录模型，用于持久化存储提醒历史
//

import Foundation
import SwiftData

/// 补款提醒记录 - 用于记录每次补款提醒的发送情况
@Model
final class DepositNotificationRecord {
    var id: UUID = UUID()
    var clothingID: UUID = UUID()
    var clothingName: String = ""
    var scheduledDate: Date = Date()
    var actualDate: Date? = nil
    var daysBefore: Int = 0
    var isTriggered: Bool = false
    var isRead: Bool = false
    var createdAt: Date = Date()
    var lastModified: Date = Date()
    /// 通知来源：apple = Apple推送通知, local = 本地记录
    var source: String = "local"
    
    init(clothingID: UUID, clothingName: String, scheduledDate: Date, daysBefore: Int, source: String = "local") {
        self.id = UUID()
        self.clothingID = clothingID
        self.clothingName = clothingName
        self.scheduledDate = scheduledDate
        self.daysBefore = daysBefore
        self.source = source
        self.createdAt = Date()
        self.lastModified = Date()
    }
    
    /// 标记为已触发
    func markAsTriggered(source: String = "apple") {
        self.isTriggered = true
        self.actualDate = Date()
        self.source = source
        self.lastModified = Date()
    }
    
    /// 标记为已读
    func markAsRead() {
        self.isRead = true
        self.lastModified = Date()
    }
}

/// 补款提醒设置 - 用于CloudKit同步的设置数据
@Model
final class DepositNotificationSettings {
    var id: UUID = UUID()
    var isEnabled: Bool = false
    var selectedDays: [Int] = [0]
    var notificationHour: Int = 9
    var notificationMinute: Int = 0
    var lastModified: Date = Date()
    
    init() {
        self.id = UUID()
        self.isEnabled = false
        self.selectedDays = [0]
        self.notificationHour = 9
        self.notificationMinute = 0
        self.lastModified = Date()
    }
    
    /// 获取提醒时间
    var notificationTime: Date {
        var components = DateComponents()
        components.hour = notificationHour
        components.minute = notificationMinute
        return Calendar.current.date(from: components) ?? Date()
    }
    
    /// 设置提醒时间
    func setNotificationTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.notificationHour = components.hour ?? 9
        self.notificationMinute = components.minute ?? 0
        self.lastModified = Date()
    }
}
