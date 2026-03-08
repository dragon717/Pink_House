//
//  CalendarThemeManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/10/26.
//

import SwiftUI
import UIKit

// MARK: - 日历主题协议
protocol CalendarTheme {
    var id: String { get }
    var displayName: String { get }
    var backgroundColor: UIColor { get }
    var accentColor: UIColor { get } // 少女粉、水蓝色等
    var depositColor: UIColor { get } // 定金标记色
    var finalPaymentColor: UIColor { get } // 尾款标记色
    var fontName: String { get }
}

// MARK: - 基于新主题系统的日历主题适配器
struct AdaptiveCalendarTheme: CalendarTheme {
    let id: String
    let displayName: String
    let backgroundColor: UIColor
    let accentColor: UIColor
    let depositColor: UIColor
    let finalPaymentColor: UIColor
    let fontName = "PingFangSC-Regular"

    /// 从 ThemePreset 创建日历主题
    static func fromThemePreset(_ preset: ThemePreset, colorScheme: ColorScheme) -> AdaptiveCalendarTheme {
        let isDark = colorScheme == .dark
        let cardColors = preset.cardColors(forDarkMode: isDark)
        let textColors = preset.textColors(forDarkMode: isDark)

        return AdaptiveCalendarTheme(
            id: preset.id,
            displayName: preset.name,
            backgroundColor: UIColor(cardColors.backgroundRGBA.color),
            accentColor: UIColor(cardColors.accentRGBA.color),
            depositColor: UIColor(cardColors.depositRGBA.color),
            finalPaymentColor: UIColor(cardColors.finalPaymentRGBA.color)
        )
    }

    /// 从 ThemeManager 获取当前主题
    static func current(from themeManager: ThemeManager, colorScheme: ColorScheme) -> AdaptiveCalendarTheme {
        let config = themeManager.themeColorConfig
        let preset = config.currentTheme(forDarkMode: colorScheme == .dark)
        return fromThemePreset(preset, colorScheme: colorScheme)
    }
}

// MARK: - 主题管理器
@Observable
class CalendarThemeManager {
    static let shared = CalendarThemeManager()

    var currentTheme: CalendarTheme

    // 是否使用客制化配色（从 ThemeManager 获取）
    var useCustomColorScheme: Bool = false {
        didSet {
            UserDefaults.standard.set(useCustomColorScheme, forKey: "calendar_use_custom_color_scheme")
        }
    }

    private init() {
        // 加载是否使用客制化配色的设置
        self.useCustomColorScheme = UserDefaults.standard.bool(forKey: "calendar_use_custom_color_scheme")

        // 默认使用莫妮卡粉主题
        self.currentTheme = AdaptiveCalendarTheme.fromThemePreset(CustomColorPresets.monicaPink, colorScheme: .light)
    }

    /// 刷新主题（根据 ThemeManager 的当前配置）
    func refreshTheme(from themeManager: ThemeManager, colorScheme: ColorScheme) {
        currentTheme = AdaptiveCalendarTheme.current(from: themeManager, colorScheme: colorScheme)
    }

    /// 设置使用客制化配色
    func setCustomTheme(from themeManager: ThemeManager, colorScheme: ColorScheme) {
        refreshTheme(from: themeManager, colorScheme: colorScheme)
        useCustomColorScheme = true
    }

    /// 设置使用预设主题
    func setPresetTheme(_ preset: ThemePreset, colorScheme: ColorScheme) {
        currentTheme = AdaptiveCalendarTheme.fromThemePreset(preset, colorScheme: colorScheme)
        useCustomColorScheme = false
    }
}
