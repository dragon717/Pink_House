
import SwiftUI
import Combine

// MARK: - Wealth Tier Definition

enum WealthTier {
    case copper
    case silver
    case gold
    case emerald
    case platinum
    case diamond
    case sparklingGold
    case rainbow
    
    static func current(for valueCNY: Double) -> WealthTier {
        switch valueCNY {
        case ..<1_000: return .copper
        case 1_000..<5_000: return .silver
        // 扩大金色范围 (5k - 500k)
        case 5_000..<500_000: return .gold
        case 500_000..<600_000: return .emerald
        case 600_000..<700_000: return .platinum
        case 700_000..<800_000: return .diamond
        // 扩大闪金范围 (50w - 200w)
        case 800_000..<2_000_000: return .sparklingGold
        // 200w 以上为彩金
        default: return .rainbow
        }
    }
    
    var textColors: [Color] {
        switch self {
        case .copper:
            return [Color(hex: "B87333"), Color(hex: "A0522D")] // 铜色
        case .silver:
            return [Color(hex: "E0E0E0"), Color(hex: "B0B0B0")] // 银色
        case .gold:
            return [Color(hex: "FFD700"), Color(hex: "DAA520")] // 金色
        case .emerald:
            return [Color(hex: "50C878"), Color(hex: "006B3C")] // 翡翠绿
        case .platinum:
            return [Color(hex: "E5E4E2"), Color(hex: "D1D1D1")] // 铂金色 (略带金属灰白)
        case .diamond:
            return [Color.white, Color(hex: "F0F8FF")] // 钻石白 (带一点点蓝)
        case .sparklingGold:
            return [Color(hex: "FFD700"), Color(hex: "FDB931")] // 闪亮金
        case .rainbow:
            return [.red, .orange, .yellow, .green, .blue, .purple, .pink] // 彩虹
        }
    }
    
    var shadowColor: Color {
        switch self {
        case .copper: return Color.black.opacity(0.2)
        case .silver: return Color.black.opacity(0.2)
        case .gold: return Color(hex: "8B6914").opacity(0.3)
        case .emerald: return Color(hex: "004020").opacity(0.3)
        case .platinum: return Color.black.opacity(0.15)
        case .diamond: return Color(hex: "E0FFFF").opacity(0.6) // 钻石发光阴影
        case .sparklingGold: return Color(hex: "FFD700").opacity(0.5) // 金色发光阴影
        case .rainbow: return Color.white.opacity(0.4)
        }
    }
    
    var shadowRadius: CGFloat {
        switch self {
        case .diamond, .sparklingGold, .rainbow: return 4
        default: return 2
        }
    }
}


// MARK: - Main View

/// 一个带有液态玻璃效果和动态等级颜色的数字滚动组件
struct LiquidRollingNumber: View {
    let value: Double // Changed to Double
    /// 当前货币对人民币的汇率（例如 JPY 汇率为 0.05 左右，CNY 为 1.0）
    var exchangeRateToCNY: Double = 1.0
    var fractionLength: Int = 0 // Number of decimal places
    
    // 动画状态
    @State private var animatedValue: Double = 0
    var fixedTier: WealthTier? = nil // Optional fixed tier overriding calculation
    
    private var currentTier: WealthTier {
        if let fixed = fixedTier {
            return fixed
        } else {
            let currentCNYValue = animatedValue * exchangeRateToCNY
            return WealthTier.current(for: currentCNYValue)
        }
    }
    
    var body: some View {
        RollingText(value: animatedValue, tier: currentTier, fractionLength: fractionLength)
            .onAppear {
                // Ensure value is valid
                if value.isFinite {
                    runAnimation(to: value)
                }
            }
            .onChange(of: value) { _, newValue in
                // If the value changes drastically, reset animation?
                // Or just animate to new value.
                // Existing logic reset animatedValue to 0 then animated.
                // This creates a "restart" effect.
                // For unit switching (Int -> Double), this is fine.
                // For small increments, maybe just animate?
                // Let's keep existing behavior for "Wealth" effect (counting up).
                if newValue.isFinite {
                    runAnimation(to: newValue)
                }
            }
    }
    
