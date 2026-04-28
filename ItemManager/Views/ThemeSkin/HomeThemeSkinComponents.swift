import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum HomeThemeSkinTokens {
    static let supportedNamespaces: Set<String> = ["girl_closet", "sky_concert", "swan_dream"]

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
            return 19
        case .segment:
            return 21
        case .searchEntry:
            return 15
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .group:
            return 11
        case .segment:
            return 10
        case .searchEntry:
            return 8
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
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8,
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
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
    }

    private var shouldUseCompactChrome: Bool {
        guard isActive else { return false }
        #if canImport(UIKit)
        if #available(iOS 26.0, *) {
            return UIDevice.current.userInterfaceIdiom == .phone
        }
        #endif
        return false
    }

    private var effectiveHorizontalPadding: CGFloat {
        shouldUseCompactChrome ? min(horizontalPadding, 6) : horizontalPadding
    }

    private var effectiveVerticalPadding: CGFloat {
        shouldUseCompactChrome ? min(verticalPadding, 4) : verticalPadding
    }
}

struct HomeThemeSkinToolbarIconShell<Content: View>: View {
    let descriptor: ThemeSkinDescriptor?
    let minWidth: CGFloat
    let minHeight: CGFloat
    let content: Content

    init(
        descriptor: ThemeSkinDescriptor?,
        minWidth: CGFloat = 30,
        minHeight: CGFloat = 30,
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
                .frame(minWidth: effectiveMinWidth, minHeight: effectiveMinHeight)
                .padding(effectivePadding)
                .background {
                    ThemeSkinOptionalResizableAsset(
                        ThemeSkinAssetName.topBarIconButton,
                        namespace: descriptor?.assetNamespace,
                        allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
                    ) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        HomeThemeSkinTokens.creamTop(for: descriptor).opacity(0.98),
                                        HomeThemeSkinTokens.softAccent(for: descriptor).opacity(0.9)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.95),
                                                HomeThemeSkinTokens.border(for: descriptor).opacity(0.82)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .shadow(color: HomeThemeSkinTokens.shadow(for: descriptor).opacity(0.16), radius: 8, x: 0, y: 4)
        } else {
            content
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
    }

    private var shouldUseCompactChrome: Bool {
        guard isActive else { return false }
        #if canImport(UIKit)
        if #available(iOS 26.0, *) {
            return UIDevice.current.userInterfaceIdiom == .phone
        }
        #endif
        return false
    }

    private var effectiveMinWidth: CGFloat {
        shouldUseCompactChrome ? min(minWidth, 24) : minWidth
    }

    private var effectiveMinHeight: CGFloat {
        shouldUseCompactChrome ? min(minHeight, 24) : minHeight
    }

    private var effectivePadding: CGFloat {
        shouldUseCompactChrome ? 4 : 6
    }

    private var effectiveIconSize: CGFloat {
        shouldUseCompactChrome ? 13 : 14
    }
}

struct HomeThemeSkinSearchMenuLabel: View {
    let descriptor: ThemeSkinDescriptor?
    let title: String
    let systemImage: String

    var body: some View {
        if isActive {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeThemeSkinTokens.accent(for: descriptor))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                HomeThemeSkinChromeBackground(descriptor: descriptor, style: .searchEntry)
            }
        } else {
            Label(title, systemImage: systemImage)
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
            if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.toolbarPlacements(for: style))
            } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                SkyConcertDecorationLayer(
                    placements: SwanDreamThemeSkin.toolbarPlacements(for: style),
                    namespace: SwanDreamThemeSkin.namespace
                )
            }
        }
        .shadow(color: HomeThemeSkinTokens.shadow(for: descriptor).opacity(0.18), radius: style.shadowRadius, x: 0, y: 6)
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
                            HomeThemeSkinTokens.border(for: descriptor).opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )

            RoundedRectangle(cornerRadius: style.cornerRadius - 3, style: .continuous)
                .stroke(HomeThemeSkinTokens.softAccent(for: descriptor).opacity(0.45), lineWidth: 0.6)
                .padding(3)

            Circle()
                .fill(HomeThemeSkinTokens.softAccent(for: descriptor).opacity(0.95))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                }
                .offset(x: -26, y: -11)

            Circle()
                .fill(HomeThemeSkinTokens.creamTop(for: descriptor).opacity(0.98))
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(HomeThemeSkinTokens.border(for: descriptor).opacity(0.65), lineWidth: 1)
                }
                .offset(x: 28, y: 12)
        }
    }
}
