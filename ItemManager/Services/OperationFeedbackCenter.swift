import SwiftUI

/// 普通操作提示的唯一队列。业务保存和奖励记账完成后，才把结果交给这里展示。
@MainActor
@Observable
final class OperationFeedbackCenter {
    static let shared = OperationFeedbackCenter()
    // 没有 UI 清理工作；UIKit 释放宿主时不切换 deinit executor。
    nonisolated deinit {}

    struct RewardRequest {
        let type: RewardType
        /// 使用记录 ID / 交易 ID；不能用每次点击新生成的 UUID。
        let operationID: String
    }

    struct Message: Identifiable, Equatable {
        let id: UUID
        let text: String
        let kind: ToastManager.ToastType
        let fishCoins: Int
        let detail: String?
        let duration: Double
    }

    private(set) var messages: [Message] = []
    var current: Message? { messages.first }

    func show(_ text: String, kind: ToastManager.ToastType = .info,
              fishCoins: Int = 0, detail: String? = nil, duration: Double = 2) {
        messages.append(Message(id: UUID(), text: text, kind: kind,
                                fishCoins: max(0, fishCoins), detail: detail,
                                duration: max(0.5, duration)))
    }

    func dismiss(id: UUID) {
        messages.removeAll { $0.id == id }
    }

    /// 用户操作成功 + 奖励合并成一条提示；奖励失败不改变已保存的业务结果。
    func succeeded(_ text: String, rewards: [RewardRequest] = [],
                   rewardManager: RewardManager? = nil) {
        let rewardManager = rewardManager ?? .shared
        var earned = 0
        var limited = false
        var failed = false
        for reward in rewards {
            let receipt = rewardManager.grant(type: reward.type, operationID: reward.operationID)
            earned += receipt.actualAmount
            limited = limited || receipt.isLimited
            failed = failed || receipt.status == .unavailable
        }
        let detail = failed ? "奖励暂未到账".appLocalized
            : limited ? "已达到今日鱼币奖励上限".appLocalized : nil
        show(text, kind: .success, fishCoins: earned, detail: detail, duration: 3)
    }
}
