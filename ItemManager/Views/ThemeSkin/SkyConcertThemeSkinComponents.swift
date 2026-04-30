import SwiftUI

enum SkyConcertThemeSkin {
    static let namespace = "sky_concert"

    static let decorBunnyAccordionStage = "sky_concert_decor_bunny_accordion_stage"
    static let decorCrescentRainCloud = "sky_concert_decor_crescent_rain_cloud"
    static let decorMoonStarClouds = "sky_concert_decor_moon_star_clouds"
    static let decorMusicScrollClouds = "sky_concert_decor_music_scroll_clouds"
    static let decorPastelPlanets = "sky_concert_decor_pastel_planets"
    static let decorShootingStar = "sky_concert_decor_shooting_star"
    static let decorSkyBalloonDoves = "sky_concert_decor_sky_balloon_doves"
    static let decorViolinCloud = "sky_concert_decor_" + "violin_cloud"
    static let decorWhaleCloudStars = "sky_concert_decor_whale_cloud_stars"
    static let decorWingedUnicornPrince = "sky_concert_decor_winged_unicorn_prince"

    static let creamTop = Color(hex: "FFFDF8")
    static let creamBottom = Color(hex: "F4FBFF")
    static let cloudBlue = Color(hex: "DCEFFF")
    static let cloudBlueDeep = Color(hex: "A9D8F6")
    static let blush = Color(hex: "FDECF2")
    static let softGold = Color(hex: "E5C57C")
    static let roseLine = Color(hex: "C99AA4")
    static let text = Color(hex: "6A647D")
    static let shadow = Color(hex: "94CBEA").opacity(0.24)

    static func isSkyConcert(_ descriptor: ThemeSkinDescriptor?) -> Bool {
        descriptor?.assetNamespace == namespace
    }

    static func hasDedicatedVisualProfile(_ descriptor: ThemeSkinDescriptor?) -> Bool {
        isSkyConcert(descriptor) || SwanDreamThemeSkin.isSwanDream(descriptor)
    }

    static func shouldAvoidShortAssetFallback(for descriptor: ThemeSkinDescriptor?) -> Bool {
        hasDedicatedVisualProfile(descriptor)
    }

    static func title(for descriptor: ThemeSkinDescriptor?) -> String {
        switch descriptor?.assetNamespace {
        case namespace:
            return "天空音乐会"
        case SwanDreamThemeSkin.namespace:
            return "天鹅入梦"
        default:
            return "少女衣橱"
        }
    }

