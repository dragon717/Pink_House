import SwiftUI

enum WardrobeThemeSkinSupport {
    static let supportedNamespaces: Set<String> = ["girl_closet", "sky_concert", "swan_dream"]

    static func isThemeSkinDescriptor(_ descriptor: ThemeSkinDescriptor?) -> Bool {
        guard let namespace = descriptor?.assetNamespace else { return false }
        return supportedNamespaces.contains(namespace)
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
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor)
    }

    private var descriptorTitle: String {
        SkyConcertThemeSkin.title(for: descriptor)
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
                Text(descriptorTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.4)
            }
            .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statsHeaderBackground)

            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            ThemeSkinOptionalResizableAsset(
                ThemeSkinAssetName.cardStatsDefault,
                namespace: descriptor?.assetNamespace,
                allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor),
                capInsets: ThemeSkinAssetName.capInsets(for: ThemeSkinAssetName.cardStatsDefault)
            ) {
                shellBackground(cornerRadius: 24, descriptor: descriptor)
            }
        }
        .overlay {
            if !ThemeSkinAssetAvailability.hasImage(
                named: ThemeSkinAssetName.cardStatsDefault,
                namespace: descriptor?.assetNamespace,
                allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
            ) {
                shellOutline(cornerRadius: 24, descriptor: descriptor)
            }
        }
        .overlay {
            if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.statsCardPlacements)
            } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                SkyConcertDecorationLayer(
                    placements: SwanDreamThemeSkin.statsCardPlacements,
                    namespace: SwanDreamThemeSkin.namespace
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            if !SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor),
               !ThemeSkinAssetAvailability.hasImage(named: ThemeSkinAssetName.cardStatsDefault) {
                WardrobeThemeDoodle(icon: "star.fill")
                    .offset(x: 10, y: -10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor),
               !ThemeSkinAssetAvailability.hasImage(named: ThemeSkinAssetName.cardStatsDefault) {
                WardrobeThemeDoodle(icon: "sparkles", tint: WardrobeGirlClosetTokens.accent)
                    .offset(x: -6, y: 8)
            }
        }
        .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor), radius: 12, x: 0, y: 6)
    }

    private var statsHeaderBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(0.96)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.95), lineWidth: 1)
            )
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
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor)
    }

    var body: some View {
        Group {
            if isGirlClosetEnabled {
                content
                    .background {
                        ThemeSkinOptionalResizableAsset(
                            ThemeSkinAssetName.cardWardrobeItem,
                            namespace: descriptor?.assetNamespace,
                            allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor),
                            capInsets: ThemeSkinAssetName.capInsets(for: ThemeSkinAssetName.cardWardrobeItem)
                        ) {
                            shellBackground(cornerRadius: 22, descriptor: descriptor)
                        }
                    }
                    .overlay {
                        if !ThemeSkinAssetAvailability.hasImage(
                            named: ThemeSkinAssetName.cardWardrobeItem,
                            namespace: descriptor?.assetNamespace,
                            allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
                        ) {
                            shellOutline(cornerRadius: 22, descriptor: descriptor)
                        }
                    }
                    .overlay {
                        if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                            SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.wardrobeCardPlacements)
                        } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                            SkyConcertDecorationLayer(
                                placements: SwanDreamThemeSkin.wardrobeCardPlacements,
                                namespace: SwanDreamThemeSkin.namespace
                            )
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if !SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) {
                            ThemeSkinOptionalFittedAsset(
                                ThemeSkinAssetName.cardWardrobeRibbonTopLeft,
                                namespace: descriptor?.assetNamespace
                            ) {
                                WardrobeThemeDoodle(icon: "star.fill")
                            }
                            .frame(width: 58, height: 40)
                            .padding(.top, 10)
                            .padding(.leading, 8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.65), radius: 10, x: 0, y: 5)
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
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor)
    }

    var body: some View {
        Group {
            if isGirlClosetEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SkyConcertThemeSkin.accent(for: descriptor))

                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor))
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
                                    SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.9), lineWidth: 1)
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
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor)
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
                        .fill(SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.95) : Color.white.opacity(0.95))
                )
                .overlay(
                    Capsule()
                        .stroke((SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellStroke(for: descriptor) : tint).opacity(0.45), lineWidth: 1)
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

private func shellBackground(cornerRadius: CGFloat, descriptor: ThemeSkinDescriptor?) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    SkyConcertThemeSkin.shellFillTop(for: descriptor),
                    SkyConcertThemeSkin.shellFillBottom(for: descriptor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
}

private func shellOutline(cornerRadius: CGFloat, descriptor: ThemeSkinDescriptor?) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [
                    WardrobeGirlClosetTokens.shellStrokeSoft,
                    SkyConcertThemeSkin.shellStroke(for: descriptor),
                    SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1.4
        )
        .padding(0.5)
}
