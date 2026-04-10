//
//  AdaptiveColorSystemV2.swift
//  ItemManager
//
//  魔法配色系统 V2 - 支持暗夜模式、卡片就近配色、持久化
//

import SwiftUI
import UIKit

// MARK: - 配色模式枚举
enum ColorSchemeMode: String, Codable, CaseIterable {
    case magic = "magic"           // 魔法配色（智能）
    case custom = "custom"         // 客制化配色

    var displayName: String {
        switch self {
        case .magic: return "魔法配色"
        case .custom: return "客制化配色"
        }
    }
}

// MARK: - 卡片配色配置
struct CardColorConfig: Codable {
    // 卡片背景色
    var backgroundRGBA: ColorRGBA
    // 卡片强调色（用于标签、按钮等）
    var accentRGBA: ColorRGBA
    // 卡片次要色
    var secondaryRGBA: ColorRGBA
    // 定金标记色
    var depositRGBA: ColorRGBA
    // 尾款标记色
    var finalPaymentRGBA: ColorRGBA

    // 默认配置
    static let `default` = CardColorConfig(
        backgroundRGBA: ColorRGBA(r: 1.0, g: 0.94, b: 0.96), // 薰衣草淡粉
        accentRGBA: ColorRGBA(r: 0.85, g: 0.75, b: 0.85),    // 蓟色
        secondaryRGBA: ColorRGBA(r: 0.9, g: 0.9, b: 0.9),    // 浅灰
        depositRGBA: ColorRGBA(r: 1.0, g: 0.84, b: 0.0),     // 金色
        finalPaymentRGBA: ColorRGBA(r: 1.0, g: 0.41, b: 0.71) // 热粉
    )

    // 莫妮卡主题
    static let monica = CardColorConfig(
        backgroundRGBA: ColorRGBA(r: 1.0, g: 0.94, b: 0.96),
        accentRGBA: ColorRGBA(r: 0.85, g: 0.75, b: 0.85),
        secondaryRGBA: ColorRGBA(r: 0.96, g: 0.9, b: 0.94),
        depositRGBA: ColorRGBA(r: 1.0, g: 0.84, b: 0.0),
        finalPaymentRGBA: ColorRGBA(r: 1.0, g: 0.41, b: 0.71)
    )

    // 灰姑娘主题
    static let cinderella = CardColorConfig(
        backgroundRGBA: ColorRGBA(r: 0.94, g: 0.97, b: 1.0),
        accentRGBA: ColorRGBA(r: 0.53, g: 0.81, b: 0.92),
        secondaryRGBA: ColorRGBA(r: 0.9, g: 0.94, b: 0.98),
        depositRGBA: ColorRGBA(r: 1.0, g: 0.65, b: 0.0),
        finalPaymentRGBA: ColorRGBA(r: 0.25, g: 0.41, b: 0.88)
    )

    // 抹茶拿铁主题
    static let matcha = CardColorConfig(
        backgroundRGBA: ColorRGBA(r: 0.94, g: 1.0, b: 0.94),
        accentRGBA: ColorRGBA(r: 0.6, g: 0.98, b: 0.6),
        secondaryRGBA: ColorRGBA(r: 0.9, g: 0.96, b: 0.9),
        depositRGBA: ColorRGBA(r: 0.85, g: 0.65, b: 0.13),
        finalPaymentRGBA: ColorRGBA(r: 0.13, g: 0.55, b: 0.13)
    )

    // 哥特人偶主题
    static let gothic = CardColorConfig(
        backgroundRGBA: ColorRGBA(r: 0.15, g: 0.15, b: 0.15),
        accentRGBA: ColorRGBA(r: 0.5, g: 0.0, b: 0.0),
        secondaryRGBA: ColorRGBA(r: 0.25, g: 0.25, b: 0.25),
        depositRGBA: ColorRGBA(r: 0.8, g: 0.8, b: 0.8),
        finalPaymentRGBA: ColorRGBA(r: 0.8, g: 0.0, b: 0.0)
    )
}

