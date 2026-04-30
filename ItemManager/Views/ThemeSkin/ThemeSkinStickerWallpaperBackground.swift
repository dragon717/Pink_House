import SwiftUI

enum ThemeSkinWallpaperContext: String, CaseIterable, Identifiable, Hashable {
    case general
    case wardrobe
    case depositPlan
    case house
    case wealth
    case journal
    case me
    case petChat
    case themeDetail

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "通用"
        case .wardrobe: return "衣橱"
        case .depositPlan: return "心愿尾款"
        case .house: return "House"
        case .wealth: return "财富"
        case .journal: return "穿搭手帐"
        case .me: return "我的"
        case .petChat: return "萌宠对话"
        case .themeDetail: return "主题设置"
        }
    }

    var assetIndexOffset: Int {
        switch self {
        case .general: return 0
        case .wardrobe: return 1
        case .depositPlan: return 3
        case .house: return 5
        case .wealth: return 2
        case .journal: return 4
        case .me: return 6
        case .petChat: return 7
        case .themeDetail: return 8
        }
    }

    var xOffset: CGFloat {
        switch self {
        case .general: return 0
        case .wardrobe: return 0.018
        case .depositPlan: return -0.026
        case .house: return 0.044
        case .wealth: return -0.044
        case .journal: return 0.032
        case .me: return -0.018
        case .petChat: return 0.052
        case .themeDetail: return -0.036
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .general: return 0
        case .wardrobe: return -0.014
        case .depositPlan: return 0.036
        case .house: return -0.044
        case .wealth: return 0.052
        case .journal: return -0.028
        case .me: return 0.024
        case .petChat: return 0.014
        case .themeDetail: return -0.022
        }
    }

    var rotationOffset: Double {
        switch self {
        case .general: return 0
        case .wardrobe: return 4
        case .depositPlan: return -6
        case .house: return 8
        case .wealth: return -3
        case .journal: return 6
        case .me: return -4
        case .petChat: return 10
        case .themeDetail: return -8
        }
    }

    var opacityMultiplier: Double {
        switch self {
        case .general, .themeDetail: return 1
        case .wardrobe, .journal: return 0.96
        case .depositPlan, .wealth: return 0.9
        case .house: return 0.82
        case .me: return 0.88
        case .petChat: return 0.86
        }
    }

    func tintColor(namespace: String) -> Color {
        switch (namespace, self) {
        case (SwanDreamThemeSkin.namespace, .depositPlan), (SwanDreamThemeSkin.namespace, .wealth):
            return SwanDreamThemeSkin.moonGold
        case (SwanDreamThemeSkin.namespace, .house), (SwanDreamThemeSkin.namespace, .petChat):
            return SwanDreamThemeSkin.mistPurple
        case (SwanDreamThemeSkin.namespace, .journal):
            return SwanDreamThemeSkin.ribbonPink
        case (SwanDreamThemeSkin.namespace, _):
            return SwanDreamThemeSkin.moonLavender
        case (SkyConcertThemeSkin.namespace, .depositPlan), (SkyConcertThemeSkin.namespace, .wealth):
            return SkyConcertThemeSkin.softGold
        case (SkyConcertThemeSkin.namespace, .house), (SkyConcertThemeSkin.namespace, .petChat):
            return SkyConcertThemeSkin.cloudBlueDeep
        case (SkyConcertThemeSkin.namespace, .journal):
            return SkyConcertThemeSkin.blush
        case (SkyConcertThemeSkin.namespace, _):
            return SkyConcertThemeSkin.cloudBlue
        default:
            return Color.white.opacity(0.5)
        }
    }

    var tintOpacity: Double {
        switch self {
        case .general: return 0
        case .wardrobe: return 0.08
        case .depositPlan: return 0.11
        case .house: return 0.07
        case .wealth: return 0.12
        case .journal: return 0.1
        case .me: return 0.09
        case .petChat: return 0.08
        case .themeDetail: return 0.13
        }
    }
}

struct ThemeSkinStickerWallpaperBackground: View {
    let product: ThemeSkinProduct
    let heroAssetName: String?
    var layoutPreset: ThemeSkinWallpaperLayoutPreset = .mixedFocus
    var context: ThemeSkinWallpaperContext = .general
    var includeBaseFill: Bool = true

