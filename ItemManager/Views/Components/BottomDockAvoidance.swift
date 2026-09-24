import SwiftUI

// MARK: - 底部悬浮 Dock 避让（唯一口径）
//
//  `MainTabView` 的底部导航 Dock（`customTabBar`）是叠在 `contentView` **之上**的
//  覆盖层，**不是**系统 `TabBar`、**也不参与安全区计算**。它占据
//  `[屏高 − safeAreaBottom − 贴底 2 − 56, 屏高 − safeAreaBottom − 2]`
//  这一段，任何渲染在 tab 内容层里的滚动页面，只要内容能伸到屏幕底部，
//  最后一个元素就会被 Dock 盖住（2026-09-24 全量排查的事故类别）。
//
//  **预留高度只有一处定义**：`LegacyCustomTabBarLayout.floatingSurfaceBottomInset`
//  （= 56 Dock 高 + max(2, 4) 贴底 + 12 视觉间隙 = **72**），由 `MainTabView` 通过
//  `\.customBottomNavigationAvoidanceInset` 下发。页面**不要自己写数字**，
//  也**不要**再判断系统版本 —— Dock 是本 App 自己的，iOS 26+ 不会有人替我们留空间
//  （旧实现 `legacyCustomTabBarAvoidanceInset` 在 iOS 26+ 返回 0，正是漏避让的根源）。
//
//  使用边界：
//  - 只用于 **tab 根页面** 与 **在 tab 内 push 的页面**；
//    `.sheet` / `.fullScreenCover` 呈现的页面浮在 Dock 之上，加避让只会多出一块空白。
//  - 页面若自带了贴底的常驻操作条（例如 `ShopCatalogSeriesMenuView` 的
//    `safeAreaInset(edge: .bottom)` 选择条），两者会叠加成双倍留白 —— 二选一。
//  - 页面若已经在滚动内容尾部用 `padding(.bottom, N)`（N ≥ 72）预留，不要重复添加。

/// 为底部悬浮 Dock 预留空间。见文件头注释。
struct BottomDockAvoidanceModifier: ViewModifier {
    @Environment(\.customBottomNavigationAvoidanceInset) private var avoidanceInset

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: max(0, avoidanceInset))
        }
    }
}

extension View {
    /// 让滚动内容为底部悬浮 Dock 让出空间，保证最后一个元素完整可见、可点。
    ///
    /// Dock 高度取自环境值（唯一口径），在 tab 之外（如 `.sheet`）自动退化为 0，因此
    /// 即使在不需要的场合误加也不会造成留白。
    func avoidingBottomDock() -> some View {
        modifier(BottomDockAvoidanceModifier())
    }
}
