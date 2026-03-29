import SwiftUI

// VIP试用期弹窗视图 - 现代化设计
struct VIPTrialPopupView: View {
    @Binding var isPresented: Bool
    var onConfirm: () -> Void
    var onDismiss: () -> Void
    
    @Environment(ThemeManager.self) private var themeManager
    @State private var showContent = false
    @State private var glowAnimation = false
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPopup()
                }
            
            // 弹窗内容
            VStack(spacing: 0) {
                // 顶部装饰区域
                ZStack {
                    // 渐变背景
                    LinearGradient(
                        colors: [
                            Color(hex: "FFD700"),
                            Color(hex: "FFA500"),
                            Color(hex: "FF6B6B")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // 发光效果
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .blur(radius: 60)
                        .offset(y: glowAnimation ? -10 : 10)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: glowAnimation)
                    
                    // VIP图标
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "FFF8DC")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color(hex: "FFD700").opacity(0.8), radius: 20, x: 0, y: 0)
                        
                        Text("VIP")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "FFF8DC")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                
                // 内容区域
                VStack(spacing: 20) {
                    // 标题
                    VStack(spacing: 8) {
                        Text("限时免费体验")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("尊享会员特权 3 天")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 特权列表
                    VStack(alignment: .leading, spacing: 16) {
                        PrivilegeRow(icon: "brain.head.profile", text: "解锁 AI 智能对话")
                        // PrivilegeRow(icon: "mic.fill", text: "语音交互无限制")
                        PrivilegeRow(icon: "sparkles", text: "专属 VIP 身份标识")
                    }
                    .padding(.horizontal, 20)
                    
                    // 按钮区域
                    VStack(spacing: 12) {
                        // 确认体验按钮
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                onConfirm()
                                isPresented = false
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("确认体验")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "FFD700"),
                                        Color(hex: "FFA500")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color(hex: "FFD700").opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        .captureGuideTarget(.aiAnalysisVIPTrialConfirmButton)
                        
                        // 稍后按钮
                        Button(action: {
                            dismissPopup()
                        }) {
                            Text("稍后")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 24)
                .background(themeManager.backgroundColor)
            }
            .background(themeManager.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
            .padding(.horizontal, 32)
            .scaleEffect(showContent ? 1.0 : 0.8)
            .opacity(showContent ? 1.0 : 0.0)
            .offset(y: showContent ? 0 : 50)
        }
        .onAppear {
            glowAnimation = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }
    
    private func dismissPopup() {
        withAnimation(.spring(response: 0.3)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
            isPresented = false
        }
    }
}

// 特权行组件
private struct PrivilegeRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 32, height: 32)
            
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

// 预览
#Preview {
    VIPTrialPopupView(
        isPresented: .constant(true),
        onConfirm: { print("确认体验") },
        onDismiss: { print("关闭弹窗") }
    )
    .environment(ThemeManager.shared)
}
