import Foundation
import StoreKit

// MARK: - IAP 错误类型
// 定义内购过程中可能遇到的所有错误类型，用于UI展示和日志记录

enum IAPError: Error, LocalizedError, Equatable {
    // 商品相关错误
    case productNotFound(String)           // 找不到商品
    case productRequestFailed(String)      // 请求商品失败
    case invalidProductID(String)          // 无效的商品ID

    // 购买流程错误
    case purchaseFailed(String)            // 购买失败
    case purchasePending                   // 购买等待中（需要家长授权等）
    case purchaseCancelled                 // 用户取消购买
    case purchaseNotAllowed                // 购买不被允许
    case paymentInvalid                    // 支付无效

    // 验证相关错误
    case verificationFailed                // 交易验证失败
    case serverVerificationFailed(String)  // 服务器验证失败
    case receiptNotFound                   // 找不到收据
    case invalidReceipt                    // 无效收据
    case alreadyProcessed                  // 该交易已处理过

    // 网络错误
    case networkError(String)              // 网络错误
    case serverError(String)               // 服务器错误
    case timeout                           // 超时

    // 用户状态错误
    case notAuthenticated                  // 用户未登录
    case accountRestricted                 // 账户受限

    // 系统错误
    case storeKitError(StoreKitError)      // StoreKit 原生错误
    case unknown(Error)                    // 未知错误
    case systemError(String)               // 系统错误

    // 错误描述，用于展示给用户
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "商品暂时不可用".appLocalized
        case .productRequestFailed:
            return "获取商品信息失败".appLocalized
        case .invalidProductID:
            return "无效的商品".appLocalized
        case .purchaseFailed:
            return "购买失败，请重试".appLocalized
        case .purchasePending:
            return "购买等待中，请稍后查看".appLocalized
        case .purchaseCancelled:
            return "已取消购买".appLocalized
        case .purchaseNotAllowed:
            return "当前无法购买".appLocalized
        case .paymentInvalid:
            return "支付信息无效".appLocalized
        case .verificationFailed:
            return "交易验证失败".appLocalized
        case .serverVerificationFailed:
            return "服务器验证失败".appLocalized
        case .receiptNotFound:
            return "找不到购买凭证".appLocalized
        case .invalidReceipt:
            return "购买凭证无效".appLocalized
        case .alreadyProcessed:
            return "该订单已处理".appLocalized
        case .networkError:
            return "网络连接失败".appLocalized
        case .serverError:
            return "服务器繁忙".appLocalized
        case .timeout:
            return "请求超时".appLocalized
        case .notAuthenticated:
            return "请先登录".appLocalized
        case .accountRestricted:
            return "账户受限".appLocalized
        case .storeKitError(let error):
            return error.localizedDescription
        case .unknown:
            return "发生未知错误".appLocalized
        case .systemError:
            return "系统错误".appLocalized
        }
    }

    // 详细错误信息，用于日志和调试
    var detailedDescription: String {
        switch self {
        case .productNotFound(let id):
            return "找不到商品: \(id)"
        case .productRequestFailed(let reason):
            return "请求商品失败: \(reason)"
        case .invalidProductID(let id):
            return "无效的商品ID: \(id)"
        case .purchaseFailed(let reason):
            return "购买失败: \(reason)"
        case .purchasePending:
            return "购买等待中，可能需要家长授权"
        case .purchaseCancelled:
            return "用户取消了购买"
        case .purchaseNotAllowed:
            return "当前设备或账户不允许购买"
        case .paymentInvalid:
            return "支付信息无效，请检查付款方式"
        case .verificationFailed:
            return "交易验证失败，可能是伪造的交易"
        case .serverVerificationFailed(let reason):
            return "服务器验证失败: \(reason)"
        case .receiptNotFound:
            return "找不到购买凭证"
        case .invalidReceipt:
            return "购买凭证无效或已过期"
        case .alreadyProcessed:
            return "该交易ID已经处理过，防止重复发放"
        case .networkError(let reason):
            return "网络错误: \(reason)"
        case .serverError(let reason):
            return "服务器错误: \(reason)"
        case .timeout:
            return "请求超时，请检查网络连接"
        case .notAuthenticated:
            return "用户未登录，无法完成购买"
        case .accountRestricted:
            return "账户受限，无法购买"
        case .storeKitError(let error):
            return "StoreKit错误: \(error)"
        case .unknown(let error):
            return "未知错误: \(error)"
        case .systemError(let reason):
            return "系统错误: \(reason)"
        }
    }

    // 是否需要重试
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .timeout, .productRequestFailed:
            return true
        case .purchasePending:
            return true  // 可以稍后检查状态
        default:
            return false
        }
    }

    // 是否为用户可恢复的错误
    var isRecoverable: Bool {
        switch self {
        case .purchaseCancelled, .purchasePending:
            return true
        case .networkError, .timeout:
            return true
        default:
            return false
        }
    }

    // 从 StoreKitError 转换
    static func from(storeKitError: StoreKitError) -> IAPError {
        return .storeKitError(storeKitError)
    }

    // 从 PurchaseResult 转换
    static func from(purchaseError: Product.PurchaseError) -> IAPError {
        switch purchaseError {
        case .invalidQuantity:
            return .purchaseFailed("无效的数量".appLocalized)
        case .productUnavailable:
            return .productNotFound("")
        case .purchaseNotAllowed:
            return .purchaseNotAllowed
        @unknown default:
            return .purchaseFailed("未知购买错误".appLocalized)
        }
    }

    // Equatable 实现
    static func == (lhs: IAPError, rhs: IAPError) -> Bool {
        switch (lhs, rhs) {
        case (.productNotFound(let a), .productNotFound(let b)):
            return a == b
        case (.productRequestFailed(let a), .productRequestFailed(let b)):
            return a == b
        case (.invalidProductID(let a), .invalidProductID(let b)):
            return a == b
        case (.purchaseFailed(let a), .purchaseFailed(let b)):
            return a == b
        case (.purchasePending, .purchasePending):
            return true
        case (.purchaseCancelled, .purchaseCancelled):
            return true
        case (.purchaseNotAllowed, .purchaseNotAllowed):
            return true
        case (.paymentInvalid, .paymentInvalid):
            return true
        case (.verificationFailed, .verificationFailed):
            return true
        case (.serverVerificationFailed(let a), .serverVerificationFailed(let b)):
            return a == b
        case (.receiptNotFound, .receiptNotFound):
            return true
        case (.invalidReceipt, .invalidReceipt):
            return true
        case (.alreadyProcessed, .alreadyProcessed):
            return true
        case (.networkError(let a), .networkError(let b)):
            return a == b
        case (.serverError(let a), .serverError(let b)):
            return a == b
        case (.timeout, .timeout):
            return true
        case (.notAuthenticated, .notAuthenticated):
            return true
        case (.accountRestricted, .accountRestricted):
            return true
        case (.storeKitError(let a), .storeKitError(let b)):
            return a.localizedDescription == b.localizedDescription
        case (.systemError(let a), .systemError(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - 购买结果枚举
enum IAPPurchaseResult {
    case success(transaction: Transaction?, product: Product)
    case pending
    case cancelled
    case failed(IAPError)
}

// MARK: - 交易状态
enum IAPTransactionStatus {
    case pending      // 等待中
    case processing   // 处理中
    case verifying    // 验证中
    case completed    // 已完成
    case failed(IAPError)  // 失败
}
