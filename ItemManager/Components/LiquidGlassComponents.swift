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
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // 1. Base Layer (Color or Image)
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            if themeManager.backgroundStyle == .image, let image = themeManager.backgroundImage {
                SmartBackgroundImage(image: image, opacity: themeManager.backgroundOpacity)
                
                // Dark Mode Overlay
                if colorScheme == .dark {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                }
            } else {
                // 2. Decorative Orbs (Only for solid color background)
                // These add depth to the solid color
                Circle()
                    .fill(Color.pink.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -100, y: -200)
                
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 250, height: 250)
                    .blur(radius: 60)
                    .offset(x: 100, y: 150)
            }
            
            // 3. Blur Layer (Material Overlay)
            if themeManager.isBlurEnabled {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Glass Card
/// 统一配色的玻璃卡片组件，支持魔法配色和客制化配色
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

    /// 当前卡片样式（根据 ThemeManager 配置）
    private var cardStyle: UnifiedColorConfig.CardStyle {
        UnifiedColorConfig.CardStyle.current(from: themeManager)
    }

    var body: some View {
        ZStack {
            // 根据配置选择背景样式
            cardBackground

            // 边框（仅非全透明模式下显示）
            if !isFullyTransparent {
                cardBorder
            }

            content
                .padding(padding)
        }
        .unifiedShadow(.card)
    }
    
    /// 卡片背景
    @ViewBuilder
    private var cardBackground: some View {
        switch cardStyle {
        case .ultraThinMaterial:
            // 优化：低内存设备使用简单颜色
            if ProcessInfo.processInfo.physicalMemory <= 2 * 1024 * 1024 * 1024 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.8))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.9)
            }
        default:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardStyle.backgroundColor(colorScheme: colorScheme))
        }
    }
    
    /// 卡片边框
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: borderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    /// 边框颜色（根据配色模式调整）
    private var borderColors: [Color] {
        let isDark = colorScheme == .dark
        return [
            isDark ? Color.white.opacity(0.3) : Color.white.opacity(0.6),
            isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.1)
        ]
    }
    
    /// 是否为全透明模式
    private var isFullyTransparent: Bool {
        if case .fullyTransparent = cardStyle {
            return true
        }
        return false
    }
}

// MARK: - Text Enhancements
struct OutlinedText: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    var color: Color = .white
    var width: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        if themeManager.backgroundStyle == .image {
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


