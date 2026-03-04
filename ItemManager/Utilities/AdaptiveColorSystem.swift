//
//  AdaptiveColorSystem.swift
//  ItemManager
//
//  智能配色系统 - 根据背景自动调整字体颜色
//

import SwiftUI
import UIKit

// MARK: - 颜色亮度计算扩展
extension UIColor {
    /// 计算颜色的亮度值 (0-1, 0为最暗, 1为最亮)
    /// 使用标准对比度公式: L = 0.299*R + 0.587*G + 0.114*B
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        self.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
    
    /// 判断颜色是否为暗色 (亮度 < 0.5)
    var isDark: Bool {
        return luminance < 0.5
    }
    
    /// 判断颜色是否为亮色 (亮度 >= 0.5)
    var isLight: Bool {
        return !isDark
    }
    
    /// 获取对比色 (黑或白)
    var contrastColor: UIColor {
        return isDark ? .white : .black
    }
}

extension Color {
    /// 计算亮度
    var luminance: CGFloat {
        return UIColor(self).luminance
    }
    
    /// 是否为暗色
    var isDark: Bool {
        return UIColor(self).isDark
    }
    
    /// 是否为亮色
    var isLight: Bool {
        return UIColor(self).isLight
    }
    
    /// 获取对比色
    var contrastColor: Color {
        return Color(UIColor(self).contrastColor)
    }
}

// MARK: - 智能调色板
/// 根据背景自动生成的配色方案
struct AdaptivePalette {
    // 主标题色 - 最高重要性
    let primary: Color
    // 副标题/正文色 - 中等重要性
    let secondary: Color
    // 辅助说明色 - 低重要性
    let tertiary: Color
    // 强调色 - 按钮、链接等
    let accent: Color
    // 禁用色
    let disabled: Color
    // 分割线/边框色
    let divider: Color
    
    /// 根据背景色生成智能调色板
    static func generate(from backgroundColor: Color, accentColor: Color? = nil) -> AdaptivePalette {
        let isDarkBackground = backgroundColor.isDark
        
        // 基础对比色
        let baseColor: Color = isDarkBackground ? .white : .black
        
        // 生成强调色: 如果提供了就用,否则根据背景智能生成
        let finalAccent: Color
        if let accent = accentColor {
            finalAccent = accent
        } else {
            // 根据背景色相生成对比强调色
            finalAccent = generateAccentColor(for: backgroundColor, isDark: isDarkBackground)
        }
        
        return AdaptivePalette(
            primary: baseColor,
            secondary: baseColor.opacity(isDarkBackground ? 0.85 : 0.75),
            tertiary: baseColor.opacity(isDarkBackground ? 0.60 : 0.50),
            accent: finalAccent,
            disabled: baseColor.opacity(0.30),
            divider: baseColor.opacity(isDarkBackground ? 0.20 : 0.15)
        )
    }
    
    /// 暗色背景调色板 (预设)
    static var darkBackground: AdaptivePalette {
        AdaptivePalette(
            primary: .white,
            secondary: .white.opacity(0.85),
            tertiary: .white.opacity(0.60),
            accent: .pink,
            disabled: .white.opacity(0.30),
            divider: .white.opacity(0.20)
        )
    }
    
    /// 亮色背景调色板 (预设)
    static var lightBackground: AdaptivePalette {
        AdaptivePalette(
            primary: .black,
            secondary: .black.opacity(0.75),
            tertiary: .black.opacity(0.50),
            accent: .pink,
            disabled: .black.opacity(0.30),
            divider: .black.opacity(0.15)
        )
    }
    
    // MARK: - 私有方法
    
    /// 智能生成强调色
    private static func generateAccentColor(for background: Color, isDark: Bool) -> Color {
        // 提取背景色的色相
        let uiColor = UIColor(background)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        
        if uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            // 生成对比色相 (加0.5即180度,取补色)
            let contrastHue = fmod(hue + 0.5, 1.0)
            
            // 根据背景亮度调整强调色
            if isDark {
                // 暗背景: 使用高饱和度高亮度的颜色
                return Color(hue: contrastHue, saturation: 0.8, brightness: 1.0)
            } else {
                // 亮背景: 使用高饱和度中等亮度的颜色
                return Color(hue: contrastHue, saturation: 0.7, brightness: 0.6)
            }
        }
        
        // 默认返回粉色
        return isDark ? .pink : .red
    }
}

// MARK: - 背景类型
enum BackgroundType {
    case solid(color: Color)           // 纯色背景
    case image(dominantColor: Color?)  // 图片背景 (带主色调)
    case gradient(colors: [Color])     // 渐变背景
    case material                      // 材质背景
    
    /// 获取用于判断的背景色
    var referenceColor: Color {
        switch self {
        case .solid(let color):
            return color
        case .image(let dominantColor):
            return dominantColor ?? .white
        case .gradient(let colors):
            // 取渐变色的平均亮度
            let totalLuminance = colors.reduce(0.0) { $0 + $1.luminance }
            let avgLuminance = totalLuminance / CGFloat(colors.count)
            return avgLuminance < 0.5 ? .black : .white
        case .material:
            // 材质背景根据系统外观
            return Color(uiColor: .systemBackground)
        }
    }
    
