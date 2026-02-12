import SwiftUI

struct ChatView: View {
    @StateObject private var petAI: PetAIService
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSending = false
    
    // 初始化时传入角色和API Key
    init(role: PetRole, petName: String, apiKey: String) {
        _petAI = StateObject(wrappedValue: PetAIService(role: role, petName: petName, apiKey: apiKey))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 聊天记录区域
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.gray.opacity(0.1))
            
            // 输入区域
            HStack(spacing: 10) {
                TextField("跟它聊聊...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding()
            .background(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: -5)
        }
    }
    
    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        // 1. 显示用户消息
        let userMsg = ChatMessage(text: userText, isUser: true)
        messages.append(userMsg)
        inputText = ""
        isSending = true
        
        // 2. 异步请求 AI 回复
        Task {
            // 模拟一点延迟，让交互更自然
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            let reply = await petAI.sendMessage(userText)
            
            await MainActor.run {
                messages.append(reply)
                isSending = false
                
                // 触发触觉反馈
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }
}

// 单条消息气泡组件
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer()
                
                Text(message.text)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .corners([.topLeft, .topRight, .bottomLeft], radius: 16)
                    .corners([.bottomRight], radius: 2)
            } else {
                // AI 回复
                VStack(alignment: .leading, spacing: 8) {
                    // 1. 图片内容 (如果有)
                    if let imageName = message.imageName {
                        // 尝试加载图片，如果 Assets 中没有，显示占位符
                        // 注意：这里假设图片在 Assets.xcassets 中
                        if let _ = UIImage(named: imageName) {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200)
                                .cornerRadius(12)
                        } else {
                            // 调试用占位符
                            ZStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(12)
                                
                                VStack {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                    Text(imageName)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    
                    // 2. 文字内容
                    Text(message.text)
                        .padding(12)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(16)
                        .corners([.topLeft, .topRight, .bottomRight], radius: 16)
                        .corners([.bottomLeft], radius: 2)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                }
                
                Spacer()
            }
        }
    }
}

// 辅助扩展：圆角设置
extension View {
    func corners(_ corners: UIRectCorner, radius: CGFloat) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}
