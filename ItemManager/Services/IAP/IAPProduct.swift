import Foundation
import StoreKit

// MARK: - IAP 商品定义
// 定义所有内购商品（当前仅包含喵币）

enum IAPProductType: String, CaseIterable {
    // 喵币 - 消耗型项目
    // 汇率 10:1（1元 = 10喵币）
    case meowCoin60 = "com.pinkhouse.app.meowcoin_60"      // 6元 = 60喵币
    case meowCoin120 = "com.pinkhouse.app.meowcoin_120"    // 12元 = 120喵币
    case meowCoin300 = "com.pinkhouse.app.meowcoin_300"    // 30元 = 300喵币
    case meowCoin500 = "com.pinkhouse.app.meowcoin_500"    // 50元 = 500喵币（热门）
    case meowCoin1280 = "com.pinkhouse.app.mcoin_1280"  // 128元 = 1280喵币（最划算）
    case meowCoin3280 = "com.pinkhouse.app.mcoin_3280"  // 328元 = 3280喵币

    // 商品ID列表，用于请求商品信息
    static var allProductIDs: [String] {
        return Self.allCases.map { $0.rawValue }
    }

    // 喵币商品ID列表
    // 汇率 10:1（1元 = 10喵币）
    static var coinProductIDs: [String] {
        return [
            meowCoin60.rawValue,    // 6元
            meowCoin120.rawValue,   // 12元
            meowCoin300.rawValue,   // 30元
            meowCoin500.rawValue,   // 50元
            meowCoin1280.rawValue,  // 128元
            meowCoin3280.rawValue   // 328元
        ]
    }
}

// MARK: - App Store 优惠码兑换配置
// 优惠码不再绑定隐藏礼包商品，统一绑定现有 60 喵币档位。
// 通过 App Store Offer Codes 免费兑换时只发放基础 60 喵币，不消耗首充双倍资格。
enum IAPOfferCodeRedemption {
    static let productID = IAPProductType.meowCoin60.rawValue
    static let meowCoinAmount = 60
    static let successMessage = "兑换成功！获得 60 喵币"
    static let source = "offer_code_redemption"
    static let pendingProductIDKey = "iap_offer_code_redemption_pending_product_id"
    static let pendingStartedAtKey = "iap_offer_code_redemption_pending_started_at"
    static let pendingSessionTTL: TimeInterval = 15 * 60
}

// MARK: - 喵币商品信息
struct MeowCoinProduct: Identifiable, Equatable {
    let id: String
    let coinAmount: Int      // 获得的喵币数量
    let bonusAmount: Int     // 赠送的喵币数量
    let price: Decimal       // 价格
    let displayPrice: String // 显示价格
    let isPopular: Bool      // 是否热门推荐
    let isBestValue: Bool    // 是否最划算

    var totalCoins: Int {
        coinAmount + bonusAmount
    }

    // 根据ID创建商品信息
    static func from(storeProduct: Product) -> MeowCoinProduct? {
        guard let type = IAPProductType(rawValue: storeProduct.id),
              IAPProductType.coinProductIDs.contains(type.rawValue) else { return nil }

        let (amount, bonus, popular, bestValue) = Self.getProductDetails(for: type)

        return MeowCoinProduct(
            id: storeProduct.id,
            coinAmount: amount,
            bonusAmount: bonus,
            price: storeProduct.price,
            displayPrice: storeProduct.displayPrice,
            isPopular: popular,
            isBestValue: bestValue
        )
    }

    private static func getProductDetails(for type: IAPProductType) -> (amount: Int, bonus: Int, popular: Bool, bestValue: Bool) {
        // 汇率 10:1（1元 = 10喵币）
        // 策略：首次购买双倍，之后按档位 +10%、+25%、+35% 赠送
        switch type {
        case .meowCoin60:
            // 6元档：首次120喵币，之后60+6(10%)
            return (60, 6, false, false)
        case .meowCoin120:
            // 12元档：首次240喵币，之后120+12(10%)
            return (120, 12, false, false)
        case .meowCoin300:
            // 30元档：首次600喵币，之后300+30(10%)
            return (300, 30, false, false)
        case .meowCoin500:
            // 50元档：首次1000喵币，之后500+75(15%)
            return (500, 75, true, false)
        case .meowCoin1280:
            // 128元档：首次2560喵币，之后1280+320(25%)，最划算
            return (1280, 320, false, true)
        case .meowCoin3280:
            // 328元档：首次6560喵币，之后3280+1148(35%)
            return (3280, 1148, false, false)
        default:
            return (0, 0, false, false)
        }
    }
}

// MARK: - 购买记录
struct IAPPurchaseRecord: Codable, Identifiable {
    let id: String                    // 交易ID
    let productID: String             // 商品ID
    let purchaseDate: Date            // 购买时间
    let coinAmount: Int?              // 获得的喵币数量（如果是喵币商品）
    let subscriptionMonths: Int?      // 历史字段：旧版本 VIP 时长（月）
    let isVerified: Bool              // 是否已通过服务器验证
    let verificationDate: Date?       // 验证时间

    // 用于本地存储的键
    static let storageKey = "IAPPurchaseRecords"
}

// MARK: - 用户喵币账户
struct MeowCoinAccount: Codable {
    var balance: Int = 0                    // 当前余额
    var totalPurchased: Int = 0             // 累计购买
    var totalSpent: Int = 0                 // 累计消费
    var lastUpdated: Date = Date()
    // 每个商品档位的首充完成状态，key为productID
    var firstPurchaseCompletedByProduct: [String: Bool] = [:]

    static let storageKey = "MeowCoinAccount"
}

// MARK: - 首次双倍活动管理
// 每个商品档位独立计算首充双倍
struct FirstDoubleBonusManager {
    static let shared = FirstDoubleBonusManager()

    // 检查指定商品是否还有首次双倍资格
    func hasFirstDoubleBonus(for productID: String) -> Bool {
        let account = StoreManager.loadMeowCoinAccount()
        return !(account.firstPurchaseCompletedByProduct[productID] ?? false)
    }

    // 检查是否还有任何商品档位有首充双倍资格（用于显示全局横幅）
    func hasAnyFirstDoubleBonus() -> Bool {
        let account = StoreManager.loadMeowCoinAccount()
        for productID in IAPProductType.coinProductIDs {
            if !(account.firstPurchaseCompletedByProduct[productID] ?? false) {
                return true
            }
        }
        return false
    }

    // 标记指定商品的首次购买已完成
    func markFirstPurchaseCompleted(for productID: String) {
        var account = StoreManager.loadMeowCoinAccount()
        account.firstPurchaseCompletedByProduct[productID] = true
        StoreManager.saveMeowCoinAccount(account)
    }

    // 计算实际获得的喵币（包含首次双倍）
    func calculateActualCoins(baseAmount: Int, bonusAmount: Int, productID: String) -> (total: Int, isFirstDouble: Bool) {
        let isFirstDouble = hasFirstDoubleBonus(for: productID)

        if isFirstDouble {
            // 首次购买该档位：基础数量双倍（不包含赠送）
            let total = baseAmount * 2
            return (total, true)
        } else {
            // 非首次购买该档位：基础金额 + 赠送
            let total = baseAmount + bonusAmount
            return (total, false)
        }
    }
}
