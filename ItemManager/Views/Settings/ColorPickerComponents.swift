//
//  ColorPickerComponents.swift
//  ItemManager
//
//  颜色选择器相关组件
//

import SwiftUI

// MARK: - 紧凑颜色选择器 Sheet
struct CompactColorPickerSheet: View {
    let title: String
    let colorType: ThemeColorPickerType
    @Binding var selectedColor: Color
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    // 扩展的预设颜色 - 更多选择
    let presetColors: [Color] = [
        // 基础色
        .black, .white,
        // 红色系
        .red, .pink,
        Color(hex: "FF1493"), // 深粉
        Color(hex: "DC143C"), // 猩红
        Color(hex: "B22222"), // 火砖红
        // 橙色系
        .orange,
        Color(hex: "FF8C00"), // 深橙
        Color(hex: "FF6347"), // 番茄红
        // 黄色系
        .yellow,
        Color(hex: "FFD700"), // 金色
        Color(hex: "FFA500"), // 橙色
        Color(hex: "F0E68C"), // 卡其黄
        // 绿色系
        .green, .mint,
        Color(hex: "32CD32"), // 酸橙绿
        Color(hex: "228B22"), // 森林绿
        Color(hex: "20B2AA"), // 浅海绿
        // 青色系
        .teal, .cyan,
        Color(hex: "00CED1"), // 深青
        // 蓝色系
        .blue, .indigo,
        Color(hex: "4169E1"), // 皇家蓝
        Color(hex: "0000CD"), // 中蓝
        Color(hex: "87CEEB"), // 天蓝
        // 紫色系
        .purple,
        Color(hex: "8A2BE2"), // 蓝紫
        Color(hex: "9932CC"), // 深兰花紫
        Color(hex: "DDA0DD"), // 梅花色
        // 棕色系
        .brown,
        Color(hex: "D2691E"), // 巧克力色
        // 灰色系
        .gray,
        Color(hex: "808080"), // 灰色
        Color(hex: "A9A9A9"), // 暗灰
        Color(hex: "C0C0C0"), // 银灰
    ]

