//
//  ThemePreviewSection.swift
//  ItemManager
//
//  主题预览区域组件
//

import SwiftUI

// MARK: - 主题预览区域
struct ThemePreviewSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    // 计算当前主题 - 根据配色模式返回不同的主题
    private var currentTheme: ThemePreset {
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

    private var textColors: (primary: Color, secondary: Color, tertiary: Color, accent: Color) {
        let colors = currentTheme.textColors(forDarkMode: colorScheme == .dark)
        return (colors.primary.color, colors.secondary.color, colors.tertiary.color, colors.accent.color)
    }

    private var cardColors: CardColorConfig {
        currentTheme.cardColors(forDarkMode: colorScheme == .dark)
    }

    // 根据卡片样式计算预览卡片背景
    private var previewCardBackground: some View {
        let baseColor = cardColors.backgroundRGBA.color
        switch themeManager.cardStyle {
        case .solid:
            return AnyView(baseColor)
        case .transparent:
            return AnyView(baseColor.opacity(themeManager.transparentOpacity))
        case .fullyTransparent:
            return AnyView(Color.clear)
        case .tinted:
            // 色调强度越高，背景色越明显（越接近实色）
            return AnyView(baseColor.opacity(themeManager.tintOpacity))
        }
    }

    // 根据裙装填充模式计算图片区域背景
    private func skirtImageBackground(baseColor: Color) -> Color {
        switch themeManager.skirtFillMode {
        case .solid:
            return baseColor
        case .transparent:
            return baseColor.opacity(0.5)
        case .fullyTransparent:
            return Color.clear
        case .tinted:
            return baseColor.opacity(0.3)
        }
    }

    var body: some View {
        // 预览内容 - 使用 TabView 实现左右滑动
        VStack(spacing: 4) {
            // 标签
            HStack {
                Text("主题预览")
                    .font(.caption)
                    .foregroundStyle(textColors.tertiary)
                Spacer()
            }
            .padding(.horizontal, 16)

            // 左右滑动的模块预览（带灰色遮罩）
            ZStack {
                // 灰色遮罩 - 覆盖整个预览区域
                Color.black
                    .opacity(themeManager.backgroundStyle == .image ? 0.3 : 0.1)

                TabView {
                    // 第 1 页：主题色卡片示例（原预览）
                    clothingCardPreview

                    // 第 2 页：梦幻衣橱模块预览
                    wardrobeModulePreview

                    // 第 3 页：梦裙日历模块预览
                    calendarModulePreview

                    // 第 4 页：马上来财模块预览
                    wealthModulePreview

                    // 第 5 页：萌宠对话气泡预览
                    petChatBubblePreview
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .frame(height: 180)

            // 图例说明
            HStack(spacing: 16) {
                LegendItem(color: textColors.primary, label: "主要")
                LegendItem(color: textColors.secondary, label: "次要")
                LegendItem(color: textColors.tertiary, label: "辅助")
                LegendItem(color: textColors.accent, label: "强调")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    // MARK: - 主题色卡片示例预览
    private var clothingCardPreview: some View {
        HStack(spacing: 12) {
            // 图片占位（模拟裙装图片区域）- 应用裙装填充模式
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(skirtImageBackground(baseColor: cardColors.secondaryRGBA.color))
                    .frame(width: 80, height: 80)

                Image(systemName: "tshirt.fill")
                    .font(.title2)
                    .foregroundStyle(cardColors.accentRGBA.color.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 信息区域
            VStack(alignment: .leading, spacing: 6) {
                // 裙装名称 - 主要文字
                Text("小裙装名称")
                    .font(.headline)
                    .foregroundStyle(textColors.primary)

                // 品牌 - 次要文字
                Text("品牌名称 · 型色")
                    .font(.subheadline)
                    .foregroundStyle(textColors.secondary)

                // 价格和状态
                HStack {
                    // 价格 - 主要文字
                    Text("¥999")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(textColors.primary)

                    Spacer()

                    // 标签 - 强调色
                    Text("已拥有")
                        .font(.caption)
                        .foregroundStyle(textColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(textColors.accent.opacity(0.15))
                        .cornerRadius(4)
                }

                // 购买日期 - 辅助文字
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(textColors.tertiary)
                    Text("2024-01-01 购买")
                        .font(.caption)
                        .foregroundStyle(textColors.tertiary)
                }
            }

            Spacer()
        }
        .padding()
        .background(previewCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardColors.accentRGBA.color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - 梦幻衣橱模块预览
    private var wardrobeModulePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("梦幻衣橱")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(textColors.primary)
            Text("原生顶部栏 · 菜单 · 页签")
                .font(.caption2)
                .foregroundStyle(textColors.secondary)

            HStack {
                Image(systemName: "arrow.up.arrow.down")
                Image(systemName: "line.3.horizontal.decrease.circle")
                Spacer()
                Text("少女衣橱 / 心愿尾款")
                    .font(.caption2)
                Spacer()
                Image(systemName: "square.grid.2x2")
                Image(systemName: "ellipsis.circle")
            }
            .font(.caption)
            .foregroundStyle(textColors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardColors.backgroundRGBA.color.opacity(colorScheme == .dark ? 0.46 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(cardColors.accentRGBA.color.opacity(0.2), lineWidth: 1)
            )
        }
        .padding()
        .background(previewCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardColors.accentRGBA.color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - 梦裙日历模块预览
    private var calendarModulePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("梦裙日历")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(textColors.primary)
            Text("筛选按钮 · 分段页签")
                .font(.caption2)
                .foregroundStyle(textColors.secondary)

            HStack(spacing: 6) {
                Image(systemName: "paintpalette")
                    .foregroundStyle(textColors.accent)
                Capsule()
                    .fill(cardColors.accentRGBA.color.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(width: 110, height: 28)
                    .overlay(
                        HStack(spacing: 4) {
                            Capsule()
                                .fill(cardColors.backgroundRGBA.color.mixed(with: .white, amount: colorScheme == .dark ? 0.08 : 0.18))
                                .frame(width: 52, height: 22)
                                .overlay(Text("月").font(.caption2).foregroundStyle(textColors.primary))
                            Text("年")
                                .font(.caption2)
                                .foregroundStyle(textColors.secondary)
                        }
                    )
                Spacer()
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(textColors.accent)
            }
            .font(.caption)
        }
        .padding()
        .background(previewCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardColors.accentRGBA.color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - 马上来财模块预览
    private var wealthModulePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("马上来财")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(textColors.primary)
            Text("请签文字色 · 容器系统文字色")
                .font(.caption2)
                .foregroundStyle(textColors.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("请签：今日适合温柔俏皮配色")
                    .font(.caption)
                    .foregroundStyle(textColors.primary)
                HStack(spacing: 8) {
                    Text("请签")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(textColors.accent.opacity(colorScheme == .dark ? 0.20 : 0.12))
                        .clipShape(Capsule())
                    Text("数钱")
                        .font(.caption2)
                        .foregroundStyle(textColors.secondary)
                    Text("安财")
                        .font(.caption2)
                        .foregroundStyle(textColors.secondary)
                }
            }
        }
        .padding()
        .background(previewCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardColors.accentRGBA.color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - 萌宠对话气泡预览
    private var petChatBubblePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("萌宠对话")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(textColors.primary)
            Text("气泡样式 · 快捷选项")
                .font(.caption2)
                .foregroundStyle(textColors.secondary)

            // 使用当前皮肤主题预览
            let skinTheme = themeManager.petChatSkinTheme

            VStack(spacing: 8) {
                // 助手气泡（奶茶）- 使用卡片背景色 + 主题色边框
                HStack {
                    Text("奶茶：今天想要偏甜美，还是偏通勤呢？")
                        .font(.caption)
                        .foregroundStyle(textColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: skinTheme.cornerRadius)
                                .fill(themeManager.cardBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: skinTheme.cornerRadius)
                                        .stroke(
                                            LinearGradient(
                                                colors: skinTheme.resolvedAssistantStrokeColors(themeManager: themeManager, colorScheme: colorScheme),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                    Spacer()
                }

                // 用户气泡
                HStack {
                    Spacer()
                    Text("主人：先给我看天气穿搭～")
                        .font(.caption)
                        .foregroundStyle(textColors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: skinTheme.cornerRadius)
                                .fill(themeManager.cardBackgroundColor)
                        )
                }

                // 快捷选项
                HStack(spacing: 6) {
                    petChatPreviewChip("A. 搭一套", skinTheme: skinTheme)
                    petChatPreviewChip("B. 看天气", skinTheme: skinTheme)
                    petChatPreviewChip("C. 找裙子", skinTheme: skinTheme)
                }
            }
        }
        .padding()
        .background(previewCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardColors.accentRGBA.color.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func petChatPreviewChip(_ text: String, skinTheme: PetChatSkinTheme) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(skinTheme.resolvedQuickOptionTextColor(themeManager: themeManager, colorScheme: colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(skinTheme.resolvedQuickOptionFill(themeManager: themeManager, colorScheme: colorScheme))
            .overlay(
                Capsule()
                    .stroke(skinTheme.resolvedQuickOptionStroke(themeManager: themeManager, colorScheme: colorScheme), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

}

// MARK: - 图例项
struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
