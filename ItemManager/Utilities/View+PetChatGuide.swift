import SwiftUI

// MARK: - View 扩展 - 萌宠对话新手引导

extension View {
    /// 添加萌宠对话新手引导遮罩
    /// 在主视图上调用，自动处理引导流程
    func withPetChatGuide() -> some View {
        modifier(PetChatGuideModifier())
    }

    /// 标记视图为萌宠对话引导的高亮锚点
    /// - Parameter anchor: 锚点类型
    func petChatGuideAnchor(_ anchor: PetChatGuideHighlightAnchor) -> some View {
        overlay(
            PetChatGuideHighlightAnchorView(anchor: anchor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

// MARK: - 萌宠对话引导修饰器

struct PetChatGuideModifier: ViewModifier {
    @StateObject private var guideManager = PetChatGuideManager.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if guideManager.isShowingGuide {
                PetChatGuideOverlay()
            }
        }
    }
}

// MARK: - 便捷调用方式

/// 在 App 主视图上启用萌宠对话新手引导
/// 使用示例：
/// ```swift
/// ContentView()
///     .enablePetChatGuide()
/// ```
extension View {
    func enablePetChatGuide() -> some View {
        withPetChatGuide()
    }
}

// MARK: - 高亮锚点便捷方法

extension View {
    /// 标记为悬浮小猫高亮锚点
    func petChatGuideFloatingCat() -> some View {
        petChatGuideAnchor(.floatingCat)
    }

    /// 标记为"我"tab高亮锚点
    func petChatGuideMeTab() -> some View {
        petChatGuideAnchor(.meTab)
    }

    /// 标记为VIP卡片高亮锚点
    func petChatGuideVIPCard() -> some View {
        petChatGuideAnchor(.vipCard)
    }

    /// 标记为充值按钮高亮锚点
    func petChatGuideRechargeButton() -> some View {
        petChatGuideAnchor(.rechargeButton)
    }

    /// 标记为兑换按钮高亮锚点
    func petChatGuideRedeemButton() -> some View {
        petChatGuideAnchor(.redeemButton)
    }
}