// MARK: - 完整主题方案
struct ThemePreset: Codable, Identifiable {
    let id: String
    let name: String
    // 字体配色
    var textPrimaryRGBA: ColorRGBA
    var textSecondaryRGBA: ColorRGBA
    var textTertiaryRGBA: ColorRGBA
    var textAccentRGBA: ColorRGBA
    // 卡片配色
    var cardConfig: CardColorConfig
    // 是否支持暗夜模式变体
    var supportsDarkMode: Bool

    // 暗夜模式配色（可选）
    var darkTextPrimaryRGBA: ColorRGBA?
    var darkTextSecondaryRGBA: ColorRGBA?
    var darkTextTertiaryRGBA: ColorRGBA?
    var darkTextAccentRGBA: ColorRGBA?
    var darkCardConfig: CardColorConfig?

    // 获取指定模式下的字体配色
    func textColors(forDarkMode isDark: Bool) -> (primary: ColorRGBA, secondary: ColorRGBA, tertiary: ColorRGBA, accent: ColorRGBA) {
        if isDark && supportsDarkMode {
            return (
                darkTextPrimaryRGBA ?? textPrimaryRGBA,
                darkTextSecondaryRGBA ?? textSecondaryRGBA,
                darkTextTertiaryRGBA ?? textTertiaryRGBA,
                darkTextAccentRGBA ?? textAccentRGBA
            )
        }
        return (textPrimaryRGBA, textSecondaryRGBA, textTertiaryRGBA, textAccentRGBA)
    }

    // 获取指定模式下的卡片配色
    func cardColors(forDarkMode isDark: Bool) -> CardColorConfig {
        if isDark && supportsDarkMode {
            return darkCardConfig ?? cardConfig
        }
        return cardConfig
    }

    /// 从自适应调色板创建主题预设（用于魔法配色预览）
    static func fromAdaptivePalette(_ palette: AdaptivePalette, cardBackground: Color, isDarkMode: Bool, accentColor: Color) -> ThemePreset {
        // 将 Color 转换为 ColorRGBA
        let primaryRGBA = palette.primary.rgba ?? ColorRGBA(r: 0, g: 0, b: 0)
        let secondaryRGBA = palette.secondary.rgba ?? ColorRGBA(r: 0.3, g: 0.3, b: 0.3)
        let tertiaryRGBA = palette.tertiary.rgba ?? ColorRGBA(r: 0.5, g: 0.5, b: 0.5)
        let accentRGBA = accentColor.rgba ?? ColorRGBA(r: 1, g: 0.4, b: 0.7)
        let cardBgRGBA = cardBackground.rgba ?? ColorRGBA(r: 1, g: 1, b: 1)

        let cardConfig = CardColorConfig(
            backgroundRGBA: cardBgRGBA,
            accentRGBA: accentRGBA,
            secondaryRGBA: secondaryRGBA,
            depositRGBA: ColorRGBA(r: 1.0, g: 0.84, b: 0.0), // 金色
            finalPaymentRGBA: ColorRGBA(r: 1.0, g: 0.41, b: 0.71) // 热粉
        )

        // 暗夜模式颜色
        let darkPrimaryRGBA = isDarkMode ? primaryRGBA : ColorRGBA(r: 1, g: 1, b: 1)
        let darkSecondaryRGBA = isDarkMode ? secondaryRGBA : ColorRGBA(r: 0.85, g: 0.85, b: 0.85)
        let darkTertiaryRGBA = isDarkMode ? tertiaryRGBA : ColorRGBA(r: 0.6, g: 0.6, b: 0.6)
        let darkAccentRGBA = isDarkMode ? accentRGBA : ColorRGBA(r: 0.9, g: 0.7, b: 0.85)
        let darkCardBgRGBA = isDarkMode ? cardBgRGBA : ColorRGBA(r: 0.25, g: 0.2, b: 0.28)

        let darkCardConfig = CardColorConfig(
            backgroundRGBA: darkCardBgRGBA,
            accentRGBA: darkAccentRGBA,
            secondaryRGBA: darkSecondaryRGBA,
            depositRGBA: ColorRGBA(r: 1.0, g: 0.84, b: 0.0),
            finalPaymentRGBA: ColorRGBA(r: 1.0, g: 0.41, b: 0.71)
        )

        return ThemePreset(
            id: "magic_adaptive",
            name: "魔法配色",
            textPrimaryRGBA: primaryRGBA,
            textSecondaryRGBA: secondaryRGBA,
            textTertiaryRGBA: tertiaryRGBA,
            textAccentRGBA: accentRGBA,
            cardConfig: cardConfig,
            supportsDarkMode: true,
            darkTextPrimaryRGBA: darkPrimaryRGBA,
            darkTextSecondaryRGBA: darkSecondaryRGBA,
            darkTextTertiaryRGBA: darkTertiaryRGBA,
            darkTextAccentRGBA: darkAccentRGBA,
            darkCardConfig: darkCardConfig
        )
    }
}

