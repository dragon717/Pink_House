//
//  ShopCatalogSaleReminder.swift
//  ItemManager
//
//  店家上新「开售提醒」本地通知（V1.2 四态按钮配套）：
//  商品处于「预约未开始」时，用户点【加入心愿】的实际作用是开售提醒——
//  本服务在预约窗口 startAt 到点弹出本地通知，提醒用户来买。
//
//  设计：
//  · 独立 identifier 前缀，不与尾款提醒（NotificationManager）互相干扰；
//  · 同一商品重复加入心愿 = 同 identifier 覆盖，天然幂等；
//  · 纯逻辑（挑时间 / 拼标识）与系统能力（授权 / 注册）分离，前者可单测。
//

import Foundation
import UserNotifications

nonisolated enum ShopCatalogSaleReminder {

    /// 通知 identifier 前缀（也用于清理）
    static let identifierPrefix = "shop-catalog-sale-reminder-"

    // MARK: - 纯逻辑（可单测）

    /// 从商品销售记录里挑出「下一次预约开始时间」：
    /// 只看预约窗口（type == .reservation）且 startAt 在未来的记录，取最早的一个。
    /// 没有可提醒的时间（未定档 / 已开始 / 已结束）返回 nil。
    static func upcomingSaleStart(events: [CatalogSaleEvent], now: Date = Date()) -> Date? {
        events
            .filter { $0.type == .reservation }
            .compactMap { $0.startAt }
            .filter { $0 > now }
            .min()
    }

    /// 同一商品固定一个 identifier：重复加入 = 覆盖旧提醒，不重复堆积
    static func identifier(for productID: String) -> String {
        identifierPrefix + productID
    }

    static func contentTitle() -> String {
        "开售提醒"
    }

    static func contentBody(productName: String, seriesName: String?) -> String {
        let label = seriesName.map { "\($0)·\(productName)" } ?? productName
        return "「\(label)」预约已开始，记得去店家下单"
    }

    // MARK: - 系统能力（授权 + 注册）

    /// 注册开售提醒。返回用户可感知的结果，供调用方 toast。
    /// - 返回 false：通知权限被拒（提醒注册不了，调用方应提示去设置开启）。
    @MainActor
    static func schedule(
        productID: String,
        productName: String,
        seriesName: String?,
        fireDate: Date
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return false }
        default:
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = contentTitle()
        content.body = contentBody(productName: productName, seriesName: seriesName)
        content.sound = .default
        content.userInfo = [
            "kind": "shop-catalog-sale-reminder",
            "catalogProductID": productID
        ]

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: productID), content: content, trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    /// 取消某商品的开售提醒（移除心愿时调用；不存在时为无害操作）
    @MainActor
    static func cancel(productID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: productID)])
    }
}
