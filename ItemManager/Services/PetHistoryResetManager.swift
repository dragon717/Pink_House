import Foundation

@MainActor
final class PetHistoryResetManager {
    static let shared = PetHistoryResetManager()

    private static let petHistoryResetAppliedVersionKey = "pet_history_reset_applied_version"
    private static let petHistoryTargetVersion = "1.4"
    private static let iapFirstDoubleResetAppliedVersionKey = "iap_first_double_reset_applied_version"
    private static let iapFirstDoubleTargetVersion = "1.6"
    private static let legacyFirstPurchaseStatusKey = "iap_first_purchase_completed_by_product"

    private init() {}

    func applyForcedResetIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        applyPetHistoryResetIfNeeded(currentVersion: currentVersion)
        applyIAPFirstDoubleResetIfNeeded(currentVersion: currentVersion)
    }

    func clearAllPetHistory(reason: String) {
        PetChatTranscriptStore.clearAll()
        PetAIService.shared.clearPersistedHistory()
        PetConversationMemoryStore.shared.resetAll()
        print("🧹 [PetHistoryResetManager] Cleared all pet history. reason=\(reason)")
    }

    private func applyPetHistoryResetIfNeeded(currentVersion: String) {
        let savedVersion = UserDefaults.standard.string(forKey: Self.petHistoryResetAppliedVersionKey)

        guard savedVersion != Self.petHistoryTargetVersion else { return }
        guard currentVersion.compare(Self.petHistoryTargetVersion, options: .numeric) != .orderedAscending else { return }

        clearAllPetHistory(reason: "version_reset_\(currentVersion)")
        UserDefaults.standard.set(Self.petHistoryTargetVersion, forKey: Self.petHistoryResetAppliedVersionKey)
        print("🧹 [PetHistoryResetManager] Forced pet history reset applied for version \(Self.petHistoryTargetVersion)")
    }

    private func applyIAPFirstDoubleResetIfNeeded(currentVersion: String) {
        let savedVersion = UserDefaults.standard.string(forKey: Self.iapFirstDoubleResetAppliedVersionKey)

        guard savedVersion != Self.iapFirstDoubleTargetVersion else { return }
        guard currentVersion.compare(Self.iapFirstDoubleTargetVersion, options: .numeric) != .orderedAscending else { return }

        var account = StoreManager.loadMeowCoinAccount()
        account.firstPurchaseCompletedByProduct.removeAll()
        account.lastUpdated = Date()
        StoreManager.saveMeowCoinAccount(account)

        // 清掉测试面板使用的历史首充缓存键，避免调试遗留状态误导正式逻辑。
        UserDefaults.standard.removeObject(forKey: Self.legacyFirstPurchaseStatusKey)
        UserDefaults.standard.set(Self.iapFirstDoubleTargetVersion, forKey: Self.iapFirstDoubleResetAppliedVersionKey)
        print("🪙 [PetHistoryResetManager] Forced IAP first-double reset applied for version \(Self.iapFirstDoubleTargetVersion)")
    }
}