    private var stickerOptions: [ThemeSkinBackgroundStickerOption] {
        product.backgroundStickerOptions
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let base = min(max(min(size.width, size.height), 320), 460)
            let placements = Self.patternPlacements(for: layoutPreset, context: context)

            ZStack {
                if includeBaseFill {
                    baseBackground
                    contextTintOverlay
                }

                ForEach(placements) { placement in
                    if let assetName = assetName(for: placement) {
                        ThemeSkinOptionalFittedAsset(
                            assetName,
                            namespace: product.assetNamespace,
                            allowShortNameFallback: false
                        ) {
                            Color.clear
                        }
                        .frame(
                            width: base * widthMultiplier(for: placement),
                            height: base * widthMultiplier(for: placement)
                        )
                        .opacity(opacity(for: placement))
                        .rotationEffect(.degrees(placement.rotationDegrees))
                        .scaleEffect(x: placement.flipped ? -1 : 1, y: 1)
                        .position(x: placement.x * size.width, y: placement.y * size.height)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var baseBackground: some View {
        LinearGradient(
            colors: baseColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var contextTintOverlay: some View {
        LinearGradient(
            colors: [
                context.tintColor(namespace: product.assetNamespace).opacity(context.tintOpacity),
                Color.white.opacity(context.tintOpacity * 0.38),
                context.tintColor(namespace: product.assetNamespace).opacity(context.tintOpacity * 0.7)
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    private var baseColors: [Color] {
        switch product.assetNamespace {
        case SwanDreamThemeSkin.namespace:
            return [
                Color(hex: "FFF7FB"),
                Color(hex: "F4ECFF"),
                Color(hex: "FFFDF8")
            ]
        case SkyConcertThemeSkin.namespace:
            return [
                Color(hex: "F8FCFF"),
                Color(hex: "EAF7FF"),
                Color(hex: "FFF7FB")
            ]
        default:
            return [Color(hex: "F4DADB"), Color.white.opacity(0.86)]
        }
    }

    private func assetName(for placement: ThemeSkinWallpaperStickerPlacement) -> String? {
        guard !stickerOptions.isEmpty else { return nil }

        if placement.isHero, let heroAssetName {
            return heroAssetName
        }

        let index = positiveModulo(placement.assetIndex + context.assetIndexOffset, stickerOptions.count)
        return stickerOptions[index].assetName
    }

    private func widthMultiplier(for placement: ThemeSkinWallpaperStickerPlacement) -> CGFloat {
        var width = placement.width

        if placement.isHero, heroAssetName == nil {
            width *= 0.58
        }

        switch layoutPreset {
        case .mixedFocus:
            return width
        case .heroStatement:
            return placement.isHero ? width * 1.08 : width * 0.92
        case .balancedScatter:
            return width * 0.94
        case .miniPattern:
            return width * 0.82
        }
    }

    private func opacity(for placement: ThemeSkinWallpaperStickerPlacement) -> Double {
        var opacity = placement.opacity * context.opacityMultiplier
        if placement.isHero, heroAssetName == nil {
            opacity = min(opacity + 0.06, 0.92)
        }
        return min(max(opacity, 0.12), 0.92)
    }

    private func positiveModulo(_ value: Int, _ count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private static func patternPlacements(
        for preset: ThemeSkinWallpaperLayoutPreset,
        context: ThemeSkinWallpaperContext
    ) -> [ThemeSkinWallpaperStickerPlacement] {
        let base: [ThemeSkinWallpaperStickerPlacement]
        switch preset {
        case .mixedFocus:
            base = mixedFocusPlacements
        case .heroStatement:
            base = heroStatementPlacements
        case .balancedScatter:
            base = balancedScatterPlacements
        case .miniPattern:
            base = miniPatternPlacements
        }

        return base.map { $0.adjusted(for: context) }
    }

    private static let mixedFocusPlacements: [ThemeSkinWallpaperStickerPlacement] = [
        .init(id: 0, x: 0.08, y: -0.02, width: 0.18, assetIndex: 4, rotationDegrees: -8, opacity: 0.46),
        .init(id: 1, x: 0.32, y: 0.04, width: 0.15, assetIndex: 5, rotationDegrees: 7, opacity: 0.50),
        .init(id: 2, x: 0.60, y: 0.01, width: 0.20, assetIndex: 3, rotationDegrees: -5, opacity: 0.44),
        .init(id: 3, x: 0.86, y: 0.07, width: 0.17, assetIndex: 4, rotationDegrees: 8, opacity: 0.46, flipped: true),
        .init(id: 4, x: 0.24, y: 0.13, width: 0.34, assetIndex: 0, rotationDegrees: -8, isHero: true, opacity: 0.34),
        .init(id: 5, x: 0.74, y: 0.18, width: 0.16, assetIndex: 1, rotationDegrees: 10, opacity: 0.58),
        .init(id: 6, x: 0.05, y: 0.22, width: 0.15, assetIndex: 2, rotationDegrees: -12, opacity: 0.52),
        .init(id: 7, x: 0.45, y: 0.25, width: 0.18, assetIndex: 4, rotationDegrees: 7, opacity: 0.60),
        .init(id: 8, x: 0.95, y: 0.27, width: 0.23, assetIndex: 3, rotationDegrees: -5, opacity: 0.44),
        .init(id: 9, x: 0.65, y: 0.33, width: 0.38, assetIndex: 0, rotationDegrees: 8, isHero: true, opacity: 0.32, flipped: true),
        .init(id: 10, x: 0.18, y: 0.36, width: 0.16, assetIndex: 1, rotationDegrees: 4, opacity: 0.58),
        .init(id: 11, x: 0.42, y: 0.42, width: 0.14, assetIndex: 5, rotationDegrees: -5, opacity: 0.60),
        .init(id: 12, x: 0.82, y: 0.45, width: 0.18, assetIndex: 2, rotationDegrees: 11, opacity: 0.54),
        .init(id: 13, x: 0.10, y: 0.53, width: 0.31, assetIndex: 0, rotationDegrees: 8, isHero: true, opacity: 0.36, flipped: true),
        .init(id: 14, x: 0.56, y: 0.55, width: 0.17, assetIndex: 3, rotationDegrees: -8, opacity: 0.52),
        .init(id: 15, x: 1.02, y: 0.57, width: 0.17, assetIndex: 4, rotationDegrees: 6, opacity: 0.46),
        .init(id: 16, x: 0.28, y: 0.64, width: 0.15, assetIndex: 5, rotationDegrees: -6, opacity: 0.60),
        .init(id: 17, x: 0.75, y: 0.68, width: 0.34, assetIndex: 0, rotationDegrees: -9, isHero: true, opacity: 0.34),
        .init(id: 18, x: 0.03, y: 0.72, width: 0.18, assetIndex: 1, rotationDegrees: 11, opacity: 0.50),
        .init(id: 19, x: 0.48, y: 0.77, width: 0.17, assetIndex: 2, rotationDegrees: 6, opacity: 0.55),
        .init(id: 20, x: 0.91, y: 0.82, width: 0.16, assetIndex: 5, rotationDegrees: -10, opacity: 0.60),
        .init(id: 21, x: 0.22, y: 0.88, width: 0.38, assetIndex: 0, rotationDegrees: -7, isHero: true, opacity: 0.34),
        .init(id: 22, x: 0.63, y: 0.93, width: 0.15, assetIndex: 4, rotationDegrees: 8, opacity: 0.54),
        .init(id: 23, x: 0.98, y: 1.02, width: 0.25, assetIndex: 3, rotationDegrees: -4, opacity: 0.42)
    ]

    private static let heroStatementPlacements: [ThemeSkinWallpaperStickerPlacement] = [
        .init(id: 100, x: 0.52, y: 0.08, width: 0.46, assetIndex: 0, rotationDegrees: -5, isHero: true, opacity: 0.34),
        .init(id: 101, x: 0.18, y: 0.20, width: 0.19, assetIndex: 1, rotationDegrees: -10, opacity: 0.52),
        .init(id: 102, x: 0.86, y: 0.25, width: 0.22, assetIndex: 2, rotationDegrees: 9, opacity: 0.48, flipped: true),
        .init(id: 103, x: 0.32, y: 0.38, width: 0.50, assetIndex: 0, rotationDegrees: 7, isHero: true, opacity: 0.32, flipped: true),
        .init(id: 104, x: 0.68, y: 0.48, width: 0.20, assetIndex: 3, rotationDegrees: -8, opacity: 0.48),
        .init(id: 105, x: 0.08, y: 0.56, width: 0.22, assetIndex: 4, rotationDegrees: 7, opacity: 0.44),
        .init(id: 106, x: 0.78, y: 0.66, width: 0.48, assetIndex: 0, rotationDegrees: -8, isHero: true, opacity: 0.33),
        .init(id: 107, x: 0.25, y: 0.78, width: 0.21, assetIndex: 5, rotationDegrees: 10, opacity: 0.5),
        .init(id: 108, x: 0.58, y: 0.88, width: 0.18, assetIndex: 2, rotationDegrees: -7, opacity: 0.46),
        .init(id: 109, x: 0.98, y: 0.96, width: 0.24, assetIndex: 3, rotationDegrees: 5, opacity: 0.38, flipped: true)
    ]

    private static let balancedScatterPlacements: [ThemeSkinWallpaperStickerPlacement] = [
        .init(id: 200, x: 0.08, y: 0.02, width: 0.20, assetIndex: 0, rotationDegrees: -8, opacity: 0.50),
        .init(id: 201, x: 0.38, y: 0.08, width: 0.18, assetIndex: 1, rotationDegrees: 7, opacity: 0.54),
        .init(id: 202, x: 0.72, y: 0.04, width: 0.22, assetIndex: 2, rotationDegrees: -4, opacity: 0.48, flipped: true),
        .init(id: 203, x: 0.95, y: 0.17, width: 0.18, assetIndex: 3, rotationDegrees: 11, opacity: 0.48),
        .init(id: 204, x: 0.18, y: 0.25, width: 0.24, assetIndex: 4, rotationDegrees: 8, opacity: 0.50),
        .init(id: 205, x: 0.54, y: 0.28, width: 0.20, assetIndex: 5, rotationDegrees: -9, opacity: 0.54),
        .init(id: 206, x: 0.82, y: 0.36, width: 0.22, assetIndex: 0, rotationDegrees: 6, opacity: 0.50),
        .init(id: 207, x: 0.04, y: 0.43, width: 0.18, assetIndex: 2, rotationDegrees: -11, opacity: 0.44),
        .init(id: 208, x: 0.35, y: 0.51, width: 0.22, assetIndex: 3, rotationDegrees: 7, opacity: 0.52, flipped: true),
        .init(id: 209, x: 0.66, y: 0.55, width: 0.24, assetIndex: 4, rotationDegrees: -6, opacity: 0.50),
        .init(id: 210, x: 0.92, y: 0.62, width: 0.20, assetIndex: 5, rotationDegrees: 9, opacity: 0.46),
        .init(id: 211, x: 0.18, y: 0.70, width: 0.20, assetIndex: 1, rotationDegrees: -5, opacity: 0.52),
        .init(id: 212, x: 0.48, y: 0.76, width: 0.24, assetIndex: 0, rotationDegrees: 8, opacity: 0.50),
        .init(id: 213, x: 0.76, y: 0.84, width: 0.20, assetIndex: 2, rotationDegrees: -10, opacity: 0.52),
        .init(id: 214, x: 0.05, y: 0.91, width: 0.19, assetIndex: 4, rotationDegrees: 4, opacity: 0.46),
        .init(id: 215, x: 0.34, y: 0.98, width: 0.21, assetIndex: 5, rotationDegrees: -7, opacity: 0.48),
        .init(id: 216, x: 0.62, y: 0.94, width: 0.18, assetIndex: 3, rotationDegrees: 6, opacity: 0.52),
        .init(id: 217, x: 0.98, y: 1.02, width: 0.22, assetIndex: 1, rotationDegrees: -5, opacity: 0.42)
    ]

    private static let miniPatternPlacements: [ThemeSkinWallpaperStickerPlacement] = [
        .init(id: 300, x: 0.06, y: 0.02, width: 0.15, assetIndex: 0, rotationDegrees: -6, opacity: 0.44),
        .init(id: 301, x: 0.28, y: 0.04, width: 0.13, assetIndex: 1, rotationDegrees: 5, opacity: 0.48),
        .init(id: 302, x: 0.50, y: 0.02, width: 0.15, assetIndex: 2, rotationDegrees: -4, opacity: 0.42),
        .init(id: 303, x: 0.74, y: 0.05, width: 0.14, assetIndex: 3, rotationDegrees: 6, opacity: 0.46),
        .init(id: 304, x: 0.96, y: 0.03, width: 0.16, assetIndex: 4, rotationDegrees: -7, opacity: 0.42),
        .init(id: 305, x: 0.17, y: 0.16, width: 0.17, assetIndex: 5, rotationDegrees: 8, opacity: 0.50),
        .init(id: 306, x: 0.42, y: 0.17, width: 0.14, assetIndex: 0, rotationDegrees: -9, opacity: 0.50),
        .init(id: 307, x: 0.67, y: 0.18, width: 0.16, assetIndex: 1, rotationDegrees: 5, opacity: 0.48),
        .init(id: 308, x: 0.90, y: 0.19, width: 0.13, assetIndex: 2, rotationDegrees: -6, opacity: 0.46),
        .init(id: 309, x: 0.03, y: 0.31, width: 0.14, assetIndex: 3, rotationDegrees: 7, opacity: 0.42),
        .init(id: 310, x: 0.30, y: 0.32, width: 0.18, assetIndex: 4, rotationDegrees: -5, opacity: 0.50),
        .init(id: 311, x: 0.54, y: 0.32, width: 0.14, assetIndex: 5, rotationDegrees: 6, opacity: 0.48),
        .init(id: 312, x: 0.79, y: 0.34, width: 0.17, assetIndex: 0, rotationDegrees: -7, opacity: 0.50),
        .init(id: 313, x: 1.02, y: 0.34, width: 0.14, assetIndex: 1, rotationDegrees: 6, opacity: 0.42),
        .init(id: 314, x: 0.15, y: 0.47, width: 0.15, assetIndex: 2, rotationDegrees: -8, opacity: 0.46),
        .init(id: 315, x: 0.39, y: 0.49, width: 0.17, assetIndex: 3, rotationDegrees: 7, opacity: 0.50),
        .init(id: 316, x: 0.63, y: 0.48, width: 0.15, assetIndex: 4, rotationDegrees: -5, opacity: 0.48),
        .init(id: 317, x: 0.88, y: 0.50, width: 0.16, assetIndex: 5, rotationDegrees: 6, opacity: 0.48),
        .init(id: 318, x: 0.04, y: 0.63, width: 0.15, assetIndex: 0, rotationDegrees: -7, opacity: 0.42),
        .init(id: 319, x: 0.27, y: 0.64, width: 0.14, assetIndex: 1, rotationDegrees: 8, opacity: 0.48),
        .init(id: 320, x: 0.52, y: 0.66, width: 0.18, assetIndex: 2, rotationDegrees: -6, opacity: 0.50),
        .init(id: 321, x: 0.76, y: 0.64, width: 0.14, assetIndex: 3, rotationDegrees: 5, opacity: 0.48),
        .init(id: 322, x: 0.97, y: 0.68, width: 0.15, assetIndex: 4, rotationDegrees: -8, opacity: 0.42),
        .init(id: 323, x: 0.16, y: 0.80, width: 0.17, assetIndex: 5, rotationDegrees: 7, opacity: 0.50),
        .init(id: 324, x: 0.40, y: 0.82, width: 0.14, assetIndex: 0, rotationDegrees: -6, opacity: 0.48),
        .init(id: 325, x: 0.66, y: 0.81, width: 0.16, assetIndex: 1, rotationDegrees: 8, opacity: 0.48),
        .init(id: 326, x: 0.88, y: 0.84, width: 0.14, assetIndex: 2, rotationDegrees: -5, opacity: 0.46),
        .init(id: 327, x: 0.08, y: 0.98, width: 0.15, assetIndex: 3, rotationDegrees: 6, opacity: 0.42),
        .init(id: 328, x: 0.34, y: 0.96, width: 0.16, assetIndex: 4, rotationDegrees: -7, opacity: 0.46),
        .init(id: 329, x: 0.61, y: 0.99, width: 0.14, assetIndex: 5, rotationDegrees: 6, opacity: 0.44),
        .init(id: 330, x: 0.93, y: 1.00, width: 0.16, assetIndex: 0, rotationDegrees: -6, opacity: 0.42)
    ]
}

private struct ThemeSkinWallpaperStickerPlacement: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let assetIndex: Int
    let rotationDegrees: Double
    var isHero: Bool = false
    var opacity: Double = 0.5
    var flipped: Bool = false

    func adjusted(for context: ThemeSkinWallpaperContext) -> ThemeSkinWallpaperStickerPlacement {
        ThemeSkinWallpaperStickerPlacement(
            id: id,
            x: wrapped(x + context.xOffset, lowerBound: -0.04, upperBound: 1.04),
            y: wrapped(y + context.yOffset, lowerBound: -0.04, upperBound: 1.04),
            width: width,
            assetIndex: assetIndex + context.assetIndexOffset,
            rotationDegrees: rotationDegrees + context.rotationOffset,
            isHero: isHero,
            opacity: opacity,
            flipped: context.assetIndexOffset.isMultiple(of: 2) ? flipped : !flipped
        )
    }

    private func wrapped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        let range = upperBound - lowerBound
        var next = value
        while next < lowerBound { next += range }
        while next > upperBound { next -= range }
        return next
    }
}

struct ThemeSkinBackgroundStickerSelectionCard: View {
    let product: ThemeSkinProduct

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @State private var showingHeroMenu = false

    private var selectedHeroAssetName: String? {
        themeSkinManager.backgroundHeroAssetName(for: product.themeId)
    }

    private var selectedLayoutPreset: ThemeSkinWallpaperLayoutPreset {
        themeSkinManager.backgroundLayoutPreset(for: product.themeId)
    }

    private var descriptor: ThemeSkinDescriptor? {
        themeSkinManager.descriptor(forThemeId: product.themeId, slot: .sectionCard)
    }

    private var options: [ThemeSkinBackgroundStickerOption] {
        product.backgroundStickerOptions
    }

    private var selectedHeroTitle: String {
        guard let selectedHeroAssetName else { return "全部小主图" }
        return options.first { $0.assetName == selectedHeroAssetName }?.displayName ?? "默认大主图"
    }

    var body: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                header
                wallpaperPreview
                layoutPresetGrid
                heroMenuButton
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("背景贴纸排布")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
            Text("先选大主图与小主图的排列方式；需要换大图时，再从弹窗菜单里选择。")
                .font(.footnote)
                .foregroundStyle(themeManager.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wallpaperPreview: some View {
        ThemeSkinStickerWallpaperBackground(
            product: product,
            heroAssetName: selectedHeroAssetName,
            layoutPreset: selectedLayoutPreset,
            context: .themeDetail,
            includeBaseFill: true
        )
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("当前：\(selectedLayoutPreset.displayName) · \(selectedHeroTitle)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .chip, slot: .sectionCard, descriptor: descriptor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .themeSkinLegibilityBackdrop(level: .chip, slot: .sectionCard, cornerRadius: 14, descriptor: descriptor)
                .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }

    private var layoutPresetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(ThemeSkinWallpaperLayoutPreset.allCases) { preset in
                layoutPresetButton(preset)
            }
        }
    }

    private func layoutPresetButton(_ preset: ThemeSkinWallpaperLayoutPreset) -> some View {
        let isSelected = selectedLayoutPreset == preset
        return Button {
            themeSkinManager.setBackgroundLayoutPreset(preset, for: product.themeId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.systemImageName)
                    .font(.headline)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(preset.summary)
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? themeManager.accentTextColor : themeManager.primaryTextColor)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? themeManager.cardTintColor.opacity(0.28) : Color.white.opacity(0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? themeManager.cardTintColor.opacity(0.86) : Color.white.opacity(0.5), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("背景贴纸排布：\(preset.displayName)")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private var heroMenuButton: some View {
        Button {
            showingHeroMenu = true
        } label: {
            HStack(spacing: 12) {
                heroThumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择大主图")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text(selectedHeroTitle)
                        .font(.footnote)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            .padding(12)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog("选择大主图", isPresented: $showingHeroMenu, titleVisibility: .visible) {
            Button("全部小主图") {
                themeSkinManager.setBackgroundHeroAssetName(nil, for: product.themeId)
            }

            ForEach(options) { option in
                Button(option.displayName) {
                    themeSkinManager.setBackgroundHeroAssetName(option.assetName, for: product.themeId)
                }
            }

            Button("取消", role: .cancel) { }
        } message: {
            Text("排列方式保持不变，只替换大主图。")
        }
    }

    private var heroThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeManager.cardTintColor.opacity(0.16))
                .frame(width: 54, height: 54)

            if let selectedHeroAssetName {
                ThemeSkinOptionalFittedAsset(
                    selectedHeroAssetName,
                    namespace: product.assetNamespace,
                    allowShortNameFallback: false
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(themeManager.accentTextColor)
                }
                .frame(width: 44, height: 44)
            } else {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.title3)
                    .foregroundStyle(themeManager.accentTextColor)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        )
    }
}
