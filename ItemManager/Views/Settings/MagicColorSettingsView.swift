//
//  MagicColorSettingsView.swift
//  ItemManager
//
//  魔法配色设置页面 - 智能配色与客制化配色 V4
//  整合主题色卡片（字体配色 + 卡片配色）
//

import SwiftUI

struct MagicColorSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // 当前选中的页签
    @State private var selectedTab: ColorSchemeMode = .custom

    // 功能解锁管理器
    @StateObject private var unlockManager = FeatureUnlockManager.shared

    // 颜色选择器状态
    @State private var showingColorPicker = false
    @State private var colorPickerType: ColorPickerType = .primary

    // 未解锁提示弹窗
    @State private var showUnlockAlert = false

    // 卡片样式设置
    @State private var cardStyle: CardStyle = .solid
    @State private var skirtFillMode: SkirtFillMode = .transparent
    @State private var transparentOpacity: Double = 1.0
    @State private var tintOpacity: Double = 0.2

    enum ColorPickerType {
        case primary, secondary, tertiary, accent
        case cardBackground, cardAccent, deposit, finalPayment
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 预览区域 - 主题色卡片示例
                ThemePreviewSection()
                    .frame(height: 260)

                // 系统原生页签切换
                Picker("配色模式", selection: $selectedTab) {
                    ForEach(ColorSchemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTab) { _, newValue in
                    if newValue == .magic && !unlockManager.isUnlocked(.themeCustomize) {
                        // 未解锁时弹窗提示，并切回客制化页签
                        selectedTab = .custom
                        themeManager.switchColorSchemeMode(to: .custom)
                        showUnlockAlert = true
                    } else {
                        themeManager.switchColorSchemeMode(to: newValue)
                    }
                }

                // 内容区域
                ScrollView {
                    VStack(spacing: 20) {
                        NavigationLink(destination: PetChatSkinSettingsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "message.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.pink)
                                    .frame(width: 36, height: 36)
                                    .background(Color.pink.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("魔法皮肤")
                                        .font(.headline)
                                        .foregroundStyle(themeManager.primaryTextColor)
                                    Text("萌宠对话皮肤设置与预览")
                                        .font(.caption)
                                        .foregroundStyle(themeManager.secondaryTextColor)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.systemBackground).opacity(0.75))
                            )
                        }
                        .buttonStyle(.plain)

                        // 卡片样式设置（所有模式共用）
                        CardStyleSection(
                            cardStyle: $cardStyle,
                            skirtFillMode: $skirtFillMode,
                            transparentOpacity: $transparentOpacity,
                            tintOpacity: $tintOpacity
                        )

                        MagicThemeModuleSection()

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
            .navigationTitle("主题配色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingColorPicker) {
                ThemeColorPickerSheet(
                    title: colorPickerTitle,
                    colorType: colorPickerType,
                    selectedColor: bindingForColorPickerType(),
                    onReset: { resetColorToDefault() }
                )
            }
            .alert("魔法配色未解锁", isPresented: $showUnlockAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                let condition = unlockManager.getCondition(for: .themeCustomize)
                Text(condition.description)
            }
            .onAppear {
                let savedMode = themeManager.colorSchemeMode
                if savedMode == .magic && !unlockManager.isUnlocked(.themeCustomize) {
                    selectedTab = .custom
                    themeManager.switchColorSchemeMode(to: .custom)
                } else {
                    selectedTab = savedMode
                }
                cardStyle = themeManager.cardStyle
                skirtFillMode = themeManager.skirtFillMode
                transparentOpacity = themeManager.transparentOpacity
                tintOpacity = themeManager.tintOpacity
            }
        }
    }

    // MARK: - 应用预设方案
    private func applyPreset(_ preset: ThemePreset) {
        var newConfig = themeManager.themeColorConfig
        newConfig.customColorConfig.selectedPresetId = preset.id
        newConfig.colorSchemeMode = .custom

        // 将预设的颜色值同步到 currentCustom，确保切换回客制化时基于当前预设
        newConfig.customColorConfig.currentCustom.textPrimaryRGBA = preset.textPrimaryRGBA
        newConfig.customColorConfig.currentCustom.textSecondaryRGBA = preset.textSecondaryRGBA
        newConfig.customColorConfig.currentCustom.textTertiaryRGBA = preset.textTertiaryRGBA
        newConfig.customColorConfig.currentCustom.textAccentRGBA = preset.textAccentRGBA
        newConfig.customColorConfig.currentCustom.cardConfig = preset.cardConfig

        // 同步暗夜模式配色（如果预设支持）
        if preset.supportsDarkMode {
            newConfig.customColorConfig.currentCustom.darkTextPrimaryRGBA = preset.darkTextPrimaryRGBA ?? preset.textPrimaryRGBA
            newConfig.customColorConfig.currentCustom.darkTextSecondaryRGBA = preset.darkTextSecondaryRGBA ?? preset.textSecondaryRGBA
            newConfig.customColorConfig.currentCustom.darkTextTertiaryRGBA = preset.darkTextTertiaryRGBA ?? preset.textTertiaryRGBA
            newConfig.customColorConfig.currentCustom.darkTextAccentRGBA = preset.darkTextAccentRGBA ?? preset.textAccentRGBA
            newConfig.customColorConfig.currentCustom.darkCardConfig = preset.darkCardConfig ?? preset.cardConfig
        }

        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }

    // MARK: - 颜色选择器标题
    private var colorPickerTitle: String {
        switch colorPickerType {
        case .primary: return "主标题颜色"
        case .secondary: return "副标题颜色"
        case .tertiary: return "辅助文字颜色"
        case .accent: return "强调色"
        case .cardBackground: return "卡片背景色"
        case .cardAccent: return "卡片强调色"
        case .deposit: return "定金标记色"
        case .finalPayment: return "尾款标记色"
        }
    }

    // MARK: - 颜色选择器绑定
    private func bindingForColorPickerType() -> Binding<Color> {
        let config = themeManager.themeColorConfig.customColorConfig
        let isDark = colorScheme == .dark

        switch colorPickerType {
        case .primary:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextPrimaryRGBA : config.currentCustom.textPrimaryRGBA).color },
                set: { updateTextColor($0, for: \.textPrimaryRGBA, dark: \.darkTextPrimaryRGBA) }
            )
        case .secondary:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextSecondaryRGBA : config.currentCustom.textSecondaryRGBA).color },
                set: { updateTextColor($0, for: \.textSecondaryRGBA, dark: \.darkTextSecondaryRGBA) }
            )
        case .tertiary:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextTertiaryRGBA : config.currentCustom.textTertiaryRGBA).color },
                set: { updateTextColor($0, for: \.textTertiaryRGBA, dark: \.darkTextTertiaryRGBA) }
            )
        case .accent:
            return Binding(
                get: { (isDark ? config.currentCustom.darkTextAccentRGBA : config.currentCustom.textAccentRGBA).color },
                set: { updateTextColor($0, for: \.textAccentRGBA, dark: \.darkTextAccentRGBA) }
            )
        case .cardBackground:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.backgroundRGBA : config.currentCustom.cardConfig.backgroundRGBA).color },
                set: { updateCardColor($0, for: \.backgroundRGBA) }
            )
        case .cardAccent:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.accentRGBA : config.currentCustom.cardConfig.accentRGBA).color },
                set: { updateCardColor($0, for: \.accentRGBA) }
            )
        case .deposit:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.depositRGBA : config.currentCustom.cardConfig.depositRGBA).color },
                set: { updateCardColor($0, for: \.depositRGBA) }
            )
        case .finalPayment:
            return Binding(
                get: { (isDark ? config.currentCustom.darkCardConfig.finalPaymentRGBA : config.currentCustom.cardConfig.finalPaymentRGBA).color },
                set: { updateCardColor($0, for: \.finalPaymentRGBA) }
            )
        }
    }

    private func updateTextColor(_ color: Color, for keyPath: WritableKeyPath<UserCustomTheme, ColorRGBA>, dark darkKeyPath: WritableKeyPath<UserCustomTheme, ColorRGBA>) {
        guard let rgba = color.rgba else { return }
        var newConfig = themeManager.themeColorConfig
        let isDark = colorScheme == .dark
        if isDark {
            newConfig.customColorConfig.currentCustom[keyPath: darkKeyPath] = rgba
        } else {
            newConfig.customColorConfig.currentCustom[keyPath: keyPath] = rgba
        }
        // 切换到自定义模式
        newConfig.customColorConfig.selectedPresetId = nil
        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }

    private func updateCardColor(_ color: Color, for keyPath: WritableKeyPath<CardColorConfig, ColorRGBA>) {
        guard let rgba = color.rgba else { return }
        var newConfig = themeManager.themeColorConfig
        let isDark = colorScheme == .dark
        if isDark {
            var darkCard = newConfig.customColorConfig.currentCustom.darkCardConfig
            darkCard[keyPath: keyPath] = rgba
            newConfig.customColorConfig.currentCustom.darkCardConfig = darkCard
        } else {
            var customCard = newConfig.customColorConfig.currentCustom.cardConfig
            customCard[keyPath: keyPath] = rgba
            newConfig.customColorConfig.currentCustom.cardConfig = customCard
        }
        // 切换到自定义模式
        newConfig.customColorConfig.selectedPresetId = nil
        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }

    // MARK: - 重置颜色
    private func resetColorToDefault() {
        let isDark = colorScheme == .dark
        var newConfig = themeManager.themeColorConfig

        switch colorPickerType {
        case .primary:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextPrimaryRGBA = ColorRGBA.white
            } else {
                newConfig.customColorConfig.currentCustom.textPrimaryRGBA = ColorRGBA(r: 0.42, g: 0.36, b: 0.45)
            }
        case .secondary:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextSecondaryRGBA = ColorRGBA(r: 0.70, g: 0.65, b: 0.75)
            } else {
                newConfig.customColorConfig.currentCustom.textSecondaryRGBA = ColorRGBA(r: 0.61, g: 0.54, b: 0.65)
            }
        case .tertiary:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextTertiaryRGBA = ColorRGBA(r: 0.55, g: 0.50, b: 0.60)
            } else {
                newConfig.customColorConfig.currentCustom.textTertiaryRGBA = ColorRGBA(r: 0.77, g: 0.71, b: 0.80)
            }
        case .accent:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkTextAccentRGBA = ColorRGBA(r: 0.90, g: 0.70, b: 0.85)
            } else {
                newConfig.customColorConfig.currentCustom.textAccentRGBA = ColorRGBA(r: 0.85, g: 0.65, b: 0.78)
            }
        case .cardBackground:
            let defaultBg = isDark ? ColorRGBA(r: 0.25, g: 0.20, b: 0.28) : ColorRGBA(r: 1.0, g: 0.94, b: 0.96)
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.backgroundRGBA = defaultBg
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.backgroundRGBA = defaultBg
            }
        case .cardAccent:
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.accentRGBA = ColorRGBA(r: 0.70, g: 0.60, b: 0.75)
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.accentRGBA = ColorRGBA(r: 0.85, g: 0.75, b: 0.85)
            }
        case .deposit:
            let gold = ColorRGBA(r: 1.0, g: 0.84, b: 0.0)
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.depositRGBA = gold
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.depositRGBA = gold
            }
        case .finalPayment:
            let pink = ColorRGBA(r: 1.0, g: 0.41, b: 0.71)
            if isDark {
                newConfig.customColorConfig.currentCustom.darkCardConfig.finalPaymentRGBA = pink
            } else {
                newConfig.customColorConfig.currentCustom.cardConfig.finalPaymentRGBA = pink
            }
        }

        newConfig.customColorConfig.selectedPresetId = nil
        newConfig.customColorConfig.currentCustom.updatedAt = Date()
        themeManager.themeColorConfig = newConfig
    }
}

