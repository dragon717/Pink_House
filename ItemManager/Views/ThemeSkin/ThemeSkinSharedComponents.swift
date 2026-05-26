import Foundation
import SwiftUI

/// Shared theme-skin surfaces used by detail pages, settings cards, journals and book/page lists.
/// These components intentionally do not introduce new required assets: they reuse the active
/// theme namespace, existing sticker PNGs, and programmatic SwiftUI fallback chrome.

private enum ThemeSkinSharedSurfaceTokens {
    static let supportedNamespaces: Set<String> = ["sky_concert", "swan_dream"]

    static func isSupported(_ descriptor: ThemeSkinDescriptor?) -> Bool {
        guard let namespace = descriptor?.assetNamespace else { return false }
        return supportedNamespaces.contains(namespace)
    }

    static func primaryOrnamentAssetName(for descriptor: ThemeSkinDescriptor?, style: ThemeSkinOrnateFrameStyle) -> String {
        switch style {
        case .compact, .scrollOptimized:
            return ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .scrollPrimary)
        case .standard:
            return ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .cardCornerTopTrailing)
        case .hero:
            return ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .heroPrimary)
        }
    }

    static func secondaryOrnamentAssetName(for descriptor: ThemeSkinDescriptor?, style: ThemeSkinOrnateFrameStyle) -> String {
        switch style {
        case .compact, .scrollOptimized:
            return ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .scrollSecondary)
        case .standard:
            return ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .cardCornerBottomLeading)
        case .hero:
            return ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .heroSecondary)
        }
    }
}

enum ThemeSkinLegibilityLevel: Equatable {
    case inline
    case chip
    case badge
    case preview
    case hero

    var backdropOutset: CGFloat {
        switch self {
        case .inline:
            return 0
        case .chip:
            return 4
        case .badge:
            return 5
        case .preview:
            return 8
        case .hero:
            return 12
        }
    }
}

private enum ThemeSkinDarkLegibilityFeature {
    static let key = "THEMESKIN_DARK_LEGIBILITY_V2"
    static let disabledKey = "THEMESKIN_DARK_LEGIBILITY_V2_DISABLED"

    static var isEnabled: Bool {
        if UserDefaults.standard.bool(forKey: disabledKey) {
            return false
        }

        if let explicitValue = UserDefaults.standard.object(forKey: key) as? Bool {
            return explicitValue
        }

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(disabledKey) || arguments.contains("-\(disabledKey)") {
            return false
        }
        if arguments.contains(key) || arguments.contains("-\(key)") {
            return true
        }
        #endif

        return true
    }
}

struct ThemeSkinLegibilityPalette {
    let backdropBase: Color
    let backdropSoft: Color
    let backdropAccent: Color
    let backdropStroke: Color

    static func resolve(
        for descriptor: ThemeSkinDescriptor?,
        colorScheme: ColorScheme
    ) -> ThemeSkinLegibilityPalette? {
        guard ThemeSkinSharedSurfaceTokens.isSupported(descriptor) else {
            return nil
        }

        let isDark = colorScheme == .dark
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return ThemeSkinLegibilityPalette(
                backdropBase: SwanDreamThemeSkin.textToken.resolved(for: colorScheme).opacity(isDark ? 0.16 : 0.04),
                backdropSoft: SwanDreamThemeSkin.moonCreamToken.resolved(for: colorScheme).opacity(isDark ? 0.36 : 0.12),
                backdropAccent: SwanDreamThemeSkin.ribbonPink.opacity(isDark ? 0.32 : 0.10),
                backdropStroke: SwanDreamThemeSkin.moonGoldToken.resolved(for: colorScheme).opacity(isDark ? 0.42 : 0.16)
            )
        }

        if SkyConcertThemeSkin.isSkyConcert(descriptor) {
            return ThemeSkinLegibilityPalette(
                backdropBase: SkyConcertThemeSkin.textToken.resolved(for: colorScheme).opacity(isDark ? 0.16 : 0.04),
                backdropSoft: SkyConcertThemeSkin.creamTopToken.resolved(for: colorScheme).opacity(isDark ? 0.36 : 0.12),
                backdropAccent: SkyConcertThemeSkin.cloudBlue.opacity(isDark ? 0.34 : 0.10),
                backdropStroke: SkyConcertThemeSkin.softGoldToken.resolved(for: colorScheme).opacity(isDark ? 0.38 : 0.14)
            )
        }

