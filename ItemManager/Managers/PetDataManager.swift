import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let petStatusDidUpdateExternally = Notification.Name("PetStatusDidUpdateExternally")
}

class PetDataManager: ObservableObject {
    static let shared = PetDataManager()
    static let fullReloadUserInfoKey = "reloadAll"
    static let updateSourceUserInfoKey = "source"
    
    @Published var status: PetStatus {
        didSet {
            // Optional: Auto-save or sync logic could go here
        }
    }
    
    private let statusKey = "PetStatus_Data"
    private let statusModifiedAtKey = "PetStatus_LastModified"
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let persistenceQueue = DispatchQueue(label: "PetDataManager.persistence")
    
    private init() {
        self.status = PetDataManager.loadStatusFromDisk()
        setupObservers()
        synchronizeCloudSnapshotIfNeeded(reason: "launch")
    }
    
    // MARK: - Persistence

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func reloadFromDisk() {
        self.status = PetDataManager.loadStatusFromDisk()
        postExternalUpdate(fullReload: true, source: "diskReload")
    }
    
    static func loadStatusFromDisk() -> PetStatus {
        let statusKey = "PetStatus_Data"
        guard let data = UserDefaults.standard.data(forKey: statusKey) else {
            print("PetDataManager: No saved data found. Creating new status.")
            return sanitizeStatus(PetStatus())
        }
        
        do {
            let decoded = try decodeStatus(from: data)
            
            print("PetDataManager: Successfully loaded status. Pet: \(decoded.petName ?? "unnamed")")
            return decoded
        } catch {
            print("PetDataManager: Failed to decode saved status: \(error)")
            // 备份损坏数据
            let backupKey = "\(statusKey)_corrupted_\(Int(Date().timeIntervalSince1970))"
            UserDefaults.standard.set(data, forKey: backupKey)
            print("PetDataManager: Corrupted data backed up to key: \(backupKey)")
            
            return sanitizeStatus(PetStatus())
        }
    }
    
