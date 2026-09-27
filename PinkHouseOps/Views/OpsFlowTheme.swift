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
//  ## 主题模式（2026-09-27 起跟随系统深/浅色）
//
//  浅色值 = 参考图原稿，逐字节不变；深色值 = 同一色相的降亮度映射（瓷片从
//  「极浅底」变成「深底上的同色相暗瓷片」，文字反转成浅色）。实现走
//  **动态 NSColor**：每个 token 一次声明两套值，系统外观切换时 SwiftUI
//  重渲染并按当前外观重解析 —— 不需要任何视图层代码或手动监听。
//
//  ⚠️ 视图层不许再写 `Color.white` / 固定 hex 当**表面色**（背景/文字底）；
//     彩色填充（瓷片、主色按钮、页脚）上的白字两套模式都成立，可以保留。
//

import SwiftUI

// MARK: - 色板

/// 参考图色板。浅色值 hex 直接来自图稿取色；深色值见 `dynamic(light:dark:)` 各调用点。
enum OpsFlowPalette {
    /// 动态颜色：浅色/深色两套 hex，按当前 NSAppearance 解析。
    private static func dynamic(light: UInt, dark: UInt, alpha: Double = 1) -> Color {
        let provider: (NSAppearance) -> NSColor = { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex: UInt = isDark ? dark : light
            return NSColor(hex: hex, alpha: alpha)
        }
        let resolved = NSColor(name: nil, dynamicProvider: provider)
        return Color(nsColor: resolved)
    }

    // 整页渐变（图2 的淡紫底、图1 的粉紫顶部）→ 深色：深紫夜空
    static let bgTop = dynamic(light: 0xFB_F5FA, dark: 0x1C_1726)
    static let bgBottom = dynamic(light: 0xF1_EAFA, dark: 0x13_101E)

    // 卡片 → 深色：抬升的深灰紫面
    static let cardBackground = dynamic(light: 0xFF_FFFF, dark: 0x23_202C)
    static let cardBorder = dynamic(light: 0xEB_DFEC, dark: 0x38_3240)
    static let cardShadow = dynamic(light: 0x8A_5F82, dark: 0x00_0000, alpha: 0.10)

    // 双主色（深色下提亮一档：在深卡上作**文字/描边**仍够对比；
    // 它们同时也是实心按钮/胶囊的底，白字对比经大号半粗字校验 ≥3:1）
    /// 品牌粉（图1：数字徽、进入按钮、JSK 分类胶囊）
    static let accentPink = dynamic(light: 0xC9_486F, dark: 0xDD_7396)
    static let accentPinkDeep = dynamic(light: 0xB0_3A62, dark: 0xC9_5A80)
    /// 流程紫（图2：「下一步、继续编辑」主按钮）
    static let primaryPurple = dynamic(light: 0x7B_5BD6, dark: 0x9B_82E6)
    static let primaryPurpleDeep = dynamic(light: 0x6A_4BC8, dark: 0x86_70D6)

    // 文字 → 深色反转
    static let textPrimary = dynamic(light: 0x33_283A, dark: 0xF0_EDF4)
    static let textSecondary = dynamic(light: 0x8B_8194, dark: 0xA7_9FB2)

    // 瓷片底色（图1/图2 的粉彩色块）→ 深色：同色相暗瓷片（贴卡片底的「深一档」色）
    static let tilePink = dynamic(light: 0xFB_EFF3, dark: 0x3B_2830)
    static let tileLilac = dynamic(light: 0xF1_EBFA, dark: 0x2D_2741)
    static let tileMint = dynamic(light: 0xE9_F6EE, dark: 0x24_352C)
    static let tileCream = dynamic(light: 0xFF_F5E6, dark: 0x3B_3225)
    static let tileRed = dynamic(light: 0xFC_EBEB, dark: 0x3E_2A2C)
    static let tileBorder = dynamic(light: 0xF0_E3EE, dark: 0x3E_3846)

    // 状态（深色下提亮保对比）
    static let okGreen = dynamic(light: 0x3E_9E64, dark: 0x6C_C794)
    static let warnOrange = dynamic(light: 0xC7_7312, dark: 0xE5_A45C)

    // 页脚（图1/图2 底部的深藏青说明条）：本身就是深色，两套模式共用
    static let footerNavy = Color(hex: 0x23_2741)

    /// 次按钮 / 搜索胶囊这类「浮在装饰面上的小面板」底色：浅=白，深=抬升面
    static let surfaceRaised = dynamic(light: 0xFF_FFFF, dark: 0x2E_2A38)
}

extension NSColor {
    /// 0xRRGGBB（可带 0xAARRGGBB）→ NSColor。动态色板专用。
    /// （用 device-RGB 初始化器：色彩空间差在此 UI 上不可感知，
    /// 换取与 SDK 版本无关的稳定签名。）
    convenience init(hex: UInt, alpha: Double = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: CGFloat(alpha))
    }
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
/// 底色走 `surfaceRaised`：深色模式下是抬升的深面 + 亮字，而不是白底刺眼。
/// `ghost` = 深色页脚上的幽灵形态：无实底（tint 14% 蒙层）+ tint 字与描边 ——
/// 页脚里的「上一步」传 `.white`，落在深藏青条上两种模式都可读
/// （旧实现白底 + tint 白字，浅色下字直接消失）。
struct OpsFlowSecondaryButtonStyle: ButtonStyle {
    var tint: Color = OpsFlowPalette.accentPink
    var ghost: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(ghost
                    ? tint.opacity(0.14)
                    : OpsFlowPalette.surfaceRaised.opacity(configuration.isPressed ? 0.85 : 1)))
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
