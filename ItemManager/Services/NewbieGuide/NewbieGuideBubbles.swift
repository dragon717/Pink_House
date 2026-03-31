import SwiftUI

struct GenericFeatureGuideBubbleView: View {
    let title: String
    let message: String
    let currentStep: Int
    let totalSteps: Int
    let accent: Color
    let actionTitle: String?
    let actionGuideTarget: GuideTargetKey?
    let onSkip: () -> Void
    let onAction: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var effectiveAccent: Color {
        accent.mixed(with: magicPalette.accent, amount: 1.0)
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
                HStack(spacing: 4) {
                    ForEach(1...max(totalSteps, 1), id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? effectiveAccent : magicPalette.tertiaryText.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)

                if let actionTitle {
                    Button {
                        onAction?()
                    } label: {
                        Text(actionTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(magicPalette.bubbleUserTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [effectiveAccent, effectiveAccent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .captureGuideTarget(actionGuideTarget)
                    .padding(.top, 8)
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
        .padding(.horizontal, 20)
        .captureGuideInteractionRegion("guide.text.bubble")
    }
}

struct WidgetScrollHintView: View {
    let title: String
    let subtitle: String
    @State private var animateHint = false
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    init(
        title: String = "请向下滑动",
        subtitle: String = "小组件入口在更下方的豆腐块区域"
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(magicPalette.primaryText)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(magicPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(magicPalette.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(magicPalette.quickOptionStroke, lineWidth: 1)
            )

            VStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(magicPalette.accent)
                    .offset(y: animateHint ? 18 : -4)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(magicPalette.accent.opacity(0.96))
                    .scaleEffect(animateHint ? 1.08 : 0.94)
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
                    .offset(y: animateHint ? 14 : 0)
            }
            .opacity(0.98)

            Spacer()
        }
        .padding(.bottom, 180)
        .onAppear {
            guard !animateHint else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animateHint = true
            }
        }
    }
}
