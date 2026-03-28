import Foundation

@MainActor
final class PetHistoryResetManager {
    static let shared = PetHistoryResetManager()

    private static let resetAppliedVersionKey = "pet_history_reset_applied_version"
    private static let targetVersion = "1.4"

    private init() {}

    func applyForcedResetIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let savedVersion = UserDefaults.standard.string(forKey: Self.resetAppliedVersionKey)

        guard savedVersion != Self.targetVersion else { return }
        guard currentVersion.compare(Self.targetVersion, options: .numeric) != .orderedAscending else { return }

        clearAllPetHistory(reason: "version_reset_\(currentVersion)")
        UserDefaults.standard.set(Self.targetVersion, forKey: Self.resetAppliedVersionKey)
        print("🧹 [PetHistoryResetManager] Forced pet history reset applied for version \(Self.targetVersion)")
    }

    func clearAllPetHistory(reason: String) {
        PetChatTranscriptStore.clearAll()
        PetAIService.shared.clearPersistedHistory()
        PetConversationMemoryStore.shared.resetAll()
        print("🧹 [PetHistoryResetManager] Cleared all pet history. reason=\(reason)")
    }
}
