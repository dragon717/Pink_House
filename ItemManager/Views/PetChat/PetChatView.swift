//
//  PetChatView.swift
//  ItemManager
//
//  萌宠对话视图 - 整合AI对话、衣橱统计、查询、搭配色、搜索功能
//

import SwiftUI
import SwiftData
import CoreLocation

// MARK: - 萌宠对话主视图
@available(iOS 18.0, *)
struct PetChatView: View {
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
    @State private var selectedClothing: Clothing?
    @State private var navigateToDetail = false
    // iOS26 搜索栏展开状态（用于控制常用菜单长按交互）
    @State private var isSearchPresented = false
    @State private var hasEnteredOnce = false
    @State private var showingHistorySearch = false
    @State private var showingMeowCoinStore = false
    @State private var showingCurrencyExchangeSheet = false
    @State private var preferredExchangeDirection: PetCurrencyExchangeDirection = .fishToBone

    // 搭配建议相关状态
    @State private var selectedOutfitClothings: [Clothing] = []
    @State private var showingOutfitStickerFlow = false
    
    // 保存成功提示状态
    @State private var showingSaveSuccessToast = false
    @State private var isSavingOutfit = false
    @State private var showingThemeSwitchOverlay = false
    @State private var activeFeedAnimation: PetFeedAnimationPayload?
    @State private var feedAnimationNonce: Int = 0

    // 每日问候管理器
    @StateObject private var greetingManager = DailyGreetingManager.shared
    
    // 搜索框提示文字，使用用户起的宠物名字
    private var searchPrompt: String {
        let petName = PetDataManager.shared.status.displayName
        return "和\(petName)对话、搜索裙子..."
    }