// MARK: - 用户自定义配色方案
struct UserCustomTheme: Codable, Identifiable {
    let id: String
    var name: String
    // 亮色模式配色
    var textPrimaryRGBA: ColorRGBA
    var textSecondaryRGBA: ColorRGBA
    var textTertiaryRGBA: ColorRGBA
    var textAccentRGBA: ColorRGBA
    var cardConfig: CardColorConfig
    // 暗夜模式配色
    var darkTextPrimaryRGBA: ColorRGBA
    var darkTextSecondaryRGBA: ColorRGBA
    var darkTextTertiaryRGBA: ColorRGBA
    var darkTextAccentRGBA: ColorRGBA
    var darkCardConfig: CardColorConfig
    // 创建时间
    let createdAt: Date
    var updatedAt: Date

    /// 获取指定模式下的字体配色
    func textColors(forDarkMode isDark: Bool) -> (primary: ColorRGBA, secondary: ColorRGBA, tertiary: ColorRGBA, accent: ColorRGBA) {
        if isDark {
            return (darkTextPrimaryRGBA, darkTextSecondaryRGBA, darkTextTertiaryRGBA, darkTextAccentRGBA)
        }
        return (textPrimaryRGBA, textSecondaryRGBA, textTertiaryRGBA, textAccentRGBA)
    }

    /// 获取指定模式下的卡片配色
    func cardColors(forDarkMode isDark: Bool) -> CardColorConfig {
        if isDark {
            return darkCardConfig
        }
        return cardConfig
    }

    /// 转换为ThemePreset
    func toThemePreset() -> ThemePreset {
        ThemePreset(
            id: id,
            name: name,
            textPrimaryRGBA: textPrimaryRGBA,
            textSecondaryRGBA: textSecondaryRGBA,
            textTertiaryRGBA: textTertiaryRGBA,
            textAccentRGBA: textAccentRGBA,
            cardConfig: cardConfig,
            supportsDarkMode: true,
            darkTextPrimaryRGBA: darkTextPrimaryRGBA,
            darkTextSecondaryRGBA: darkTextSecondaryRGBA,
            darkTextTertiaryRGBA: darkTextTertiaryRGBA,
            darkTextAccentRGBA: darkTextAccentRGBA,
            darkCardConfig: darkCardConfig
        )
    }
}

// MARK: - 客制化配色配置
struct CustomColorConfig: Codable {
    // 当前选中的预设方案ID（4个预设之一或nil表示使用自定义）
    var selectedPresetId: String?
    // 用户保存的自定义方案列表
    var userCustomThemes: [UserCustomTheme]
    // 当前正在使用的自定义配色（当selectedPresetId为nil时使用）
    var currentCustom: UserCustomTheme

