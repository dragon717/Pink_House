import Foundation
import StoreKit
import Combine

// MARK: - StoreManager
// StoreKit 2 支付管理类，处理所有内购相关逻辑
// 包括商品获取、购买流程、交易验证等

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - Published Properties
    @Published var coinProducts: [Product] = []           // 喵币商品列表
    @Published var isLoading: Bool = false                // 是否正在加载
    @Published var isPurchasing: Bool = false             // 是否正在购买
    @Published var lastError: IAPError?                   // 最后一次错误
    @Published var purchaseSuccess: Bool = false          // 购买成功标志
    @Published var purchaseSuccessMessage: String = ""    // 购买成功消息

    // 交易更新监听器
    private var transactionListener: Task<Void, Error>?

    // 已处理的交易ID集合（防止重复处理）
    private var processedTransactionIDs: Set<String> = []

    // MARK: - Initialization
    private init() {
        // 启动交易监听器，处理未完成交易和外部交易
        startTransactionListener()
        // 加载已处理的交易ID
        loadProcessedTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - 交易监听器
    // 监听所有交易更新，包括：
    // 1. 应用启动时的未完成交易
    // 2. 购买过程中的状态更新
    // 3. 外部到账通知
    // 4. 退款通知
    private func startTransactionListener() {
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }

                do {
                    let transaction = try await self.checkVerified(result)

                    // 检查是否已处理过
                    if await self.isTransactionProcessed(transaction.id) {
                        await transaction.finish()
                        continue
                    }

                    // 处理交易
                    await self.processTransaction(transaction)
                } catch {
                    print("[StoreManager] 交易验证失败: \(error)")
                }
            }
        }
    }

    // MARK: - 获取商品信息
    // 从 App Store 获取商品信息
    // 需要在 App Store Connect 中预先配置商品
    func fetchProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allProductIDs = IAPProductType.allProductIDs
            let products = try await Product.products(for: allProductIDs)

            coinProducts = products.filter { product in
                IAPProductType.coinProductIDs.contains(product.id)
            }.sorted { p1, p2 in
                // 按价格排序
                p1.price < p2.price
            }

            print("[StoreManager] 获取到 \(coinProducts.count) 个喵币商品")

        } catch {
            print("[StoreManager] 获取商品失败: \(error)")
            lastError = .productRequestFailed(error.localizedDescription)
        }
    }

    // MARK: - 购买商品
    // 发起购买流程
    // 支持测试模式和服务器验证模式
    // 参数:
    //   - product: 要购买的商品
    // 返回:
    //   - IAPPurchaseResult: 购买结果
    func purchase(_ product: Product) async -> IAPPurchaseResult {
        isPurchasing = true
        defer { isPurchasing = false }

        // 测试模式：使用模拟支付
        if IAPTestManager.shared.isTestMode {
            return await purchaseInTestMode(product: product)
        }

        // 生产模式：正常Apple支付流程
        return await purchaseInProductionMode(product: product)
    }

    // MARK: - 测试模式购买
    private func purchaseInTestMode(product: Product) async -> IAPPurchaseResult {
        // 模拟购买延迟
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        guard let productType = IAPProductType(rawValue: product.id) else {
            return .failed(.productNotFound(product.id))
        }

        switch productType {
        case .meowCoin60, .meowCoin120, .meowCoin300, .meowCoin500, .meowCoin1280, .meowCoin3280:
            let result = IAPTestManager.shared.mockVerifyPayment(productID: product.id)

            switch result {
            case .success(let deliveredCoins, _, let isFirstDouble):
                await showPurchaseSuccessMessage(
                    isFirstDouble
                    ? "🎉 首充双倍！获得 \(deliveredCoins) 喵币"
                    : "成功获得 \(deliveredCoins) 喵币"
                )
                return .success(transaction: nil, product: product)

            case .failure(let error):
                return .failed(.purchaseFailed(error))
            }
        }
    }

    // MARK: - 生产模式购买
    private func purchaseInProductionMode(product: Product) async -> IAPPurchaseResult {
        do {
            // 准备购买选项
            var options: Set<Product.PurchaseOption> = []
            // 可选：传入appAccountToken用于关联用户（当前使用本地验证，不需要）
            // if let userUUID = getCurrentUserUUID() {
            //     options.insert(.appAccountToken(userUUID))
            // }

            // 发起购买请求
            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                // 验证交易
                let transaction = try await checkVerified(verification)

                // 检查是否已处理
                if isTransactionProcessed(transaction.id) {
                    await transaction.finish()
                    return .failed(.alreadyProcessed)
                }

                await processTransaction(transaction)
                return .success(transaction: transaction, product: product)

            case .userCancelled:
                print("[StoreManager] 用户取消购买")
                return .cancelled

            case .pending:
                print("[StoreManager] 购买等待中")
                return .pending

            @unknown default:
                return .failed(.purchaseFailed("未知状态"))
            }

        } catch let error as Product.PurchaseError {
            print("[StoreManager] 购买错误: \(error)")
            let iapError = IAPError.from(purchaseError: error)
            lastError = iapError
            return .failed(iapError)

        } catch {
            print("[StoreManager] 购买失败: \(error)")
            let iapError = IAPError.purchaseFailed(error.localizedDescription)
            lastError = iapError
            return .failed(iapError)
        }
    }

    // MARK: - 验证交易
    // 验证 StoreKit 返回的交易签名
    // 确保交易是真实的，不是伪造的
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw IAPError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - 处理交易
    // 处理已验证的交易
    // 包括：发放喵币、更新VIP状态、记录交易等
    private func processTransaction(_ transaction: Transaction) async {
        print("[StoreManager] 处理交易: \(transaction.id)")

        // 标记为已处理
        markTransactionAsProcessed(transaction.id)

        // 根据商品类型处理
        if let productType = IAPProductType(rawValue: transaction.productID) {
            switch productType {
            case .meowCoin60, .meowCoin120, .meowCoin300, .meowCoin500, .meowCoin1280, .meowCoin3280:
                await deliverMeowCoins(for: transaction, productType: productType)
            }
        }

        // 完成交易
        await transaction.finish()
    }

    // MARK: - 发放喵币
    // 根据购买的商品发放相应数量的喵币（支持首次双倍活动）
    private func deliverMeowCoins(for transaction: Transaction, productType: IAPProductType) async {
        let (baseAmount, bonus) = getCoinAmount(for: productType)

        // 计算实际获得的喵币（考虑首次双倍）
        let (totalAmount, isFirstDouble) = FirstDoubleBonusManager.shared.calculateActualCoins(
            baseAmount: baseAmount,
            bonusAmount: bonus,
            productID: transaction.productID
        )

        // 如果是首次购买该档位，标记为已完成
        if isFirstDouble {
            FirstDoubleBonusManager.shared.markFirstPurchaseCompleted(for: transaction.productID)
        }

        // 更新用户喵币余额
        await MainActor.run {
            var account = Self.loadMeowCoinAccount()
            account.balance += totalAmount
            account.totalPurchased += totalAmount
            account.lastUpdated = Date()
            Self.saveMeowCoinAccount(account)

            // 同时更新 PetDataManager 中的喵币
            var status = PetDataManager.shared.status
            status.meowCoin = account.balance
            PetDataManager.shared.saveStatus(status)
            Self.notifyPetStatusDidChange()

            // 显示成功消息
            purchaseSuccess = true
            if isFirstDouble {
                // 首次双倍提示
                purchaseSuccessMessage = "🎉 首充双倍！获得 \(totalAmount) 喵币"
            } else if bonus > 0 {
                purchaseSuccessMessage = "成功获得 \(totalAmount) 喵币（含赠送 \(bonus)）"
            } else {
                purchaseSuccessMessage = "成功获得 \(totalAmount) 喵币"
            }

            // 3秒后清除成功标志
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.purchaseSuccess = false
                self.purchaseSuccessMessage = ""
            }
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

        print("[StoreManager] 发放喵币: \(totalAmount) (基础: \(baseAmount), 赠送: \(bonus), 首充双倍: \(isFirstDouble))")
    }

    // MARK: - 获取喵币数量
    // 根据商品类型返回对应的喵币数量和赠送数量
    // 汇率 10:1（1元 = 10喵币）
    // 策略：首次购买双倍，之后按档位 +10%、+15%、+25%、+35% 赠送
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

    // MARK: - 交易处理记录
    // 防止重复处理同一笔交易
    private func isTransactionProcessed(_ id: UInt64) -> Bool {
        return processedTransactionIDs.contains(String(id))
    }

    private func markTransactionAsProcessed(_ id: UInt64) {
        processedTransactionIDs.insert(String(id))
        saveProcessedTransactions()
    }

    private func loadProcessedTransactions() {
        if let data = UserDefaults.standard.data(forKey: "ProcessedTransactionIDs"),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            processedTransactionIDs = Set(ids)
        }
    }

    private func saveProcessedTransactions() {
        if let data = try? JSONEncoder().encode(Array(processedTransactionIDs)) {
            UserDefaults.standard.set(data, forKey: "ProcessedTransactionIDs")
        }
    }

    // MARK: - 购买记录存储
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

    // MARK: - 喵币账户管理
    static func loadMeowCoinAccount() -> MeowCoinAccount {
        if let data = UserDefaults.standard.data(forKey: MeowCoinAccount.storageKey),
           let account = try? JSONDecoder().decode(MeowCoinAccount.self, from: data) {
            return account
        }
        return MeowCoinAccount()
    }

    static func synchronizedMeowCoinAccount() -> MeowCoinAccount {
        var account = loadMeowCoinAccount()
        let actualBalance = PetDataManager.shared.status.meowCoin
        let inferredSpent = max(account.totalSpent, max(0, account.totalPurchased - actualBalance))

        if account.balance != actualBalance || account.totalSpent != inferredSpent {
            account.balance = actualBalance
            account.totalSpent = inferredSpent
            account.lastUpdated = Date()
            saveMeowCoinAccount(account)
        }

        return account
    }

    static func saveMeowCoinAccount(_ account: MeowCoinAccount) {
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: MeowCoinAccount.storageKey)
        }
    }

    // MARK: - 消费喵币
    // 用于购买虚拟物品时扣除喵币
    @discardableResult
    static func spendMeowCoins(_ amount: Int, in status: inout PetStatus) -> Bool {
        guard status.meowCoin >= amount else { return false }

        status.meowCoin -= amount

        var account = synchronizedMeowCoinAccount()
        account.balance = status.meowCoin
        account.totalSpent += amount
        account.lastUpdated = Date()
        saveMeowCoinAccount(account)

        return true
    }

    static func spendMeowCoins(_ amount: Int) -> Bool {
        var status = PetDataManager.shared.status
        guard spendMeowCoins(amount, in: &status) else { return false }

        PetDataManager.shared.saveStatus(status)
        Self.notifyPetStatusDidChange()

        return true
    }

    // MARK: - 获取当前喵币余额
    static func getCurrentBalance() -> Int {
        return synchronizedMeowCoinAccount().balance
    }

    // MARK: - 检查是否可以购买
    func canMakePurchases() -> Bool {
        return AppStore.canMakePayments
    }

    // MARK: - 清除错误
    func clearError() {
        lastError = nil
    }

    private static func notifyPetStatusDidChange() {
        NotificationCenter.default.post(
            name: Notification.Name("PetStatusDidUpdateExternally"),
            object: nil
        )
    }

    private func showPurchaseSuccessMessage(_ message: String) async {
        await MainActor.run {
            purchaseSuccess = true
            purchaseSuccessMessage = message

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.purchaseSuccess = false
                self.purchaseSuccessMessage = ""
            }
        }
    }
}
