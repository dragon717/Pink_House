//
//  DarkModeColors.swift
//  ItemManager
//
//  世界书 - 暗夜模式颜色适配
//

import SwiftUI

// MARK: - 暗夜模式颜色扩展
/// 使用说明：
/// 1. 背景色使用 adaptiveBackground 系列
/// 2. 文字颜色使用 adaptiveLabel 系列
/// 3. 分隔线使用 adaptiveSeparator
/// 4. 填充色使用 adaptiveFill 系列
/// 5. 品牌色（金色、主题色）保持不变
extension Color {
    
    // MARK: - 背景色
    
    /// 主背景色 - 自动适配浅色/深色模式
    /// 浅色：白色  深色：黑色
    static var adaptiveBackground: Color {
        // 使用 SwiftUI 语义化颜色，自动适配
        Color.white.opacity(0) == Color.black.opacity(0) ? Color.white : Color.black
        // 实际上应该使用：
        // 在 iOS 15+ 可以使用 Color(uiColor: .systemBackground)
        // 这里使用简单的黑白切换
        return Color.primary.opacity(0.05)
    }
    
    /// 二级背景色 - 用于卡片、分组
    /// 浅色：浅灰色  深色：深灰色
    static var adaptiveSecondaryBackground: Color {
        Color.primary.opacity(0.1)
    }
    
    /// 三级背景色 - 用于输入框、小卡片
    static var adaptiveTertiaryBackground: Color {
        Color.primary.opacity(0.15)
    }
    
    /// 分组背景色
    static var adaptiveGroupedBackground: Color {
        Color.primary.opacity(0.05)
    }
    
    /// 二级分组背景色
    static var adaptiveSecondaryGroupedBackground: Color {
        Color.primary.opacity(0.1)
    }
    
    // MARK: - 文字颜色
    
    /// 主文字色 - 自动适配
    /// 浅色：黑色  深色：白色
    static var adaptiveLabel: Color {
        Color.primary
    }
    
    /// 二级文字色 - 副标题、描述
    static var adaptiveSecondaryLabel: Color {
        Color.secondary
    }
    
    /// 三级文字色 - 占位符、禁用状态
    static var adaptiveTertiaryLabel: Color {
        Color.gray
    }
    
    // MARK: - 辅助颜色
    
    /// 分隔线颜色
    static var adaptiveSeparator: Color {
        Color.primary.opacity(0.2)
    }
    
    /// 分隔线颜色 - 用于 overlay
    static var separatorColor: Color {
        Color.gray.opacity(0.3)
    }
    
    /// 填充色 - 用于开关、滑块
    static var adaptiveFill: Color {
        Color.primary.opacity(0.1)
    }
    
    /// 二级填充色
    static var adaptiveSecondaryFill: Color {
        Color.primary.opacity(0.2)
    }
    
    // MARK: - 特殊背景色（保留原有风格）
    
    /// 沉浸式深色背景 - 用于飞行体验、徽章展示等需要深色氛围的界面
    static var immersiveDarkBackground: Color {
        Color(red: 0.05, green: 0.05, blue: 0.08)
    }
    
    /// 沉浸式卡片背景
    static var immersiveCardBackground: Color {
        Color(red: 0.12, green: 0.12, blue: 0.15)
    }
    
    /// 机场浅色背景 - BoardingExperienceView 专用
    static var airportLightBackground: Color {
        Color(red: 0.95, green: 0.95, blue: 0.97)
    }
}

// MARK: - 环境颜色方案
/// 用于在视图中获取当前颜色方案
struct ColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

extension EnvironmentValues {
    var colorSchemeValue: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}

// MARK: - View 扩展 - 暗夜模式适配
extension View {
    
    /// 应用自适应背景色
    func adaptiveBackground() -> some View {
        self.background(Color.adaptiveBackground)
    }
    
    /// 应用二级自适应背景色
    func adaptiveSecondaryBackground() -> some View {
        self.background(Color.adaptiveSecondaryBackground)
    }
    
    /// 应用分组背景色
    func adaptiveGroupedBackground() -> some View {
        self.background(Color.adaptiveGroupedBackground)
    }
}

// MARK: - 颜色方案观察
/// 用于在视图中观察当前颜色方案
struct ColorSchemeObserver: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .preference(key: ColorSchemePreferenceKey.self, value: colorScheme)
    }
}

struct ColorSchemePreferenceKey: PreferenceKey {
    static var defaultValue: ColorScheme = .light
    static func reduce(value: inout ColorScheme, nextValue: () -> ColorScheme) {
        value = nextValue()
    }
}
