import SwiftUI

struct PetDialogueInputView: View {
    @Binding var text: String
    var placeholder: String = "请输入的文字"
    var onSend: () -> Void
    var focusRequestID: Int = 0
    var onFocusChange: ((Bool) -> Void)? = nil
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 输入框
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(themeManager.tertiaryTextColor.opacity(0.6))
                        .padding(.horizontal, 16)
                }

                TextField("", text: $text)
                    .focused($isFocused)
                    .font(.system(size: 17))
                    .foregroundStyle(themeManager.primaryTextColor)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(onSend)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(themeManager.cardBackgroundColor)
            .clipShape(Capsule())
            // 简单的内阴影效果
            .overlay(
                Capsule()
                    .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
            )

            // 发送按钮 (猫爪)
            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    themeManager.cardTintColor.mixed(with: .white, amount: 0.1),
                                    themeManager.cardTintColor.mixed(with: .black, amount: 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: themeManager.cardTintColor.opacity(0.3), radius: 2, x: 0, y: 2)

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
                // 主体气泡 - 使用主题卡片背景色
                RoundedRectangle(cornerRadius: 30)
                    .fill(themeManager.cardBackgroundColor)
                    .shadow(color: themeManager.accentTextColor.opacity(0.15), radius: 10, x: 0, y: 5)

                // 气泡尾巴 (左下角)
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 20, y: geo.size.height - 20)) // 起点在圆角上方一点
                        path.addLine(to: CGPoint(x: 8, y: geo.size.height + 6)) // 延伸出去的点
                        path.addLine(to: CGPoint(x: 40, y: geo.size.height - 10)) // 回到气泡底部
                        path.closeSubpath()
                    }
                    .fill(themeManager.cardBackgroundColor) // 与气泡背景一致
                }
            }
        )
        // 确保整体有立体感
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
        )
        .onChange(of: isFocused) { _, newValue in
            onFocusChange?(newValue)
        }
        .onChange(of: focusRequestID) { _, newValue in
            guard newValue > 0 else { return }
            DispatchQueue.main.async {
                isFocused = true
            }
        }
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