    private var guideSearchBarCaptureAnchor: some View {
        GeometryReader { proxy in
            let searchFrame = CGRect(
                x: 16,
                y: max(proxy.safeAreaInsets.top + 56, 94),
                width: proxy.size.width - 32,
                height: 44
            )

            Color.clear
                .frame(width: searchFrame.width, height: searchFrame.height)
                .position(x: searchFrame.midX, y: searchFrame.midY)
                .captureGuideTarget(.petChatSearchBar)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景 - 使用 LiquidBackground，不使用魔法配色/客制化配色的背景色
                LiquidBackground()
                    .ignoresSafeArea()

                // 聊天记录 - 使用 overlay 放置悬浮按钮
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { message in
                                messageBubble(for: message)
                            }
                            
                            if isThinking {
                                HStack {
                                    ModernAIThinkingView()
                                        .id("thinking")
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: messages.count) { _ in
                        if let lastId = messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isThinking) { _ in
                        if isThinking {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(petAI.petName)的悄悄话")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPrompt
            )
            .onSubmit(of: .search) {
                if !searchText.isEmpty {
                    sendMessageFromSearchBar()
                }
            }
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
            .sheet(isPresented: $showingCurrencyExchangeSheet) {
                PetCurrencyExchangeSheet(preferredDirection: preferredExchangeDirection)
                    .presentationDetents([.medium])
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

                    if let payload = activeFeedAnimation {
                        PetFeedAnimationOverlay(payload: payload)
                            .transition(.opacity)
                            .zIndex(110)
                    }
                }
            }
            .overlay(alignment: .top) {
                guideSearchBarCaptureAnchor
            }
            .onAppear {
                if messages.isEmpty {
                    loadInitialGreeting()
                }
                ensureGuideEmbeddedOptionMessageIfNeeded()
                // 配置 AI 服务
                configureAIService()
                // 首次进入萌宠对话页面时，自动展开搜索栏
                if !hasEnteredOnce {
                    hasEnteredOnce = true
                    withAnimation {
                        isSearchPresented = true
                    }
                }
                // 监听自动展开搜索栏的通知
                NotificationCenter.default.addObserver(
                    forName: .autoExpandPetChatSearch,
                    object: nil,
                    queue: .main
                ) { _ in
                    withAnimation {
                        isSearchPresented = true
                    }
                }
            }
            .onChange(of: guideManager.currentFeatureExperienceFeature?.rawValue) { _, _ in
                ensureGuideEmbeddedOptionMessageIfNeeded()
            }
            .onChange(of: isSearchPresented) { oldValue, newValue in
                // 当 iOS26 搜索栏展开/收起时，通知常用菜单禁用/启用长按交互
                NotificationCenter.default.post(
                    name: .petChatSearchStateChanged,
                    object: nil,
                    userInfo: ["isSearching": newValue]
                )
            }
            .onChange(of: messages.count) { _, _ in
                PetChatTranscriptStore.save(messages: messages)
            }
            // iOS26+ 悬浮按钮 - 使用 safeAreaInset 确保跟随键盘移动
            .safeAreaInset(edge: .bottom) {
                // 当搜索栏展开时显示按钮在键盘上方
                if isSearchPresented {
                    floatingButtonsRow
                        .padding(.vertical, 60)
                        .background(.clear) // 透明背景，不遮挡内容
                }
            }
            // 搜索栏收起时的悬浮按钮（原位显示）
            .overlay(alignment: .bottom) {
                if !isSearchPresented {
                    floatingButtonsRow
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    private var floatingButtonsRow: some View {
        HStack {
            iOS26LeftFloatingButton
                .padding(.leading, 16)
            
            Spacer()
            
            iOS26RightFloatingButton
                .padding(.trailing, 16)
        }
    }
    
    // iOS26+ 左侧悬浮菜单按钮
    private var iOS26LeftFloatingButton: some View {
        Menu {
            Section("AI搭配") {
                Button {
                    handleOutfitSuggestion("帮我搭配一套")
                } label: {
                    Label("智能搭配", systemImage: "wand.and.stars")
                }

                Menu("快速搭配") {
                    Button {
                        createQuickOutfit(style: "甜美", occasion: "约会")
                    } label: {
                        Label("甜美约会", systemImage: "heart.fill")
                    }

                    Button {
                        createQuickOutfit(style: "优雅", occasion: "茶会")
                    } label: {
                        Label("优雅茶会", systemImage: "cup.and.saucer.fill")
                    }

                    Button {
                        createQuickOutfit(style: "日常", occasion: "出门")
                    } label: {
                        Label("日常出门", systemImage: "bag.fill")
                    }
                }
            }

            Section("快捷功能") {
                Button {
                    handleWardrobeStatistics()
                } label: {
                    Label("统计裙子", systemImage: "chart.pie.fill")
                }

                Button {
                    handlePetStatusOverview()
                } label: {
                    Label("查看萌宠状态", systemImage: "heart.text.square.fill")
                }

                Button {
                    handleInventoryPanel()
                } label: {
                    Label("打开萌宠背包", systemImage: "shippingbox.fill")
                }

                Button {
                    handleShopPanel()
                } label: {
                    Label("打开萌宠商店", systemImage: "cart.fill")
                }
                
                Button {
                    handleWeatherOutfitGuidance()
                } label: {
                    Label("查看天气穿搭", systemImage: "cloud.sun.rain.fill")
                }

                Button {
                    handleDepositPlanQuery()
                } label: {
                    Label("尾款提醒", systemImage: "tag.fill")
                }
                
                Button {
                    handleMoneyCounterPanel()
                } label: {
                    Label("去来财数钞票", systemImage: "yensign.circle.fill")
                }

                Button {
                    handleDivinationPanel()
                } label: {
                    Label("今日求签", systemImage: "wand.and.stars")
                }
            }

            Section("查找") {
                Button {
                    // 设置搜索栏文本为"帮我找"
                    searchText = "帮我找"
                } label: {
                    Label("查找衣柜", systemImage: "magnifyingglass")
                }

                Button {
                    showingHistorySearch = true
                } label: {
                    Label("历史消息查询", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("其他") {
                Button {
                    handleOutfitSuggestion("帮我来一套今天能直接穿的裙装搭配")
                } label: {
                    Label("随机穿搭推荐", systemImage: "sparkles")
                }

                Button {
                    handleDivinationPanel()
                } label: {
                    Label("今日运势", systemImage: "star.fill")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24))
                .foregroundStyle(.pink)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
        }
    }
    
    // iOS26+ 右侧悬浮发送按钮
    private var iOS26RightFloatingButton: some View {
        Button {
            if !searchText.isEmpty {
                sendMessageFromSearchBar()
            }
        } label: {
            Text("发送")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(searchText.isEmpty ? .gray.opacity(0.5) : .pink)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
        }
        .disabled(searchText.isEmpty)
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

    // 从搜索栏发送消息 - 等同于 PetDialogueInputView 的功能
    private func sendMessageFromSearchBar() {
        let userText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        // 清空搜索栏
        searchText = ""
        
        // 添加用户消息到对话
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图（和底部输入框一样的逻辑）
        processUserIntent(userText)
    }

    // 处理来自搜索栏的搜索（菜单中的搜索功能）
    private func handleSearchFromSearchBar(_ query: String) {
        // 添加用户搜索消息
        let userMessage = PetChatMessage(text: "\(query)", isUser: true)
        messages.append(userMessage)
        
        isThinking = true
        
        // 执行搜索
        let results = clothings.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(query) ||
            (clothing.brand?.name.localizedCaseInsensitiveContains(query) ?? false) ||
            clothing.types.localizedCaseInsensitiveContains(query) ||
            (clothing.tags?.contains { $0.name.localizedCaseInsensitiveContains(query) } ?? false)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isThinking = false
            
            let responseText: String
            if results.isEmpty {
                responseText = "喵... 没找到相关的裙子呢，要不要看看其他的？"
            } else {
                responseText = "（眼睛发亮）找到\(results.count)件相关的裙子，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: results.isEmpty ? nil : results
            )
            messages.append(message)
            
            // 清空搜索栏
            searchText = ""
        }
    }
    
    // 配置AI服务 - 根据当前选中的宠物使用对应的AI角色
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
    
    // 加载初始问候
    private func loadInitialGreeting() {
        let localTranscript = PetChatTranscriptStore.load()
        if !localTranscript.isEmpty {
            messages = localTranscript
            return
        }

        let greeting = greetingManager.getGreetingTitle()
        // 根据当前宠物使用对应的问候语和用户起的宠物名字
        let currentCharacter = PetDataManager.shared.getCurrentPetCharacter()
        let greetingSuffix = currentCharacter == .maomao ? "汪~" : "喵~"
        let petDisplayName = PetDataManager.shared.status.displayName // 使用用户起的宠物名字
        let onboardingWidgets = onboardingWidgetsForCurrentPetState()
        let welcomeMessage = PetChatMessage(
            text: "\(greeting)\(greetingSuffix) 我是你的专属衣橱管家\(petDisplayName)，有什么可以帮你的吗？",
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
                        PetWidgetOption(title: "领养奶茶（免费）", command: "adopt_pet:naicha", icon: "pawprint.fill"),
                        PetWidgetOption(title: "领养毛毛（60喵币）", command: "adopt_pet:maomao", icon: "pawprint.circle.fill"),
                        PetWidgetOption(title: "看看货币余额", command: "pet_currency_panel", icon: "wallet.pass.fill")
                    ]
                )
            ]
        }
        return PetWidgetSuggestionBuilder.onboardingWidgets()
    }

    private func ensureGuideEmbeddedOptionMessageIfNeeded() {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }

        let hasGuideOption = messages.contains { message in
            (message.widgets ?? []).contains { widget in
                widget.options.contains { $0.command == "weather_guidance" }
            }
        }
        guard !hasGuideOption else { return }

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
    }
    
    // 发送消息
    private func sendMessage() {
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }
        
        inputText = ""
        
        // 添加用户消息
        let userMessage = PetChatMessage(text: userText, isUser: true)
        messages.append(userMessage)
        
        // 处理用户意图
        processUserIntent(userText)
    }
    
    // 处理用户意图
    private func processUserIntent(_ text: String) {
        if handleDirectPetSwitchMention(text) {
            return
        }

        if handleDirectFeedIntent(text) {
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
            messages.append(PetChatMessage(text: "\(targetName)还没领养，先领养再切换哦～", isUser: false, isAIGenerated: true))
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
                text: kind == .all ? "给你把钱包摊开看啦～" : "我把\(kind.title)单独拎出来给你看啦。",
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
                text: "背包我给你摊开啦，点一下或者直接拖过去都行。",
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
                text: "商店我也给你带来啦，想买什么直接点就好～",
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
        guard let intent = detectEmbeddedPanelIntent(from: text, petName: PetDataManager.shared.status.displayName) else {
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
        if command.hasPrefix("buy_item:") || command == "pet_shop_panel" || command.hasPrefix("shop:") {
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
        case "pet_status_hunger":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hunger, feedback: feedback)])
        case "pet_status_hydration":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hydration, feedback: feedback)])
        case "pet_status_hygiene", "pet_clean_now":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hygiene, feedback: feedback)])
        case "pet_status_mood":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .mood, feedback: feedback)])
        case "pet_status_intimacy":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .intimacy, feedback: feedback)])
        default:
            break
        }
    }

    private func handleSecondPetAdoptionIntent() {
        var status = PetDataManager.shared.status
        let owned = Set(status.ownedPetIds)

        if owned.count >= PetCharacter.allCases.count {
            messages.append(PetChatMessage(text: "你已经是双宝家庭啦，要不要我帮你切换宠物管家？", isUser: false, isAIGenerated: true))
            handleSwitchPetIntent()
            return
        }

        guard let target = PetCharacter.allCases.first(where: { !owned.contains($0.id) }) else {
            messages.append(PetChatMessage(text: "我暂时没找到可领养的新伙伴喔。", isUser: false, isAIGenerated: true))
            return
        }

        let cost = 60
        guard status.meowCoin >= cost else {
            let lack = cost - status.meowCoin
            let widget = PetWidgetData(
                type: .quickOptions,
                title: "领养二宝需要 60 喵币",
                options: [
                    PetWidgetOption(title: "我想充值喵币", command: "pet_topup", icon: "plus.circle.fill"),
                    PetWidgetOption(title: "看看余额", command: "pet_currency_panel", icon: "wallet.pass.fill"),
                    PetWidgetOption(title: "先不领养", command: "mood_support", icon: "pause.circle.fill")
                ]
            )
            messages.append(
                PetChatMessage(
                    text: "还差 \(lack) 喵币就能领养\(target.displayName)啦～",
                    isUser: false,
                    isAIGenerated: true,
                    widgets: [widget]
                )
            )
            return
        }

        status.meowCoin -= cost
        status.ownedPetIds.append(target.id)
        status.selectedPetId = target.id
        if status.petNames[target.id] == nil {
            status.petNames[target.id] = target.displayName
        }
        status.intimacy = min(100, status.intimacy + 8)
        PetDataManager.shared.saveStatus(status)

        let widget = PetWidgetData(
            type: .quickOptions,
            title: "领养成功：\(target.displayName)",
            options: [
                PetWidgetOption(title: "看看货币余额", command: "pet_currency_panel", icon: "wallet.pass.fill"),
                PetWidgetOption(title: "我想再切换宠物", command: "pet_switch", icon: "arrow.triangle.2.circlepath"),
                PetWidgetOption(title: "先聊聊今天穿搭", command: "weather_guidance", icon: "cloud.sun.fill")
            ]
        )
        messages.append(
            PetChatMessage(
                text: "领养完成！\(target.displayName)来陪你啦，已经扣除 60 喵币。",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleSwitchPetIntent() {
        let status = PetDataManager.shared.status
        let ownedPets = PetCharacter.allCases.filter { status.ownedPetIds.contains($0.id) }
        guard ownedPets.count >= 2 else {
            messages.append(PetChatMessage(text: "你现在只有一只宠物，想养二宝的话我可以直接帮你办理。", isUser: false, isAIGenerated: true))
            return
        }

        let options = ownedPets.prefix(3).map { pet in
            return PetWidgetOption(
                title: "切换到\(pet.displayName)",
                command: "switch_pet:\(pet.id)",
                icon: "pawprint.fill"
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

    private func handleThemeConversationIntent(_ text: String) -> Bool {
        guard let result = PetThemeConversationEngine.handleIfNeeded(userText: text, themeManager: themeManager) else {
            return false
        }
        if result.shouldAnimate {
            triggerThemeSwitchAnimation()
        }
        let reply = PetChatMessage(text: result.reply, isUser: false, isAIGenerated: true)
        messages.append(reply)
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

    private func handleWidgetAction(_ option: PetWidgetOption, messageID: UUID) {
        switch option.command {
        case "outfit_suggest":
            handleOutfitSuggestion("帮我搭配一套")
        case "weather_guidance":
            handleWeatherOutfitGuidance()
        case "search_prompt":
            searchText = "帮我找"
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
#if DEBUG
            _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 100)
            messages.append(PetChatMessage(text: "🛠️ Debug：已添加 100 喵币", isUser: false, isAIGenerated: true))
#else
            showingMeowCoinStore = true
#endif
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
        case "pet_topup":
            handleMeowCoinTopUpIntent()
        case "pet_clean_now":
            refreshPanel(for: "pet_clean_now", messageID: messageID, feedback: cleanPetStatusNow())
        case "open_meow_store":
#if DEBUG
            _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 100)
            messages.append(PetChatMessage(text: "🛠️ Debug：已添加 100 喵币", isUser: false, isAIGenerated: true))
#else
            showingMeowCoinStore = true
#endif
        case "open_money_counting":
            refreshPanel(for: "open_money_counting", messageID: messageID)
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
                let result = purchasePetItemResult(itemId: rawId, autoFeedWhenPossible: true)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("inventory:") {
                let rawId = String(option.command.dropFirst("inventory:".count))
                let result = consumePetItemResult(itemId: rawId)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("shop:") {
                let rawId = String(option.command.dropFirst("shop:".count))
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
                        messages.append(PetChatMessage(text: "这只小伙伴还没领养，先领养再切换哦～", isUser: false, isAIGenerated: true))
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
                    let cost = pet == .maomao ? 60 : 0
                    guard status.meowCoin >= cost else {
                        messages.append(PetChatMessage(text: "领养\(pet.displayName)需要 \(cost) 喵币，你当前余额不够喔。", isUser: false, isAIGenerated: true))
                        return
                    }
                    status.meowCoin -= cost
                    status.ownedPetIds.append(pet.id)
                    status.selectedPetId = pet.id
                    if status.petNames[pet.id] == nil {
                        status.petNames[pet.id] = pet.displayName
                    }
                    status.intimacy = min(100, status.intimacy + 5)
                    PetDataManager.shared.saveStatus(status)
                    messages.append(PetChatMessage(text: "领养成功！欢迎\(pet.displayName)加入小队～", isUser: false, isAIGenerated: true))
                }
            } else if option.command.hasPrefix("ask:") {
                let query = String(option.command.dropFirst(4))
                if !query.isEmpty {
                    let userMessage = PetChatMessage(text: query, isUser: true, isUserAuthored: false)
                    messages.append(userMessage)
                    processUserIntent(query)
                }
            }
        }
    }

    // 创建消息气泡视图
    private func messageBubble(for message: PetChatMessage) -> some View {
        PetChatBubble(
            message: message,
            petName: petAI.petName,
            onCardTap: handleClothingTap,
            onSearchResultTap: handleClothingTap,
            onOutfitTap: handleOutfitTap,
            onWidgetAction: handleWidgetAction
        )
        .id(message.id)
    }

    // 处理服装点击
    private func handleClothingTap(_ clothing: Clothing) {
        selectedClothing = clothing
        navigateToDetail = true
    }

    // 处理搭配建议点击 - 直接保存到默认手帐
    private func handleOutfitTap(_ suggestion: OutfitSuggestionData) {
        guard !isSavingOutfit else { return }
        
        // 设置要展示的搭配裙装列表
        selectedOutfitClothings = suggestion.clothings
        
        // 直接执行保存流程
        Task {
            await saveOutfitToDefaultBook(clothings: suggestion.clothings)
        }
    }
    
    // MARK: - 保存搭配到默认手帐
    private func saveOutfitToDefaultBook(clothings: [Clothing]) async {
        await MainActor.run {
            isSavingOutfit = true
        }
        
        do {
            // 获取所有抠图
            let allCutouts = try modelContext.fetch(FetchDescriptor<CutoutItem>())
            
            // 查找推荐裙装的抠图
            var availableCutouts: [CutoutItem] = []
            for clothing in clothings {
                if let cutout = allCutouts.first(where: { $0.linkedClothingID == clothing.id }) {
                    availableCutouts.append(cutout)
                }
            }
            
            // 至少需要2个抠图才能生成搭配
            guard availableCutouts.count >= 2 else {
                await MainActor.run {
                    isSavingOutfit = false
                    // 显示错误消息
                    let errorMessage = PetChatMessage(
                        text: "（歪头）这些裙子还没有抠图呢，至少需要2件单品的抠图才能生成搭配喵~",
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
            let book = try await getOrCreateDefaultBook()
            
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
    
    // MARK: - 获取或创建默认手帐
    private func getOrCreateDefaultBook() async throws -> BookGroup {
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

    // 处理衣橱统计
    private func handleWardrobeStatistics() {
        isThinking = true
        
        // 计算统计数据
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
        
        // 模拟思考延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isThinking = false
            
            let responseText: String
            if totalCount == 0 {
                responseText = "喵？你的衣橱还是空的耶，快去添加几件漂亮裙子吧~"
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
    
    // 处理搭配色推荐
    private func handleColorMatch() {
        isThinking = true
        
        // 根据衣橱颜色分布生成推荐
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
    
    // 处理搜索
    private func handleSearch(_ query: String) {
        isThinking = true
        
        // 提取搜索关键词
        let keywords = query
            .replacingOccurrences(of: "帮我找", with: "")
            .replacingOccurrences(of: "搜索", with: "")
            .replacingOccurrences(of: "有没有", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let results = clothings.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(keywords) ||
            (clothing.brand?.name.localizedCaseInsensitiveContains(keywords) ?? false) ||
            clothing.types.localizedCaseInsensitiveContains(keywords)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if results.isEmpty {
                responseText = "喵... 没找到相关的裙子呢，要不要看看其他的？"
            } else {
                responseText = "（眼睛发亮）找到\(results.count)件相关的裙子，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: results.isEmpty ? nil : results
            )
            messages.append(message)
        }
    }
    
    // 处理尾款查询
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
                responseText = "喵~ 目前没有待补款的裙子呢，主人的钱包可以休息一下啦！"
            } else {
                responseText = "（认真脸）主人还有\(depositPlans.count)款裙子要补尾款，一共要准备\(NSDecimalNumber(decimal: totalBalance).stringValue)元喵~"
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
        if let summary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: role) {
            text = "（翻出小账本）\(summary)～要不要我按这个预算再给你一套同风格的？"
        } else {
            text = "（挠挠耳朵）我这边还没记到最近一套搭配价格喵，先让我给你搭一套，再帮你精确算总价吧。"
        }

        let message = PetChatMessage(
            text: text,
            isUser: false
        )
        messages.append(message)
    }
    
    private func handleWeatherOutfitGuidance() {
        isThinking = true
        let selection = PetChatGuidanceEngine.pickWeatherOutfitItems(from: clothings)
        
        Task { @MainActor in
            let weather = await fetchCurrentWeather()
            let responseText = PetChatGuidanceEngine.buildWeatherAdvice(weather: weather, selection: selection)
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
        
        return nil
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
    
    // 处理AI对话
    private func handleAIChat(_ text: String) {
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

    // MARK: - 搭配建议处理

    /// 处理搭配建议请求
    private func handleOutfitSuggestion(_ text: String) {
        // 检查是否有足够的裙装
        guard clothings.count >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的裙子还不够呢，至少需要2件单品才能搭配喵~",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制，防止卡住
                let (selectedClothings, responseText, style, occasion) = try await withTimeout(seconds: 30) {
                    try await OutfitSuggestionService.shared.processOutfitRequest(
                        query: text,
                        clothings: self.clothings,
                        context: self.modelContext
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
                        description: responseText,
                        style: style,
                        occasion: occasion,
                        layoutInfos: nil
                    )

                    let message = PetChatMessage(
                        text: responseText,
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（蹭蹭你）我刚刚卡壳了喵…可以试试切稳定网络、把需求说短一点（场景+风格），或者等半分钟再试，我会继续陪你慢慢挑~",
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false

                    let errorMessage = (error as? OutfitSuggestionError)?.errorDescription ?? "搭配生成失败，请重试喵~"
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
        guard clothings.count >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的裙子还不够呢，至少需要2件单品才能搭配喵~",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制
                let selectedClothings = try await withTimeout(seconds: 15) {
                    try await OutfitSuggestionService.shared.createQuickOutfit(
                        style: style,
                        occasion: occasion,
                        clothings: self.clothings,
                        context: self.modelContext
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
                        text: "（眼睛发亮）为你准备了一套\(style)风\(occasion)搭配，快来看看吧喵~",
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（蹭蹭你）我刚刚卡壳了喵…可以试试切稳定网络、把需求说短一点（场景+风格），或者等半分钟再试，我会继续陪你慢慢挑~",
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
    @State private var selectedClothing: Clothing?
    @State private var navigateToDetail = false
    @State private var hasEnteredOnce = false
    @State private var showingHistorySearch = false
    @State private var showingMeowCoinStore = false
    @State private var showingCurrencyExchangeSheet = false
    @State private var preferredExchangeDirection: PetCurrencyExchangeDirection = .fishToBone

    // 搭配建议相关状态
    @State private var selectedOutfitClothings: [Clothing] = []
    @State private var showingOutfitStickerFlow = false
    
    // 保存成功提示状态
    @State private var showingSaveSuccessToast = false
    @State private var isSavingOutfit = false
    @State private var showingThemeSwitchOverlay = false
    @State private var activeFeedAnimation: PetFeedAnimationPayload?
    @State private var feedAnimationNonce: Int = 0

    @StateObject private var greetingManager = DailyGreetingManager.shared
    
    // 输入框提示文字，使用用户起的宠物名字
    private var inputPlaceholder: String {
        let petName = PetDataManager.shared.status.displayName
        return "和\(petName)对话、搜索裙子..."
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
                                    legacyMessageBubble(for: message)
                                }
                                
                                if isThinking {
                                    HStack {
                                        ModernAIThinkingView()
                                            .id("thinking")
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
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
            .sheet(isPresented: $showingCurrencyExchangeSheet) {
                PetCurrencyExchangeSheet(preferredDirection: preferredExchangeDirection)
                    .presentationDetents([.medium])
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

                    if let payload = activeFeedAnimation {
                        PetFeedAnimationOverlay(payload: payload)
                            .transition(.opacity)
                            .zIndex(110)
                    }
                }
            }
            .onAppear {
                if messages.isEmpty {
                    loadInitialGreeting()
                }
                ensureGuideEmbeddedOptionMessageIfNeeded()
                configureAIService()
                // 首次进入萌宠对话页面时，自动展开搜索栏
                if !hasEnteredOnce {
                    hasEnteredOnce = true
                    // iOS 18 以下版本不支持 isPresented，使用 searchText 触发搜索模式
                    searchText = " "
                }
            }
            .onChange(of: guideManager.currentFeatureExperienceFeature?.rawValue) { _, _ in
                ensureGuideEmbeddedOptionMessageIfNeeded()
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
                    // AI搭配菜单
                    Menu("AI搭配") {
                        Button {
                            handleOutfitSuggestion("帮我搭配一套")
                        } label: {
                            Label("智能搭配", systemImage: "wand.and.stars")
                        }

                        Button {
                            createQuickOutfit(style: "甜美", occasion: "约会")
                        } label: {
                            Label("甜美约会", systemImage: "heart")
                        }

                        Button {
                            createQuickOutfit(style: "优雅", occasion: "茶会")
                        } label: {
                            Label("优雅茶会", systemImage: "cup.and.saucer")
                        }

                        Button {
                            createQuickOutfit(style: "日常", occasion: "出门")
                        } label: {
                            Label("日常出门", systemImage: "bag")
                        }
                    }

                    Button {
                        handleWardrobeStatistics()
                    } label: {
                        Label("统计裙子", systemImage: "chart.pie")
                    }

                    Button {
                        handlePetStatusOverview()
                    } label: {
                        Label("查看萌宠状态", systemImage: "heart.text.square.fill")
                    }

                    Button {
                        handleInventoryPanel()
                    } label: {
                        Label("打开萌宠背包", systemImage: "shippingbox.fill")
                    }

                    Button {
                        handleShopPanel()
                    } label: {
                        Label("打开萌宠商店", systemImage: "cart.fill")
                    }
                    
                    Button {
                        handleWeatherOutfitGuidance()
                    } label: {
                        Label("查看天气穿搭", systemImage: "cloud.sun.rain.fill")
                    }

                    Button {
                        handleDepositPlanQuery()
                    } label: {
                        Label("尾款提醒", systemImage: "tag")
                    }
                    
                    Button {
                        handleMoneyCounterPanel()
                    } label: {
                        Label("去来财数钞票", systemImage: "yensign.circle.fill")
                    }

                    Button {
                        handleDivinationPanel()
                    } label: {
                        Label("今日求签", systemImage: "wand.and.stars")
                    }

                    Button {
                        // 查找衣柜功能
                        inputText = "帮我找"
                    } label: {
                        Label("查找衣柜", systemImage: "magnifyingglass")
                    }

                    Button {
                        showingHistorySearch = true
                    } label: {
                        Label("历史消息查询", systemImage: "clock.arrow.circlepath")
                    }
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
        let localTranscript = PetChatTranscriptStore.load()
        if !localTranscript.isEmpty {
            messages = localTranscript
            return
        }

        let greeting = greetingManager.getGreetingTitle()
        // 根据当前宠物使用对应的问候语和用户起的宠物名字
        let currentCharacter = PetDataManager.shared.getCurrentPetCharacter()
        let greetingSuffix = currentCharacter == .maomao ? "汪~" : "喵~"
        let petDisplayName = PetDataManager.shared.status.displayName // 使用用户起的宠物名字
        let onboardingWidgets = onboardingWidgetsForCurrentPetState()
        let welcomeMessage = PetChatMessage(
            text: "\(greeting)\(greetingSuffix) 我是你的专属衣橱管家\(petDisplayName)，有什么可以帮你的吗？",
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
                        PetWidgetOption(title: "领养奶茶（免费）", command: "adopt_pet:naicha", icon: "pawprint.fill"),
                        PetWidgetOption(title: "领养毛毛（60喵币）", command: "adopt_pet:maomao", icon: "pawprint.circle.fill"),
                        PetWidgetOption(title: "看看货币余额", command: "pet_currency_panel", icon: "wallet.pass.fill")
                    ]
                )
            ]
        }
        return PetWidgetSuggestionBuilder.onboardingWidgets()
    }

    private func ensureGuideEmbeddedOptionMessageIfNeeded() {
        guard guideManager.currentFeatureExperienceFeature == .aiAnalysis else { return }

        let hasGuideOption = messages.contains { message in
            (message.widgets ?? []).contains { widget in
                widget.options.contains { $0.command == "weather_guidance" }
            }
        }
        guard !hasGuideOption else { return }

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
            
            // 查找推荐裙装的抠图
            var availableCutouts: [CutoutItem] = []
            for clothing in clothings {
                if let cutout = allCutouts.first(where: { $0.linkedClothingID == clothing.id }) {
                    availableCutouts.append(cutout)
                }
            }
            
            // 至少需要2个抠图才能生成搭配
            guard availableCutouts.count >= 2 else {
                await MainActor.run {
                    isSavingOutfit = false
                    // 显示错误消息
                    let errorMessage = PetChatMessage(
                        text: "（歪头）这些裙子还没有抠图呢，至少需要2件单品的抠图才能生成搭配喵~",
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
            messages.append(PetChatMessage(text: "\(targetName)还没领养，先领养再切换哦～", isUser: false, isAIGenerated: true))
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
                text: kind == .all ? "给你把钱包摊开看啦～" : "我把\(kind.title)单独拎出来给你看啦。",
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
                text: "背包我给你摊开啦，点一下或者直接拖过去都行。",
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
                text: "商店我也给你带来啦，想买什么直接点就好～",
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
        guard let intent = detectEmbeddedPanelIntent(from: text, petName: PetDataManager.shared.status.displayName) else {
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
        if command.hasPrefix("buy_item:") || command == "pet_shop_panel" || command.hasPrefix("shop:") {
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
        case "pet_status_hunger":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hunger, feedback: feedback)])
        case "pet_status_hydration":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hydration, feedback: feedback)])
        case "pet_status_hygiene", "pet_clean_now":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .hygiene, feedback: feedback)])
        case "pet_status_mood":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .mood, feedback: feedback)])
        case "pet_status_intimacy":
            replaceWidgets(in: messageID, with: [makeStatusPanelWidget(status: status, kind: .intimacy, feedback: feedback)])
        default:
            break
        }
    }

    private func handleSecondPetAdoptionIntent() {
        var status = PetDataManager.shared.status
        let owned = Set(status.ownedPetIds)

        if owned.count >= PetCharacter.allCases.count {
            messages.append(PetChatMessage(text: "你已经是双宝家庭啦，要不要我帮你切换宠物管家？", isUser: false, isAIGenerated: true))
            handleSwitchPetIntent()
            return
        }

        guard let target = PetCharacter.allCases.first(where: { !owned.contains($0.id) }) else {
            messages.append(PetChatMessage(text: "我暂时没找到可领养的新伙伴喔。", isUser: false, isAIGenerated: true))
            return
        }

        let cost = 60
        guard status.meowCoin >= cost else {
            let lack = cost - status.meowCoin
            let widget = PetWidgetData(
                type: .quickOptions,
                title: "领养二宝需要 60 喵币",
                options: [
                    PetWidgetOption(title: "我想充值喵币", command: "pet_topup", icon: "plus.circle.fill"),
                    PetWidgetOption(title: "看看余额", command: "pet_currency_panel", icon: "wallet.pass.fill"),
                    PetWidgetOption(title: "先不领养", command: "mood_support", icon: "pause.circle.fill")
                ]
            )
            messages.append(
                PetChatMessage(
                    text: "还差 \(lack) 喵币就能领养\(target.displayName)啦～",
                    isUser: false,
                    isAIGenerated: true,
                    widgets: [widget]
                )
            )
            return
        }

        status.meowCoin -= cost
        status.ownedPetIds.append(target.id)
        status.selectedPetId = target.id
        if status.petNames[target.id] == nil {
            status.petNames[target.id] = target.displayName
        }
        status.intimacy = min(100, status.intimacy + 8)
        PetDataManager.shared.saveStatus(status)

        let widget = PetWidgetData(
            type: .quickOptions,
            title: "领养成功：\(target.displayName)",
            options: [
                PetWidgetOption(title: "看看货币余额", command: "pet_currency_panel", icon: "wallet.pass.fill"),
                PetWidgetOption(title: "我想再切换宠物", command: "pet_switch", icon: "arrow.triangle.2.circlepath"),
                PetWidgetOption(title: "先聊聊今天穿搭", command: "weather_guidance", icon: "cloud.sun.fill")
            ]
        )
        messages.append(
            PetChatMessage(
                text: "领养完成！\(target.displayName)来陪你啦，已经扣除 60 喵币。",
                isUser: false,
                isAIGenerated: true,
                widgets: [widget]
            )
        )
    }

    private func handleSwitchPetIntent() {
        let status = PetDataManager.shared.status
        let ownedPets = PetCharacter.allCases.filter { status.ownedPetIds.contains($0.id) }
        guard ownedPets.count >= 2 else {
            messages.append(PetChatMessage(text: "你现在只有一只宠物，想养二宝的话我可以直接帮你办理。", isUser: false, isAIGenerated: true))
            return
        }

        let options = ownedPets.prefix(3).map { pet in
            return PetWidgetOption(
                title: "切换到\(pet.displayName)",
                command: "switch_pet:\(pet.id)",
                icon: "pawprint.fill"
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

    private func handleThemeConversationIntent(_ text: String) -> Bool {
        guard let result = PetThemeConversationEngine.handleIfNeeded(userText: text, themeManager: themeManager) else {
            return false
        }
        if result.shouldAnimate {
            triggerThemeSwitchAnimation()
        }
        let reply = PetChatMessage(text: result.reply, isUser: false, isAIGenerated: true)
        messages.append(reply)
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

    private func legacyHandleWidgetAction(_ option: PetWidgetOption, messageID: UUID) {
        switch option.command {
        case "outfit_suggest":
            handleOutfitSuggestion("帮我搭配一套")
        case "weather_guidance":
            handleWeatherOutfitGuidance()
        case "search_prompt":
            inputText = "帮我找"
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
#if DEBUG
            _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 100)
            messages.append(PetChatMessage(text: "🛠️ Debug：已添加 100 喵币", isUser: false, isAIGenerated: true))
#else
            showingMeowCoinStore = true
#endif
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
        case "pet_topup":
            handleMeowCoinTopUpIntent()
        case "pet_clean_now":
            refreshPanel(for: "pet_clean_now", messageID: messageID, feedback: cleanPetStatusNow())
        case "open_meow_store":
#if DEBUG
            _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 100)
            messages.append(PetChatMessage(text: "🛠️ Debug：已添加 100 喵币", isUser: false, isAIGenerated: true))
#else
            showingMeowCoinStore = true
#endif
        case "open_money_counting":
            refreshPanel(for: "open_money_counting", messageID: messageID)
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
                let result = purchasePetItemResult(itemId: rawId, autoFeedWhenPossible: true)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("inventory:") {
                let rawId = String(option.command.dropFirst("inventory:".count))
                let result = consumePetItemResult(itemId: rawId)
                if let animation = result.feedAnimation {
                    triggerFeedAnimation(animation)
                }
                refreshPanel(for: option.command, messageID: messageID, feedback: result.feedback)
            } else if option.command.hasPrefix("shop:") {
                let rawId = String(option.command.dropFirst("shop:".count))
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
                        messages.append(PetChatMessage(text: "这只小伙伴还没领养，先领养再切换哦～", isUser: false, isAIGenerated: true))
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
                    let cost = pet == .maomao ? 60 : 0
                    guard status.meowCoin >= cost else {
                        messages.append(PetChatMessage(text: "领养\(pet.displayName)需要 \(cost) 喵币，你当前余额不够喔。", isUser: false, isAIGenerated: true))
                        return
                    }
                    status.meowCoin -= cost
                    status.ownedPetIds.append(pet.id)
                    status.selectedPetId = pet.id
                    if status.petNames[pet.id] == nil {
                        status.petNames[pet.id] = pet.displayName
                    }
                    status.intimacy = min(100, status.intimacy + 5)
                    PetDataManager.shared.saveStatus(status)
                    messages.append(PetChatMessage(text: "领养成功！欢迎\(pet.displayName)加入小队～", isUser: false, isAIGenerated: true))
                }
            } else if option.command.hasPrefix("ask:") {
                let query = String(option.command.dropFirst(4))
                if !query.isEmpty {
                    let userMessage = PetChatMessage(text: query, isUser: true, isUserAuthored: false)
                    messages.append(userMessage)
                    processUserIntent(query)
                }
            }
        }
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
                responseText = "喵？你的衣橱还是空的耶，快去添加几件漂亮裙子吧~"
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
        
        let keywords = query
            .replacingOccurrences(of: "帮我找", with: "")
            .replacingOccurrences(of: "搜索", with: "")
            .replacingOccurrences(of: "有没有", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let results = clothings.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(keywords) ||
            (clothing.brand?.name.localizedCaseInsensitiveContains(keywords) ?? false) ||
            clothing.types.localizedCaseInsensitiveContains(keywords)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isThinking = false
            
            let responseText: String
            if results.isEmpty {
                responseText = "喵... 没找到相关的裙子呢，要不要看看其他的？"
            } else {
                responseText = "（眼睛发亮）找到\(results.count)件相关的裙子，主人快看看~"
            }
            
            let message = PetChatMessage(
                text: responseText,
                isUser: false,
                type: .searchResults,
                searchResults: results.isEmpty ? nil : results
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
                responseText = "喵~ 目前没有待补款的裙子呢，主人的钱包可以休息一下啦！"
            } else {
                responseText = "（认真脸）主人还有\(depositPlans.count)款裙子要补尾款，一共要准备\(NSDecimalNumber(decimal: totalBalance).stringValue)元喵~"
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
        if let summary = PetConversationMemoryStore.shared.latestOutfitPriceSummary(for: role) {
            text = "（翻出小账本）\(summary)～你要我顺便按这个价位再补一套吗？"
        } else {
            text = "（挠挠耳朵）我这边还没记到最近一套搭配价格喵，先让我给你搭一套，再帮你精确算总价吧。"
        }

        let message = PetChatMessage(
            text: text,
            isUser: false
        )
        messages.append(message)
    }
    
    private func handleWeatherOutfitGuidance() {
        isThinking = true
        let selection = PetChatGuidanceEngine.pickWeatherOutfitItems(from: clothings)
        
        Task { @MainActor in
            let weather = await fetchCurrentWeather()
            let responseText = PetChatGuidanceEngine.buildWeatherAdvice(weather: weather, selection: selection)
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
        
        return nil
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
        // 检查是否有足够的抠图
        let availableCount = OutfitSuggestionService.shared.availableCutoutCount(context: modelContext)
        guard availableCount >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的抠图还不够呢，至少需要2件单品才能搭配喵~ 快去生成一些抠图吧！",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制
                let (selectedClothings, responseText, style, occasion) = try await withTimeout(seconds: 30) {
                    try await OutfitSuggestionService.shared.processOutfitRequest(
                        query: text,
                        clothings: self.clothings,
                        context: self.modelContext
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
                        description: responseText,
                        style: style,
                        occasion: occasion,
                        layoutInfos: nil
                    )

                    let message = PetChatMessage(
                        text: responseText,
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（抱住你）我刚刚想太久啦喵…你可以先给我“场景+风格”短句，或换稳定网络再试一次，我会乖乖继续帮你配~",
                        isUser: false
                    )
                    messages.append(message)
                }
            } catch {
                await MainActor.run {
                    isThinking = false

                    let errorMessage = (error as? OutfitSuggestionError)?.errorDescription ?? "搭配生成失败，请重试喵~"
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
        guard clothings.count >= 2 else {
            let message = PetChatMessage(
                text: "（歪头）主人衣橱里的裙子还不够呢，至少需要2件单品才能搭配喵~",
                isUser: false
            )
            messages.append(message)
            return
        }

        isThinking = true

        Task {
            do {
                // 添加超时机制
                let selectedClothings = try await withTimeout(seconds: 15) {
                    try await OutfitSuggestionService.shared.createQuickOutfit(
                        style: style,
                        occasion: occasion,
                        clothings: self.clothings,
                        context: self.modelContext
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
                        text: "（眼睛发亮）为你准备了一套\(style)风\(occasion)搭配，快来看看吧喵~",
                        isUser: false,
                        type: .outfitSuggestion,
                        outfitSuggestion: suggestionData
                    )
                    messages.append(message)
                }
            } catch is TimeoutError {
                await MainActor.run {
                    isThinking = false
                    let message = PetChatMessage(
                        text: "（抱住你）我刚刚想太久啦喵…你可以先给我“场景+风格”短句，或换稳定网络再试一次，我会乖乖继续帮你配~",
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

// MARK: - 预览
#Preview {
    if #available(iOS 18.0, *) {
        PetChatView(searchText: .constant(""))
    } else {
        PetChatViewLegacy(searchText: .constant(""))
    }
}
