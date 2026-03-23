import Foundation
import StoreKit
import Combine

// MARK: - IAPServerManager
// StoreKit 2 原生本地验证管理类
// 使用 StoreKit 2 的 VerificationResult 进行本地验证，无需后端服务器
// 注意：这种方式比旧版收据验证安全，但无法防范越狱插件

@MainActor
class IAPServerManager: ObservableObject {
    static let shared = IAPServerManager()

    // Published 状态
    @Published var meowCoinBalance: Int = 0
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private init() {
        // 初始化时同步本地数据
        syncLocalData()
    }

    // MARK: - 同步本地数据

    /// 从本地存储同步用户资产数据
    func syncLocalData() {
        let account = StoreManager.loadMeowCoinAccount()

        self.meowCoinBalance = account.balance

        print("[IAPServerManager] 本地数据同步: 喵币=\(account.balance)")
    }

    // MARK: - 验证交易并发放奖励

    /// 验证 StoreKit 2 交易并发放喵币/VIP
    /// - Parameters:
    ///   - transaction: StoreKit 2 验证后的交易
    ///   - productID: 商品ID
    /// - Returns: 是否成功
    func verifyAndDeliver(transaction: Transaction, productID: String? = nil) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        // StoreKit 2 的 Transaction 已经通过 VerificationResult 验证
        // 这里只需要处理业务逻辑：发放喵币或开通VIP

        guard let productType = IAPProductType(rawValue: transaction.productID) else {
            lastError = "未知商品类型"
            return false
        }

        switch productType {
        case .meowCoin60, .meowCoin120, .meowCoin300, .meowCoin500, .meowCoin1280, .meowCoin3280:
            return await deliverMeowCoins(for: transaction, productType: productType)
        }
    }

    // MARK: - 发放喵币

    private func deliverMeowCoins(for transaction: Transaction, productType: IAPProductType) async -> Bool {
        let (baseAmount, bonus) = getCoinAmount(for: productType)

        // 计算实际获得的喵币（考虑首充双倍）
        let (totalAmount, isFirstDouble) = FirstDoubleBonusManager.shared.calculateActualCoins(
            baseAmount: baseAmount,
            bonusAmount: bonus,
            productID: transaction.productID
        )

        // 如果是首次购买，标记为已完成
        if isFirstDouble {
            FirstDoubleBonusManager.shared.markFirstPurchaseCompleted(for: transaction.productID)
        }

        // 更新用户喵币余额
        await MainActor.run {
            var account = StoreManager.loadMeowCoinAccount()
            account.balance += totalAmount
            account.totalPurchased += totalAmount
            account.lastUpdated = Date()
            StoreManager.saveMeowCoinAccount(account)

            // 同时更新 PetDataManager 中的喵币
            var status = PetDataManager.shared.status
            status.meowCoin = account.balance
            PetDataManager.shared.saveStatus(status)
            notifyPetStatusDidChange()

            // 更新本地状态
            self.meowCoinBalance = account.balance
        }

        // 记录购买历史
        let record = IAPPurchaseRecord(
            id: String(transaction.id),
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            coinAmount: totalAmount,
            subscriptionMonths: nil,
            isVerified: true,
            verificationDate: Date()
        )
        savePurchaseRecord(record)

        print("[IAPServerManager] 发放喵币: \(totalAmount) (基础: \(baseAmount), 赠送: \(bonus), 首充双倍: \(isFirstDouble))")
        return true
    }

    // MARK: - 消费喵币

    /// 消费喵币（购买虚拟物品时调用）
    /// - Parameter amount: 消费数量
    /// - Returns: 是否成功
    func spendMeowCoins(_ amount: Int) async -> Bool {
        let success = StoreManager.spendMeowCoins(amount)

        if success {
            syncLocalData()
        } else {
            lastError = "余额不足"
        }

        return success
    }

    // MARK: - 私有方法

    private func getCoinAmount(for productType: IAPProductType) -> (base: Int, bonus: Int) {
        switch productType {
        case .meowCoin60:
            return (60, 6)       // 6元档：基础60 + 赠送6(10%)
        case .meowCoin120:
            return (120, 12)     // 12元档：基础120 + 赠送12(10%)
        case .meowCoin300:
            return (300, 30)     // 30元档：基础300 + 赠送30(10%)
        case .meowCoin500:
            return (500, 75)     // 50元档：基础500 + 赠送75(15%)
        case .meowCoin1280:
            return (1280, 320)   // 128元档：基础1280 + 赠送320(25%)
        case .meowCoin3280:
            return (3280, 1148)  // 328元档：基础3280 + 赠送1148(35%)
        default:
            return (0, 0)
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw ServerError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    private func savePurchaseRecord(_ record: IAPPurchaseRecord) {
        var records = loadPurchaseRecords()
        records.append(record)

        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: IAPPurchaseRecord.storageKey)
        }
    }

    private func loadPurchaseRecords() -> [IAPPurchaseRecord] {
        if let data = UserDefaults.standard.data(forKey: IAPPurchaseRecord.storageKey),
           let records = try? JSONDecoder().decode([IAPPurchaseRecord].self, from: data) {
            return records
        }
        return []
    }

    private func notifyPetStatusDidChange() {
        NotificationCenter.default.post(
            name: Notification.Name("PetStatusDidUpdateExternally"),
            object: nil
        )
    }
}

enum ServerError: Error {
    case verificationFailed
}
