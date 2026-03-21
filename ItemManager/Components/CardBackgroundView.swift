import SwiftUI

struct CardBackgroundView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            switch themeManager.cardStyle {
            case .solid:
                // 实色模式：使用主题色系统中的卡片背景颜色
                // 根据当前配色模式动态计算卡片背景色
                magicCardBackgroundColor
            case .fullyTransparent:
                Color.clear
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
                // 色调模式：使用卡片背景色 + 色调强度透明度
                // 与主题预览中的豆腐块实现保持一致
                magicCardBackgroundColor
                    .opacity(themeManager.tintOpacity)
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
    
    /// 魔法配色下的卡片背景色 - 基于用户设置的背景色动态计算
    private var magicCardBackgroundColor: Color {
        // 客制化配色模式：使用预设主题的卡片背景色
        if themeManager.colorSchemeMode == .custom {
            let isDark = colorScheme == .dark
            let cardColors = themeManager.themeColorConfig.customColorConfig.currentCustom.cardColors(forDarkMode: isDark)
            return cardColors.backgroundRGBA.color
        }
        
        // 魔法配色模式：基于用户设置的背景色生成卡片背景色
        let isDark = colorScheme == .dark
        let bgColor = themeManager.backgroundColor
        
        if isDark {
            // 暗夜模式：比背景色稍亮一点，增加层次感
            return bgColor.opacity(0.9)
        } else {
            // 亮色模式：使用半透明白色，与背景色融合
            if bgColor.isDark {
                return Color.white.opacity(0.95)
            } else {
                return Color.white.opacity(0.85)
            }
        }
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
