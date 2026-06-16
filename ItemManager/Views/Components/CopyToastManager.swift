import SwiftUI
import Combine

/// 全局拷贝提示管理器
/// 用于在屏幕中央上方显示拷贝成功提示
@Observable
class CopyToastManager {
    static let shared = CopyToastManager()
    
    var isShowing = false
    var copiedText = ""
    private var hideTask: Task<Void, Never>?
    
    private init() {}
    
    /// 显示拷贝成功提示
    func show(text: String) {
        // 取消之前的隐藏任务
        hideTask?.cancel()
        
        copiedText = text
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isShowing = true
        }
        
        // 触发触觉反馈
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // 1.5秒后自动隐藏
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            
            // 检查任务是否被取消
            guard !Task.isCancelled else { return }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowing = false
            }
        }
    }
}

/// 全局拷贝提示视图 - 显示在屏幕中央上方
struct GlobalCopyToast: View {
    @State private var manager = CopyToastManager.shared
    
    var body: some View {
        VStack {
            if manager.isShowing {
                CopyToastContent(text: manager.copiedText)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            
            Spacer()
        }
        .padding(.top, 100) // 屏幕中央上方
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false) // 不拦截下方触摸事件
    }
}

/// 拷贝提示内容视图
private struct CopyToastContent: View {
    let text: String
    
    var body: some View {
        VStack(spacing: 16) {
            // 成功图标
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 70, height: 70)
                
                Circle()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: 55, height: 55)
                
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.green)
            }
            
            // 标题
            Text("已拷贝到剪贴板".appLocalized)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            
            // 拷贝的内容预览
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .frame(maxWidth: 280)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        
        GlobalCopyToast()
    }
}
