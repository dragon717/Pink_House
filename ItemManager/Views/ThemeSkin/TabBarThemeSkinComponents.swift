import SwiftUI

enum ThemeSkinTabRole {
    case wardrobe
    case house
    case me
    case petChat
}

private enum TabBarThemeSkinTokens {
    static let supportedNamespaces: Set<String> = ["sky_concert", "swan_dream"]

    static let creamTop = Color(red: 1.0, green: 0.981, blue: 0.965)
    static let creamBottom = Color(red: 0.989, green: 0.934, blue: 0.955)
    static let pinkBorder = Color(red: 0.91, green: 0.75, blue: 0.81)
    static let pinkAccent = Color(red: 0.84, green: 0.56, blue: 0.68)
    static let roseText = Color(red: 0.54, green: 0.34, blue: 0.42)
    static let shadow = Color(red: 0.84, green: 0.62, blue: 0.72).opacity(0.22)

    static func creamTop(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellFillTop(for: descriptor) : creamTop
    }

    static func creamBottom(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellFillBottom(for: descriptor) : creamBottom
    }

    static func border(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellStroke(for: descriptor) : pinkBorder
    }

    static func accent(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.accent(for: descriptor) : pinkAccent
    }

    static func accent(for descriptor: ThemeSkinDescriptor?, colorScheme: ColorScheme) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme) : pinkAccent
    }

    static func text(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.labelColor(for: descriptor) : roseText
    }

    static func text(for descriptor: ThemeSkinDescriptor?, colorScheme: ColorScheme) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme) : roseText
    }

    static func shadow(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shadowColor(for: descriptor) : shadow
    }

    /// Bottom-tab stickers must use the complete, namespace-prefixed sticker exports.
    /// Avoid the older short `decor_*` crops here: several of those are edge fragments.
    static func fullStickerAssetName(for role: ThemeSkinTabRole?, descriptor: ThemeSkinDescriptor?) -> String? {
        guard let role else { return nil }

        switch descriptor?.assetNamespace {
        case SkyConcertThemeSkin.namespace:
            switch role {
            case .wardrobe:
                return SkyConcertThemeSkin.decorMusicScrollClouds
            case .house:
                return SkyConcertThemeSkin.decorSkyBalloonDoves
            case .me:
                return SkyConcertThemeSkin.decorWingedUnicornPrince
            case .petChat:
                return SkyConcertThemeSkin.decorBunnyAccordionStage
            }
        case SwanDreamThemeSkin.namespace:
            switch role {
            case .wardrobe:
                return SwanDreamThemeSkin.decorMoonBowBottle
            case .house:
                return SwanDreamThemeSkin.decorDreamCastleClouds
            case .me:
                return SwanDreamThemeSkin.decorCrownedSwanClouds
            case .petChat:
                return SwanDreamThemeSkin.decorFlyingSwanStars
            }
        default:
            return nil
        }
    }
}

private extension ThemeSkinDescriptor {
    var usesThemeSkinTabBarChrome: Bool {
        TabBarThemeSkinTokens.supportedNamespaces.contains(assetNamespace)
    }
}

struct ThemeSkinTabBarBackdrop: View {
    let descriptor: ThemeSkinDescriptor?
    let safeAreaBottom: CGFloat
    var horizontalPadding: CGFloat = 12
    var bottomPadding: CGFloat? = nil

    private var isActive: Bool {
        descriptor?.usesThemeSkinTabBarChrome == true
    }

    private var shapeStyle: ThemeSkinTabBarShapeStyle {
        ThemeSkinTabBarShapeStyle.style(for: descriptor)
    }

    private var backdropHeight: CGFloat {
        shapeStyle.height + safeAreaBottom
    }

    private var resolvedHorizontalPadding: CGFloat {
        horizontalPadding == 12 ? shapeStyle.horizontalPadding : horizontalPadding
    }

