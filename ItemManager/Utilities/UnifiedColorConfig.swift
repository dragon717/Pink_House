//
//  UnifiedColorConfig.swift
//  ItemManager
//
//  统一配色配置管理 - 为豆腐块和详情界面提供一致的配色体验
//  支持魔法配色和客制化配色两种模式
//

import SwiftUI

// MARK: - 统一配色配置
/// 集中管理所有界面的配色配置，确保豆腐块和详情界面的一致性
enum UnifiedColorConfig {
    
    // MARK: - 卡片样式配置
    enum CardStyle {
        case solid                    // 实色背景
        case transparent(opacity: Double)  // 半透明
        case fullyTransparent         // 全透明
        case tinted(color: Color, opacity: Double)  // 色调
        case ultraThinMaterial        // 系统材质
        
        /// 根据 ThemeManager 获取当前卡片样式
        static func current(from themeManager: ThemeManager) -> CardStyle {
            switch themeManager.cardStyle {
            case .solid:
                return .solid
            case .transparent:
                return .transparent(opacity: themeManager.transparentOpacity)
            case .fullyTransparent:
                return .fullyTransparent
            case .tinted:
                return .tinted(color: themeManager.cardTintColor, opacity: themeManager.tintOpacity)
            }
        }
        
        /// 获取背景颜色（亮色模式）
        func backgroundColor(colorScheme: ColorScheme) -> Color {
            let isDark = colorScheme == .dark
            let baseColor: Color = isDark ? Color.black.opacity(0.6) : Color.white.opacity(0.8)
            
            switch self {
            case .solid:
                return baseColor
            case .transparent(let opacity):
                return baseColor.opacity(opacity)
            case .fullyTransparent:
                return Color.clear
            case .tinted(let color, let opacity):
                return color.opacity(opacity)
            case .ultraThinMaterial:
                return Color.clear // 使用材质背景
            }
        }
    }
    
    // MARK: - 图片填充模式
    enum ImageFillMode {
        case solid(opacity: Double)
        case transparent(opacity: Double)
        case fullyTransparent
        case tinted(color: Color, opacity: Double)
        case imageTinted(color: Color, opacity: Double)  // 图片填充色调模式

        /// 根据 ThemeManager 获取当前填充模式
        static func current(from themeManager: ThemeManager, colorScheme: ColorScheme) -> ImageFillMode {
            let isDark = colorScheme == .dark

            switch themeManager.skirtFillMode {
            case .solid:
                return .solid(opacity: isDark ? 0.6 : 0.1)
            case .transparent:
                // 使用 ThemeManager 中设置的透明度（默认100%）
                return .transparent(opacity: isDark ? themeManager.transparentOpacity * 0.3 : themeManager.transparentOpacity * 0.4)
            case .fullyTransparent:
                return .fullyTransparent
            case .tinted:
                // 客制化配色-莫妮卡粉：使用图片填充色调
                return .imageTinted(color: themeManager.imageFillTintColor, opacity: themeManager.imageFillTintOpacity)
            }
        }

        /// 获取背景颜色
        func backgroundColor() -> Color {
            switch self {
            case .solid(let opacity):
                return Color.black.opacity(opacity)
            case .transparent(let opacity):
                return Color.white.opacity(opacity)
            case .fullyTransparent:
                return Color.clear
            case .tinted(let color, let opacity):
                return color.opacity(opacity)
            case .imageTinted(let color, let opacity):
                return color.opacity(opacity)
            }
        }

        /// 获取色调颜色（用于图片叠加）
        func tintColor() -> Color? {
            switch self {
            case .imageTinted(let color, _):
                return color
            default:
                return nil
            }
        }

        /// 获取色调透明度
        func tintOpacity() -> Double {
            switch self {
            case .imageTinted(_, let opacity):
                return opacity
            default:
                return 0
            }
        }
    }
    
    // MARK: - 文本颜色配置
    struct TextColors {
        let primary: Color      // 主标题、重要文字
        let secondary: Color    // 副标题、次要信息
        let tertiary: Color     // 辅助文字、说明
        let accent: Color       // 强调色、价格、按钮
        
