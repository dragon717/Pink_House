//
//  MagicColorSettingsView.swift
//  ItemManager
//
//  魔法配色设置页面 - 智能配色与客制化配色 V5
//  整合主题色卡片（字体配色 + 卡片配色）
//

import SwiftUI

struct MagicColorSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // 当前选中的页签，initTab 用于首次显示的页签（外部指定）
    @State private var selectedTab: ColorSchemeMode = .custom
    @State private var initTab: ColorSchemeMode?

    // 功能解锁管理器
    @StateObject private var unlockManager = FeatureUnlockManager.shared

    // 未解锁提示弹窗
    @State private var showUnlockAlert = false

    // 卡片样式设置
    @State private var cardStyle: CardStyle = .solid
    @State private var skirtFillMode: SkirtFillMode = .transparent
    @State private var transparentOpacity: Double = 1.0
    @State private var tintOpacity: Double = 0.2

    // 我的主题方案展开状态
    @State private var isMyThemesExpanded: Bool = false

    // 主题背景 - 不使用全局模糊
    private var themeBackground: some View {
        Group {
            switch themeManager.effectiveBackgroundStyle {
            case .color:
                themeManager.backgroundColor
            case .image:
                if let image = themeManager.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // 没有图片时回退到背景色
                    themeManager.backgroundColor
                }
            }
        }
        .ignoresSafeArea()
    }

    init(initialTab: ColorSchemeMode? = nil) {
        _initTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 底层背景
                themeBackground
                
                VStack(spacing: 0) {
                    // 预览区域 - 主题色卡片示例
                    ThemePreviewSection()
                        .frame(height: 260)

                    // 内容区域
                    ScrollView {
                        VStack(spacing: 20) {
                            // 配色模式页签（原生魔法配色 / 客制化配色）
                            colorSchemeModeTabs

                            // 卡片样式设置（所有模式共用）
                            CardStyleSection(
                                cardStyle: $cardStyle,
                                skirtFillMode: $skirtFillMode,
                                transparentOpacity: $transparentOpacity,
                                tintOpacity: $tintOpacity
                            )

                            // 配色设置内容
                            switch selectedTab {
                            case .magic:
                                MagicColorTabContent()
                            case .custom:
                                CustomColorTabContent(
                                    isMyThemesExpanded: $isMyThemesExpanded,
                                    onPresetSelected: { preset in
                                        applyPreset(preset)
                                    },
                                    onPersonalizationTap: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isMyThemesExpanded.toggle()
                                        }
                                    }
                                )
                            }

                            // 我的主题方案模块（点击个性化后展开）
                            if selectedTab == .custom && isMyThemesExpanded {
                                MagicThemeModuleSection()
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("主题配色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".appLocalized) { dismiss() }
                }
            }
            .alert("魔法配色未解锁".appLocalized, isPresented: $showUnlockAlert) {
                Button("知道了".appLocalized, role: .cancel) { }
            } message: {
                let condition = unlockManager.getCondition(for: .themeCustomize)
                Text(condition.localizedDescription)
            }
            .onAppear {
                NotificationCenter.default.post(name: .magicColorSettingsOpened, object: nil)
                // 优先使用外部指定的初始页签
                if let tab = initTab {
                    selectedTab = tab
                } else {
                    let savedMode = themeManager.colorSchemeMode
                    if savedMode == .magic && !unlockManager.hasEffectiveAccess(.themeCustomize) {
                        selectedTab = .custom
                        themeManager.switchColorSchemeMode(to: .custom)
                    } else {
                        selectedTab = savedMode
                    }
                }
                cardStyle = themeManager.cardStyle
                skirtFillMode = themeManager.skirtFillMode
                transparentOpacity = themeManager.transparentOpacity
                tintOpacity = themeManager.tintOpacity

                // 如果当前是客制化配色且没有选中预设（即使用个性化主题），默认展开我的主题方案
                let config = themeManager.themeColorConfig
                if config.colorSchemeMode == .custom && config.customColorConfig.selectedPresetId == nil {
                    isMyThemesExpanded = true
                }
            }
        }
    }

    // MARK: - 配色模式页签
    private var colorSchemeModeTabs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配色模式")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
                .padding(.horizontal, 4)

            Picker("配色模式", selection: $selectedTab) {
                ForEach(ColorSchemeMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .captureGuideTarget(.themeColorModeTabs)
            .onChange(of: selectedTab) { _, newValue in
                if newValue == .magic && !unlockManager.hasEffectiveAccess(.themeCustomize) {
                    // 未解锁时弹窗提示，并切回客制化页签
                    selectedTab = .custom
                    themeManager.switchColorSchemeMode(to: .custom)
                    showUnlockAlert = true
                } else {
                    themeManager.switchColorSchemeMode(to: newValue)
                    NotificationCenter.default.post(
                        name: .magicColorModeChanged,
                        object: nil,
                        userInfo: ["mode": newValue.rawValue]
                    )
                }
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

            // 当前调色板展示 - 字体颜色
            VStack(alignment: .leading, spacing: 12) {
                Text("字体配色")
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

            // 卡片背景色展示
            VStack(alignment: .leading, spacing: 12) {
                Text("卡片背景")
                    .font(.headline)
                    .padding(.horizontal, 4)

                // 卡片背景色预览
                HStack(spacing: 12) {
                    // 卡片背景色
                    VStack(alignment: .leading, spacing: 8) {
                        Text("卡片背景色")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.primaryTextColor)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.cardBackgroundColor)
                            .frame(height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.accentTextColor.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                Text("示例卡片")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.primaryTextColor)
                            )

                        Text("基于背景色智能生成")
                            .font(.caption2)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 强调色
                    VStack(alignment: .leading, spacing: 8) {
                        Text("强调色")
                            .font(.subheadline)
                            .foregroundStyle(themeManager.primaryTextColor)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeManager.accentTextColor.opacity(0.2))
                            .frame(height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.accentTextColor.opacity(0.5), lineWidth: 1)
                            )
                            .overlay(
                                Text("标签/按钮")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.accentTextColor)
                            )

                        Text("用于标签和高亮")
                            .font(.caption2)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - 客制化配色页签内容
struct CustomColorTabContent: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    @Binding var isMyThemesExpanded: Bool
    let onPresetSelected: (ThemePreset) -> Void
    let onPersonalizationTap: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // 预设主题区域
            presetThemesSection
        }
    }

    // MARK: - 预设主题区域
    private var presetThemesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预设主题")
                .font(.headline)
                .padding(.horizontal, 4)

            // 预设主题网格（4个预设 + 个性化豆腐块）
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

                // 个性化豆腐块 - 点击展开我的主题方案
                // 当选中个性化主题（即没有选中预设）时，显示为选中状态
                let isPersonalizationSelected = themeManager.colorSchemeMode == .custom
                    && themeManager.themeColorConfig.customColorConfig.selectedPresetId == nil
                CustomThemeButton(
                    isSelected: isPersonalizationSelected
                ) {
                    onPersonalizationTap()
                }
                .captureGuideTarget(.themeCustomPersonalizationEntry)
            }
        }
    }
}

