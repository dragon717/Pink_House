//
//  OpsFlowTheme.swift
//  PinkHouseOps
//
//  「Pink House 运营」视觉设计系统 —— 严格对齐两张流程参考图：
//
//    · 图1《店家与系列 · 商品查看与运营编辑》
//    · 图2《Pink House Mac 商品发布流程》（S1–S5）
//
//  ## 从参考图拆出的设计语言（本文件是它的唯一代码化）
//
//  · **背景**：淡粉→淡紫的整页渐变（#FBF5FA → #F1EAFA）；
//  · **卡片**：白色、大圆角（16pt）、极浅投影 + 一根极浅描边；
//  · **双色主色**：品牌粉 `accentPink`（#C9486F，图1 的数字徽/按钮/分类胶囊）
//    与流程紫 `primaryPurple`（#7B5BD6，图2 的「下一步、继续编辑」主按钮）；
//  · **瓷片（tile）**：粉/丁香紫/薄荷绿/奶油黄/浅红 五种极浅底色圆角块，
//    承载店家卡、系列卡、信息组、提示条；
//  · **数字圆徽**：实心圆 + 白色序号（当前步/进行中的分区），未激活用描边灰；
//  · **按钮**：实心圆角(10pt) 主按钮 + 白底描边次按钮，绝不用系统默认蓝；
//  · **胶囊（chip）**：极浅底 + 同系深字的小圆角标签（价格、状态、分类）；
//  · **页脚**：深藏青条（#232741）+ 白色小字（两张图的收尾说明条）。
//
//  ⚠️ 所有颜色都是**固定浅色主题值**：本工具面向 Mac 运营、参考图即浅色稿，
//     不做暗色适配（暗色下这些粉彩瓷片本来也不成立）。
//

import SwiftUI

// MARK: - 色板

/// 参考图色板。hex 直接来自图稿取色，命名对齐图里的角色而不是抽象色号。
enum OpsFlowPalette {
    // 整页渐变（图2 的淡紫底、图1 的粉紫顶部）
    static let bgTop = Color(hex: 0xFB_F5FA)
    static let bgBottom = Color(hex: 0xF1_EAFA)

    // 卡片
    static let cardBackground = Color.white
    static let cardBorder = Color(hex: 0xEB_DFEC)
    static let cardShadow = Color(hex: 0x8A_5F82, alpha: 0.10)

    // 双主色
    /// 品牌粉（图1：数字徽、进入按钮、JSK 分类胶囊）
    static let accentPink = Color(hex: 0xC9_486F)
    static let accentPinkDeep = Color(hex: 0xB0_3A62)
    /// 流程紫（图2：「下一步、继续编辑」主按钮）
    static let primaryPurple = Color(hex: 0x7B_5BD6)
    static let primaryPurpleDeep = Color(hex: 0x6A_4BC8)

    // 文字
    static let textPrimary = Color(hex: 0x33_283A)
    static let textSecondary = Color(hex: 0x8B_8194)

    // 瓷片底色（图1/图2 的粉彩色块）
    static let tilePink = Color(hex: 0xFB_EFF3)
    static let tileLilac = Color(hex: 0xF1_EBFA)
    static let tileMint = Color(hex: 0xE9_F6EE)
    static let tileCream = Color(hex: 0xFF_F5E6)
    static let tileRed = Color(hex: 0xFC_EBEB)
    static let tileBorder = Color(hex: 0xF0_E3EE)

    // 状态
    static let okGreen = Color(hex: 0x3E_9E64)
    static let warnOrange = Color(hex: 0xC7_7312)

    // 页脚（图1/图2 底部的深藏青说明条）
    static let footerNavy = Color(hex: 0x23_2741)
}

extension Color {
    /// 0xRRGGBB（可带 0xAARRGGBB）→ Color。设计系统专用，业务代码不直接用。
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha)
    }
}

// MARK: - 整页渐变背景

/// 参考图的整页底色：淡粉→淡紫。分区根视图直接 `.background(OpsFlowPageBackground())`。
struct OpsFlowPageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [OpsFlowPalette.bgTop, OpsFlowPalette.bgBottom],
            startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - 卡片

/// 白色大圆角卡（两张图的基本容器）。透明内容区 + 自带留白。
struct OpsFlowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OpsFlowPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(OpsFlowPalette.cardBorder, lineWidth: 1))
            .shadow(color: OpsFlowPalette.cardShadow, radius: 10, x: 0, y: 4)
    }
}