        /// 从 ThemeManager 获取当前文本颜色
        static func current(from themeManager: ThemeManager) -> TextColors {
            return TextColors(
                primary: themeManager.primaryTextColor,
                secondary: themeManager.secondaryTextColor,
                tertiary: themeManager.tertiaryTextColor,
                accent: themeManager.accentTextColor
            )
        }
    }
    
    // MARK: - 边框和分割线配置
    struct BorderConfig {
        let color: Color
        let width: CGFloat
        let cornerRadius: CGFloat
        
        static let `default` = BorderConfig(
            color: Color.primary.opacity(0.1),
            width: 1,
            cornerRadius: 16
        )
        
        static let highlighted = BorderConfig(
            color: Color.pink.opacity(0.3),
            width: 2,
            cornerRadius: 16
        )
    }
    
    // MARK: - 阴影配置
    struct ShadowConfig {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        
        /// 默认卡片阴影
        static let card = ShadowConfig(
            color: Color.black.opacity(0.05),
            radius: 5,
            x: 0,
            y: 2
        )
        
        /// 强调阴影
        static let emphasized = ShadowConfig(
            color: Color.black.opacity(0.1),
            radius: 8,
            x: 0,
            y: 4
        )
        
        /// 无阴影
        static let none = ShadowConfig(
            color: Color.clear,
            radius: 0,
            x: 0,
            y: 0
        )
    }
}

// MARK: - View 扩展 - 统一配色应用
extension View {
    /// 应用统一的卡片背景样式
    func unifiedCardBackground(
        style: UnifiedColorConfig.CardStyle,
        colorScheme: ColorScheme
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(style.backgroundColor(colorScheme: colorScheme))
        )
    }
    
    /// 应用统一的阴影
    func unifiedShadow(_ config: UnifiedColorConfig.ShadowConfig = .card) -> some View {
        self.shadow(
            color: config.color,
            radius: config.radius,
            x: config.x,
            y: config.y
        )
    }
    
    /// 应用统一的边框
    func unifiedBorder(_ config: UnifiedColorConfig.BorderConfig = .default) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                .stroke(config.color, lineWidth: config.width)
        )
    }
}

// MARK: - 统一配色环境值
private struct UnifiedTextColorsKey: EnvironmentKey {
    static let defaultValue: UnifiedColorConfig.TextColors = UnifiedColorConfig.TextColors(
        primary: .primary,
        secondary: .secondary,
        tertiary: .gray,
        accent: .pink
    )
}

extension EnvironmentValues {
    var unifiedTextColors: UnifiedColorConfig.TextColors {
        get { self[UnifiedTextColorsKey.self] }
        set { self[UnifiedTextColorsKey.self] = newValue }
    }
}

// MARK: - 统一配色修饰器
struct UnifiedColorModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let textColors = UnifiedColorConfig.TextColors.current(from: themeManager)
        
        return content
            .environment(\.unifiedTextColors, textColors)
    }
}

extension View {
    /// 应用统一配色环境
    func unifiedColors() -> some View {
        modifier(UnifiedColorModifier())
    }
}

// MARK: - 便捷文本修饰器
struct UnifiedPrimaryText: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    
    func body(content: Content) -> some View {
        content.foregroundColor(themeManager.primaryTextColor)
    }
}

struct UnifiedSecondaryText: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    
    func body(content: Content) -> some View {
        content.foregroundColor(themeManager.secondaryTextColor)
    }
}

struct UnifiedTertiaryText: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    
    func body(content: Content) -> some View {
        content.foregroundColor(themeManager.tertiaryTextColor)
    }
}

struct UnifiedAccentText: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    
    func body(content: Content) -> some View {
        content.foregroundColor(themeManager.accentTextColor)
    }
}

extension View {
    /// 主标题颜色（统一配色）
    func unifiedPrimary() -> some View {
        modifier(UnifiedPrimaryText())
    }
    
    /// 副标题颜色（统一配色）
    func unifiedSecondary() -> some View {
        modifier(UnifiedSecondaryText())
    }
    
    /// 辅助文字颜色（统一配色）
    func unifiedTertiary() -> some View {
        modifier(UnifiedTertiaryText())
    }
    
    /// 强调色（统一配色）
    func unifiedAccent() -> some View {
    modifier(UnifiedAccentText())
    }
}
