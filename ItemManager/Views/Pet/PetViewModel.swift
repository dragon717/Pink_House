import SwiftUI
import Combine
import AVFoundation

struct FloatingTextData: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
    var offset: CGSize = .zero
    var opacity: Double = 1.0
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
    
    // MARK: - Initialization
    init() {
        // Load saved status
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
            
            self.status = decoded
        } else {
            self.status = PetStatus()
        }
        
        // Calculate offline decay
        calculateOfflineDecay()
        checkDailyReset()
        
        // Start timer
        startTimer()
        
        setupAudioBindings()
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
            showFloatingText("余额不足", color: .gray)
            return
        }
        
        // 2. 扣钱
        switch item.petCurrency {
        case .fishCoin:
            status.fishCoin -= item.price
        case .meowCoin:
            status.meowCoin -= item.price
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
        
        // 5. 显示扣款提示
        showFloatingText("-\(item.price)", color: .orange)
        
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
            showFloatingText("这个不能吃哦", color: .red)
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
                showFloatingText("精力 -\(Int(energyCost))", color: .blue)
            }
            showFloatingText("心情 +\(Int(item.recoveryValue))", color: .pink)
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
        }
        
        saveStatus()
    }
    
    // 兼容旧代码
    func consumeItem(_ itemType: PetItemType) {
        if let def = PetConfigManager.shared.getItem(byId: itemType.configId) {
            consumeItem(def)
        }
    }
    
    func clean() {
        guard currentState == .idle else { return }
        
        // 检查鱼币是否足够
        let cost = 20
        if status.fishCoin >= cost {
            // 扣除鱼币
            status.fishCoin -= cost
            showFloatingText("-\(cost)", color: .red)
            
            // 更新状态
            status.hygiene = min(100, status.hygiene + 20)
            status.mood = min(100, status.mood + 10) // 清洁也恢复心情
            saveStatus()
            
            // 切换状态
            changeState(to: .cleaning)
        } else {
            // 余额不足提示
            showFloatingText("鱼币不足!", color: .gray)
        }
    }
    
    func onAnimationFinished() {
        // Return to idle after action finished
        if currentState != .idle {
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
    
    private func checkDailyReset() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(status.lastDailyResetDate) {
            status.dailyFishCoinEarned = 0
            status.lastDailyResetDate = Date()
            saveStatus()
        }
    }
    
    // MARK: - UI Effects
    
    func showFloatingText(_ text: String, color: Color) {
        let newData = FloatingTextData(text: text, color: color)
        floatingTexts.append(newData)
        
        // 自动移除
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.floatingTexts.removeAll(where: { $0.id == newData.id })
        }
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
        
        saveStatus()
        
        if job != .none {
            showFloatingText("开始打工: \(job.rawValue)", color: .blue)
        }
    }
    
    func stopJob() {
        guard status.currentJob != .none else { return }
        
        let jobName = status.currentJob.rawValue
        status.currentJob = .none
        status.jobStartTime = nil
        jobIncomeAccumulator = 0.0
        
        saveStatus()
        
        showFloatingText("结束打工: \(jobName)", color: .green)
    }
    
    private func updateStatus() {
        // 检查跨天重置
        checkDailyReset()
        
        // Decay logic
        let multiplier = status.currentJob.consumptionMultiplier
        
        status.hunger = max(0, status.hunger - PetStatus.hungerDecayRate * multiplier)
        status.hygiene = max(0, status.hygiene - PetStatus.hygieneDecayRate * multiplier)
        
        // 精力逻辑：工作时衰减，空闲时恢复
        if status.currentJob != .none {
            status.energy = max(0, status.energy - PetStatus.energyDecayRate * multiplier)
        } else {
            // 空闲时每小时恢复 20 点 (20.0 / 3600.0)
            status.energy = min(100, status.energy + (20.0 / 3600.0))
        }
        
        status.mood = max(0, status.mood - PetStatus.moodDecayRate * multiplier)
        status.lastUpdateTime = Date()
        
        // Job Income
        if status.currentJob != .none {
            let incomePerSecond = Double(status.currentJob.incomeRate) / 60.0
            jobIncomeAccumulator += incomePerSecond
            
            if jobIncomeAccumulator >= 1.0 {
                let coinToAdd = Int(jobIncomeAccumulator)
                earnFishCoin(amount: coinToAdd) // 使用 earnFishCoin 处理每日上限
                jobIncomeAccumulator -= Double(coinToAdd)
            }
            
            // 自动停止打工条件
            if status.hunger < 10 || status.hygiene < 10 || status.energy < 10 || status.mood < 10 {
                stopJob()
                showFloatingText("太累了，回家休息...", color: .red)
            }
        }
    }
    
    private func calculateOfflineDecay() {
        let now = Date()
        let timeInterval = now.timeIntervalSince(status.lastUpdateTime)
        
        let multiplier = status.currentJob.consumptionMultiplier
        
        let hungerLoss = timeInterval * PetStatus.hungerDecayRate * multiplier
        let hygieneLoss = timeInterval * PetStatus.hygieneDecayRate * multiplier
        let moodLoss = timeInterval * PetStatus.moodDecayRate * multiplier
        
        // 计算收益 (在扣除属性前计算，简单处理)
        if status.currentJob != .none {
            let totalIncome = Int(timeInterval / 60.0 * Double(status.currentJob.incomeRate))
            if totalIncome > 0 {
                earnFishCoin(amount: totalIncome)
            }
        }
        
        status.hunger = max(0, status.hunger - hungerLoss)
        status.hygiene = max(0, status.hygiene - hygieneLoss)
        status.mood = max(0, status.mood - moodLoss)
        
        // 精力逻辑：工作时衰减，空闲时恢复
        if status.currentJob != .none {
            let energyLoss = timeInterval * PetStatus.energyDecayRate * multiplier
            status.energy = max(0, status.energy - energyLoss)
        } else {
            let energyGain = timeInterval * (20.0 / 3600.0)
            status.energy = min(100, status.energy + energyGain)
        }
        
        status.lastUpdateTime = now
        
        // 检查是否需要自动停止
        if status.currentJob != .none && (status.hunger < 10 || status.hygiene < 10 || status.energy < 10 || status.mood < 10) {
            status.currentJob = .none
            status.jobStartTime = nil
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
