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

// MARK: - 主题配色配置（持久化）
struct ThemeColorConfig: Codable {
    // 配色模式
    var colorSchemeMode: ColorSchemeMode
    
    // 客制化颜色（RGBA存储，兼容备份）
    var customPrimaryRGBA: ColorRGBA
    var customSecondaryRGBA: ColorRGBA
    var customTertiaryRGBA: ColorRGBA
    var customAccentRGBA: ColorRGBA
    
    // 暗夜模式下的客制化颜色
    var darkPrimaryRGBA: ColorRGBA
    var darkSecondaryRGBA: ColorRGBA
    var darkTertiaryRGBA: ColorRGBA
    var darkAccentRGBA: ColorRGBA
    
    // 是否跟随系统暗夜模式
    var followSystemDarkMode: Bool
    
    // 默认配置 - 客制化配色作为默认模式
    static let `default` = ThemeColorConfig(
        colorSchemeMode: .custom,
        customPrimaryRGBA: ColorRGBA.black,
        customSecondaryRGBA: ColorRGBA.gray,
        customTertiaryRGBA: ColorRGBA.lightGray,
        customAccentRGBA: ColorRGBA.pink,
        darkPrimaryRGBA: ColorRGBA.white,
        darkSecondaryRGBA: ColorRGBA.lightGray,
        darkTertiaryRGBA: ColorRGBA.gray,
        darkAccentRGBA: ColorRGBA.pink,
        followSystemDarkMode: true
    )
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
