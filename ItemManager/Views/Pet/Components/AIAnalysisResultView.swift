import SwiftUI
import UIKit

struct AIAnalysisResultView: View {
    let resultText: String
    let analyzedImage: UIImage?
    var userQuestion: String = "这是什么？" // 默认问题，如果未提供
    var petName: String = "小伙伴" // 动态名字，实际使用时应传入 status.displayName
    let onClose: () -> Void
    
    @State private var isChatMode = false
    @State private var appearAnimation = false
    @State private var localMessages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    
    // For Image Viewer
    @State private var selectedImageWrapper: ImageWrapper?
    
    var body: some View {
        ZStack {
            // Background Blur/Dim
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    closeWithAnimation()
                }
            
            // Main Card
            VStack(spacing: 0) {
                // Header (Common)
                if !isChatMode {
                    headerView
                } else {
                    chatHeaderView
                }
                
                // Content Area
                if !isChatMode {
                    // 1. Result Display Mode
                    resultContentView
                } else {
                    // 2. Chat Mode
                    chatContentView
                }
                
                // Footer Area
                if !isChatMode {
                    // Result Actions
                    HStack(spacing: 20) {
                        Button(action: closeWithAnimation) {
                            Text("收到啦 💖")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "FFB6C1"), Color(hex: "FF69B4")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "FF69B4").opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        
                        Button(action: {
                            withAnimation(.spring()) {
                                isChatMode = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "pawprint.fill")
                                Text("继续问问")
                            }
                            .font(.headline)
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.pink, lineWidth: 2)
                            )
                        }
                    }
                    .padding(24)
                } else {
                    // Chat Input
                    PetDialogueInputView(
                        text: $inputText,
                        onSend: sendMessage
                    )
                    .disabled(isSending)
                }
            }
            .background(
                ZStack {
                    Color(hex: "FFF0F5") // Base background
                    PatternBackground()  // Texture
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
            )
            .shadow(color: Color(hex: "FF69B4").opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, isChatMode ? 20 : 40)
            .padding(.vertical, isChatMode ? 40 : 20)
            .frame(maxWidth: 500)
            .scaleEffect(appearAnimation ? 1.0 : 0.8)
            .opacity(appearAnimation ? 1.0 : 0.0)
        }
        .onAppear {
            initializeMessages()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appearAnimation = true
            }
        }
        .fullScreenCover(item: $selectedImageWrapper) { wrapper in
            FullScreenImageViewer(image: wrapper.image)
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 0) {
            if let image = analyzedImage {
                ZStack {
                    Color.white
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
                }
                .frame(height: 200)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color(hex: "FFF0F5")],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottomTrailing) {
                    StampView()
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                        .rotationEffect(.degrees(-15))
                }
            }
            
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: "FF69B4"))
                Text("\(petName)观察日记")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "DB7093"))
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(hex: "FF69B4"))
            }
            .padding(.top, analyzedImage == nil ? 20 : 10)
            .padding(.bottom, 10)
        }
    }
    
    private var chatHeaderView: some View {
        HStack {
            Text("\(petName)的观察日记")
                .font(.headline)
                .foregroundStyle(.pink)
            Spacer()
            Button(action: {
                closeWithAnimation()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .padding()
        .background(Color.white.opacity(0.5))
    }
    
    private var resultContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // User Question (Collapsed style)
            HStack {
                Text("你问了\(petName):")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Text(userQuestion)
                    .font(.caption)
                    .foregroundStyle(Color(hex: "DB7093"))
                    .lineLimit(1)
            }
            .padding(10)
            .background(Color.white.opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal)
            
            ScrollView(showsIndicators: false) {
                Text(resultText)
                    .font(.system(.body, design: .rounded))
                    .lineSpacing(6)
                    .foregroundStyle(Color(hex: "4A4A4A"))
                    .padding(.horizontal)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
    }
    
    private var chatContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(localMessages) { msg in
                        MessageBubble(message: msg, onImageTap: { image in
                            selectedImageWrapper = ImageWrapper(image: image)
                        })
                        .id(msg.id)
                    }
                    
                    if isSending {
                        HStack {
                            Spacer()
                            TypingIndicator()
                            Spacer()
                        }
                        .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: localMessages.count) { _ in
                if let lastId = localMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Logic
    
    private func closeWithAnimation() {
        withAnimation(.easeIn(duration: 0.2)) {
            appearAnimation = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onClose()
        }
    }
    
    private func initializeMessages() {
        guard localMessages.isEmpty else { return }
        
        // 1. User Message (with Image)
        var imagePath: String? = nil
        if let image = analyzedImage {
            imagePath = saveTempImage(image)
        }
        
        let userMsg = ChatMessage(
            text: userQuestion,
            imagePath: imagePath,
            isUser: true
        )
        
        // 2. AI Message (Result)
        let aiMsg = ChatMessage(
            text: resultText,
            isUser: false
        )
        
        localMessages = [userMsg, aiMsg]
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let userMsg = ChatMessage(text: text, isUser: true)
        withAnimation {
            localMessages.append(userMsg)
            inputText = ""
            isSending = true
        }
        
        Task {
            let character = PetDataManager.shared.getCurrentPetCharacter()
            let persona = PetPersonaRegistry.profile(
                for: character.aiRole,
                petName: PetDataManager.shared.status.displayName
            )
            let module = PetChatIntentRouter.detect(from: text).module
            let recentAssistantReplies = PetGenerativePromptBuilder.recentAssistantReplies(
                from: localMessages,
                isUser: \.isUser,
                text: \.text
            )
            let prompt = PetGenerativePromptBuilder.buildPrompt(
                input: .init(
                    userQuery: text,
                    wardrobeContextBlock: nil,
                    persona: persona,
                    module: module,
                    recentAssistantReplies: recentAssistantReplies
                )
            )
            let aiMsg = await PetAIService.shared.sendMessage(prompt, displayText: text)
            await MainActor.run {
                withAnimation {
                    localMessages.append(aiMsg)
                    isSending = false
                }
            }
        }
    }
    
    private func saveTempImage(_ image: UIImage) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent(fileName)
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
            return fileName
        }
        return nil
    }
}

// Simple Typing Indicator
struct TypingIndicator: View {
    @State private var offset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.gray).frame(width: 6, height: 6).offset(y: offset)
            Circle().fill(Color.gray).frame(width: 6, height: 6).offset(y: -offset)
            Circle().fill(Color.gray).frame(width: 6, height: 6).offset(y: offset)
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                offset = 3
            }
        }
    }
}
