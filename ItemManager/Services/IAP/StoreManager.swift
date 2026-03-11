import Foundation
import StoreKit
import Combine

// MARK: - StoreManager
// StoreKit 2 支付管理类，处理所有内购相关逻辑
// 包括商品获取、购买流程、交易验证、恢复购买等

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - Published Properties
    @Published var coinProducts: [Product] = []           // 喵币商品列表
    @Published var subscriptionProducts: [Product] = []   // VIP订阅商品列表
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
    // 3. 订阅续订通知
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

            // 分类商品
            coinProducts = products.filter { product in
                IAPProductType.coinProductIDs.contains(product.id)
            }.sorted { p1, p2 in
                // 按价格排序
                p1.price < p2.price
            }

            subscriptionProducts = products.filter { product in
                IAPProductType.subscriptionProductIDs.contains(product.id)
            }.sorted { p1, p2 in
                p1.price < p2.price
            }

            print("[StoreManager] 获取到 \(coinProducts.count) 个喵币商品, \(subscriptionProducts.count) 个订阅商品")

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

        // 使用测试管理器模拟验证
        let result = IAPTestManager.shared.mockVerifyPayment(productID: product.id)

        switch result {
        case .success(let deliveredCoins, _, let isFirstDouble):
            // 显示成功消息
            await MainActor.run {
                purchaseSuccess = true
                if isFirstDouble {
                    purchaseSuccessMessage = "🎉 首充双倍！获得 \(deliveredCoins) 喵币"
                } else {
                    purchaseSuccessMessage = "成功获得 \(deliveredCoins) 喵币"
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.purchaseSuccess = false
                    self.purchaseSuccessMessage = ""
                }
            }

            // 测试模式返回成功，transaction为nil（测试模式不处理真实Transaction）
            return .success(transaction: nil, product: product)

        case .failure(let error):
            return .failed(.purchaseFailed(error))
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

                // 发送到服务器验证并发放喵币
                let serverSuccess = await IAPServerManager.shared.verifyAndDeliver(
                    transaction: transaction,
                    productID: product.id
                )

                if serverSuccess {
                    await transaction.finish()
                    return .success(transaction: transaction, product: product)
                } else {
                    return .failed(.serverVerificationFailed("服务器验证失败"))
                }

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

    // MARK: - 恢复购买
    // 恢复用户的非消耗型购买和订阅
    // 用户可以在新设备上恢复之前的购买
    func restorePurchases() async -> IAPRestoreResult {
        isLoading = true
        defer { isLoading = false }

        do {
            var restoredTransactions: [Transaction] = []

            // 遍历当前用户的所有交易
            for await result in Transaction.currentEntitlements {
                do {
                    let transaction = try checkVerified(result)
                    restoredTransactions.append(transaction)

                    // 恢复订阅状态
                    if transaction.productType == .autoRenewable {
                        await restoreSubscription(transaction)
                    }
                } catch {
                    print("[StoreManager] 恢复交易验证失败: \(error)")
                }
            }

            if restoredTransactions.isEmpty {
                return .empty
            }

            return .success(restoredTransactions: restoredTransactions)

        } catch {
            print("[StoreManager] 恢复购买失败: \(error)")
            return .failed(.purchaseFailed(error.localizedDescription))
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

            case .vipMonthly, .vipYearly:
                await activateVIP(for: transaction, productType: productType)
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

    // MARK: - 激活VIP
    // 根据订阅类型激活VIP会员
    private func activateVIP(for transaction: Transaction, productType: IAPProductType) async {
        let months: Int
        switch productType {
        case .vipMonthly:
            months = 1
        case .vipYearly:
            months = 12
        default:
            return
        }

        // 更新VIP状态
        await MainActor.run {
            var status = PetDataManager.shared.status

            // 计算新的过期时间
            let currentExpireDate = status.vipStatus.expireDate ?? Date()
            let baseDate = currentExpireDate > Date() ? currentExpireDate : Date()

            if let newExpireDate = Calendar.current.date(byAdding: .month, value: months, to: baseDate) {
                status.vipStatus.isActive = true
                status.vipStatus.expireDate = newExpireDate

                // 生成VIP号码（如果没有）
                if status.vipStatus.vipNumber == nil {
                    status.vipStatus.vipNumber = generateVIPNumber()
                }

                PetDataManager.shared.saveStatus(status)

                // 显示成功消息
                purchaseSuccess = true
                purchaseSuccessMessage = "VIP开通成功！有效期至 \(newExpireDate.formatted(date: .numeric, time: .omitted))"

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.purchaseSuccess = false
                    self.purchaseSuccessMessage = ""
                }
            }
        }

        // 记录购买历史
        let record = IAPPurchaseRecord(
            id: String(transaction.id),
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            coinAmount: nil,
            subscriptionMonths: months,
            isVerified: true,
            verificationDate: Date()
        )
        savePurchaseRecord(record)

        print("[StoreManager] 激活VIP: \(months) 个月")
    }

    // MARK: - 恢复订阅
    // 恢复订阅状态
    private func restoreSubscription(_ transaction: Transaction) async {
        guard let productType = IAPProductType(rawValue: transaction.productID),
              productType == .vipMonthly || productType == .vipYearly else {
            return
        }

        // 检查订阅是否仍然有效
        if let expirationDate = transaction.expirationDate,
           expirationDate > Date() {
            await MainActor.run {
                var status = PetDataManager.shared.status
                status.vipStatus.isActive = true
                status.vipStatus.expireDate = expirationDate
                PetDataManager.shared.saveStatus(status)
            }
        }
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

    // MARK: - 生成VIP号码
    // 生成一个吉利的VIP号码
    private func generateVIPNumber() -> String {
        let length = Int.random(in: 6...8)
        let luckyDigits = ["6", "8", "9", "0", "8", "6"]
        let allDigits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

        var result = ""
        for _ in 0..<length {
            if Int.random(in: 1...10) <= 7 {
                result += luckyDigits.randomElement()!
            } else {
                result += allDigits.randomElement()!
            }
        }
        return result
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

    static func saveMeowCoinAccount(_ account: MeowCoinAccount) {
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: MeowCoinAccount.storageKey)
        }
    }

    // MARK: - 消费喵币
    // 用于购买虚拟物品时扣除喵币
    static func spendMeowCoins(_ amount: Int) -> Bool {
        var account = loadMeowCoinAccount()
        guard account.balance >= amount else { return false }

        account.balance -= amount
        account.totalSpent += amount
        account.lastUpdated = Date()
        saveMeowCoinAccount(account)

        // 同步到 PetDataManager
        var status = PetDataManager.shared.status
        status.meowCoin = account.balance
        PetDataManager.shared.saveStatus(status)

        return true
    }

    // MARK: - 获取当前喵币余额
    static func getCurrentBalance() -> Int {
        return loadMeowCoinAccount().balance
    }

    // MARK: - 检查是否可以购买
    func canMakePurchases() -> Bool {
        return AppStore.canMakePayments
    }

    // MARK: - 清除错误
    func clearError() {
        lastError = nil
    }
}
