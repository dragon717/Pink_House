import SwiftUI

// MARK: - 萌宠对话新手引导遮罩视图

struct PetChatGuideOverlay: View {
    @StateObject private var guideManager = PetChatGuideManager.shared
    @State private var showingSkipConfirmation = false
    @State private var bubbleOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明背景 + 挖空高亮
                maskLayer(in: geometry)

                // 高亮脉冲效果
                if guideManager.showHighlight {
                    highlightPulseLayer(in: geometry)
                }

                // 气泡内容
                bubbleContent(in: geometry)

                // 跳过确认弹窗
                if showingSkipConfirmation {
                    SkipConfirmationView(
                        onConfirm: {
                            showingSkipConfirmation = false
                            guideManager.skipGuide()
                        },
                        onCancel: {
                            showingSkipConfirmation = false
                        }
                    )
                }
            }
            .transition(.opacity)
            .zIndex(1000)
        }
    }

    // MARK: - 遮罩层（带挖空）

    private func maskLayer(in geometry: GeometryProxy) -> some View {
        ZStack {
            // 半透明背景
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()

            // 挖空区域 - 允许点击穿透
            if guideManager.showHighlight {
                highlightCutout(in: geometry)
            }
        }
        .compositingGroup()
        // 允许点击穿透到挖空区域
        .allowsHitTesting(false)
    }

    // MARK: - 高亮挖空

    private func highlightCutout(in geometry: GeometryProxy) -> some View {
        let frame = guideManager.highlightFrame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let radius = max(frame.width, frame.height) / 2

        return Circle()
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .blendMode(.destinationOut)
    }

    // MARK: - 脉冲高亮效果

    private func highlightPulseLayer(in geometry: GeometryProxy) -> some View {
        let frame = guideManager.highlightFrame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let radius = max(frame.width, frame.height) / 2

        return HighlightPulseViewNoClick(
            center: center,
            radius: radius
        )
        .allowsHitTesting(false)
    }

    // MARK: - 气泡内容

    private func bubbleContent(in geometry: GeometryProxy) -> some View {
        VStack {
            // 根据步骤调整气泡位置
            if shouldShowBubbleAtTop {
                Spacer()
            }

            GuideBubbleView(
                step: guideManager.currentStep,
                onNext: {
                    handleNextStep()
                },
                onSkip: {
                    showingSkipConfirmation = true
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, shouldShowBubbleAtTop ? 100 : 0)
            .padding(.top, shouldShowBubbleAtTop ? 0 : 100)

            if !shouldShowBubbleAtTop {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 判断气泡位置

    private var shouldShowBubbleAtTop: Bool {
        // 根据高亮位置判断气泡应该显示在上方还是下方
        let frame = guideManager.highlightFrame
        let screenHeight = UIScreen.main.bounds.height
        return frame.midY > screenHeight / 2
    }

    // MARK: - 处理下一步

    private func handleNextStep() {
        switch guideManager.currentStep {
        case .welcome:
            // 欢迎步骤点击后，跳转到"我"tab步骤
            guideManager.nextStep()
            // 发送通知让主视图切换到"我"tab
            NotificationCenter.default.post(name: .petChatGuideSwitchToMeTab, object: nil)
        case .goToMeTab:
            guideManager.nextStep()
        case .clickVIPCard:
            guideManager.nextStep()
        case .rechargeCoins:
            guideManager.nextStep()
        case .redeemVIP:
            guideManager.completeGuide()
        default:
            guideManager.nextStep()
        }
    }
}

// MARK: - 引导气泡视图

struct GuideBubbleView: View {
    let step: PetChatGuideStep
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 跳过按钮
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // 内容区域
            VStack(spacing: 12) {
                // 图标
                Image(systemName: iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(magicPalette.accent)

                Text(step.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Text(step.description)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                // 下一步按钮
                Button {
                    onNext()
                } label: {
                    Text(buttonText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [magicPalette.accent, magicPalette.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(magicPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: 320)
    }

    private var iconName: String {
        switch step {
        case .none: return ""
        case .welcome: return "sparkles"
        case .goToMeTab: return "person.fill"
        case .clickVIPCard: return "crown.fill"
        case .rechargeCoins: return "pawprint.circle.fill"
        case .redeemVIP: return "gift.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private var buttonText: String {
        if step.buttonText.isEmpty {
            return "知道了"
        }
        return step.buttonText
    }
}

// MARK: - 跳过确认弹窗

struct SkipConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("跳过新手引导？")
                    .font(.system(size: 18, weight: .bold))

                Text("跳过之后可以随时在设置中重新开启引导")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("继续引导")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        onConfirm()
                    } label: {
                        Text("确认跳过")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - 高亮锚点视图修饰器

struct PetChatGuideHighlightAnchorView: View {
    let anchor: PetChatGuideHighlightAnchor
    @StateObject private var guideManager = PetChatGuideManager.shared

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    updateHighlightFrame(in: geometry)
                }
                .onChange(of: guideManager.currentStep) { _ in
                    updateHighlightFrame(in: geometry)
                }
        }
    }

    private func updateHighlightFrame(in geometry: GeometryProxy) {
        let frame = geometry.frame(in: .global)

        // 根据当前步骤和锚点类型决定是否显示高亮
        let shouldHighlight = shouldShowHighlight(for: anchor)

        if shouldHighlight {
            guideManager.updateHighlightFrame(frame)
        }
    }

    private func shouldShowHighlight(for anchor: PetChatGuideHighlightAnchor) -> Bool {
        switch (guideManager.currentStep, anchor) {
        case (.welcome, .floatingCat):
            return true
        case (.goToMeTab, .meTab):
            return true
        case (.clickVIPCard, .vipCard):
            return true
        case (.rechargeCoins, .rechargeButton):
            return true
        case (.redeemVIP, .redeemButton):
            return true
        default:
            return false
        }
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    static let petChatGuideSwitchToMeTab = Notification.Name("petChatGuideSwitchToMeTab")
}
