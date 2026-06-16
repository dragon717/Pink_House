import SwiftUI

struct PetNamingView: View {
    @Binding var petName: String?
    var onConfirm: () -> Void
    
    @State private var inputName: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // 背景
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // 欢迎标题
                VStack(spacing: 16) {
                    Text("欢迎来到温馨小屋".appLocalized)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("给你的第一个伙伴起个名字吧".appLocalized)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                // 萌宠图标动画
                Image(systemName: "cat.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.pink.opacity(0.8))
                    .padding()
                    .background(
                        Circle()
                            .fill(Color.pink.opacity(0.1))
                            .frame(width: 180, height: 180)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.pink.opacity(0.3), lineWidth: 2)
                            .scaleEffect(1.2)
                    )
                    .shadow(radius: 10)
                
                // 输入框
                VStack(spacing: 8) {
                    TextField("输入萌宠名字".appLocalized, text: $inputName)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(15)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            confirmName()
                        }
                        .padding(.horizontal, 40)
                    
                    if inputName.isEmpty {
                        Text("名字不能为空哦".appLocalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                    }
                }
                
                Spacer()
                
                // 确认按钮
                Button(action: confirmName) {
                    Text("开始陪伴".appLocalized)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
                            ? Color.gray.opacity(0.5) 
                            : Color.pink
                        )
                        .cornerRadius(15)
                        .shadow(radius: inputName.isEmpty ? 0 : 5)
                }
                .disabled(inputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func confirmName() {
        let trimmedName = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        withAnimation {
            petName = trimmedName
            onConfirm()
        }
    }
}

#Preview {
    PetNamingView(petName: .constant(nil)) {}
}
