import Foundation
import SwiftUI
import Combine

// MARK: - IAPTestManager
// 测试专用管理类，提供"豆腐块"功能用于实验室测试
// 功能：
// 1. 模拟服务器响应（无需真实服务器）
// 2. 清除购买记录（重置首次购买状态）
// 3. 快速添加测试用的喵币
// 4. 切换测试模式/生产模式

@MainActor
class IAPTestManager: ObservableObject {
    static let shared = IAPTestManager()

    // MARK: - 测试模式开关
    @Published var isTestMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isTestMode, forKey: "iap_test_mode")
            if isTestMode {
                print("[IAPTestManager] 进入测试模式")
            } else {
                print("[IAPTestManager] 进入生产模式")
            }
        }
    }

    // MARK: - 模拟服务器数据（仅在测试模式使用）
    @Published var mockBalance: Int = 0
    @Published var mockIsVIP: Bool = false
    @Published var mockFirstPurchaseCompleted: Bool = false

    // MARK: - 测试配置
    struct TestConfig {
        var enableFirstDouble: Bool = true
        var mockNetworkDelay: TimeInterval = 0.5
        var simulateNetworkError: Bool = false
    }

    @Published var testConfig = TestConfig()

    private init() {
        // 读取保存的测试模式状态
        self.isTestMode = UserDefaults.standard.bool(forKey: "iap_test_mode")
        loadMockData()
    }

    // MARK: - 豆腐块功能

    /// 显示测试控制面板（在UI中调用）
    func showTestPanel() -> some View {
        IAPTestPanel()
    }

    // MARK: - 清除购买记录

    /// 清除所有购买记录（用于测试首次购买体验）
    func clearAllPurchaseRecords() {
        // 1. 清除本地首次购买标记
        mockFirstPurchaseCompleted = false
        UserDefaults.standard.set(false, forKey: "iap_first_purchase_completed")

        // 2. 清除已处理的交易ID
        UserDefaults.standard.removeObject(forKey: "ProcessedTransactionIDs")

        // 3. 清除购买历史
        UserDefaults.standard.removeObject(forKey: IAPPurchaseRecord.storageKey)

        // 4. 清除喵币账户
        UserDefaults.standard.removeObject(forKey: MeowCoinAccount.storageKey)

        // 5. 重置模拟数据
        mockBalance = 0
        mockIsVIP = false

        print("[IAPTestManager] ✅ 已清除所有购买记录，可以重新测试首次购买")
    }

    // MARK: - 快速添加喵币（豆腐块）

    /// 快速添加喵币（测试用）
    /// - Parameters:
    ///   - amount: 数量
    ///   - isFirstDouble: 是否应用首充双倍
    func addMeowCoins(_ amount: Int, isFirstDouble: Bool = false) {
        let finalAmount = isFirstDouble ? amount * 2 : amount

        if isTestMode {
            mockBalance += finalAmount
            // 如果是首充双倍，标记首次购买已完成
            if isFirstDouble {
                markFirstPurchaseCompleted()
            }
            saveMockData()
        }

        // 同时更新本地存储（兼容模式）
        var account = StoreManager.loadMeowCoinAccount()
        account.balance += finalAmount
        account.totalPurchased += finalAmount
        account.lastUpdated = Date()
        // 如果是首充双倍，标记首次购买已完成
        if isFirstDouble {
            account.firstPurchaseCompleted = true
        }
        StoreManager.saveMeowCoinAccount(account)

        // 同步到 PetDataManager
        var status = PetDataManager.shared.status
        status.meowCoin = account.balance
        PetDataManager.shared.saveStatus(status)

        print("[IAPTestManager] ✅ 已添加 \(finalAmount) 喵币")
    }

    /// 设置喵币余额（直接设置，非累加）
    func setMeowCoins(_ amount: Int) {
        if isTestMode {
            mockBalance = amount
            saveMockData()
        }

        var account = StoreManager.loadMeowCoinAccount()
        account.balance = amount
        account.lastUpdated = Date()
        StoreManager.saveMeowCoinAccount(account)

        var status = PetDataManager.shared.status
        status.meowCoin = amount
        PetDataManager.shared.saveStatus(status)

        print("[IAPTestManager] ✅ 余额已设置为 \(amount)")
    }

    // MARK: - VIP 测试

    /// 开通VIP（测试用）
    func activateVIP(months: Int = 1) {
        if isTestMode {
            mockIsVIP = true
            saveMockData()
        }

        var status = PetDataManager.shared.status
        status.vipStatus.isActive = true

        let baseDate = status.vipStatus.expireDate ?? Date()
        let effectiveDate = baseDate > Date() ? baseDate : Date()

        if let newExpireDate = Calendar.current.date(byAdding: .month, value: months, to: effectiveDate) {
            status.vipStatus.expireDate = newExpireDate
        }

        if status.vipStatus.vipNumber == nil {
            status.vipStatus.vipNumber = generateTestVIPNumber()
        }

        PetDataManager.shared.saveStatus(status)

        print("[IAPTestManager] ✅ VIP已开通 \(months) 个月")
    }

    /// 取消VIP（测试用）
    func deactivateVIP() {
        if isTestMode {
            mockIsVIP = false
            saveMockData()
        }

        var status = PetDataManager.shared.status
        status.vipStatus.isActive = false
        status.vipStatus.expireDate = Date()
        PetDataManager.shared.saveStatus(status)

        print("[IAPTestManager] ✅ VIP已取消")
    }

    // MARK: - 首次购买测试

    /// 标记首次购买已完成
    func markFirstPurchaseCompleted() {
        mockFirstPurchaseCompleted = true
        UserDefaults.standard.set(true, forKey: "iap_first_purchase_completed")

        // 同时更新 MeowCoinAccount 中的首次购买标记，确保 FirstDoubleBonusManager 能正确读取
        var account = StoreManager.loadMeowCoinAccount()
        account.firstPurchaseCompleted = true
        StoreManager.saveMeowCoinAccount(account)

        print("[IAPTestManager] ✅ 已标记首次购买完成")
    }

    /// 重置首次购买状态
    func resetFirstPurchase() {
        mockFirstPurchaseCompleted = false
        UserDefaults.standard.set(false, forKey: "iap_first_purchase_completed")

        var account = StoreManager.loadMeowCoinAccount()
        account.firstPurchaseCompleted = false
        StoreManager.saveMeowCoinAccount(account)

        print("[IAPTestManager] ✅ 首次购买状态已重置")
    }

    /// 检查是否还有首次双倍资格
    func hasFirstDoubleBonus() -> Bool {
        if isTestMode {
            return !mockFirstPurchaseCompleted
        }
        return !UserDefaults.standard.bool(forKey: "iap_first_purchase_completed")
    }

    // MARK: - 模拟服务器响应

    /// 模拟验证支付（测试模式使用）
    func mockVerifyPayment(productID: String) -> MockPaymentResult {
        // 模拟网络延迟
        Thread.sleep(forTimeInterval: testConfig.mockNetworkDelay)

        // 模拟网络错误
        if testConfig.simulateNetworkError {
            return .failure("网络连接失败")
        }

        // 根据商品ID返回模拟结果
        guard let type = IAPProductType(rawValue: productID) else {
            return .failure("无效的商品ID")
        }

        let (baseAmount, bonus) = getMockCoinAmount(for: type)

        // 应用首充双倍
        let isFirstDouble = hasFirstDoubleBonus() && testConfig.enableFirstDouble
        let finalAmount = isFirstDouble ? (baseAmount * 2 + bonus) : (baseAmount + bonus)

        // 更新模拟数据
        mockBalance += finalAmount
        if isFirstDouble {
            markFirstPurchaseCompleted()
        }
        saveMockData()

        return .success(
            deliveredCoins: finalAmount,
            newBalance: mockBalance,
            isFirstDouble: isFirstDouble
        )
    }

    // MARK: - 私有方法

    private func getMockCoinAmount(for type: IAPProductType) -> (base: Int, bonus: Int) {
        switch type {
        case .meowCoin60:
            return (60, 6)
        case .meowCoin120:
            return (120, 12)
        case .meowCoin300:
            return (300, 30)
        case .meowCoin500:
            return (500, 75)
        case .meowCoin1280:
            return (1280, 320)
        case .meowCoin3280:
            return (3280, 1148)
        default:
            return (0, 0)
        }
    }

    private func generateTestVIPNumber() -> String {
        return String(format: "%08d", Int.random(in: 10000000...99999999))
    }

    private func loadMockData() {
        mockBalance = UserDefaults.standard.integer(forKey: "iap_mock_balance")
        mockIsVIP = UserDefaults.standard.bool(forKey: "iap_mock_vip")
        mockFirstPurchaseCompleted = UserDefaults.standard.bool(forKey: "iap_first_purchase_completed")
    }

    private func saveMockData() {
        UserDefaults.standard.set(mockBalance, forKey: "iap_mock_balance")
        UserDefaults.standard.set(mockIsVIP, forKey: "iap_mock_vip")
        UserDefaults.standard.set(mockFirstPurchaseCompleted, forKey: "iap_first_purchase_completed")
    }
}

