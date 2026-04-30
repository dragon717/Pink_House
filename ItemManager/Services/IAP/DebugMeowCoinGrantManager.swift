import Foundation

#if DEBUG
@MainActor
enum DebugMeowCoinGrantManager {
    private static let grantAmount = 10_000
    private static let grantAppliedKey = "debug.meow_coin_10000_grant_applied"

    static func grantIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: grantAppliedKey) else {
            print("🪙 [DebugMeowCoinGrantManager] Debug 喵币已发放过，跳过")
            return
        }

        let previousBalance = PetDataManager.shared.status.meowCoin
        let newBalance = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: grantAmount)
        UserDefaults.standard.set(true, forKey: grantAppliedKey)

        print("🪙 [DebugMeowCoinGrantManager] Debug 首次发放 \(grantAmount) 喵币，余额 \(previousBalance) -> \(newBalance)")
    }
}
#endif
