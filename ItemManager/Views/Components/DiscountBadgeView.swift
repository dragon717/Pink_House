import SwiftUI

enum DiscountBadgeStyle {
    case capsuleGlow
    case inlineGlow
}

enum DiscountBadgeSize {
    case small
    case medium

    var fontSize: CGFloat {
        switch self {
        case .small:
            return 10
        case .medium:
            return 12
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small:
            return 8
        case .medium:
            return 10
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small:
            return 5
        case .medium:
            return 6
        }
    }
}

struct DiscountBadgeView: View {
    let text: String
    var style: DiscountBadgeStyle = .capsuleGlow
    var size: DiscountBadgeSize = .small

    private let highlightColor = Color(hex: "FF4D5E")
    private let glowColor = Color(hex: "FF2446")

    var body: some View {
        switch style {
        case .capsuleGlow:
            Text(text)
                .font(.system(size: size.fontSize, weight: .heavy))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(capsuleBackground)
                .fixedSize()
        case .inlineGlow:
            Text(text)
                .font(.system(size: size.fontSize, weight: .heavy))
                .foregroundStyle(highlightColor)
                .shadow(color: glowColor.opacity(0.95), radius: 7, x: 0, y: 0)
                .shadow(color: glowColor.opacity(0.55), radius: 14, x: 0, y: 0)
                .fixedSize()
        }
    }

    private var capsuleBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        highlightColor.opacity(0.26),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.16))
            )
            .overlay(
                Capsule()
                    .stroke(highlightColor.opacity(0.88), lineWidth: 1.1)
            )
            .shadow(color: glowColor.opacity(0.42), radius: 10, x: 0, y: 0)
    }
}

#Preview {
    VStack(spacing: 16) {
        DiscountBadgeView(text: "-5% OFF", style: .capsuleGlow, size: .small)
        DiscountBadgeView(text: "-40% OFF", style: .inlineGlow, size: .medium)
    }
    .padding()
    .background(Color.black)
}
