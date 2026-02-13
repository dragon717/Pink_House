import SwiftUI

struct PetDialogueInputView: View {
    @Binding var text: String
    var onSend: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 输入框
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("请输入的文字")
                        .foregroundStyle(.gray.opacity(0.6))
                        .padding(.horizontal, 16)
                }
                
                TextField("", text: $text)
                    .focused($isFocused)
                    .font(.system(size: 17))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Color.white)
            .clipShape(Capsule())
            // 简单的内阴影效果
            .overlay(
                Capsule()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
            
            // 发送按钮 (猫爪)
            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFC0CB"), Color(hex: "FFB6C1")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: "FF69B4").opacity(0.3), radius: 2, x: 0, y: 2)
                    
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                }
                .frame(width: 50, height: 50)
            }
        }
        .padding(16)
        .background(
            ZStack {
                // 主体气泡
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFD1DC"), Color(hex: "FFC0CB")], // 浅粉色渐变
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                // 气泡尾巴 (左下角)
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 20, y: geo.size.height - 20)) // 起点在圆角上方一点
                        path.addLine(to: CGPoint(x: 8, y: geo.size.height + 6)) // 延伸出去的点
                        path.addLine(to: CGPoint(x: 40, y: geo.size.height - 10)) // 回到气泡底部
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "FFC0CB")) // 与底部颜色一致
                }
            }
        )
        // 确保整体有立体感
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )

    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            Spacer()
            PetDialogueInputView(text: .constant(""), onSend: {})
                .padding()
        }
    }
}
