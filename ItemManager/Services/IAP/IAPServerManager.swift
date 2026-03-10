import Foundation
import StoreKit
import Combine

// MARK: - IAPServerManager
// 服务器通信管理类，处理所有与后端公有数据库的交互
// 遵循"以服务器为准"的原则，不在本地持久化支付状态

@MainActor
class IAPServerManager: ObservableObject {
    static let shared = IAPServerManager()

    // 服务器基础URL（实际项目中应该从配置读取）
    private let baseURL = "https://api.pinkhouse.com/v1"

    // 用户Token（从登录系统获取）
    private var userToken: String?

    // 当前用户UUID（用于appAccountToken）
    private var userUUID: UUID?

    // Published 状态 - 只在内存中维护
    @Published var meowCoinBalance: Int = 0
    @Published var isVIP: Bool = false
    @Published var vipExpireDate: Date?
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    private init() {
        // 初始化时尝试从钥匙串读取用户信息
        loadUserCredentials()
    }

    // MARK: - 用户认证

    /// 设置用户凭证（登录后调用）
    func setUserCredentials(token: String, uuid: UUID) {
        self.userToken = token
        self.userUUID = uuid
        saveUserCredentials()
    }

    /// 清除用户凭证（登出时调用）
    func clearUserCredentials() {
        self.userToken = nil
        self.userUUID = nil
        self.meowCoinBalance = 0
        self.isVIP = false
        self.vipExpireDate = nil

        // 从钥匙串删除
        KeychainHelper.delete(key: "iap_user_token")
        KeychainHelper.delete(key: "iap_user_uuid")
    }

    /// 获取当前用户UUID（用于appAccountToken）
    func getUserUUID() -> UUID? {
        return userUUID
    }

    /// 检查是否已登录
    var isAuthenticated: Bool {
        return userToken != nil && userUUID != nil
    }

    // MARK: - 从服务器同步数据

    /// 同步用户资产数据（进入商店或启动App时调用）
    func syncUserAssets() async {
        guard isAuthenticated else {
            lastError = "用户未登录"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let assets = try await fetchAssetsFromServer()

            // 更新内存中的状态
            await MainActor.run {
                self.meowCoinBalance = assets.meowCoinBalance
                self.isVIP = assets.isVIP
                self.vipExpireDate = assets.vipExpireDate
            }

            print("[IAPServerManager] 同步成功: 喵币=\(assets.meowCoinBalance), VIP=\(assets.isVIP)")

        } catch {
            print("[IAPServerManager] 同步失败: \(error)")
            lastError = "网络连接失败，请检查网络"
        }
    }

    // MARK: - 验证交易并入库

    /// 验证交易并通知服务器发放喵币
    /// - Parameters:
    ///   - transaction: StoreKit交易
    ///   - productID: 商品ID（可选，用于恢复购买场景）
    /// - Returns: 是否成功
    func verifyAndDeliver(transaction: Transaction, productID: String? = nil) async -> Bool {
        guard isAuthenticated else {
            lastError = "用户未登录"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 准备验证请求
            // 注意：StoreKit 2 使用 JWSTransaction 格式，通过 verificationResult 获取
            let verifyRequest = PaymentVerifyRequest(
                transactionId: String(transaction.id),
                productId: transaction.productID,
                appAccountToken: transaction.appAccountToken?.uuidString ?? userUUID?.uuidString,
                purchaseDate: transaction.purchaseDate
            )

            // 发送到服务器验证
            let result = try await verifyPaymentWithServer(request: verifyRequest)

            if result.success {
                // 更新本地内存状态
                await MainActor.run {
                    self.meowCoinBalance = result.newBalance
                    self.isVIP = result.isVIP
                    self.vipExpireDate = result.vipExpireDate
                }

                print("[IAPServerManager] 验证成功，发放 \(result.deliveredCoins) 喵币")
                return true
            } else {
                lastError = result.errorMessage ?? "验证失败"
                return false
            }

        } catch {
            print("[IAPServerManager] 验证失败: \(error)")
            lastError = "服务器验证失败，请稍后重试"
            return false
        }
    }

    // MARK: - 恢复购买