    static func shellFillTop(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.creamTop
        }
        return isSkyConcert(descriptor) ? creamTop : Color(hex: "FFFDF8")
    }

    static func shellFillBottom(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.moonLavender.opacity(0.94)
        }
        return isSkyConcert(descriptor) ? cloudBlue.opacity(0.92) : Color(hex: "FCEEF3")
    }

    static func shellStroke(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.roseLine
        }
        return isSkyConcert(descriptor) ? cloudBlueDeep : Color(hex: "E7C7D3")
    }

    static func accent(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.moonGold
        }
        return isSkyConcert(descriptor) ? softGold : Color(hex: "D793AA")
    }

    static func accentSoft(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.ribbonPink.opacity(0.82)
        }
        return isSkyConcert(descriptor) ? cloudBlue.opacity(0.82) : Color(hex: "F4D5DF")
    }

    static func labelColor(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.text
        }
        return isSkyConcert(descriptor) ? text : Color(hex: "8A5C6F")
    }

    static func shadowColor(for descriptor: ThemeSkinDescriptor?) -> Color {
        if SwanDreamThemeSkin.isSwanDream(descriptor) {
            return SwanDreamThemeSkin.shadow
        }
        return isSkyConcert(descriptor) ? shadow : Color(hex: "DFAEBF").opacity(0.28)
    }

    static func toolbarPlacements(for style: HomeThemeSkinChromeStyle) -> [SkyConcertDecorationPlacement] {
        switch style {
        case .group:
            return [
                SkyConcertDecorationPlacement(
                    assetName: decorMusicScrollClouds,
                    width: 64,
                    opacity: 0.58,
                    alignment: .topTrailing,
                    offset: CGSize(width: 26, height: -24),
                    rotationDegrees: -8
                ),
                SkyConcertDecorationPlacement(
                    assetName: decorViolinCloud,
                    width: 32,
                    opacity: 0.46,
                    alignment: .bottomLeading,
                    offset: CGSize(width: -10, height: 10),
                    rotationDegrees: -10
                )
            ]
        case .segment:
            return [
                SkyConcertDecorationPlacement(
                    assetName: decorMoonStarClouds,
                    width: 52,
                    opacity: 0.28,
                    alignment: .topLeading,
                    offset: CGSize(width: -22, height: -18),
                    rotationDegrees: 0
                )
            ]
        case .searchEntry:
            return [
                SkyConcertDecorationPlacement(
                    assetName: decorViolinCloud,
                    width: 34,
                    opacity: 0.72,
                    alignment: .topTrailing,
                    offset: CGSize(width: 12, height: -12),
                    rotationDegrees: -8
                )
            ]
        }
    }

    static let wardrobeBackdropPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorSkyBalloonDoves,
            width: 196,
            opacity: 0.42,
            alignment: .topTrailing,
            offset: CGSize(width: 72, height: 70),
            rotationDegrees: -4
        ),
        SkyConcertDecorationPlacement(
            assetName: decorMoonStarClouds,
            width: 164,
            opacity: 0.48,
            alignment: .topLeading,
            offset: CGSize(width: -52, height: 88),
            rotationDegrees: -3
        ),
        SkyConcertDecorationPlacement(
            assetName: decorWhaleCloudStars,
            width: 270,
            opacity: 0.22,
            alignment: .center,
            offset: CGSize(width: 18, height: -122),
            rotationDegrees: 0
        ),
        SkyConcertDecorationPlacement(
            assetName: decorPastelPlanets,
            width: 82,
            opacity: 0.38,
            alignment: .trailing,
            offset: CGSize(width: 24, height: 34),
            rotationDegrees: 0
        ),
        SkyConcertDecorationPlacement(
            assetName: decorWingedUnicornPrince,
            width: 148,
            opacity: 0.28,
            alignment: .bottomTrailing,
            offset: CGSize(width: 42, height: -114),
            rotationDegrees: 3
        )
    ]

    static let statsCardPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorWhaleCloudStars,
            width: 190,
            opacity: 0.18,
            alignment: .bottom,
            offset: CGSize(width: 0, height: 12),
            rotationDegrees: 0
        ),
        SkyConcertDecorationPlacement(
            assetName: decorBunnyAccordionStage,
            width: 92,
            opacity: 0.9,
            alignment: .topTrailing,
            offset: CGSize(width: 26, height: -52),
            rotationDegrees: -5
        ),
        SkyConcertDecorationPlacement(
            assetName: decorViolinCloud,
            width: 48,
            opacity: 0.72,
            alignment: .topLeading,
            offset: CGSize(width: -14, height: -14),
            rotationDegrees: -8
        )
    ]

    static let wardrobeCardPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorViolinCloud,
            width: 56,
            opacity: 0.68,
            alignment: .topTrailing,
            offset: CGSize(width: 20, height: -24),
            rotationDegrees: 7
        ),
        SkyConcertDecorationPlacement(
            assetName: decorMusicScrollClouds,
            width: 36,
            opacity: 0.76,
            alignment: .topLeading,
            offset: CGSize(width: -12, height: -12),
            rotationDegrees: -8
        ),
        SkyConcertDecorationPlacement(
            assetName: decorPastelPlanets,
            width: 34,
            opacity: 0.38,
            alignment: .bottomTrailing,
            offset: CGSize(width: 8, height: 8),
            rotationDegrees: 0
        )
    ]

    static let tabBarPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorCrescentRainCloud,
            width: 62,
            opacity: 0.82,
            alignment: .topTrailing,
            offset: CGSize(width: -6, height: -42),
            rotationDegrees: 4
        ),
        SkyConcertDecorationPlacement(
            assetName: decorSkyBalloonDoves,
            width: 58,
            opacity: 0.42,
            alignment: .topLeading,
            offset: CGSize(width: 14, height: -28),
            rotationDegrees: -6
        )
    ]
}

