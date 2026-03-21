import SwiftUI

enum PetChatSkinTheme: String, CaseIterable, Codable, Identifiable, Equatable {
    case classic
    case magic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典皮肤"
        case .magic: return "魔法皮肤"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "保留原有粉白气泡风格"
        case .magic: return "玻璃感 + 魔法渐变 + 更灵动的对话气泡"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .classic: return 20
        case .magic: return 24
        }
    }

    var userBubbleColors: [Color] {
        switch self {
        case .classic:
            return [.pink, .pink]
        case .magic:
            return [
                Color(red: 1.00, green: 0.51, blue: 0.82),
                Color(red: 0.96, green: 0.44, blue: 0.59)
            ]
        }
    }

    var assistantStrokeColors: [Color] {
        switch self {
        case .classic:
            return [Color.clear, Color.clear]
        case .magic:
            return [
                Color(red: 1.0, green: 0.74, blue: 0.86).opacity(0.75),
                Color(red: 0.93, green: 0.80, blue: 1.0).opacity(0.65)
            ]
        }
    }

    var previewBackgroundColors: [Color] {
        switch self {
        case .classic:
            return [
                Color(red: 1.0, green: 0.95, blue: 0.98),
                Color(red: 1.0, green: 0.98, blue: 0.98)
            ]
        case .magic:
            return [
                Color(red: 0.98, green: 0.92, blue: 1.0),
                Color(red: 0.93, green: 0.96, blue: 1.0),
                Color(red: 1.0, green: 0.93, blue: 0.97)
            ]
        }
    }

    // MARK: - 魔法配色适配方法

    /// 获取当前主题预设 - 支持魔法配色和客制化配色两种模式（与 ThemePreviewSection 逻辑一致）
    private static func currentThemePreset(themeManager: ThemeManager, colorScheme: ColorScheme) -> ThemePreset {
        let isDark = colorScheme == .dark
        switch themeManager.colorSchemeMode {
        case .magic:
            // 魔法配色：使用自适应调色板生成主题，使用 cardTintColor 作为强调色
            return ThemePreset.fromAdaptivePalette(
                themeManager.adaptivePalette,
                cardBackground: themeManager.cardBackgroundColor,
                isDarkMode: isDark,
                accentColor: themeManager.cardTintColor
            )
        case .custom:
            // 客制化配色：使用当前自定义主题
            return themeManager.themeColorConfig.currentTheme(forDarkMode: isDark)
        }
    }

    /// 获取当前主题颜色 - 支持魔法配色和客制化配色两种模式
    private static func currentThemeColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> (
        primary: Color, secondary: Color, tertiary: Color, accent: Color,
        cardBackground: Color, cardAccent: Color
    ) {
        let isDark = colorScheme == .dark
        let theme = Self.currentThemePreset(themeManager: themeManager, colorScheme: colorScheme)
        let textColors = theme.textColors(forDarkMode: isDark)
        let cardColors = theme.cardColors(forDarkMode: isDark)

        return (
            primary: textColors.primary.color,
            secondary: textColors.secondary.color,
            tertiary: textColors.tertiary.color,
            accent: textColors.accent.color,
            cardBackground: cardColors.backgroundRGBA.color,
            cardAccent: cardColors.accentRGBA.color
        )
    }

    func resolvedUserBubbleColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> [Color] {
        guard self == .magic else { return userBubbleColors }
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        let isDark = colorScheme == .dark
        let bubbleStart = colors.accent.mixed(with: .white, amount: isDark ? 0.10 : 0.06)
        let bubbleEnd = colors.cardAccent.mixed(with: .black, amount: isDark ? 0.08 : 0.03)
        return [bubbleStart, bubbleEnd]
    }

    func resolvedAssistantStrokeColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> [Color] {
        guard self == .magic else { return assistantStrokeColors }
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        let isDark = colorScheme == .dark
        return [
            colors.accent.opacity(isDark ? 0.58 : 0.44),
            colors.cardAccent.opacity(isDark ? 0.48 : 0.34)
        ]
    }

    func resolvedPreviewBackgroundColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> [Color] {
        guard self == .magic else { return previewBackgroundColors }
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        let isDark = colorScheme == .dark
        return [
            colors.cardBackground.mixed(with: colors.accent, amount: isDark ? 0.14 : 0.08),
            colors.cardBackground.mixed(with: colors.cardAccent, amount: isDark ? 0.18 : 0.10),
            colors.cardBackground.mixed(with: .white, amount: isDark ? 0.10 : 0.22)
        ]
    }

    func resolvedQuickOptionFill(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return themeManager.accentTextColor.opacity(0.12) }
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.accent.opacity(colorScheme == .dark ? 0.20 : 0.12)
    }

    func resolvedQuickOptionStroke(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return themeManager.accentTextColor.opacity(0.24) }
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.accent.opacity(colorScheme == .dark ? 0.45 : 0.28)
    }

    /// 用户气泡文字颜色 - 根据主题自适应，确保在渐变背景上有足够对比度
    func resolvedUserBubbleTextColor(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return .white }
        return .white
    }

    /// 快捷选项文字颜色
    func resolvedQuickOptionTextColor(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return themeManager.accentTextColor.mixed(with: .black, amount: 0.15) }
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.accent.mixed(with: .black, amount: colorScheme == .dark ? 0.0 : 0.08)
    }

    /// 萌宠气泡背景颜色 - 使用卡片背景色适配魔法配色
    func resolvedAssistantBubbleBackground(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else {
            // 经典皮肤使用系统背景色
            return Color(.systemBackground)
        }
        // 魔法皮肤使用主题卡片背景色
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.cardBackground
    }

    /// 萌宠气泡文字颜色 - 使用主题主文字色
    func resolvedAssistantBubbleTextColor(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else {
            // 经典皮肤使用系统主文字色
            return .primary
        }
        // 魔法皮肤使用主题主文字色
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.primary
    }

    /// 萌宠气泡内卡片背景色 - 用于衣橱卡片、统计卡片等
    func resolvedAssistantCardBackground(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else {
            // 经典皮肤使用系统次要背景色
            return Color(.secondarySystemBackground)
        }
        // 魔法皮肤使用主题卡片强调色
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.cardAccent.opacity(colorScheme == .dark ? 0.3 : 0.2)
    }

    /// 萌宠气泡内强调色 - 用于价格、图标等
    func resolvedAssistantAccentColor(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else {
            // 经典皮肤使用粉色
            return .pink
        }
        // 魔法皮肤使用主题强调色
        let colors = Self.currentThemeColors(themeManager: themeManager, colorScheme: colorScheme)
        return colors.accent
    }
}
