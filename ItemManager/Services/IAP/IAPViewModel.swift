import Foundation
import StoreKit
import Combine
import SwiftUI

// MARK: - IAPViewModel
// 内购业务逻辑层，连接 StoreManager 和 UI
// 提供友好的接口给 SwiftUI 视图使用

@MainActor
class IAPViewModel: ObservableObject {
    static let shared = IAPViewModel()

    // MARK: - Published Properties
    @Published var meowCoinProducts: [MeowCoinProductDisplay] = []
    @Published var currentBalance: Int = 0
    @Published var isVIP: Bool = false
    @Published var vipExpireDate: Date?
    @Published var isLoading: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var showSuccessToast: Bool = false
    @Published var successMessage: String = ""
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String = ""
    @Published var firstPurchaseStatusVersion: Int = 0

    // MARK: - Private Properties
    private var storeManager = StoreManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var activePurchaseAttemptID: String?

    // MARK: - Initialization
    private init() {
        setupBindings()
        loadUserData()
    }

    // MARK: - 绑定 StoreManager
    private func setupBindings() {
        // 监听 StoreManager 的状态变化
        storeManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        storeManager.$isPurchasing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPurchasing)

        storeManager.$purchaseSuccessContext
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] context in
                self?.handlePurchaseSuccessContext(context)
            }
            .store(in: &cancellables)

        storeManager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.showErrorAlert = true
                    self?.errorMessage = error.errorDescription ?? "购买失败"
                }
            }
            .store(in: &cancellables)

        storeManager.$coinProducts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] products in
                self?.updateMeowCoinProducts(products)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .petStatusDidUpdateExternally)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadUserData()
            }
            .store(in: &cancellables)

    }

    // MARK: - 加载用户数据
    func loadUserData() {
        // 加载喵币余额
        currentBalance = StoreManager.getCurrentBalance()

        // 加载VIP状态
        let status = PetDataManager.shared.status
        isVIP = status.vipStatus.isActive && !status.vipStatus.isExpired
        vipExpireDate = status.vipStatus.expireDate
        firstPurchaseStatusVersion &+= 1
    }

    // MARK: - 更新商品展示数据
    private func updateMeowCoinProducts(_ products: [Product]) {
        meowCoinProducts = products.compactMap { product in
            guard let type = IAPProductType(rawValue: product.id) else { return nil }
            return MeowCoinProductDisplay(from: product, type: type)
        }.sorted { $0.coinAmount < $1.coinAmount }
    }

    // MARK: - 获取商品
    func fetchProducts() async {
        await storeManager.fetchProducts()
    }

    // MARK: - 购买喵币
    func purchaseMeowCoin(product: MeowCoinProductDisplay) async {
        let attemptID = IAPDiagnosticStore.makeAttemptID()

        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "purchase_tapped",
            attemptID: attemptID,
            productID: product.id,
            fields: [
                "displayPrice": product.price,
                "currentBalance": String(currentBalance),
                "uiIsPurchasing": String(isPurchasing)
            ]
        )

        if isPurchasing || storeManager.isPurchasing {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_tap_ignored_already_purchasing",
                level: .notice,
                attemptID: attemptID,
                productID: product.id
            )
            return
        }

        let canMakePurchases = storeManager.canMakePurchases()
        await IAPDiagnosticStore.shared.record(
            category: .flow,
            name: "purchase_capability_checked",
            attemptID: attemptID,
            productID: product.id,
            fields: ["canMakePurchases": String(canMakePurchases)]
        )

        guard canMakePurchases else {
            showErrorAlert = true
            errorMessage = "当前设备或账户无法发起购买，请检查系统购买限制后重试。"
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_blocked_cannot_make_payments",
                level: .notice,
                attemptID: attemptID,
                productID: product.id
            )
            return
        }

        guard let storeProduct = storeManager.coinProducts.first(where: { $0.id == product.id }) else {
            showErrorAlert = true
            errorMessage = "商品信息已过期，请刷新重试"
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_store_product_missing",
                level: .error,
                attemptID: attemptID,
                productID: product.id
            )
            return
        }

        activePurchaseAttemptID = attemptID
        let result = await storeManager.purchase(storeProduct, attemptID: attemptID)
        handlePurchaseResult(result, attemptID: attemptID, productID: product.id)
    }

    // MARK: - 处理购买结果
    private func handlePurchaseResult(_ result: IAPPurchaseResult, attemptID: String, productID: String) {
        switch result {
        case .success:
            // 成功消息通过 StoreManager 的 publisher 处理
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_result_success",
                    attemptID: attemptID,
                    productID: productID
                )
            }
            break
        case .pending:
            activePurchaseAttemptID = nil
            showSuccessToast = true
            successMessage = "购买请求已提交，正在等待 App Store 处理。到账后会自动更新余额。"
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_result_pending",
                    level: .notice,
                    attemptID: attemptID,
                    productID: productID
                )
            }
        case .cancelled:
            activePurchaseAttemptID = nil
            // 用户取消，不显示错误
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_result_cancelled",
                    level: .notice,
                    attemptID: attemptID,
                    productID: productID
                )
            }
            break
        case .failed(let error):
            activePurchaseAttemptID = nil
            showErrorAlert = true
            errorMessage = error.errorDescription ?? "购买失败"
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_result_failed",
                    level: .error,
                    attemptID: attemptID,
                    productID: productID,
                    fields: [
                        "error": error.errorDescription ?? "unknown",
                        "detailedError": error.detailedDescription
                    ]
                )
            }
        }
    }

    private func handlePurchaseSuccessContext(_ context: IAPPurchaseSuccessContext) {
        loadUserData()

        let isCurrentAttempt = context.attemptID != nil && context.attemptID == activePurchaseAttemptID
        let isOfferCodeBonus = context.message == IAPOfferCodeBonus.successMessage
        guard isCurrentAttempt || isOfferCodeBonus else {
            Task {
                await IAPDiagnosticStore.shared.record(
                    category: .flow,
                    name: "purchase_success_toast_suppressed_unmatched_attempt",
                    level: .notice,
                    attemptID: context.attemptID,
                    fields: [
                        "activeAttemptID": activePurchaseAttemptID ?? "nil",
                        "source": context.source,
                        "message": context.message
                    ]
                )
            }
            return
        }

        showSuccessToast = true
        successMessage = context.message
        activePurchaseAttemptID = nil

        Task {
            await IAPDiagnosticStore.shared.record(
                category: .flow,
                name: "purchase_success_toast_presented",
                attemptID: context.attemptID,
                fields: [
                    "source": context.source,
                    "message": context.message
                ]
            )
        }
    }

    func exportDiagnostics() async throws -> URL {
        try await IAPDiagnosticStore.shared.exportSnapshot()
    }

    // MARK: - 检查购买能力
    func canMakePurchases() -> Bool {
        return storeManager.canMakePurchases()
    }

    // MARK: - 消费喵币
    func spendMeowCoins(_ amount: Int) -> Bool {
        let success = StoreManager.spendMeowCoins(amount)
        if success {
            loadUserData() // 刷新余额
        }
        return success
    }

    // MARK: - 关闭提示
    func dismissSuccessToast() {
        showSuccessToast = false
    }

    func dismissErrorAlert() {
        showErrorAlert = false
        storeManager.clearError()
    }

}

