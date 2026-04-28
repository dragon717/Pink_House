import SwiftUI

private enum TabBarThemeSkinTokens {
    static let supportedNamespaces: Set<String> = ["girl_closet", "sky_concert", "swan_dream"]

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

    static func text(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.labelColor(for: descriptor) : roseText
    }

    static func shadow(for descriptor: ThemeSkinDescriptor?) -> Color {
        SkyConcertThemeSkin.hasDedicatedVisualProfile(descriptor) ? SkyConcertThemeSkin.shadowColor(for: descriptor) : shadow
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
            .overlay {
                if SkyConcertThemeSkin.isSkyConcert(descriptor) {
                    SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.tabBarPlacements)
                } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
                    SkyConcertDecorationLayer(
                        placements: SwanDreamThemeSkin.tabBarPlacements,
                        namespace: SwanDreamThemeSkin.namespace
                    )
                }
            }
            .frame(height: (SwanDreamThemeSkin.isSwanDream(descriptor) ? 66 : 58) + safeAreaBottom)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding ?? (safeAreaBottom > 0 ? 2 : 8))
        }
    }

    @ViewBuilder
    private var fallbackBackdrop: some View {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            swanDreamBackdrop
        } else {
            standardBackdrop
        }
    }

    private var standardBackdrop: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TabBarThemeSkinTokens.creamTop(for: descriptor).opacity(0.98),
                            TabBarThemeSkinTokens.creamBottom(for: descriptor).opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.98),
                                    TabBarThemeSkinTokens.border(for: descriptor).opacity(0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                }
                .shadow(color: TabBarThemeSkinTokens.shadow(for: descriptor), radius: 16, x: 0, y: 6)

            HStack {
                tabBarDoodle(icon: "star.fill")
                Spacer()
                tabBarDoodle(icon: "sparkles")
            }
            .padding(.horizontal, 18)
        }
    }

    private var swanDreamBackdrop: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 34,
                bottomLeadingRadius: 30,
                bottomTrailingRadius: 34,
                topTrailingRadius: 24,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        SwanDreamThemeSkin.creamTop.opacity(0.98),
                        SwanDreamThemeSkin.ribbonPink.opacity(0.72),
                        SwanDreamThemeSkin.moonLavender.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 34,
                    bottomLeadingRadius: 30,
                    bottomTrailingRadius: 34,
                    topTrailingRadius: 24,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.98),
                            SwanDreamThemeSkin.roseLine.opacity(0.82),
                            SwanDreamThemeSkin.moonGold.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.25
                )
            }
            .shadow(color: SwanDreamThemeSkin.shadow.opacity(0.9), radius: 16, x: 0, y: 6)

            HStack {
                tabBarDoodle(icon: "star.fill")
                Spacer()
                tabBarDoodle(icon: "sparkles")
            }
            .padding(.horizontal, 20)

            Circle()
                .fill(SwanDreamThemeSkin.creamTop.opacity(0.92))
                .frame(width: 58, height: 58)
                .overlay {
                    Circle()
                        .stroke(SwanDreamThemeSkin.roseLine.opacity(0.6), lineWidth: 1)
                }
                .offset(y: -16)
                .opacity(0.42)
                .allowsHitTesting(false)
        }
    }

    private func tabBarDoodle(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(TabBarThemeSkinTokens.accent(for: descriptor))
            .padding(6)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.96))
            )
            .overlay(
                Circle()
                    .stroke(TabBarThemeSkinTokens.border(for: descriptor).opacity(0.9), lineWidth: 1)
            )
    }
}

struct ThemeSkinModernTabLabel: View {
    let descriptor: ThemeSkinDescriptor?
    let title: String
    let systemImage: String
    let isSelected: Bool

    private var isActive: Bool {
        descriptor?.usesThemeSkinTabBarChrome == true
    }

    private var assetName: String {
        isSelected ? ThemeSkinAssetName.tabBarItemSelected : ThemeSkinAssetName.tabBarItemDefault
    }

    var body: some View {
        if isActive {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .medium))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? TabBarThemeSkinTokens.accent(for: descriptor) : TabBarThemeSkinTokens.text(for: descriptor).opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                ThemeSkinOptionalResizableAsset(
                    assetName,
                    namespace: descriptor?.assetNamespace,
                    allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
                ) {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.96))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(TabBarThemeSkinTokens.border(for: descriptor).opacity(0.9), lineWidth: 1)
                            }
                    } else {
                        Color.clear
                    }
                }
            }
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

    private var isActive: Bool {
        descriptor?.usesThemeSkinTabBarChrome == true
    }

    private var assetName: String {
        isSelected ? ThemeSkinAssetName.tabBarItemSelected : ThemeSkinAssetName.tabBarItemDefault
    }

    var body: some View {
        if isActive {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? TabBarThemeSkinTokens.accent(for: descriptor) : TabBarThemeSkinTokens.text(for: descriptor).opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                ThemeSkinOptionalResizableAsset(
                    assetName,
                    namespace: descriptor?.assetNamespace,
                    allowShortNameFallback: !SkyConcertThemeSkin.shouldAvoidShortAssetFallback(for: descriptor)
                ) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.96))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(TabBarThemeSkinTokens.border(for: descriptor).opacity(0.92), lineWidth: 1.1)
                            }
                    } else {
                        Color.clear
                    }
                }
            }
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
