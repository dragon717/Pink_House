import SwiftUI
import Combine
import AVFoundation
import GameplayKit

struct FloatingTextData: Identifiable {
    let id = UUID()
    let text: String
    let style: FloatingTextStyle
    var offset: CGSize = .zero
    // 移除 opacity，由 View 层动画控制
}

enum FloatingTextStyle: Equatable {
    case warning    // 红色
    case meowCoin   // 闪光的金色，带喵币icon
    case fishCoin   // 闪光的铜色，带鱼币icon
    case boneCoin   // 骨头色
    case hunger     // 橙色
    case hygiene    // 蓝色
    case energy     // 绿色
    case mood       // 粉色
    case custom(Color) // 自定义颜色
    
    var color: Color {
        switch self {
        case .warning: return .red
        case .meowCoin: return .yellow // 基础色，View层会做特殊处理
        case .fishCoin: return .orange // 基础色，View层会做特殊处理
        case .boneCoin: return .brown  // 基础色，View层会做特殊处理
        case .hunger: return .orange
        case .hygiene: return .blue
        case .energy: return .green
        case .mood: return .pink
        case .custom(let color): return color
        }
    }
}

enum PetFundingSheetDestination: Identifiable, Equatable {
    case meowCoinStore
    case currencyExchange(PetCurrencyExchangeDirection)

    var id: String {
        switch self {
        case .meowCoinStore:
            return "meowCoinStore"
        case .currencyExchange(let direction):
            return "currencyExchange:\(direction.rawValue)"
        }
    }
}

struct PetFundingPrompt: Identifiable {
    let id = UUID()
    let currency: PetCurrency
    let title: String
    let message: String
    let actionTitle: String
    let destination: PetFundingSheetDestination
}

class PetViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentState: PetState = .idle
    @Published var currentVideoName: String = "idle" // 逻辑视频名 (e.g. "idle", "eating")
    @Published var currentVideoFileName: String = "idle" // 实际文件名前缀 (e.g. "naicha_idle", "naicha_eating")
    @Published var isCurrentLooping: Bool = true // 新增：动态控制当前视频是否循环
    @Published var status: PetStatus
    @Published var floatingTexts: [FloatingTextData] = []
    @Published var recognizedSpeechText: String = ""
    @Published var isAIMode: Bool = false // 是否开启 AI 对话模式
    @Published var presentedFundingSheet: PetFundingSheetDestination?
    @Published var presentedFundingPrompt: PetFundingPrompt?
    
    // MARK: - Behavior
    var currentBehavior: PetBehavior = DefaultPetBehavior(character: .naicha)
    
    static func getBehavior(for pet: PetCharacter) -> PetBehavior {
        switch pet {
        case .naicha: return NaichaBehavior()
        default: return DefaultPetBehavior(character: pet)
        }
    }
    
    // MARK: - Video State Machine
    var videoStateMachine: GKStateMachine!
    
    private var audioSubscription: AnyCancellable?
    
    // MARK: - Settings
    // Deprecated: isMicrophoneEnabled is now managed by AudioManager
    @Published var isMicrophoneEnabled: Bool = false
    
    // MARK: - Private Properties
    private var timer: Timer?
    private var speechBubbleWorkItem: DispatchWorkItem?
    private var silenceFeedbackTimer: Timer? // 用于处理沉默/噪声的延迟计时器
    private var cancellables = Set<AnyCancellable>()
    @Published var aiService: PetAIService? // Changed to public published
    // private let statusKey = "PetStatus_Data" // Moved to PetDataManager
    
    var currentPet: PetCharacter {
        // 如果 selectedPetId 为 nil，默认使用 naicha
        return PetCharacter(rawValue: status.selectedPetId ?? "") ?? .naicha
    }
    
    init(status: PetStatus) {
        self.status = status
        
        // 监听设置变化通知
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsChange), name: Notification.Name("AISettingsChanged"), object: nil)
        
        setupAIService()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopTimer()
        silenceFeedbackTimer?.invalidate()
    }
    
    @objc private func handleSettingsChange() {
        print("🔄 [PetViewModel] 检测到 AI 设置变更，正在重新加载配置...")
        setupAIService()
    }
    
    // MARK: - Helper Methods
    
    // 存储衣橱上下文
    var wardrobeContext: String = ""
    
    func updateWardrobeContext(clothings: [Clothing]) {
        let summary = WardrobeContextManager.shared.generateWardrobeSummary(clothings: clothings)
        self.wardrobeContext = summary
        
        // 更新共享服务的上下文
        PetAIService.shared.updateSystemContext(wardrobeContext: summary)
        
        // 确保 aiService 指向共享实例
        if self.aiService == nil {
            setupAIService()
        }
    }
    
    private func setupAIService() {
        let petName = status.displayName
        
        // 读取用户设置的优先级 (默认为 DeepSeek > Minimax)
        let priorityString = UserDefaults.standard.string(forKey: "textModelPriority") ?? "DeepSeek,Minimax"
        let priorityList = priorityString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        print("🔍 [PetViewModel] AI 模型优先级: \(priorityList)")
        
        for model in priorityList {
            print("  - Checking model: \(model)")
            switch model {
            case "DeepSeek":
                if let dsApiKey = AIConfigManager.shared.dsApiKey {
                    print("    -> DeepSeek Key found: \(dsApiKey.prefix(4))...")
                    PetAIService.shared.updateConfiguration(role: currentPet.aiRole, petName: petName, apiKey: dsApiKey, provider: .deepSeek, wardrobeContext: self.wardrobeContext)
                    self.aiService = PetAIService.shared
                    print("✅ [PetViewModel] 已启用 DeepSeek 模型")
                    return
                } else {
                     print("    -> DeepSeek Key NOT found")
                }
                
            case "Minimax":
                if let minimaxKey = AIConfigManager.shared.minimaxApiKey {
                    print("    -> Minimax Key found: \(minimaxKey.prefix(4))...")
                    PetAIService.shared.updateConfiguration(role: currentPet.aiRole, petName: petName, apiKey: minimaxKey, provider: .minimax, wardrobeContext: self.wardrobeContext)
                    self.aiService = PetAIService.shared
                    print("✅ [PetViewModel] 已启用 Minimax 模型")
                    return
                } else {
                     print("    -> Minimax Key NOT found")
                }
                
            default:
                print("    -> Unknown model: \(model)")
                break
            }
        }
        
        print("⚠️ [PetViewModel] 未找到可用的 AI 模型配置")
    }
    
    private func scheduleSpeechBubbleClear() {
        // 取消之前的任务
        speechBubbleWorkItem?.cancel()
        
        // 创建新任务
        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.5)) {
                self?.recognizedSpeechText = ""
            }
        }
        
        speechBubbleWorkItem = workItem
        
        // 自适应时长：基础 2s + 每字 0.2s，最长 10s
        let duration = min(10.0, max(2.0, 2.0 + Double(recognizedSpeechText.count) * 0.2))
        
        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    // 获取带角色前缀的视频文件名
    func getCharacterVideoName(action: String) -> String {
        // 如果 action 已经包含了路径分隔符（如 "asserts/"），或者是绝对路径，直接返回
        if action.hasPrefix("/") {
            return action
        }
        
        // 简单规则：角色ID_动作名
        // 例如：naicha_idle, maomao_eating
        return "\(currentPet.rawValue)_\(action)"
    }
    
    // MARK: - Pet Adoption & Switching
    
    // 获取领养价格
    static func adoptionPrice(for pet: PetCharacter, ownedPetIds: [String]) -> (price: Int, currency: PetCurrency) {
        // 规则：第一只宠物免费（不限角色）
        if ownedPetIds.isEmpty {
            return (0, .fishCoin)
        }
        
        switch pet {
        case .naicha, .maomao:
            return (60, .meowCoin)
        default:
            return (0, .fishCoin)
        }
    }
    
    func getAdoptionPrice(for pet: PetCharacter) -> (price: Int, currency: PetCurrency) {
        Self.adoptionPrice(for: pet, ownedPetIds: status.ownedPetIds)
    }
    
    // 领养宠物 (返回是否成功)
    @discardableResult
    func adoptPet(_ pet: PetCharacter, name: String? = nil) -> Bool {
        if status.ownedPetIds.contains(pet.id) {
            // 已经拥有，只更新名字和切换
            if let name = name, !name.isEmpty {
                status.petNames[pet.id] = name
            }
            switchPet(pet)
            saveStatus()
            return true
        }
        
        // 检查费用
        let (price, currency) = getAdoptionPrice(for: pet)
        if price > 0 {
            switch currency {
            case .meowCoin:
                guard StoreManager.spendMeowCoins(price, in: &status) else { return false }
            case .fishCoin:
                if status.fishCoin < price { return false }
                status.fishCoin -= price
            case .boneCoin:
                if status.boneCoin < price { return false }
                status.boneCoin -= price
            }
        }
        
        status.ownedPetIds.append(pet.id)
        
        if let name = name, !name.isEmpty {
            status.petNames[pet.id] = name
        }
        
        // 自动切换到新领养的宠物
        switchPet(pet)
        
        saveStatus()
        return true
    }
    
    // 切换宠物
    func switchPet(_ pet: PetCharacter) {
        guard status.ownedPetIds.contains(pet.id) else { return }
        
        // 更新状态
        status.selectedPetId = pet.id
        
        // 更新行为
        self.currentBehavior = Self.getBehavior(for: pet)
        setupAIService()
        
        // 通知 PetInteractionManager 更新宠物 ID
        // 注意：PetInteractionManager.currentPetId 是计算属性，依赖 PetDataManager.shared.status
        // 所以我们必须先保存状态，或者手动触发更新通知
        saveStatus()
        
        // 发送通知，强制 InteractionManager 刷新（如果它是观察者）
        // 或者直接调用它的更新方法
        // 由于 PetInteractionManager 也是单例且依赖 DataManager，
        // 我们需要确保 DataManager 已经有了最新的 status
        // saveStatus() 已经做了这件事
        
        // 显式通知 PetInteractionManager (如果它监听特定通知)
        // 或者因为 PetInteractionManager 是 ObservableObject，如果它被 View 观察，View 会重绘。
        // 但 OverlayView 中的 petImagePrefix 是计算属性，依赖 interactionManager.currentPetId
        // 而 interactionManager.currentPetId 依赖 PetDataManager.shared.status
        // 所以理论上只要 View 重绘，就会获取到新的 ID。
        // 为了确保万无一失，我们可以发布一个 Notification
        NotificationCenter.default.post(name: Notification.Name("PetDidSwitch"), object: nil)
        
        // 强制刷新视频状态
        // 这里我们需要重置一些状态，以确保 UI 刷新
        let currentAction = currentVideoName // e.g. "idle"
        let newFileName = getCharacterVideoName(action: currentAction)
        
        withAnimation {
            self.currentVideoFileName = newFileName
            // 如果需要，也可以重置回 idle
            if currentAction != "idle" {
                changeState(to: .idle)
            }
        }
    }
    
    // 获取下一个“胎”数中文名 (用于“再要x胎”)
    var nextAdoptionNumberText: String {
        let count = status.ownedPetIds.count
        // 简单映射，支持到 10 胎够用了吧...
        let numbers = ["", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if count < numbers.count {
            return numbers[count]
        }
        return "\(count + 1)"
    }
    
    // MARK: - Constants
    struct PetVideoPaths {
        static let angry = "angry_click"
        static let rolling = "rolling"
        static let bathingBoring = "bathing_boring"
        static let bathingHappy = "bathing_happy"
        static let drinking = "drinking_glass"
        static let eatingCanned = "eating_cannedFood"
        static let eatingCatFood = "eating_catFood"
        static let enjoy = "enjoy_click"
        static let grooming = "grooming"
        static let listening = "listening"
        static let playing = "playing"
        static let sleeping = "sleeping"
        
        static let attention = "attention"
        static let talking = "talking"
        static let dressingWork = "dressing_work"
        static let coronation = "coronation"
    }

    private let sleepThreshold: Double = 20.0
    private let forceSleepMinuteStart: Int = 45 // 每小时 45 分开始 (保留 15 分钟休息)
    private let forceSleepMinuteEnd: Int = 0    // 整点结束
    private let sleepEnergyRecoveryRate: Double = 100.0 / 3600.0 // 睡觉每小时回满 (100点)
    private let idleEnergyRecoveryRate: Double = 20.0 / 3600.0   // 闲置每小时回 20 点
    private let sleepMoodRecoveryRate: Double = 30.0 / 3600.0    // 睡觉心情恢复 (降低恢复量，确保不交互时心情总体下降)
    private let idleMoodRecoveryRate: Double = 10.0 / 3600.0     // 闲置心情恢复
    
    // MARK: - Initialization
    init() {
        // Initial load from DataManager
        self.status = PetDataManager.shared.status
        
        // Initialize behavior
        let initialPet = PetCharacter(rawValue: status.selectedPetId ?? "") ?? .naicha
        self.currentBehavior = Self.getBehavior(for: initialPet)
        
        setupAIService()
        setupStateMachine()
        
        // Calculate offline decay
        calculateOfflineDecay()
        checkDailyReset()
        
        // Start timer
        startTimer()
        
        setupAudioBindings()
        setupNotificationObserver()
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopTimer()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.startTimer()
            self?.onAppDidBecomeActive()
        }
    }
    
    // Deprecated: Logic moved to PetDataManager
    // static func loadStatusFromDisk() -> PetStatus { ... }
    
    private func setupStateMachine() {
        let states: [GKState] = [
            IdleState(viewModel: self),
            ExpectingState(viewModel: self),
            InteractionState(viewModel: self),
            GroomingState(viewModel: self),
            FeedingState(viewModel: self),
            DrinkingState(viewModel: self),
            PlayingState(viewModel: self),
            CleaningState(viewModel: self),
            SleepingState(viewModel: self),
            WorkingState(viewModel: self)
        ]
        videoStateMachine = GKStateMachine(states: states)
        // 初始状态
        videoStateMachine.enter(IdleState.self)
    }
    
    func updateVideoState(videoName: String, isLooping: Bool) {
        let actualFileName = getCharacterVideoName(action: videoName)
        
        if self.currentVideoName != videoName || self.currentVideoFileName != actualFileName || self.isCurrentLooping != isLooping {
            withAnimation {
                self.currentVideoName = videoName
                self.currentVideoFileName = actualFileName
                self.isCurrentLooping = isLooping
            }
        }
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(forName: Notification.Name("PetStatusDidUpdateExternally"), object: nil, queue: .main) { [weak self] _ in
            self?.reloadStatus()
        }
    }
    
    func reloadStatus() {
        // Reload from Manager (Source of Truth)
        let newStatus = PetDataManager.shared.status
        // 只更新货币，避免覆盖运行时的其他状态（如饥饿度等瞬时变化）
        self.status.fishCoin = newStatus.fishCoin
        self.status.meowCoin = newStatus.meowCoin
        self.status.boneCoin = newStatus.boneCoin
        // 也可以选择完全重载，视需求而定
    }
    
    private func setupAudioBindings() {
        audioSubscription = AudioManager.shared.$interactionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleAudioStateChange(state)
            }
        
        AudioManager.shared.$recognizedText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.recognizedSpeechText = text
                if !text.isEmpty {
                    self?.scheduleSpeechBubbleClear()
                }
            }
            .store(in: &cancellables)
            
        // Handle Speech Completion (Wait for TTS to finish before listening again)
        PetVoiceManager.shared.$isSpeaking
            .receive(on: DispatchQueue.main)
            .dropFirst() // Ignore initial value
            .sink { [weak self] isSpeaking in
                if !isSpeaking {
                    // TTS Finished -> Restart Listening if Interaction is enabled
                    if AudioManager.shared.isInteractionEnabled {
                        // Delay slightly to avoid picking up trailing audio
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            AudioManager.shared.restartListening()
                        }
                    }
                } else {
                    // TTS Started -> Update state to Playing (Show speaking animation)
                    // 修改：只有 Echo 模式（AudioManager 驱动）才播放说话动画
                    // TTS（AI 对话、随机互动）不触发 Playing 状态，从而不播放说话动画
                    // AudioManager.shared.interactionState = .playing
                }
            }
            .store(in: &cancellables)
            
        // Handle Recording Finish (Trigger AI or Echo)
        AudioManager.shared.onRecordingFinished = { [weak self] text in
            guard let self = self else { return }
            
            if self.isAIMode {
                // AI 模式：发送给 DeepSeek
                self.debugTriggerDialogue(text: text)
            } else {
                // 复述模式：默认行为 (已在 AudioManager 中处理)
                // 这里不需要做任何事，因为 AudioManager 会自动播放录音
                // 但我们可以在这里更新字幕
                // 实际上 AudioManager 已经更新了 recognizedSpeechText
            }
        }
    }
    
    private func handleAudioStateChange(_ state: PetInteractionState) {
        // 根据音频状态更新宠物动画
        switch state {
        case .preparing, .listening, .recording, .processing:
            // 倾听、录音、处理中都保持倾听状态
            // 允许从 idle 或 说话状态(talking) 切换过来，形成闭环
             if currentState == .idle || (currentState == .interacting && currentVideoName == PetVideoPaths.talking) {
                 changeState(to: .expecting, videoName: PetVideoPaths.listening)
             }
        case .playing:
            // 检查回音彩蛋
            if let eggVideo = currentBehavior.getEchoEgg(text: recognizedSpeechText) {
                // 播放彩蛋 (不可打断由 forceLoop=false + 非 talking 状态保证)
                changeState(to: .interacting, videoName: eggVideo, forceLoop: false)
            } else {
                // 说话时（播放变音）
                changeState(to: .interacting, videoName: PetVideoPaths.talking, forceLoop: true)
            }
        case .idle:
            // 只有当当前是倾听或说话状态时，才切回 idle
            // 避免打断其他状态（如吃饭、睡觉）
            if currentState == .expecting || (currentState == .interacting && currentVideoName == PetVideoPaths.talking) {
                changeState(to: .idle)
            }
        }
    }
    

    
    // MARK: - Lifecycle
    
    private var isViewVisible: Bool = true
    
    func onViewAppear() {
        isViewVisible = true
        startTimer()
        calculateOfflineDecay()
        checkDailyReset()
    }
    
    func onViewDisappear() {
        isViewVisible = false
        stopTimer()
        saveStatus() // 离开页面时保存
    }
    
    func onAppDidBecomeActive() {
        calculateOfflineDecay()
        checkDailyReset()
        if isViewVisible {
            startTimer()
        }
    }
    
    func onAppDidEnterBackground() {
        saveStatus()
        stopTimer()
    }
    
    // MARK: - Debug
    func debugTriggerDialogue(text: String) {
        // 取消旧的沉默计时器
        silenceFeedbackTimer?.invalidate()
        silenceFeedbackTimer = nil
        
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 检查是否为有效语音（过滤空字符串和仅包含标点符号的情况）
        if cleanText.isEmpty {
            print("Detected silence/noise. Waiting 30s before triggering feedback...")
            // 30s 后触发“怎么不说话”逻辑
            silenceFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                self?.handleSilenceTimeout()
            }
            return
        }
        
        // 模拟语音识别结果
        self.recognizedSpeechText = text
        scheduleSpeechBubbleClear()
        
        // 1. 优先检查回音彩蛋 (Priority Check for Easter Eggs)
        // 如果触发了彩蛋，直接播放并跳过 AI 请求
        if let eggVideo = currentBehavior.getEchoEgg(text: text) {
            changeState(to: .interacting, videoName: eggVideo, forceLoop: false)
            return
        }
        
        // 2. 尝试使用 AI 回复
        if let ai = aiService {
            guard VIPManager.shared.isVIP else {
                presentSpeechVIPUpsell(for: .remoteChat)
                return
            }

            Task {
                // 显示加载状态 (可选)
                // await MainActor.run { self.recognizedSpeechText += "..." }

                let prompt = buildPromptForSpeechInput(text, ai: ai)
                let response = await ai.sendMessage(prompt, displayText: text)
                
                await MainActor.run {
                    // 更新字幕为 AI 的回复
                    self.recognizedSpeechText = response.text
                    scheduleSpeechBubbleClear()
                    
                    // 处理 AI 指令
                    if let action = response.imageName {
                         handleAIAction(action)
                    }
                }
            }
            return
        }
        
        // (Fallback) 如果没有 AI 服务，再次检查彩蛋（虽然上面已经检查过了，但为了逻辑完整保留或移除）
        // 这里可以直接移除，因为上面已经 return 了。
        // 但为了保持原有结构，我们假设如果走到这里，说明既没有彩蛋也没有 AI。
    }
    
    // 处理长时间沉默
    private func handleSilenceTimeout() {
        print("Silence timeout triggered.")
        guard let ai = aiService else { return }
        guard VIPManager.shared.isVIP else {
            presentSpeechVIPUpsell(for: .remoteChat)
            return
        }
        
        Task {
            // 发送一个特殊的提示给 AI，让它主动发起对话
            let seed = "用户一直看着你但没有说话，可能在发呆或环境吵听不清。请主动关心并轻轻开启话题。"
            let prompt = buildPromptForSpeechInput(seed, ai: ai, moduleOverride: .mood)
            
            // 这里的 displayText 会显示在聊天记录中，显示 "..." 表示沉默
            let response = await ai.sendMessage(prompt, displayText: "...")
            
            await MainActor.run {
                self.recognizedSpeechText = response.text
                scheduleSpeechBubbleClear()
                
                if let action = response.imageName {
                     handleAIAction(action)
                }
            }
        }
    }

    private func presentSpeechVIPUpsell(for feature: PetChatPremiumFeature) {
        recognizedSpeechText = feature.upsellText(petName: status.displayName)
        scheduleSpeechBubbleClear()
    }

    private func buildPromptForSpeechInput(
        _ text: String,
        ai: PetAIService,
        moduleOverride: PetConversationModule? = nil
    ) -> String {
        let character = PetDataManager.shared.getCurrentPetCharacter()
        let persona = PetPersonaRegistry.profile(for: character.aiRole, petName: status.displayName)
        let module = moduleOverride ?? PetChatIntentRouter.detect(from: text).module
        let recentAssistantReplies = PetGenerativePromptBuilder.recentAssistantReplies(
            from: ai.uiMessages,
            isUser: \.isUser,
            text: \.text
        )

        return PetGenerativePromptBuilder.buildPrompt(
            input: .init(
                userQuery: text,
                wardrobeContextBlock: nil,
                persona: persona,
                module: module,
                recentAssistantReplies: recentAssistantReplies
            )
        )
    }
    
    private func handleAIAction(_ action: String) {
        var videoName: String?
        
        switch action {
        case "happy_cat", "happy_dog":
            videoName = PetVideoPaths.enjoy
        case "playful_cat", "playful_dog":
            videoName = PetVideoPaths.playing
        case "sad_cat", "sad_dog":
            videoName = PetVideoPaths.listening // 暂时用聆听替代委屈
        case "angry_cat", "angry_dog":
            videoName = PetVideoPaths.angry
        case "sleepy_cat", "sleepy_dog":
            videoName = PetVideoPaths.sleeping
        case "curious_cat", "curious_dog", "thinking_cat", "thinking_dog":
             videoName = PetVideoPaths.attention
        case "cat", "dog":
            videoName = PetVideoPaths.enjoy
        default:
            // 尝试直接匹配
            videoName = action
        }
        
        if let v = videoName {
             changeState(to: .interacting, videoName: v, forceLoop: false)
        }
    }
    
    // MARK: - State Management
    
    // 拖拽物品开始
    func onDragStarted() {
        if currentState == .idle {
            changeState(to: .expecting, videoName: PetVideoPaths.attention)
        }
    }
    
    // 拖拽物品结束（未喂食）
    func onDragEnded() {
        if currentState == .expecting {
            changeState(to: .idle)
        }
    }
    
    // 购买并立即消费（拖拽购买）
    func purchaseAndConsumeItem(_ item: PetItemDefinition) {
        let finalPrice = priceForPetShopItem(item)

        // 0. 检查精力是否足够 (如果道具消耗精力)
        if let energyCost = item.energyCost, energyCost > 0 {
             if status.energy < Double(energyCost) {
                 showFloatingText("\(status.displayName)太累了，不想玩...", style: .warning)
                 return
             }
        }
        
        // 1. 检查钱够不够
        let canAfford: Bool
        switch item.petCurrency {
        case .fishCoin:
            canAfford = status.fishCoin >= finalPrice
        case .meowCoin:
            canAfford = status.meowCoin >= finalPrice
        case .boneCoin:
            canAfford = status.boneCoin >= finalPrice
        }
        
        guard canAfford else {
            presentShopFundingPrompt(for: item.petCurrency, itemName: item.name)
            return
        }
        
        // 2. 扣钱
        switch item.petCurrency {
        case .fishCoin:
            status.fishCoin -= finalPrice
        case .meowCoin:
            guard StoreManager.spendMeowCoins(finalPrice, in: &status) else {
                presentFundingFlow(for: .meowCoin)
                return
            }
        case .boneCoin:
            status.boneCoin -= finalPrice
        }
        
        // 显示扣款提示 (先显示扣款，再显示属性增加)
        if item.petCurrency == .meowCoin {
            showFloatingText("-\(finalPrice)", style: .meowCoin)
        } else if item.petCurrency == .boneCoin {
            showFloatingText("-\(finalPrice)", style: .boneCoin)
        } else {
            showFloatingText("-\(finalPrice)", style: .fishCoin)
        }
        
        // 3. 消费效果 (这里不经过背包，直接产生效果)
        // 增加库存只是为了记录？或者直接跳过库存？
        // 既然是拖拽给宠物吃，就不加库存了，直接产生效果。
        // 但为了逻辑一致性，我们可以临时加库存然后马上 consume，或者提取 consume 的核心逻辑。
        // 这里为了简单，直接复用 consumeItem 的逻辑，但要注意 consumeItem 会扣库存。
        // 所以先加库存
        status.inventory[item.id, default: 0] += 1
        
        // 4. 消费
        consumeItem(item)
        
        saveStatus()
    }
    
    // 兼容旧代码
    func purchaseAndConsumeItem(_ itemType: PetItemType) {
        if let def = PetConfigManager.shared.getItem(byId: itemType.configId) {
            purchaseAndConsumeItem(def)
        }
    }
    
    // 拖拽喂食/饮水成功
    func consumeItem(_ item: PetItemDefinition) {
        // 特殊道具不能直接食用
        if item.id == "renameCard" {
            showFloatingText("这个不能吃哦", style: .warning)
            return
        }
        
        // 精力药丸
        if item.id == "energyPill" {
            // 扣除物品
            guard let count = status.inventory[item.id], count > 0 else { return }
            status.inventory[item.id] = count - 1
            
            // 恢复精力
            let oldEnergy = status.energy
            status.energy = min(100, status.energy + item.recoveryValue)
            let recovered = status.energy - oldEnergy
            
            // 稍微加点心情
            status.mood = min(100, status.mood + 5)
            
            // 提示
            if recovered > 0 {
                showFloatingText("精力 +\(Int(recovered))", style: .energy)
            } else {
                showFloatingText("精力已满", style: .energy)
            }
            
            saveStatus()
            return
        }
        
        // 检查精力是否足够 (如果道具消耗精力)
        if let energyCost = item.energyCost, energyCost > 0 {
             if status.energy < Double(energyCost) {
                 showFloatingText("\(status.displayName)太累了，不想玩...", style: .warning)
                 return
             }
        }
        
        // 扣除物品
        guard let count = status.inventory[item.id], count > 0 else { return }
        status.inventory[item.id] = count - 1
        
        if item.isToy {
            // 玩具：消耗精力，大幅增加心情
            let energyCost = Double(item.energyCost ?? 0)
            status.energy = max(0, status.energy - energyCost)
            status.mood = min(100, status.mood + item.recoveryValue)
            changeState(to: .playing, videoName: PetVideoPaths.playing)
            
            // 提示
            if energyCost > 0 {
                showFloatingText("精力 -\(Int(energyCost))", style: .energy)
            }
            showFloatingText("心情 +\(Int(item.recoveryValue))", style: .mood)
        } else {
            // 食物/水
            // 增加属性
            let moodRecovery = item.recoveryValue * 0.2 // 恢复心情（食物效果的 20%）
            status.mood = min(100, status.mood + moodRecovery)
            
            if item.isDrink {
                status.hunger = min(100, status.hunger + item.recoveryValue)
                changeState(to: .drinking, videoName: PetVideoPaths.drinking)
            } else {
                status.hunger = min(100, status.hunger + item.recoveryValue)
                
                // 检查喂食彩蛋
                if let eggVideo = currentBehavior.getFeedingEgg(item: item) {
                    changeState(to: .eating, videoName: eggVideo, forceLoop: false)
                } else {
                    // 默认使用 eatingCatFood 作为通用进食动画
                    var video = PetVideoPaths.eatingCatFood
                    
                    if item.id == "cannedFood" {
                        video = PetVideoPaths.eatingCanned
                    }
                    // 其他食物 (如 catRice, catStrip, rawMeat 等) 都使用默认的 eatingCatFood
                    
                    changeState(to: .eating, videoName: video)
                }
            }
            
            // 提示属性增加
            if item.recoveryValue > 0 {
                if item.isDrink {
                    // 饮水可能同时增加饱食度（如果是奶）或者只是解渴？当前逻辑是加 hunger
                    // 但通常水是解渴。这里假设 hunger 也代表渴度。
                    showFloatingText("饱食度 +\(Int(item.recoveryValue))", style: .hunger)
                } else {
                    showFloatingText("饱食度 +\(Int(item.recoveryValue))", style: .hunger)
                }
            }
            if moodRecovery >= 1 {
                showFloatingText("心情 +\(Int(moodRecovery))", style: .mood)
            }
        }
        
        saveStatus()
    }
    
    // 兼容旧代码
    func consumeItem(_ itemType: PetItemType) {
        if let def = PetConfigManager.shared.getItem(byId: itemType.configId) {
            consumeItem(def)
        }
    }
    
    // MARK: - Touch Interaction (Long Press Support)
    
    private var isTouching = false
    private var touchStartTime: Date?
    private var touchReleaseWorkItem: DispatchWorkItem?
    
    // 开始触摸（按下）
    // 长按时一直播放对应动画，循环播放
    func startTouching(at location: CGPoint, in size: CGSize) {
        // 1. 如果有待执行的“松开”任务，立即取消，保持视频循环播放（视为连续点击）
        if let item = touchReleaseWorkItem {
            item.cancel()
            touchReleaseWorkItem = nil
        }
        
        guard !isTouching else { return }
        isTouching = true
        touchStartTime = Date()
        
        let isUpper = location.y < size.height / 2
        
        // 设置 State Context
        if let state = videoStateMachine.state(forClass: InteractionState.self) {
            state.setContext(isHead: isUpper, mood: status.mood)
        }
        
        // 关键：强制设为循环播放
        // 注意：如果是连续点击，changeState 内部会判断如果 videoName 没变，不会重新加载，
        // 并且 forceLoop 为 true 会保持/重新设置为循环模式。
        changeState(to: .interacting, forceLoop: true)
    }
    
    // 结束触摸（松开）
    // 结算算一次点击，停止循环（自然播放完当前次后切回 idle）
    func stopTouching() {
        guard isTouching else { return }
        isTouching = false
        
        // 计算按下时长
        let duration = Date().timeIntervalSince(touchStartTime ?? Date())
        
        // 只有短按 (< 0.3s) 才触发点击反馈 (心情+5)
        if duration < 0.3 {
            // 结算心情 (每次完整的短按算一次)
            let moodIncrease = 5.0
            status.mood = min(100, status.mood + moodIncrease)
            showFloatingText("心情 +\(Int(moodIncrease))", style: .mood)
            
            // 如果触发了生气视频，额外提示
            if currentVideoName == PetVideoPaths.angry {
                 showFloatingText("别碰我！", style: .warning)
                 // 生气语音
                 Task { @MainActor in
                     PetVoiceManager.shared.speak("别碰我！", for: self.currentPet.aiRole)
                 }
            } else {
                // 随机撒娇语音 (增加互动感)
                let interactions = ["蹭蹭~", "喵~", "主人最好了", "好舒服喵", "还要摸摸"]
                let randomText = interactions.randomElement() ?? "喵~"
                let localizedText = currentPet.localizedCatchphraseText(randomText)
                Task { @MainActor in
                    PetVoiceManager.shared.speak(localizedText, for: self.currentPet.aiRole)
                }
            }
            
            saveStatus()
        }
        
        // 关键：延迟取消循环，实现“连续点击不打断”
        // 创建一个新的任务，延迟 0.3 秒执行
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // 真正执行停止循环
            // PetVideoPlayer 监听到 isCurrentLooping 变 false 后，会停止 Looper，并监听播放结束通知。
            // 当视频播放结束时，会调用 onAnimationFinished，从而切回 idle。
            self.isCurrentLooping = false
            self.touchReleaseWorkItem = nil
        }
        
        self.touchReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // 兼容旧代码
    func handleTouch(at location: CGPoint, in size: CGSize) {
        // 旧的一次性点击逻辑，现在改为短按触发 start + stop
        startTouching(at: location, in: size)
        
        // 延迟一小段时间模拟短按，确保动画能开始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.stopTouching()
        }
    }
    
    // 兼容旧代码
    func pet() {
        // 默认模拟摸头
        handleTouch(at: CGPoint(x: 0, y: 0), in: CGSize(width: 100, height: 100))
    }
    
    func clean() {
        // 如果是休息状态，且精力 >= 20，允许打断
        let canInterruptSleep = currentState == .sleeping && status.energy >= 20
        
        guard currentState == .idle || canInterruptSleep else {
            print("DEBUG: clean blocked, current state: \(currentState), energy: \(status.energy)")

            let petName = status.displayName
            let message: String
            switch currentState {
            case .sleeping:
                if status.energy < 20 {
                    message = "\(petName)太累了，需要休息~"
                } else {
                    message = "\(petName)正在休息，请稍后再来~"
                }
            case .working:
                message = "\(petName)正在努力打工，不能洗澡哦~"
            case .eating, .drinking:
                message = "\(petName)正在用餐，请稍等~"
            case .playing:
                message = "\(petName)玩得正开心呢~"
            case .expecting:
                message = "\(petName)正在期待你的投喂呢~"
            default:
                message = "\(petName)正忙着呢~ (\(currentState.rawValue))"
            }
            
            showFloatingText(message, style: .warning)
            return
        }
        
        let cost = 20
        let cleaningCurrency: PetCurrency = currentPet == .maomao ? .boneCoin : .fishCoin

        let canAffordCleaning: Bool
        switch cleaningCurrency {
        case .fishCoin:
            canAffordCleaning = status.fishCoin >= cost
        case .boneCoin:
            canAffordCleaning = status.boneCoin >= cost
        case .meowCoin:
            canAffordCleaning = status.meowCoin >= cost
        }

        if canAffordCleaning {
            switch cleaningCurrency {
            case .fishCoin:
                status.fishCoin -= cost
                showFloatingText("-\(cost)", style: .fishCoin)
            case .boneCoin:
                status.boneCoin -= cost
                showFloatingText("-\(cost)", style: .boneCoin)
            case .meowCoin:
                guard StoreManager.spendMeowCoins(cost, in: &status) else {
                    presentFundingFlow(for: .meowCoin)
                    return
                }
                showFloatingText("-\(cost)", style: .meowCoin)
            }
            
            // 更新状态
            let oldHygiene = status.hygiene
            status.hygiene = 100 // 直接加满
            let addedHygiene = 100.0 - oldHygiene
            
            status.mood = min(100, status.mood + 10) // 清洁也恢复心情
            saveStatus()
            
            // 切换状态
            var video = PetVideoPaths.bathingHappy
            if status.mood < 50 {
                if Double.random(in: 0...1) < 0.6 {
                    video = PetVideoPaths.bathingBoring
                } else {
                    video = PetVideoPaths.bathingHappy
                }
            } else if status.mood > 90 {
                if Double.random(in: 0...1) < 0.9 {
                    video = PetVideoPaths.bathingHappy
                } else {
                    video = PetVideoPaths.bathingBoring
                }
            } else {
                // 50 <= mood <= 90
                if Double.random(in: 0...1) < 0.6 {
                    video = PetVideoPaths.bathingHappy
                } else {
                    video = PetVideoPaths.bathingBoring
                }
            }
            changeState(to: .cleaning, videoName: video)
            
            // 提示属性变化
            if addedHygiene > 0 {
                showFloatingText("清洁度 +\(Int(addedHygiene))", style: .hygiene)
            } else {
                showFloatingText("清洁度已满", style: .hygiene)
            }
            showFloatingText("心情 +10", style: .mood)
        } else {
            presentFundingFlow(for: cleaningCurrency)
        }
    }
    
    func onAnimationFinished() {
        // 保护逻辑：特定状态下忽略播放结束信号，并强制维持循环
        // 这可以防止因视频文件问题或播放器状态异常导致的意外切回 idle
        if currentState == .working || currentState == .sleeping {
            print("Warning: Video finished in \(currentState) state. Ignoring finish signal.")
            return
        }

        // Return to idle after action finished
        // 只有非循环动画才自动切回 idle
        if !isCurrentLooping && currentState != .idle {
            changeState(to: .idle)
        }
    }
    
    private func changeState(to newState: PetState, videoName: String? = nil, forceLoop: Bool? = nil) {
        withAnimation {
            currentState = newState
            
            // 更新 Animation State Machine
            switch newState {
            case .idle:
                videoStateMachine.enter(IdleState.self)
                
            case .expecting:
                if let v = videoName, let state = videoStateMachine.state(forClass: ExpectingState.self) {
                    state.setVideoName(v)
                }
                videoStateMachine.enter(ExpectingState.self)
                
            case .interacting:
                if videoName == PetVideoPaths.grooming {
                    videoStateMachine.enter(GroomingState.self)
                } else {
                    if let v = videoName, let state = videoStateMachine.state(forClass: InteractionState.self) {
                         state.setExplicitVideoName(v)
                    }
                    // 假设 context 已经在 startTouching 里设置好了
                    videoStateMachine.enter(InteractionState.self)
                }
                
            case .eating:
                 if let v = videoName, let state = videoStateMachine.state(forClass: FeedingState.self) {
                     // 检查是否是绝对路径
                     if v.hasPrefix("/") {
                         // 如果是绝对路径，我们可能需要一个新的方法来设置，或者利用现有的
                         // 这里 FeedingState.setFoodType 只接受简单的类型字符串
                         // 我们可以临时扩展 FeedingState 或者直接在这里强制设置 currentVideoName
                         // 但 StateMachine 会覆盖它。
                         // 最好的办法是让 FeedingState 支持显式视频路径
                         // 不过现在 StateMachine 已经有点复杂了。
                         // 让我们看下面 changeState 结束后的处理。
                         // 实际上，videoName 参数会被传递给 currentVideoName
                     } else if v == PetVideoPaths.eatingCanned {
                         state.setFoodType("cannedFood")
                     } else {
                         state.setFoodType("catFood")
                     }
                 }
                 videoStateMachine.enter(FeedingState.self)
                 
            case .drinking:
                videoStateMachine.enter(DrinkingState.self)
                
            case .playing:
                videoStateMachine.enter(PlayingState.self)
                
            case .sleeping:
                videoStateMachine.enter(SleepingState.self)
                
            case .cleaning:
                videoStateMachine.enter(CleaningState.self)
                
            case .working:
                videoStateMachine.enter(WorkingState.self)
            }
            
            // 关键修正：确保 videoName 优先级最高，覆盖 StateMachine 的默认值
            // StateMachine.enter 会设置 videoName，但我们传入的 videoName 应该是最终决定的
            if let v = videoName {
                self.currentVideoName = v
            }
            
            // 兼容 forceLoop (如果外部强制指定，覆盖 State 的默认设置)
            if let force = forceLoop {
                isCurrentLooping = force
            }
            
            // 重新计算文件名 (处理前缀)
            if self.currentVideoName.hasPrefix("/") {
                self.currentVideoFileName = self.currentVideoName
            } else {
                self.currentVideoFileName = getCharacterVideoName(action: self.currentVideoName)
            }
        }
    }
    
    // MARK: - Economy & Inventory

    func priceForPetShopItem(_ item: PetItemDefinition) -> Int {
        VIPManager.shared.petShopPrice(for: item.price)
    }

    func savingsForPetShopItem(_ item: PetItemDefinition) -> Int {
        max(0, item.price - priceForPetShopItem(item))
    }
    
    func purchaseItem(_ item: PetItemDefinition) -> Bool {
        let finalPrice = priceForPetShopItem(item)

        switch item.petCurrency {
        case .fishCoin:
            if status.fishCoin >= finalPrice {
                status.fishCoin -= finalPrice
                status.inventory[item.id, default: 0] += 1
                saveStatus()
                showFloatingText("-\(finalPrice)", style: .fishCoin)
                return true
            } else {
                presentShopFundingPrompt(for: .fishCoin, itemName: item.name)
            }
        case .meowCoin:
            if StoreManager.spendMeowCoins(finalPrice, in: &status) {
                status.inventory[item.id, default: 0] += 1
                saveStatus()
                showFloatingText("-\(finalPrice)", style: .meowCoin)
                return true
            } else {
                presentShopFundingPrompt(for: .meowCoin, itemName: item.name)
            }
        case .boneCoin:
            if status.boneCoin >= finalPrice {
                status.boneCoin -= finalPrice
                status.inventory[item.id, default: 0] += 1
                saveStatus()
                showFloatingText("-\(finalPrice)", style: .boneCoin)
                return true
            } else {
                presentShopFundingPrompt(for: .boneCoin, itemName: item.name)
            }
        }
        return false
    }

    private func presentShopFundingPrompt(for currency: PetCurrency, itemName: String) {
        presentedFundingSheet = nil
        presentedFundingPrompt = makeFundingPrompt(for: currency, itemName: itemName)
    }

    private func presentFundingFlow(for currency: PetCurrency) {
        presentedFundingPrompt = nil
        switch currency {
        case .meowCoin:
            showFloatingText("喵币不足", style: .warning)
            presentedFundingSheet = .meowCoinStore
        case .fishCoin:
            showFloatingText("鱼币不足", style: .warning)
            presentedFundingSheet = .currencyExchange(.boneToFish)
        case .boneCoin:
            showFloatingText("骨头币不足", style: .warning)
            presentedFundingSheet = .currencyExchange(.fishToBone)
        }
    }

    private func makeFundingPrompt(for currency: PetCurrency, itemName: String) -> PetFundingPrompt {
        switch currency {
        case .meowCoin:
            return PetFundingPrompt(
                currency: .meowCoin,
                title: "喵币不够啦",
                message: "想把\(itemName)带回家，还差一点喵币。先去充值一下，再回来继续逛萌宠商店吧。",
                actionTitle: "去充喵币",
                destination: .meowCoinStore
            )
        case .fishCoin:
            return PetFundingPrompt(
                currency: .fishCoin,
                title: "鱼币不够啦",
                message: "想买\(itemName)，还差一点鱼币。先把骨头币换成鱼币，再回来继续挑吧。",
                actionTitle: "去换鱼币",
                destination: .currencyExchange(.boneToFish)
            )
        case .boneCoin:
            return PetFundingPrompt(
                currency: .boneCoin,
                title: "骨头币不够啦",
                message: "想买\(itemName)，还差一点骨头币。先把鱼币换成骨头币，再回来继续挑吧。",
                actionTitle: "去换骨头币",
                destination: .currencyExchange(.fishToBone)
            )
        }
    }

    func dismissFundingPrompt() {
        presentedFundingPrompt = nil
    }

    func continueFundingPromptFlow() {
        guard let destination = presentedFundingPrompt?.destination else { return }
        presentedFundingPrompt = nil
        presentedFundingSheet = destination
    }

    func dismissFundingSheet() {
        presentedFundingSheet = nil
    }
    
    // 货币兑换：鱼币 -> 骨头币
    func exchangeFishToBone(amount: Int) -> Bool {
        guard status.fishCoin >= amount else {
            showFloatingText("鱼币不足", style: .warning)
            return false
        }
        
        status.fishCoin -= amount
        status.boneCoin += amount // 1:1 汇率
        saveStatus()
        
        showFloatingText("-\(amount)", style: .fishCoin)
        showFloatingText("+\(amount)", style: .boneCoin)
        return true
    }
    
    // 货币兑换：骨头币 -> 鱼币 (可选，虽然需求没明确说要换回去，但通常互通是双向的)
    func exchangeBoneToFish(amount: Int) -> Bool {
        guard status.boneCoin >= amount else {
            showFloatingText("骨头币不足", style: .warning)
            return false
        }
        
        status.boneCoin -= amount
        status.fishCoin += amount // 1:1 汇率
        saveStatus()
        
        showFloatingText("-\(amount)", style: .boneCoin)
        showFloatingText("+\(amount)", style: .fishCoin)
        return true
    }
    
    func purchaseItem(_ itemType: PetItemType) -> Bool {
        if let def = PetConfigManager.shared.getItem(byId: itemType.configId) {
            return purchaseItem(def)
        }
        return false
    }
    
    func earnFishCoin(amount: Int) {
        checkDailyReset()
        
        let remainingQuota = PetStatus.dailyFishCoinLimit - status.dailyFishCoinEarned
        let actualEarned = min(amount, remainingQuota)
        
        if actualEarned > 0 {
            status.fishCoin += actualEarned
            status.dailyFishCoinEarned += actualEarned
            saveStatus()
        }
    }
    
    // 调试用：无视上限增加鱼币
    func debugAddFishCoin(amount: Int) {
        status.fishCoin += amount
        saveStatus()
    }
    
    // 充值喵币 (模拟)
    func rechargeMeowCoin(amount: Int) {
        status.meowCoin += amount
        saveStatus()
    }
    
    private func checkDailyReset(currentTime: Date = Date()) {
        let calendar = Calendar.current
        if !calendar.isDate(currentTime, inSameDayAs: status.lastDailyResetDate) {
            status.dailyFishCoinEarned = 0
            status.lastDailyResetDate = currentTime
            saveStatus()
        }
    }
    
    // MARK: - UI Effects
    
    private var pendingBubbleQueue: [(String, FloatingTextStyle)] = []
    private var isProcessingBubbles = false
    
    func showFloatingText(_ text: String, style: FloatingTextStyle) {
        // 加入队列
        pendingBubbleQueue.append((text, style))
        
        // 如果当前没有在处理队列，开始处理
        if !isProcessingBubbles {
            processNextBubble()
        }
    }
    
    private func processNextBubble() {
        guard !pendingBubbleQueue.isEmpty else {
            isProcessingBubbles = false
            return
        }
        
        isProcessingBubbles = true
        let (text, style) = pendingBubbleQueue.removeFirst()
        
        // 限制最大数量，防止内存暴涨
        if floatingTexts.count >= 6 {
            floatingTexts.removeFirst()
        }
        
        // 生成随机偏移，避免重叠
        // 分布在两边，避开中间区域（避免遮挡小猫视频）
        let isLeft = Bool.random()
        // 中间保留约 200pt 的空隙 (-100 ~ 100)，气泡分布在两边
        let randomX = isLeft ? CGFloat.random(in: -150...(-100)) : CGFloat.random(in: 100...150)
        let randomY = CGFloat.random(in: -60...40) // 上下分布随机些，稍微偏上一点(-60)给下方留空间
        
        let newData = FloatingTextData(
            text: text,
            style: style,
            offset: CGSize(width: randomX, height: randomY)
        )
        floatingTexts.append(newData)
        
        // 自动移除 (稍微延长一点时间，配合 View 层的进出动画)
        // 自适应时长：基础 2s + 每字 0.2s，最长 10s
        let duration = min(10.0, max(2.0, 2.0 + Double(text.count) * 0.2))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            // 只有当该 ID 还在数组中时才移除 (避免已经被 max count 移除导致的无效操作，虽无害但浪费)
            self?.floatingTexts.removeAll(where: { $0.id == newData.id })
        }
        
        // 调度下一个气泡
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.processNextBubble()
        }
    }
    
    // 兼容旧代码的方法
    func showFloatingText(_ text: String, color: Color) {
        showFloatingText(text, style: .custom(color))
    }
    
    // MARK: - Status Management
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateStatus()
            // 更新状态机 (deltaTime: 1.0)
            self.videoStateMachine.update(deltaTime: 1.0)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Job System
    private var jobIncomeAccumulator: Double = 0.0
    
    func startJob(_ job: PetJob) {
        if status.currentJob != .none {
            stopJob()
        }
        
        status.currentJob = job
        status.jobStartTime = Date()
        status.currentJobEarnedFishCoin = 0 // 重置打工收益计数器
        jobIncomeAccumulator = 0.0
        
        // 播放换装动画（一次性），使用 interacting 状态作为临时载体
        // 播放完后会自动切回 idle，然后 processTimePassage 会检测到 isWorking 并切到 WorkingState (播放 idle)
        changeState(to: .interacting, videoName: PetVideoPaths.dressingWork, forceLoop: false)
        
        saveStatus()
        
        if job != .none {
            showFloatingText("开始打工: \(job.rawValue)", style: .custom(.blue))
        }
    }
    
    func stopJob(isInterrupted: Bool = false) {
        guard status.currentJob != .none else { return }
        
        let job = status.currentJob
        status.currentJob = .none
        status.jobStartTime = nil
        jobIncomeAccumulator = 0.0
        saveStatus()
        
        if isInterrupted {
            let video = currentBehavior.getWorkInterruptedVideo()
            // 播放中断视频
            changeState(to: .interacting, videoName: video, forceLoop: false)
            showFloatingText("被迫停止打工...", style: .warning)
        } else {
            // 正常结束
            let result = currentBehavior.getWorkFinishResult(job: job, status: status)
            
            // 播放结算视频
            changeState(to: .interacting, videoName: result.video, forceLoop: false)
            
            // 显示文案
            showFloatingText(result.message, style: result.success ? .fishCoin : .warning)
        }
    }
    
    private func updateStatus() {
        processTimePassage(timeInterval: 1.0)
    }
    
    /// 核心状态流逝逻辑
    /// - Parameters:
    ///   - timeInterval: 流逝的时间（秒）
    ///   - isOfflineSimulation: 是否是离线模拟（不触发UI和实时保存）
    func processTimePassage(timeInterval: Double, isOfflineSimulation: Bool = false) {
        let calendar = Calendar.current
        // 在线模式下用当前时间，离线模拟模式下基于 lastUpdateTime 递推
        let now = isOfflineSimulation ? status.lastUpdateTime.addingTimeInterval(timeInterval) : Date()
        let currentMinute = calendar.component(.minute, from: now)
        
        // 检查跨天重置 (仅在线或模拟到新的一天时)
        if !isOfflineSimulation || !calendar.isDate(now, inSameDayAs: status.lastDailyResetDate) {
            checkDailyReset(currentTime: now)
        }
        
        // 1. 判定是否处于强制睡觉时间段 (每小时 45-59 分)
        let isFixedSleepTime = currentMinute >= forceSleepMinuteStart
        
        // 2. 判定是否精力耗尽 (昏睡)
        let isExhausted = status.energy <= 0
        
        // 3. 判定是否低精力自动睡觉 (仅在空闲时触发)
        let isLowEnergy = status.energy < sleepThreshold
        
        // 决策当前行为
        var isSleeping = false
        var isWorking = false
        
        // 打工中断检查：精力或者饱食归0则立即停止打工
        let shouldStopWork = status.currentJob != .none && (status.energy <= 0 || status.hunger <= 0)
        
        // 状态判定优先级：打工中断 > 精力耗尽 > 强制休息 > 工作 > 低精力自动休息
        
        if shouldStopWork {
            // 强制停止工作
            if !isOfflineSimulation {
                stopJob(isInterrupted: true)
            } else {
                status.currentJob = .none
                status.jobStartTime = nil
            }
            
            // 如果是因为精力耗尽，则进入睡眠状态
            if isExhausted {
                isSleeping = true
            }
        } else if isExhausted {
            isSleeping = true
        } else if isFixedSleepTime && (currentState == .idle || currentState == .sleeping) {
            // 强制休息时间：仅在空闲或已睡觉时触发，不打断其他动画（工作、互动等）
            isSleeping = true
        } else if status.currentJob != .none {
            // 正常工作时间
            isWorking = true
            // 注意：之前的状态不好判定逻辑已被 shouldStopWork 替代
        } else if isLowEnergy && (currentState == .idle || currentState == .sleeping) {
            // 没有工作，精力低 -> 自动睡觉 (仅在空闲时触发)
            isSleeping = true
        }
        
        // 更新 UI 状态 (仅在线模式)
        if !isOfflineSimulation {
            if isSleeping && currentState != .sleeping {
                changeState(to: .sleeping)
            } else if !isSleeping && currentState == .sleeping {
                // 醒来逻辑优化：优先恢复工作
                if status.currentJob != .none {
                    changeState(to: .working)
                } else if status.energy > 50 {
                    // 只有在非工作状态下，才需要精力门槛避免反复横跳
                    changeState(to: .idle)
                }
            } else if isWorking && currentState != .working && currentState != .interacting && !isSleeping {
                // 确保工作时处于工作状态（除非正在睡觉或正在交互/换装）
                // 这里的 .interacting 包括了换装动画，避免强制打断
                changeState(to: .working)
            } else if !isWorking && currentState == .working {
                // 如果不再工作但状态还是 working，切回 idle
                 changeState(to: .idle)
            }
        }
        
        // 计算属性变化
        if isSleeping {
            // 睡觉：快速恢复精力，恢复心情，消耗饱食/清洁
            status.energy = min(100, status.energy + sleepEnergyRecoveryRate * timeInterval)
            status.mood = min(100, status.mood + sleepMoodRecoveryRate * timeInterval)
            status.hunger = max(0, status.hunger - PetStatus.hungerDecayRate * timeInterval)
            status.hygiene = max(0, status.hygiene - PetStatus.hygieneDecayRate * timeInterval)
        } else if isWorking {
            // 工作：消耗所有属性，增加收入
            let multiplier = status.currentJob.consumptionMultiplier
            
            status.energy = max(0, status.energy - PetStatus.energyDecayRate * multiplier * timeInterval)
            status.mood = max(0, status.mood - PetStatus.moodDecayRate * multiplier * timeInterval)
            status.hunger = max(0, status.hunger - PetStatus.hungerDecayRate * multiplier * timeInterval)
            status.hygiene = max(0, status.hygiene - PetStatus.hygieneDecayRate * multiplier * timeInterval)
            
            // 结算收益
            let incomePerSecond = Double(status.currentJob.incomeRate) / 60.0
            jobIncomeAccumulator += incomePerSecond * timeInterval
            
            if jobIncomeAccumulator >= 1.0 {
                let coinToAdd = Int(jobIncomeAccumulator)
                if !isOfflineSimulation {
                     // 在线模式：调用 earnFishCoin (含每日上限检查)
                     // 注意：我们需要在 earnFishCoin 成功后再累加 currentJobEarnedFishCoin
                     // 但 earnFishCoin 目前没有返回值告诉我们要不要加
                     // 所以我们在这里手动处理上限逻辑，或者修改 earnFishCoin 返回实际增加量
                     // 为了简单且安全，我们复用 earnFishCoin 的逻辑，但假设它会处理上限
                     // 这里我们只记录"尝试"增加的量，或者更准确地，我们需要知道实际增加了多少
                     // 让我们直接在这里处理，因为 earnFishCoin 逻辑也比较简单
                     
                     checkDailyReset()
                     let remainingQuota = PetStatus.dailyFishCoinLimit - status.dailyFishCoinEarned
                     let actualEarned = min(coinToAdd, remainingQuota)
                     
                     if actualEarned > 0 {
                         status.fishCoin += actualEarned
                         status.dailyFishCoinEarned += actualEarned
                         status.currentJobEarnedFishCoin += actualEarned // 累加打工收益
                         saveStatus()
                     }
                } else {
                     // 离线模拟直接加，不触发保存
                     let remainingQuota = PetStatus.dailyFishCoinLimit - status.dailyFishCoinEarned
                     let actualEarned = min(coinToAdd, remainingQuota)
                     if actualEarned > 0 {
                         status.fishCoin += actualEarned
                         status.dailyFishCoinEarned += actualEarned
                         status.currentJobEarnedFishCoin += actualEarned // 累加打工收益
                     }
                }
                jobIncomeAccumulator -= Double(coinToAdd)
            }
        } else {
            // 闲置：缓慢恢复精力，消耗心情/饱食/清洁
            status.energy = min(100, status.energy + idleEnergyRecoveryRate * timeInterval)
            // 闲置时心情随时间衰减
            status.mood = max(0, status.mood - PetStatus.moodDecayRate * timeInterval)
            
            status.hunger = max(0, status.hunger - PetStatus.hungerDecayRate * timeInterval)
            status.hygiene = max(0, status.hygiene - PetStatus.hygieneDecayRate * timeInterval)
            
            // 随机洗脸逻辑已移至 IdleState.update
        }
        
        status.lastUpdateTime = now
    }
    
    private func calculateOfflineDecay() {
        let now = Date()
        var simulationTime = status.lastUpdateTime
        
        // 为了防止离线太久导致死循环，如果离线超过 24 小时，只计算最后 24 小时
        let maxSimulationDuration: TimeInterval = 24 * 3600
        if now.timeIntervalSince(simulationTime) > maxSimulationDuration {
            simulationTime = now.addingTimeInterval(-maxSimulationDuration)
            status.lastUpdateTime = simulationTime
        }
        
        // 步进模拟，步长 60 秒 (分钟级精度)
        let step: TimeInterval = 60.0
        
        while simulationTime < now {
            let remaining = now.timeIntervalSince(simulationTime)
            let currentStep = min(step, remaining)
            
            processTimePassage(timeInterval: currentStep, isOfflineSimulation: true)
            
            simulationTime = status.lastUpdateTime
        }
        
        saveStatus()
    }
    
    func saveStatus() {
        PetDataManager.shared.saveStatus(self.status)
    }
    
    func setPetName(_ name: String) {
        let cleanName = name.replacingOccurrences(of: "\"", with: "")
                            .replacingOccurrences(of: "“", with: "")
                            .replacingOccurrences(of: "”", with: "")
        status.petName = cleanName
        saveStatus()
    }
    
    func hasRenameCard() -> Bool {
        return (status.inventory["renameCard"] ?? 0) > 0
    }
    
    func useRenameCard(newName: String) -> Bool {
        guard hasRenameCard() else { return false }
        
        // 消耗改名卡
        status.inventory["renameCard", default: 0] -= 1
        
        // 改名
        setPetName(newName)
        return true
    }
    
    private func requestMicrophonePermission() {
        isMicrophoneEnabled = false
    }
}
