import SwiftUI

struct PetDialogueInputView: View {
    @Binding var text: String
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    var placeholder: String = "请输入的文字"
    var onSend: () -> Void
    var onQuickMenuAction: (() -> Void)? = nil
    var focusRequestID: Int = 0
    var onFocusChange: ((Bool) -> Void)? = nil
    
    @FocusState private var isFocused: Bool

    private var inputTokens: PetDialogueInputThemeTokens {
        themeManager.petChatSkinTheme.resolvedDialogueInputTokens(
            themeManager: themeManager,
            colorScheme: colorScheme
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let onQuickMenuAction = onQuickMenuAction {
                    Button(action: onQuickMenuAction) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(inputTokens.menuAccent)
                    }
                }
                
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(inputTokens.placeholderText)
                            .padding(.horizontal, 16)
                    }
                    
                    TextField("", text: $text)
                        .focused($isFocused)
                        .font(.system(size: 17))
                        .foregroundStyle(inputTokens.fieldText)
                        .submitLabel(.send)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(onSend)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(inputTokens.fieldFill)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(inputTokens.fieldStroke, lineWidth: 1)
                )
                
                Button {
                    if !text.isEmpty {
                        onSend()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: inputTokens.actionButtonGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: inputTokens.actionButtonShadow, radius: 2, x: 0, y: 2)
                        
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(inputTokens.actionButtonForeground)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    }
                    .frame(width: 44, height: 44)
                }
                .disabled(text.isEmpty)
                .opacity(text.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: inputTokens.containerGradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: inputTokens.containerShadow, radius: 10, x: 0, y: -5)
                
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 30, y: geo.size.height - 25))
                        path.addLine(to: CGPoint(x: 18, y: geo.size.height + 6))
                        path.addLine(to: CGPoint(x: 50, y: geo.size.height - 15))
                        path.closeSubpath()
                    }
                    .fill(inputTokens.containerTailFill)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(inputTokens.containerStroke, lineWidth: 1)
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
    .environment(ThemeManager.shared)
}