// MARK: - 数字圆徽（步骤条 / 分区序号）

/// 实心数字圆徽：当前步 = 紫色实心；已完成 = 绿色；未到 = 描边灰。
/// 图1/图2 的「1 2 3 4 5」序号圆。
struct OpsFlowNumberBadge: View {
    let text: String
    let state: State
    var tint: Color = OpsFlowPalette.primaryPurple

    enum State { case current, done, pending }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .frame(width: 22, height: 22)
            .background(background, in: Circle())
            .overlay(Circle().stroke(borderColor, lineWidth: 1.5))
    }

    private var foreground: Color {
        switch state {
        case .current: return .white
        case .done: return .white
        case .pending: return OpsFlowPalette.textSecondary
        }
    }

    private var background: Color {
        switch state {
        case .current: return tint
        case .done: return OpsFlowPalette.okGreen
        case .pending: return OpsFlowPalette.cardBackground
        }
    }

    private var borderColor: Color {
        switch state {
        case .current, .done: return .clear
        case .pending: return OpsFlowPalette.cardBorder
        }
    }
}

/// 步骤条（图2 顶部）：圆徽 + 「S1·选择店家与系列」+ 节点间连接线。
struct OpsFlowStepHeader: View {
    let steps: [String]
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let state: OpsFlowNumberBadge.State =
                    index < currentIndex ? .done : (index == currentIndex ? .current : .pending)
                HStack(spacing: 6) {
                    OpsFlowNumberBadge(
                        text: "\(index + 1)", state: state,
                        tint: OpsFlowPalette.primaryPurple)
                    Text(title)
                        .font(.callout.weight(index == currentIndex ? .semibold : .regular))
                        .foregroundStyle(index == currentIndex
                            ? OpsFlowPalette.textPrimary
                            : OpsFlowPalette.textSecondary)
                        .lineLimit(1)
                }
                if index < steps.count - 1 {
                    // 节点连接线（图1 左侧竖线的横向版）
                    Rectangle()
                        .fill(index < currentIndex
                            ? OpsFlowPalette.primaryPurple.opacity(0.45)
                            : OpsFlowPalette.cardBorder)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - 胶囊标签

/// 小胶囊：极浅底 + 同系深字（图1 的「JSK」分类胶囊、价格标签、状态标签）。
struct OpsFlowChip: View {
    let text: String
    var tint: Color = OpsFlowPalette.accentPink
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - 瓷片

/// 粉彩瓷片（图1 的店家卡/系列卡/提示条、图2 的信息组底色）。
struct OpsFlowTile<Content: View>: View {
    var color: Color
    var selected: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? OpsFlowPalette.accentPink : OpsFlowPalette.tileBorder,
                            lineWidth: selected ? 1.5 : 1))
    }
}

/// 浅红警示条（图1「本次只读」条 / 图2 的阻断项）。
struct OpsFlowNoticeBar: View {
    let text: String
    var tint: Color = OpsFlowPalette.accentPink

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(tint)
            opsMarkdown(text)
                .font(.callout)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 按钮样式（参考图不允许系统默认蓝）

/// 主按钮：实心圆角（图2「下一步、继续编辑」的紫 / 图1「进入商品列表」的粉）。
struct OpsFlowPrimaryButtonStyle: ButtonStyle {
    /// 紫 = 流程推进（图2），粉 = 品牌动作（图1）
    var tint: Color = OpsFlowPalette.primaryPurple

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(tint.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

/// 次按钮：白底描边（图1「查看本系列全部商品」「查看详情」）。
struct OpsFlowSecondaryButtonStyle: ButtonStyle {
    var tint: Color = OpsFlowPalette.accentPink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.85 : 1)))
            .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - 页脚说明条

/// 深藏青页脚（图1/图2 底部）：白/浅灰小字收尾说明 + 操作按钮。
struct OpsFlowFooterBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(OpsFlowPalette.footerNavy)
    }
}

/// 深底上的小字（页脚专用）
struct OpsFlowFooterText: View {
    let text: String
    var dimmed: Bool = false

    var body: some View {
        opsMarkdown(text)
            .font(.caption)
            .lineLimit(3)
            .foregroundStyle(dimmed ? AnyShapeStyle(Color.white.opacity(0.6)) : AnyShapeStyle(.white))
    }
}