enum SwanDreamThemeSkin {
    static let namespace = "swan_dream"

    static let decorCrownedSwanClouds = "swan_dream_decor_crowned_swan_clouds"
    static let decorFlyingSwanStars = "swan_dream_decor_flying_swan_stars"
    static let decorRibbonSwanClouds = "swan_dream_decor_ribbon_swan_clouds"
    static let decorSwanFeatherBow = "swan_dream_decor_" + "swan_feather_bow"
    static let decorCrescentPlanetSparkle = "swan_dream_decor_crescent_planet_sparkle"
    static let decorMoonBowBottle = "swan_dream_decor_moon_bow_bottle"
    static let decorPinkRibbonBow = "swan_dream_decor_pink_ribbon_bow"
    static let decorCrystalStars = "swan_dream_decor_crystal_stars"
    static let decorDreamCastleClouds = "swan_dream_decor_dream_castle_clouds"

    static let creamTop = Color(hex: "FFFDF9")
    static let moonCream = Color(hex: "FFF6DE")
    static let moonLavender = Color(hex: "F1E8FF")
    static let mistPurple = Color(hex: "DBC7F2")
    static let ribbonPink = Color(hex: "F8D6E6")
    static let roseLine = Color(hex: "D8A4B4")
    static let moonGold = Color(hex: "E7C06F")
    static let text = Color(hex: "735E78")
    static let shadow = Color(hex: "CBA6D8").opacity(0.24)

    static func isSwanDream(_ descriptor: ThemeSkinDescriptor?) -> Bool {
        descriptor?.assetNamespace == namespace
    }

    static func toolbarPlacements(for style: HomeThemeSkinChromeStyle) -> [SkyConcertDecorationPlacement] {
        switch style {
        case .group:
            return [
                SkyConcertDecorationPlacement(
                    assetName: decorPinkRibbonBow,
                    width: 50,
                    opacity: 0.56,
                    alignment: .topTrailing,
                    offset: CGSize(width: 22, height: -22),
                    rotationDegrees: -7
                ),
                SkyConcertDecorationPlacement(
                    assetName: decorMoonBowBottle,
                    width: 34,
                    opacity: 0.46,
                    alignment: .bottomLeading,
                    offset: CGSize(width: -9, height: 10),
                    rotationDegrees: -6
                )
            ]
        case .segment:
            return [
                SkyConcertDecorationPlacement(
                    assetName: decorSwanFeatherBow,
                    width: 52,
                    opacity: 0.3,
                    alignment: .topLeading,
                    offset: CGSize(width: -22, height: -18),
                    rotationDegrees: -9
                )
            ]
        case .searchEntry:
            return [
                SkyConcertDecorationPlacement(
                    assetName: decorMoonBowBottle,
                    width: 36,
                    opacity: 0.72,
                    alignment: .topTrailing,
                    offset: CGSize(width: 12, height: -13),
                    rotationDegrees: -4
                )
            ]
        }
    }