    var body: some View {
        if isActive {
            ThemeSkinOptionalResizableAsset(
                ThemeSkinAssetName.tabBarMain,
                namespace: descriptor?.assetNamespace,
                allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor),
                capInsets: ThemeSkinAssetName.capInsets(for: ThemeSkinAssetName.tabBarMain)
            ) {
                fallbackBackdrop
            }
            .clipShape(shapeStyle)
            .compositingGroup()
            .shadow(color: TabBarThemeSkinTokens.shadow(for: descriptor), radius: 14, x: 0, y: 6)
            .overlay {
                tabBarDecorations
            }
            .frame(height: backdropHeight)
            .padding(.horizontal, resolvedHorizontalPadding)
            .padding(.bottom, bottomPadding ?? (safeAreaBottom > 0 ? 2 : 8))
        }
    }

    private var fallbackBackdrop: some View {
        ZStack {
            shapeStyle
                .fill(
                    LinearGradient(
                        colors: shellGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    shapeStyle
                        .stroke(
                            LinearGradient(
                                colors: shellStrokeColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.55
                        )
                }
                .overlay {
                    shapeStyle
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
                        .padding(4)
                }

            HStack {
                tabBarSticker(role: .tabBarLeading, fallbackSystemName: "star.fill")
                Spacer()
                tabBarSticker(role: .tabBarTrailing, fallbackSystemName: "sparkles")
            }
            .padding(.horizontal, SwanDreamThemeSkin.isSwanDream(descriptor) ? 20 : 18)
        }
    }

    @ViewBuilder
    private var tabBarDecorations: some View {
        if SkyConcertThemeSkin.isSkyConcert(descriptor) {
            SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.tabBarPlacements)
        } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
            ZStack {
                SkyConcertDecorationLayer(
                    placements: SwanDreamThemeSkin.tabBarPlacements,
                    namespace: SwanDreamThemeSkin.namespace
                )
                swanDreamMoonDecoration
            }
        }
    }

    private var swanDreamMoonDecoration: some View {
        ThemeSkinOptionalFittedAsset(
            SwanDreamThemeSkin.decorCrescentPlanetSparkle,
            namespace: SwanDreamThemeSkin.namespace,
            allowShortNameFallback: false
        ) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(SwanDreamThemeSkin.moonGold.opacity(0.72))
        }
        .frame(width: 72, height: 72)
        .offset(y: -30)
        .opacity(0.68)
        .allowsHitTesting(false)
    }

    private var shellGradientColors: [Color] {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return [
                SwanDreamThemeSkin.creamTop.opacity(0.98),
                SwanDreamThemeSkin.ribbonPink.opacity(0.72),
                SwanDreamThemeSkin.moonLavender.opacity(0.9)
            ]
        }
        return [
            TabBarThemeSkinTokens.creamTop(for: descriptor).opacity(0.98),
            TabBarThemeSkinTokens.creamBottom(for: descriptor).opacity(0.96)
        ]
    }

    private var shellStrokeColors: [Color] {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return [
                .white.opacity(0.98),
                SwanDreamThemeSkin.roseLine.opacity(0.82),
                SwanDreamThemeSkin.moonGold.opacity(0.5)
            ]
        }
        return [
            .white.opacity(0.98),
            TabBarThemeSkinTokens.border(for: descriptor).opacity(0.9)
        ]
    }

    private func tabBarSticker(role: ThemeSkinEdgeStickerRole, fallbackSystemName: String) -> some View {
        ThemeSkinEdgeSticker(
            descriptor: descriptor,
            assetName: ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: role),
            size: SwanDreamThemeSkin.isSwanDream(descriptor) ? 30 : 32,
            opacity: 0.34,
            offset: .zero,
            fallbackSystemName: fallbackSystemName
        )
    }
}

struct ThemeSkinModernTabLabel: View {
    let descriptor: ThemeSkinDescriptor?
    let title: String
    let systemImage: String
    let isSelected: Bool
    var tabRole: ThemeSkinTabRole? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var isActive: Bool {
        descriptor?.usesThemeSkinTabBarChrome == true
    }

    var body: some View {
        if isActive {
            VStack(spacing: 2) {
                ThemeSkinTabStickerIcon(
                    descriptor: descriptor,
                    tabRole: tabRole,
                    systemImage: systemImage,
                    fallbackPointSize: 18
                )
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? TabBarThemeSkinTokens.accent(for: descriptor, colorScheme: colorScheme)
                            : TabBarThemeSkinTokens.text(for: descriptor, colorScheme: colorScheme).opacity(0.88)
                    )
                    .themeSkinLegibleText(level: isSelected ? .chip : .inline, slot: .tabBarMain, descriptor: descriptor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

struct ThemeSkinLegacyTabLabel: View {
    let descriptor: ThemeSkinDescriptor?
    let title: String
    let systemImage: String
    let isSelected: Bool
    let selectedColor: Color
    let inactiveColor: Color
    var tabRole: ThemeSkinTabRole? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var isActive: Bool {
        descriptor?.usesThemeSkinTabBarChrome == true
    }

    var body: some View {
        if isActive {
            VStack(spacing: 2) {
                ThemeSkinTabStickerIcon(
                    descriptor: descriptor,
                    tabRole: tabRole,
                    systemImage: systemImage,
                    fallbackPointSize: 20
                )
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? TabBarThemeSkinTokens.accent(for: descriptor, colorScheme: colorScheme)
                            : TabBarThemeSkinTokens.text(for: descriptor, colorScheme: colorScheme).opacity(0.88)
                    )
                    .themeSkinLegibleText(level: isSelected ? .chip : .inline, slot: .tabBarMain, descriptor: descriptor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? selectedColor : inactiveColor)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? selectedColor : inactiveColor)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ThemeSkinTabStickerIcon: View {
    let descriptor: ThemeSkinDescriptor?
    let tabRole: ThemeSkinTabRole?
    let systemImage: String
    let fallbackPointSize: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var stickerAssetName: String? {
        TabBarThemeSkinTokens.fullStickerAssetName(for: tabRole, descriptor: descriptor)
    }

    var body: some View {
        if let stickerAssetName {
            ThemeSkinOptionalFittedAsset(
                stickerAssetName,
                namespace: descriptor?.assetNamespace,
                allowShortNameFallback: false
            ) {
                fallbackIcon
            }
            .frame(width: 34, height: 30)
            .accessibilityHidden(true)
        } else {
            fallbackIcon
                .frame(width: 34, height: 30)
                .accessibilityHidden(true)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: fallbackPointSize, weight: .medium))
            .foregroundStyle(TabBarThemeSkinTokens.text(for: descriptor, colorScheme: colorScheme).opacity(0.88))
    }
}