    /// 恢复购买 - 将Apple ID下的所有有效交易同步到服务器
    func restorePurchases() async -> RestoreResult {
        guard isAuthenticated else {
            return .failure("用户未登录")
        }

        isLoading = true
        defer { isLoading = false }

        var restoredCount = 0
        var errors: [String] = []

        // 遍历所有当前有效的交易
        for await verification in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(verification)

                // 发送到服务器验证并恢复
                // 恢复购买时不传递 Product 对象，只传递 productID
                let success = await verifyAndDeliver(transaction: transaction, productID: transaction.productID)

                if success {
                    restoredCount += 1
                }

            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // 重新同步最新状态
        await syncUserAssets()

        if restoredCount > 0 {
            return .success(restoredCount: restoredCount)
        } else if errors.isEmpty {
            return .empty
        } else {
            return .failure(errors.joined(separator: ", "))
        }
    }

    // MARK: - 消费喵币

    /// 消费喵币（购买虚拟物品时调用）
    /// - Parameter amount: 消费数量
    /// - Returns: 是否成功
    func spendMeowCoins(_ amount: Int) async -> Bool {
        guard isAuthenticated else { return false }
        guard meowCoinBalance >= amount else { return false }

        do {
            let result = try await spendCoinsOnServer(amount: amount)

            if result.success {
                await MainActor.run {
                    self.meowCoinBalance = result.newBalance
                }
                return true
            } else {
                lastError = result.errorMessage ?? "余额不足"
                return false
            }

        } catch {
            lastError = "网络错误"
            return false
        }
    }

    // MARK: - 私有方法：网络请求

    /// 从服务器获取用户资产
    private func fetchAssetsFromServer() async throws -> UserAssets {
        guard let token = userToken else {
            throw ServerError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/user/assets")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServerError.invalidResponse
        }

        return try JSONDecoder().decode(UserAssets.self, from: data)
    }

    /// 验证支付到服务器
    private func verifyPaymentWithServer(request: PaymentVerifyRequest) async throws -> PaymentVerifyResponse {
        guard let token = userToken else {
            throw ServerError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/payment/verify")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServerError.invalidResponse
        }

        return try JSONDecoder().decode(PaymentVerifyResponse.self, from: data)
    }

    /// 在服务器消费喵币
    private func spendCoinsOnServer(amount: Int) async throws -> SpendCoinsResponse {
        guard let token = userToken else {
            throw ServerError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/user/spend-coins")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["amount": amount]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServerError.invalidResponse
        }

        return try JSONDecoder().decode(SpendCoinsResponse.self, from: data)
    }

    // MARK: - 辅助方法

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw ServerError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    private func loadUserCredentials() {
        if let token = KeychainHelper.read(key: "iap_user_token"),
           let uuidString = KeychainHelper.read(key: "iap_user_uuid"),
           let uuid = UUID(uuidString: uuidString) {
            self.userToken = token
            self.userUUID = uuid
        }
    }

    private func saveUserCredentials() {
        if let token = userToken, let uuid = userUUID {
            KeychainHelper.save(key: "iap_user_token", value: token)
            KeychainHelper.save(key: "iap_user_uuid", value: uuid.uuidString)
        }
    }
}

// MARK: - 数据模型

struct UserAssets: Codable {
    let meowCoinBalance: Int
    let isVIP: Bool
    let vipExpireDate: Date?
    let unlockedThemes: [String]
}

struct PaymentVerifyRequest: Codable {
    let transactionId: String
    let productId: String
    let appAccountToken: String?
    let purchaseDate: Date
}

struct PaymentVerifyResponse: Codable {
    let success: Bool
    let deliveredCoins: Int
    let newBalance: Int
    let isVIP: Bool
    let vipExpireDate: Date?
    let errorMessage: String?
}

struct SpendCoinsResponse: Codable {
    let success: Bool
    let newBalance: Int
    let errorMessage: String?
}

enum RestoreResult {
    case success(restoredCount: Int)
    case empty
    case failure(String)
}

enum ServerError: Error {
    case notAuthenticated
    case invalidResponse
    case verificationFailed
}

// MARK: - Keychain 辅助类

class KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
