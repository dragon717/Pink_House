
import SwiftUI

/// 小世界悬浮标签样式
enum SmallWorldLabelStyle {
    case horizontal(angle: Double)
    case vertical(angle: Double)
    case diagonal(angle: Double)
}

/// 悬浮文字标签组件
struct FloatingTextLabel: View {
    let text: String
    let style: SmallWorldLabelStyle
    var color: Color = .white
    var fontSize: CGFloat = 14
    var shadowColor: Color = .black.opacity(0.5)
    
    @State private var isFloating = false
    
    var body: some View {
        Group {
            switch style {
            case .horizontal(let angle):
                Text(text)
                    .font(.system(size: fontSize, weight: .bold, design: .serif))
                    .foregroundStyle(color)
                    .shadow(color: shadowColor, radius: 2, x: 1, y: 1)
                    .rotationEffect(.degrees(angle))
                
            case .vertical(let angle):
                VStack(spacing: 2) {
                    ForEach(Array(text), id: \.self) { char in
                        Text(String(char))
                            .font(.system(size: fontSize, weight: .bold, design: .serif))
                            .foregroundStyle(color)
                            .shadow(color: shadowColor, radius: 2, x: 1, y: 1)
                    }
                }
                .rotationEffect(.degrees(angle))
                
            case .diagonal(let angle):
                Text(text)
                    .font(.system(size: fontSize, weight: .bold, design: .serif))
                    .foregroundStyle(color)
                    .shadow(color: shadowColor, radius: 2, x: 1, y: 1)
                    .rotationEffect(.degrees(angle))
            }
        }
        .offset(y: isFloating ? -3 : 3)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }
}
