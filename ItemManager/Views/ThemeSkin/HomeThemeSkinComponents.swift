import SwiftUI

private enum HomeThemeSkinTokens {
    static let supportedNamespaces: Set<String> = ["girl_closet", "sky_concert", "swan_dream"]

    static let creamTop = Color(red: 1.0, green: 0.977, blue: 0.965)
    static let creamBottom = Color(red: 1.0, green: 0.938, blue: 0.95)
    static let pinkBorder = Color(red: 0.918, green: 0.694, blue: 0.796)
    static let pinkShadow = Color(red: 0.89, green: 0.6, blue: 0.72)
    static let blush = Color(red: 0.996, green: 0.852, blue: 0.9)
    static let rose = Color(red: 0.878, green: 0.518, blue: 0.675)
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
            return 14
        case .segment:
            return 12
        case .searchEntry:
            return 10
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
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    HomeThemeSkinChromeBackground(style: style)
                }
        } else {
            content
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
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
                .frame(minWidth: minWidth, minHeight: minHeight)
                .padding(6)
                .background {
                    ThemeSkinOptionalResizableAsset(ThemeSkinAssetName.topBarIconButton) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        HomeThemeSkinTokens.creamTop.opacity(0.98),
                                        HomeThemeSkinTokens.blush.opacity(0.9)
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
                                                HomeThemeSkinTokens.pinkBorder.opacity(0.82)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .shadow(color: HomeThemeSkinTokens.pinkShadow.opacity(0.16), radius: 8, x: 0, y: 4)
        } else {
            content
        }
    }

    private var isActive: Bool {
        descriptor?.usesThemeSkinChrome == true
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
                    .foregroundStyle(HomeThemeSkinTokens.rose)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                HomeThemeSkinChromeBackground(style: .searchEntry)
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
            capInsets: ThemeSkinAssetName.capInsets(for: assetName)
        ) {
            fallbackBackground
        }
        .shadow(color: HomeThemeSkinTokens.pinkShadow.opacity(0.18), radius: style.shadowRadius, x: 0, y: 6)
    }

    private var fallbackBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            HomeThemeSkinTokens.creamTop.opacity(0.98),
                            HomeThemeSkinTokens.creamBottom.opacity(0.96)
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
                            HomeThemeSkinTokens.pinkBorder.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )

            RoundedRectangle(cornerRadius: style.cornerRadius - 3, style: .continuous)
                .stroke(HomeThemeSkinTokens.blush.opacity(0.45), lineWidth: 0.6)
                .padding(3)

            Circle()
                .fill(HomeThemeSkinTokens.blush.opacity(0.95))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                }
                .offset(x: -26, y: -11)

            Circle()
                .fill(HomeThemeSkinTokens.creamTop.opacity(0.98))
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(HomeThemeSkinTokens.pinkBorder.opacity(0.65), lineWidth: 1)
                }
                .offset(x: 28, y: 12)
        }
    }
}
