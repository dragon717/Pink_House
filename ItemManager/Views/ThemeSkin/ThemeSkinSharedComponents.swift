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

    static func stickerAssetName(for descriptor: ThemeSkinDescriptor?) -> String {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.decorCrystalStars
        }
        return SkyConcertThemeSkin.decorShootingStar
    }

    static func secondaryStickerAssetName(for descriptor: ThemeSkinDescriptor?) -> String {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.decorSwanFeatherBow
        }
        return SkyConcertThemeSkin.decorMusicScrollClouds
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
        content
            .background(backgroundLayer)
            .overlay(borderLayer)
            .overlay(alignment: .topTrailing) {
                if isThemed && showsDecoration {
                    ThemeSkinCornerSticker(
                        descriptor: descriptor,
                        assetName: ThemeSkinSharedSurfaceTokens.stickerAssetName(for: descriptor),
                        size: 34,
                        opacity: 0.62,
                        offset: CGSize(width: 10, height: -12)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: isThemed ? SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.72) : Color.black.opacity(0.05),
                radius: isThemed ? 12 : 5,
                x: 0,
                y: isThemed ? 6 : 2
            )
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if isThemed {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.98),
                            SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.76 : 0.58),
                            SkyConcertThemeSkin.shellFillBottom(for: descriptor).opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            CardBackgroundView(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                isThemed
                    ? LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.92),
                            SkyConcertThemeSkin.accent(for: descriptor).opacity(0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color.primary.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                lineWidth: isThemed ? 1.1 : 1
            )
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
        content
            .background(backgroundLayer)
            .overlay(borderLayer)
            .overlay(alignment: .topTrailing) {
                if isThemed && showsDecoration {
                    ThemeSkinCornerSticker(
                        descriptor: descriptor,
                        assetName: ThemeSkinSharedSurfaceTokens.stickerAssetName(for: descriptor),
                        size: 28,
                        opacity: 0.48,
                        offset: CGSize(width: 8, height: -10)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: isThemed ? SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.62) : .clear,
                radius: isThemed ? 10 : 0,
                x: 0,
                y: isThemed ? 5 : 0
            )
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if isThemed {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.97),
                            SkyConcertThemeSkin.accentSoft(for: descriptor).opacity(SwanDreamThemeSkin.isSwanDream(descriptor) ? 0.64 : 0.48),
                            SkyConcertThemeSkin.shellFillBottom(for: descriptor).opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            fallbackBackground
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                isThemed
                    ? LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.78),
                            SkyConcertThemeSkin.accent(for: descriptor).opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                lineWidth: isThemed ? 1 : 0
            )
    }
}

private struct ThemeSkinCornerSticker: View {
    let descriptor: ThemeSkinDescriptor?
    let assetName: String
    let size: CGFloat
    let opacity: Double
    let offset: CGSize

    var body: some View {
        ThemeSkinOptionalFittedAsset(
            assetName,
            namespace: descriptor?.assetNamespace,
            allowShortNameFallback: false
        ) {
            Image(systemName: "sparkles")
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
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(
                        isThemed
                            ? SkyConcertThemeSkin.shellFillTop(for: descriptor).opacity(0.94)
                            : fallbackColor.opacity(0.12)
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        isThemed
                            ? SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.95)
                            : fallbackColor.opacity(0.16),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isThemed ? SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.42) : .clear,
                radius: 6,
                x: 0,
                y: 3
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
            Circle()
                .fill(fillColor)
                .frame(width: 24, height: 24)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
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
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            SkyConcertThemeSkin.shellStroke(for: descriptor).opacity(0.95),
                            SkyConcertThemeSkin.accent(for: descriptor).opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
                .overlay(alignment: .topTrailing) {
                    ThemeSkinCornerSticker(
                        descriptor: descriptor,
                        assetName: ThemeSkinSharedSurfaceTokens.secondaryStickerAssetName(for: descriptor),
                        size: 28,
                        opacity: 0.54,
                        offset: CGSize(width: 8, height: -9)
                    )
                }
                .shadow(color: SkyConcertThemeSkin.shadowColor(for: descriptor).opacity(0.45), radius: 7, x: 0, y: 4)
        }
    }
}
