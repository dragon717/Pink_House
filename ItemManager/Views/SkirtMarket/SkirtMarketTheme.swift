//
//  SkirtMarketTheme.swift
//  裙装股市 - 主题配置
//
//  莫妮卡粉主题配色方案
//

import SwiftUI

// MARK: - 裙装股市主题配置
enum SkirtMarketTheme {
    // MARK: - 主题色（莫妮卡粉系）
    
    /// 主色调：莫妮卡粉 #E29399
    static let primaryPink = Color(hex: "E29399")
    
    /// 深莫妮卡粉（用于强调）
    static let deepPink = Color(hex: "D4787F")
    
    /// 浅莫妮卡粉（用于背景）
    static let lightPink = Color(hex: "F5D0D3")
    
    /// 极浅粉（用于卡片背景）
    static let ultraLightPink = Color(hex: "FDF5F6")
    
    /// 蕾丝白（背景色）
    static let laceWhite = Color(hex: "F9F5F2")
    
    /// 午夜蓝（深色模式背景）
    static let midnightBlue = Color(hex: "2C3E50")
    
    /// 薄荷灰绿（下跌/中性提示）
    static let mintGreen = Color(hex: "A3C1AD")
    
    /// 深绿（上涨）
    static let riseGreen = Color(hex: "32CD32")
    
    /// 深红（下跌）
    static let fallRed = Color(hex: "DC143C")
    
    /// 金色（提示）
    static let gold = Color(hex: "FFD700")
    
    // MARK: - 渐变
    
    /// 主渐变
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primaryPink, deepPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// 背景渐变（亮色模式）
    static var lightBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [laceWhite, ultraLightPink],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// 背景渐变（暗夜模式）
    static var darkBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [midnightBlue, midnightBlue.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - 字体
    
    /// 大盘指数数字字体
    static let indexFont = Font.system(size: 48, weight: .bold, design: .rounded)
    
    /// 标题字体
    static let titleFont = Font.system(size: 20, weight: .bold, design: .rounded)
    
    /// 副标题字体
    static let subtitleFont = Font.system(size: 16, weight: .semibold)
    
    /// 正文字体
    static let bodyFont = Font.system(size: 14, weight: .regular)
    
    /// 小字字体
    static let captionFont = Font.system(size: 12, weight: .medium)
    
    // MARK: - 布局
    
    /// 卡片圆角
    static let cardCornerRadius: CGFloat = 16
    
    /// 按钮圆角
    static let buttonCornerRadius: CGFloat = 12
    
    /// 标准间距
    static let standardSpacing: CGFloat = 16
    
    /// 小间距
    static let smallSpacing: CGFloat = 8
    
    /// 卡片内边距
    static let cardPadding: CGFloat = 20
    
    // MARK: - 动画
    
    /// 标准动画时长
    static let animationDuration: Double = 0.3
    
    /// 弹簧动画
    static var springAnimation: Animation {
        .spring(response: 0.4, dampingFraction: 0.8)
    }
    
    // MARK: - 暗夜模式适配
    
    /// 卡片背景色（根据当前颜色方案自动适配）
    static var cardBackground: Color {
        Color(.systemBackground)
    }
    
    /// 次级背景色
    static var secondaryBackground: Color {
        Color(.secondarySystemBackground)
    }
    
    /// 主文本颜色
    static var primaryText: Color {
        .primary
    }
    
    /// 次级文本颜色
    static var secondaryText: Color {
        .secondary
    }
}

// MARK: - View扩展
extension View {
    /// 应用裙装股市卡片样式（自动适配暗夜模式）
    func skirtMarketCardStyle() -> some View {
        self
            .padding(SkirtMarketTheme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: SkirtMarketTheme.cardCornerRadius)
                    .fill(SkirtMarketTheme.cardBackground)
                    .shadow(
                        color: SkirtMarketTheme.primaryPink.opacity(0.15),
                        radius: 12,
                        x: 0,
                        y: 4
                    )
            )
    }
    
    /// 应用主按钮样式
    func primaryButtonStyle() -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(SkirtMarketTheme.primaryPink)
            .foregroundColor(.white)
            .cornerRadius(SkirtMarketTheme.buttonCornerRadius)
            .font(SkirtMarketTheme.subtitleFont)
    }
}

// MARK: - 共享组件

/// 脉冲点（实时指示器）
struct PulsingDot: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(SkirtMarketTheme.primaryPink)
            .frame(width: 6, height: 6)
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}


