import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum TabBarItemAnchorResolver {
    static func resolvedFrame(
        for guideTargetKey: GuideTargetKey,
        preferredTabIndex: Int? = nil,
        in geometry: GeometryProxy,
        expansion: CGFloat = 0,
        fallback: CGRect
    ) -> CGRect {
        let screenBounds = CGRect(origin: .zero, size: geometry.size)
        let candidates: [CGRect?] = [
            preferredTabIndex.flatMap { liveFrame(at: $0) },
            AppFirstLaunchGuideManager.shared.guideTargetFrame(for: guideTargetKey)
        ]

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
    static func liveFrame(at tabIndex: Int) -> CGRect? {
        guard let window = activeWindow(),
              let tabBar = findTabBar(in: window) else {
            return nil
        }

        let buttons = tabBar.subviews
            .filter { NSStringFromClass(type(of: $0)).contains("UITabBarButton") }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard buttons.indices.contains(tabIndex) else {
            return nil
        }

        let button = buttons[tabIndex]
        return button.convert(button.bounds, to: nil)
    }

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
