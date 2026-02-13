import SwiftUI

struct ChatView: View {
    @ObservedObject var petAI: PetAIService
    @State private var inputText = ""
    @State private var isSending = false
    
    // Pagination State
    @State private var isLoadingHistory = false
    @State private var previousTopMessageId: UUID?
    
    // Edit Mode State
    @State private var isEditing = false
    @State private var selectedMessageIds = Set<UUID>()
    @State private var showingDeleteAlert = false
    
    // Image Viewing State
    @State private var selectedImageWrapper: ImageWrapper?
    
    // 初始化时传入 Service
    init(service: PetAIService) {
        self.petAI = service
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 聊天记录区域
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Loading Trigger (Pagination)
                        if !petAI.uiMessages.isEmpty {
                            Color.clear
                                .frame(height: 20)
                                .onAppear {
                                    loadMore()
                                }
                        }
                        
                        ForEach(petAI.uiMessages) { msg in
                            HStack {
                                if isEditing {
                                    Image(systemName: selectedMessageIds.contains(msg.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(selectedMessageIds.contains(msg.id) ? .pink : .gray.opacity(0.5))
                                        .onTapGesture {
                                            toggleSelection(for: msg.id)
                                        }
                                }
                                
                                MessageBubble(message: msg, onImageTap: { image in
                                    if isEditing {
                                        toggleSelection(for: msg.id)
                                    } else {
                                        selectedImageWrapper = ImageWrapper(image: image)
                                    }
                                })
                                    .id(msg.id)
                                    .onTapGesture {
                                        if isEditing {
                                            toggleSelection(for: msg.id)
                                        }
                                    }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: petAI.uiMessages) { _ in
                    if isLoadingHistory, let oldId = previousTopMessageId {
                        // Maintain scroll position (keep old top message visible at top)
                        proxy.scrollTo(oldId, anchor: .top)
                        
                        // Reset state
                        isLoadingHistory = false
                        previousTopMessageId = nil
                    } else if !isEditing, let lastId = petAI.uiMessages.last?.id {
                        // Auto-scroll to bottom for new messages
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .background(
                ZStack {
                    Color(hex: "FFF0F5").opacity(0.3) // Light base
                    PatternBackground()
                }
            )
            
            // 输入区域 (编辑模式下隐藏)
            if !isEditing {
                PetDialogueInputView(
                    text: $inputText,
                    onSend: {
                        sendMessage()
                    }
                )
                .disabled(petAI.isProcessing)
            } else {
                // 编辑模式下的底部工具栏
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("删除 (\(selectedMessageIds.count))")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(selectedMessageIds.isEmpty ? Color.gray : Color.red)
                        .cornerRadius(24)
                    }
                    .disabled(selectedMessageIds.isEmpty)
                    Spacer()
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: -5)
            }
        }
        .navigationTitle("\(petAI.petName)的日记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    withAnimation {
                        isEditing.toggle()
                        selectedMessageIds.removeAll()
                    }
                }) {
                    Text(isEditing ? "完成" : "管理")
                        .foregroundStyle(.pink)
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedMessages()
            }
        } message: {
            Text("确定要删除选中的 \(selectedMessageIds.count) 条记录吗？此操作无法撤销。")
        }
        .onDisappear {
            // 离开页面时停止语音播放
            PetVoiceManager.shared.stop()
            // 释放内存并重置 UI 状态
            petAI.resetToLatest()
        }
        .fullScreenCover(item: $selectedImageWrapper) { wrapper in
            FullScreenImageViewer(image: wrapper.image)
        }
    }
    
    private func toggleSelection(for id: UUID) {
        if selectedMessageIds.contains(id) {
            selectedMessageIds.remove(id)
        } else {
            selectedMessageIds.insert(id)
        }
    }
    
    private func deleteSelectedMessages() {
        petAI.deleteMessages(ids: selectedMessageIds)
        withAnimation {
            isEditing = false
            selectedMessageIds.removeAll()
        }
    }
    
    private func loadMore() {
        guard !isLoadingHistory else { return }
        
        if let firstId = petAI.uiMessages.first?.id {
            previousTopMessageId = firstId
            isLoadingHistory = true
            
            // Give UI a moment
            DispatchQueue.main.async {
                petAI.loadMoreHistory()
                
                // If no change (end of history), reset state
                if let newFirstId = petAI.uiMessages.first?.id, newFirstId == firstId {
                    isLoadingHistory = false
                    previousTopMessageId = nil
                }
            }
        }
    }

    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        inputText = ""
        isSending = true
        
        // 异步请求 AI 回复
        Task {
            // 模拟一点延迟，让交互更自然
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            _ = await petAI.sendMessage(userText)
            
            await MainActor.run {
                isSending = false
                
                // 触发触觉反馈
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }
}




