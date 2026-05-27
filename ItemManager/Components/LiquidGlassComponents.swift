//
//  LiquidGlassComponents.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI

// MARK: - Smart Background Image
struct SmartBackgroundImage: View {
    let image: UIImage
    let opacity: Double
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            let imageSize = image.size
            
            // 如果图片尺寸小于屏幕尺寸，则平铺 (Tile)
            // 否则，缩放填充并居中 (ScaledToFill)
            if imageSize.width < screenSize.width || imageSize.height < screenSize.height {
                Image(uiImage: image)
                    .resizable(resizingMode: .tile)
                    .opacity(opacity)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenSize.width, height: screenSize.height, alignment: .center)
                    .clipped()
                    .opacity(opacity)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Background
struct LiquidBackground: View {
    var themeSkinWallpaperContext: ThemeSkinWallpaperContext = .general

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    
    var body: some View {
        ZStack {
            // 1. Base Layer (Color or Image)
            themeManager.backgroundColor
                .ignoresSafeArea()

            if let activeProduct = themeSkinManager.activeProduct {
                ThemeSkinStickerWallpaperBackground(
                    product: activeProduct,
                    heroAssetName: themeSkinManager.backgroundHeroAssetName(for: activeProduct.themeId),
                    layoutPreset: themeSkinManager.backgroundLayoutPreset(for: activeProduct.themeId),
                    context: themeSkinWallpaperContext
                )
            } else if themeManager.effectiveBackgroundStyle == .image, let image = themeManager.backgroundImage {
                SmartBackgroundImage(image: image, opacity: themeManager.backgroundOpacity)
                
                // Dark Mode Overlay
                if colorScheme == .dark {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                }
            }
            
            // 2. Blur Layer (Material Overlay)
            if themeManager.isBlurEnabled && themeSkinManager.activeProduct == nil {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

// MARK: - Glass Card
/// 统一配色的玻璃卡片组件，支持魔法配色和客制化配色
/// 使用 CardBackgroundView 统一处理卡片背景，确保色调强度实时变化
struct GlassCard<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    var content: Content

    init(cornerRadius: CGFloat = 24, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        ZStack {
            // 使用 CardBackgroundView 统一处理卡片背景
            CardBackgroundView(cornerRadius: cornerRadius)

            content
                .padding(padding)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .unifiedShadow(.card)
    }
}

// MARK: - Text Enhancements
struct OutlinedText: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    var color: Color = .white
    var width: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        if themeManager.effectiveBackgroundStyle == .image {
            if colorScheme == .dark {
                content
                    .shadow(color: .black, radius: 1, x: 0, y: 0)
                    .shadow(color: .black, radius: 1, x: 0, y: 0) // Double shadow for stronger effect
            } else {
                content
                    .shadow(color: .white, radius: 1, x: 0, y: 0)
                    .shadow(color: .white, radius: 1, x: 0, y: 0)
            }
        } else {
            content
        }
    }
}

extension View {
    func outlined() -> some View {
        modifier(OutlinedText())
    }
}
