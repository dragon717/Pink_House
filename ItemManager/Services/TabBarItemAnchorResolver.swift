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
        print("🎯 [resolvedFrame] guideTargetKey: \(guideTargetKey), preferredTabIndex: \(preferredTabIndex?.description ?? "nil")")

        let screenBounds = CGRect(origin: .zero, size: geometry.size)
        let candidates: [CGRect?] = [
            preferredTabIndex.flatMap { liveFrame(at: $0) },
            AppFirstLaunchGuideManager.shared.guideTargetFrame(for: guideTargetKey)
        ]

        if let liveFrame = candidates[0] {
            print("   候选1 (liveFrame): \(liveFrame)")
        } else {
            print("   候选1 (liveFrame): nil")
        }
        if let capturedFrame = candidates[1] {
            print("   候选2 (capturedFrame): \(capturedFrame)")
        } else {
            print("   候选2 (capturedFrame): nil")
        }

        for candidate in candidates.compactMap({ $0 }) {
            let expandedFrame = candidate.insetBy(dx: -expansion, dy: -expansion)
            guard expandedFrame.width > 0,
                  expandedFrame.height > 0,
                  screenBounds.intersects(expandedFrame) else {
                print("   ⚠️ 候选坐标不符合条件，跳过")
                continue
            }
            let clampedFrame = clamped(expandedFrame, to: screenBounds)
            print("   ✅ 使用候选坐标: \(clampedFrame)")
            return clampedFrame
        }

        let clampedFallback = clamped(fallback, to: screenBounds)
        print("   ⚠️ 使用 fallback: \(clampedFallback)")
        return clampedFallback
    }

    #if canImport(UIKit)
    static func liveFrame(at tabIndex: Int) -> CGRect? {
        print("🔍 [TabBarItemAnchorResolver] 尝试获取 tabIndex: \(tabIndex) 的坐标（UIKit 方式）")

        guard let window = activeWindow() else {
            print("   ❌ 未找到 activeWindow")
            return nil
        }

        guard let tabBar = findTabBar(in: window) else {
            print("   ❌ 未找到 UITabBar（iOS 18+ 现代 TabView 不使用 UITabBar）")
            return nil
        }

        let buttons = tabBar.subviews
            .filter { NSStringFromClass(type(of: $0)).contains("UITabBarButton") }
            .sorted { $0.frame.minX < $1.frame.minX }

        print("   找到 \(buttons.count) 个 UITabBarButton")

        guard buttons.indices.contains(tabIndex) else {
            print("   ❌ tabIndex \(tabIndex) 超出范围 (0..<\(buttons.count))")
            return nil
        }

        let button = buttons[tabIndex]
        let globalFrame = button.convert(button.bounds, to: nil)
        print("   ✅ 返回 Tab[\(tabIndex)] globalFrame: \(globalFrame)")
        return globalFrame
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