// MARK: - 萌宠对话皮肤选择区域
struct PetChatSkinSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("萌宠对话皮肤")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(PetChatSkinTheme.allCases) { skin in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            themeManager.petChatSkinTheme = skin
                        }
                    } label: {
                        HStack(spacing: 12) {
                            // 皮肤颜色预览
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: skin.resolvedUserBubbleColors(themeManager: themeManager, colorScheme: colorScheme),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(skin.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.primaryTextColor)
                                Text(skin.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                            }

                            Spacer()

                            if themeManager.petChatSkinTheme == skin {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(themeManager.accentTextColor)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .background(
                        themeManager.petChatSkinTheme == skin
                            ? themeManager.accentTextColor.opacity(colorScheme == .dark ? 0.15 : 0.1)
                            : Color.clear
                    )

                    if skin != PetChatSkinTheme.allCases.last {
                        Divider()
                            .padding(.leading, 46)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.5 : 0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - 预览
#Preview {
    MagicColorSettingsView()
        .environment(ThemeManager.shared)
}

// MARK: - 魔法配色页面包装（用于从魔法任务跳转，自动切换到魔法配色标签）
struct MagicColorSettingsViewWithMagicTab: View {
    var body: some View {
        MagicColorSettingsView(initialTab: .magic)
    }
}

// MARK: - 客制化配色页面包装（用于从魔法任务跳转，自动切换到客制化配色标签）
struct MagicColorSettingsViewWithCustomTab: View {
    var body: some View {
        MagicColorSettingsView(initialTab: .custom)
    }
}
