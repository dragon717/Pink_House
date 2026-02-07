import SwiftUI
import Combine

class PetViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentState: PetState = .idle
    @Published var status: PetStatus
    
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
        
        // Start timer
        startTimer()
    }
    
    deinit {
        stopTimer()
    }
    
    // MARK: - State Management
    
    func feed() {
        guard currentState == .idle else { return }
        
        // Update status
        status.hunger = min(100, status.hunger + 20)
        saveStatus()
        
        // Change state
        changeState(to: .eating)
    }
    
    func clean() {
        guard currentState == .idle else { return }
        
        // Update status
        status.hygiene = min(100, status.hygiene + 20)
        saveStatus()
        
        // Change state
        changeState(to: .cleaning)
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
        
        // Save periodically (or could do it in scenePhase changes)
        // For simplicity, we save less frequently or rely on onDisappear/scenePhase
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
}