    // 主题相关推荐颜色
    var themeColors: [Color] {
        switch colorType {
        case .deposit:
            // 金色系
            return [
                Color(hex: "FFD700"), // 金色
                Color(hex: "FFA500"), // 橙色
                Color(hex: "FF8C00"), // 深橙
                Color(hex: "DAA520"), // 金菊黄
                Color(hex: "B8860B"), // 暗金
                Color(hex: "F0E68C"), // 卡其黄
                Color(hex: "EEE8AA"), // 浅黄
                Color(hex: "BDB76B"), // 深卡其
            ]
        case .finalPayment:
            // 粉色/红色系
            return [
                Color(hex: "FF69B4"), // 热粉
                Color(hex: "FF1493"), // 深粉
                Color(hex: "DC143C"), // 猩红
                Color(hex: "FF6347"), // 番茄红
                Color(hex: "FFB6C1"), // 浅粉
                Color(hex: "FFC0CB"), // 粉红
                Color(hex: "DB7093"), // 浅紫粉
                Color(hex: "C71585"), // 中紫红
            ]
        case .accent:
            // 强调色推荐
            return [
                Color(hex: "FF69B4"), // 热粉
                Color(hex: "9370DB"), // 中紫
                Color(hex: "20B2AA"), // 浅海绿
                Color(hex: "FF6347"), // 番茄红
                Color(hex: "FFD700"), // 金色
                Color(hex: "00BFFF"), // 深天蓝
                Color(hex: "FF8C00"), // 深橙
                Color(hex: "DA70D6"), // 兰花紫
            ]
        default:
            return []
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 当前颜色展示
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selectedColor)
                        .frame(height: 80)
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

                            FlowLayout(spacing: 12) {
                                ForEach(Array(themeColors.enumerated()), id: \.offset) { _, color in
                                    ColorCircle(
                                        color: color,
                                        isSelected: color == selectedColor
                                    ) {
                                        selectedColor = color
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // 预设颜色 - 使用流式布局
                    VStack(alignment: .leading, spacing: 12) {
                        Text("预设颜色")
                            .font(.headline)
                            .padding(.horizontal)

                        FlowLayout(spacing: 10) {
                            ForEach(Array(presetColors.enumerated()), id: \.offset) { _, color in
                                ColorCircle(
                                    color: color,
                                    isSelected: color == selectedColor
                                ) {
                                    selectedColor = color
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // 颜色滑块（HSB 选择器）
                    VStack(alignment: .leading, spacing: 12) {
                        Text("精细调整")
                            .font(.headline)
                            .padding(.horizontal)

                        ColorSliderSection(selectedColor: $selectedColor)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
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



// MARK: - 颜色圆形按钮
struct ColorCircle: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .opacity(isSelected ? 1 : 0)
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 颜色滑块区域
struct ColorSliderSection: View {
    @Binding var selectedColor: Color
    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1

    var body: some View {
        VStack(spacing: 16) {
            // 色相滑块
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("色相")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(hue * 360))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // 彩虹渐变背景
                        LinearGradient(
                            colors: [
                                Color(hue: 0, saturation: 1, brightness: 1),
                                Color(hue: 0.17, saturation: 1, brightness: 1),
                                Color(hue: 0.33, saturation: 1, brightness: 1),
                                Color(hue: 0.5, saturation: 1, brightness: 1),
                                Color(hue: 0.67, saturation: 1, brightness: 1),
                                Color(hue: 0.83, saturation: 1, brightness: 1),
                                Color(hue: 1, saturation: 1, brightness: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // 滑块指示器
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                            .offset(x: hue * (geo.size.width - 20))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                hue = max(0, min(1, value.location.x / geo.size.width))
                                updateColor()
                            }
                    )
                }
                .frame(height: 24)
            }

            // 饱和度滑块
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("饱和度")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(saturation * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // 饱和度渐变
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: 0, brightness: brightness),
                                Color(hue: hue, saturation: 1, brightness: brightness),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                            .offset(x: saturation * (geo.size.width - 20))
                    }
                    .frame(height: 24)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                saturation = max(0, min(1, value.location.x / geo.size.width))
                                updateColor()
                            }
                    )
                }
                .frame(height: 24)
            }

            // 亮度滑块
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("亮度")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(brightness * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // 亮度渐变
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: saturation, brightness: 0),
                                Color(hue: hue, saturation: saturation, brightness: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                            .offset(x: brightness * (geo.size.width - 20))
                    }
                    .frame(height: 24)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                brightness = max(0, min(1, value.location.x / geo.size.width))
                                updateColor()
                            }
                    )
                }
                .frame(height: 24)
            }
        }
        .onAppear {
            extractHSB()
        }
        .onChange(of: selectedColor) { _, _ in
            extractHSB()
        }
    }

    private func extractHSB() {
        // 从 Color 提取 HSB 值
        let uiColor = UIColor(selectedColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
    }

    private func updateColor() {
        selectedColor = Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

// MARK: - 紧凑颜色按钮
struct CompactColorButton: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 颜色预览
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 我的主题方案卡片
struct MyThemeCard: View {
    let theme: UserCustomTheme
    let isActive: Bool
    let onApply: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onApply) {
            VStack(spacing: 8) {
                // 预览卡片
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.cardConfig.backgroundRGBA.color)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 4) {
                            Circle().fill(theme.textPrimaryRGBA.color).frame(width: 8, height: 8)
                            Circle().fill(theme.textSecondaryRGBA.color).frame(width: 8, height: 8)
                            Circle().fill(theme.textAccentRGBA.color).frame(width: 8, height: 8)
                            Spacer()
                        }
                        .padding(8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActive ? Color.pink : Color.clear, lineWidth: 2)
                    )

                // 主题名称和删除按钮
                HStack(spacing: 4) {
                    Text(theme.name)
                        .font(.caption)
                        .fontWeight(isActive ? .bold : .regular)
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer()

                    // 删除按钮
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
