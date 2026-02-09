import SwiftUI

struct CardBackgroundView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        Group {
            switch themeManager.cardStyle {
            case .solid:
                Color(uiColor: .secondarySystemGroupedBackground)
            case .transparent:
                // Liquid Glass: UltraThin Material + Subtle Border
                ZStack {
                    if themeManager.isBlurEnabled {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    } else {
                        // Fallback: Lighten slightly in both modes to simulate glass
                        glassFallbackColor
                    }
                }
                .opacity(themeManager.transparentOpacity)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: glassBorderColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                
            case .tinted:
                // Acrylic/Mica: Regular Material + Tint Overlay
                ZStack {
                    if themeManager.isBlurEnabled {
                        Rectangle()
                            .fill(.regularMaterial)
                    } else {
                        // Fallback
                        Color(uiColor: .systemBackground).opacity(0.5)
                    }
                    
                    themeManager.cardTintColor
                        .opacity(themeManager.tintOpacity)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: micaBorderColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    private var glassFallbackColor: Color {
        #if DEBUG
        if colorScheme == .dark {
            return Color.black.opacity(themeManager.dbg_glass_fallback_dark)
        } else {
            return Color.white.opacity(themeManager.dbg_glass_fallback_light)
        }
        #else
        if colorScheme == .dark {
            return Color.black.opacity(0.5) // 黑色半透明 0.5
        } else {
            return Color.white.opacity(0.5)
        }
        #endif
    }
    
    private var glassBorderColors: [Color] {
        #if DEBUG
        return [
            .white.opacity(colorScheme == .dark ? themeManager.dbg_glass_border_dark_start : themeManager.dbg_glass_border_light_start),
            .white.opacity(colorScheme == .dark ? themeManager.dbg_glass_border_dark_end : themeManager.dbg_glass_border_light_end)
        ]
        #else
        return [
            .white.opacity(colorScheme == .dark ? 0.25 : 0.4),
            .white.opacity(colorScheme == .dark ? 0.05 : 0.1)
        ]
        #endif
    }
    
    private var micaBorderColors: [Color] {
        #if DEBUG
        return [
            themeManager.cardTintColor.opacity(colorScheme == .dark ? themeManager.dbg_mica_border_dark_start : themeManager.dbg_mica_border_light_start),
            themeManager.cardTintColor.opacity(colorScheme == .dark ? themeManager.dbg_mica_border_dark_end : themeManager.dbg_mica_border_light_end)
        ]
        #else
        return [
            themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.3 : 0.5),
            themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.05 : 0.1)
        ]
        #endif
    }
}
