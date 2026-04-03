import SwiftUI

enum VIPVisualTheme: String, CaseIterable, Identifiable {
    case black
    case deepBlue
    case monicaPink

    var id: String { rawValue }

    var backgroundGradientColors: [Color] {
        switch self {
        case .black:
            return [
                Color(hex: "111111"),
                Color(hex: "1E1E1E"),
                Color(hex: "050505")
            ]
        case .deepBlue:
            return [
                Color(hex: "183B64"),
                Color(hex: "0E223D"),
                Color(hex: "060A12")
            ]
        case .monicaPink:
            return [
                Color(hex: "5B2743"),
                Color(hex: "2E1525"),
                Color(hex: "090608")
            ]
        }
    }

    var glowColor: Color {
        switch self {
        case .black:
            return Color.white.opacity(0.12)
        case .deepBlue:
            return Color(hex: "7CD9FF").opacity(0.28)
        case .monicaPink:
            return Color(hex: "FF8FD8").opacity(0.24)
        }
    }

    var accentColor: Color {
        switch self {
        case .black:
            return Color(hex: "E5E7EB")
        case .deepBlue:
            return Color(hex: "9AE7FF")
        case .monicaPink:
            return Color(hex: "FFB2E5")
        }
    }

    var secondaryTextColor: Color {
        Color.white.opacity(0.72)
    }

    var primaryGlassStyle: VIPGlassStyle {
        switch self {
        case .black:
            return .glossBlack
        case .deepBlue:
            return .iceBlue
        case .monicaPink:
            return .glossPink
        }
    }

    var secondaryGlassStyle: VIPGlassStyle {
        .glossBlack
    }
}

enum VIPGlassStyle: String, CaseIterable, Identifiable {
    case glossBlack
    case iceBlue
    case glossPink

    var id: String { rawValue }

    var fillColors: [Color] {
        switch self {
        case .glossBlack:
            return [
                Color.white.opacity(0.12),
                Color.black.opacity(0.34),
                Color.black.opacity(0.56)
            ]
        case .iceBlue:
            return [
                Color(hex: "7CD9FF").opacity(0.28),
                Color(hex: "17314E").opacity(0.42),
                Color.black.opacity(0.56)
            ]
        case .glossPink:
            return [
                Color(hex: "FFB2E5").opacity(0.28),
                Color(hex: "51253E").opacity(0.42),
                Color.black.opacity(0.56)
            ]
        }
    }

    var strokeColor: Color {
        switch self {
        case .glossBlack:
            return Color.white.opacity(0.22)
        case .iceBlue:
            return Color(hex: "A7EEFF").opacity(0.55)
        case .glossPink:
            return Color(hex: "FFC2EA").opacity(0.5)
        }
    }

    var glowColor: Color {
        switch self {
        case .glossBlack:
            return Color.white.opacity(0.14)
        case .iceBlue:
            return Color(hex: "7CD9FF").opacity(0.2)
        case .glossPink:
            return Color(hex: "FF8FD8").opacity(0.2)
        }
    }

    var iconTint: Color {
        switch self {
        case .glossBlack:
            return Color.white
        case .iceBlue:
            return Color(hex: "D2F6FF")
        case .glossPink:
            return Color(hex: "FFE3F5")
        }
    }
}

struct VIPPlan: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let months: Int
    let meowCoins: Int
    let badgeText: String?
}

struct VIPBenefit: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let preferredGlassStyle: VIPGlassStyle?
    let isWide: Bool

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        preferredGlassStyle: VIPGlassStyle? = nil,
        isWide: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.preferredGlassStyle = preferredGlassStyle
        self.isWide = isWide
    }
}

struct VIPGlassCardBackground: View {
    let glassStyle: VIPGlassStyle
    var cornerRadius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: glassStyle.fillColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(glassStyle.strokeColor, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 4)
            }
            .shadow(color: glassStyle.glowColor, radius: 18, x: 0, y: 8)
    }
}
