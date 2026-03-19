//
//  ColorSettingsComponents.swift
//  ItemManager
//
//  颜色设置共享组件
//

import SwiftUI

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
