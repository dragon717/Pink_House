//
//  AdaptiveColorSystem+Examples.swift
//  ItemManager
//
//  智能配色系统使用示例
//

import SwiftUI

// MARK: - 使用示例

/*
 ============================================
 智能配色系统使用指南
 ============================================
 
 本系统提供以下核心功能:
 1. 自动根据背景亮度调整字体颜色
 2. 支持纯色背景、图片背景、渐变背景
 3. 提供三种重要性级别的文本颜色
 4. 支持手动覆盖和智能生成强调色
 
 */

// MARK: - 示例1: 基础使用 (推荐)

struct BasicUsageExample: View {
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        VStack(spacing: 20) {
            // 直接使用 ThemeManager 提供的颜色
            Text("主标题")
                .foregroundColor(themeManager.primaryTextColor)
            
            Text("副标题/正文")
                .foregroundColor(themeManager.secondaryTextColor)
            
            Text("辅助说明文字")
                .foregroundColor(themeManager.tertiaryTextColor)
            
            Button("强调按钮") {}
                .foregroundColor(themeManager.accentTextColor)
        }
    }
}

// MARK: - 示例2: 使用环境值 (适用于复杂视图层级)

struct EnvironmentUsageExample: View {
    var body: some View {
        VStack(spacing: 20) {
            // 使用环境值中的调色板
            Text("主标题")
                .primaryTextStyle()
            
            Text("副标题/正文")
                .secondaryTextStyle()
            
            Text("辅助说明文字")
                .tertiaryTextStyle()
        }
        // 应用自适应配色
        .adaptiveColors()
    }
}

// MARK: - 示例3: 特定背景类型的配色

struct SpecificBackgroundExample: View {
    var body: some View {
        VStack {
            // 为特定背景指定配色
            Text("深色卡片上的文字")
                .primaryTextStyle()
        }
        .padding()
        .background(Color.black)
        .cornerRadius(12)
        // 明确指定这是暗色背景
        .adaptiveColors(for: .solid(color: .black))
    }
}

// MARK: - 示例4: 图片背景上的文字

struct ImageBackgroundExample: View {
    let backgroundImage: UIImage
    
    var body: some View {
        ZStack {
            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFill()
            
            VStack {
                // 使用 SmartContrastText 确保在复杂图片上可读
                SmartContrastText("重要标题", font: .title, useOutline: true)
                
                SmartContrastText("副标题文字", font: .body)
            }
        }
    }
}

// MARK: - 示例5: 卡片组件中使用

struct AdaptiveCardExample: View {
    @Environment(\.adaptivePalette) private var palette
    
    let title: String
    let subtitle: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(palette.primary)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(palette.secondary)
            
            Divider()
                .background(palette.divider)
            
            Text(description)
                .font(.body)
                .foregroundColor(palette.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// MARK: - 示例6: 完整页面示例

struct AdaptiveColorDemoView: View {
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        ZStack {
            // 背景
            LiquidBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // 标题区
                    VStack(spacing: 8) {
                        Text("智能配色演示")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(themeManager.primaryTextColor)
                        
                        Text("根据背景自动调整字体颜色")
                            .font(.subheadline)
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                    
                    // 调色板展示
                    PalettePreviewCard()
                    
                    // 示例卡片
                    AdaptiveCardExample(
                        title: "自适应卡片",
                        subtitle: "根据背景自动调整颜色",
                        description: "这是辅助说明文字,使用第三级颜色"
                    )
                    
                    // 按钮组
                    VStack(spacing: 12) {
                        Button("主要操作") {}
                            .buttonStyle(AdaptiveButtonStyle(isPrimary: true))
                        
                        Button("次要操作") {}
                            .buttonStyle(AdaptiveButtonStyle(isPrimary: false))
                    }
                }
                .padding()
            }
        }
        // 自动应用自适应配色
        .adaptiveColors()
    }
}

// MARK: - 辅助组件

struct PalettePreviewCard: View {
    @Environment(\.adaptivePalette) private var palette
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前调色板")
                .font(.headline)
                .foregroundColor(palette.primary)
            
            HStack(spacing: 12) {
                ColorSample(color: palette.primary, label: "主色")
                ColorSample(color: palette.secondary, label: "副色")
                ColorSample(color: palette.tertiary, label: "辅助")
                ColorSample(color: palette.accent, label: "强调")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct ColorSample: View {
    let color: Color
    let label: String
    
    var body: some View {
        VStack {
            Circle()
                .fill(color)
                .frame(width: 40, height: 40)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 自适应按钮样式

struct AdaptiveButtonStyle: ButtonStyle {
    @Environment(\.adaptivePalette) private var palette
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(isPrimary ? palette.primary : palette.accent)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                isPrimary
                    ? palette.accent.opacity(0.2)
                    : palette.divider
            )
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// MARK: - 示例7: 在 List/Form 中使用

struct AdaptiveListExample: View {
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        List {
            Section {
                Text("列表项 1")
                    .foregroundColor(themeManager.primaryTextColor)
                Text("列表项 2")
                    .foregroundColor(themeManager.primaryTextColor)
            } header: {
                Text("分组标题")
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Section {
                Toggle("开关选项", isOn: .constant(true))
                    .foregroundColor(themeManager.primaryTextColor)
                
                Button("操作按钮") {}
                    .foregroundColor(themeManager.accentTextColor)
            } footer: {
                Text("这是底部说明文字")
                    .foregroundColor(themeManager.tertiaryTextColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LiquidBackground())
    }
}

// MARK: - 预览

#Preview("亮色背景") {
    AdaptiveColorDemoView()
        .environment(ThemeManager.shared)
}

#Preview("暗色背景") {
    AdaptiveColorDemoView()
        .environment(ThemeManager.shared)
        .background(Color.black)
        .adaptiveColors(for: .solid(color: .black))
}
