import SwiftUI

enum WardrobeThemeSkinSupport {
    static let girlClosetNamespace = "girl_closet"

    static func isGirlClosetDescriptor(_ descriptor: ThemeSkinDescriptor?) -> Bool {
        descriptor?.assetNamespace == girlClosetNamespace
    }
}

private enum WardrobeGirlClosetTokens {
    static let shellFillTop = Color(hex: "FFFDF8")
    static let shellFillBottom = Color(hex: "FCEEF3")
    static let shellStroke = Color(hex: "E7C7D3")
    static let shellStrokeSoft = Color.white.opacity(0.92)
    static let accent = Color(hex: "D793AA")
    static let accentSoft = Color(hex: "F4D5DF")
    static let label = Color(hex: "8A5C6F")
    static let chocolate = Color(hex: "7A5A54")
    static let lavender = Color(hex: "9E86B8")
    static let shadow = Color(hex: "DFAEBF").opacity(0.28)
}

struct WardrobeThemeStatsCardContainer<Content: View>: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    private let content: Content
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(for: .statsCard)
    }

    private var isGirlClosetEnabled: Bool {
        WardrobeThemeSkinSupport.isGirlClosetDescriptor(descriptor)
    }

    var body: some View {
        Group {
            if isGirlClosetEnabled {
                themedContent
            } else {
                defaultContent
            }
        }
    }

    private var defaultContent: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                CardBackgroundView(cornerRadius: cornerRadius)
            }
    }

    private var themedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("少女衣橱")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.4)
            }
            .foregroundStyle(WardrobeGirlClosetTokens.label)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                WardrobeGirlClosetTokens.accentSoft.opacity(0.96)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(WardrobeGirlClosetTokens.shellStroke.opacity(0.95), lineWidth: 1)
            )

            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(shellBackground(cornerRadius: 24))
        .overlay(shellOutline(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            WardrobeThemeDoodle(icon: "star.fill")
                .offset(x: 10, y: -10)
        }
        .overlay(alignment: .bottomLeading) {
            WardrobeThemeDoodle(icon: "sparkles", tint: WardrobeGirlClosetTokens.accent)
                .offset(x: -6, y: 8)
        }
        .shadow(color: WardrobeGirlClosetTokens.shadow, radius: 12, x: 0, y: 6)
    }
}

struct WardrobeThemeClothingCardContainer<Content: View>: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    private let content: Content
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(for: .wardrobeItemCard)
    }

    private var isGirlClosetEnabled: Bool {
        WardrobeThemeSkinSupport.isGirlClosetDescriptor(descriptor)
    }

    var body: some View {
        Group {
            if isGirlClosetEnabled {
                content
                    .background(shellBackground(cornerRadius: 22))
                    .overlay(shellOutline(cornerRadius: 22))
                    .overlay(alignment: .topLeading) {
                        WardrobeThemeDoodle(icon: "star.fill")
                            .padding(.top, 10)
                            .padding(.leading, 8)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        WardrobeThemeDoodle(icon: "sparkles", tint: WardrobeGirlClosetTokens.accent)
                            .padding(.bottom, 10)
                            .padding(.trailing, 8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: WardrobeGirlClosetTokens.shadow.opacity(0.65), radius: 10, x: 0, y: 5)
            } else {
                content
                    .background {
                        CardBackgroundView(cornerRadius: cornerRadius)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}

struct WardrobeThemeCardTitle: View {
    let title: String

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(for: .wardrobeItemCard)
    }

    private var isGirlClosetEnabled: Bool {
        WardrobeThemeSkinSupport.isGirlClosetDescriptor(descriptor)
    }

    var body: some View {
        Group {
            if isGirlClosetEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WardrobeGirlClosetTokens.accent)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(WardrobeGirlClosetTokens.label)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    WardrobeGirlClosetTokens.accentSoft.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WardrobeGirlClosetTokens.shellStroke.opacity(0.9), lineWidth: 1)
                )
            } else {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WardrobeThemeCornerBadge: View {
    let text: String
    let tint: Color
    var icon: String? = nil

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(for: .wardrobeItemCard)
    }

    private var isGirlClosetEnabled: Bool {
        WardrobeThemeSkinSupport.isGirlClosetDescriptor(descriptor)
    }

    var body: some View {
        Group {
            if isGirlClosetEnabled {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 8, weight: .bold))
                    }

                    Text(text)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                )
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.16), radius: 6, x: 0, y: 2)
            } else {
                Text(text)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.88))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

private struct WardrobeThemeDoodle: View {
    let icon: String
    var tint: Color = WardrobeGirlClosetTokens.accent

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(6)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.95))
            )
            .overlay(
                Circle()
                    .stroke(WardrobeGirlClosetTokens.shellStroke.opacity(0.95), lineWidth: 1)
            )
    }
}

private func shellBackground(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    WardrobeGirlClosetTokens.shellFillTop,
                    WardrobeGirlClosetTokens.shellFillBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
}

private func shellOutline(cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [
                    WardrobeGirlClosetTokens.shellStrokeSoft,
                    WardrobeGirlClosetTokens.shellStroke,
                    WardrobeGirlClosetTokens.shellStroke.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1.4
        )
        .padding(0.5)
}
