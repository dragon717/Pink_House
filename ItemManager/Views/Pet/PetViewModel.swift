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

enum FloatingTextStyle {
    case warning    // 红色
    case meowCoin   // 闪光的金色，带喵币icon
    case fishCoin   // 闪光的铜色，带鱼币icon
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
        case .hunger: return .orange
        case .hygiene: return .blue
        case .energy: return .green
        case .mood: return .pink
        case .custom(let color): return color
        }
    }
}

class PetViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentState: PetState = .idle
    @Published var currentVideoName: String = "idle"
    @Published var isCurrentLooping: Bool = true // 新增：动态控制当前视频是否循环
    @Published var status: PetStatus
    @Published var floatingTexts: [FloatingTextData] = []
    @Published var recognizedSpeechText: String = ""
    
    // MARK: - Video State Machine
    var videoStateMachine: GKStateMachine!
    
    private var audioSubscription: AnyCancellable?
    
    // MARK: - Settings
    // Deprecated: isMicrophoneEnabled is now managed by AudioManager
    @Published var isMicrophoneEnabled: Bool = false
    
    // MARK: - Private Properties
    private var timer: Timer?
    private let statusKey = "PetStatus_Data"
    
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
        // Initial load
        self.status = PetViewModel.loadStatusFromDisk()
        
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
    
    static func loadStatusFromDisk() -> PetStatus {
        let statusKey = "PetStatus_Data"
        if let data = UserDefaults.standard.data(forKey: statusKey),
           var decoded = try? JSONDecoder().decode(PetStatus.self, from: data) {
            
            // 数据清理：只保留在新配置中存在的物品，遗弃老数据
            var validInv: [String: Int] = [:]
            for (key, count) in decoded.inventory {
                if PetConfigManager.shared.getItem(byId: key) != nil {
                    validInv[key] = count
                }
            }
            decoded.inventory = validInv
            
            return decoded
        } else {
            return PetStatus()
        }
    }
    
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
        if self.currentVideoName != videoName || self.isCurrentLooping != isLooping {
            withAnimation {
                self.currentVideoName = videoName
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
        let newStatus = PetViewModel.loadStatusFromDisk()
        // 只更新货币，避免覆盖运行时的其他状态（如饥饿度等瞬时变化）
        self.status.fishCoin = newStatus.fishCoin
        self.status.meowCoin = newStatus.meowCoin
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
            .assign(to: &$recognizedSpeechText)
    }
    
    private func handleAudioStateChange(_ state: PetInteractionState) {
        // 根据音频状态更新宠物动画
        switch state {
        case .listening, .recording, .processing:
            // 倾听、录音、处理中都保持倾听状态
            // 允许从 idle 或 说话状态(talking) 切换过来，形成闭环
             if currentState == .idle || (currentState == .interacting && currentVideoName == PetVideoPaths.talking) {
                 changeState(to: .expecting, videoName: PetVideoPaths.listening)
             }
        case .playing:
            // 说话时（播放变音）
            changeState(to: .interacting, videoName: PetVideoPaths.talking, forceLoop: true)
        case .idle:
            // 只有当当前是倾听或说话状态时，才切回 idle
            // 避免打断其他状态（如吃饭、睡觉）
            if currentState == .expecting || (currentState == .interacting && currentVideoName == PetVideoPaths.talking) {
                changeState(to: .idle)
            }
        }
    }
    
    deinit {
        stopTimer()
    }
    
    // MARK: - Lifecycle
    
    func onAppDidBecomeActive() {
        calculateOfflineDecay()
        checkDailyReset()
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
        // 0. 检查精力是否足够 (如果道具消耗精力)
        if let energyCost = item.energyCost, energyCost > 0 {
             if status.energy < Double(energyCost) {
                 showFloatingText("\(status.petName ?? "萌宠")太累了，不想玩...", style: .warning)
                 return
             }
        }
        
        // 1. 检查钱够不够
        let canAfford: Bool
        switch item.petCurrency {
        case .fishCoin:
            canAfford = status.fishCoin >= item.price
        case .meowCoin:
            canAfford = status.meowCoin >= item.price
        }
        
        guard canAfford else {
            showFloatingText("余额不足", style: .warning)
            return
        }
        
        // 2. 扣钱
        switch item.petCurrency {
        case .fishCoin:
            status.fishCoin -= item.price
        case .meowCoin:
            status.meowCoin -= item.price
        }
        
        // 显示扣款提示 (先显示扣款，再显示属性增加)
        if item.petCurrency == .meowCoin {
            showFloatingText("-\(item.price)", style: .meowCoin)
        } else {
            showFloatingText("-\(item.price)", style: .fishCoin)
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
                 showFloatingText("\(status.petName ?? "萌宠")太累了，不想玩...", style: .warning)
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
                
                // 默认使用 eatingCatFood 作为通用进食动画
                var video = PetVideoPaths.eatingCatFood
                
                if item.id == "cannedFood" {
                    video = PetVideoPaths.eatingCanned
                } 
                // 其他食物 (如 catRice, catStrip, rawMeat 等) 都使用默认的 eatingCatFood
                
                changeState(to: .eating, videoName: video)
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
            
            let petName = status.petName ?? "萌宠"
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
        
        // 检查鱼币是否足够
        let cost = 20
        if status.fishCoin >= cost {
            // 扣除鱼币
            status.fishCoin -= cost
            showFloatingText("-\(cost)", style: .fishCoin)
            
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
            // 余额不足提示
            showFloatingText("鱼币不足!", style: .warning)
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
                     if v == PetVideoPaths.eatingCanned {
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
            
            // 兼容 forceLoop (如果外部强制指定，覆盖 State 的默认设置)
            if let force = forceLoop {
                isCurrentLooping = force
            }
        }
    }
    
    // MARK: - Economy & Inventory
    
    func purchaseItem(_ item: PetItemDefinition) -> Bool {
        switch item.petCurrency {
        case .fishCoin:
            if status.fishCoin >= item.price {
                status.fishCoin -= item.price
                status.inventory[item.id, default: 0] += 1
                saveStatus()
                showFloatingText("-\(item.price)", style: .fishCoin)
                return true
            } else {
                showFloatingText("余额不足", style: .warning)
            }
        case .meowCoin:
            if status.meowCoin >= item.price {
                status.meowCoin -= item.price
                status.inventory[item.id, default: 0] += 1
                saveStatus()
                showFloatingText("-\(item.price)", style: .meowCoin)
                return true
            } else {
                showFloatingText("余额不足", style: .warning)
            }
        }
        return false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
        jobIncomeAccumulator = 0.0
        
        // 播放换装动画（一次性），使用 interacting 状态作为临时载体
        // 播放完后会自动切回 idle，然后 processTimePassage 会检测到 isWorking 并切到 WorkingState (播放 idle)
        changeState(to: .interacting, videoName: PetVideoPaths.dressingWork, forceLoop: false)
        
        saveStatus()
        
        if job != .none {
            showFloatingText("开始打工: \(job.rawValue)", style: .custom(.blue))
        }
    }
    
    func stopJob() {
        guard status.currentJob != .none else { return }
        
        let jobName = status.currentJob.rawValue
        status.currentJob = .none
        status.jobStartTime = nil
        jobIncomeAccumulator = 0.0
        
        // 如果当前是工作状态，停止工作后切回 idle
        if currentState == .working {
            changeState(to: .idle)
        }
        
        saveStatus()
        
        showFloatingText("结束打工: \(jobName)", style: .custom(.green))
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
        
        // 状态判定优先级：精力耗尽 > 强制休息 > 工作 > 低精力自动休息
        
        if isExhausted {
            isSleeping = true
            // 精力耗尽，强制停止工作（彻底罢工）
            if status.currentJob != .none {
                if !isOfflineSimulation {
                    stopJob()
                    showFloatingText("精力耗尽，强制昏睡！", style: .warning)
                } else {
                    status.currentJob = .none
                    status.jobStartTime = nil
                }
            }
        } else if isFixedSleepTime && (currentState == .idle || currentState == .sleeping) {
            // 强制休息时间：仅在空闲或已睡觉时触发，不打断其他动画（工作、互动等）
            isSleeping = true
        } else if status.currentJob != .none {
            // 正常工作时间
            isWorking = true
            
            // 检查状态是否过低导致停止工作 (罢工)
            if status.hunger < 10 || status.hygiene < 10 || status.mood < 10 {
                isWorking = false
                if !isOfflineSimulation {
                    stopJob()
                    showFloatingText("状态不好，不干了！", style: .warning)
                } else {
                    status.currentJob = .none
                    status.jobStartTime = nil
                }
            }
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
                     earnFishCoin(amount: coinToAdd)
                } else {
                     // 离线模拟直接加，不触发保存
                     let remainingQuota = PetStatus.dailyFishCoinLimit - status.dailyFishCoinEarned
                     let actualEarned = min(coinToAdd, remainingQuota)
                     if actualEarned > 0 {
                         status.fishCoin += actualEarned
                         status.dailyFishCoinEarned += actualEarned
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
        if let encoded = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(encoded, forKey: statusKey)
        }
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
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.isMicrophoneEnabled = false
                    // TODO: Show alert if needed
                }
            }
        }
    }
}