    // 默认配置（莫妮卡粉作为App默认主题）
    static let `default` = CustomColorConfig(
        selectedPresetId: "monica_pink", // 默认选中莫妮卡粉
        userCustomThemes: [],
        currentCustom: UserCustomTheme(
            id: "custom_current",
            name: "自定义",
            textPrimaryRGBA: ColorRGBA(r: 0.369, g: 0.337, b: 0.353),
            textSecondaryRGBA: ColorRGBA(r: 0.541, g: 0.502, b: 0.525),
            textTertiaryRGBA: ColorRGBA(r: 0.714, g: 0.667, b: 0.690),
            textAccentRGBA: ColorRGBA(r: 0.851, g: 0.663, b: 0.737),
            cardConfig: CardColorConfig(
                backgroundRGBA: ColorRGBA(r: 0.988, g: 0.980, b: 0.984),
                accentRGBA: ColorRGBA(r: 0.878, g: 0.722, b: 0.784),
                secondaryRGBA: ColorRGBA(r: 0.980, g: 0.976, b: 0.980),
                depositRGBA: ColorRGBA(r: 1.0, g: 0.84, b: 0.0),
                finalPaymentRGBA: ColorRGBA(r: 1.0, g: 0.41, b: 0.71)
            ),
            darkTextPrimaryRGBA: ColorRGBA(r: 0.95, g: 0.85, b: 0.90),
            darkTextSecondaryRGBA: ColorRGBA(r: 0.80, g: 0.70, b: 0.75),
            darkTextTertiaryRGBA: ColorRGBA(r: 0.65, g: 0.55, b: 0.60),
            darkTextAccentRGBA: ColorRGBA(r: 1.0, g: 0.60, b: 0.75),
            darkCardConfig: CardColorConfig(
                backgroundRGBA: ColorRGBA(r: 0.35, g: 0.20, b: 0.28),
                accentRGBA: ColorRGBA(r: 0.90, g: 0.50, b: 0.65),
                secondaryRGBA: ColorRGBA(r: 0.45, g: 0.30, b: 0.38),
                depositRGBA: ColorRGBA(r: 0.9, g: 0.75, b: 0.2),
                finalPaymentRGBA: ColorRGBA(r: 0.95, g: 0.5, b: 0.75)
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
    )

    /// 获取当前主题
    func currentTheme(forDarkMode isDark: Bool) -> ThemePreset {
        // 如果有选中的预设，返回预设
        if let presetId = selectedPresetId,
           let preset = CustomColorPresets.all.first(where: { $0.id == presetId }) {
            return preset
        }
        // 否则返回当前自定义配置
        return currentCustom.toThemePreset()
    }

    /// 保存当前配置为新方案
    mutating func saveAsNewTheme(name: String) -> UserCustomTheme {
        let newTheme = UserCustomTheme(
            id: UUID().uuidString,
            name: name,
            textPrimaryRGBA: currentCustom.textPrimaryRGBA,
            textSecondaryRGBA: currentCustom.textSecondaryRGBA,
            textTertiaryRGBA: currentCustom.textTertiaryRGBA,
            textAccentRGBA: currentCustom.textAccentRGBA,
            cardConfig: currentCustom.cardConfig,
            darkTextPrimaryRGBA: currentCustom.darkTextPrimaryRGBA,
            darkTextSecondaryRGBA: currentCustom.darkTextSecondaryRGBA,
            darkTextTertiaryRGBA: currentCustom.darkTextTertiaryRGBA,
            darkTextAccentRGBA: currentCustom.darkTextAccentRGBA,
            darkCardConfig: currentCustom.darkCardConfig,
            createdAt: Date(),
            updatedAt: Date()
        )
        userCustomThemes.append(newTheme)
        return newTheme
    }

    /// 删除自定义方案
    mutating func deleteCustomTheme(id: String) {
        userCustomThemes.removeAll { $0.id == id }
    }

    /// 更新当前自定义配色
    mutating func updateCurrentCustom(_ theme: UserCustomTheme) {
        currentCustom = theme
        selectedPresetId = nil // 切换到自定义模式
    }
}

// MARK: - 客制化配色预设方案（5个梦群日历主题）
enum CustomColorPresets {
    // 莫妮卡粉主题（App默认）- 柔和的粉红色调
    static let monicaPink = ThemePreset(
        id: "monica_pink",
        name: "莫妮卡粉",
        textPrimaryRGBA: ColorRGBA(r: 0.369, g: 0.337, b: 0.353),
        textSecondaryRGBA: ColorRGBA(r: 0.541, g: 0.502, b: 0.525),
        textTertiaryRGBA: ColorRGBA(r: 0.714, g: 0.667, b: 0.690),
        textAccentRGBA: ColorRGBA(r: 0.851, g: 0.663, b: 0.737),
        cardConfig: CardColorConfig(
            backgroundRGBA: ColorRGBA(r: 0.988, g: 0.980, b: 0.984),
            accentRGBA: ColorRGBA(r: 0.878, g: 0.722, b: 0.784),
            secondaryRGBA: ColorRGBA(r: 0.980, g: 0.976, b: 0.980),
            depositRGBA: ColorRGBA(r: 1.0, g: 0.84, b: 0.0),
            finalPaymentRGBA: ColorRGBA(r: 1.0, g: 0.41, b: 0.71)
        ),
        supportsDarkMode: true,
        darkTextPrimaryRGBA: ColorRGBA(r: 0.95, g: 0.85, b: 0.90),
        darkTextSecondaryRGBA: ColorRGBA(r: 0.80, g: 0.70, b: 0.75),
        darkTextTertiaryRGBA: ColorRGBA(r: 0.65, g: 0.55, b: 0.60),
        darkTextAccentRGBA: ColorRGBA(r: 1.0, g: 0.60, b: 0.75),
        darkCardConfig: CardColorConfig(
            backgroundRGBA: ColorRGBA(r: 0.35, g: 0.20, b: 0.28),
            accentRGBA: ColorRGBA(r: 0.90, g: 0.50, b: 0.65),
            secondaryRGBA: ColorRGBA(r: 0.45, g: 0.30, b: 0.38),
            depositRGBA: ColorRGBA(r: 0.9, g: 0.75, b: 0.2),
            finalPaymentRGBA: ColorRGBA(r: 0.95, g: 0.5, b: 0.75)
        )
    )

    // 莫妮卡紫主题（原莫妮卡）- 薰衣草紫色调
    static let monicaPurple = ThemePreset(
        id: "monica_purple",
        name: "莫妮卡紫",
        textPrimaryRGBA: ColorRGBA(r: 0.42, g: 0.36, b: 0.45),
        textSecondaryRGBA: ColorRGBA(r: 0.61, g: 0.54, b: 0.65),
        textTertiaryRGBA: ColorRGBA(r: 0.77, g: 0.71, b: 0.80),
        textAccentRGBA: ColorRGBA(r: 0.85, g: 0.65, b: 0.78),
        cardConfig: CardColorConfig.monica,
        supportsDarkMode: true,
        darkTextPrimaryRGBA: ColorRGBA(r: 0.88, g: 0.84, b: 0.90),
        darkTextSecondaryRGBA: ColorRGBA(r: 0.70, g: 0.65, b: 0.75),
        darkTextTertiaryRGBA: ColorRGBA(r: 0.55, g: 0.50, b: 0.60),
        darkTextAccentRGBA: ColorRGBA(r: 0.90, g: 0.70, b: 0.85),
        darkCardConfig: CardColorConfig(
            backgroundRGBA: ColorRGBA(r: 0.25, g: 0.20, b: 0.28),
            accentRGBA: ColorRGBA(r: 0.70, g: 0.60, b: 0.75),
            secondaryRGBA: ColorRGBA(r: 0.35, g: 0.30, b: 0.38),
            depositRGBA: ColorRGBA(r: 0.9, g: 0.75, b: 0.2),
            finalPaymentRGBA: ColorRGBA(r: 0.95, g: 0.5, b: 0.75)
        )
    )

    // 灰姑娘主题（水蓝色调）
    static let cinderella = ThemePreset(
        id: "cinderella",
        name: "灰姑娘",
        textPrimaryRGBA: ColorRGBA(r: 0.17, g: 0.37, b: 0.49),
        textSecondaryRGBA: ColorRGBA(r: 0.36, g: 0.62, b: 0.71),
        textTertiaryRGBA: ColorRGBA(r: 0.56, g: 0.77, b: 0.85),
        textAccentRGBA: ColorRGBA(r: 0.53, g: 0.81, b: 0.92),
        cardConfig: CardColorConfig.cinderella,
        supportsDarkMode: true,
        darkTextPrimaryRGBA: ColorRGBA(r: 0.80, g: 0.90, b: 0.95),
        darkTextSecondaryRGBA: ColorRGBA(r: 0.60, g: 0.75, b: 0.85),
        darkTextTertiaryRGBA: ColorRGBA(r: 0.45, g: 0.60, b: 0.70),
        darkTextAccentRGBA: ColorRGBA(r: 0.65, g: 0.85, b: 0.95),
        darkCardConfig: CardColorConfig(
            backgroundRGBA: ColorRGBA(r: 0.15, g: 0.25, b: 0.35),
            accentRGBA: ColorRGBA(r: 0.45, g: 0.70, b: 0.85),
            secondaryRGBA: ColorRGBA(r: 0.25, g: 0.35, b: 0.45),
            depositRGBA: ColorRGBA(r: 0.9, g: 0.6, b: 0.1),
            finalPaymentRGBA: ColorRGBA(r: 0.4, g: 0.6, b: 0.95)
        )
    )

    // 抹茶拿铁主题（绿色调）
    static let matcha = ThemePreset(
        id: "matcha",
        name: "抹茶拿铁",
        textPrimaryRGBA: ColorRGBA(r: 0.24, g: 0.36, b: 0.24),
        textSecondaryRGBA: ColorRGBA(r: 0.42, g: 0.56, b: 0.42),
        textTertiaryRGBA: ColorRGBA(r: 0.61, g: 0.75, b: 0.61),
        textAccentRGBA: ColorRGBA(r: 0.24, g: 0.71, b: 0.54),
        cardConfig: CardColorConfig.matcha,
        supportsDarkMode: true,
        darkTextPrimaryRGBA: ColorRGBA(r: 0.85, g: 0.92, b: 0.85),
        darkTextSecondaryRGBA: ColorRGBA(r: 0.65, g: 0.78, b: 0.65),
        darkTextTertiaryRGBA: ColorRGBA(r: 0.50, g: 0.63, b: 0.50),
        darkTextAccentRGBA: ColorRGBA(r: 0.55, g: 0.85, b: 0.70),
        darkCardConfig: CardColorConfig(
            backgroundRGBA: ColorRGBA(r: 0.18, g: 0.28, b: 0.18),
            accentRGBA: ColorRGBA(r: 0.55, g: 0.85, b: 0.55),
            secondaryRGBA: ColorRGBA(r: 0.28, g: 0.38, b: 0.28),
            depositRGBA: ColorRGBA(r: 0.85, g: 0.70, b: 0.25),
            finalPaymentRGBA: ColorRGBA(r: 0.35, g: 0.75, b: 0.35)
        )
    )

    // 哥特人偶主题（暗红黑色调）
    static let gothic = ThemePreset(
        id: "gothic",
        name: "哥特人偶",
        textPrimaryRGBA: ColorRGBA(r: 0.88, g: 0.88, b: 0.88),
        textSecondaryRGBA: ColorRGBA(r: 0.63, g: 0.63, b: 0.63),
        textTertiaryRGBA: ColorRGBA(r: 0.44, g: 0.44, b: 0.44),
        textAccentRGBA: ColorRGBA(r: 0.80, g: 0.0, b: 0.0),
        cardConfig: CardColorConfig.gothic,
        supportsDarkMode: true,
        darkTextPrimaryRGBA: ColorRGBA(r: 0.90, g: 0.90, b: 0.90),
        darkTextSecondaryRGBA: ColorRGBA(r: 0.70, g: 0.70, b: 0.70),
        darkTextTertiaryRGBA: ColorRGBA(r: 0.50, g: 0.50, b: 0.50),
        darkTextAccentRGBA: ColorRGBA(r: 0.90, g: 0.20, b: 0.20),
        darkCardConfig: CardColorConfig.gothic
    )

    // 所有预设（莫妮卡粉作为默认排在第一位）
    static let all: [ThemePreset] = [monicaPink, monicaPurple, cinderella, matcha, gothic]
}

// MARK: - 主题配色配置（持久化）
struct ThemeColorConfig: Codable {
    // 配色模式
    var colorSchemeMode: ColorSchemeMode

    // 客制化配色配置（新增）
    var customColorConfig: CustomColorConfig

    // 是否跟随系统暗夜模式
    var followSystemDarkMode: Bool

    // 默认配置
    static let `default` = ThemeColorConfig(
        colorSchemeMode: .custom,
        customColorConfig: CustomColorConfig.default,
        followSystemDarkMode: true
    )

    // 获取当前主题
    func currentTheme(forDarkMode isDark: Bool) -> ThemePreset {
        customColorConfig.currentTheme(forDarkMode: isDark)
    }

    // 获取所有可选主题（4个预设 + 用户自定义方案）
    func allAvailableThemes() -> [ThemePreset] {
        var themes = CustomColorPresets.all
        themes.append(contentsOf: customColorConfig.userCustomThemes.map { $0.toThemePreset() })
        return themes
    }
}

// MARK: - RGBA颜色结构（备份兼容）
struct ColorRGBA: Codable, Equatable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double
    
    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    var color: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
    
    // 预设颜色
    static let black = ColorRGBA(r: 0, g: 0, b: 0)
    static let white = ColorRGBA(r: 1, g: 1, b: 1)
    static let gray = ColorRGBA(r: 0.5, g: 0.5, b: 0.5)
    static let lightGray = ColorRGBA(r: 0.7, g: 0.7, b: 0.7)
    static let pink = ColorRGBA(r: 1, g: 0.4, b: 0.7)
}

// MARK: - 扩展Color转RGBA
extension Color {
    var rgba: ColorRGBA? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return ColorRGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}

// MARK: - 容器背景类型
enum ContainerBackgroundType {
    case ultraThinMaterial      // 超薄材质（毛玻璃）
    case thinMaterial           // 薄材质
    case regularMaterial        // 常规材质
    case thickMaterial          // 厚材质
    case solid(color: Color)    // 纯色
    case custom(opacity: Double) // 自定义透明度
    
