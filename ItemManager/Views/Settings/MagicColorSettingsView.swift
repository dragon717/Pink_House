//
//  MagicColorSettingsView.swift
//  ItemManager
//
//  魔法配色设置页面 - 智能配色与客制化配色 V2
//

import SwiftUI

struct MagicColorSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: ColorSchemeMode = .magic
    @State private var showingColorPicker = false
    @State private var colorPickerType: ColorPickerType = .primary
    
    // 客制化配色临时存储
    @State private var customPrimaryColor: Color = .black
    @State private var customSecondaryColor: Color = .gray
    @State private var customTertiaryColor: Color = .gray.opacity(0.6)
    @State private var customAccentColor: Color = .pink
    
    enum ColorPickerType {
        case primary, secondary, tertiary, accent
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 预览区域 - 裙子卡片示例
                PreviewCardSection(
                    selectedTab: selectedTab,
                    customPrimaryColor: customPrimaryColor,
                    customSecondaryColor: customSecondaryColor,
                    customTertiaryColor: customTertiaryColor,
                    customAccentColor: customAccentColor
                )
                .frame(height: 220)
                
                // 系统原生页签切换
                Picker("配色模式", selection: $selectedTab) {
                    ForEach(ColorSchemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedTab) { oldValue, newValue in
                    // 切换页签时立即生效并持久化
                    themeManager.switchColorSchemeMode(to: newValue)
                }
                
                // 内容区域
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .magic:
                            MagicColorTabContent()
                        case .custom:
                            CustomColorTabContent(
                                primaryColor: $customPrimaryColor,
                                secondaryColor: $customSecondaryColor,
                                tertiaryColor: $customTertiaryColor,
                                accentColor: $customAccentColor,
                                onColorTap: { type in
                                    colorPickerType = type
                                    showingColorPicker = true
                                },
                                onColorChange: {
                                    // 颜色变化时实时保存
                                    saveCustomColors()
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
                // 同步当前模式到本地状态
                selectedTab = themeManager.colorSchemeMode
                // 加载当前客制化颜色
                loadCustomColors()
            }
        }
    }
    
    // MARK: - 加载客制化颜色
    private func loadCustomColors() {
        let config = themeManager.themeColorConfig
        customPrimaryColor = config.customPrimaryRGBA.color
        customSecondaryColor = config.customSecondaryRGBA.color
        customTertiaryColor = config.customTertiaryRGBA.color
        customAccentColor = config.customAccentRGBA.color
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
        switch colorPickerType {
        case .primary: return $customPrimaryColor
        case .secondary: return $customSecondaryColor
        case .tertiary: return $customTertiaryColor
        case .accent: return $customAccentColor
        }
    }
    
    // MARK: - 重置颜色
    private func resetColorToDefault() {
        switch colorPickerType {
        case .primary:
            customPrimaryColor = colorScheme == .dark ? .white : .black
        case .secondary:
            customSecondaryColor = .gray
        case .tertiary:
            customTertiaryColor = .gray.opacity(0.6)
        case .accent:
            customAccentColor = .pink
        }
        // 保存到配置
        saveCustomColors()
    }
    
    // MARK: - 保存客制化颜色
    private func saveCustomColors() {
        themeManager.updateCustomColors(
            primary: customPrimaryColor,
            secondary: customSecondaryColor,
            tertiary: customTertiaryColor,
            accent: customAccentColor
        )
    }
}