        return nil
    }
}

enum ThemeSkinEdgeStickerRole {
    case cardPrimary
    case cardSecondary
    case cardCornerTopLeading
    case cardCornerTopTrailing
    case cardCornerBottomLeading
    case cardCornerBottomTrailing
    case cardCenterEmblem
    case heroPrimary
    case heroSecondary
    case scrollPrimary
    case scrollSecondary
    case tabBarLeading
    case tabBarTrailing
    case titleLeading
    case iconCorner
}

enum ThemeSkinEdgeStickerAssets {
    static func assetName(for descriptor: ThemeSkinDescriptor?, role: ThemeSkinEdgeStickerRole) -> String {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            switch role {
            case .cardPrimary, .cardCornerTopTrailing, .titleLeading:
                return SwanDreamThemeSkin.decorCrownedSwanClouds
            case .cardSecondary, .cardCornerBottomLeading, .scrollSecondary:
                return SwanDreamThemeSkin.decorCrystalStars
            case .cardCornerTopLeading:
                return SwanDreamThemeSkin.decorMoonBowBottle
            case .cardCornerBottomTrailing:
                return SwanDreamThemeSkin.decorDreamCastleClouds
            case .cardCenterEmblem:
                return SwanDreamThemeSkin.decorCrescentPlanetSparkle
            case .heroPrimary:
                return SwanDreamThemeSkin.decorRibbonSwanClouds
            case .heroSecondary, .tabBarLeading:
                return SwanDreamThemeSkin.decorCrownedSwanClouds
            case .scrollPrimary, .iconCorner:
                return SwanDreamThemeSkin.decorMoonBowBottle
            case .tabBarTrailing:
                return SwanDreamThemeSkin.decorCrescentPlanetSparkle
            }
        }

        switch role {
        case .cardPrimary, .cardCornerTopTrailing, .scrollSecondary:
            return SkyConcertThemeSkin.decorMusicScrollClouds
        case .cardSecondary, .cardCornerBottomLeading, .scrollPrimary, .titleLeading:
            return SkyConcertThemeSkin.decorViolinCloud
        case .cardCornerTopLeading:
            return SkyConcertThemeSkin.decorPastelPlanets
        case .cardCornerBottomTrailing:
            return SkyConcertThemeSkin.decorShootingStar
        case .cardCenterEmblem:
            return SkyConcertThemeSkin.decorWhaleCloudStars
        case .heroPrimary:
            return SkyConcertThemeSkin.decorBunnyAccordionStage
        case .heroSecondary:
            return SkyConcertThemeSkin.decorWingedUnicornPrince
        case .tabBarLeading:
            return SkyConcertThemeSkin.decorSkyBalloonDoves
        case .tabBarTrailing:
            return SkyConcertThemeSkin.decorCrescentRainCloud
        case .iconCorner:
            return SkyConcertThemeSkin.decorMusicScrollClouds
        }
    }
}

enum ThemeSkinOrnateFrameStyle: Equatable {
    case compact
    case standard
    case hero
    case scrollOptimized

    var lineWidth: CGFloat {
        switch self {
        case .compact, .scrollOptimized:
            return 1.35
        case .standard:
            return 1.75
        case .hero:
            return 2.1
        }
    }

    var innerLineWidth: CGFloat {
        switch self {
        case .compact, .scrollOptimized:
            return 0.65
        case .standard:
            return 0.85
        case .hero:
            return 1
        }
    }

    var innerInset: CGFloat {
        switch self {
        case .compact, .scrollOptimized:
            return 3
        case .standard:
            return 4.5
        case .hero:
            return 6
        }
    }

    var primaryStickerSize: CGFloat {
        switch self {
        case .compact:
            return 30
        case .standard:
            return 46
        case .hero:
            return 72
        case .scrollOptimized:
            return 0
        }
    }