// MARK: - 主题预览区域
struct ThemePreviewSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    // 计算当前主题 - 根据配色模式返回不同的主题
    private var currentTheme: ThemePreset {
        let isDark = colorScheme == .dark
        switch themeManager.colorSchemeMode {
        case .magic:
            // 魔法配色：使用自适应调色板生成主题
            return ThemePreset.fromAdaptivePalette(
                themeManager.adaptivePalette,
                cardBackground: themeManager.cardBackgroundColor,
                isDarkMode: isDark
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
        ZStack {
            // 背景
            themeBackground

            // 预览内容 - 主题色卡片示例
            VStack(spacing: 12) {
                // 标签
                HStack {
                    Text("主题预览")
                        .font(.caption)
                        .foregroundStyle(textColors.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // 主题色卡片示例 - 应用卡片样式设置
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

                // 图例说明
                HStack(spacing: 16) {
                    LegendItem(color: textColors.primary, label: "主要")
                    LegendItem(color: textColors.secondary, label: "次要")
                    LegendItem(color: textColors.tertiary, label: "辅助")
                    LegendItem(color: textColors.accent, label: "强调")
                }
                .padding(.horizontal, 20)

                // 卡片配色图例
                HStack(spacing: 12) {
                    CardLegendItem(color: cardColors.backgroundRGBA.color, label: "卡片背景")
                    CardLegendItem(color: cardColors.accentRGBA.color, label: "卡片强调")
                    CardLegendItem(color: cardColors.depositRGBA.color, label: "定金")
                    CardLegendItem(color: cardColors.finalPaymentRGBA.color, label: "尾款")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private var themeBackground: some View {
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
        // 添加暗色遮罩提高文字可读性，纯色背景使用较低的透明度
        .overlay(
            Color.black.opacity(themeManager.backgroundStyle == .image ? 0.3 : 0.1)
        )
    }
}

// MARK: - 卡片图例项
struct CardLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
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
                        Slider(value: $transparentOpacity, in: 0.1...0.5, step: 0.05)
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

            // 裙装填充模式
            VStack(alignment: .leading, spacing: 12) {
                Text("裙装图片填充")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("填充模式", selection: $skirtFillMode) {
                    Text("实色").tag(SkirtFillMode.solid)
                    Text("半透明").tag(SkirtFillMode.transparent)
                    Text("全透明").tag(SkirtFillMode.fullyTransparent)
                    Text("色调").tag(SkirtFillMode.tinted)
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
                        Text("根据背景和容器自动调整字体和卡片颜色")
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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var unlockManager = FeatureUnlockManager.shared

    let onColorTap: (MagicColorSettingsView.ColorPickerType) -> Void
    let onPresetSelected: (ThemePreset) -> Void

    // 检查魔法配色是否已解锁
    private var isMagicColorUnlocked: Bool {
        unlockManager.isUnlocked(.themeCustomize)
    }

    // 当前主题
    private var currentTheme: ThemePreset {
        themeManager.themeColorConfig.currentTheme(forDarkMode: colorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 20) {
            // 预设主题区域
            presetThemesSection

            // 自定义颜色设置 - 仅在魔法配色解锁时显示
            if isMagicColorUnlocked {
                customColorsSection
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
        }
    }

    // MARK: - 预设主题区域
    private var presetThemesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预设主题")
                .font(.headline)
                .padding(.horizontal, 4)

            // 4个梦群日历主题 + 客制化 = 5个主题
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // 预设主题（4个梦群日历主题）
                ForEach(CustomColorPresets.all) { preset in
                    ThemePresetButton(
                        preset: preset,
                        isSelected: themeManager.themeColorConfig.customColorConfig.selectedPresetId == preset.id
                    ) {
                        onPresetSelected(preset)
                    }
                }

                // 客制化选项
                CustomThemeButton(
                    isSelected: themeManager.themeColorConfig.customColorConfig.selectedPresetId == nil
                ) {
                    var newConfig = themeManager.themeColorConfig
                    newConfig.customColorConfig.selectedPresetId = nil
                    themeManager.themeColorConfig = newConfig
                }
            }
        }
    }

    // MARK: - 自定义颜色区域
    private var customColorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义颜色")
                .font(.headline)
                .padding(.horizontal, 4)

            // 字体配色
            VStack(alignment: .leading, spacing: 8) {
                Text("字体配色")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    CustomColorRow(
                        title: "主标题",
                        description: "最重要的文字",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).primary.color,
                        onTap: { onColorTap(.primary) }
                    )

                    Divider()

                    CustomColorRow(
                        title: "副标题",
                        description: "次要文字",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).secondary.color,
                        onTap: { onColorTap(.secondary) }
                    )

                    Divider()

                    CustomColorRow(
                        title: "辅助文字",
                        description: "辅助信息",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).tertiary.color,
                        onTap: { onColorTap(.tertiary) }
                    )

                    Divider()

                    CustomColorRow(
                        title: "强调色",
                        description: "按钮、标签",
                        color: currentTheme.textColors(forDarkMode: colorScheme == .dark).accent.color,
                        onTap: { onColorTap(.accent) }
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }

            // 卡片配色
            VStack(alignment: .leading, spacing: 8) {
                Text("卡片配色")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    CustomColorRow(
                        title: "卡片背景",
                        description: "卡片背景色",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).backgroundRGBA.color,
                        onTap: { onColorTap(.cardBackground) }
                    )

                    Divider()

                    CustomColorRow(
                        title: "卡片强调",
                        description: "标签、按钮",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).accentRGBA.color,
                        onTap: { onColorTap(.cardAccent) }
                    )

                    Divider()

                    CustomColorRow(
                        title: "定金标记",
                        description: "定金日期标记",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).depositRGBA.color,
                        onTap: { onColorTap(.deposit) }
                    )

                    Divider()

                    CustomColorRow(
                        title: "尾款标记",
                        description: "尾款日期标记",
                        color: currentTheme.cardColors(forDarkMode: colorScheme == .dark).finalPaymentRGBA.color,
                        onTap: { onColorTap(.finalPayment) }
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
        }
    }
}

// MARK: - 主题预设按钮
struct ThemePresetButton: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // 预览卡片
                RoundedRectangle(cornerRadius: 12)
                    .fill(preset.cardColors(forDarkMode: colorScheme == .dark).backgroundRGBA.color)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 4) {
                            let textColors = preset.textColors(forDarkMode: colorScheme == .dark)
                            Circle().fill(textColors.primary.color).frame(width: 8, height: 8)
                            Circle().fill(textColors.secondary.color).frame(width: 8, height: 8)
                            Circle().fill(textColors.accent.color).frame(width: 8, height: 8)
                            Spacer()
                        }
                        .padding(8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
                    )

                Text(preset.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 客制化主题按钮
struct CustomThemeButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // 预览卡片
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(height: 60)
                    .overlay(
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
                    )

                Text("个性化")
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
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

// MARK: - 颜色选择器 Sheet
struct ThemeColorPickerSheet: View {
    let title: String
    let colorType: MagicColorSettingsView.ColorPickerType
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

    // 主题相关颜色
    var themeColors: [Color] {
        switch colorType {
        case .deposit:
            // 金色系
            return [
                Color(hex: "FFD700"), Color(hex: "FFA500"),
                Color(hex: "FF8C00"), Color(hex: "DAA520"),
                Color(hex: "B8860B"), Color(hex: "F0E68C")
            ]
        case .finalPayment:
            // 粉色/红色系
            return [
                Color(hex: "FF69B4"), Color(hex: "FF1493"),
                Color(hex: "DC143C"), Color(hex: "FF6347"),
                Color(hex: "FFB6C1"), Color(hex: "FFC0CB")
            ]
        default:
            return []
        }
    }

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

                // 主题相关颜色（如果有）
                if !themeColors.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("推荐颜色")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(Array(themeColors.enumerated()), id: \.offset) { index, color in
                                Button(action: {
                                    selectedColor = color
                                }) {
                                    Circle()
                                        .fill(color)
                                        .frame(height: 40)
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
                }

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
