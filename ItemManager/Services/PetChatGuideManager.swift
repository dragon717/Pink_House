import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - 萌宠对话新手引导步骤

enum PetChatGuideStep: String, CaseIterable, Identifiable {
    case none = "none"           // 无引导
    case welcome = "welcome"     // 欢迎气泡（点击悬浮小猫后）
    case goToMeTab = "goToMeTab" // 引导去"我"tab
    case clickVIPCard = "clickVIPCard" // 引导点击VIP卡片
    case rechargeCoins = "rechargeCoins" // 引导充值喵币
    case redeemVIP = "redeemVIP" // 引导兑换VIP
    case complete = "complete"   // 引导完成

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return ""
        case .welcome: return "解锁智能对话"
        case .goToMeTab: return "前往会员中心"
        case .clickVIPCard: return "开通VIP会员"
        case .rechargeCoins: return "充值喵币"
        case .redeemVIP: return "兑换VIP天数"
        case .complete: return "引导完成"
        }
    }

    var description: String {
        switch self {
        case .none: return ""
        case .welcome:
            return "智能对话功能需要VIP会员才能使用哦~让我带你开通吧！"
        case .goToMeTab:
            return "点击下方的「我」标签，进入会员中心"
        case .clickVIPCard:
            return "点击VIP卡片，进入会员中心"
        case .rechargeCoins:
            return "喵币不足时，点击这里充值喵币"
        case .redeemVIP:
            return "有兑换码？点击右上角菜单使用兑换码兑换VIP"
        case .complete:
            return "恭喜你！现在可以使用智能对话功能啦~"
        }
    }

    var buttonText: String {
        switch self {
        case .none, .complete: return ""
        case .welcome: return "去开通"
        case .goToMeTab: return "知道了"
        case .clickVIPCard: return "点击VIP卡片"
        case .rechargeCoins: return "去充值"
        case .redeemVIP: return "兑换VIP"
        }
    }
}

// MARK: - 萌宠对话新手引导状态

struct PetChatGuideState: Codable {
    var isCompleted: Bool = false
    var currentStep: String = PetChatGuideStep.none.rawValue
    var skippedAt: Date? = nil
    var startedAt: Date = Date()
}

// MARK: - 萌宠对话新手引导管理器

final class PetChatGuideManager: ObservableObject {
    static let shared = PetChatGuideManager()

    // MARK: - Published Properties

    @Published var state: PetChatGuideState = PetChatGuideState()
    @Published var isShowingGuide: Bool = false
    @Published var currentStep: PetChatGuideStep = .none

    // 高亮相关状态
    @Published var highlightFrame: CGRect = .zero
    @Published var showHighlight: Bool = false

    // MARK: - 配置

    private let stateKey = "petChatGuide.state"
    private let hasSeenGuideKey = "petChatGuide.hasSeen"

    // 高亮圈配置
    let highlightRadius: CGFloat = 40
    let highlightPadding: CGFloat = 8

    // MARK: - 计算属性

    var isFirstLaunch: Bool {
        return !UserDefaults.standard.bool(forKey: hasSeenGuideKey)
    }

    var shouldShowGuide: Bool {
        // 只有未完成的首次引导才显示
        return !state.isCompleted && isFirstLaunch
    }

    // MARK: - Initialization

    private init() {
        loadState()
    }

    // MARK: - 状态管理

    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(PetChatGuideState.self, from: data) {
            state = decoded
            currentStep = PetChatGuideStep(rawValue: decoded.currentStep) ?? .none
        }
    }

    private func saveState() {
        state.currentStep = currentStep.rawValue
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: stateKey)
        }
    }

    // MARK: - 引导控制

    /// 开始新手引导（从悬浮小猫点击后调用）
    func startGuide() {
        guard shouldShowGuide else { return }

        currentStep = .welcome
        isShowingGuide = true
        saveState()

        UserDefaults.standard.set(true, forKey: hasSeenGuideKey)
    }

    /// 进入下一步
    func nextStep() {
        switch currentStep {
        case .none:
            currentStep = .welcome
        case .welcome:
            currentStep = .goToMeTab
        case .goToMeTab:
            currentStep = .clickVIPCard
        case .clickVIPCard:
            currentStep = .rechargeCoins
        case .rechargeCoins:
            currentStep = .redeemVIP
        case .redeemVIP:
            currentStep = .complete
        case .complete:
            completeGuide()
            return
        }
        saveState()
    }

    /// 跳转到指定步骤
    func jumpToStep(_ step: PetChatGuideStep) {
        currentStep = step
        saveState()
    }

    /// 完成引导
    func completeGuide() {
        state.isCompleted = true
        currentStep = .complete
        isShowingGuide = false
        showHighlight = false
        saveState()
    }

    /// 跳过引导
    func skipGuide() {
        state.skippedAt = Date()
        state.isCompleted = true
        isShowingGuide = false
        showHighlight = false
        saveState()
    }

    /// 重置引导状态
    func resetGuide() {
        state = PetChatGuideState()
        currentStep = .none
        isShowingGuide = false
        showHighlight = false
        UserDefaults.standard.set(false, forKey: hasSeenGuideKey)
        saveState()
    }

    // MARK: - 高亮位置计算

    /// 更新高亮框位置
    func updateHighlightFrame(_ frame: CGRect) {
        highlightFrame = frame.insetBy(dx: -highlightPadding, dy: -highlightPadding)
        showHighlight = true
    }

    /// 清除高亮
    func clearHighlight() {
        showHighlight = false
    }
}

// MARK: - 引导步骤配置协议

protocol PetChatGuideStepConfigurable {
    var step: PetChatGuideStep { get }
    var title: String { get }
    var description: String { get }
    var buttonText: String { get }
    var highlightAnchor: PetChatGuideHighlightAnchor? { get }
}

// MARK: - 高亮锚点类型

enum PetChatGuideHighlightAnchor {
    case floatingCat        // 悬浮小猫
    case meTab              // 我tab
    case vipCard            // VIP卡片
    case rechargeButton     // 充值按钮
    case redeemButton       // 兑换按钮
    case custom(CGRect)     // 自定义位置
}
