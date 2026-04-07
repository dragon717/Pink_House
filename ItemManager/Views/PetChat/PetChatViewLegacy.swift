import SwiftUI
import SwiftData
import CoreLocation

// MARK: - iOS 18以下版本
struct PetChatViewLegacy: View {
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]
    
    @StateObject private var petAI = PetAIService.shared
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared
    @State private var messages: [PetChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @State private var isThinkingLongWait = false
    @State private var thinkingDelayWorkItem: DispatchWorkItem?
    @State private var selectedClothing: Clothing?
    @State private var navigateToDetail = false
    @State private var hasEnteredOnce = false
    @State private var showingHistorySearch = false
    @State private var showingMeowCoinStore = false
    @State private var showingVIPCenter = false
    @State private var showingCurrencyExchangeSheet = false
    @State private var preferredExchangeDirection: PetCurrencyExchangeDirection = .fishToBone
    @State private var showingRenameAlert = false
    @State private var renameInputText = ""
    @State private var showingInitialAdoptionSheet = false

    // 搭配建议相关状态
    @State private var selectedOutfitClothings: [Clothing] = []
    @State private var showingOutfitStickerFlow = false
    
    // 保存成功提示状态
    @State private var showingSaveSuccessToast = false
    @State private var showingPurchaseSuccessToast = false
    @State private var purchaseSuccessMessage = ""
    @State private var purchaseToastHideWorkItem: DispatchWorkItem?
    @State private var isSavingOutfit = false
    @State private var showingThemeSwitchOverlay = false
    @State private var activeFeedAnimation: PetFeedAnimationPayload?
    @State private var feedAnimationNonce: Int = 0
    @State private var lastInjectedAIAnalysisGuideCaptureVersion: UInt = 0

    @StateObject private var greetingManager = DailyGreetingManager.shared
    @StateObject private var adoptionViewModel = PetViewModel(status: PetDataManager.shared.status)
    
    // 输入框提示文字，使用用户起的宠物名字
    private var inputPlaceholder: String {
        let petName = PetDataManager.shared.status.displayName
        return "和\(petName)对话、搜索裙子..."
    }

    private var quickMenuOwnedPets: [PetCharacter] {
        let owned = Set(PetDataManager.shared.status.ownedPetIds)
        return PetCharacter.allCases.filter { owned.contains($0.id) }
    }

    private var quickMenuAdoptionTitle: String? {
        let owned = Set(PetDataManager.shared.status.ownedPetIds)
        guard PetCharacter.allCases.contains(where: { !owned.contains($0.id) }) else { return nil }
        return "领养\(quickMenuOwnedPets.count + 1)胎"
    }

    private var currentCharacter: PetCharacter {
        PetDataManager.shared.getCurrentPetCharacter()
    }
    
    // 菜单回调
    private var menuCallbacks: PetChatMenuCallbacks {
        PetChatMenuCallbacks(
            handleOutfitSuggestion: { query in
                handleOutfitSuggestion(query)
            },
            createQuickOutfit: { style, occasion in
                createQuickOutfit(style: style, occasion: occasion)
            },
            handleWardrobeStatistics: { handleWardrobeStatistics() },
            handlePetStatusOverview: { handlePetStatusOverview() },
            handleSwitchPetIntent: { handleSwitchPetIntent() },
            handleSecondPetAdoptionIntent: { handleSecondPetAdoptionIntent() },
            handleRenamePetIntent: { handleRenamePetIntent() },
            handleInventoryPanel: { handleInventoryPanel() },
            handleShopPanel: { handleShopPanel() },
            handleWeatherOutfitGuidance: { handleWeatherOutfitGuidance() },
            handleDepositPlanQuery: { handleDepositPlanQuery() },
            handleMoneyCounterPanel: { handleMoneyCounterPanel() },
            handleDivinationPanel: { handleDivinationPanel() },
            onSearchWardrobe: {
                inputText = WardrobeContextManager.shared.defaultSearchPrompt(clothings: clothings)
            },
            onShowHistorySearch: {
                showingHistorySearch = true
            }
        )
    }
    
    // 菜单上下文
    private var menuContext: PetChatMenuContext {
        PetChatMenuContext(
            clothings: clothings,
            quickMenuOwnedPets: quickMenuOwnedPets,
            quickMenuAdoptionTitle: quickMenuAdoptionTitle
        )
    }

    private func localizedCatchphraseText(_ text: String) -> String {
        currentCharacter.localizedCatchphraseText(text)
    }

    private func adoptionOptionTitle(for pet: PetCharacter, status: PetStatus) -> String {
        let (price, currency) = PetViewModel.adoptionPrice(for: pet, ownedPetIds: status.ownedPetIds)
        if price <= 0 {
            return "领养\(pet.displayName)（免费）"
        }
        return "领养\(pet.displayName)（\(price)\(currency.rawValue)）"
    }

    private func presentInitialAdoptionSheetIfNeeded() {
        guard PetDataManager.shared.status.ownedPetIds.isEmpty else { return }
        adoptionViewModel.status = PetDataManager.shared.status
        showingInitialAdoptionSheet = true
    }

    private func presentAdoptionSheet() {
        adoptionViewModel.status = PetDataManager.shared.status
        showingInitialAdoptionSheet = true
    }

    private var currentThinkingImageName: String {
        let status = PetDataManager.shared.status
        let character = PetCharacter(rawValue: status.selectedPetId ?? "") ?? .naicha
        if isThinkingLongWait {
            return character.chatExpressionImageName(for: .confused)
        }
        if petChatShouldShowSleepyExpression(status: status) {
            return character.chatExpressionImageName(for: .sleepy)
        }
        return character.chatExpressionImageName(for: .thinking)
    }

    private func updateThinkingPhase(isActive: Bool) {
        thinkingDelayWorkItem?.cancel()
        thinkingDelayWorkItem = nil

        guard isActive else {
            isThinkingLongWait = false
            return
        }

        isThinkingLongWait = false
        let workItem = DispatchWorkItem { [self] in
            guard isThinking else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isThinkingLongWait = true
            }
        }
        thinkingDelayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    private var legacyThinkingBubble: some View {
        HStack {
            AnyView(
                ModernAIThinkingView(
                    petImageName: currentThinkingImageName,
                    isConfused: isThinkingLongWait
                )
            )
            .id("thinking")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景 - 使用 LiquidBackground，不使用魔法配色/客制化配色的背景色
                LiquidBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    AnyView(legacyMessageBubble(for: message))
                                }
                                
                                if isThinking {
                                    legacyThinkingBubble
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .onChange(of: messages.count) { _ in
                            if let lastId = messages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: isThinking) { _ in
                            updateThinkingPhase(isActive: isThinking)
                            if isThinking {
                                withAnimation {
                                    proxy.scrollTo("thinking", anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // 底部输入区域（Legacy 版本使用萌宠对话框样式）
                    petDialogueInputArea
                }
            }
            .navigationTitle("\(petAI.petName)的悄悄话")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToDetail) {
                if let clothing = selectedClothing {
                    ClothingDetailView(clothing: clothing)
                }
            }
            .sheet(isPresented: $showingHistorySearch) {
                PetChatHistorySearchSheet { query in
                    reuseHistoryQuery(query)
                }
            }
            .sheet(isPresented: $showingMeowCoinStore) {
                MeowCoinStoreView()
            }
            .sheet(isPresented: $showingVIPCenter) {
                NavigationStack {
                    VIPCenterView()
                }
            }
            .sheet(isPresented: $showingCurrencyExchangeSheet) {
                PetCurrencyExchangeSheet(preferredDirection: preferredExchangeDirection)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingInitialAdoptionSheet) {
                NavigationStack {
                    PetAdoptionView(viewModel: adoptionViewModel)
                }
                .presentationDetents([.large])
            }
            .alert("修改名字", isPresented: $showingRenameAlert) {
                TextField("输入新名字", text: $renameInputText)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    commitPetRename()
                }
            } message: {
                Text("改名将消耗一个改名项圈")
            }
            // 保存成功提示覆盖层
            .overlay {
                ZStack {
                    if showingThemeSwitchOverlay {
                        PetThemeSwitchOverlay()
                            .transition(.opacity)
                            .zIndex(90)
                    }

                    if showingSaveSuccessToast {
                        OutfitSaveSuccessToast(message: "已保存到默认手帐")
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                            .zIndex(100)
                    }

                    if showingPurchaseSuccessToast {
                        PetActionSuccessToast(
                            title: "购买成功",
                            message: purchaseSuccessMessage,
                            systemImage: "cart.badge.plus"
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                        .zIndex(105)
                    }

                    if let payload = activeFeedAnimation {
                        PetFeedAnimationOverlay(payload: payload)
                            .transition(.opacity)
                            .zIndex(110)
                    }

                    if let prompt = adoptionViewModel.presentedFundingPrompt {
                        PetShopFundingPromptOverlay(
                            prompt: prompt,
                            onDismiss: { adoptionViewModel.dismissFundingPrompt() },
                            onPrimaryAction: handleFundingPromptPrimaryAction
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(115)
                    }
                }
            }
            .onAppear {
                if messages.isEmpty {
                    loadInitialGreeting()
                }
                presentInitialAdoptionSheetIfNeeded()
                ensureGuideEmbeddedOptionMessageIfNeeded(forceRefreshForCurrentGuideSession: true)
                configureAIService()
                // 首次进入萌宠对话页面时，自动展开搜索栏
                if !hasEnteredOnce {
                    hasEnteredOnce = true
                    // iOS 18 以下版本不支持 isPresented，使用 searchText 触发搜索模式
                    searchText = " "
                }
                NotificationCenter.default.post(
                    name: .petChatSearchStateChanged,
                    object: nil,
                    userInfo: ["isSearching": !searchText.isEmpty]
                )
            }
            .onDisappear {
                thinkingDelayWorkItem?.cancel()
                isThinkingLongWait = false
                purchaseToastHideWorkItem?.cancel()
                showingPurchaseSuccessToast = false
                NotificationCenter.default.post(
                    name: .petChatSearchStateChanged,
                    object: nil,
                    userInfo: ["isSearching": false]
                )
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: adoptionViewModel.presentedFundingPrompt?.id)
            .onChange(of: searchText) { _, newValue in
                NotificationCenter.default.post(
                    name: .petChatSearchStateChanged,
                    object: nil,
                    userInfo: ["isSearching": !newValue.isEmpty]
                )
            }
            .onChange(of: guideManager.currentFeatureExperienceFeature?.rawValue) { _, _ in
                ensureGuideEmbeddedOptionMessageIfNeeded(forceRefreshForCurrentGuideSession: true)
            }
            .onChange(of: messages.count) { _, _ in
                PetChatTranscriptStore.save(messages: messages)
            }
        }
    }

    // 萌宠对话框样式的输入区域（iOS18 版本）- 放在底部导航栏上方
    private var petDialogueInputArea: some View {
        VStack(spacing: 0) {
            // 使用萌宠对话框样式
            HStack(spacing: 12) {
                // 左侧功能菜单按钮
                Menu {
                    PetChatMenuContent(
                        callbacks: menuCallbacks,
                        context: menuContext,
                        useSectionLayout: false
                    )
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.pink)
                }
                
                // 中间输入框（萌宠对话框样式）
                ZStack(alignment: .leading) {
                    if inputText.isEmpty {
                        Text(inputPlaceholder)
                            .foregroundStyle(.gray.opacity(0.6))
                            .padding(.horizontal, 16)
                    }
                    
                    TextField("", text: $inputText)
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
                
                // 右侧发送按钮（猫爪样式）
                Button {
                    if !inputText.isEmpty {
                        sendMessageFromInput()
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
                .disabled(inputText.isEmpty)
                .opacity(inputText.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            ZStack {
                // 主体气泡背景
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFD1DC"), Color(hex: "FFC0CB")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
                
                // 气泡尾巴（左下角）
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
        // 添加底部安全区域间距，避免与底部导航栏重叠
        .padding(.bottom, 80)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    
    // 从底部输入框发送消息 - 等同于 PetDialogueInputView 的功能
    private func sendMessageFromInput() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        // 清空输入框
        inputText = ""
        
        // 添加用户消息到对话
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图
        processUserIntent(userText)
    }

    private func reuseHistoryQuery(_ query: String) {
        let userText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        processUserIntent(userText)
    }

    private func configureAIService() {
        let wardrobeContext = WardrobeContextManager.shared.generateWardrobeSummary(
            clothings: clothings,
            includeItemList: false
        )
        // 获取当前宠物角色，使用对应的AI人设
        let currentCharacter = PetDataManager.shared.getCurrentPetCharacter()
        petAI.ensureConfiguration(
            role: currentCharacter.aiRole,
            petName: PetDataManager.shared.status.displayName,
            wardrobeContext: wardrobeContext
        )
    }
    
    private func loadInitialGreeting() {
        let localTranscript = PetChatTranscriptStore.load(enrichingWith: clothings)
        if !localTranscript.isEmpty {
            messages = localTranscript
            return
        }

        let greeting = greetingManager.getGreetingTitle()
        // 根据当前宠物使用对应的问候语和用户起的宠物名字
        let petDisplayName = PetDataManager.shared.status.displayName // 使用用户起的宠物名字
        let onboardingWidgets = onboardingWidgetsForCurrentPetState()
        let welcomeMessage = PetChatMessage(
            text: "\(greeting)\(currentCharacter.catchphraseSuffix) 我是你的衣橱管家\(petDisplayName)，有什么可以帮你的吗？",
            isUser: false,
            widgets: onboardingWidgets
        )
        messages.append(welcomeMessage)
    }

    private func onboardingWidgetsForCurrentPetState() -> [PetWidgetData] {
        let status = PetDataManager.shared.status
        if status.ownedPetIds.isEmpty {
            return [
                PetWidgetData(
                    type: .quickOptions,
                    title: "先领养一个小伙伴吧",
                    options: [
                        PetWidgetOption(title: adoptionOptionTitle(for: .naicha, status: status), command: "adopt_pet:naicha", icon: PetCharacter.naicha.quickOptionIconName),
                        PetWidgetOption(title: adoptionOptionTitle(for: .maomao, status: status), command: "adopt_pet:maomao", icon: PetCharacter.maomao.quickOptionIconName),
                        PetWidgetOption(title: "看看货币余额", command: "pet_currency_panel", icon: "wallet.pass.fill")
                    ]
                )
            ]
        }
        return PetWidgetSuggestionBuilder.onboardingWidgets()
    }

    private func isAIAnalysisGuideInjectedMessage(_ message: PetChatMessage) -> Bool {
        guard !message.isUser,
              let widgets = message.widgets,
              widgets.count == 1 else { return false }

        let widget = widgets[0]
        return widget.type == .quickOptions &&
            widget.title == "先点对话里的引导选项" &&
            widget.options.count == 1 &&
            widget.options[0].command == "weather_guidance"
    }

    private func ensureGuideEmbeddedOptionMessageIfNeeded(forceRefreshForCurrentGuideSession: Bool = false) {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }

        let currentGuideCaptureVersion = guideManager.guideTargetCaptureVersion
        let shouldRefreshForSession =
            forceRefreshForCurrentGuideSession &&
            lastInjectedAIAnalysisGuideCaptureVersion != currentGuideCaptureVersion

        if shouldRefreshForSession {
            // 重开引导时丢掉旧的专用提示，改为补一条新的可见入口，避免目标只停留在历史记录里。
            messages.removeAll(where: isAIAnalysisGuideInjectedMessage)
        }

        let hasGuideOption = messages.contains { message in
            (message.widgets ?? []).contains { widget in
                widget.options.contains { $0.command == "weather_guidance" }
            }
        }
        guard shouldRefreshForSession || !hasGuideOption else { return }

        let guideWidget = PetWidgetData(
            type: .quickOptions,
            title: "先点对话里的引导选项",
            subtitle: "这个按钮嵌在聊天窗口里，点一下就能开始体验。",
            options: [
                PetWidgetOption(title: "看天气穿搭（引导）", command: "weather_guidance", icon: "cloud.sun.fill")
            ]
        )
        messages.append(
            PetChatMessage(
                text: "先试试这颗嵌入在对话窗口里的引导按钮吧～",
                isUser: false,
                isAIGenerated: true,
                widgets: [guideWidget]
            )
        )
        lastInjectedAIAnalysisGuideCaptureVersion = currentGuideCaptureVersion
    }
    
    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        inputText = ""
        
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        processUserIntent(userText)
    }

    // 创建消息气泡视图（Legacy版本）
    private func legacyMessageBubble(for message: PetChatMessage) -> some View {
        PetChatBubble(
            message: message,
            petName: petAI.petName,
            onCardTap: legacyHandleClothingTap,
            onSearchResultTap: legacyHandleClothingTap,
            onOutfitTap: legacyHandleOutfitTap,
            onWidgetAction: legacyHandleWidgetAction
        )
        .id(message.id)
    }

    // 处理服装点击（Legacy版本）
    private func legacyHandleClothingTap(_ clothing: Clothing) {
        selectedClothing = clothing
        navigateToDetail = true
    }

    // 处理搭配建议点击（Legacy版本）- 直接保存到默认手帐
    private func legacyHandleOutfitTap(_ suggestion: OutfitSuggestionData) {
        guard !isSavingOutfit else { return }
        
        selectedOutfitClothings = suggestion.clothings
        
        // 直接执行保存流程
        Task {
            await legacySaveOutfitToDefaultBook(clothings: suggestion.clothings)
        }
    }
    
    // MARK: - Legacy版本保存搭配到默认手帐
    private func legacySaveOutfitToDefaultBook(clothings: [Clothing]) async {
        await MainActor.run {
            isSavingOutfit = true
        }
        
        do {
            // 获取所有抠图
            let allCutouts = try modelContext.fetch(FetchDescriptor<CutoutItem>())
            
            // 查找推荐裙装的抠图（带路径/哈希兜底）
            let resolved = OOTDCutoutResolver.resolveCutouts(for: clothings, from: allCutouts)
            let availableCutouts = resolved.found
            try? modelContext.save()
            
            // 至少需要2个抠图才能生成搭配
            guard availableCutouts.count >= 2 else {
                await MainActor.run {
                    isSavingOutfit = false
                    let missingNames = resolved.missing.map(\.name).joined(separator: "、")
                    let detail = missingNames.isEmpty ? "" : "\n缺少抠图：\(missingNames)"
                    // 显示错误消息
                    let errorMessage = PetChatMessage(
                        text: localizedCatchphraseText("（歪头）至少需要2件单品的抠图才能生成搭配喵~\(detail)"),
                        isUser: false
                    )
                    messages.append(errorMessage)
                }
                return
            }
            
            // 生成搭配布局
            let outfit = OOTDLayoutEngine.shared.createOutfitWithLayout(
                cutouts: availableCutouts,
                book: nil,
                description: "AI搭配推荐"
            )
            
            // 获取或创建默认手帐
            let book = try await legacyGetOrCreateDefaultBook()
            
            // 保存到数据库
            await MainActor.run {
                outfit.book = book
                modelContext.insert(outfit)
                if let items = outfit.items {
                    for item in items {
                        modelContext.insert(item)
                    }
                }
                try? modelContext.save()
                
                // 显示成功提示
                isSavingOutfit = false
                selectedOutfitClothings = []
                
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showingSaveSuccessToast = true
                }
                
                // 播放成功音效和震动
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // 发送通知，跳转到魔法平面书页
                NotificationCenter.default.post(name: .navigateToBook, object: nil)
                
                // 3秒后自动关闭提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showingSaveSuccessToast = false
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                isSavingOutfit = false
                let errorMessage = PetChatMessage(
                    text: "（挠头）保存搭配失败了：\(error.localizedDescription)",
                    isUser: false
                )
                messages.append(errorMessage)
            }
        }
    }
    
    // MARK: - Legacy版本获取或创建默认手帐
    private func legacyGetOrCreateDefaultBook() async throws -> BookGroup {
        try await MainActor.run {
            let allBooks = try modelContext.fetch(FetchDescriptor<BookGroup>())
            
            if let existingBook = allBooks.first(where: { $0.title == "默认手帐" && $0.deletedAt == nil }) {
                return existingBook
            }
            
            // 创建默认手帐
            let newBook = BookGroup(title: "默认手帐")
            modelContext.insert(newBook)
            try modelContext.save()
            return newBook
        }
    }

    private func processUserIntent(_ text: String) {
        if handleDirectPetSwitchMention(text) {
            return
        }

        if handleDirectFeedIntent(text) {
            return
        }

        if handleDirectPlayIntent(text) {
            return
        }

        if handleDirectUseIntent(text) {
            return
        }

        if shouldTreatAsOutfitPriceFollowUp(
            query: text,
            recentMessages: messages,
            dialogueTurns: 2
        ) {
            handleLastOutfitPriceQuery()
            return
        }

        if shouldTreatAsOutfitReplaceFollowUp(
            query: text,
            recentMessages: messages,
            dialogueTurns: 2
        ) {
            handleOutfitReplace(text)
            return
        }

        if shouldTreatAsOutfitAugmentFollowUp(
            query: text,
            recentMessages: messages,
            dialogueTurns: 2
        ) {
            handleOutfitAugment(text)
            return
        }

        if handleEmbeddedPanelIntent(text) {
            return
        }

        if handleThemeConversationIntent(text) {
            return
        }

        let decision = PetChatIntentRouter.decide(from: text)
        if decision.shouldDisambiguate {
            presentIntentDisambiguation(decision, rawText: text)
            return
        }

        routeIntent(decision.primaryIntent, rawText: text)
    }

    private func handleDirectFeedIntent(_ text: String) -> Bool {
        guard let intent = detectDirectFeedIntent(from: text) else {
            return false
        }

        let currentStatus = PetDataManager.shared.status
        guard let targetItem = resolveDirectFeedItem(intent: intent, status: currentStatus) else {
            messages.append(PetChatMessage(text: "我现在没找到能直接投喂的食物，先打开商店补点货吧。", isUser: false, isAIGenerated: true))
            return true
        }

        let inStock = currentStatus.inventory[targetItem.id, default: 0] > 0
        let result: PetItemCommandResult = inStock
            ? consumePetItemResult(itemId: targetItem.id)
            : purchasePetItemResult(itemId: targetItem.id, autoFeedWhenPossible: true)

        if let animation = result.feedAnimation {
            triggerFeedAnimation(animation)
        }
        messages.append(PetChatMessage(text: result.feedback, isUser: false, isAIGenerated: true))
        return true
    }

    private func handleDirectPlayIntent(_ text: String) -> Bool {
        guard let intent = detectDirectPlayIntent(from: text) else {
            return false
        }

        let currentStatus = PetDataManager.shared.status
        guard let targetItem = resolveDirectPlayItem(intent: intent, status: currentStatus) else {
            return false
        }

        if currentStatus.inventory[targetItem.id, default: 0] > 0 {
            let result = consumePetItemResult(itemId: targetItem.id)
            if let animation = result.feedAnimation {
                triggerFeedAnimation(animation)
            }
            messages.append(PetChatMessage(text: "我已经从背包里把\(targetItem.name)拿出来啦～\(result.feedback)", isUser: false, isAIGenerated: true))
        } else {
            let guidance = shopGuidanceText(for: targetItem)
            let widget = makeShopPanelWidget(status: currentStatus, feedback: guidance)
            messages.append(PetChatMessage(text: guidance, isUser: false, isAIGenerated: true, widgets: [widget]))
        }
        return true
    }

    private func handleDirectUseIntent(_ text: String) -> Bool {
        guard let intent = detectDirectUseIntent(from: text) else {
            return false
        }

        let currentStatus = PetDataManager.shared.status
        guard let targetItem = resolveDirectUseItem(intent: intent, status: currentStatus) else {
            return false
        }

        if targetItem.isToy {
            if currentStatus.inventory[targetItem.id, default: 0] > 0 {
                let result = consumePetItemResult(itemId: targetItem.id)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                messages.append(PetChatMessage(text: "我已经从背包里把\(targetItem.name)拿出来啦～\(result.feedback)", isUser: false, isAIGenerated: true))
            } else {
                let guidance = shopGuidanceText(for: targetItem)
                let widget = makeShopPanelWidget(status: currentStatus, feedback: guidance)
                messages.append(PetChatMessage(text: guidance, isUser: false, isAIGenerated: true, widgets: [widget]))
            }
            return true
        }

        let inStock = currentStatus.inventory[targetItem.id, default: 0] > 0
        let result: PetItemCommandResult = inStock
            ? consumePetItemResult(itemId: targetItem.id)
            : purchasePetItemResult(itemId: targetItem.id, autoFeedWhenPossible: true)

        if let animation = result.feedAnimation {
            triggerFeedAnimation(animation)
        }
        messages.append(PetChatMessage(text: result.feedback, isUser: false, isAIGenerated: true))
        return true
    }

    private func triggerFeedAnimation(_ payload: PetFeedAnimationPayload) {
        feedAnimationNonce += 1
        let currentNonce = feedAnimationNonce
        withAnimation(.easeOut(duration: 0.18)) {
            activeFeedAnimation = payload
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard currentNonce == feedAnimationNonce else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                activeFeedAnimation = nil
            }
        }
    }

    private func handleDirectPetSwitchMention(_ text: String) -> Bool {
        var status = PetDataManager.shared.status
        guard let target = PetChatIntentRouter.detectSwitchTarget(from: text, status: status) else {
            return false
        }

        let targetName = displayName(for: target, in: status)
        guard status.ownedPetIds.contains(target.id) else {
            openAdoptionSheetWithFeedback("\(targetName)还没领养，我先带你去领养界面把它接回家吧～")
            return true
        }

        if status.selectedPetId == target.id {
            messages.append(PetChatMessage(text: "现在已经是\(targetName)在陪你啦～", isUser: false, isAIGenerated: true))
            return true
        }

        status.selectedPetId = target.id
        status.intimacy = min(100, status.intimacy + 2)
        PetDataManager.shared.saveStatus(status)
        messages.append(PetChatMessage(text: "好哒，已切换到\(targetName)管家模式～", isUser: false, isAIGenerated: true))
        return true
    }

    private func openAdoptionSheetWithFeedback(_ text: String) {
        messages.append(PetChatMessage(text: text, isUser: false, isAIGenerated: true))
        presentAdoptionSheet()
    }

    private func routeIntent(_ intent: PetChatIntent, rawText: String) {
        switch intent {
        case .wardrobeStats:
            handleWardrobeStatistics()
        case .outfitSuggestion:
            handleOutfitSuggestion(rawText)
        case .lastOutfitPrice:
            handleLastOutfitPriceQuery()
        case .weatherGuidance:
            handleWeatherOutfitGuidance()
        case .search:
            handleSearch(rawText)
        case .depositPlan:
            handleDepositPlanQuery()
        case .currencyOverview:
            handleCurrencyOverview()
        case .petStatusOverview:
            handlePetStatusOverview()
        case .secondPetAdoption:
            handleSecondPetAdoptionIntent()
        case .switchPetCompanion:
            handleSwitchPetIntent()
        case .meowCoinTopUp:
            handleMeowCoinTopUpIntent()
        case .moodSupport, .generalChat:
            handleAIChat(rawText)
        }
    }

    private func presentIntentDisambiguation(_ decision: PetChatIntentRouter.IntentDecision, rawText: String) {
        var options = decision.candidates.prefix(3).map { candidate in
            return PetWidgetOption(
                title: candidate.intent.guideTitle,
                command: candidate.intent.guideCommand,
                icon: candidate.intent.guideIcon
            )
        }

        if options.count < 3 {
            options.append(
                PetWidgetOption(
                    title: "都不是，我换个问法",
                    command: "ask:我换个说法",
                    icon: "arrow.triangle.2.circlepath"
                )
            )
        }

        let widget = PetWidgetData(
            type: .quickOptions,
            title: "我听到你可能想做这几件事：",
            subtitle: rawText,
            options: options
        )

        let message = PetChatMessage(
            text: "我猜到你想做这些，点一个我马上办～",
            isUser: false,
            isAIGenerated: true,
            widgets: [widget]
        )
        messages.append(message)
    }

    private func handleCurrencyOverview() {
        handleCurrencyPanel(.all)
    }

    private func handleCurrencyPanel(_ kind: PetCurrencyPanelKind) {
        let status = PetDataManager.shared.status
        let widget = makeCurrencyPanelWidget(status: status, kind: kind)
        messages.append(
            PetChatMessage(
                text: kind == .all ? "我的小金库都在这儿啦～" : "这是我的\(kind.title)，给你看看呀～",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handlePetStatusOverview() {
        handlePetStatusPanel(.all)
    }

    private func handlePetStatusPanel(_ kind: PetStatusPanelKind) {
        handlePetStatusPanel(kind, sourceText: nil)
    }

    private func handlePetStatusPanel(_ kind: PetStatusPanelKind, sourceText: String?) {
        let status = PetDataManager.shared.status
        let contextualReply = contextualStatusReply(for: kind, status: status, sourceText: sourceText)
        let widget = makeStatusPanelWidget(
            status: status,
            kind: kind,
            feedback: contextualReply.subtitle
        )
        messages.append(
            PetChatMessage(
                text: contextualReply.message,
                isUser: false,
                imageName: petChatStatusExpressionImageName(status: status, kind: kind),
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleInventoryPanel() {
        let status = PetDataManager.shared.status
        let widget = makeInventoryPanelWidget(status: status)
        messages.append(
            PetChatMessage(
                text: "这是我的背包呀，点一下就能用，也可以直接拖过去～",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleShopPanel() {
        let status = PetDataManager.shared.status
        let widget = makeShopPanelWidget(status: status)
        messages.append(
            PetChatMessage(
                text: shopPanelIntroMessage(status: status),
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleMoneyCounterPanel(currency: CurrencyType = .rmb) {
        let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
        let widget = makeMoneyCounterWidget(totalValue: totalValue, currency: currency)
        messages.append(
            PetChatMessage(
                text: "来，我们就在这儿盘盘今天的小金库～",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleEmbeddedPanelIntent(_ text: String) -> Bool {
        guard let intent = detectEmbeddedPanelIntent(
            from: text,
            petName: PetDataManager.shared.status.displayName,
            recentMessages: messages
        ) else {
            return false
        }

        switch intent {
        case .currency(let kind):
            handleCurrencyPanel(kind)
        case .inventory:
            handleInventoryPanel()
        case .shop:
            handleShopPanel()
        case .moneyCounter(let currency):
            handleMoneyCounterPanel(currency: currency)
        case .divination:
            handleDivinationPanel()
        case .status(let kind):
            handlePetStatusPanel(kind, sourceText: text)
        }
        return true
    }

    private func handleDivinationPanel() {
        let widget = makeDivinationWidget()
        messages.append(
            PetChatMessage(
                text: "请签求好运～我把签筒抱来啦！",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func replaceWidgets(in messageID: UUID, with widgets: [PetWidgetData]) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].widgets = widgets
    }

    private func updateMessageImage(in messageID: UUID, imageName: String?) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].imageName = imageName
    }

    private func refreshPanel(for command: String, messageID: UUID, feedback: String? = nil) {
        let status = PetDataManager.shared.status
        if command.hasPrefix("use_item:") || command == "pet_inventory_panel" || command.hasPrefix("inventory:") {
            replaceWidgets(in: messageID, with: [makeInventoryPanelWidget(status: status, feedback: feedback)])
            return
        }
        if command == "pet_currency_panel" || command == "pet_currency_all" {
            replaceWidgets(in: messageID, with: [makeCurrencyPanelWidget(status: status, kind: .all, feedback: feedback)])
            return
        }
        if command == "pet_currency_meow" {
            replaceWidgets(in: messageID, with: [makeCurrencyPanelWidget(status: status, kind: .meowCoin, feedback: feedback)])
            return
        }
        if command == "pet_currency_fish" {
            replaceWidgets(in: messageID, with: [makeCurrencyPanelWidget(status: status, kind: .fishCoin, feedback: feedback)])
            return
        }
        if command == "pet_currency_bone" {
            replaceWidgets(in: messageID, with: [makeCurrencyPanelWidget(status: status, kind: .boneCoin, feedback: feedback)])
            return
        }
        if command.hasPrefix("buy_item:") || command == "pet_shop_panel" || command.hasPrefix("shop:") || command.hasPrefix("drag_shop_item:") {
            replaceWidgets(in: messageID, with: [makeShopPanelWidget(status: status, feedback: feedback)])
            return
        }
        if command == "pet_money_counter" || command == "open_money_counting" {
            let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
            replaceWidgets(in: messageID, with: [makeMoneyCounterWidget(totalValue: totalValue, currency: .rmb)])
            return
        }
        if command == "pet_money_counter_jpy" {
            let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
            replaceWidgets(in: messageID, with: [makeMoneyCounterWidget(totalValue: totalValue, currency: .jpy)])
            return
        }
        if command == "pet_money_counter_usd" {
            let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
            replaceWidgets(in: messageID, with: [makeMoneyCounterWidget(totalValue: totalValue, currency: .usd)])
            return
        }
        if command == "pet_divination_panel" {
            replaceWidgets(in: messageID, with: [makeDivinationWidget()])
            return
        }

        switch command {
        case "pet_status_panel", "pet_status_all":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .all, feedback: feedback)])
            updateMessageImage(in: messageID, imageName: petChatStatusExpressionImageName(status: status, kind: .all))
        case "pet_status_hunger":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hunger, feedback: feedback)])
            updateMessageImage(in: messageID, imageName: petChatStatusExpressionImageName(status: status, kind: .hunger))
        case "pet_status_hydration":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hydration, feedback: feedback)])
            updateMessageImage(in: messageID, imageName: petChatStatusExpressionImageName(status: status, kind: .hydration))
        case "pet_status_hygiene", "pet_clean_now":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hygiene, feedback: feedback)])
            updateMessageImage(in: messageID, imageName: petChatStatusExpressionImageName(status: status, kind: .hygiene))
        case "pet_status_mood":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .mood, feedback: feedback)])
            updateMessageImage(in: messageID, imageName: petChatStatusExpressionImageName(status: status, kind: .mood))
        case "pet_status_intimacy":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .intimacy, feedback: feedback)])
            updateMessageImage(in: messageID, imageName: petChatStatusExpressionImageName(status: status, kind: .intimacy))
        default:
            break
        }
    }

    private func handleSecondPetAdoptionIntent() {
        let status = PetDataManager.shared.status
        if status.ownedPetIds.count >= PetCharacter.allCases.count {
            messages.append(PetChatMessage(text: "你已经是双宝家庭啦，要不要我帮你切换宠物管家？", isUser: false, isAIGenerated: true))
            handleSwitchPetIntent()
            return
        }

        openAdoptionSheetWithFeedback("好哒，给你打开领养界面啦～")
    }

    private func handleSwitchPetIntent() {
        let status = PetDataManager.shared.status
        let ownedPets = PetCharacter.allCases.filter { status.ownedPetIds.contains($0.id) }
        guard ownedPets.count >= 2 else {
            openAdoptionSheetWithFeedback("想换新伙伴的话，我先带你去领养界面挑一只呀～")
            return
        }

        let options = ownedPets.prefix(3).map { pet in
            return PetWidgetOption(
                title: "切换到\(pet.displayName)",
                command: "switch_pet:\(pet.id)",
                icon: pet.quickOptionIconName
            )
        }

        let widget = PetWidgetData(
            type: .quickOptions,
            title: "选择你要切换的萌宠管家：",
            options: options
        )
        messages.append(
            PetChatMessage(
                text: "来，点一下就切换。",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleMeowCoinTopUpIntent() {
        let widget = PetWidgetData(
            type: .quickOptions,
            title: "你是想充值喵币吗？",
            options: [
                PetWidgetOption(title: "打开喵币充值", command: "open_meow_store", icon: "cart.fill"),
                PetWidgetOption(title: "看看三种货币余额", command: "pet_currency_panel", icon: "wallet.pass.fill"),
                PetWidgetOption(title: "先不充，继续聊", command: "mood_support", icon: "face.smiling.fill")
            ]
        )
        messages.append(
            PetChatMessage(
                text: "没问题，我这就带你去充喵币～",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handlePetCleanNow(messageID: UUID) {
        let result = cleanPetStatusNow()
        switch result.fundingDestination {
        case .meowCoinStore:
            showingMeowCoinStore = true
        case .currencyExchange(let direction):
            preferredExchangeDirection = direction
            showingCurrencyExchangeSheet = true
        case nil:
            break
        }
        refreshPanel(for: "pet_clean_now", messageID: messageID, feedback: result.feedback)
    }

    private func handleThemeConversationIntent(_ text: String) -> Bool {
        guard let result = PetThemeConversationEngine.handleIfNeeded(userText: text, themeManager: themeManager) else {
            return false
        }
        if result.shouldAnimate {
            triggerThemeSwitchAnimation()
        }
        let reply = PetChatMessage(
            text: localizedCatchphraseText(result.reply),
            isUser: false,
            isAIGenerated: true,
            widgets: result.widgets.isEmpty ? nil : result.widgets
        )
        messages.append(reply)
        return true
    }

    private func handleThemeQuickAction(_ command: String) -> Bool {
        guard let result = PetThemeConversationEngine.handleQuickAction(command: command, themeManager: themeManager) else {
            return false
        }

        if result.shouldAnimate {
            triggerThemeSwitchAnimation()
        }

        messages.append(
            PetChatMessage(
                text: localizedCatchphraseText(result.reply),
                isUser: false,
                isAIGenerated: true,
                widgets: result.widgets.isEmpty ? nil : result.widgets
            )
        )
        return true
    }

    private func triggerThemeSwitchAnimation() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showingThemeSwitchOverlay = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.28)) {
                showingThemeSwitchOverlay = false
            }
        }
    }

    private func showPurchaseSuccessToast(itemName: String) {
        purchaseToastHideWorkItem?.cancel()
        purchaseSuccessMessage = "\(itemName)已收进我的背包"

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            showingPurchaseSuccessToast = true
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let hideWorkItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                showingPurchaseSuccessToast = false
            }
        }
        purchaseToastHideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: hideWorkItem)
    }

    private func canAffordShopItem(_ item: PetItemDefinition) -> Bool {
        let status = PetDataManager.shared.status
        let finalPrice = VIPManager.shared.petShopPrice(for: item.price)
        switch item.petCurrency {
        case .meowCoin:
            return status.meowCoin >= finalPrice
        case .fishCoin:
            return status.fishCoin >= finalPrice
        case .boneCoin:
            return status.boneCoin >= finalPrice
        }
    }

    private func presentFundingPromptIfNeeded(for itemId: String) {
        guard let item = PetConfigManager.shared.getItem(byId: itemId) else { return }
        guard !canAffordShopItem(item) else { return }
        adoptionViewModel.presentFundingPrompt(for: item.petCurrency, itemName: item.name)
    }

    private func handleFundingPromptPrimaryAction() {
        guard let destination = adoptionViewModel.presentedFundingPrompt?.destination else { return }
        adoptionViewModel.dismissFundingPrompt()

        switch destination {
        case .meowCoinStore:
            showingMeowCoinStore = true
        case .currencyExchange(let direction):
            preferredExchangeDirection = direction
            showingCurrencyExchangeSheet = true
        }
    }

    private func handleRenamePetIntent() {
        var status = PetDataManager.shared.status
        guard !status.ownedPetIds.isEmpty, status.selectedPetId != nil else {
            messages.append(PetChatMessage(text: "先领养一个萌宠，再来改名喔～", isUser: false, isAIGenerated: true))
            return
        }

        if (status.inventory["renameCard"] ?? 0) <= 0 {
            let renameCost = PetConfigManager.shared.getItem(byId: "renameCard")?.price ?? 10
            guard status.meowCoin >= renameCost else {
                showingMeowCoinStore = true
                messages.append(PetChatMessage(text: "改名项圈需要 \(renameCost) 喵币，你现在喵币不够，先带你去 Apple 原生充值～", isUser: false, isAIGenerated: true))
                return
            }

            _ = StoreManager.spendMeowCoins(renameCost, in: &status)
            status.inventory["renameCard", default: 0] += 1
            PetDataManager.shared.saveStatus(status)
            messages.append(PetChatMessage(text: "已帮你买好改名项圈，来起个新名字吧～", isUser: false, isAIGenerated: true))
        }

        renameInputText = status.displayName
        showingRenameAlert = true
    }

    private func commitPetRename() {
        let trimmed = renameInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var status = PetDataManager.shared.status
        guard let selectedPetId = status.selectedPetId else { return }
        guard (status.inventory["renameCard"] ?? 0) > 0 else {
            handleRenamePetIntent()
            return
        }

        let cleanName = trimmed
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")

        status.inventory["renameCard", default: 0] -= 1
        status.petNames[selectedPetId] = cleanName
        PetDataManager.shared.saveStatus(status)
        configureAIService()

        messages.append(PetChatMessage(text: "改名成功！我现在叫「\(cleanName)」～", isUser: false, isAIGenerated: true))
    }

    private func legacyHandleWidgetAction(_ option: PetWidgetOption, messageID: UUID) {
        if handleInlineYarnBallShortcut(option, messageID: messageID) {
            return
        }

        if handleThemeQuickAction(option.command) {
            return
        }

        switch option.command {
        case "outfit_suggest":
            handleOutfitSuggestion("帮我搭配一套")
        case "weather_guidance":
            handleWeatherOutfitGuidance()
        case "search_prompt":
            handleWidgetSearchPrompt(option)
        case "mood_support":
            handleAIChat("我有点累，想被温柔安慰一下，也想听听今天适合什么穿搭。")
        case "pet_currency_panel":
            refreshPanel(for: "pet_currency_panel", messageID: messageID)
        case "pet_currency_all":
            refreshPanel(for: "pet_currency_all", messageID: messageID)
        case "pet_currency_meow":
            refreshPanel(for: "pet_currency_meow", messageID: messageID)
        case "pet_currency_fish":
            refreshPanel(for: "pet_currency_fish", messageID: messageID)
        case "pet_currency_bone":
            refreshPanel(for: "pet_currency_bone", messageID: messageID)
        case "pet_currency_action_meow":
            showingMeowCoinStore = true
        case "pet_currency_action_fish":
            preferredExchangeDirection = .fishToBone
            showingCurrencyExchangeSheet = true
        case "pet_currency_action_bone":
            preferredExchangeDirection = .boneToFish
            showingCurrencyExchangeSheet = true
        case "pet_status_panel":
            refreshPanel(for: "pet_status_panel", messageID: messageID)
        case "pet_status_all":
            refreshPanel(for: "pet_status_all", messageID: messageID)
        case "pet_status_hunger":
            refreshPanel(for: "pet_status_hunger", messageID: messageID)
        case "pet_status_hydration":
            refreshPanel(for: "pet_status_hydration", messageID: messageID)
        case "pet_status_hygiene":
            refreshPanel(for: "pet_status_hygiene", messageID: messageID)
        case "pet_status_mood":
            refreshPanel(for: "pet_status_mood", messageID: messageID)
        case "pet_status_intimacy":
            refreshPanel(for: "pet_status_intimacy", messageID: messageID)
        case "pet_inventory_panel":
            refreshPanel(for: "pet_inventory_panel", messageID: messageID)
        case "pet_shop_panel":
            refreshPanel(for: "pet_shop_panel", messageID: messageID)
        case "pet_money_counter":
            refreshPanel(for: "pet_money_counter", messageID: messageID)
        case "pet_divination_panel":
            refreshPanel(for: "pet_divination_panel", messageID: messageID)
        case "pet_second_adopt":
            handleSecondPetAdoptionIntent()
        case "pet_switch":
            handleSwitchPetIntent()
        case "pet_rename":
            handleRenamePetIntent()
        case "pet_topup":
            handleMeowCoinTopUpIntent()
        case "pet_clean_now":
            handlePetCleanNow(messageID: messageID)
        case "open_meow_store":
            showingMeowCoinStore = true
        case "open_vip_center":
            showingVIPCenter = true
        case "open_money_counting":
            refreshPanel(for: "open_money_counting", messageID: messageID)
        case let cmd where cmd.hasPrefix("weather_guidance:"):
            let styleParam = String(cmd.dropFirst("weather_guidance:".count))
            let stylePreference: String?
            switch styleParam {
            case "rain":
                stylePreference = "防雨 稳妥"
            case "sweet":
                stylePreference = "甜美"
            default:
                stylePreference = nil
            }
            handleWeatherOutfitGuidance(stylePreference: stylePreference)
        default:
            if option.command.hasPrefix("use_item:") {
                let rawId = String(option.command.dropFirst("use_item:".count))
                let result = consumePetItemResult(itemId: rawId)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("buy_item:") {
                let rawId = String(option.command.dropFirst("buy_item:".count))
                presentFundingPromptIfNeeded(for: rawId)
                let beforeCount = PetDataManager.shared.status.inventory[rawId, default: 0]
                let result = purchasePetItemResult(itemId: rawId, autoFeedWhenPossible: false)
                let afterCount = PetDataManager.shared.status.inventory[rawId, default: 0]
                if afterCount > beforeCount {
                    let itemName = PetConfigManager.shared.getItem(byId: rawId)?.name ?? "道具"
                    showPurchaseSuccessToast(itemName: itemName)
                }
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("drag_shop_item:") {
                let rawId = String(option.command.dropFirst("drag_shop_item:".count))
                presentFundingPromptIfNeeded(for: rawId)
                let result = purchasePetItemResult(itemId: rawId, autoFeedWhenPossible: true)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: "pet_shop_panel", messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("inventory:") {
                let rawId = String(option.command.dropFirst("inventory:".count))
                let result = consumePetItemResult(itemId: rawId)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("shop:") {
                let rawId = String(option.command.dropFirst("shop:".count))
                presentFundingPromptIfNeeded(for: rawId)
                let result = purchasePetItemResult(itemId: rawId, autoFeedWhenPossible: true)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else
            if option.command.hasPrefix("switch_pet:") {
                let rawId = String(option.command.dropFirst("switch_pet:".count))
                if let pet = PetCharacter(rawValue: rawId) {
                    var status = PetDataManager.shared.status
                    guard status.ownedPetIds.contains(pet.id) else {
                        openAdoptionSheetWithFeedback("\(pet.displayName)还没领养，我先带你去领养界面把它接回家吧～")
                        return
                    }
                    status.selectedPetId = pet.id
                    status.intimacy = min(100, status.intimacy + 2)
                    PetDataManager.shared.saveStatus(status)
                    messages.append(PetChatMessage(text: "已切换到\(pet.displayName)管家模式，继续陪你～", isUser: false, isAIGenerated: true))
                }
            } else if option.command.hasPrefix("adopt_pet:") {
                let rawId = String(option.command.dropFirst("adopt_pet:".count))
                if let pet = PetCharacter(rawValue: rawId) {
                    var status = PetDataManager.shared.status
                    if status.ownedPetIds.contains(pet.id) {
                        status.selectedPetId = pet.id
                        PetDataManager.shared.saveStatus(status)
                        messages.append(PetChatMessage(text: "\(pet.displayName)已经在家里啦，已帮你切过去～", isUser: false, isAIGenerated: true))
                        return
                    }
                    messages.append(PetChatMessage(text: "这就打开领养界面，选中后就能带\(pet.displayName)回家啦～", isUser: false, isAIGenerated: true))
                    presentAdoptionSheet()
                }
            } else if option.command.hasPrefix("ask:") {
                let query = String(option.command.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    processUserIntent(query)
                }
            }
        }
    }

    private func guardPremiumFeature(_ feature: PetChatPremiumFeature) -> Bool {
        guard !VIPManager.shared.isVIP else { return false }
        messages.append(
            PetChatVIPAccessSupport.upgradeMessage(
                for: feature,
                petName: PetDataManager.shared.status.displayName
            )
        )
        return true
    }

    private func handleWidgetSearchPrompt(_ option: PetWidgetOption) {
        let query = widgetSearchQuery(for: option)
        guard !query.isEmpty else { return }

        let userMessage = PetChatMessage(text: query, isUser: true)
        messages.append(userMessage)
        handleSearch(query)
    }

    private func widgetSearchQuery(for option: PetWidgetOption) -> String {
        let cleanedTitle = option.title
            .replacingOccurrences(
                of: #"^[A-Za-z]\s*[\.、]\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isDirectSearchTitle(cleanedTitle) {
            return cleanedTitle
        }

        return WardrobeContextManager.shared.defaultSearchPrompt(clothings: clothings)
    }

    private func isDirectSearchTitle(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }

        let directSearchHints = [
            "帮我找", "我想找", "找", "搜索", "查一下", "查查",
            "开衫", "外套", "罩衫", "披肩", "上衣", "内搭", "短袖", "长袖", "马甲", "衬衫"
        ]
        return directSearchHints.contains { title.contains($0) }
    }

    private func handleInlineYarnBallShortcut(_ option: PetWidgetOption, messageID: UUID) -> Bool {
        let structuredPrefixes = ["use_item:", "inventory:", "buy_item:", "shop:", "drag_shop_item:"]
        if structuredPrefixes.contains(where: { option.command.hasPrefix($0) }) {
            return false
        }

        let normalized = "\(option.title) \(option.command)".lowercased()
        let containsYarnBall = normalized.contains("毛线球")
            || normalized.contains("线球")
            || normalized.contains("yarnball")
            || normalized.contains("yarn ball")
        guard containsYarnBall,
              let yarnBall = PetConfigManager.shared.getItem(byId: "yarnBall") else {
            return false
        }

        let status = PetDataManager.shared.status
        if status.inventory[yarnBall.id, default: 0] > 0 {
            let result = consumePetItemResult(itemId: yarnBall.id)
            if let animation = result.feedAnimation {
                triggerFeedAnimation(animation)
            }
            refreshPanel(
                for: "pet_inventory_panel",
                messageID: messageID,
                feedback: "我已经从背包里把毛线球拿出来啦～\(result.feedback)"
            )
        } else {
            refreshPanel(
                for: "pet_shop_panel",
                messageID: messageID,
                feedback: shopGuidanceText(for: yarnBall)
            )
        }
        return true
    }

    private func handleWardrobeStatistics() {
        isThinking = true

        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
        let mostExpensiveItem = clothings.max(by: { $0.inventoryTotalPrice < $1.inventoryTotalPrice })
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }
        
        let stats = WardrobeStats(
            totalCount: totalCount,
            totalValue: totalValue,
            mostExpensiveItem: mostExpensiveItem,
            depositPlanCount: depositPlans.count,
            totalDeposit: totalDeposit,
            totalBalance: totalBalance
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isThinking = false
            
            let responseText: String
            if totalCount == 0 {
                responseText = localizedCatchphraseText("喵？你的衣橱还是空的耶，快去添加几件漂亮裙子吧~")
            } else {
                responseText = "（翻看着小账本）主人，你的衣橱里有\(totalCount)件宝贝，总价值\(NSDecimalNumber(decimal: totalValue).stringValue)元呢！"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .statistics,
                statistics: stats
            )
            messages.append(message)
        }
    }
    
    private func handleColorMatch() {
        isThinking = true
        
        let colorRecommendations = [
            ColorRecommendation(
                primaryColor: "粉色",
                secondaryColor: "白色",
                accentColor: "米色",
                description: "甜美优雅",
                reasoning: "粉色系是Lo裙的经典配色，白色和米色的点缀能让整体更加温柔~"
            ),
            ColorRecommendation(
                primaryColor: "蓝色",
                secondaryColor: "白色",
                accentColor: "银色",
                description: "清新梦幻",
                reasoning: "蓝色系像天空一样清新，适合夏日穿搭，银色点缀增添梦幻感~"
            ),
            ColorRecommendation(
                primaryColor: "紫色",
                secondaryColor: "黑色",
                accentColor: "金色",
                description: "神秘高贵",
                reasoning: "紫色与黑色的搭配神秘又高贵，金色点缀更显华丽~"
            )
        ]
        
        let randomRec = colorRecommendations.randomElement()!
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isThinking = false
            
            let message = PetChatMessage(
                text: "（歪头思考）主人今天想走什么风格呢？我给你搭配了一套~",
                isUser: false,
                type: .colorMatch,
                colorRecommendation: randomRec
            )
            messages.append(message)
        }
    }
    
    private func handleSearch(_ query: String) {
        isThinking = true
        let resolution = WardrobeContextManager.shared.resolveSearch(query: query, clothings: clothings)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if resolution.results.isEmpty {
                if resolution.normalizedQuery.isEmpty {
                    responseText = localizedCatchphraseText("我先把你衣橱里的标签和类型记住啦～你可以直接试试这句：\(resolution.suggestedPrompt)")
                } else {
                    let learnedTerms = resolution.matchedTerms.joined(separator: "、")
                    responseText = localizedCatchphraseText(
                        learnedTerms.isEmpty
                        ? "喵… 没找到完全对得上的单品。你可以试试这样问我：\(resolution.suggestedPrompt)"
                        : "喵… 没找到完全同名的，但我已经按你常用的词「\(learnedTerms)」学着找了。你可以试试这样问我：\(resolution.suggestedPrompt)"
                    )
                }
            } else {
                let termSuffix = resolution.matchedTerms.isEmpty ? "" : "，还顺着你常用的词「\(resolution.matchedTerms.joined(separator: "、"))」一起找了"
                responseText = "（眼睛发亮）找到\(resolution.results.count)件相关的单品\(termSuffix)，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: resolution.results.isEmpty ? nil : resolution.results
            )
            messages.append(message)
        }
    }
    
    private func handleDepositPlanQuery() {
        isThinking = true
        
        // 计算完整的衣橱统计数据
        let totalCount = clothings.reduce(0) { $0 + $1.stock }
        let totalValue = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
        let depositPlans = clothings.filter { $0.isDepositPlan }
        let totalDeposit = depositPlans.reduce(Decimal(0)) { $0 + ($1.deposit * Decimal($1.stock)) }
        let totalBalance = depositPlans.reduce(Decimal(0)) { $0 + ($1.balance * Decimal($1.stock)) }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if depositPlans.isEmpty {
                responseText = localizedCatchphraseText("喵~ 目前没有待补款的裙子呢，主人的钱包可以休息一下啦！")
            } else {
                responseText = localizedCatchphraseText("（认真脸）主人还有\(depositPlans.count)款裙子要补尾款，一共要准备\(NSDecimalNumber(decimal: totalBalance).stringValue)元喵~")
            }
            
            let stats = WardrobeStats(
                totalCount: totalCount,
                totalValue: totalValue,
                mostExpensiveItem: nil,
                depositPlanCount: depositPlans.count,
                totalDeposit: totalDeposit,
                totalBalance: totalBalance
            )
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: depositPlans.isEmpty ? .text : .statistics,
                statistics: depositPlans.isEmpty ? nil : stats
            )
            messages.append(message)
        }
    }

    private func handleLastOutfitPriceQuery() {
        let role = activePetRole()
        let text: String
        if let suggestion = latestRecentOutfitSuggestion(in: messages, dialogueTurns: 2),
           let summary = buildOutfitPriceSummary(clothings: suggestion.clothings) {
            text = "（翻出刚刚的推荐清单）\(summary)～你要我顺便按这个价位再补一套吗？"
        } else if let summary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: role) {
            text = "（翻出小账本）\(summary)～你要我顺便按这个价位再补一套吗？"
        } else {
            text = localizedCatchphraseText("（挠挠耳朵）我这边还没记到最近一套搭配价格喵，先让我给你搭一套，再帮你精确算总价吧。")
        }

        let message = PetChatMessage(
            text: text,
            isUser: false
        )
        messages.append(message)
    }

    private func handleOutfitAugment(_ text: String) {
        if guardPremiumFeature(.outfitSuggestion) {
            return
        }

        guard let latestSuggestion = latestRecentOutfitSuggestion(in: messages, dialogueTurns: 2) else {
            handleOutfitSuggestion(text)
            return
        }

        isThinking = true

        Task {
            do {
                let weather = await fetchCurrentWeather()
                let (updatedClothings, responseText) = try await withTimeout(seconds: 12) {
                    try OutfitSuggestionService.shared.extendOutfit(
                        baseSuggestion: latestSuggestion,
                        query: text,
                        clothings: self.clothings,
                        weather: weather
                    )
                }

                await MainActor.run {
                    isThinking = false
                    let suggestionData = OutfitSuggestionData(
                        clothings: updatedClothings,
                        description: responseText,
                        style: latestSuggestion.style,
                        occasion: latestSuggestion.occasion,
                        layoutInfos: nil
                    )
                    PetConversationMemoryStore.shared.recordOutfitSelection(
                        clothings: updatedClothings,
                        role: activePetRole()
                    )

                    messages.append(
                        PetChatMessage(
                            text: responseText,
                            isUser: false,
                            type: .outfitSuggestion,
                            isAIGenerated: true,
                            outfitSuggestion: suggestionData,
                            widgets: [buildOutfitContinuationWidget(for: suggestionData)]
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    isThinking = false
                    messages.append(
                        PetChatMessage(
                            text: localizedCatchphraseText("（翻翻衣橱）这套里我暂时没找到更合适的可加单品喵，要不要直接说想加上衣、轻薄开衫、小物、鞋子，或者我重新给你搭一套？"),
                            isUser: false,
                            isAIGenerated: true
                        )
                    )
                }
            }
        }
    }

    private func handleOutfitReplace(_ text: String) {
        if guardPremiumFeature(.outfitSuggestion) {
            return
        }

        guard let latestSuggestion = latestRecentOutfitSuggestion(in: messages, dialogueTurns: 2) else {
            handleOutfitSuggestion(text)
            return
        }

        isThinking = true

        Task {
            do {
                let weather = await fetchCurrentWeather()
                let (updatedClothings, responseText) = try await withTimeout(seconds: 12) {
                    try OutfitSuggestionService.shared.replaceOutfitItem(
                        baseSuggestion: latestSuggestion,
                        query: text,
                        clothings: self.clothings,
                        weather: weather
                    )
                }

                await MainActor.run {
                    isThinking = false
                    let suggestionData = OutfitSuggestionData(
                        clothings: updatedClothings,
                        description: responseText,
                        style: latestSuggestion.style,
                        occasion: latestSuggestion.occasion,
                        layoutInfos: nil
                    )
                    PetConversationMemoryStore.shared.recordOutfitSelection(
                        clothings: updatedClothings,
                        role: activePetRole()
                    )

                    messages.append(
                        PetChatMessage(
                            text: responseText,
                            isUser: false,
                            type: .outfitSuggestion,
                            isAIGenerated: true,
                            outfitSuggestion: suggestionData,
                            widgets: [buildOutfitContinuationWidget(for: suggestionData)]
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    isThinking = false
                    messages.append(
                        PetChatMessage(
                            text: localizedCatchphraseText("（翻翻衣橱）这套里我暂时没找到更合适的可替换单品喵。你可以直接说“换主裙/换上衣/换轻薄开衫/换鞋子/换浅色小物”，我继续帮你细调~"),
                            isUser: false,
                            isAIGenerated: true
                        )
                    )
                }
            }
        }
    }
    
    private func handleWeatherOutfitGuidance(stylePreference: String? = nil) {
        if guardPremiumFeature(.weatherGuidance) {
            return
        }

        isThinking = true

        Task { @MainActor in
            let weather = await fetchCurrentWeather()
            let selection = PetChatGuidanceEngine.pickWeatherOutfitItems(
                from: clothings,
                weather: weather,
                stylePreference: stylePreference
            )
            let baseAdvice = PetChatGuidanceEngine.buildWeatherAdvice(weather: weather, selection: selection)
            let responseText: String
            if let stylePreference = stylePreference, stylePreference.contains("甜美") {
                responseText = "好哒~我会按甜美方向，再结合天气稳稳地帮你挑。\n\(baseAdvice)"
            } else if let stylePreference = stylePreference, stylePreference.contains("防雨") {
                responseText = "没问题~我会优先挑更稳妥防雨的单品。\n\(baseAdvice)"
            } else {
                responseText = baseAdvice
            }
            let items = selection.combinedItems
            let widgets = PetChatWidgetFactory.weatherGuidanceWidgets(weather: weather, selection: selection)

            isThinking = false
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: items.isEmpty ? .text : .searchResults,
                searchResults: items.isEmpty ? nil : items,
                widgets: widgets
            )
            messages.append(message)
        }
    }
    
    @MainActor
    private func fetchCurrentWeather() async -> WeatherData? {
        let locationService = LocationService.shared
        let weatherService = WeatherService.shared
        
        if let location = await locationService.getCurrentLocation() {
            let cityInfo = await locationService.reverseGeocode(location)
            let city = cityInfo?.city ?? locationService.currentCity
            return await weatherService.fetchWeather(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                city: city == "未知城市" ? "当前位置" : city
            )
        }
        
        let cachedCity = locationService.currentCity
        if cachedCity != "未知城市" {
            return await weatherService.fetchWeatherForCity(cachedCity)
        }

        return weatherService.currentWeather
    }

    private func promptWealthCountingNavigation() {
        let widget = PetWidgetData(
            type: .quickOptions,
            title: "要跳转到「来财」数钱页吗？",
            options: [
                PetWidgetOption(title: "现在去数钞票", command: "open_money_counting", icon: "yensign.circle.fill"),
                PetWidgetOption(title: "先留在聊天里", command: "mood_support", icon: "bubble.left.and.bubble.right.fill"),
                PetWidgetOption(title: "先看看我的货币", command: "pet_currency_panel", icon: "wallet.pass.fill")
            ]
        )
        messages.append(
            PetChatMessage(
                text: "这个场景需要跳转，我先征求你确认～",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }
    
    private func navigateToWealthCounting() {
        let message = PetChatMessage(
            text: "走吧，我们去「来财」数钞票放松一下～",
            isUser: false
        )
        messages.append(message)
        // 直接跳转到来财的数钱页签
        TabNavigationManager.shared.navigate(to: .smallWorld(.wealth(.moneyCounting)))
    }
    
    private func handleAIChat(_ text: String) {
        if guardPremiumFeature(.remoteChat) {
            return
        }

        isThinking = true

        Task {
            let detectedIntent = PetChatIntentRouter.decide(from: text).primaryIntent
            let wardrobeContext = WardrobeContextManager.shared.buildWardrobeContextBlockIfNeeded(
                query: text,
                clothings: clothings,
                module: detectedIntent.module,
                maxItems: wardrobeContextBudget(for: detectedIntent)
            )
            let persona = activePetPersonaProfile(petName: petAI.petName)
            let recentAssistantReplies = PetGenerativePromptBuilder.recentAssistantReplies(
                from: messages,
                isUser: \.isUser,
                text: \.text
            )
            let prompt = PetGenerativePromptBuilder.buildPrompt(
                input: .init(
                    userQuery: text,
                    wardrobeContextBlock: wardrobeContext,
                    persona: persona,
                    module: detectedIntent.module,
                    recentAssistantReplies: recentAssistantReplies
                )
            )
            let response = await petAI.sendMessage(
                prompt,
                displayText: text,
                enableVoice: false
            )
            let renderContent = PetGenerativeUIParser.buildRenderableContent(
                rawText: response.rawText ?? response.text,
                fallbackDisplayText: response.text,
                userQuery: text
            )

            await MainActor.run {
                isThinking = false

                let message = PetChatMessage(
                    text: renderContent.text,
                    isUser: false,
                    imageName: response.imageName,
                    isAIGenerated: true,
                    widgets: renderContent.widgets
                )
                messages.append(message)
            }
        }
    }

    // MARK: - 搭配建议处理（Legacy版本）

    /// 处理搭配建议请求
    private func handleOutfitSuggestion(_ text: String) {
        if guardPremiumFeature(.outfitSuggestion) {
            return
        }

        // 检查是否有足够的抠图
        let availableCount = OutfitSuggestionService.shared.availableCutoutCount(context: modelContext)
        guard availableCount >= 2 else {
            let message = PetChatMessage(
                text: localizedCatchphraseText("（歪头）主人衣橱里的抠图还不够呢，至少需要2件单品才能搭配喵~ 快去生成一些抠图吧！"),
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                let weather = await fetchCurrentWeather()
                // 添加超时机制
                let (selectedClothings, responseText, style, occasion) = try await withTimeout(seconds: 30) {
                    try await OutfitSuggestionService.shared.processOutfitRequest(
                        query: text,
                        clothings: self.clothings,
                        context: self.modelContext,
                        weather: weather
                    )
                }

                await MainActor.run {
                    isThinking = false
                    PetConversationMemoryStore.shared.recordOutfitSelection(
                        clothings: selectedClothings,
                        role: activePetRole()
                    )

                    let suggestionData = OutfitSuggestionData(
                        clothings: selectedClothings,
                        description: localizedCatchphraseText(responseText),
                        style: style,
                        occasion: occasion,
                        layoutInfos: nil
                    )

                    let message = PetChatMessage(
                        text: localizedCatchphraseText(responseText),
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData,
                        widgets: [buildOutfitContinuationWidget(for: suggestionData)]
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: localizedCatchphraseText("（抱住你）我刚刚想太久啦喵…你可以先给我“场景+风格”短句，或换稳定网络再试一次，我会乖乖继续帮你配~"),
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false

                    let errorMessage = localizedCatchphraseText((error as? OutfitSuggestionError)?.errorDescription ?? "搭配生成失败，请重试喵~")
                    let message = PetChatMessage(
                        text: "（挠头）\(errorMessage)",
                        isUser: false
                    )
                    messages.append(message)
                }
            }
        }
    }

    /// 快速创建搭配（无需AI）
    private func createQuickOutfit(style: String, occasion: String) {
        if guardPremiumFeature(.outfitSuggestion) {
            return
        }

        guard clothings.count >= 2 else {
            let message = PetChatMessage(
                text: localizedCatchphraseText("（歪头）主人衣橱里的裙子还不够呢，至少需要2件单品才能搭配喵~"),
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                let weather = await fetchCurrentWeather()
                // 添加超时机制
                let selectedClothings = try await withTimeout(seconds: 15) {
                    try await OutfitSuggestionService.shared.createQuickOutfit(
                        style: style,
                        occasion: occasion,
                        clothings: self.clothings,
                        context: self.modelContext,
                        weather: weather
                    )
                }

                await MainActor.run {
                    isThinking = false
                    PetConversationMemoryStore.shared.recordOutfitSelection(
                        clothings: selectedClothings,
                        role: activePetRole()
                    )

                    let suggestionData = OutfitSuggestionData(
                        clothings: selectedClothings,
                        description: "为你准备了一套\(style)风\(occasion)搭配~",
                        style: style,
                        occasion: occasion,
                        layoutInfos: nil
                    )

                    let message = PetChatMessage(
                        text: localizedCatchphraseText("（眼睛发亮）为你准备了一套\(style)风\(occasion)搭配，快来看看吧喵~"),
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData,
                        widgets: [buildOutfitContinuationWidget(for: suggestionData)]
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: localizedCatchphraseText("（抱住你）我刚刚想太久啦喵…你可以先给我“场景+风格”短句，或换稳定网络再试一次，我会乖乖继续帮你配~"),
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（挠头）搭配生成失败：\(error.localizedDescription)",
                        isUser: false
                    )
                    messages.append(message)
                }
            }
        }
    }
}
