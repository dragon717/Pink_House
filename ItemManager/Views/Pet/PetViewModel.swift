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
           let decoded = try? JSONDecoder().decode(PetStatus.self, from: data) {
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
    
    // 拖拽喂食/饮水成功
    func consumeItem(_ itemType: PetItemType) {
        // 扣除物品
        guard let count = status.inventory[itemType], count > 0 else { return }
        status.inventory[itemType] = count - 1
        
        // 增加属性
        if itemType.isDrink {
            status.hunger = min(100, status.hunger + itemType.recoveryValue)
            changeState(to: .drinking)
        } else {
            status.hunger = min(100, status.hunger + itemType.recoveryValue)
            changeState(to: .eating)
        }
        
        saveStatus()
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
    
    func purchaseItem(_ itemType: PetItemType) -> Bool {
        if status.fishCoin >= itemType.price {
            status.fishCoin -= itemType.price
            status.inventory[itemType, default: 0] += 1
            saveStatus()
            return true
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
    
    private func updateStatus() {
        // Decay logic
        status.hunger = max(0, status.hunger - PetStatus.hungerDecayRate)
        status.hygiene = max(0, status.hygiene - PetStatus.hygieneDecayRate)
        status.lastUpdateTime = Date()
    }
    
    private func calculateOfflineDecay() {
        let now = Date()
        let timeInterval = now.timeIntervalSince(status.lastUpdateTime)
        
        let hungerLoss = timeInterval * PetStatus.hungerDecayRate
        let hygieneLoss = timeInterval * PetStatus.hygieneDecayRate
        
        status.hunger = max(0, status.hunger - hungerLoss)
        status.hygiene = max(0, status.hygiene - hygieneLoss)
        status.lastUpdateTime = now
        
        saveStatus()
    }
    
    func saveStatus() {
        if let encoded = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(encoded, forKey: statusKey)
        }
    }
    
    func setPetName(_ name: String) {
        status.petName = name
        saveStatus()
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
