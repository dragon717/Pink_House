import SwiftData
import Foundation

/// 已保存的衣橱操作产生一次成功反馈，奖励标识取业务记录而不是视图 UUID。
@MainActor
enum WardrobeOperationFeedback {
    static func added(_ clothing: [Clothing], message: String? = nil) {
        let ids = Array(Set(clothing.map(\.id))).sorted { $0.uuidString < $1.uuidString }
        guard !ids.isEmpty else { return }
        OperationFeedbackCenter.shared.succeeded(
            message ?? (ids.count == 1 ? "添加成功，已加入少女衣橱".appLocalized
                        : "添加成功，已加入少女衣橱（%@ 条记录）".appLocalized(String(ids.count))),
            rewards: ids.map { .init(type: .addClothing, operationID: "wardrobe-add:\($0.uuidString)") })
    }

    static func paidBalance(for clothing: Clothing, paymentID: UUID) {
        OperationFeedbackCenter.shared.succeeded("已标记为已付尾款".appLocalized,
            rewards: [.init(type: .payBalance, operationID: "balance-paid:\(paymentID.uuidString)")])
    }

    /// 时光馆没有手动编辑页的保存收尾，需在整个图片/记录事务成功后统一补齐。
    static func completeTimeHallAddition(_ clothing: [Clothing], context: ModelContext,
                                        message: String? = nil) {
        guard !clothing.isEmpty else { return }
        for item in clothing {
            NotificationCenter.default.post(name: .depositPlanDataDidChange, object: item.id)
            NotificationManager.shared.scheduleNotification(for: item, modelContext: context)
        }
        FeatureUnlockManager.shared.refreshClothingCountCache(from: context, reason: "time-hall-add")
        Task { await SharedPersistence.shared.syncWidgetData(reason: "time-hall-add") }
        added(clothing, message: message)
    }
}
