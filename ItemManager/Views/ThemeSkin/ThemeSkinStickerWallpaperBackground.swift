import SwiftUI

struct ThemeSkinStickerWallpaperBackground: View {
    let product: ThemeSkinProduct
    let heroAssetName: String?
    var includeBaseFill: Bool = true

    private var stickerOptions: [ThemeSkinBackgroundStickerOption] {
        product.backgroundStickerOptions
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let base = min(max(size.width, 320), 460)

            ZStack {
                if includeBaseFill {
                    baseBackground
                }

                ForEach(Self.patternPlacements) { placement in
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

        return stickerOptions[placement.assetIndex % stickerOptions.count].assetName
    }

    private func widthMultiplier(for placement: ThemeSkinWallpaperStickerPlacement) -> CGFloat {
        if placement.isHero, heroAssetName == nil {
            return placement.width * 0.58
        }
        return placement.width
    }

    private func opacity(for placement: ThemeSkinWallpaperStickerPlacement) -> Double {
        if placement.isHero, heroAssetName == nil {
            return min(placement.opacity + 0.06, 0.92)
        }
        return placement.opacity
    }

    private static let patternPlacements: [ThemeSkinWallpaperStickerPlacement] = [
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
}

struct ThemeSkinBackgroundStickerSelectionCard: View {
    let product: ThemeSkinProduct

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager

    private var selectedHeroAssetName: String? {
        themeSkinManager.backgroundHeroAssetName(for: product.themeId)
    }

    private var options: [ThemeSkinBackgroundStickerOption] {
        product.backgroundStickerOptions
    }

    var body: some View {
        ThemeSkinSectionCardContainer(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                header
                wallpaperPreview
                optionScroller
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("背景贴纸排布")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
            Text("默认用一张大主图压住视觉焦点，再按参考图的 Emoji 墙节奏铺小贴纸；选择“全部小主图”会取消大主图。")
                .font(.footnote)
                .foregroundStyle(themeManager.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wallpaperPreview: some View {
        ThemeSkinStickerWallpaperBackground(
            product: product,
            heroAssetName: selectedHeroAssetName,
            includeBaseFill: true
        )
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
    }

    private var optionScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                optionButton(assetName: nil, title: "全部小主图")

                ForEach(options) { option in
                    optionButton(assetName: option.assetName, title: option.displayName)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func optionButton(assetName: String?, title: String) -> some View {
        let isSelected = selectedHeroAssetName == assetName
        return Button {
            themeSkinManager.setBackgroundHeroAssetName(assetName, for: product.themeId)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? themeManager.cardTintColor.opacity(0.24) : Color.white.opacity(0.54))
                        .frame(width: 74, height: 74)

                    if let assetName {
                        ThemeSkinOptionalFittedAsset(
                            assetName,
                            namespace: product.assetNamespace,
                            allowShortNameFallback: false
                        ) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(themeManager.accentTextColor)
                        }
                        .frame(width: 58, height: 58)
                    } else {
                        Image(systemName: "circle.grid.cross")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(themeManager.accentTextColor)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? themeManager.cardTintColor.opacity(0.82) : Color.white.opacity(0.52), lineWidth: isSelected ? 2 : 1)
                )

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? themeManager.accentTextColor : themeManager.secondaryTextColor)
                    .lineLimit(1)
                    .frame(width: 78)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("背景大主图：\(title)")
    }
}