    /// 判断容器背景是亮还是暗
    var isDark: Bool {
        switch self {
        case .ultraThinMaterial, .thinMaterial:
            // 材质背景跟随系统外观
            return UITraitCollection.current.userInterfaceStyle == .dark
        case .regularMaterial, .thickMaterial:
            return UITraitCollection.current.userInterfaceStyle == .dark
        case .solid(let color):
            return color.isDark
        case .custom:
            // 自定义透明度默认假设是毛玻璃效果
            return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }
}

// MARK: - 智能调色板 V2
struct AdaptivePaletteV2 {
    let primary: Color       // 主标题
    let secondary: Color     // 副标题
    let tertiary: Color      // 辅助文字
    let accent: Color        // 强调色
    let disabled: Color      // 禁用色
    let divider: Color       // 分割线
    
    /// 根据背景生成调色板
    static func generate(
        from background: Color,
        isDark: Bool? = nil,
        accentColor: Color = .pink,
        containerBackground: ContainerBackgroundType? = nil
    ) -> AdaptivePaletteV2 {
        // 如果提供了容器背景，优先使用容器的亮度
        let isDarkBackground: Bool
        if let container = containerBackground {
            isDarkBackground = container.isDark
        } else if let dark = isDark {
            isDarkBackground = dark
        } else {
            isDarkBackground = background.isDark
        }
        
        let baseColor: Color = isDarkBackground ? .white : .black
        
        return AdaptivePaletteV2(
            primary: baseColor,
            secondary: baseColor.opacity(isDarkBackground ? 0.85 : 0.75),
            tertiary: baseColor.opacity(isDarkBackground ? 0.60 : 0.50),
            accent: accentColor,
            disabled: baseColor.opacity(0.30),
            divider: baseColor.opacity(isDarkBackground ? 0.20 : 0.15)
        )
    }
    