    var secondaryStickerSize: CGFloat {
        switch self {
        case .compact:
            return 22
        case .standard:
            return 30
        case .hero:
            return 46
        case .scrollOptimized:
            return 0
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .compact:
            return 7
        case .standard:
            return 13
        case .hero:
            return 20
        case .scrollOptimized:
            return 2
        }
    }

    var shadowYOffset: CGFloat {
        switch self {
        case .compact:
            return 3
        case .standard:
            return 7
        case .hero:
            return 10
        case .scrollOptimized:
            return 1
        }
    }

    var primaryStickerOffset: CGSize {
        switch self {
        case .compact:
            return CGSize(width: 9, height: -9)
        case .standard:
            return CGSize(width: 16, height: -18)
        case .hero:
            return CGSize(width: 28, height: -28)
        case .scrollOptimized:
            return .zero
        }
    }

    var secondaryStickerOffset: CGSize {
        switch self {
        case .compact:
            return CGSize(width: -8, height: 8)
        case .standard:
            return CGSize(width: -10, height: 13)
        case .hero:
            return CGSize(width: -18, height: 18)
        case .scrollOptimized:
            return .zero
        }
    }
}

struct ThemeSkinOrnateFrameSurface: View {
    let descriptor: ThemeSkinDescriptor?
    let cornerRadius: CGFloat
    let style: ThemeSkinOrnateFrameStyle
    let showsDecoration: Bool

    init(
        descriptor: ThemeSkinDescriptor?,
        cornerRadius: CGFloat,
        style: ThemeSkinOrnateFrameStyle = .standard,
        showsDecoration: Bool = true
    ) {
        self.descriptor = descriptor
        self.cornerRadius = cornerRadius
        self.style = style
        self.showsDecoration = showsDecoration
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            baseFill
            ornateBorder
            innerHighlight

            if showsDecoration {
                if style == .scrollOptimized {
                    scrollOptimizedCornerMarks
                } else {
                    stickerDecorations
                }
            }
        }
        .shadow(
            color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(style == .scrollOptimized ? 0.2 : 0.58),
            radius: style.shadowRadius,
            x: 0,
            y: style.shadowYOffset
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var baseFill: some View {
        shape
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }


    private var ornateBorder: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.96),
                        SkyConcertThemeSkin.accent(for: descriptor).opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: style.lineWidth
            )
    }

    private var innerHighlight: some View {
        RoundedRectangle(cornerRadius: max(cornerRadius - style.innerInset, 4), style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.68),
                        SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(0.32),
                        SkyConcertThemeSkin.accent(for: descriptor).opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: style.innerLineWidth
            )
            .padding(style.innerInset)
    }

    private var stickerDecorations: some View {
        ZStack {
            ThemeSkinCornerSticker(
                descriptor: descriptor,
                assetName: ThemeSkinSharedSurfaceTokens.primaryOrnamentAssetName(for: descriptor, style: style),
                size: style.primaryStickerSize,
                opacity: SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.72 : 0.7,
                offset: style.primaryStickerOffset
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            ThemeSkinCornerSticker(
                descriptor: descriptor,
                assetName: ThemeSkinSharedSurfaceTokens.secondaryOrnamentAssetName(for: descriptor, style: style),
                size: style.secondaryStickerSize,
                opacity: SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.54 : 0.5,
                offset: style.secondaryStickerOffset
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            edgePearls
        }
    }

    private var scrollOptimizedCornerMarks: some View {
        ZStack {
            ThemeSkinEdgeSticker(
                descriptor: descriptor,
                assetName: ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .scrollPrimary),
                size: 24,
                opacity: 0.64,
                offset: CGSize(width: 7, height: -7),
                fallbackSystemName: SwanDreamThemeSkin.isSwanDream(descriptor) ? "moon.stars.fill" : "music.note"
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            ThemeSkinEdgeSticker(
                descriptor: descriptor,
                assetName: ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .scrollSecondary),
                size: 20,
                opacity: 0.52,
                offset: CGSize(width: -5, height: 5),
                fallbackSystemName: "sparkles"
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private var edgePearls: some View {
        ZStack {
            ornatePearl(size: style == .hero ? 9 : 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: style == .hero ? -4 : -2, y: style == .hero ? 18 : 12)

            ornatePearl(size: style == .hero ? 7 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: style == .hero ? 5 : 3, y: style == .hero ? -18 : -12)
        }
    }

    private func ornatePearl(size: CGFloat) -> some View {
        Circle()
            .fill(SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.96))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(SkyConcertThemeSkin.accent(for: descriptor).opacity(0.62), lineWidth: 1)
            }
    }

    private var gradientColors: [Color] {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return [
                SwanDreamThemeSkin.creamTop.opacity(0.99),
                SwanDreamThemeSkin.ribbonPink.opacity(style == .scrollOptimized ? 0.58 : 0.74),
                SwanDreamThemeSkin.moonLavender.opacity(0.96)
            ]
        }

        return [
            SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.99),
            SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(style == .scrollOptimized ? 0.46 : 0.68),
            SkyConcertThemeSkin.shellFillBottom(for: descriptor).opacity(0.96)
        ]
    }
}

