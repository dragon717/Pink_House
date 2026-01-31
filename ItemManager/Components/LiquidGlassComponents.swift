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
    let fillMode: BackgroundFillMode
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            
            switch fillMode {
            case .tile:
                Image(uiImage: image)
                    .resizable(resizingMode: .tile)
                    .opacity(opacity)
            case .fill:
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenSize.width, height: screenSize.height, alignment: .center)
                    .clipped()
                    .opacity(opacity)
            case .fit:
                ZStack {
                    // Fit mode usually needs a background color if it doesn't fill
                    Color.clear 
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: screenSize.width, height: screenSize.height, alignment: .center)
                        .opacity(opacity)
                }
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
                SmartBackgroundImage(
                    image: image,
                    opacity: themeManager.backgroundOpacity,
                    fillMode: themeManager.backgroundFillMode
                )
                
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
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var content: Content
    
    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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