    /// 从RGBA生成
    static func fromRGBA(
        primary: ColorRGBA,
        secondary: ColorRGBA,
        tertiary: ColorRGBA,
        accent: ColorRGBA
    ) -> AdaptivePaletteV2 {
        AdaptivePaletteV2(
            primary: primary.color,
            secondary: secondary.color,
            tertiary: tertiary.color,
            accent: accent.color,
            disabled: ColorRGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5).color,
            divider: ColorRGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.2).color
        )
    }
}

// MARK: - 卡片就近配色修饰器
struct ContainerAdaptiveColorModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    let containerBackground: ContainerBackgroundType
    let overrideAccent: Color?
    
    func body(content: Content) -> some View {
        let palette = themeManager.getPaletteForContainer(
            containerBackground: containerBackground,
            colorScheme: colorScheme,
            overrideAccent: overrideAccent
        )
        
        content
            .environment(\.containerPalette, palette)
    }
}

// MARK: - 环境值键
private struct ContainerPaletteKey: EnvironmentKey {
    static let defaultValue: AdaptivePaletteV2 = AdaptivePaletteV2(
        primary: Color.primary,
        secondary: Color.secondary,
        tertiary: Color.gray,
        accent: .pink,
        disabled: .gray,
        divider: .gray.opacity(0.3)
    )
}

