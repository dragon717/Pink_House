import SwiftUI
import Combine

/// 全局 Toast 管理器
/// 用于显示各种提示信息（成功、错误、警告等）
@Observable
class ToastManager {
    static let shared = ToastManager()
    
    var isShowing = false
    var message = ""
    var type: ToastType = .info
    private var hideTask: Task<Void, Never>?
    
    private init() {}
    
    enum ToastType {
        case success
        case error
        case warning
        case info
        
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
    
    /// 显示 Toast 提示
    /// - Parameters:
    ///   - message: 提示内容
    ///   - type: 提示类型
    ///   - duration: 显示时长（秒），默认 2 秒
    func show(message: String, type: ToastType = .info, duration: Double = 2.0) {
        // 取消之前的隐藏任务
        hideTask?.cancel()
        
        self.message = message
        self.type = type
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isShowing = true
        }
        
        // 触发触觉反馈
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // 指定时间后自动隐藏
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            
            // 检查任务是否被取消
            guard !Task.isCancelled else { return }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowing = false
            }
        }
    }
    
    /// 显示成功提示
    func showSuccess(_ message: String, duration: Double = 1.5) {
        show(message: message, type: .success, duration: duration)
    }
    
    /// 显示错误提示
    func showError(_ message: String, duration: Double = 2.5) {
        show(message: message, type: .error, duration: duration)
    }
    
    /// 显示警告提示
    func showWarning(_ message: String, duration: Double = 2.0) {
        show(message: message, type: .warning, duration: duration)
    }
    
    /// 隐藏当前 Toast
    func hide() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowing = false
        }
    }
}

/// 全局 Toast 视图 - 显示在屏幕顶部
struct GlobalToast: View {
    @State private var manager = ToastManager.shared
    
    var body: some View {
        VStack {
            if manager.isShowing {
                ToastContent(message: manager.message, type: manager.type)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            
            Spacer()
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false) // 不拦截下方触摸事件
    }
}

/// Toast 内容视图
private struct ToastContent: View {
    let message: String
    let type: ToastManager.ToastType
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(type.color)
            
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(type.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        
        VStack(spacing: 20) {
            Button("显示成功") {
                ToastManager.shared.showSuccess("操作成功完成！")
            }
            
            Button("显示错误") {
                ToastManager.shared.showError("网络连接失败，请稍后重试")
            }
            
            Button("显示警告") {
                ToastManager.shared.showWarning("请注意检查输入内容")
            }
            
            Button("显示信息") {
                ToastManager.shared.show(message: "正在后台同步数据...")
            }
        }
        
        GlobalToast()
    }
}
