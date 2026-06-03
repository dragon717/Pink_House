import Foundation
import StoreKit
import Combine

struct IAPPurchaseSuccessContext: Identifiable, Equatable {
    let id = UUID()
    let attemptID: String?
    let source: String
    let message: String
}

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
    @Published var purchaseSuccessContext: IAPPurchaseSuccessContext?

    // 交易更新监听器
    private var transactionListener: Task<Void, Error>?
    private var storefrontListener: Task<Void, Never>?

    // 已处理的交易ID集合（防止重复处理）
    private var processedTransactionIDs: Set<String> = []
    private var lastObservedStorefrontSignature: String?

    // MARK: - Initialization
    private init() {
        // 启动交易监听器，处理未完成交易和外部交易
        startTransactionListener()
        startStorefrontListener()
        // 加载已处理的交易ID
        loadProcessedTransactions()
        recoverUnfinishedTransactions()
    }

    deinit {
        transactionListener?.cancel()
        storefrontListener?.cancel()
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
                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "transaction_update_received",
                        productID: transaction.productID,
                        transactionID: String(transaction.id),
                        fields: [
                            "source": "transaction_updates",
                            "purchaseDate": transaction.purchaseDate.ISO8601Format()
                        ]
                    )

                    // 检查是否已处理过
                    if await self.isTransactionProcessed(transaction.id) {
                        await IAPDiagnosticStore.shared.record(
                            category: .flow,
                            name: "transaction_update_already_processed",
                            level: .notice,
                            productID: transaction.productID,
                            transactionID: String(transaction.id),
                            fields: ["source": "transaction_updates"]
                        )
                        await transaction.finish()
                        continue
                    }

                    // 处理交易
                    await self.processTransaction(transaction, source: "transaction_updates", attemptID: nil)
                } catch {
                    print("[StoreManager] 交易验证失败: \(error)")
                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "transaction_update_verification_failed",
                        level: .error,
                        fields: [
                            "source": "transaction_updates",
                            "error": error.localizedDescription
                        ]
                    )
                }
            }
        }
    }

    private func startStorefrontListener() {
        storefrontListener?.cancel()
        storefrontListener = Task { [weak self] in
            guard let self = self else { return }

            let currentStorefront = await Storefront.current
            await self.handleObservedStorefront(
                currentStorefront,
                source: "current",
                shouldRefreshProducts: false
            )

            for await storefront in Storefront.updates {
                if Task.isCancelled { break }
                await self.handleObservedStorefront(
                    storefront,
                    source: "updates",
                    shouldRefreshProducts: true
                )
            }
        }
    }

    private func handleObservedStorefront(
        _ storefront: Storefront?,
        source: String,
        shouldRefreshProducts: Bool
    ) async {
        let fields = storefrontFields(from: storefront)
        let signature = storefrontSignature(from: storefront)
        let previousSignature = lastObservedStorefrontSignature
        let previousFields = storefrontFields(fromSignature: previousSignature)

        if previousSignature == nil {
            lastObservedStorefrontSignature = signature
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "storefront_observed_initial",
                fields: fields.merging(["source": source]) { _, new in new }
            )
            return
        }

        guard previousSignature != signature else {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "storefront_update_ignored_same_value",
                fields: fields.merging(["source": source]) { _, new in new }
            )
            return
        }

        lastObservedStorefrontSignature = signature
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "storefront_changed",
            level: .notice,
            fields: [
                "source": source,
                "previousStorefrontCountryCode": previousFields["storefrontCountryCode"] ?? "nil",
                "previousStorefrontCurrency": previousFields["storefrontCurrency"] ?? "nil",
                "previousStorefrontID": previousFields["storefrontID"] ?? "nil"
            ].merging(fields) { _, new in new }
        )

        guard shouldRefreshProducts else { return }

        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "storefront_refreshing_products",
            level: .notice,
            fields: fields.merging(["source": source]) { _, new in new }
        )
        await fetchProducts()
    }

    // MARK: - 获取商品信息
    // 从 App Store 获取商品信息
    // 需要在 App Store Connect 中预先配置商品
    func fetchProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allProductIDs = IAPProductType.allProductIDs
            let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
            let logPrefix = "[IAPFetch]"

            print("\(logPrefix) ===== 商品拉取开始 =====")
            print("\(logPrefix) bundleID=\(bundleID)")
            print("\(logPrefix) requestedIDs=\(allProductIDs.joined(separator: ", "))")
            let fetchStorefrontFields = await currentStorefrontFields()
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "product_fetch_started",
                fields: [
                    "bundleID": bundleID,
                    "requestedIDs": allProductIDs.joined(separator: ",")
                ].merging(fetchStorefrontFields) { _, new in new }
            )

            let products = try await Product.products(for: allProductIDs)

            coinProducts = products.filter { product in
                IAPProductType.coinProductIDs.contains(product.id)
            }.sorted { p1, p2 in
                // 按价格排序
                p1.price < p2.price
            }

            print("\(logPrefix) matchedCount=\(coinProducts.count)")

            if coinProducts.isEmpty {
                print("\(logPrefix) result=EMPTY")
                print("\(logPrefix) reasonHint=Apple 未返回任何匹配的喵币商品")
            } else {
                for product in coinProducts {
                    print("\(logPrefix) returnedProduct id=\(product.id) | name=\(product.displayName) | price=\(product.displayPrice) | type=\(product.type)")
                }
            }

            let returnedIDs = Set(products.map(\.id))
            let missingIDs = allProductIDs.filter { !returnedIDs.contains($0) }
            if !missingIDs.isEmpty {
                print("\(logPrefix) missingIDs=\(missingIDs.joined(separator: ", "))")
            } else {
                print("\(logPrefix) missingIDs=none")
            }

            print("\(logPrefix) ===== 商品拉取结束 =====")
            let fetchFinishedStorefrontFields = await currentStorefrontFields()
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "product_fetch_finished",
                level: coinProducts.isEmpty ? .notice : .info,
                fields: [
                    "matchedCount": String(coinProducts.count),
                    "missingIDs": missingIDs.joined(separator: ",").isEmpty ? "none" : missingIDs.joined(separator: ",")
                ].merging(fetchFinishedStorefrontFields) { _, new in new }
            )

        } catch {
            print("[IAPFetch] ===== 商品拉取失败 =====")
            print("[IAPFetch] error=\(error)")
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "product_fetch_failed",
                level: .error,
                fields: ["error": error.localizedDescription]
            )
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
    func purchase(_ product: Product, attemptID: String) async -> IAPPurchaseResult {
        isPurchasing = true
        defer { isPurchasing = false }

        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "purchase_requested",
            attemptID: attemptID,
            productID: product.id,
            fields: [
                "isTestMode": String(IAPTestManager.shared.isTestMode),
                "displayPrice": product.displayPrice
            ]
        )

        // 测试模式：使用模拟支付
        if IAPTestManager.shared.isTestMode {
            return await purchaseInTestMode(product: product, attemptID: attemptID)
        }

        // 生产模式：正常Apple支付流程
        return await purchaseInProductionMode(product: product, attemptID: attemptID)
    }

    // MARK: - 测试模式购买
    private func purchaseInTestMode(product: Product, attemptID: String) async -> IAPPurchaseResult {
        // 模拟购买延迟
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "purchase_test_mode_started",
            attemptID: attemptID,
            productID: product.id
        )

        guard IAPProductType(rawValue: product.id) != nil else {
            return .failed(.productNotFound(product.id))
        }

        let result = IAPTestManager.shared.mockVerifyPayment(productID: product.id)

        switch result {
        case .success(let deliveredCoins, _, let isFirstDouble):
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_test_mode_succeeded",
                attemptID: attemptID,
                productID: product.id,
                fields: [
                    "deliveredCoins": String(deliveredCoins),
                    "isFirstDouble": String(isFirstDouble)
                ]
            )
            await publishPurchaseSuccess(
                isFirstDouble
                ? "🎉 首充双倍！获得 %d 喵币".appLocalized(deliveredCoins)
                : "成功获得 %d 喵币".appLocalized(deliveredCoins),
                attemptID: attemptID,
                source: "test_mode"
            )
            return .success(transaction: nil, product: product)

        case .failure(let error):
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_test_mode_failed",
                level: .error,
                attemptID: attemptID,
                productID: product.id,
                fields: ["error": error]
            )
            return .failed(.purchaseFailed(error))
        }
    }

    // MARK: - 生产模式购买
    private func purchaseInProductionMode(product: Product, attemptID: String) async -> IAPPurchaseResult {
        do {
            // 准备购买选项
            var options: Set<Product.PurchaseOption> = []
            // 可选：传入appAccountToken用于关联用户（当前使用本地验证，不需要）
            // if let userUUID = getCurrentUserUUID() {
            //     options.insert(.appAccountToken(userUUID))
            // }

            // 发起购买请求
            let purchaseStorefrontFields = await currentStorefrontFields()
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_invoking_storekit",
                attemptID: attemptID,
                productID: product.id,
                fields: [
                    "optionsCount": String(options.count)
                ].merging(purchaseStorefrontFields) { _, new in new }
            )
            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                // 验证交易
                let transaction = try await checkVerified(verification)
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_verification_succeeded",
                    attemptID: attemptID,
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    fields: [
                        "purchaseDate": transaction.purchaseDate.ISO8601Format(),
                        "transactionEnvironment": String(describing: transaction.environment),
                        "transactionStorefrontCountryCode": transaction.storefront.countryCode,
                        "transactionStorefrontCurrency": transaction.storefront.currency?.identifier ?? "nil",
                        "transactionStorefrontID": transaction.storefront.id
                    ]
                )

                // 检查是否已处理
                if isTransactionProcessed(transaction.id) {
                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "purchase_duplicate_transaction",
                        level: .notice,
                        attemptID: attemptID,
                        productID: transaction.productID,
                        transactionID: String(transaction.id)
                    )
                    await transaction.finish()
                    return .failed(.alreadyProcessed)
                }

                await processTransaction(transaction, source: "purchase_flow", attemptID: attemptID)
                return .success(transaction: transaction, product: product)

            case .userCancelled:
                print("[StoreManager] 用户取消购买")
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_cancelled",
                    level: .notice,
                    attemptID: attemptID,
                    productID: product.id
                )
                return .cancelled

            case .pending:
                print("[StoreManager] 购买等待中")
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_pending",
                    level: .notice,
                    attemptID: attemptID,
                    productID: product.id
                )
                return .pending

            @unknown default:
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_unknown_result",
                    level: .error,
                    attemptID: attemptID,
                    productID: product.id
                )
                return .failed(.purchaseFailed("未知状态".appLocalized))
            }

        } catch let error as Product.PurchaseError {
            print("[StoreManager] 购买错误: \(error)")
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_storekit_error",
                level: .error,
                attemptID: attemptID,
                productID: product.id,
                fields: ["error": String(describing: error)]
            )
            let iapError = IAPError.from(purchaseError: error)
            lastError = iapError
            return .failed(iapError)

        } catch {
            print("[StoreManager] 购买失败: \(error)")
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_failed",
                level: .error,
                attemptID: attemptID,
                productID: product.id,
                fields: ["error": error.localizedDescription]
            )
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
    private func processTransaction(_ transaction: Transaction, source: String, attemptID: String?) async {
        print("[StoreManager] 处理交易: \(transaction.id)")
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "transaction_processing_started",
            attemptID: attemptID,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                "source": source,
                "purchaseDate": transaction.purchaseDate.ISO8601Format(),
                "offerType": transaction.offerType.map { String(describing: $0) } ?? "nil",
                "offerID": transaction.offerID ?? "nil"
            ]) { _, new in new }
        )

        // 标记为已处理
        markTransactionAsProcessed(transaction.id)

        // 根据商品类型处理
        if let productType = IAPProductType(rawValue: transaction.productID) {
            let shouldHandleAsOfferCodeRedemption: Bool
            if isOfferCodeRedemptionTransaction(transaction) {
                shouldHandleAsOfferCodeRedemption = true
            } else {
                shouldHandleAsOfferCodeRedemption = await consumeOfferCodeRedemptionSessionIfNeeded(for: transaction, source: source, attemptID: attemptID)
            }

            if shouldHandleAsOfferCodeRedemption {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "offer_code_transaction_detected",
                    level: .notice,
                    attemptID: attemptID,
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    fields: transactionDiagnosticFields(for: transaction, source: source)
                )
                await deliverOfferCodeMeowCoins(for: transaction, attemptID: attemptID, source: IAPOfferCodeRedemption.source)
            } else {
                await deliverMeowCoins(for: transaction, productType: productType, attemptID: attemptID, source: source)
            }
        }

        // 完成交易
        await transaction.finish()
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "transaction_finished",
            attemptID: attemptID,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            fields: ["source": source]
        )
    }

    private func recoverUnfinishedTransactions() {
        Task.detached { [weak self] in
            for await result in Transaction.unfinished {
                guard let self = self else { return }

                do {
                    let transaction = try await self.checkVerified(result)
                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "unfinished_transaction_received",
                        level: .notice,
                        productID: transaction.productID,
                        transactionID: String(transaction.id),
                        fields: transactionDiagnosticFields(for: transaction, source: "unfinished_transactions").merging([
                            "purchaseDate": transaction.purchaseDate.ISO8601Format(),
                            "offerType": transaction.offerType.map { String(describing: $0) } ?? "nil",
                            "offerID": transaction.offerID ?? "nil"
                        ]) { _, new in new }
                    )

                    if await self.isTransactionProcessed(transaction.id) {
                        await IAPDiagnosticStore.shared.record(
                            category: .flow,
                            name: "unfinished_transaction_already_processed",
                            level: .notice,
                            productID: transaction.productID,
                            transactionID: String(transaction.id)
                        )
                        await transaction.finish()
                        continue
                    }

                    await self.processTransaction(transaction, source: "unfinished_transactions", attemptID: nil)
                } catch {
                    await IAPDiagnosticStore.shared.record(
                        category: .flow,
                        name: "unfinished_transaction_verification_failed",
                        level: .error,
                        fields: ["error": error.localizedDescription]
                    )
                }
            }
        }
    }

    // MARK: - App Store 优惠码兑换会话

    func prepareOfferCodeRedemptionSession(source: String) async -> Bool {
        let canMakePurchases = canMakePurchases()
        let eligibleProductIDs = IAPOfferCodeRedemption.eligibleProductIDs
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "offer_code_redemption_prepare_started",
            level: .notice,
            fields: [
                "source": source,
                "canMakePurchases": String(canMakePurchases),
                "eligibleProductIDs": eligibleProductIDs.joined(separator: ",")
            ].merging(await currentStorefrontFields()) { _, new in new }
        )

        guard canMakePurchases else {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "offer_code_redemption_prepare_blocked_cannot_make_payments",
                level: .notice,
                fields: [
                    "source": source,
                    "eligibleProductIDs": eligibleProductIDs.joined(separator: ",")
                ]
            )
            return false
        }

        await fetchProducts()

        let availableProductIDs = coinProducts.map(\.id)
        let availableProductIDSet = Set(availableProductIDs)
        let missingProductIDs = eligibleProductIDs.filter { !availableProductIDSet.contains($0) }
        let hasAnyEligibleProductAvailable = eligibleProductIDs.contains { availableProductIDSet.contains($0) }
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: hasAnyEligibleProductAvailable ? "offer_code_redemption_prepare_products_available" : "offer_code_redemption_prepare_products_missing",
            level: hasAnyEligibleProductAvailable ? .notice : .error,
            fields: [
                "source": source,
                "eligibleProductIDs": eligibleProductIDs.joined(separator: ","),
                "availableProductIDs": availableProductIDs.joined(separator: ","),
                "missingProductIDs": missingProductIDs.isEmpty ? "none" : missingProductIDs.joined(separator: ",")
            ].merging(await currentStorefrontFields()) { _, new in new }
        )

        guard hasAnyEligibleProductAvailable else {
            clearOfferCodeRedemptionSession()
            return false
        }

        beginOfferCodeRedemptionSession(source: source)
        return true
    }

    func beginOfferCodeRedemptionSession(source: String) {
        let defaults = UserDefaults.standard
        let startedAt = Date().timeIntervalSince1970
        defaults.set(startedAt, forKey: IAPOfferCodeRedemption.pendingStartedAtKey)

        Task {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "offer_code_redemption_session_started",
                level: .notice,
                fields: [
                    "source": source,
                    "ttlSeconds": String(Int(IAPOfferCodeRedemption.pendingSessionTTL)),
                    "eligibleProductIDs": IAPOfferCodeRedemption.eligibleProductIDs.joined(separator: ",")
                ].merging(await currentStorefrontFields()) { _, new in new }
            )
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(IAPOfferCodeRedemption.pendingSessionTTL * 1_000_000_000))
            await self?.recordOfferCodeRedemptionSessionTimeoutIfNeeded(startedAt: startedAt, source: source)
        }
    }

    func cancelOfferCodeRedemptionSession(reason: String) {
        clearOfferCodeRedemptionSession()

        Task {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "offer_code_redemption_session_cancelled",
                level: .notice,
                fields: [
                    "reason": reason,
                    "eligibleProductIDs": IAPOfferCodeRedemption.eligibleProductIDs.joined(separator: ",")
                ]
            )
        }
    }

    private func consumeOfferCodeRedemptionSessionIfNeeded(
        for transaction: Transaction,
        source: String,
        attemptID: String?
    ) async -> Bool {
        guard attemptID == nil,
              ["transaction_updates", "unfinished_transactions"].contains(source),
              IAPOfferCodeRedemption.baseCoinAmount(for: transaction.productID) != nil else {
            return false
        }

        let defaults = UserDefaults.standard
        let startedAt = defaults.double(forKey: IAPOfferCodeRedemption.pendingStartedAtKey)
        guard startedAt > 0 else {
            clearOfferCodeRedemptionSession()
            return false
        }

        let elapsed = Date().timeIntervalSince1970 - startedAt
        guard elapsed <= IAPOfferCodeRedemption.pendingSessionTTL else {
            clearOfferCodeRedemptionSession()
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "offer_code_redemption_session_expired",
                level: .notice,
                productID: transaction.productID,
                transactionID: String(transaction.id),
                fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                    "elapsedSeconds": String(Int(elapsed))
                ]) { _, new in new }
            )
            return false
        }

        let transactionTime = transaction.purchaseDate.timeIntervalSince1970
        guard transactionTime >= startedAt - 60 else {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "offer_code_redemption_old_transaction_ignored",
                level: .notice,
                productID: transaction.productID,
                transactionID: String(transaction.id),
                fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                    "sessionStartedAt": String(Int(startedAt)),
                    "transactionPurchaseDate": String(Int(transactionTime))
                ]) { _, new in new }
            )
            return false
        }

        clearOfferCodeRedemptionSession()
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "offer_code_redemption_session_consumed",
            level: .notice,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                "source": source,
                "elapsedSeconds": String(Int(elapsed))
            ]) { _, new in new }
        )
        return true
    }

    private func isOfferCodeRedemptionTransaction(_ transaction: Transaction) -> Bool {
        transaction.offerType == .code && IAPOfferCodeRedemption.baseCoinAmount(for: transaction.productID) != nil
    }

    private func clearOfferCodeRedemptionSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: IAPOfferCodeRedemption.pendingStartedAtKey)
    }

    private func recordOfferCodeRedemptionSessionTimeoutIfNeeded(startedAt: TimeInterval, source: String) async {
        let currentStartedAt = UserDefaults.standard.double(forKey: IAPOfferCodeRedemption.pendingStartedAtKey)
        guard currentStartedAt == startedAt else { return }

        clearOfferCodeRedemptionSession()
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "redemption_session_timed_out_no_transaction",
            level: .notice,
            fields: [
                "source": source,
                "ttlSeconds": String(Int(IAPOfferCodeRedemption.pendingSessionTTL)),
                "eligibleProductIDs": IAPOfferCodeRedemption.eligibleProductIDs.joined(separator: ",")
            ].merging(await currentStorefrontFields()) { _, new in new }
        )
    }

    // MARK: - 发放喵币
    // 根据购买的商品发放相应数量的喵币（支持首次双倍活动）
    private func deliverMeowCoins(for transaction: Transaction, productType: IAPProductType, attemptID: String?, source: String) async {
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

        let successMessage: String
        if isFirstDouble {
            successMessage = "🎉 首充双倍！获得 %d 喵币".appLocalized(totalAmount)
        } else if bonus > 0 {
            successMessage = "成功获得 %d 喵币（含赠送 %d）".appLocalized(totalAmount, bonus)
        } else {
            successMessage = "成功获得 %d 喵币".appLocalized(totalAmount)
        }

        // 更新用户喵币余额
        await MainActor.run {
            let previousAccountBalance = Self.loadMeowCoinAccount().balance
            let previousStatusBalance = PetDataManager.shared.status.meowCoin
            var account = Self.loadMeowCoinAccount()
            account.balance += totalAmount
            account.totalPurchased += totalAmount
            account.lastUpdated = Date()
            Self.saveMeowCoinAccount(account)

            // 同时更新 PetDataManager 中的喵币
            var status = PetDataManager.shared.status
            status.meowCoin = account.balance
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "balance_delivery_pre_save",
                    attemptID: attemptID,
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    fields: [
                        "source": source,
                        "previousAccountBalance": String(previousAccountBalance),
                        "previousStatusBalance": String(previousStatusBalance),
                        "newAccountBalance": String(account.balance),
                        "newStatusBalance": String(status.meowCoin),
                        "deliveredAmount": String(totalAmount)
                    ]
                )
            }
            PetDataManager.shared.saveStatus(status)
            Self.notifyPetStatusDidChange()
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "balance_delivery_post_save",
                    attemptID: attemptID,
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    fields: [
                        "source": source,
                        "storedAccountBalance": String(Self.loadMeowCoinAccount().balance),
                        "storedStatusBalance": String(PetDataManager.shared.status.meowCoin),
                        "purchaseSuccessMessage": bonus > 0 ? "coin_delivery_with_bonus" : "coin_delivery"
                    ]
                )
            }

        }

        await publishPurchaseSuccess(
            successMessage,
            attemptID: attemptID,
            source: source
        )

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
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "coin_delivery_completed",
            attemptID: attemptID,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            fields: [
                "source": source,
                "baseAmount": String(baseAmount),
                "bonusAmount": String(bonus),
                "totalAmount": String(totalAmount),
                "isFirstDouble": String(isFirstDouble)
            ]
        )
    }

    // MARK: - 发放 App Store 优惠码喵币
    // 优惠码绑定现有喵币档位；免费兑换只发对应档位基础喵币，不消耗首充双倍资格。
    private func deliverOfferCodeMeowCoins(for transaction: Transaction, attemptID: String?, source: String) async {
        guard let meowCoinAmount = IAPOfferCodeRedemption.baseCoinAmount(for: transaction.productID) else {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "offer_code_delivery_failed_unknown_product",
                level: .error,
                attemptID: attemptID,
                productID: transaction.productID,
                transactionID: String(transaction.id),
                fields: transactionDiagnosticFields(for: transaction, source: source)
            )
            return
        }

        await MainActor.run {
            let previousAccountBalance = Self.loadMeowCoinAccount().balance
            let previousStatusMeowCoin = PetDataManager.shared.status.meowCoin

            var account = Self.loadMeowCoinAccount()
            account.balance += meowCoinAmount
            account.totalPurchased += meowCoinAmount
            account.lastUpdated = Date()
            Self.saveMeowCoinAccount(account)

            var status = PetDataManager.shared.status
            status.meowCoin = account.balance

            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "offer_code_delivery_pre_save",
                    attemptID: attemptID,
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                        "source": source,
                        "previousAccountBalance": String(previousAccountBalance),
                        "previousStatusMeowCoin": String(previousStatusMeowCoin),
                        "newAccountBalance": String(account.balance),
                        "newStatusMeowCoin": String(status.meowCoin),
                        "deliveredMeowCoin": String(meowCoinAmount),
                        "firstDoubleConsumed": "false"
                    ]) { _, new in new }
                )
            }

            PetDataManager.shared.saveStatus(status)
            Self.notifyPetStatusDidChange()

            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "offer_code_delivery_post_save",
                    attemptID: attemptID,
                    productID: transaction.productID,
                    transactionID: String(transaction.id),
                    fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                        "source": source,
                        "storedAccountBalance": String(Self.loadMeowCoinAccount().balance),
                        "storedStatusMeowCoin": String(PetDataManager.shared.status.meowCoin)
                    ]) { _, new in new }
                )
            }
        }

        await publishPurchaseSuccess(
            IAPOfferCodeRedemption.successMessage(for: meowCoinAmount),
            attemptID: attemptID,
            source: source
        )

        let record = IAPPurchaseRecord(
            id: String(transaction.id),
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            coinAmount: meowCoinAmount,
            subscriptionMonths: nil,
            isVerified: true,
            verificationDate: Date()
        )
        savePurchaseRecord(record)

        print("[StoreManager] 发放 App Store 优惠码喵币: \(meowCoinAmount) 喵币")
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "offer_code_delivery_completed",
            attemptID: attemptID,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            fields: transactionDiagnosticFields(for: transaction, source: source).merging([
                "source": source,
                "meowCoinAmount": String(meowCoinAmount),
                "firstDoubleConsumed": "false"
            ]) { _, new in new }
        )
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
            let previousBalance = account.balance
            let previousSpent = account.totalSpent
            account.balance = actualBalance
            account.totalSpent = inferredSpent
            account.lastUpdated = Date()
            saveMeowCoinAccount(account)
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .balance,
                    name: "balance_synchronized_from_status",
                    level: .notice,
                    fields: [
                        "previousAccountBalance": String(previousBalance),
                        "actualStatusBalance": String(actualBalance),
                        "previousTotalSpent": String(previousSpent),
                        "newTotalSpent": String(inferredSpent)
                    ]
                )
            }
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

        let previousBalance = status.meowCoin
        status.meowCoin -= amount

        var account = synchronizedMeowCoinAccount()
        account.balance = status.meowCoin
        account.totalSpent += amount
        account.lastUpdated = Date()
        saveMeowCoinAccount(account)
        let newBalance = status.meowCoin
        let totalSpent = account.totalSpent
        Task {
            await IAPDiagnosticStore.shared.record(
                category: .balance,
                name: "balance_spent",
                fields: [
                    "spentAmount": String(amount),
                    "previousStatusBalance": String(previousBalance),
                    "newStatusBalance": String(newBalance),
                    "accountTotalSpent": String(totalSpent)
                ]
            )
        }

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

    private func publishPurchaseSuccess(_ message: String, attemptID: String?, source: String) async {
        await MainActor.run {
            purchaseSuccessMessage = message
            let context = IAPPurchaseSuccessContext(
                attemptID: attemptID,
                source: source,
                message: message
            )
            purchaseSuccessContext = context
            purchaseSuccess = true
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_success_state_published",
                    level: source == "transaction_updates" ? .notice : .info,
                    attemptID: attemptID,
                    fields: [
                        "message": message,
                        "source": source
                    ]
                )
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.purchaseSuccess = false
                self.purchaseSuccessMessage = ""
                if self.purchaseSuccessContext == context {
                    self.purchaseSuccessContext = nil
                }
            }
        }
    }

    private func currentStorefrontFields() async -> [String: String] {
        let storefront = await Storefront.current
        return storefrontFields(from: storefront)
    }

    private func transactionDiagnosticFields(for transaction: Transaction, source: String) -> [String: String] {
        [
            "source": source,
            "transactionEnvironment": String(describing: transaction.environment),
            "transactionStorefrontCountryCode": transaction.storefront.countryCode,
            "transactionStorefrontCurrency": transaction.storefront.currency?.identifier ?? "nil",
            "transactionStorefrontID": transaction.storefront.id,
            "purchaseDate": transaction.purchaseDate.ISO8601Format(),
            "offerType": transaction.offerType.map { String(describing: $0) } ?? "nil",
            "offerID": transaction.offerID ?? "nil"
        ]
    }

    private func storefrontFields(from storefront: Storefront?) -> [String: String] {
        guard let storefront else {
            return [
                "storefrontCountryCode": "nil",
                "storefrontCurrency": "nil",
                "storefrontID": "nil"
            ]
        }

        return [
            "storefrontCountryCode": storefront.countryCode,
            "storefrontCurrency": storefront.currency?.identifier ?? "nil",
            "storefrontID": storefront.id
        ]
    }

    private func storefrontSignature(from storefront: Storefront?) -> String {
        let fields = storefrontFields(from: storefront)
        return [
            fields["storefrontCountryCode"] ?? "nil",
            fields["storefrontCurrency"] ?? "nil",
            fields["storefrontID"] ?? "nil"
        ].joined(separator: "|")
    }

    private func storefrontFields(fromSignature signature: String?) -> [String: String] {
        guard let signature else {
            return [
                "storefrontCountryCode": "nil",
                "storefrontCurrency": "nil",
                "storefrontID": "nil"
            ]
        }

        let components = signature.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return [
            "storefrontCountryCode": components.indices.contains(0) ? components[0] : "nil",
            "storefrontCurrency": components.indices.contains(1) ? components[1] : "nil",
            "storefrontID": components.indices.contains(2) ? components[2] : "nil"
        ]
    }
}