extension EnvironmentValues {
    var containerPalette: AdaptivePaletteV2 {
        get { self[ContainerPaletteKey.self] }
        set { self[ContainerPaletteKey.self] = newValue }
    }
}

// MARK: - View扩展
extension View {
    /// 应用容器就近配色
    func containerAdaptiveColors(
        background: ContainerBackgroundType = .ultraThinMaterial,
        accent: Color? = nil
    ) -> some View {
        modifier(ContainerAdaptiveColorModifier(
            containerBackground: background,
            overrideAccent: accent
        ))
    }
}

// MARK: - 便捷文本样式
struct ContainerPrimaryText: ViewModifier {
    @Environment(\.containerPalette) private var palette
    
    func body(content: Content) -> some View {
        content.foregroundColor(palette.primary)
    }
}

struct ContainerSecondaryText: ViewModifier {
    @Environment(\.containerPalette) private var palette
    
    func body(content: Content) -> some View {
        content.foregroundColor(palette.secondary)
    }
}

struct ContainerTertiaryText: ViewModifier {
    @Environment(\.containerPalette) private var palette
    
    func body(content: Content) -> some View {
        content.foregroundColor(palette.tertiary)
    }
}

struct ContainerAccentText: ViewModifier {
    @Environment(\.containerPalette) private var palette
    
    func body(content: Content) -> some View {
        content.foregroundColor(palette.accent)
    }
}

extension View {
    func containerPrimary() -> some View {
        modifier(ContainerPrimaryText())
    }
    
    func containerSecondary() -> some View {
        modifier(ContainerSecondaryText())
    }
    
    func containerTertiary() -> some View {
        modifier(ContainerTertiaryText())
    }
    
    func containerAccent() -> some View {
        modifier(ContainerAccentText())
    }
}
