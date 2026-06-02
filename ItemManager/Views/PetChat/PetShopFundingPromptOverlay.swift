import SwiftUI

struct PetShopFundingPromptOverlay: View {
    let prompt: PetFundingPrompt
    let onDismiss: () -> Void
    let onPrimaryAction: () -> Void

    private var accentGradient: LinearGradient {
        switch prompt.currency {
        case .meowCoin:
            return LinearGradient(
                colors: [Color(hex: "FFD76A"), Color(hex: "FF9F43")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .fishCoin:
            return LinearGradient(
                colors: [Color(hex: "7DD3FC"), Color(hex: "38BDF8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .boneCoin:
            return LinearGradient(
                colors: [Color(hex: "E7C9A9"), Color(hex: "C08A5B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var accentTint: Color {
        switch prompt.currency {
        case .meowCoin:
            return Color(hex: "FFB020")
        case .fishCoin:
            return Color(hex: "0EA5E9")
        case .boneCoin:
            return Color(hex: "A16207")
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accentGradient)
                            .frame(width: 58, height: 58)
                            .shadow(color: accentTint.opacity(0.28), radius: 14, x: 0, y: 8)
                        promptIcon
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("余额不足".appLocalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .themeSkinAdaptiveSectionCard(slot: .filterChip, cornerRadius: 16, showsDecoration: false) {
                                Capsule().fill(accentTint.opacity(0.12))
                            }

                        Text(prompt.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(prompt.message)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .themeSkinAdaptiveSectionCard(slot: .iconCircleButton, cornerRadius: 14, showsDecoration: false) {
                                Circle().fill(Color.black.opacity(0.05))
                            }
                    }
                }

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("稍后再说".appLocalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .themeSkinAdaptiveSectionCard(slot: .filterChip, cornerRadius: 22, showsDecoration: false) {
                                Capsule().fill(Color.black.opacity(0.05))
                            }
                    }

                    Button(action: onPrimaryAction) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text(prompt.actionTitle)
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 22, showsDecoration: false) {
                            accentGradient
                        }
                        .shadow(color: accentTint.opacity(0.24), radius: 12, x: 0, y: 8)
                    }
                }
            }
            .padding(22)
            .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 28) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: 460)
        }
    }

    @ViewBuilder
    private var promptIcon: some View {
        switch prompt.currency {
        case .meowCoin:
            Image(systemName: "pawprint.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
        case .fishCoin:
            Image(systemName: "fish.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        case .boneCoin:
            Text("🦴")
                .font(.system(size: 26))
        }
    }
}
