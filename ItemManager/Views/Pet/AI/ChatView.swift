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
    
    // 历史记录解锁状态（下拉触发）
    @State private var isHistoryUnlocked = false
    @State private var historyUnlockProgress: CGFloat = 0
    @State private var showingHistoryUnlockHint = false
    @State private var isChatScrollPinnedToTop = true
    @State private var initialHistoryMessageIDs = Set<UUID>()
    @State private var isLoadingHistoryPage = false
    @State private var previousTopVisibleMessageId: UUID?
    @State private var lockedWelcomeTimestamp = Date()
    
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
    @State private var showingVIPUpsellAlert = false
    @State private var showingVIPCenter = false
    
    // AI 免责声明状态
    @AppStorage("hasShownAIDisclaimer") private var hasShownAIDisclaimer = false
    @State private var showingDisclaimer = false
    @State private var showingHistorySearch = false
    @StateObject private var greetingManager = DailyGreetingManager.shared
    
    private let historyUnlockThreshold: CGFloat = 120
    private let historyUnlockHintThreshold: CGFloat = 18
    private let historyUnlockDragMinimumDistance: CGFloat = 12
    private let historyPageSize: Int = 10
    private let lockedWelcomeMessageID = UUID(uuidString: "A4FB4D91-7F98-4A4F-B847-5B2F792DC9B5") ?? UUID()
    
    // 初始化时传入 Service
    init(service: PetAIService) {
        self.petAI = service
        self._initialHistoryMessageIDs = State(initialValue: Set(service.uiMessages.map(\.id)))
    }
    
    private var visibleMessages: [ChatMessage] {
        if isHistoryUnlocked {
            return petAI.uiMessages
        }
        return petAI.uiMessages.filter { !initialHistoryMessageIDs.contains($0.id) }
    }
    
    private var hasLockedHistory: Bool {
        !isHistoryUnlocked && !initialHistoryMessageIDs.isEmpty
    }

    private var currentCharacter: PetCharacter {
        PetDataManager.shared.getCurrentPetCharacter()
    }

    private func localizedCatchphraseText(_ text: String) -> String {
        currentCharacter.localizedCatchphraseText(text)
    }
    
    private var reusableWelcomeText: String {
        let greeting = greetingManager.getGreetingTitle()
        let petDisplayName = PetDataManager.shared.status.displayName
        return "\(greeting)\(currentCharacter.catchphraseSuffix) 我是你的衣橱管家\(petDisplayName)，有什么可以帮你的吗？"
    }
    
    private var lockedWelcomeMessage: ChatMessage {
        ChatMessage(
            id: lockedWelcomeMessageID,
            text: reusableWelcomeText,
            isUser: false,
            timestamp: lockedWelcomeTimestamp
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 聊天记录区域
            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: PetAIChatScrollTopOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("PetAIChatScrollView")).minY
                            )
                    }
                    .frame(height: 0)

                    LazyVStack(spacing: 20) {
                        if isHistoryUnlocked {
                            if isLoadingHistoryPage {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.85)
                                    Text("加载历史中...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            
                            if petAI.hasMoreHistoryToLoad {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        loadMoreHistoryIfNeeded()
                                    }
                            }
                        }
                        
                        ForEach(visibleMessages) { msg in
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
                        
                        if visibleMessages.isEmpty {
                            if hasLockedHistory {
                                MessageBubble(message: lockedWelcomeMessage, isAI: true)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .coordinateSpace(name: "PetAIChatScrollView")
                .onPreferenceChange(PetAIChatScrollTopOffsetPreferenceKey.self) { minY in
                    handleHistoryUnlockScrollOffset(minY)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: historyUnlockDragMinimumDistance)
                        .onChanged(handleHistoryUnlockDragChanged)
                        .onEnded(handleHistoryUnlockDragEnded)
                )
                .overlay(alignment: .top) {
                    if hasLockedHistory {
                        Group {
                            if showingHistoryUnlockHint || historyUnlockProgress > 0 {
                                historyUnlockIndicator
                            } else {
                                lockedHistoryTopHint
                                    .onTapGesture {
                                        unlockHistory()
                                    }
                            }
                        }
                        .padding(.top, 8)
                        .allowsHitTesting(true)
                    }
                }
                .onChange(of: petAI.uiMessages) { _ in
                    if isLoadingHistoryPage, let oldTopId = previousTopVisibleMessageId {
                        proxy.scrollTo(oldTopId, anchor: .top)
                        isLoadingHistoryPage = false
                        previousTopVisibleMessageId = nil
                    } else if !isEditing, let lastId = visibleMessages.last?.id {
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingHistorySearch = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.pink)
                }
            }
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
            Text("AI 生成的内容可能不准确或具有误导性，请注意甄别。\n\n本应用使用第三方 AI 服务，对话内容仅存储在您的设备本地。")
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
        .sheet(isPresented: $showingHistorySearch) {
            PetChatHistorySearchSheet { query in
                sendMessageFromHistory(query)
            }
        }
        .sheet(isPresented: $showingVIPCenter) {
            NavigationStack {
                VIPCenterView()
            }
        }
        // 举报成功提示
        .alert("举报已提交", isPresented: $showingReportSuccess) {
            Button("确定") { }
        } message: {
            Text("感谢您的反馈，我们会持续改进 AI 内容质量。")
        }
        .alert("\(PetChatPremiumFeature.remoteChat.title) 是 VIP 权益", isPresented: $showingVIPUpsellAlert) {
            Button("去升级VIP") {
                showingVIPCenter = true
            }
            Button("稍后", role: .cancel) { }
        } message: {
            Text(PetChatPremiumFeature.remoteChat.upsellText(petName: petAI.petName))
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
    
    private var historyUnlockIndicator: some View {
        let progress = min(max(historyUnlockProgress, 0), 1)
        
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.pink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(progress * 100))%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.pink)
            }
            .frame(width: 34, height: 34)
            
            Text(localizedCatchphraseText(progress >= 1 ? "松手就给你翻旧日记喵~" : "再下拉一点就能看喵~"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.92))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
    }
    
    private var lockedHistoryTopHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.pink.opacity(0.85))
            Text(localizedCatchphraseText("下拉或者点这里，我就把旧日记翻给你看喵~"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.9))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
    
    private func handleHistoryUnlockScrollOffset(_ minY: CGFloat) {
        isChatScrollPinnedToTop = minY >= -8

        guard hasLockedHistory else {
            resetHistoryUnlockHintIfNeeded(animated: false)
            return
        }

        let overscroll = max(0, minY)
        let progress = min(overscroll / historyUnlockThreshold, 1)

        if progress >= 1 {
            unlockHistory()
            return
        }

        historyUnlockProgress = progress
        showingHistoryUnlockHint = overscroll > historyUnlockHintThreshold && isChatScrollPinnedToTop

        if overscroll <= 0 {
            resetHistoryUnlockHintIfNeeded(animated: true)
        }
    }

    private func handleHistoryUnlockDragChanged(_ value: DragGesture.Value) {
        guard hasLockedHistory, isChatScrollPinnedToTop else { return }

        let pullDistance = max(0, value.translation.height)
        guard pullDistance > 0 else { return }

        let progress = min(pullDistance / historyUnlockThreshold, 1)
        historyUnlockProgress = max(historyUnlockProgress, progress)
        showingHistoryUnlockHint = true
    }

    private func handleHistoryUnlockDragEnded(_ value: DragGesture.Value) {
        guard hasLockedHistory else { return }

        let pullDistance = max(0, value.translation.height)
        let progress = max(historyUnlockProgress, min(pullDistance / historyUnlockThreshold, 1))

        if progress >= 1 {
            unlockHistory()
        } else {
            resetHistoryUnlockHintIfNeeded(animated: true)
        }
    }

    private func resetHistoryUnlockHintIfNeeded(animated: Bool) {
        guard historyUnlockProgress > 0 || showingHistoryUnlockHint else { return }

        let reset = {
            historyUnlockProgress = 0
            showingHistoryUnlockHint = false
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                reset()
            }
        } else {
            reset()
        }
    }
    
    private func unlockHistory() {
        isHistoryUnlocked = true
        showingHistoryUnlockHint = false
        historyUnlockProgress = 0
        petAI.activatePagedHistoryMode(initialVisibleCount: historyPageSize)
        initialHistoryMessageIDs.removeAll(keepingCapacity: false)
    }
    
    private func loadMoreHistoryIfNeeded() {
        guard isHistoryUnlocked else { return }
        guard !isLoadingHistoryPage else { return }
        guard petAI.hasMoreHistoryToLoad else { return }
        guard let currentTopId = visibleMessages.first?.id else { return }
        
        previousTopVisibleMessageId = currentTopId
        isLoadingHistoryPage = true
        
        let loadedCount = petAI.loadMoreHistory(pageSize: historyPageSize)
        if loadedCount == 0 {
            isLoadingHistoryPage = false
            previousTopVisibleMessageId = nil
        }
    }

    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        guard VIPManager.shared.isVIP else {
            showingVIPUpsellAlert = true
            return
        }
        
        inputText = ""
        isSending = true
        
        // 异步请求 AI 回复
        Task {
            // 模拟一点延迟，让交互更自然
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            let prompt = buildPrompt(for: userText)

            _ = await petAI.sendMessage(prompt, displayText: userText)
            
            await MainActor.run {
                isSending = false
                
                // 触发触觉反馈
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }

    private func currentPersonaProfile() -> PetPersonaProfile {
        let character = PetDataManager.shared.getCurrentPetCharacter()
        return PetPersonaRegistry.profile(for: character.aiRole, petName: petAI.petName)
    }

    private func sendMessageFromHistory(_ query: String) {
        let userText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        guard VIPManager.shared.isVIP else {
            showingVIPUpsellAlert = true
            return
        }

        isSending = true
        Task {
            let prompt = buildPrompt(for: userText)

            _ = await petAI.sendMessage(prompt, displayText: userText)

            await MainActor.run {
                isSending = false
            }
        }
    }

    private func buildPrompt(for userText: String) -> String {
        let persona = currentPersonaProfile()
        let module = PetChatIntentRouter.detect(from: userText).module
        return PetGenerativePromptBuilder.buildPrompt(
            input: .init(
                userQuery: userText,
                wardrobeContextBlock: nil,
                persona: persona,
                module: module,
                recentAssistantReplies: PetGenerativePromptBuilder.recentAssistantReplies(
                    from: petAI.uiMessages,
                    isUser: \.isUser,
                    text: \.text
                )
            )
        )
    }
}

private struct PetAIChatScrollTopOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
