import SwiftUI
import UIKit

/// 魔法配色设计系统：将当前主题配置映射为统一的语义化 UI 颜色。
struct MagicThemePalette {
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color

    let cardBackground: Color
    let cardAccent: Color

    let navigationBackground: Color
    let navigationForeground: Color

    let segmentedBackground: Color
    let segmentedSelectedBackground: Color
    let segmentedSelectedForeground: Color

    let quickOptionFill: Color
    let quickOptionStroke: Color
    let quickOptionText: Color

    let bubbleUserColors: [Color]
    let bubbleAssistantStrokeColors: [Color]
    let bubblePreviewBackgroundColors: [Color]
}

enum MagicThemeDesignSystem {
    static func palette(themeManager: ThemeManager, colorScheme: ColorScheme) -> MagicThemePalette {
        let isDark = colorScheme == .dark
        let theme = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark)
        let text = theme.textColors(forDarkMode: isDark)
        let card = theme.cardColors(forDarkMode: isDark)

        let accent = text.accent.color
        let cardAccent = card.accentRGBA.color
        let cardBackground = card.backgroundRGBA.color

        let navigationBackground: Color = {
            switch themeManager.cardStyle {
            case .tinted:
                return cardAccent.opacity(isDark ? 0.34 : 0.24)
            case .transparent:
                return cardBackground.opacity(isDark ? 0.88 : 0.78)
            case .fullyTransparent:
                return cardBackground.opacity(isDark ? 0.70 : 0.56)
            case .solid:
                return cardBackground.opacity(isDark ? 0.94 : 0.90)
            }
        }()

        let bubbleStart = accent.mixed(with: .white, amount: isDark ? 0.10 : 0.06)
        let bubbleEnd = cardAccent.mixed(with: .black, amount: isDark ? 0.08 : 0.03)

        return MagicThemePalette(
            primaryText: text.primary.color,
            secondaryText: text.secondary.color,
            tertiaryText: text.tertiary.color,
            accent: accent,
            cardBackground: cardBackground,
            cardAccent: cardAccent,
            navigationBackground: navigationBackground,
            navigationForeground: navigationBackground.contrastColor,
            segmentedBackground: cardAccent.opacity(isDark ? 0.22 : 0.14),
            segmentedSelectedBackground: cardBackground.mixed(with: .white, amount: isDark ? 0.08 : 0.18),
            segmentedSelectedForeground: text.primary.color,
            quickOptionFill: accent.opacity(isDark ? 0.20 : 0.12),
            quickOptionStroke: accent.opacity(isDark ? 0.45 : 0.28),
            quickOptionText: accent.mixed(with: .black, amount: isDark ? 0.0 : 0.08),
            bubbleUserColors: [bubbleStart, bubbleEnd],
            bubbleAssistantStrokeColors: [
                accent.opacity(isDark ? 0.58 : 0.44),
                cardAccent.opacity(isDark ? 0.48 : 0.34)
            ],
            bubblePreviewBackgroundColors: [
                cardBackground.mixed(with: accent, amount: isDark ? 0.14 : 0.08),
                cardBackground.mixed(with: cardAccent, amount: isDark ? 0.18 : 0.10),
                cardBackground.mixed(with: .white, amount: isDark ? 0.10 : 0.22)
            ]
        )
    }
}

extension Color {
    /// 简单颜色混合，用于构建同一主题下的渐变层级。
    func mixed(with other: Color, amount: Double) -> Color {
        let t = CGFloat(min(max(amount, 0), 1))
        let lhs = UIColor(self)
        let rhs = UIColor(other)

        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0

        guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
              rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else {
            return self
        }

        let r = lr + (rr - lr) * t
        let g = lg + (rg - lg) * t
        let b = lb + (rb - lb) * t
        let a = la + (ra - la) * t
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}
