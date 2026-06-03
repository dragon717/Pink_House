import SwiftUI

private enum HomeThemeSkinTokens {
    static let supportedNamespaces: Set<String> = ["sky_concert", "swan_dream"]

    static let creamTop = Color(red: 1.0, green: 0.977, blue: 0.965)
    static let creamBottom = Color(red: 1.0, green: 0.938, blue: 0.95)
    static let pinkBorder = Color(red: 0.918, green: 0.694, blue: 0.796)
    static let pinkShadow = Color(red: 0.89, green: 0.6, blue: 0.72)
    static let blush = Color(red: 0.996, green: 0.852, blue: 0.9)
    static let rose = Color(red: 0.878, green: 0.518, blue: 0.675)

    static func creamTop(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellFillTop(for: descriptor) : creamTop
    }

    static func creamBottom(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellFillBottom(for: descriptor) : creamBottom
    }

    static func border(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shellStroke(for: descriptor) : pinkBorder
    }

    static func shadow(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shadowColor(for: descriptor) : pinkShadow
    }

    static func accent(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.accent(for: descriptor) : rose
    }

    static func accent(for descriptor: ThemeSkinDescriptor?, colorScheme: ColorScheme) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.accent(for: descriptor, colorScheme: colorScheme) : rose
    }

    static func softAccent(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.accentSoft(for: descriptor) : blush
    }
}

enum HomeThemeSkinChromeStyle {
    case group
    case segment
    case searchEntry

    var cornerRadius: CGFloat {
        switch self {
        case .group:
            return 16
        case .segment:
            return 17
        case .searchEntry:
            return 13
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .group:
            return 7
        case .segment:
            return 6
        case .searchEntry:
            return 5
        }
    }
}

private extension ThemeSkinDescriptor {
    var usesThemeSkinChrome: Bool {
        HomeThemeSkinTokens.supportedNamespaces.contains(assetNamespace)
    }
}

struct HomeThemeSkinToolbarShell<Content: View>: View {
    let descriptor: ThemeSkinDescriptor?
    let style: HomeThemeSkinChromeStyle
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let content: Content

    init(
        descriptor: ThemeSkinDescriptor?,
        style: HomeThemeSkinChromeStyle = .group,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 5,
        @ViewBuilder content: () -> Content
    ) {
        self.descriptor = descriptor
        self.style = style
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        if isActive {
            content
                .padding(.horizontal, effectiveHorizontalPadding)
                .padding(.vertical, effectiveVerticalPadding)
                .background {
                    HomeThemeSkinChromeBackground(descriptor: descriptor, style: style)
                }
        } else {
            content
                .padding(.horizontal, effectiveHorizontalPadding)
                .padding(.vertical, effectiveVerticalPadding)
                .background {
                    defaultLiquidGlassBackground
                }
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
    }

    private var effectiveHorizontalPadding: CGFloat {
        horizontalPadding
    }

    private var effectiveVerticalPadding: CGFloat {
        verticalPadding
    }

    private var defaultLiquidGlassBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.46), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

struct HomeThemeSkinToolbarIconShell<Content: View>: View {
    let descriptor: ThemeSkinDescriptor?
    let minWidth: CGFloat
    let minHeight: CGFloat
    let content: Content

    init(
        descriptor: ThemeSkinDescriptor?,
        minWidth: CGFloat = 24,
        minHeight: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.descriptor = descriptor
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        if isActive {
            content
                .font(.system(size: effectiveIconSize, weight: .semibold))
                .themeSkinLegibleSymbol(level: .badge, slot: descriptor?.slot ?? .topBarIconButton, descriptor: descriptor)
                .frame(minWidth: effectiveMinWidth, minHeight: effectiveMinHeight)
        } else {
            content
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
    }

    private var effectiveMinWidth: CGFloat {
        minWidth
    }

    private var effectiveMinHeight: CGFloat {
        minHeight
    }

    private var effectiveIconSize: CGFloat {
        12
    }
}

struct HomeThemeSkinSearchMenuLabel: View {
    let descriptor: ThemeSkinDescriptor?
    let title: String
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isActive {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeThemeSkinTokens.accent(for: descriptor, colorScheme: colorScheme))
                    .themeSkinLegibleSymbol(level: .chip, slot: descriptor?.slot ?? .searchBar, descriptor: descriptor)

                Text(title.appLocalized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SkyConcertThemeSkin.labelColor(for: descriptor, colorScheme: colorScheme))
                    .themeSkinLegibleText(level: .inline, slot: descriptor?.slot ?? .searchBar, descriptor: descriptor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                HomeThemeSkinChromeBackground(descriptor: descriptor, style: .searchEntry)
            }
        } else {
            Label(title.appLocalized, systemImage: systemImage)
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
    }
}

private struct HomeThemeSkinChromeBackground: View {
    let descriptor: ThemeSkinDescriptor?
    let style: HomeThemeSkinChromeStyle

    private var assetName: String {
        switch style {
        case .group:
            return ThemeSkinAssetName.topBarMain
        case .segment:
            return ThemeSkinAssetName.topBarSegment
        case .searchEntry:
            return ThemeSkinAssetName.searchBarCompact
        }
    }

    var body: some View {
        ThemeSkinOptionalResizableAsset(
            assetName,
            namespace: descriptor?.assetNamespace,
            allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor),
            capInsets: ThemeSkinAssetName.capInsets(for: assetName)
        ) {
            fallbackBackground
        }
        .overlay {
            toolbarDecorationLayer
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: HomeThemeSkinTokens.shadow(for: descriptor).opacity(0.18), radius: style.shadowRadius, x: 0, y: 6)
    }

    @ViewBuilder
    private var toolbarDecorationLayer: some View {
        // 主题顶部装饰属于背景纹理层：保留菜单/顶栏图案，但始终位于文字与按钮内容下方。
        if SkyConcertThemeSkin.isSkyConcert(descriptor) {
            SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.toolbarPlacements(for: style))
        } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
            SkyConcertDecorationLayer(
                placements: SwanDreamThemeSkin.toolbarPlacements(for: style),
                namespace: SwanDreamThemeSkin.namespace
            )
        }
    }

    private var fallbackBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            HomeThemeSkinTokens.creamTop(for: descriptor).opacity(0.98),
                            HomeThemeSkinTokens.creamBottom(for: descriptor).opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.95),
                            HomeThemeSkinTokens.border(for: descriptor).opacity(0.95),
                            HomeThemeSkinTokens.accent(for: descriptor).opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.35
                )

            RoundedRectangle(cornerRadius: style.cornerRadius - 3, style: .continuous)
                .stroke(HomeThemeSkinTokens.softAccent(for: descriptor).opacity(0.62), lineWidth: 0.75)
                .padding(3.5)

            Circle()
                .fill(HomeThemeSkinTokens.softAccent(for: descriptor).opacity(0.95))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                }
                .offset(x: -23, y: -13)

            Circle()
                .fill(HomeThemeSkinTokens.creamTop(for: descriptor).opacity(0.98))
                .frame(width: 6, height: 6)
                .overlay {
                    Circle()
                        .stroke(HomeThemeSkinTokens.border(for: descriptor).opacity(0.65), lineWidth: 1)
                }
                .offset(x: 25, y: 14)
        }
    }
}