    /// 是否为暗色背景
    var isDark: Bool {
        return referenceColor.isDark
    }
}

// MARK: - 环境值键
private struct AdaptivePaletteKey: EnvironmentKey {
    static let defaultValue: AdaptivePalette = .lightBackground
}

extension EnvironmentValues {
    var adaptivePalette: AdaptivePalette {
        get { self[AdaptivePaletteKey.self] }
        set { self[AdaptivePaletteKey.self] = newValue }
    }
}

// MARK: - ViewModifier
/// 自适应配色修饰器
struct AdaptiveColorModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    let backgroundType: BackgroundType?
    let customAccentColor: Color?
    
    func body(content: Content) -> some View {
        let palette = resolvePalette()
        
        content
            .environment(\.adaptivePalette, palette)
    }
    
    private func resolvePalette() -> AdaptivePalette {
        // 如果指定了背景类型,直接使用
        if let bgType = backgroundType {
            return AdaptivePalette.generate(from: bgType.referenceColor, accentColor: customAccentColor)
        }
        
        // 根据 ThemeManager 自动判断
        switch themeManager.backgroundStyle {
        case .color:
            return AdaptivePalette.generate(from: themeManager.backgroundColor, accentColor: customAccentColor)
        case .image:
            // 图片背景默认使用暗色调色板 (假设图片较复杂)
            // 实际使用时可以提取图片主色调
            return .darkBackground
        }
    }
}

extension View {
    /// 应用自适应配色
    func adaptiveColors(
        for backgroundType: BackgroundType? = nil,
        accentColor: Color? = nil
    ) -> some View {
        modifier(AdaptiveColorModifier(
            backgroundType: backgroundType,
            customAccentColor: accentColor
        ))
    }
}

// MARK: - 便捷使用扩展
extension View {
    /// 主标题样式
    func primaryTextStyle() -> some View {
        self.modifier(PrimaryTextStyle())
    }
    
    /// 副标题样式
    func secondaryTextStyle() -> some View {
        self.modifier(SecondaryTextStyle())
    }
    
    /// 辅助文字样式
    func tertiaryTextStyle() -> some View {
        self.modifier(TertiaryTextStyle())
    }
}

// MARK: - 文本样式修饰器
struct PrimaryTextStyle: ViewModifier {
    @Environment(\.adaptivePalette) private var palette
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(palette.primary)
    }
}

struct SecondaryTextStyle: ViewModifier {
    @Environment(\.adaptivePalette) private var palette
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(palette.secondary)
    }
}

struct TertiaryTextStyle: ViewModifier {
    @Environment(\.adaptivePalette) private var palette
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(palette.tertiary)
    }
}

// MARK: - 智能对比度文本 (用于复杂背景)
/// 在复杂背景上显示带阴影的文本,确保可读性
struct SmartContrastText: View {
    let text: String
    let font: Font
    let alignment: TextAlignment
    let useOutline: Bool
    
    init(
        _ text: String,
        font: Font = .body,
        alignment: TextAlignment = .leading,
        useOutline: Bool = false
    ) {
        self.text = text
        self.font = font
        self.alignment = alignment
        self.useOutline = useOutline
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(alignment)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .overlay(
                Group {
                    if useOutline {
                        Text(text)
                            .font(font)
                            .multilineTextAlignment(alignment)
                            .foregroundColor(.clear)
                            .overlay(
                                Text(text)
                                    .font(font)
                                    .multilineTextAlignment(alignment)
                                    .foregroundColor(.white)
                            )
                            .shadow(color: .black, radius: 0.5, x: 0.5, y: 0.5)
                            .shadow(color: .black, radius: 0.5, x: -0.5, y: -0.5)
                            .shadow(color: .black, radius: 0.5, x: 0.5, y: -0.5)
                            .shadow(color: .black, radius: 0.5, x: -0.5, y: 0.5)
                    }
                }
            )
    }
}

// MARK: - 背景感知容器
/// 自动检测背景并应用合适配色的容器
struct AdaptiveContainer<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    
    let backgroundType: BackgroundType?
    let accentColor: Color?
    let content: Content
    
    init(
        backgroundType: BackgroundType? = nil,
        accentColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundType = backgroundType
        self.accentColor = accentColor
        self.content = content()
    }
    
    private var palette: AdaptivePalette {
        if let bgType = backgroundType {
            return AdaptivePalette.generate(from: bgType.referenceColor, accentColor: accentColor)
        }
        
        switch themeManager.backgroundStyle {
        case .color:
            return AdaptivePalette.generate(from: themeManager.backgroundColor, accentColor: accentColor)
        case .image:
            return .darkBackground
        }
    }
    
    var body: some View {
        content
            .environment(\.adaptivePalette, palette)
    }
}

// MARK: - 图片主色调提取扩展
/// 使用 UIImage+Extensions.swift 中已有的 averageColor 属性
extension UIImage {
    /// 判断图片整体是偏亮还是偏暗
    var isDarkImage: Bool {
        guard let avgColor = averageColor else { return false }
        return avgColor.isDark
    }
}
