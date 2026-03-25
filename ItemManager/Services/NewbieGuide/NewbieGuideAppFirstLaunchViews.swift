import SwiftUI

struct GuideCatVideoPlayer: View {
    let videoName: String
    let isLooping: Bool
    let isFlipped: Bool
    let onFinished: (() -> Void)?

    var body: some View {
        PetVideoPlayer(
            videoName: videoName,
            isLooping: isLooping,
            isMuted: true,
            onFinished: onFinished
        )
        .frame(width: 100, height: 100)
        .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
    }
}

struct WelcomeBubbleView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                Text("欢迎来到少女心愿衣橱")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text("我是你的向导奶茶，让我带你了解一下这个魔法衣橱吧！")
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Button {
                    onStart()
                } label: {
                    Text("开始探索")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
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
}

struct PointingBubbleView: View {
    let onSkip: () -> Void
    let onComplete: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onSkip()
                } label: {
                    Text("跳过")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(magicPalette.quickOptionText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(magicPalette.quickOptionFill)
                        .overlay(
                            Capsule()
                                .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 12) {
                Text("添加你的第一件裙子")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text("这里是衣橱的手动创建入口，你可以一件一件添加你的裙子。\n\n当然，我们也支持批量创建，一次导入多件衣物，省时省力！")
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text("点击右上角的 + 号试试")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(magicPalette.accent)
                    .padding(.top, 4)

                Button {
                    onComplete()
                } label: {
                    Text("知道了")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(magicPalette.bubbleUserTextColor)
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
                .padding(.top, 8)
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
}

struct SkipGuideConfirmationView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

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
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("继续引导")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(magicPalette.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(magicPalette.quickOptionFill)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        onConfirm()
                    } label: {
                        Text("确认跳过")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(magicPalette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(magicPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 40)
        }
    }
}

struct AppFirstLaunchGuideOverlay: View {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @State private var showingSkipConfirmation = false

    var body: some View {
        ZStack {
            switch guideManager.currentStep {
            case .welcome:
                welcomeMask
            case .running:
                runningMask
            case .pointing:
                pointingMask
            default:
                EmptyView()
            }

            if showingSkipConfirmation {
                SkipGuideConfirmationView(
                    onConfirm: {
                        showingSkipConfirmation = false
                        guideManager.completeGuide()
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

    private var welcomeMask: some View {
        ZStack {
            GeometryReader { _ in
                ZStack {
                    Color.black
                        .opacity(0.5)
                        .ignoresSafeArea()

                    Circle()
                        .frame(width: 100, height: 100)
                        .position(guideManager.floatingCatStartPosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }

            VStack {
                Spacer()

                WelcomeBubbleView(
                    onStart: {
                        guideManager.startRunningAnimation()
                    },
                    onSkip: {
                        showingSkipConfirmation = true
                    }
                )
                .padding(.bottom, 160)
            }
        }
    }

    private var runningMask: some View {
        ZStack {
            Color.black
                .opacity(0.3)
                .ignoresSafeArea()

            if guideManager.isRunningAnimation {
                let needsFlip = guideManager.catPosition.x < UIScreen.main.bounds.width / 2

                GuideCatVideoPlayer(
                    videoName: guideManager.runningVideoName,
                    isLooping: true,
                    isFlipped: needsFlip,
                    onFinished: nil
                )
                .position(guideManager.catPosition)
            }
        }
    }

    private var pointingMask: some View {
        ZStack {
            GeometryReader { _ in
                ZStack {
                    Color.black
                        .opacity(0.4)
                        .ignoresSafeArea()

                    Circle()
                        .frame(width: 80, height: 80)
                        .position(guideManager.highlightCirclePosition)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
            }

            if guideManager.showPointingVideo {
                GuideCatVideoPlayer(
                    videoName: guideManager.pointingVideoName,
                    isLooping: false,
                    isFlipped: false,
                    onFinished: nil
                )
                .position(guideManager.createButtonPosition)
                .allowsHitTesting(false)
            }

            if guideManager.showCreateButtonHighlight {
                HighlightPulseViewNoClick(
                    center: guideManager.highlightCirclePosition,
                    radius: 35
                )
                .allowsHitTesting(false)
            }

            VStack {
                Spacer()

                PointingBubbleView(
                    onSkip: {
                        showingSkipConfirmation = true
                    },
                    onComplete: {
                        guideManager.completeGuide()
                    }
                )
                .padding(.bottom, 120)
            }
        }
    }
}

extension View {
    func withAppFirstLaunchGuide() -> some View {
        modifier(AppFirstLaunchGuideModifier())
    }
}

struct AppFirstLaunchGuideModifier: ViewModifier {
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if guideManager.isShowingGuide {
                AppFirstLaunchGuideOverlay()
            }

            if guideManager.isShowingFeatureExperienceGuide {
                FeatureExperienceGuideOverlay()
            }
        }
    }
}