// MARK: - 喵币商品展示模型
struct MeowCoinProductDisplay: Identifiable {
    let id: String
    let coinAmount: Int
    let bonusAmount: Int
    let price: String
    let isPopular: Bool
    let isBestValue: Bool
    let tag: String?
    let packageName: String
    let packageDescription: String
    let assetName: String

    var totalCoins: Int {
        coinAmount + bonusAmount
    }

    var firstDoubleCoins: Int {
        coinAmount * 2
    }

    var displayTitle: String {
        if bonusAmount > 0 {
            return "\(totalCoins) 喵币"
        } else {
            return "\(coinAmount) 喵币"
        }
    }

    var baseTitle: String {
        "\(coinAmount) 喵币"
    }

    var firstDoubleTitle: String {
        "\(firstDoubleCoins) 喵币"
    }

    var subtitle: String {
        if isBestValue {
            return "最划算"
        } else if isPopular {
            return "热门"
        } else if bonusAmount > 0 {
            return "送 \(bonusAmount)"
        } else {
            return ""
        }
    }

    var isBonusRateTag: Bool {
        tag?.hasPrefix("+") == true
    }

    init(from product: Product, type: IAPProductType) {
        self.id = product.id
        self.price = product.displayPrice

        // 根据商品类型设置数值
        // 汇率 10:1（1元 = 10喵币）
        // 策略：首次购买双倍，之后按档位 +10%、+15%、+25%、+35% 赠送
        switch type {
        case .meowCoin60:
            // 6元档：首次120，之后66（+10%）
            self.coinAmount = 60
            self.bonusAmount = 6
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+10%"
            self.packageName = "喵币小钱包"
            self.packageDescription = "一只轻巧的小钱包，装着 60 喵币，适合先给小猫存一笔零花。"
            self.assetName = "meowcoin_60"
        case .meowCoin120:
            // 12元档：首次240，之后132（+10%）
            self.coinAmount = 120
            self.bonusAmount = 12
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+10%"
            self.packageName = "喵币零食袋"
            self.packageDescription = "一袋鼓鼓的零食袋，装着 120 喵币，刚好够添几样喜欢的小东西。"
            self.assetName = "meowcoin_120"
        case .meowCoin300:
            // 30元档：首次600，之后330（+10%）
            self.coinAmount = 300
            self.bonusAmount = 30
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+10%"
            self.packageName = "喵币鼓鼓袋"
            self.packageDescription = "一袋沉甸甸的鼓鼓袋，装着 300 喵币，花起来更从容一些。"
            self.assetName = "meowcoin_300"
        case .meowCoin500:
            // 50元档：首次1000，之后575（+15%）
            self.coinAmount = 500
            self.bonusAmount = 75
            self.isPopular = true
            self.isBestValue = false
            self.tag = "热门"
            self.packageName = "喵币小宝箱"
            self.packageDescription = "一只满满当当的小宝箱，装着 500 喵币，拿在手里都觉得底气足。"
            self.assetName = "meowcoin_500"
        case .meowCoin1280:
            // 128元档：首次2560，之后1600（+25%）
            self.coinAmount = 1280
            self.bonusAmount = 320
            self.isPopular = false
            self.isBestValue = true
            self.tag = "最划算"
            self.packageName = "喵币大宝箱"
            self.packageDescription = "一个闪闪发亮的大宝箱，装着 1280 喵币，一开箱就是满满收获。"
            self.assetName = "mcoin_1280"
        case .meowCoin3280:
            // 328元档：首次6560，之后4428（+35%）
            self.coinAmount = 3280
            self.bonusAmount = 1148
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+35%"
            self.packageName = "喵币藏宝库入场券"
            self.packageDescription = "一座堆得满满的藏宝库，装着 3280 喵币，想把一整片小金库都搬回家。"
            self.assetName = "mcoin_3280"
        default:
            self.coinAmount = 0
            self.bonusAmount = 0
            self.isPopular = false
            self.isBestValue = false
            self.tag = nil
            self.packageName = ""
            self.packageDescription = ""
            self.assetName = ""
        }
    }
}
