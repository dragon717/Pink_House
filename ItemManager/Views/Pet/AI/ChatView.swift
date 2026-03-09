import SwiftUI

// AI 消息举报原因枚举
enum AIReportReason: String, CaseIterable {
    case inappropriate = "不当内容"
    case inaccurate = "内容不准确"
    case harmful = "有害信息"
    case other = "其他"
    
    var icon: String {
        switch self {
        case .inappropriate: return "exclamationmark.triangle"
        case .inaccurate: return "xmark.circle"
        case .harmful: return "shield.exclamationmark"
        case .other: return "questionmark.circle"
        }
    }
}

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
    
    // AI 举报功能状态
    @State private var showingReportSheet = false
    @State private var reportedMessageId: UUID?
    @State private var selectedReportReason: AIReportReason?
    @State private var reportDescription = ""
    @State private var showingReportSuccess = false
    
    // AI 免责声明状态
    @AppStorage("hasShownAIDisclaimer") private var hasShownAIDisclaimer = false
    @State private var showingDisclaimer = false
    
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
                                
                                MessageBubble(
                                    message: msg,
                                    isAI: !msg.isUser,
                                    onImageTap: { image in
                                        if isEditing {
                                            toggleSelection(for: msg.id)
                                        } else {
                                            selectedImageWrapper = ImageWrapper(image: image)
                                        }
                                    },
                                    onReport: !msg.isUser ? {
                                        reportedMessageId = msg.id
                                        showingReportSheet = true
                                    } : nil
                                )
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
                if petAI.isProcessing {
                    // AI 生成中显示停止按钮
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text("AI 思考中...")
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            petAI.stopGeneration()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                Text("停止")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(20)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: -5)
                } else {
                    PetDialogueInputView(
                        text: $inputText,
                        onSend: {
                            sendMessage()
                        }
                    )
                }
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
        .onAppear {
            // 首次使用时显示 AI 免责声明
            if !hasShownAIDisclaimer {
                showingDisclaimer = true
            }
        }
        .fullScreenCover(item: $selectedImageWrapper) { wrapper in
            FullScreenImageViewer(image: wrapper.image)
        }
        // AI 免责声明弹窗
        .alert("AI 功能免责声明", isPresented: $showingDisclaimer) {
            Button("我已了解") {
                hasShownAIDisclaimer = true
            }
        } message: {
            Text("AI 生成的内容可能不准确或具有误导性，请注意甄别。\n\n本应用使用 DeepSeek、Minimax 等第三方 AI 服务，对话内容仅存储在您的设备本地。")
        }
        // AI 内容举报弹窗
        .sheet(isPresented: $showingReportSheet) {
            AIReportSheet(
                selectedReason: $selectedReportReason,
                description: $reportDescription,
                onSubmit: submitReport,
                onCancel: { showingReportSheet = false }
            )
        }
        // 举报成功提示
        .alert("举报已提交", isPresented: $showingReportSuccess) {
            Button("确定") { }
        } message: {
            Text("感谢您的反馈，我们会持续改进 AI 内容质量。")
        }
    }
    
    // 提交举报
    private func submitReport() {
        guard let messageId = reportedMessageId,
              let reason = selectedReportReason else { return }
        
        // 这里可以将举报信息发送到服务器或本地记录
        print("🚨 AI 内容举报 - 消息ID: \(messageId), 原因: \(reason.rawValue), 描述: \(reportDescription)")
        
        // 重置状态
        showingReportSheet = false
        selectedReportReason = nil
        reportDescription = ""
        reportedMessageId = nil
        
        // 显示成功提示
        showingReportSuccess = true
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