    func saveStatus(_ newStatus: PetStatus? = nil) {
        let previousStatus = self.status
        if let newStatus = newStatus {
            self.status = Self.sanitizeStatus(newStatus)
        } else {
            self.status = Self.sanitizeStatus(self.status)
        }
        
        let statusToSave = self.status
        let modifiedAt = Date()
        
        guard let encoded = try? JSONEncoder().encode(statusToSave) else {
            print("PetDataManager: Failed to encode status for save.")
            return
        }

        if previousStatus.meowCoin != statusToSave.meowCoin {
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "pet_status_save_meow_coin_changed",
                    fields: [
                        "previousMeowCoin": String(previousStatus.meowCoin),
                        "newMeowCoin": String(statusToSave.meowCoin)
                    ]
                )
            }
        }

        writeSnapshot(encoded, modifiedAt: modifiedAt, mirrorToCloud: true)
    }
    
    // MARK: - Backup & Restore
    
    private let lastBackupDateKey = "PetStatus_LastBackupDate"
    
    private func checkAutoBackup(using encoded: Data) {
        let lastBackup = UserDefaults.standard.double(forKey: lastBackupDateKey)
        let now = Date().timeIntervalSince1970
        // Backup every 24 hours (86400 seconds)
        if now - lastBackup > 86400 {
            backupStatus(using: encoded)
            UserDefaults.standard.set(now, forKey: lastBackupDateKey)
        }
    }
    
    func backupStatus(using encoded: Data? = nil) {
        let backupKey = "\(statusKey)_backup_\(Int(Date().timeIntervalSince1970))"
        let payload = encoded ?? exportStatusDataForBackup()
        if let payload {
            UserDefaults.standard.set(payload, forKey: backupKey)
            
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
        return replaceStatusFromExternalData(data, source: "petBackupRestore", mirrorToCloud: true)
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
    
    // MARK: - 获取当前宠物角色
    /// 获取当前选中的宠物角色，如果没有选中则默认返回奶茶
    func getCurrentPetCharacter() -> PetCharacter {
        guard let petId = status.selectedPetId,
              let character = PetCharacter(rawValue: petId) else {
            return .naicha // 默认返回奶茶
        }
        return character
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
        let previousValue = getCurrency(type: type)
        switch type {
        case .meowCoin:
            if delta < 0 {
                if !StoreManager.spendMeowCoins(-delta, in: &status) {
                    status.meowCoin = 0
                }
            } else {
                status.meowCoin += delta
                var account = StoreManager.loadMeowCoinAccount()
                account.balance = status.meowCoin
                account.lastUpdated = Date()
                StoreManager.saveMeowCoinAccount(account)
            }
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
        postExternalUpdate(fullReload: false, source: "currencyUpdate")

        if type == .meowCoin {
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "pet_currency_updated",
                    fields: [
                        "delta": String(delta),
                        "previousValue": String(previousValue),
                        "newValue": String(status.meowCoin),
                        "source": "currencyUpdate"
                    ]
                )
            }
        }

        return getCurrency(type: type)
    }

    // MARK: - External Sync / Backup APIs

    func exportStatusDataForBackup() -> Data? {
        let sanitized = Self.sanitizeStatus(status)
        return try? JSONEncoder().encode(sanitized)
    }

    @discardableResult
    func restoreFromBackupData(_ data: Data) -> Bool {
        replaceStatusFromExternalData(data, source: "backupRestore", mirrorToCloud: true)
    }

    @discardableResult
    func replaceStatusFromExternalData(_ data: Data, source: String, mirrorToCloud: Bool) -> Bool {
        do {
            let decoded = try Self.decodeStatus(from: data)
            let modifiedAt = Date()
            self.status = decoded
            guard let encoded = try? JSONEncoder().encode(decoded) else {
                print("PetDataManager: Failed to re-encode external status from \(source).")
                return false
            }
            writeSnapshot(encoded, modifiedAt: modifiedAt, mirrorToCloud: mirrorToCloud)
            postExternalUpdate(fullReload: true, source: source)
            return true
        } catch {
            print("PetDataManager: Failed to apply external status from \(source): \(error)")
            return false
        }
    }

    // MARK: - Cloud Mirror

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
#if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
#endif
    }

    @objc private func handleCloudStoreDidChange(_ notification: Notification) {
        guard isCloudRealtimeSyncEnabled else { return }

        if let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
           !changedKeys.contains(statusKey),
           !changedKeys.contains(statusModifiedAtKey) {
            return
        }

        synchronizeCloudSnapshotIfNeeded(reason: "cloudStoreDidChange")
    }

    @objc private func handleAppWillEnterForeground() {
        synchronizeCloudSnapshotIfNeeded(reason: "foreground")
    }

    private var isCloudRealtimeSyncEnabled: Bool {
        SwiftDataMigrationManager.shared.isCloudSyncEnabled
    }

    private func synchronizeCloudSnapshotIfNeeded(reason: String) {
        guard isCloudRealtimeSyncEnabled else { return }

        cloudStore.synchronize()

        let localData = UserDefaults.standard.data(forKey: statusKey)
        let remoteData = cloudStore.data(forKey: statusKey)
        let localModifiedAt = storedModifiedAt(in: UserDefaults.standard)
        let remoteModifiedAt = storedModifiedAt(in: cloudStore)
        let localMeowCoin = Self.meowCoin(from: localData)
        let remoteMeowCoin = Self.meowCoin(from: remoteData)

        switch (localData, remoteData) {
        case (nil, nil):
            return
        case let (local?, nil):
            let timestamp = localModifiedAt ?? Date()
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .cloudSync,
                    name: "cloud_sync_push_local_only",
                    level: .notice,
                    fields: [
                        "reason": reason,
                        "localModifiedAt": Self.format(localModifiedAt),
                        "localMeowCoin": Self.format(localMeowCoin)
                    ]
                )
            }
            writeCloudSnapshot(local, modifiedAt: timestamp)
        case let (nil, remote?):
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .cloudSync,
                    name: "cloud_sync_apply_remote_only",
                    level: .notice,
                    fields: [
                        "reason": reason,
                        "remoteModifiedAt": Self.format(remoteModifiedAt),
                        "remoteMeowCoin": Self.format(remoteMeowCoin)
                    ]
                )
            }
            _ = replaceStatusFromCloudData(remote, modifiedAt: remoteModifiedAt ?? Date(), reason: reason)
        case let (local?, remote?):
            let localTimestamp = localModifiedAt ?? .distantPast
            let remoteTimestamp = remoteModifiedAt ?? .distantPast
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .cloudSync,
                    name: "cloud_sync_compared",
                    fields: [
                        "reason": reason,
                        "localModifiedAt": Self.format(localModifiedAt),
                        "remoteModifiedAt": Self.format(remoteModifiedAt),
                        "localMeowCoin": Self.format(localMeowCoin),
                        "remoteMeowCoin": Self.format(remoteMeowCoin)
                    ]
                )
            }

            if remoteTimestamp > localTimestamp {
                Task {
                    await IAPDiagnosticStore.shared.record(
                        category: .cloudSync,
                        name: "cloud_sync_remote_wins",
                        level: .notice,
                        fields: [
                            "reason": reason,
                            "localModifiedAt": Self.format(localModifiedAt),
                            "remoteModifiedAt": Self.format(remoteModifiedAt),
                            "localMeowCoin": Self.format(localMeowCoin),
                            "remoteMeowCoin": Self.format(remoteMeowCoin)
                        ]
                    )
                }
                _ = replaceStatusFromCloudData(remote, modifiedAt: remoteTimestamp, reason: reason)
            } else if localTimestamp > remoteTimestamp || local != remote {
                Task {
                    await IAPDiagnosticStore.shared.record(
                        category: .cloudSync,
                        name: "cloud_sync_local_wins",
                        level: .notice,
                        fields: [
                            "reason": reason,
                            "localModifiedAt": Self.format(localModifiedAt),
                            "remoteModifiedAt": Self.format(remoteModifiedAt),
                            "localMeowCoin": Self.format(localMeowCoin),
                            "remoteMeowCoin": Self.format(remoteMeowCoin)
                        ]
                    )
                }
                writeCloudSnapshot(local, modifiedAt: localModifiedAt ?? Date())
            }
        }
    }

    @discardableResult
    private func replaceStatusFromCloudData(_ data: Data, modifiedAt: Date, reason: String) -> Bool {
        do {
            let previousMeowCoin = self.status.meowCoin
            let decoded = try Self.decodeStatus(from: data)
            self.status = decoded
            guard let encoded = try? JSONEncoder().encode(decoded) else {
                print("PetDataManager: Failed to re-encode cloud status.")
                return false
            }
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .cloudSync,
                    name: "cloud_sync_status_replaced",
                    level: .notice,
                    fields: [
                        "reason": reason,
                        "previousMeowCoin": String(previousMeowCoin),
                        "newMeowCoin": String(decoded.meowCoin),
                        "modifiedAt": modifiedAt.ISO8601Format()
                    ]
                )
            }
            writeSnapshot(encoded, modifiedAt: modifiedAt, mirrorToCloud: false)
            postExternalUpdate(fullReload: true, source: "cloudSync:\(reason)")
            return true
        } catch {
            print("PetDataManager: Failed to decode cloud status: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    private static func decodeStatus(from data: Data) throws -> PetStatus {
        let decoded = try JSONDecoder().decode(PetStatus.self, from: data)
        return sanitizeStatus(decoded)
    }

    private static func sanitizeStatus(_ rawStatus: PetStatus) -> PetStatus {
        var sanitized = rawStatus

        sanitized.hunger = sanitized.hunger.clamped(to: 0...100)
        sanitized.hygiene = sanitized.hygiene.clamped(to: 0...100)
        sanitized.energy = sanitized.energy.clamped(to: 0...100)
        sanitized.mood = sanitized.mood.clamped(to: 0...100)
        sanitized.intimacy = sanitized.intimacy.clamped(to: 0...100)

        sanitized.meowCoin = max(0, sanitized.meowCoin)
        sanitized.fishCoin = max(0, sanitized.fishCoin)
        sanitized.boneCoin = max(0, sanitized.boneCoin)
        sanitized.dailyFishCoinEarned = max(0, min(PetStatus.dailyFishCoinLimit, sanitized.dailyFishCoinEarned))
        sanitized.currentJobEarnedFishCoin = max(0, sanitized.currentJobEarnedFishCoin)

        var validInv: [String: Int] = [:]
        for (key, count) in sanitized.inventory where count > 0 {
            if PetConfigManager.shared.getItem(byId: key) != nil {
                validInv[key] = count
            }
        }
        sanitized.inventory = validInv

        var uniqueOwnedPetIds: [String] = []
        for petId in sanitized.ownedPetIds where !uniqueOwnedPetIds.contains(petId) {
            uniqueOwnedPetIds.append(petId)
        }
        sanitized.ownedPetIds = uniqueOwnedPetIds
        sanitized.ownedPetIds.removeAll { $0.isEmpty }

        if let selected = sanitized.selectedPetId, !selected.isEmpty {
            if !sanitized.ownedPetIds.contains(selected) {
                sanitized.ownedPetIds.append(selected)
            }
        } else if let firstOwned = sanitized.ownedPetIds.first {
            sanitized.selectedPetId = firstOwned
        }

        return sanitized
    }

    private static func meowCoin(from data: Data?) -> Int? {
        guard let data else { return nil }
        return (try? decodeStatus(from: data))?.meowCoin
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return date.ISO8601Format()
    }

    private static func format(_ value: Int?) -> String {
        guard let value else { return "nil" }
        return String(value)
    }

    private func writeSnapshot(_ encoded: Data, modifiedAt: Date, mirrorToCloud: Bool) {
        persistenceQueue.async { [weak self] in
            guard let self = self else { return }

            UserDefaults.standard.set(encoded, forKey: self.statusKey)
            UserDefaults.standard.set(modifiedAt.timeIntervalSince1970, forKey: self.statusModifiedAtKey)

            if mirrorToCloud && self.isCloudRealtimeSyncEnabled {
                self.writeCloudSnapshot(encoded, modifiedAt: modifiedAt)
            }

            self.checkAutoBackup(using: encoded)
        }
    }

    private func writeCloudSnapshot(_ encoded: Data, modifiedAt: Date) {
        cloudStore.set(encoded, forKey: statusKey)
        cloudStore.set(modifiedAt.timeIntervalSince1970, forKey: statusModifiedAtKey)
        cloudStore.synchronize()
    }

    private func storedModifiedAt(in defaults: UserDefaults) -> Date? {
        let timestamp = defaults.double(forKey: statusModifiedAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func storedModifiedAt(in cloudStore: NSUbiquitousKeyValueStore) -> Date? {
        let timestamp = cloudStore.double(forKey: statusModifiedAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func postExternalUpdate(fullReload: Bool, source: String) {
        NotificationCenter.default.post(
            name: .petStatusDidUpdateExternally,
            object: nil,
            userInfo: [
                Self.fullReloadUserInfoKey: fullReload,
                Self.updateSourceUserInfoKey: source
            ]
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
