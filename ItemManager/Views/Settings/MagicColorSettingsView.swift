//
//  MagicColorSettingsView.swift
//  ItemManager
//
//  魔法配色设置页面 - 智能配色与客制化配色 V3
//  整合卡片样式、裙子填充模式、液态玻璃效果
//

import SwiftUI

// 导入必要的类型
import UIKit

struct MagicColorSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // 当前选中的页签 - 默认选择客制化配色
    @State private var selectedTab: ColorSchemeMode = .custom
    
    // 功能解锁管理器
    @StateObject private var unlockManager = FeatureUnlockManager.shared
    
    // 颜色选择器状态
    @State private var showingColorPicker = false
    @State private var colorPickerType: ColorPickerType = .primary
    
    // 卡片样式设置
    @State private var cardStyle: CardStyle = .solid
    @State private var skirtFillMode: SkirtFillMode = .transparent
    @State private var transparentOpacity: Double = 1.0
    @State private var tintOpacity: Double = 0.2
    
    enum ColorPickerType {
        case primary, secondary, tertiary, accent
    }
    
    // 计算预览颜色 - 直接在主视图中计算，确保响应式更新
    private var previewColors: (primary: Color, secondary: Color, tertiary: Color, accent: Color) {
        switch selectedTab {
        case .magic:
            let palette = themeManager.getPaletteForContainer(
                containerBackground: .ultraThinMaterial,
                colorScheme: colorScheme
            )
            return (palette.primary, palette.secondary, palette.tertiary, palette.accent)
        case .custom:
            // 根据当前暗夜/亮色模式返回对应颜色
            let isDark = colorScheme == .dark
            let config = themeManager.themeColorConfig
            if isDark {
                return (
                    config.darkPrimaryRGBA.color,
                    config.darkSecondaryRGBA.color,
                    config.darkTertiaryRGBA.color,
                    config.darkAccentRGBA.color
                )
            } else {
                return (
                    config.customPrimaryRGBA.color,
                    config.customSecondaryRGBA.color,
                    config.customTertiaryRGBA.color,
                    config.customAccentRGBA.color
                )
            }
        }
    }
    
    // 预览卡片背景
    private var cardBackground: some View {
        let baseColor: Color = colorScheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.8)
        
        switch cardStyle {
        case .transparent:
            return AnyView(baseColor.opacity(transparentOpacity))
        case .fullyTransparent:
            return AnyView(Color.clear)
        case .tinted:
            return AnyView(themeManager.cardTintColor.opacity(tintOpacity))
        case .solid:
            return AnyView(baseColor)
        }
    }
    
    // 裙子图片背景颜色
    private var skirtBackgroundColor: Color {
        switch skirtFillMode {
        case .transparent:
            return Color.white.opacity(colorScheme == .dark ? 0.2 : 0.4)
        case .fullyTransparent:
            return Color.clear
        case .tinted:
            return themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.15 : 0.3)
        case .solid:
            return Color.black.opacity(colorScheme == .dark ? 0.6 : 0.1)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 预览区域 - 裙子卡片示例
                previewSection
                .frame(height: 240)
                
                // 系统原生页签切换
                Picker("配色模式", selection: $selectedTab) {
                    ForEach(ColorSchemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTab) { _, newValue in
                    // 检查魔法配色是否已解锁
                    if newValue == .magic && !unlockManager.isUnlocked(.themeCustomize) {
                        // 未解锁，切换回客制化配色
                        selectedTab = .custom
                        themeManager.switchColorSchemeMode(to: .custom)
                    } else {
                        themeManager.switchColorSchemeMode(to: newValue)
                    }
                }
                
                // 内容区域
                ScrollView {
                    VStack(spacing: 20) {
                        // 卡片样式设置（所有模式共用）
                        CardStyleSection(
                            cardStyle: $cardStyle,
                            skirtFillMode: $skirtFillMode,
                            transparentOpacity: $transparentOpacity,
                            tintOpacity: $tintOpacity
                        )
                        
                        // 配色设置
                        switch selectedTab {
                        case .magic:
                            MagicColorTabContent()
                        case .custom:
                            CustomColorTabContent(
                                onColorTap: { type in
                                    colorPickerType = type
                                    showingColorPicker = true
                                },
                                onPresetSelected: { preset in
                                    applyPreset(preset)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .background(LiquidBackground())
            .navigationTitle("字体配色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingColorPicker) {
                ColorPickerSheet(
                    title: colorPickerTitle,
                    selectedColor: bindingForColorPickerType(),
                    onReset: {
                        resetColorToDefault()
                    }
                )
            }
            .onAppear {
                // 检查魔法配色是否已解锁，如果保存的模式是魔法配色但未解锁，则切换回客制化配色
                let savedMode = themeManager.colorSchemeMode
                if savedMode == .magic && !unlockManager.isUnlocked(.themeCustomize) {
                    selectedTab = .custom
                    themeManager.switchColorSchemeMode(to: .custom)
                } else {
                    selectedTab = savedMode
                }
                // 同步卡片样式设置
                cardStyle = themeManager.cardStyle
                skirtFillMode = themeManager.skirtFillMode
                transparentOpacity = themeManager.transparentOpacity
                tintOpacity = themeManager.tintOpacity
            }
        }
    }
    
    // MARK: - 应用预设方案
    private func applyPreset(_ preset: ColorPreset) {
        print("🎨 Applying preset: \(preset.name)")
        print("   Primary: \(preset.primary)")
        print("   Secondary: \(preset.secondary)")
        print("   Tertiary: \(preset.tertiary)")
        print("   Accent: \(preset.accent)")
        
        themeManager.updateCustomColors(
            primary: preset.primary,
            secondary: preset.secondary,
            tertiary: preset.tertiary,
            accent: preset.accent
        )
        
        print("✅ Preset applied to themeManager")
    }
    
    // MARK: - 预览区域视图
    private var previewSection: some View {
        ZStack {
            // 背景
            previewBackground
            
            // 预览内容 - 模拟裙子卡片
            VStack(spacing: 12) {
                // 标签
                HStack {
                    Text("预览效果")
                        .font(.caption)
                        .foregroundStyle(previewColors.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                // 裙子卡片示例
                HStack(spacing: 12) {
                    // 图片占位（模拟裙子图片区域）
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(skirtBackgroundColor)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "tshirt.fill")
                            .font(.title2)
                            .foregroundStyle(previewColors.accent.opacity(0.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // 信息区域
                    VStack(alignment: .leading, spacing: 6) {
                        // 裙子名称 - 主要文字
                        Text("小裙子名称")
                            .font(.headline)
                            .foregroundStyle(previewColors.primary)
                        
                        // 品牌 - 次要文字
                        Text("品牌名称 · 型色")
                            .font(.subheadline)
                            .foregroundStyle(previewColors.secondary)
                        
                        // 价格和状态
                        HStack {
                            // 价格 - 主要文字
                            Text("¥999")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(previewColors.primary)
                            
                            Spacer()
                            
                            // 标签 - 强调色
                            Text("已拥有")
                                .font(.caption)
                                .foregroundStyle(previewColors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(previewColors.accent.opacity(0.15))
                                .cornerRadius(4)
                        }
                        
                        // 购买日期 - 辅助文字
                        HStack {
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundStyle(previewColors.tertiary)
                            Text("2024-01-01 购买")
                                .font(.caption)
                                .foregroundStyle(previewColors.tertiary)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                
                // 图例说明
                HStack(spacing: 16) {
                    LegendItem(color: previewColors.primary, label: "主要")
                    LegendItem(color: previewColors.secondary, label: "次要")
                    LegendItem(color: previewColors.tertiary, label: "辅助")
                    LegendItem(color: previewColors.accent, label: "强调")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }
    
    private var previewBackground: some View {
        Group {
            switch themeManager.backgroundStyle {
            case .color:
                themeManager.backgroundColor
            case .image:
                if let image = themeManager.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
        }
        .overlay(
            Color.black.opacity(themeManager.backgroundStyle == .image ? 0.3 : 0)
        )
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - 颜色选择器标题
    private var colorPickerTitle: String {
        switch colorPickerType {
        case .primary: return "主标题颜色"
        case .secondary: return "副标题颜色"
        case .tertiary: return "辅助文字颜色"
        case .accent: return "强调色"
        }
    }
    
    // MARK: - 颜色选择器绑定
    private func bindingForColorPickerType() -> Binding<Color> {
        let config = themeManager.themeColorConfig
        switch colorPickerType {
        case .primary:
            return Binding(
                get: { config.customPrimaryRGBA.color },
                set: {
                    themeManager.updateCustomColors(
                        primary: $0,
                        secondary: config.customSecondaryRGBA.color,
                        tertiary: config.customTertiaryRGBA.color,
                        accent: config.customAccentRGBA.color
                    )
                }
            )
        case .secondary:
            return Binding(
                get: { config.customSecondaryRGBA.color },
                set: {
                    themeManager.updateCustomColors(
                        primary: config.customPrimaryRGBA.color,
                        secondary: $0,
                        tertiary: config.customTertiaryRGBA.color,
                        accent: config.customAccentRGBA.color
                    )
                }
            )
        case .tertiary:
            return Binding(
                get: { config.customTertiaryRGBA.color },
                set: {
                    themeManager.updateCustomColors(
                        primary: config.customPrimaryRGBA.color,
                        secondary: config.customSecondaryRGBA.color,
                        tertiary: $0,
                        accent: config.customAccentRGBA.color
                    )
                }
            )
        case .accent:
            return Binding(
                get: { config.customAccentRGBA.color },
                set: {
                    themeManager.updateCustomColors(
                        primary: config.customPrimaryRGBA.color,
                        secondary: config.customSecondaryRGBA.color,
                        tertiary: config.customTertiaryRGBA.color,
                        accent: $0
                    )
                }
            )
        }
    }
    
    // MARK: - 重置颜色
    private func resetColorToDefault() {
        let isDark = colorScheme == .dark
        themeManager.updateCustomColors(
            primary: isDark ? .white : .black,
            secondary: .gray,
            tertiary: .gray.opacity(0.6),
            accent: .pink
        )
    }
}

// MARK: - 预设方案结构
struct ColorPreset: Equatable {
    let id = UUID()
    let name: String
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let accent: Color
    let previewColors: [Color]
    
    static func == (lhs: ColorPreset, rhs: ColorPreset) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - 卡片样式设置区域
struct CardStyleSection: View {
    @Binding var cardStyle: CardStyle
    @Binding var skirtFillMode: SkirtFillMode
    @Binding var transparentOpacity: Double
    @Binding var tintOpacity: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("卡片样式")
                .font(.headline)
                .padding(.horizontal, 4)
            
            // 卡片样式选择
            VStack(alignment: .leading, spacing: 12) {
                Text("卡片背景")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("卡片样式", selection: $cardStyle) {
                    Text("实色").tag(CardStyle.solid)
                    Text("半透明").tag(CardStyle.transparent)
                    Text("全透明").tag(CardStyle.fullyTransparent)
                    Text("色调").tag(CardStyle.tinted)
                }
                .pickerStyle(.segmented)
                .onChange(of: cardStyle) { _, newValue in
                    ThemeManager.shared.cardStyle = newValue
                }
                
                // 透明度滑块（仅半透明模式）
                if cardStyle == .transparent {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("透明度")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(transparentOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $transparentOpacity, in: 0.1...1.0, step: 0.1)
                            .onChange(of: transparentOpacity) { _, newValue in
                                ThemeManager.shared.transparentOpacity = newValue
                            }
                    }
                }
                
                // 色调滑块（仅色调模式）
                if cardStyle == .tinted {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("色调强度")
                                .font(.caption)
                            Spacer()
                            Text("\(Int(tintOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $tintOpacity, in: 0.05...0.5, step: 0.05)
                            .onChange(of: tintOpacity) { _, newValue in
                                ThemeManager.shared.tintOpacity = newValue
                            }
                    }
                }
            }
            
            Divider()
            
            // 裙子填充模式
            VStack(alignment: .leading, spacing: 12) {
                Text("裙子图片填充")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("填充模式", selection: $skirtFillMode) {
                    Text("半透明").tag(SkirtFillMode.transparent)
                    Text("全透明").tag(SkirtFillMode.fullyTransparent)
                    Text("色调").tag(SkirtFillMode.tinted)
                    Text("实色").tag(SkirtFillMode.solid)
                }
                .pickerStyle(.segmented)
                .onChange(of: skirtFillMode) { _, newValue in
                    ThemeManager.shared.skirtFillMode = newValue
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
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

// MARK: - 魔法配色页签内容
struct MagicColorTabContent: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            // 说明卡片
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundColor(.pink)
                        .frame(width: 44, height: 44)
                        .background(Color.pink.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("智能配色已启用")
                            .font(.headline)
                        Text("根据背景和容器自动调整字体颜色")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            
            // 当前调色板展示
            VStack(alignment: .leading, spacing: 12) {
                Text("当前调色板")
                    .font(.headline)
                    .padding(.horizontal, 4)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ColorInfoCard(
                        title: "主标题",
                        color: themeManager.primaryTextColor,
                        description: "最高重要性"
                    )
                    ColorInfoCard(
                        title: "副标题",
                        color: themeManager.secondaryTextColor,
                        description: "中等重要性"
                    )
                    ColorInfoCard(
                        title: "辅助文字",
                        color: themeManager.tertiaryTextColor,
                        description: "低重要性"
                    )
                    ColorInfoCard(
                        title: "强调色",
                        color: themeManager.accentTextColor,
                        description: "按钮/链接"
                    )
                }
            }
        }
    }
}

// MARK: - 客制化配色页签内容
struct CustomColorTabContent: View {
    @Environment(ThemeManager.self) private var themeManager
    @StateObject private var unlockManager = FeatureUnlockManager.shared
    
    let onColorTap: (MagicColorSettingsView.ColorPickerType) -> Void
    let onPresetSelected: (ColorPreset) -> Void
    
    // 检查魔法配色是否已解锁
    private var isMagicColorUnlocked: Bool {
        unlockManager.isUnlocked(.themeCustomize)
    }
    
    // 当前颜色 - 直接从 themeManager 读取
    private var primaryColor: Color {
        themeManager.themeColorConfig.customPrimaryRGBA.color
    }
    private var secondaryColor: Color {
        themeManager.themeColorConfig.customSecondaryRGBA.color
    }
    private var tertiaryColor: Color {
        themeManager.themeColorConfig.customTertiaryRGBA.color
    }
    private var accentColor: Color {
        themeManager.themeColorConfig.customAccentRGBA.color
    }
    
    // 预设方案
    private var presets: [ColorPreset] {
        var presets: [ColorPreset] = []
        
        // 经典黑
        presets.append(ColorPreset(
            name: "经典黑",
            primary: .black,
            secondary: .gray,
            tertiary: .gray.opacity(0.6),
            accent: .pink,
            previewColors: [.black, .gray, .gray.opacity(0.6), .pink]
        ))
        
        // 纯白
        presets.append(ColorPreset(
            name: "纯白",
            primary: .white,
            secondary: .white.opacity(0.8),
            tertiary: .white.opacity(0.6),
            accent: .pink,
            previewColors: [.white, .white.opacity(0.8), .white.opacity(0.6), .pink]
        ))
        
        // 暖棕
        let warmBrownPrimary = Color(hex: "3D2B1F")
        let warmBrownSecondary = Color(hex: "6B4423")
        let warmBrownTertiary = Color(hex: "A0522D")
        let warmBrownAccent = Color(hex: "D2691E")
        presets.append(ColorPreset(
            name: "暖棕",
            primary: warmBrownPrimary,
            secondary: warmBrownSecondary,
            tertiary: warmBrownTertiary,
            accent: warmBrownAccent,
            previewColors: [warmBrownPrimary, warmBrownSecondary, warmBrownTertiary, warmBrownAccent]
        ))
        
        // 薄荷绿
        let mintPrimary = Color(hex: "2D5A4A")
        let mintSecondary = Color(hex: "4A7C6F")
        let mintTertiary = Color(hex: "6B9B8F")
        let mintAccent = Color(hex: "3EB489")
        presets.append(ColorPreset(
            name: "薄荷绿",
            primary: mintPrimary,
            secondary: mintSecondary,
            tertiary: mintTertiary,
            accent: mintAccent,
            previewColors: [mintPrimary, mintSecondary, mintTertiary, mintAccent]
        ))
        
        return presets
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 当前颜色设置 - 仅在魔法配色解锁时显示
            if isMagicColorUnlocked {
                VStack(alignment: .leading, spacing: 12) {
                    Text("当前颜色")
                        .font(.headline)
                        .padding(.horizontal, 4)
                    
                    VStack(spacing: 12) {
                        CustomColorRow(
                            title: "主标题颜色",
                            description: "最重要的文字,如标题、价格",
                            color: primaryColor,
                            onTap: { onColorTap(.primary) }
                        )
                        
                        Divider()
                        
                        CustomColorRow(
                            title: "副标题颜色",
                            description: "次要文字,如品牌、描述",
                            color: secondaryColor,
                            onTap: { onColorTap(.secondary) }
                        )
                        
                        Divider()
                        
                        CustomColorRow(
                            title: "辅助文字颜色",
                            description: "辅助信息,如日期、状态",
                            color: tertiaryColor,
                            onTap: { onColorTap(.tertiary) }
                        )
                        
                        Divider()
                        
                        CustomColorRow(
                            title: "强调色",
                            description: "按钮、标签、链接",
                            color: accentColor,
                            onTap: { onColorTap(.accent) }
                        )
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                }
            } else {
                // 未解锁时的提示
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange)
                    Text("解锁后可自定义颜色")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            
            // 预设配色方案
            VStack(alignment: .leading, spacing: 12) {
                Text("预设方案")
                    .font(.headline)
                    .padding(.horizontal, 4)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(presets.indices, id: \.self) { index in
                        let preset = presets[index]
                        PresetColorButton(
                            name: preset.name,
                            colors: preset.previewColors,
                            isSelected: isPresetSelected(preset),
                            onTap: { onPresetSelected(preset) }
                        )
                    }
                }
            }
        }
    }
    
    private func isPresetSelected(_ preset: ColorPreset) -> Bool {
        // 简化：只比较主要颜色，使用 UIColor 进行比较
        let presetUI = UIColor(preset.primary)
        let currentUI = UIColor(primaryColor)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        presetUI.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        currentUI.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        let tolerance: CGFloat = 0.01
        return abs(r1 - r2) < tolerance &&
               abs(g1 - g2) < tolerance &&
               abs(b1 - b2) < tolerance &&
               abs(a1 - a2) < tolerance
    }
}

// MARK: - 辅助组件

struct ColorInfoCard: View {
    let title: String
    let color: Color
    let description: String
    
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct CustomColorRow: View {
    let title: String
    let description: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PresetColorButton: View {
    let name: String
    let colors: [Color]
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button {
            print("🎯 Preset button tapped: \(name)")
            onTap()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                
                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 颜色选择器 Sheet
struct ColorPickerSheet: View {
    let title: String
    @Binding var selectedColor: Color
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    // 预设颜色
    let presetColors: [Color] = [
        .black, .white,
        .red, .pink, .orange, .yellow,
        .green, .mint, .teal, .cyan,
        .blue, .indigo, .purple,
        .brown, .gray
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 当前颜色展示
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedColor)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    )
                    .padding(.horizontal)
                
                // 预设颜色
                VStack(alignment: .leading, spacing: 12) {
                    Text("预设颜色")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Array(presetColors.enumerated()), id: \.offset) { index, color in
                            Button(action: {
                                selectedColor = color
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(height: 50)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.blue : Color.white.opacity(0.2), lineWidth: selectedColor == color ? 3 : 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") {
                        onReset()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    MagicColorSettingsView()
        .environment(ThemeManager.shared)
}