// MARK: - 预览卡片区域
struct PreviewCardSection: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    let selectedTab: ColorSchemeMode
    let customPrimaryColor: Color
    let customSecondaryColor: Color
    let customTertiaryColor: Color
    let customAccentColor: Color
    
    // 根据当前选中的页签返回对应的颜色
    private var previewColors: (primary: Color, secondary: Color, tertiary: Color, accent: Color) {
        switch selectedTab {
        case .magic:
            // 魔法配色：使用容器就近配色
            let palette = themeManager.getPaletteForContainer(
                containerBackground: .ultraThinMaterial,
                colorScheme: colorScheme
            )
            return (
                palette.primary,
                palette.secondary,
                palette.tertiary,
                palette.accent
            )
        case .custom:
            // 客制化配色：直接使用自定义颜色
            return (
                customPrimaryColor,
                customSecondaryColor,
                customTertiaryColor,
                customAccentColor
            )
        }
    }
    
    var body: some View {
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
                    // 图片占位
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.pink.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "tshirt.fill")
                                .font(.title2)
                                .foregroundStyle(previewColors.accent.opacity(0.5))
                        )
                    
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
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
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
            // 添加遮罩确保文字可读
            Color.black.opacity(themeManager.backgroundStyle == .image ? 0.3 : 0)
        )
        .ignoresSafeArea(edges: .top)
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
            
            // 背景信息
            VStack(alignment: .leading, spacing: 12) {
                Text("背景检测")
                    .font(.headline)
                    .padding(.horizontal, 4)
                
                HStack(spacing: 12) {
                    Image(systemName: themeManager.backgroundStyle == .image ? "photo" : "paintpalette")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(themeManager.backgroundStyle == .image ? "图片背景" : "纯色背景")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if themeManager.backgroundStyle == .color {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(themeManager.backgroundColor)
                                    .frame(width: 12, height: 12)
                                Text("亮度: \(Int(themeManager.backgroundColor.luminance * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("自动提取主色调")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(themeManager.backgroundColor.isDark ? "暗色" : "亮色")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(themeManager.backgroundColor.isDark ? Color.gray.opacity(0.3) : Color.yellow.opacity(0.3))
                        )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
            
            // 说明文字
            VStack(alignment: .leading, spacing: 8) {
                Label("算法会根据背景亮度自动选择黑/白文字", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("卡片容器会根据材质自动调整文字颜色", systemImage: "rectangle.stack")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - 客制化配色页签内容
struct CustomColorTabContent: View {
    @Binding var primaryColor: Color
    @Binding var secondaryColor: Color
    @Binding var tertiaryColor: Color
    @Binding var accentColor: Color
    let onColorTap: (MagicColorSettingsView.ColorPickerType) -> Void
    let onColorChange: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // 提示
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("点击颜色块可以自定义每个层级的颜色")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
            )
            
            // 颜色设置列表
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
            // 监听颜色变化并保存
            .onChange(of: primaryColor) { _, _ in onColorChange() }
            .onChange(of: secondaryColor) { _, _ in onColorChange() }
            .onChange(of: tertiaryColor) { _, _ in onColorChange() }
            .onChange(of: accentColor) { _, _ in onColorChange() }
            
            // 预设配色方案
            VStack(alignment: .leading, spacing: 12) {
                Text("预设方案")
                    .font(.headline)
                    .padding(.horizontal, 4)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    PresetColorButton(
                        name: "经典黑",
                        colors: [.black, .gray, .gray.opacity(0.6), .pink],
                        onTap: { applyPreset(primary: .black, secondary: .gray, tertiary: .gray.opacity(0.6), accent: .pink) }
                    )
                    
                    PresetColorButton(
                        name: "纯白",
                        colors: [.white, .white.opacity(0.8), .white.opacity(0.6), .pink],
                        onTap: { applyPreset(primary: .white, secondary: .white.opacity(0.8), tertiary: .white.opacity(0.6), accent: .pink) }
                    )
                    
                    PresetColorButton(
                        name: "暖棕",
                        colors: [Color(hex: "3D2B1F"), Color(hex: "6B4423"), Color(hex: "A0522D"), Color(hex: "D2691E")],
                        onTap: { applyPreset(primary: Color(hex: "3D2B1F"), secondary: Color(hex: "6B4423"), tertiary: Color(hex: "A0522D"), accent: Color(hex: "D2691E")) }
                    )
                }
            }
        }
    }
    
    private func applyPreset(primary: Color, secondary: Color, tertiary: Color, accent: Color) {
        primaryColor = primary
        secondaryColor = secondary
        tertiaryColor = tertiary
        accentColor = accent
        // 应用预设后立即保存
        onColorChange()
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
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
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
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
