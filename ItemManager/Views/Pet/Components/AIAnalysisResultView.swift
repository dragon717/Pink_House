import SwiftUI
import UIKit

struct AIAnalysisResultView: View {
    let resultText: String
    let analyzedImage: UIImage?
    var userQuestion: String = "这是什么？" // 默认问题，如果未提供
    var petName: String = "萌宠" // 动态名字
    let onClose: () -> Void
    
    @State private var isExpanded = false
    @State private var localMessages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    
    // For Image Viewer
    @State private var selectedImageWrapper: ImageWrapper?
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 1. Expanded View (Full Chat Interface)
            if isExpanded {
                // Dimmed Background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }
                
                // Chat Card
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("\(petName)的观察日记")
                            .font(.headline)
                            .foregroundStyle(.pink)
                        Spacer()
                        Button(action: {
                            withAnimation {
                                onClose()
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.gray.opacity(0.5))
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.9))
                    
                    // Message List
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
                                        Spacer() // AI typing indicator on left? No, usually left.
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
                    .background(
                        ZStack {
                            Color(hex: "FFF0F5").opacity(0.5)
                            PatternBackground()
                        }
                    )
                    
                    // Input Area
                    PetDialogueInputView(
                        text: $inputText,
                        onSend: sendMessage
                    )
                    .disabled(isSending)
                }
                .frame(maxWidth: 500, maxHeight: 600) // Max size for iPad/Desktop
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                .padding(20)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .zIndex(1)
            }
            
            // 2. Collapsed View (Cat Paw Icon)
            if !isExpanded {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isExpanded = true
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: .pink.opacity(0.4), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "pawprint.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                        
                        // Badge or Indicator?
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 64, height: 64)
                            .scaleEffect(1.1)
                            .opacity(0.5)
                            .overlay(
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(Color.pink, lineWidth: 2)
                                    .rotationEffect(.degrees(Date().timeIntervalSince1970 * 90))
                            )
                    }
                }
                .padding(.bottom, 100) // Adjust based on position requirements
                .padding(.trailing, 30)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }
        }
        .onAppear {
            initializeMessages()
        }
        .fullScreenCover(item: $selectedImageWrapper) { wrapper in
            FullScreenImageViewer(image: wrapper.image)
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
        
        // Add User Message locally
        let userMsg = ChatMessage(text: text, isUser: true)
        withAnimation {
            localMessages.append(userMsg)
            // inputText = "" // PetDialogueInputView doesn't clear binding automatically? 
            // Usually InputView binds to text, so clearing it here clears the view.
            inputText = ""
            isSending = true
        }
        
        Task {
            // Call AI Service
            // Note: This adds to global history too
            let aiMsg = await PetAIService.shared.sendMessage(text)
            
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