    private func runAnimation(to targetValue: Double) {
        // Reset to 0 to show "counting up" effect
        // But for small updates, maybe we shouldn't reset?
        // Current requirement implies "counting up" is desirable for "Wealth" feeling.
        animatedValue = 0
        
        // Use a spring animation for liquid feel
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            animatedValue = targetValue
        }
    }
}

// MARK: - Rendering Components

fileprivate struct RollingText: View, Animatable {
    var value: Double
    let tier: WealthTier
    var fractionLength: Int = 0
    
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    
    var body: some View {
        // Format the value string
        let stringValue: String
        if fractionLength > 0 {
            stringValue = String(format: "%.\(fractionLength)f", value)
        } else {
            stringValue = "\(Int(round(value)))"
        }
        
        // 基础文本层（用于产生形状和阴影）
        return Text(stringValue)
            .monospacedDigit()
            // 关键修正：将底层文字设为透明，防止 Overlay 覆盖不全时露出黑色底色
            .foregroundStyle(.clear)
            // 2. 颜色填充 (Masked)
            .overlay(
                TierColorView(tier: tier)
                    .mask(
                        Text(stringValue)
                            .monospacedDigit()
                    )
            )
            // 3. 玻璃光泽 (Overlay) - 简化渐变层级
            .overlay(
                LinearGradient(
                    colors: [
                        .white.opacity(0.8),
                        .white.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(
                    Text(stringValue)
                        .monospacedDigit()
                )
            )
            // 4. 阴影 - 保持立体感，但确保 drawingGroup 生效
            .shadow(color: tier.shadowColor, radius: tier.shadowRadius, x: 0, y: 1)
            // 性能关键：启用 Metal 渲染缓存，避免每帧重绘复杂视图层级
            .drawingGroup()
    }
}

/// 负责渲染等级对应的颜色或动态效果
fileprivate struct TierColorView: View {
    let tier: WealthTier
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base Gradient
                if tier == .rainbow {
                    // 修正：使用 LinearGradient + HueRotation 代替旋转的 AngularGradient
                    // 这样可以确保颜色始终覆盖整个文本区域，不会因为旋转而露出边角
                    LinearGradient(
                        colors: tier.textColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .modifier(RainbowFlowEffect())
                } else {
                    LinearGradient(
                        colors: tier.textColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                
                // Special Effects
                if tier == .sparklingGold {
                    ShimmerEffectView()
                }
                
                if tier == .diamond {
                    ShimmerEffectView(duration: 3.0, width: 0.3) // 钻石缓慢闪光
                }
            }
        }
    }
}

// MARK: - Effects

struct RainbowFlowEffect: ViewModifier {
    @State private var hueRotation: Double = 0
    
    func body(content: Content) -> some View {
        content
            .hueRotation(.degrees(hueRotation))
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    hueRotation = 360
                }
            }
    }
}

struct ShimmerEffectView: View {
    var duration: Double = 2.0
    var width: CGFloat = 0.5
    @State private var phase: CGFloat = -1.0
    
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.8),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .rotationEffect(.degrees(30))
                .scaleEffect(x: width, y: 2.0) // Width of the beam
                .offset(x: phase * geo.size.width * 3) // Move across
                .onAppear {
                    withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                        phase = 1.0
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        ScrollView {
            VStack(spacing: 30) {
                Group {
                    PreviewRow(val: 500, label: "铜 (<1k)")
                    PreviewRow(val: 3000, label: "银 (1k-5k)")
                    PreviewRow(val: 8000, label: "金 (5k-10k)")
                    PreviewRow(val: 15000, label: "翡翠 (10k-20k)")
                    PreviewRow(val: 30000, label: "铂金 (20k-50k)")
                    PreviewRow(val: 60000, label: "钻石 (50k-80k)")
                    PreviewRow(val: 90000, label: "闪光金 (80k-100k)")
                    PreviewRow(val: 120000, label: "彩金 (100k+)")
                }
            }
            .padding()
        }
    }
}

struct PreviewRow: View {
    let val: Int
    let label: String
    
    var body: some View {
        VStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            LiquidRollingNumber(value: Double(val))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
    }
}
