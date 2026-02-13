import Foundation
import Combine

class PetDataManager: ObservableObject {
    static let shared = PetDataManager()
    
    @Published var status: PetStatus {
        didSet {
            // Optional: Auto-save or sync logic could go here
        }
    }
    
    private let statusKey = "PetStatus_Data"
    
    private init() {
        self.status = PetDataManager.loadStatusFromDisk()
    }
    
    // MARK: - Persistence
    
    func reloadFromDisk() {
        self.status = PetDataManager.loadStatusFromDisk()
        // Notify listeners that status has been forcefully reloaded from disk
        NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
    }
    
    static func loadStatusFromDisk() -> PetStatus {
        let statusKey = "PetStatus_Data"
        guard let data = UserDefaults.standard.data(forKey: statusKey) else {
            print("PetDataManager: No saved data found. Creating new status.")
            return PetStatus()
        }
        
        do {
            var decoded = try JSONDecoder().decode(PetStatus.self, from: data)
            
            // 数据清理：只保留在新配置中存在的物品，遗弃老数据
            // 注意：这里依赖 PetConfigManager，确保它已初始化
            var validInv: [String: Int] = [:]
            for (key, count) in decoded.inventory {
                if PetConfigManager.shared.getItem(byId: key) != nil {
                    validInv[key] = count
                }
            }
            decoded.inventory = validInv
            
            // 确保 ownedPetIds 至少包含 selectedPetId
            if let selected = decoded.selectedPetId, !decoded.ownedPetIds.contains(selected) {
                decoded.ownedPetIds.append(selected)
            }
            
            print("PetDataManager: Successfully loaded status. Pet: \(decoded.petName ?? "unnamed")")
            return decoded
        } catch {
            print("PetDataManager: Failed to decode saved status: \(error)")
            // 备份损坏数据
            let backupKey = "\(statusKey)_corrupted_\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: backupKey)
            print("PetDataManager: Corrupted data backed up to key: \(backupKey)")
            
            return PetStatus()
        }
    }
    
    func saveStatus(_ newStatus: PetStatus? = nil) {
        if let newStatus = newStatus {
            self.status = newStatus
        }
        
        let statusToSave = self.status
        
        // 异步保存，避免阻塞主线程
        // 针对小内存设备优化：将序列化和IO操作移出主线程
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let encoded = try? JSONEncoder().encode(statusToSave) {
                UserDefaults.standard.set(encoded, forKey: self.statusKey)
                
                // Auto backup check (daily)
                self.checkAutoBackup()
            }
        }
    }
    
    // MARK: - Backup & Restore
    
    private let lastBackupDateKey = "PetStatus_LastBackupDate"
    
    private func checkAutoBackup() {
        let lastBackup = UserDefaults.standard.double(forKey: lastBackupDateKey)
        let now = Date().timeIntervalSince1970
        // Backup every 24 hours (86400 seconds)
        if now - lastBackup > 86400 {
            backupStatus()
            UserDefaults.standard.set(now, forKey: lastBackupDateKey)
        }
    }
    
    func backupStatus() {
        let backupKey = "\(statusKey)_backup_\(Int(Date().timeIntervalSince1970))"
        if let encoded = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(encoded, forKey: backupKey)
            
            // Maintain backup history (keep last 5)
            cleanUpOldBackups()
            
            print("PetDataManager: Backup created at \(backupKey)")
        }
    }
    
    func getBackups() -> [String] {
        return UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.starts(with: "\(statusKey)_backup_") }
            .sorted(by: >) // Newest first
    }
    
    func restoreFromBackup(key: String) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: key) else { return false }
        
        do {
            let decoded = try JSONDecoder().decode(PetStatus.self, from: data)
            self.status = decoded
            saveStatus()
            
            // Notify listeners (like PetViewModel) to reload
            NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
            return true
        } catch {
            print("PetDataManager: Failed to restore backup: \(error)")
            return false
        }
    }
    
    private func cleanUpOldBackups() {
        let backups = getBackups()
        if backups.count > 5 {
            for key in backups.suffix(from: 5) {
                UserDefaults.standard.removeObject(forKey: key)
                print("PetDataManager: Removed old backup \(key)")
            }
        }
    }
    
    // MARK: - Currency API (For external systems)
    
    func getCurrency(type: PetCurrency) -> Int {
        switch type {
        case .meowCoin: return status.meowCoin
        case .fishCoin: return status.fishCoin
        case .boneCoin: return status.boneCoin
        }
    }
    
    @discardableResult
    func updateCurrency(type: PetCurrency, delta: Int) -> Int {
        switch type {
        case .meowCoin:
            status.meowCoin += delta
            if status.meowCoin < 0 { status.meowCoin = 0 }
        case .fishCoin:
            status.fishCoin += delta
            if status.fishCoin < 0 { status.fishCoin = 0 }
            // If earning fishCoin, update daily limit? 
            // This assumes delta > 0 means earning. 
            // External systems might need to handle daily limit logic themselves or we add a specific method.
        case .boneCoin:
            status.boneCoin += delta
            if status.boneCoin < 0 { status.boneCoin = 0 }
        }
        
        saveStatus()
        
        // Important: Notify PetViewModel to refresh UI
        NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
        
        return getCurrency(type: type)
    }
}
