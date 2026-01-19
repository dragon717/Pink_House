//
//  LiquidGlassComponents.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
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
    
    var body: some View {
        ZStack {
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            if themeManager.backgroundStyle == .image, let image = themeManager.backgroundImage {
                SmartBackgroundImage(image: image, opacity: themeManager.backgroundOpacity)
            }
            
            if themeManager.isBlurEnabled {
                // Orb 1
                Circle()
                    .fill(Color.pink.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: -100, y: -200)
                
                // Orb 2
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 250, height: 250)
                    .blur(radius: 60)
                    .offset(x: 100, y: 150)
            }
        }
    }
}

// MARK: - Glass Card
struct GlassCard<Content: View>: View {
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            
            content
                .padding()
        }
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}