struct ThemeSkinOrnateFrameBorder: View {
    let descriptor: ThemeSkinDescriptor?
    let cornerRadius: CGFloat
    let style: ThemeSkinOrnateFrameStyle
    let showsDecoration: Bool

    init(
        descriptor: ThemeSkinDescriptor?,
        cornerRadius: CGFloat,
        style: ThemeSkinOrnateFrameStyle = .standard,
        showsDecoration: Bool = true
    ) {
        self.descriptor = descriptor
        self.cornerRadius = cornerRadius
        self.style = style
        self.showsDecoration = showsDecoration
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.96),
                            SkyConcertThemeSkin.accent(for: descriptor).opacity(0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: style.lineWidth
                )

            RoundedRectangle(cornerRadius: max(cornerRadius - style.innerInset, 4), style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: style.innerLineWidth)
                .padding(style.innerInset)

            if showsDecoration && style != .scrollOptimized {
                ThemeSkinCornerSticker(
                    descriptor: descriptor,
                    assetName: ThemeSkinSharedSurfaceTokens.primaryOrnamentAssetName(for: descriptor, style: style),
                    size: style.primaryStickerSize,
                    opacity: 0.62,
                    offset: style.primaryStickerOffset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ThemeSkinSectionCardContainer<Content: View>: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    let slot: ThemeSkinSlot
    let cornerRadius: CGFloat
    let showsDecoration: Bool
    let content: Content

    init(
        slot: ThemeSkinSlot = .sectionCard,
        cornerRadius: CGFloat = 18,
        showsDecoration: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.slot = slot
        self.cornerRadius = cornerRadius
        self.showsDecoration = showsDecoration
        self.content = content()
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: slot, state: .default)
    }

    private var isThemed: Bool {
        ThemeSkinSharedSurfaceTokens.isSupported(descriptor)
    }

    var body: some View {
        if isThemed {
            content
                .background {
                    ThemeSkinOrnateFrameSurface(
                        descriptor: descriptor,
                        cornerRadius: cornerRadius,
                        style: ornateStyle,
                        showsDecoration: showsDecoration
                    )
                }
        } else {
            content
                .background {
                    CardBackgroundView(cornerRadius: cornerRadius)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }

    private var ornateStyle: ThemeSkinOrnateFrameStyle {
        cornerRadius >= 26 ? .hero : .standard
    }
}

struct ThemeSkinAdaptiveSectionCardContainer<Content: View, FallbackBackground: View>: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    let slot: ThemeSkinSlot
    let cornerRadius: CGFloat
    let showsDecoration: Bool
    let fallbackBackground: FallbackBackground
    let content: Content

    init(
        slot: ThemeSkinSlot = .sectionCard,
        cornerRadius: CGFloat = 18,
        showsDecoration: Bool = true,
        @ViewBuilder fallbackBackground: () -> FallbackBackground,
        @ViewBuilder content: () -> Content
    ) {
        self.slot = slot
        self.cornerRadius = cornerRadius
        self.showsDecoration = showsDecoration
        self.fallbackBackground = fallbackBackground()
        self.content = content()
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: slot, state: .default)
    }

    private var isThemed: Bool {
        ThemeSkinSharedSurfaceTokens.isSupported(descriptor)
    }

    var body: some View {
        if isThemed {
            content
                .background {
                    ThemeSkinOrnateFrameSurface(
                        descriptor: descriptor,
                        cornerRadius: cornerRadius,
                        style: ornateStyle,
                        showsDecoration: showsDecoration
                    )
                }
        } else {
            content
                .background(fallbackBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var ornateStyle: ThemeSkinOrnateFrameStyle {
        cornerRadius >= 26 ? .hero : (showsDecoration ? .standard : .compact)
    }
}

struct ThemeSkinEdgeSticker: View {
    let descriptor: ThemeSkinDescriptor?
    let assetName: String
    let size: CGFloat
    let opacity: Double
    let offset: CGSize
    var fallbackSystemName: String = "sparkles"

    var body: some View {
        ThemeSkinOptionalFittedAsset(
            assetName,
            namespace: descriptor?.assetNamespace,
            allowShortNameFallback: false
        ) {
            Image(systemName: fallbackSystemName)
                .font(.system(size: max(12, size * 0.42), weight: .bold))
                .foregroundStyle(SkyConcertThemeSkin.accent(for: descriptor))
        }
        .frame(width: size, height: size)
        .opacity(opacity)
        .offset(offset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private typealias ThemeSkinCornerSticker = ThemeSkinEdgeSticker

private struct ThemeSkinLegibleTextModifier: ViewModifier {
    let level: ThemeSkinLegibilityLevel
    let slot: ThemeSkinSlot
    let descriptor: ThemeSkinDescriptor?

    func body(content: Content) -> some View {
        content
    }
}

private struct ThemeSkinLegibilityBackdropModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    let level: ThemeSkinLegibilityLevel
    let slot: ThemeSkinSlot
    let cornerRadius: CGFloat
    let descriptor: ThemeSkinDescriptor?

    private var resolvedDescriptor: ThemeSkinDescriptor? {
        descriptor ?? themeSkinManager.activeThemeDescriptor(for: slot, state: .default)
    }

    private var palette: ThemeSkinLegibilityPalette? {
        ThemeSkinLegibilityPalette.resolve(for: resolvedDescriptor, colorScheme: colorScheme)
    }

    private var shouldApply: Bool {
        colorScheme == .dark
            && ThemeSkinDarkLegibilityFeature.isEnabled
            && palette != nil
            && level != .inline
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if shouldApply, let palette {
            content
                .background {
                    ThemeSkinLegibilityBackdrop(
                        level: level,
                        palette: palette,
                        cornerRadius: cornerRadius
                    )
                }
        } else {
            content
        }
    }
}

private struct ThemeSkinLegibilityBackdrop: View {
    let level: ThemeSkinLegibilityLevel
    let palette: ThemeSkinLegibilityPalette
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            palette.backdropBase,
                            palette.backdropSoft,
                            palette.backdropAccent
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(-max(2, level.backdropOutset * 0.45))

            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            palette.backdropSoft,
                            palette.backdropStroke
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .padding(-max(2, level.backdropOutset * 0.45))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ThemeSkinSectionCardModifier: ViewModifier {
    let slot: ThemeSkinSlot
    let cornerRadius: CGFloat
    let showsDecoration: Bool

    func body(content: Content) -> some View {
        ThemeSkinSectionCardContainer(
            slot: slot,
            cornerRadius: cornerRadius,
            showsDecoration: showsDecoration
        ) {
            content
        }
    }
}

extension View {
    func themeSkinSectionCard(
        slot: ThemeSkinSlot = .sectionCard,
        cornerRadius: CGFloat = 18,
        showsDecoration: Bool = true
    ) -> some View {
        modifier(
            ThemeSkinSectionCardModifier(
                slot: slot,
                cornerRadius: cornerRadius,
                showsDecoration: showsDecoration
            )
        )
    }

    func themeSkinAdaptiveSectionCard<FallbackBackground: View>(
        slot: ThemeSkinSlot = .sectionCard,
        cornerRadius: CGFloat = 18,
        showsDecoration: Bool = true,
        @ViewBuilder fallbackBackground: () -> FallbackBackground
    ) -> some View {
        ThemeSkinAdaptiveSectionCardContainer(
            slot: slot,
            cornerRadius: cornerRadius,
            showsDecoration: showsDecoration,
            fallbackBackground: fallbackBackground
        ) {
            self
        }
    }

    func themeSkinLegibleText(
        level: ThemeSkinLegibilityLevel = .inline,
        slot: ThemeSkinSlot = .sectionCard,
        descriptor: ThemeSkinDescriptor? = nil
    ) -> some View {
        modifier(
            ThemeSkinLegibleTextModifier(
                level: level,
                slot: slot,
                descriptor: descriptor
            )
        )
    }

    func themeSkinLegibleSymbol(
        level: ThemeSkinLegibilityLevel = .chip,
        slot: ThemeSkinSlot = .iconCircleButton,
        descriptor: ThemeSkinDescriptor? = nil
    ) -> some View {
        modifier(
            ThemeSkinLegibleTextModifier(
                level: level,
                slot: slot,
                descriptor: descriptor
            )
        )
    }

    func themeSkinLegibilityBackdrop(
        level: ThemeSkinLegibilityLevel = .preview,
        slot: ThemeSkinSlot = .sectionCard,
        cornerRadius: CGFloat = 10,
        descriptor: ThemeSkinDescriptor? = nil
    ) -> some View {
        modifier(
            ThemeSkinLegibilityBackdropModifier(
                level: level,
                slot: slot,
                cornerRadius: cornerRadius,
                descriptor: descriptor
            )
        )
    }
}

struct ThemeSkinPrimaryButtonStyle: ButtonStyle {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    var fallbackTint: Color = .pink
    var slot: ThemeSkinSlot = .primaryButton
    var cornerRadius: CGFloat = 16
    var verticalPadding: CGFloat = 12

    init(
        fallbackTint: Color = .pink,
        slot: ThemeSkinSlot = .primaryButton,
        cornerRadius: CGFloat = 16,
        verticalPadding: CGFloat = 12
    ) {
        self.fallbackTint = fallbackTint
        self.slot = slot
        self.cornerRadius = cornerRadius
        self.verticalPadding = verticalPadding
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: slot, state: .default)
    }

    private var isThemed: Bool {
        ThemeSkinSharedSurfaceTokens.isSupported(descriptor)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .themeSkinLegibleText(level: .badge, slot: slot, descriptor: descriptor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(backgroundLayer(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isThemed ? 0.55 : 0.24), lineWidth: 1)
            }
            .shadow(
                color: (isThemed ? SkyConcertThemeSkin.shadowColor(for: descriptor) : fallbackTint).opacity(configuration.isPressed ? 0.12 : 0.26),
                radius: configuration.isPressed ? 4 : 9,
                x: 0,
                y: configuration.isPressed ? 2 : 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }

    @ViewBuilder
    private func backgroundLayer(isPressed: Bool) -> some View {
        if isThemed {
            LinearGradient(
                colors: [
                    SkyConcertThemeSkin.accent(for: descriptor).opacity(isPressed ? 0.78 : 0.92),
                    SkyConcertThemeSkin.labelColor(for: descriptor).opacity(isPressed ? 0.72 : 0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    fallbackTint.opacity(isPressed ? 0.72 : 0.9),
                    fallbackTint.mixed(with: .orange, amount: 0.18).opacity(isPressed ? 0.70 : 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct ThemeSkinIconBadge: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared

    let systemName: String
    var fallbackColor: Color = .pink
    var size: CGFloat = 40
    var symbolSize: CGFloat = 18
    var slot: ThemeSkinSlot = .iconCircleButton

    init(
        systemName: String,
        fallbackColor: Color = .pink,
        size: CGFloat = 40,
        symbolSize: CGFloat = 18,
        slot: ThemeSkinSlot = .iconCircleButton
    ) {
        self.systemName = systemName
        self.fallbackColor = fallbackColor
        self.size = size
        self.symbolSize = symbolSize
        self.slot = slot
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: slot, state: .default)
    }

    private var isThemed: Bool {
        ThemeSkinSharedSurfaceTokens.isSupported(descriptor)
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(isThemed ? SkyConcertThemeSkin.accent(for: descriptor) : fallbackColor)
            .themeSkinLegibleSymbol(level: .badge, slot: slot, descriptor: descriptor)
            .frame(width: size, height: size)
            .background {
                if isThemed {
                    ThemeSkinOrnateFrameSurface(
                        descriptor: descriptor,
                        cornerRadius: size / 2,
                        style: .compact,
                        showsDecoration: false
                    )
                } else {
                    Circle()
                        .fill(fallbackColor.opacity(0.12))
                }
            }
            .overlay {
                Circle()
                    .stroke(
                        isThemed
                            ? SkyConcertThemeSkin.accent(for: descriptor).opacity(0.58)
                            : fallbackColor.opacity(0.16),
                        lineWidth: isThemed ? 1.35 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isThemed && size >= 38 {
                    ornateCornerDot
                }
            }
            .shadow(
                color: isThemed ? SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.5) : .clear,
                radius: isThemed ? 8 : 6,
                x: 0,
                y: isThemed ? 4 : 3
            )
    }

    private var ornateCornerDot: some View {
        ThemeSkinEdgeSticker(
            descriptor: descriptor,
            assetName: ThemeSkinEdgeStickerAssets.assetName(for: descriptor, role: .iconCorner),
            size: max(16, size * 0.36),
            opacity: 0.78,
            offset: CGSize(width: size * 0.1, height: -size * 0.1),
            fallbackSystemName: SwanDreamThemeSkin.isSwanDream(descriptor) ? "sparkle" : "music.note"
        )
    }
}

struct ThemeSkinEmptyStateSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 26, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .themeSkinSectionCard(slot: .emptyState, cornerRadius: cornerRadius)
            .padding(.horizontal, 24)
    }
}

struct ThemeSkinSelectionBadge: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    let isSelected: Bool

    init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: .iconCircleButton, state: .default)
    }

    private var isThemed: Bool {
        ThemeSkinSharedSurfaceTokens.isSupported(descriptor)
    }

    var body: some View {
        ZStack {
            if isThemed {
                ZStack {
                    ThemeSkinOrnateFrameSurface(
                        descriptor: descriptor,
                        cornerRadius: 12,
                        style: .compact,
                        showsDecoration: false
                    )

                    if isSelected {
                        Circle()
                            .fill(SkyConcertThemeSkin.accent(for: descriptor).opacity(0.92))
                            .padding(3)
                    }
                }
                .frame(width: 24, height: 24)
            } else {
                Circle()
                    .fill(fillColor)
                    .frame(width: 24, height: 24)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .themeSkinLegibleSymbol(level: .inline, slot: .iconCircleButton, descriptor: descriptor)
            } else {
                Circle()
                    .stroke(strokeColor, lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(8)
        .shadow(color: isThemed ? SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.35) : .clear, radius: 5, x: 0, y: 2)
    }

    private var fillColor: Color {
        if isThemed {
            return isSelected ? SkyConcertThemeSkin.accent(for: descriptor) : SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.92)
        }
        return isSelected ? .pink : Color.white.opacity(0.8)
    }

    private var strokeColor: Color {
        isThemed ? SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.9) : Color.gray.opacity(0.5)
    }
}

private struct ThemeSkinPageThumbnailSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .themeSkinSectionCard(slot: .sectionCard, cornerRadius: 12, showsDecoration: false)
    }
}

extension View {
    func themeSkinPageThumbnailSurface() -> some View {
        modifier(ThemeSkinPageThumbnailSurfaceModifier())
    }
}

struct ThemeSkinBookCoverFrame: View {
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    var cornerRadius: CGFloat = 4

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.activeThemeDescriptor(for: .sectionCard, state: .default)
    }

    private var isThemed: Bool {
        ThemeSkinSharedSurfaceTokens.isSupported(descriptor)
    }

    var body: some View {
        if isThemed {
            ThemeSkinOrnateFrameBorder(
                descriptor: descriptor,
                cornerRadius: cornerRadius,
                style: .compact,
                showsDecoration: true
            )
            .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.5), radius: 8, x: 0, y: 4)
        }
    }
}
