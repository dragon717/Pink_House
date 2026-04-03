import SwiftUI

struct VIPTrialPopupView: View {
    let visualTheme: VIPVisualTheme
    @Binding var isPresented: Bool
    var onConfirm: () -> Void
    var onDismiss: () -> Void

    @State private var showContent = false

    init(
        visualTheme: VIPVisualTheme = VIPManager.shared.preferredVisualTheme,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.visualTheme = visualTheme
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPopup()
                }

            ZStack {
                popupBackground

                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(visualTheme.accentColor)

                        Text("先体验 3 天 VIP")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)

                        Text("解锁智能能力、尊贵身份与会员优惠")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(visualTheme.secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        privilegeRow(icon: "bubble.left.and.bubble.right.fill", text: "萌宠智能对话与多模态能力")
                        privilegeRow(icon: "crown.fill", text: "专属 VIP 身份与卡片皮肤")
                        privilegeRow(icon: "ticket.fill", text: "萌宠商店 \(VIPManager.petShopDiscountText)")
                    }

                    Text("体验结束后可继续兑换 1个月 / 3个月 会员时长")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                onConfirm()
                                isPresented = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("确认体验")
                            }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.92))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        visualTheme.accentColor,
                                        visualTheme.accentColor.opacity(0.82)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .shadow(color: visualTheme.glowColor, radius: 18, x: 0, y: 8)
                        }
                        .captureGuideTarget(.aiAnalysisVIPTrialConfirmButton)

                        Button {
                            dismissPopup()
                        } label: {
                            Text("稍后")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 26)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 28)
            .scaleEffect(showContent ? 1.0 : 0.88)
            .opacity(showContent ? 1.0 : 0.0)
            .offset(y: showContent ? 0 : 26)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                showContent = true
            }
        }
    }

    private var popupBackground: some View {
        ZStack {
            LinearGradient(
                colors: visualTheme.backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(visualTheme.glowColor)
                .frame(width: 180, height: 180)
                .blur(radius: 42)
                .offset(x: -76, y: -120)

            VIPGlassCardBackground(glassStyle: visualTheme.primaryGlassStyle, cornerRadius: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(visualTheme.primaryGlassStyle.strokeColor.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: visualTheme.primaryGlassStyle.glowColor, radius: 24, x: 0, y: 12)
    }

    private func privilegeRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(visualTheme.primaryGlassStyle.iconTint)
                .frame(width: 26, height: 26)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            VIPGlassCardBackground(glassStyle: .glossBlack, cornerRadius: 18)
        )
    }

    private func dismissPopup() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
            isPresented = false
        }
    }
}

#Preview {
    VIPTrialPopupView(
        visualTheme: .deepBlue,
        isPresented: .constant(true),
        onConfirm: { print("确认体验") },
        onDismiss: { print("关闭弹窗") }
    )
}
