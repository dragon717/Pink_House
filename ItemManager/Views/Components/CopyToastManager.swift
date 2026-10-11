import Foundation

/// 复制是普通操作反馈，不自动产生鱼币奖励。
@MainActor
final class CopyToastManager {
    static let shared = CopyToastManager()
    private init() {}

    func show(text: String) {
        OperationFeedbackCenter.shared.show("已拷贝到剪贴板".appLocalized,
                                             kind: .success, detail: text, duration: 1.5)
    }
}
