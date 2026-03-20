import SwiftUI

extension PetChatSkinTheme {
    func resolvedUserBubbleColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> [Color] {
        guard self == .magic else { return userBubbleColors }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).bubbleUserColors
    }

    func resolvedAssistantStrokeColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> [Color] {
        guard self == .magic else { return assistantStrokeColors }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).bubbleAssistantStrokeColors
    }

    func resolvedPreviewBackgroundColors(themeManager: ThemeManager, colorScheme: ColorScheme) -> [Color] {
        guard self == .magic else { return previewBackgroundColors }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).bubblePreviewBackgroundColors
    }

    func resolvedQuickOptionFill(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return themeManager.accentTextColor.opacity(0.12) }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).quickOptionFill
    }

    func resolvedQuickOptionStroke(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return themeManager.accentTextColor.opacity(0.24) }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).quickOptionStroke
    }

    /// 用户气泡文字颜色 - 根据主题自适应，确保在渐变背景上有足够对比度
    func resolvedUserBubbleTextColor(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return .white }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).bubbleUserTextColor
    }

    /// 快捷选项文字颜色
    func resolvedQuickOptionTextColor(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return themeManager.accentTextColor.mixed(with: .black, amount: 0.15) }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).quickOptionText
    }
}
