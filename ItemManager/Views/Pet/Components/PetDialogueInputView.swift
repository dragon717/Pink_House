import SwiftUI

struct PetDialogueInputView: View {
    @Binding var text: String
    var placeholder: String = "请输入的文字"
    var onSend: () -> Void
    var onQuickMenuAction: (() -> Void)? = nil
    var focusRequestID: Int = 0
    var onFocusChange: ((Bool) -> Void)? = nil
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let onQuickMenuAction = onQuickMenuAction {
                    Button(action: onQuickMenuAction) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.pink)
                    }
                }
                
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.gray.opacity(0.6))
                            .padding(.horizontal, 16)
                    }
                    
                    TextField("", text: $text)
                        .focused($isFocused)
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                        .submitLabel(.send)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(onSend)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
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
                                    colors: [Color(hex: "FFC0CB"), Color(hex: "FFB6C1")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(hex: "FF69B4").opacity(0.3), radius: 2, x: 0, y: 2)
                        
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
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
                            colors: [Color(hex: "FFD1DC"), Color(hex: "FFC0CB")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
                
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 30, y: geo.size.height - 25))
                        path.addLine(to: CGPoint(x: 18, y: geo.size.height + 6))
                        path.addLine(to: CGPoint(x: 50, y: geo.size.height - 15))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "FFC0CB"))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
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
