import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum TabBarItemAnchorResolver {

    struct CompactCenterPlatterState {
        let isCompact: Bool
        let frame: CGRect?
    }

    struct TabBarSubviewSnapshot {
        let depth: Int
        let className: String
        let frame: CGRect
        let alpha: CGFloat
        let isHidden: Bool
    }

    /// LegacyTabView 自绘底栏 tab 数量。
    static let mainTabCount = 4

    static func resolvedFrame(
        for guideTargetKey: GuideTargetKey,
        preferredTabIndex: Int? = nil,
        in geometry: GeometryProxy,
        expansion: CGFloat = 0,
        fallback: CGRect
    ) -> CGRect {
        let screenBounds = CGRect(origin: .zero, size: geometry.size)
        let liveCandidate = preferredTabIndex.flatMap { liveFrame(at: $0) }
        let swiftUICandidate = AppFirstLaunchGuideManager.shared.guideTargetFrame(for: guideTargetKey)

        let candidates: [CGRect?] = [liveCandidate, swiftUICandidate]

        for candidate in candidates.compactMap({ $0 }) {
            let expandedFrame = candidate.insetBy(dx: -expansion, dy: -expansion)
            guard expandedFrame.width > 0,
                  expandedFrame.height > 0,
                  screenBounds.intersects(expandedFrame) else {
                continue
            }
            return clamped(expandedFrame, to: screenBounds)
        }

        return clamped(fallback, to: screenBounds)
    }

    #if canImport(UIKit)
    @available(*, deprecated, message: "旧原生底栏已退役；仅保留原生 TabBar 调试兜底，下个 cycle 删")
    static func tabBarDebugSnapshots() -> [TabBarSubviewSnapshot] {
        guard let window = activeWindow(),
              let tabBar = findTabBar(in: window) else {
            return []
        }

        return recursiveSnapshots(in: tabBar)
            .sorted { lhs, rhs in
                if lhs.frame.minX == rhs.frame.minX {
                    if lhs.depth == rhs.depth {
                        return lhs.frame.width < rhs.frame.width
                    }
                    return lhs.depth < rhs.depth
                }
                return lhs.frame.minX < rhs.frame.minX
            }
    }

    private static func recursiveSnapshots(in root: UIView, depth: Int = 0) -> [TabBarSubviewSnapshot] {
        var snapshots: [TabBarSubviewSnapshot] = root.subviews.map { view in
            TabBarSubviewSnapshot(
                depth: depth,
                className: NSStringFromClass(type(of: view)),
                frame: view.convert(view.bounds, to: nil),
                alpha: view.alpha,
                isHidden: view.isHidden
            )
        }

        for subview in root.subviews {
            snapshots.append(contentsOf: recursiveSnapshots(in: subview, depth: depth + 1))
        }

        return snapshots
    }

    @available(*, deprecated, message: "旧原生底栏已退役；仅保留原生 TabBar 调试兜底，下个 cycle 删")
    static func compactCenterPlatterState() -> CompactCenterPlatterState? {
        guard let window = activeWindow(),
              let tabBar = findTabBar(in: window),
              let platter = findMainPlatter(in: tabBar) else {
            return nil
        }

        let globalFrame = platter.convert(platter.bounds, to: nil)
        guard globalFrame.width > 0, globalFrame.height > 0, window.bounds.width > 0 else {
            return nil
        }

        let widthRatio = globalFrame.width / window.bounds.width
        let isCompact = platter.isHidden || platter.alpha < 0.01 || widthRatio < 0.68
        return CompactCenterPlatterState(isCompact: isCompact, frame: globalFrame)
    }

    static func liveFrame(at tabIndex: Int) -> CGRect? {
        guard let window = activeWindow() else {
            return nil
        }

        // 优先级 1: iOS ≤ 25 经典路径 — UITabBar → UITabBarButton
        if let tabBar = findTabBar(in: window) {
            let buttons = tabBar.subviews
                .filter { NSStringFromClass(type(of: $0)).contains("UITabBarButton") }
                .sorted { $0.frame.minX < $1.frame.minX }

            if buttons.indices.contains(tabIndex) {
                return buttons[tabIndex].convert(buttons[tabIndex].bounds, to: nil)
            }

            // 优先级 2: 原生浮动 TabBar — UITabBar 存在但无 UITabBarButton
            // 使用 _UITabBarPlatterView 等分计算
            if let frame = platterBasedFrame(at: tabIndex, in: tabBar) {
                return frame
            }
        }

        // 优先级 3: 原生浮动 TabBar 不在 hierarchy
        // 深度搜索 window 中的 PlatterView
        if let frame = deepSearchPlatterFrame(at: tabIndex, in: window) {
            return frame
        }

        return nil
    }

    // MARK: - Retired native platter probe

    /// 在 UITabBar 内部找到主 PlatterView，按 tab 数量等分
    private static func platterBasedFrame(at tabIndex: Int, in tabBar: UITabBar) -> CGRect? {
        guard let platter = findMainPlatter(in: tabBar) else {
            return nil
        }
        return dividePlatter(platter, at: tabIndex, relativeTo: nil)
    }

    /// 原生浮动 TabBar 不在 hierarchy 时，直接在 window 中搜索 PlatterView
    private static func deepSearchPlatterFrame(at tabIndex: Int, in window: UIWindow) -> CGRect? {
        guard let platter = findMainPlatterDeep(in: window) else {
            return nil
        }
        return dividePlatter(platter, at: tabIndex, relativeTo: nil)
    }

    /// 在 UITabBar 的直接子视图中找最大的 _UITabBarPlatterView
    private static func findMainPlatter(in tabBar: UITabBar) -> UIView? {
        tabBar.subviews
            .filter {
                let name = NSStringFromClass(type(of: $0))
                return name.contains("PlatterView") && $0.frame.width > 100
            }
            .max { $0.frame.width < $1.frame.width }
    }

    /// 递归搜索整个 view hierarchy，找到 _UITabBarPlatterView（宽度 > 100，排除小的内嵌 platter）
    private static func findMainPlatterDeep(in view: UIView, depth: Int = 0) -> UIView? {
        // 限制搜索深度，避免性能问题
        guard depth < 10 else { return nil }

        let className = NSStringFromClass(type(of: view))

        // 匹配 PlatterView 且尺寸合理（是主 tab 容器而非小图标）
        if className.contains("PlatterView") && view.frame.width > 100 && view.frame.height > 30 {
            return view
        }

        // 递归搜索子视图
        for subview in view.subviews {
            if let found = findMainPlatterDeep(in: subview, depth: depth + 1) {
                return found
            }
        }

        return nil
    }

    /// 将 platter 按主 tab 数量等分，返回 index 对应的全局 frame
    private static func dividePlatter(_ platter: UIView, at tabIndex: Int, relativeTo: UIView?) -> CGRect? {
        let count = mainTabCount
        guard tabIndex >= 0, tabIndex < count else { return nil }

        let platterGlobal = platter.convert(platter.bounds, to: nil)
        guard platterGlobal.width > 0, platterGlobal.height > 0 else { return nil }

        let segmentWidth = platterGlobal.width / CGFloat(count)
        let segmentX = platterGlobal.minX + segmentWidth * CGFloat(tabIndex)

        return CGRect(
            x: segmentX,
            y: platterGlobal.minY,
            width: segmentWidth,
            height: platterGlobal.height
        )
    }

    // MARK: - Window / TabBar 查找

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { activationPriority($0.activationState) > activationPriority($1.activationState) }

        for scene in scenes {
            if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
                return keyWindow
            }
            if let visibleWindow = scene.windows.first(where: { !$0.isHidden }) {
                return visibleWindow
            }
        }

        return nil
    }

    private static func activationPriority(_ state: UIScene.ActivationState) -> Int {
        switch state {
        case .foregroundActive:
            return 3
        case .foregroundInactive:
            return 2
        case .background:
            return 1
        case .unattached:
            return 0
        @unknown default:
            return -1
        }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar {
            return tabBar
        }

        for subview in view.subviews {
            if let tabBar = findTabBar(in: subview) {
                return tabBar
            }
        }

        return nil
    }
    #else
    @available(*, deprecated, message: "旧原生底栏已退役；仅保留原生 TabBar 调试兜底，下个 cycle 删")
    static func tabBarDebugSnapshots() -> [TabBarSubviewSnapshot] {
        []
    }

    @available(*, deprecated, message: "旧原生底栏已退役；仅保留原生 TabBar 调试兜底，下个 cycle 删")
    static func compactCenterPlatterState() -> CompactCenterPlatterState? {
        nil
    }

    static func liveFrame(at tabIndex: Int) -> CGRect? {
        nil
    }
    #endif

    private static func clamped(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        guard !bounds.isEmpty else {
            return frame
        }

        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