    static let wardrobeBackdropPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorFlyingSwanStars,
            width: 190,
            opacity: 0.22,
            alignment: .topTrailing,
            offset: CGSize(width: 78, height: 72),
            rotationDegrees: -4
        ),
        SkyConcertDecorationPlacement(
            assetName: decorCrescentPlanetSparkle,
            width: 150,
            opacity: 0.18,
            alignment: .topLeading,
            offset: CGSize(width: -48, height: 92),
            rotationDegrees: -8
        ),
        SkyConcertDecorationPlacement(
            assetName: decorDreamCastleClouds,
            width: 238,
            opacity: 0.18,
            alignment: .bottomTrailing,
            offset: CGSize(width: 58, height: -112),
            rotationDegrees: 0
        ),
        SkyConcertDecorationPlacement(
            assetName: decorMoonBowBottle,
            width: 74,
            opacity: 0.28,
            alignment: .trailing,
            offset: CGSize(width: 14, height: 22),
            rotationDegrees: -4
        )
    ]

    static let statsCardPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorCrescentPlanetSparkle,
            width: 126,
            opacity: 0.16,
            alignment: .bottom,
            offset: CGSize(width: -10, height: 18),
            rotationDegrees: -8
        ),
        SkyConcertDecorationPlacement(
            assetName: decorCrownedSwanClouds,
            width: 78,
            opacity: 0.84,
            alignment: .topTrailing,
            offset: CGSize(width: 22, height: -40),
            rotationDegrees: -4
        ),
        SkyConcertDecorationPlacement(
            assetName: decorSwanFeatherBow,
            width: 42,
            opacity: 0.66,
            alignment: .topLeading,
            offset: CGSize(width: -13, height: -13),
            rotationDegrees: -12
        )
    ]

    static let wardrobeCardPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorPinkRibbonBow,
            width: 44,
            opacity: 0.72,
            alignment: .topTrailing,
            offset: CGSize(width: 15, height: -18),
            rotationDegrees: 8
        ),
        SkyConcertDecorationPlacement(
            assetName: decorMoonBowBottle,
            width: 34,
            opacity: 0.72,
            alignment: .topLeading,
            offset: CGSize(width: -12, height: -12),
            rotationDegrees: -4
        ),
        SkyConcertDecorationPlacement(
            assetName: decorSwanFeatherBow,
            width: 30,
            opacity: 0.34,
            alignment: .bottomTrailing,
            offset: CGSize(width: 6, height: 10),
            rotationDegrees: -12
        )
    ]

    static let tabBarPlacements: [SkyConcertDecorationPlacement] = [
        SkyConcertDecorationPlacement(
            assetName: decorMoonBowBottle,
            width: 54,
            opacity: 0.82,
            alignment: .topLeading,
            offset: CGSize(width: 22, height: -46),
            rotationDegrees: -4
        ),
        SkyConcertDecorationPlacement(
            assetName: decorRibbonSwanClouds,
            width: 92,
            opacity: 0.76,
            alignment: .topTrailing,
            offset: CGSize(width: -6, height: -54),
            rotationDegrees: 3
        ),
        SkyConcertDecorationPlacement(
            assetName: decorCrownedSwanClouds,
            width: 38,
            opacity: 0.58,
            alignment: .top,
            offset: CGSize(width: 8, height: -24),
            rotationDegrees: -3
        )
    ]
}

struct SkyConcertDecorationPlacement: Identifiable {
    let id = UUID()
    let assetName: String
    let width: CGFloat
    let opacity: Double
    let alignment: Alignment
    let offset: CGSize
    let rotationDegrees: Double
}

struct SkyConcertDecorationLayer: View {
    let placements: [SkyConcertDecorationPlacement]
    var namespace: String = SkyConcertThemeSkin.namespace

    var body: some View {
        ZStack {
            ForEach(placements) { placement in
                Color.clear
                    .overlay(alignment: placement.alignment) {
                        ThemeSkinOptionalFittedAsset(
                            placement.assetName,
                            namespace: namespace,
                            allowShortNameFallback: false
                        ) {
                            EmptyView()
                        }
                        .frame(width: placement.width)
                        .opacity(placement.opacity)
                        .rotationEffect(.degrees(placement.rotationDegrees))
                        .offset(placement.offset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SkyConcertWardrobeBackdrop: View {
    let descriptor: ThemeSkinDescriptor?

    var body: some View {
        if SkyConcertThemeSkin.isSkyConcert(descriptor) {
            ZStack {
                LinearGradient(
                    colors: [
                        SkyConcertThemeSkin.cloudBlue.opacity(0.32),
                        SkyConcertThemeSkin.creamTop.opacity(0.12),
                        SkyConcertThemeSkin.blush.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                SkyConcertDecorationLayer(placements: SkyConcertThemeSkin.wardrobeBackdropPlacements)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if SwanDreamThemeSkin.isSwanDream(descriptor) {
            ZStack {
                LinearGradient(
                    colors: [
                        SwanDreamThemeSkin.moonLavender.opacity(0.28),
                        SwanDreamThemeSkin.creamTop.opacity(0.12),
                        SwanDreamThemeSkin.ribbonPink.opacity(0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                SkyConcertDecorationLayer(
                    placements: SwanDreamThemeSkin.wardrobeBackdropPlacements,
                    namespace: SwanDreamThemeSkin.namespace
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
