import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum TabBarItemAnchorResolver {

    static let mainTabCount = BottomDockSettingsManager.slotCount

    /// 仅在系统控件还未布局时给引导一个近似目标，不参与页面安全区计算。
    static func fallbackFrame(screenSize: CGSize, safeAreaBottom: CGFloat,
                              houseSlotIndex: Int = 1) -> CGRect {
        let count = max(1, mainTabCount)
        let width = screenSize.width / CGFloat(count)
        let height: CGFloat = 49
        let index = min(max(houseSlotIndex, 0), count - 1)
        return CGRect(x: width * CGFloat(index),
                      y: max(0, screenSize.height - max(0, safeAreaBottom) - height),
                      width: width, height: height)
    }

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
    /// 读取系统栏的可交互控件，不依赖系统私有的 platter 类名或版本分支。
    static func liveFrame(at tabIndex: Int) -> CGRect? {
        guard let window = activeWindow(), let tabBar = findTabBar(in: window),
              !tabBar.isHidden, tabBar.alpha > 0.01,
              let items = tabBar.items, items.indices.contains(tabIndex) else { return nil }
        let controls = visibleControls(in: tabBar).sorted {
            $0.convert($0.bounds, to: window).minX < $1.convert($1.bounds, to: window).minX
        }
        if controls.count == items.count {
            let control = controls[tabIndex]
            return control.convert(control.bounds, to: nil)
        }
        let frame = tabBar.convert(tabBar.bounds, to: nil)
        guard frame.width > 0, frame.height > 0 else { return nil }
        let width = frame.width / CGFloat(items.count)
        return CGRect(x: frame.minX + width * CGFloat(tabIndex), y: frame.minY,
                      width: width, height: frame.height)
    }

    private static func visibleControls(in view: UIView) -> [UIControl] {
        view.subviews.flatMap { child -> [UIControl] in
            guard !child.isHidden, child.alpha > 0.01 else { return [] }
            if let control = child as? UIControl, control.bounds.width > 20, control.bounds.height > 20 {
                return [control]
            }
            return visibleControls(in: child)
        }
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
