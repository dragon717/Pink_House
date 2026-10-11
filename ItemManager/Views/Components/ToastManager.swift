import SwiftUI

/// 保留已有调用入口，展示与生命周期统一归 OperationFeedbackCenter 管理。
@MainActor
final class ToastManager {
    static let shared = ToastManager()
    private init() {}

    enum ToastType: Equatable {
        case success, error, warning, info
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
    }

    func show(message: String, type: ToastType = .info, duration: Double = 2) {
        OperationFeedbackCenter.shared.show(message, kind: type, duration: duration)
    }
    func showSuccess(_ message: String, duration: Double = 1.5) {
        show(message: message, type: .success, duration: duration)
    }
    func showError(_ message: String, duration: Double = 2.5) {
        show(message: message, type: .error, duration: duration)
    }
    func showWarning(_ message: String, duration: Double = 2) {
        show(message: message, type: .warning, duration: duration)
    }
}
