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
        guard self == .magic else { return Color.pink.opacity(0.12) }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).quickOptionFill
    }

    func resolvedQuickOptionStroke(themeManager: ThemeManager, colorScheme: ColorScheme) -> Color {
        guard self == .magic else { return Color.pink.opacity(0.24) }
        return MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme).quickOptionStroke
    }
}
