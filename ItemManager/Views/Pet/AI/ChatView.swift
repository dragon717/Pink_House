import SwiftUI

struct ChatView: View {
    @ObservedObject var petAI: PetAIService
    @State private var inputText = ""
    @State private var isSending = false
    
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
            ScrollView {
                // 使用 LazyVStack 且翻转，实现倒序列表 (底部对齐)
                // 列表逻辑顺序：Index 0 (最新) -> Index N (最旧)
                // 视觉顺序：Index 0 在最底部，Index N 在最顶部
                LazyVStack(spacing: 20) {
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
                        .scaleEffect(y: -1) // 翻转每个 Item 内容，使其正向显示
                    }
                    
                    // 加载更多触发器 (放在列表末尾 = 视觉顶部)
                    if petAI.hasMoreMessages {
                        ProgressView()
                            .frame(height: 40)
                            .scaleEffect(y: -1) // 翻转加载圈
                            .onAppear {
                                loadMoreHistory()
                            }
                    }
                }
                .padding(.vertical)
                // 视觉底部（逻辑顶部）增加额外间距，防止内容紧贴输入框
                .padding(.top, 10)
            }
            .scaleEffect(y: -1) // 翻转整个 ScrollView，使其从底部开始
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
        .navigationTitle("萌宠日记")
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
        }
        .fullScreenCover(item: $selectedImageWrapper) { wrapper in
            FullScreenImageViewer(image: wrapper.image)
        }
        .toolbar(.hidden, for: .tabBar) // 隐藏底部 TabBar，避免遮挡输入框，并提供沉浸式体验
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
    
    private func loadMoreHistory() {
        // 简单的触发加载，无需处理滚动位置，因为追加到末尾（视觉顶部）不会影响当前视口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = petAI.loadMoreMessages()
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

// End of ChatView

