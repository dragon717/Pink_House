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

    // MARK: - Private Properties
    private var storeManager = StoreManager.shared
    private var cancellables = Set<AnyCancellable>()

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

        storeManager.$purchaseSuccess
            .receive(on: DispatchQueue.main)
            .sink { [weak self] success in
                if success {
                    self?.showSuccessToast = true
                    self?.successMessage = self?.storeManager.purchaseSuccessMessage ?? "购买成功"
                    self?.loadUserData() // 刷新用户数据
                }
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

    }

    // MARK: - 加载用户数据
    func loadUserData() {
        // 加载喵币余额
        currentBalance = StoreManager.getCurrentBalance()

        // 加载VIP状态
        let status = PetDataManager.shared.status
        isVIP = status.vipStatus.isActive && !status.vipStatus.isExpired
        vipExpireDate = status.vipStatus.expireDate
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
        guard let storeProduct = storeManager.coinProducts.first(where: { $0.id == product.id }) else {
            showErrorAlert = true
            errorMessage = "商品信息已过期，请刷新重试"
            return
        }

        let result = await storeManager.purchase(storeProduct)
        handlePurchaseResult(result)
    }

    // MARK: - 处理购买结果
    private func handlePurchaseResult(_ result: IAPPurchaseResult) {
        switch result {
        case .success:
            // 成功消息通过 StoreManager 的 publisher 处理
            break
        case .pending:
            showSuccessToast = true
            successMessage = "购买已提交，等待处理中..."
        case .cancelled:
            // 用户取消，不显示错误
            break
        case .failed(let error):
            showErrorAlert = true
            errorMessage = error.errorDescription ?? "购买失败"
        }
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

    var totalCoins: Int {
        coinAmount + bonusAmount
    }

    var displayTitle: String {
        if bonusAmount > 0 {
            return "\(totalCoins) 喵币"
        } else {
            return "\(coinAmount) 喵币"
        }
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
        case .meowCoin120:
            // 12元档：首次240，之后132（+10%）
            self.coinAmount = 120
            self.bonusAmount = 12
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+10%"
        case .meowCoin300:
            // 30元档：首次600，之后330（+10%）
            self.coinAmount = 300
            self.bonusAmount = 30
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+10%"
        case .meowCoin500:
            // 50元档：首次1000，之后575（+15%）
            self.coinAmount = 500
            self.bonusAmount = 75
            self.isPopular = true
            self.isBestValue = false
            self.tag = "热门"
        case .meowCoin1280:
            // 128元档：首次2560，之后1600（+25%）
            self.coinAmount = 1280
            self.bonusAmount = 320
            self.isPopular = false
            self.isBestValue = true
            self.tag = "最划算"
        case .meowCoin3280:
            // 328元档：首次6560，之后4428（+35%）
            self.coinAmount = 3280
            self.bonusAmount = 1148
            self.isPopular = false
            self.isBestValue = false
            self.tag = "+35%"
        default:
            self.coinAmount = 0
            self.bonusAmount = 0
            self.isPopular = false
            self.isBestValue = false
            self.tag = nil
        }
    }
}
