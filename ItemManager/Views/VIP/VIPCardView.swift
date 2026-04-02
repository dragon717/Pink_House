import SwiftUI
import Combine

struct VIPCardView: View {
    let vipNumber: String
    let expireDate: Date?
    let isVIP: Bool
    var cardStyle: VIPCardStyle = .blackGold
    
    @State private var shimmerOffset: CGFloat = -300
    @State private var isAnimatingChange = false
    
    // MARK: - Style Helpers
    private var backgroundColors: [Color] {
        switch cardStyle {
        case .blackGold:
            return [
                Color(hex: "2C2C2C"), // Charcoal
                Color(hex: "121212"), // Almost Black
                Color(hex: "000000")  // Pure Black
            ]
        case .monicaPink:
            return [
                Color(hex: "FFB6C1"), // Light Pink
                Color(hex: "FFC0CB"), // Pink
                Color(hex: "FF69B4")  // Hot Pink
            ]
        }
    }
    
    private var shimmerColors: [Color] {
        switch cardStyle {
        case .blackGold:
            return [
                .clear,
                Color(hex: "FFD700").opacity(0.2),
                Color(hex: "FFFACD").opacity(0.4),
                Color(hex: "FFD700").opacity(0.2),
                .clear
            ]
        case .monicaPink:
            return [
                .clear,
                Color.white.opacity(0.2),
                Color.white.opacity(0.6),
                Color.white.opacity(0.2),
                .clear
            ]
        }
    }
    
    private var borderColors: [Color] {
        switch cardStyle {
        case .blackGold:
            return [Color(hex: "B8860B"), Color(hex: "FFD700"), Color(hex: "B8860B")]
        case .monicaPink:
            return [Color.white.opacity(0.5), Color.white, Color.white.opacity(0.5)]
        }
    }
    
    private var textGradientColors: [Color] {
        switch cardStyle {
        case .blackGold:
            return [Color(hex: "FFD700"), Color(hex: "FFFACD"), Color(hex: "B8860B")]
        case .monicaPink:
            return [Color.white, Color(hex: "FFF0F5"), Color(hex: "FFE4E1")]
        }
    }
    
    private var tagText: String {
        switch cardStyle {
        case .blackGold: return "黑金尊享"
        case .monicaPink: return "梦幻限定"
        }
    }
    
    private var tagColors: (bg: Color, border: Color, text: Color) {
        switch cardStyle {
        case .blackGold:
            return (Color.black.opacity(0.6), Color(hex: "FFD700"), Color(hex: "FFD700"))
        case .monicaPink:
            return (Color.pink.opacity(0.3), Color.white, Color.white)
        }
    }
    
    private var numberColors: [Color] {
        switch cardStyle {
        case .blackGold:
            return [Color(hex: "FFFACD"), Color(hex: "FFD700"), Color(hex: "B8860B")]
        case .monicaPink:
            return [Color.white, Color.white.opacity(0.8), Color.white]
        }
    }
    
    private var validThruColor: Color {
        switch cardStyle {
        case .blackGold: return Color(hex: "B8860B")
        case .monicaPink: return Color.white.opacity(0.8)
        }
    }
    
    var body: some View {
        ZStack {
            // 1. Base Background
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: cardStyle == .monicaPink ? Color.pink.opacity(0.3) : .black.opacity(0.4), radius: 10, x: 0, y: 5)
            
            // 2. Subtle Texture (Optional)
            
            // 3. Shimmer Effect
            GeometryReader { geometry in
                LinearGradient(
                    colors: shimmerColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 2.5) // 增加高度
                .rotationEffect(.degrees(20))
                .offset(x: shimmerOffset) // 去掉 y 轴偏移，保持中心对齐
                .blur(radius: 5)
                .blendMode(.overlay)
                .task(id: geometry.size) {
                    let startX = -geometry.size.width * 1.0 // 加大起始距离
                    let endX = geometry.size.width * 1.5
                    
                    // 初始位置
                    shimmerOffset = startX
                    
                    // 稍微延迟一点启动，避免页面刚显示就闪
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    
                    while !Task.isCancelled {
                        // 重置到起点 (无动画)
                        shimmerOffset = startX
                        
                        // 确保重置生效的一小段缓冲 (可选，但在高频循环中比较稳妥)
                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                        
                        // 执行流光动画
                        withAnimation(.linear(duration: 2.5)) {
                            shimmerOffset = endX
                        }
                        
                        // 等待动画结束 + 间隔时间
                        // 动画 2.5s + 间隔 2.5s = 5.0s
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                }
            }
            .mask(RoundedRectangle(cornerRadius: 20))
            
            // 4. Border
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: borderColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "crown.fill")
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: textGradientColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .orange.opacity(0.5), radius: 5)
                    
                    Text("少女心愿 VIP")
                        .font(.custom("Zapfino", size: 20))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(
                                colors: textGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                    
                    Spacer()
                    
                    if isVIP {
                        Text(tagText)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                ZStack {
                                    Capsule()
                                        .fill(tagColors.bg)
                                    Capsule()
                                        .stroke(tagColors.border, lineWidth: 1)
                                }
                            )
                            .foregroundStyle(tagColors.text)
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                Spacer()
                
                // VIP Number
                if isVIP {
                    Text(formatVIPNumber(vipNumber))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: numberColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                        .padding(.horizontal, 24)
                } else {
                    Text("加入尊贵会员，解锁专属特权")
                        .font(.subheadline)
                        .foregroundStyle(cardStyle == .monicaPink ? .white.opacity(0.8) : .gray)
                        .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // Footer
                HStack {
                    VStack(alignment: .leading) {
                        Text("VALID THRU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(validThruColor)
                        
                        if let date = expireDate, isVIP {
                            Text(date.formatted(date: .numeric, time: .omitted))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                        } else {
                            Text("--/--")
                                .font(.caption)
                                .foregroundStyle(cardStyle == .monicaPink ? .white.opacity(0.6) : .gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Chip
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(colors: [Color(hex: "FFD700"), Color(hex: "B8860B")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "simcard.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24)
                                .foregroundStyle(.black.opacity(0.4))
                                .rotationEffect(.degrees(90))
                        )
                        .shadow(radius: 2)
                }
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .scaleEffect(x: isAnimatingChange ? 1.02 : 1.0, y: 1.0)
        .onChange(of: cardStyle) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                isAnimatingChange = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    isAnimatingChange = false
                }
            }
        }
    }
    
    private func formatVIPNumber(_ number: String) -> String {
        // Format as groups of 4: 8888 8888
        var result = ""
        for (index, char) in number.enumerated() {
            if index > 0 && index % 4 == 0 {
                result += " "
            }
            result.append(char)
        }
        return result
    }
}
