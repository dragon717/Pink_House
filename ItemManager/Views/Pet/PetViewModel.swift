import SwiftUI
import Combine
import AVFoundation

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
    @Published var status: PetStatus
    @Published var floatingTexts: [FloatingTextData] = []
    @Published var recognizedSpeechText: String = ""
    
    private var audioSubscription: AnyCancellable?
    
    // MARK: - Settings
    // Deprecated: isMicrophoneEnabled is now managed by AudioManager
    @Published var isMicrophoneEnabled: Bool = false
    
    // MARK: - Private Properties
    private var timer: Timer?
    private let statusKey = "PetStatus_Data"
    
    // MARK: - Constants
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
        
        // Calculate offline decay
        calculateOfflineDecay()
        checkDailyReset()
        
        // Start timer
        startTimer()
        
        setupAudioBindings()
        setupNotificationObserver()
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
        case .recording:
            // 如果有专门的倾听动画，可以在这里切换
             if currentState == .idle {
                 changeState(to: .expecting) // 使用 expecting 模拟倾听
             }
        case .playing:
            // 说话时（播放变音）
            // 如果有说话动画，可以在这里切换
            break
        case .idle, .listening, .processing:
            if currentState == .expecting && state == .processing {
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
            changeState(to: .expecting)
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
        
        // 扣除物品
        guard let count = status.inventory[item.id], count > 0 else { return }
        status.inventory[item.id] = count - 1
        
        if item.isToy {
            // 玩具：消耗精力，大幅增加心情
            let energyCost = Double(item.energyCost ?? 0)
            status.energy = max(0, status.energy - energyCost)
            status.mood = min(100, status.mood + item.recoveryValue)
            changeState(to: .playing)
            
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
                changeState(to: .drinking)
            } else {
                status.hunger = min(100, status.hunger + item.recoveryValue)
                changeState(to: .eating)
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
    
    // 抚摸互动
    func pet() {
        let moodIncrease = 5.0
        status.mood = min(100, status.mood + moodIncrease)
        showFloatingText("心情 +\(Int(moodIncrease))", style: .mood)
        saveStatus()
    }
    
    func clean() {
        guard currentState == .idle else { return }
        
        // 检查鱼币是否足够
        let cost = 20
        if status.fishCoin >= cost {
            // 扣除鱼币
            status.fishCoin -= cost
            showFloatingText("-\(cost)", style: .fishCoin)
            
            // 更新状态
            status.hygiene = min(100, status.hygiene + 20)
            status.mood = min(100, status.mood + 10) // 清洁也恢复心情
            saveStatus()
            
            // 切换状态
            changeState(to: .cleaning)
            
            // 提示属性变化
            showFloatingText("清洁度 +20", style: .hygiene)
            showFloatingText("心情 +10", style: .mood)
        } else {
            // 余额不足提示
            showFloatingText("鱼币不足!", style: .warning)
        }
    }
    
    func onAnimationFinished() {
        // Return to idle after action finished
        // 只有非循环动画才自动切回 idle
        if !currentState.isLooping && currentState != .idle {
            changeState(to: .idle)
        }
    }
    
    private func changeState(to newState: PetState) {
        withAnimation {
            currentState = newState
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
                return true
            }
        case .meowCoin:
            if status.meowCoin >= item.price {
                status.meowCoin -= item.price
                status.inventory[item.id, default: 0] += 1
                saveStatus()
                return true
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
        // 增加 X/Y 轴的随机范围，防止多个气泡同时出现时完全重叠
        let randomX = CGFloat.random(in: -50...50)
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
            self?.updateStatus()
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
        
        // 切换到工作状态
        changeState(to: .working)
        
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
        } else if isFixedSleepTime {
            isSleeping = true
            // 强制休息时间，暂时中断工作状态（但不辞职），转为睡觉恢复精力
            // isWorking 默认为 false，不产生收益，不消耗工作精力
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
        } else if isLowEnergy {
            // 没有工作，精力低 -> 自动睡觉
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
            } else if isWorking && currentState != .working && !isSleeping {
                // 确保工作时处于工作状态（除非正在睡觉）
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
