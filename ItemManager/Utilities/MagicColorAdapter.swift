//
//  MagicColorAdapter.swift
//  ItemManager
//
//  魔法配色适配器 - 为所有界面提供统一的配色适配
//

import SwiftUI

// MARK: - 魔法配色适配修饰器
struct MagicColorAdapter: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    
    func body(content: Content) -> some View {
        content
            .environment(\.adaptivePalette, themeManager.adaptivePalette)
    }
}

extension View {
    /// 应用魔法配色适配
    func magicColorAdapted() -> some View {
        modifier(MagicColorAdapter())
    }
}

// MARK: - 自适应文本组件
struct AdaptiveText: View {
    let text: String
    let font: Font
    let level: TextLevel
    
    enum TextLevel {
        case primary      // 主标题
        case secondary    // 副标题
        case tertiary     // 辅助文字
        case accent       // 强调色
    }
    
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(textColor)
    }
    
    private var textColor: Color {
        switch level {
        case .primary:
            return themeManager.primaryTextColor
        case .secondary:
            return themeManager.secondaryTextColor
        case .tertiary:
            return themeManager.tertiaryTextColor
        case .accent:
            return themeManager.accentTextColor
        }
    }
}

// MARK: - 自适应标签组件
struct AdaptiveLabel: View {
    let title: String
    let systemImage: String
    let level: AdaptiveText.TextLevel
    
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundColor(textColor)
    }
    
    private var textColor: Color {
        switch level {
        case .primary:
            return themeManager.primaryTextColor
        case .secondary:
            return themeManager.secondaryTextColor
        case .tertiary:
            return themeManager.tertiaryTextColor
        case .accent:
            return themeManager.accentTextColor
        }
    }
}

// MARK: - View扩展 - 便捷方法
extension View {
    /// 主标题颜色
    func primaryForeground() -> some View {
        self.foregroundColor(ThemeManager.shared.primaryTextColor)
    }
    
    /// 副标题颜色
    func secondaryForeground() -> some View {
        self.foregroundColor(ThemeManager.shared.secondaryTextColor)
    }
    
    /// 辅助文字颜色
    func tertiaryForeground() -> some View {
        self.foregroundColor(ThemeManager.shared.tertiaryTextColor)
    }
    
    /// 强调色
    func accentForeground() -> some View {
        self.foregroundColor(ThemeManager.shared.accentTextColor)
    }
}

// MARK: - Text扩展 - 便捷方法
extension Text {
    /// 主标题颜色
    func primaryColor() -> some View {
        self.foregroundColor(ThemeManager.shared.primaryTextColor)
    }
    
    /// 副标题颜色
    func secondaryColor() -> some View {
        self.foregroundColor(ThemeManager.shared.secondaryTextColor)
    }
    
    /// 辅助文字颜色
    func tertiaryColor() -> some View {
        self.foregroundColor(ThemeManager.shared.tertiaryTextColor)
    }
    
    /// 强调色
    func accentColor() -> some View {
        self.foregroundColor(ThemeManager.shared.accentTextColor)
    }
}