// MARK: - 模拟支付结果

enum MockPaymentResult {
    case success(deliveredCoins: Int, newBalance: Int, isFirstDouble: Bool)
    case failure(String)
}

// MARK: - 测试控制面板 UI

struct IAPTestPanel: View {
    @StateObject private var testManager = IAPTestManager.shared
    @State private var customAmount: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 模式切换
                Section("测试模式") {
                    Toggle("启用测试模式", isOn: $testManager.isTestMode)

                    if testManager.isTestMode {
                        Text("当前处于测试模式，所有支付将使用模拟数据")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // 当前状态
                Section("当前状态") {
                    HStack {
                        Text("喵币余额")
                        Spacer()
                        Text("\(testManager.mockBalance)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("VIP状态")
                        Spacer()
                        Text(testManager.mockIsVIP ? "已开通" : "未开通")
                            .foregroundStyle(testManager.mockIsVIP ? .green : .secondary)
                    }

                    HStack {
                        Text("首次购买")
                        Spacer()
                        Text(testManager.hasFirstDoubleBonus() ? "✅ 可享受双倍" : "已完成")
                            .foregroundStyle(testManager.hasFirstDoubleBonus() ? .green : .secondary)
                    }
                }

                // 快速添加喵币（豆腐块）
                Section("快速添加喵币") {
                    // 首充档位
                    Button("💰 添加首充档位 (60喵币)") {
                        testManager.addMeowCoins(60, isFirstDouble: true)
                    }
                    .foregroundStyle(.blue)

                    Button("💰 添加中充档位 (300喵币)") {
                        testManager.addMeowCoins(300, isFirstDouble: true)
                    }
                    .foregroundStyle(.blue)

                    Button("💰 添加土豪档位 (3280喵币)") {
                        testManager.addMeowCoins(3280, isFirstDouble: true)
                    }
                    .foregroundStyle(.blue)

                    // 非首充档位
                    Button("🪙 添加60喵币（无双倍）") {
                        testManager.addMeowCoins(60, isFirstDouble: false)
                    }

                    Button("🪙 添加500喵币（无双倍）") {
                        testManager.addMeowCoins(500, isFirstDouble: false)
                    }

                    // 自定义数量
                    HStack {
                        TextField("自定义数量", text: $customAmount)
                            .keyboardType(.numberPad)

                        Button("添加") {
                            if let amount = Int(customAmount) {
                                testManager.addMeowCoins(amount)
                                customAmount = ""
                            }
                        }
                        .disabled(customAmount.isEmpty)
                    }

                    // 直接设置余额
                    Button("📝 设置余额为 9999") {
                        testManager.setMeowCoins(9999)
                    }
                    .foregroundStyle(.purple)
                }

                // VIP 测试
                Section("VIP测试") {
                    Button("👑 开通月度VIP") {
                        testManager.activateVIP(months: 1)
                    }
                    .foregroundStyle(.orange)

                    Button("👑 开通年度VIP") {
                        testManager.activateVIP(months: 12)
                    }
                    .foregroundStyle(.orange)

                    Button("🚫 取消VIP") {
                        testManager.deactivateVIP()
                    }
                    .foregroundStyle(.red)
                }

                // 首次购买测试
                Section("首次购买测试") {
                    Button("🔄 重置首次购买状态") {
                        testManager.resetFirstPurchase()
                    }
                    .foregroundStyle(.green)

                    Button("✅ 标记首次购买完成") {
                        testManager.markFirstPurchaseCompleted()
                    }

                    Toggle("启用首充双倍", isOn: $testManager.testConfig.enableFirstDouble)
                }

                // 清除数据
                Section("危险操作") {
                    Button("🗑️ 清除所有购买记录") {
                        testManager.clearAllPurchaseRecords()
                    }
                    .foregroundStyle(.red)

                    Text("清除后可重新测试首次购买流程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 网络模拟
                Section("网络模拟") {
                    Toggle("模拟网络错误", isOn: $testManager.testConfig.simulateNetworkError)

                    HStack {
                        Text("网络延迟")
                        Spacer()
                        Text("\(String(format: "%.1f", testManager.testConfig.mockNetworkDelay))s")
                    }
                }
            }
            .navigationTitle("IAP测试实验室")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 便捷调用扩展

extension View {
    /// 添加测试面板入口（通过手势或按钮触发）
    func iapTestPanel(trigger: IAPTestTrigger = .tripleTap) -> some View {
        self.modifier(IAPTestPanelModifier(trigger: trigger))
    }
}

enum IAPTestTrigger {
    case tripleTap
    case shake
    case longPress
}

struct IAPTestPanelModifier: ViewModifier {
    let trigger: IAPTestTrigger
    @State private var showTestPanel = false
    @State private var tapCount = 0

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if trigger == .tripleTap {
                    tapCount += 1
                    if tapCount >= 3 {
                        showTestPanel = true
                        tapCount = 0
                    }
                    // 2秒后重置点击计数
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        tapCount = 0
                    }
                }
            }
            .sheet(isPresented: $showTestPanel) {
                IAPTestManager.shared.showTestPanel()
            }
    }
}
