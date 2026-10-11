import SwiftUI
import UIKit

/// 单个 scene 一个宿主，覆盖 sheet，空白区域把触摸交回原窗口；不夺取 key window。
struct OperationFeedbackSceneInstaller: UIViewRepresentable {
    let isEnabled: Bool
    let center: OperationFeedbackCenter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var guide = AppFirstLaunchGuideManager.shared

    init(isEnabled: Bool, center: OperationFeedbackCenter? = nil) {
        self.isEnabled = isEnabled
        self.center = center ?? .shared
    }

    private var canPresent: Bool {
        isEnabled && scenePhase == .active && !guide.isShowingGuide && !guide.isShowingFeatureExperienceGuide
    }

    func makeCoordinator() -> Coordinator { Coordinator(center: center) }

    func makeUIView(context: Context) -> FeedbackSceneProbe {
        let view = FeedbackSceneProbe()
        view.onSceneChange = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(to: scene, isEnabled: canPresent)
        }
        return view
    }

    func updateUIView(_ view: FeedbackSceneProbe, context: Context) {
        view.onSceneChange = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(to: scene, isEnabled: canPresent)
        }
        context.coordinator.attach(to: view.window?.windowScene, isEnabled: canPresent)
    }

    static func dismantleUIView(_ view: FeedbackSceneProbe, coordinator: Coordinator) {
        coordinator.window?.isHidden = true
        coordinator.window = nil
    }

    @MainActor
    final class Coordinator {
        var window: FeedbackPassThroughWindow?
        private var controller: UIHostingController<OperationFeedbackOverlay>?
        private let center: OperationFeedbackCenter

        init(center: OperationFeedbackCenter) { self.center = center }
        nonisolated deinit {}

        func attach(to scene: UIWindowScene?, isEnabled: Bool) {
            guard let scene else { return }
            if window?.windowScene !== scene {
                window?.isHidden = true
                let window = FeedbackPassThroughWindow(windowScene: scene)
                let controller = UIHostingController(rootView: OperationFeedbackOverlay(
                    isEnabled: isEnabled, center: center, reportFrame: { [weak window] frame in
                        window?.cardFrame = frame
                    }))
                controller.view.backgroundColor = .clear
                controller.view.isOpaque = false
                window.rootViewController = controller
                window.backgroundColor = .clear
                window.isOpaque = false
                window.windowLevel = .normal + 1
                window.frame = scene.coordinateSpace.bounds
                controller.view.frame = window.bounds
                controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                window.isHidden = false
                self.window = window
                self.controller = controller
            } else {
                controller?.rootView = OperationFeedbackOverlay(isEnabled: isEnabled, center: center,
                    reportFrame: { [weak window] frame in window?.cardFrame = frame })
            }
        }
    }
}

final class FeedbackSceneProbe: UIView {
    var onSceneChange: ((UIWindowScene?) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onSceneChange?(window?.windowScene)
    }
}

final class FeedbackPassThroughWindow: UIWindow {
    var cardFrame: CGRect = .zero
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard cardFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct OperationFeedbackOverlay: View {
    let isEnabled: Bool
    let center: OperationFeedbackCenter
    let reportFrame: (CGRect) -> Void

    private var visibleMessage: OperationFeedbackCenter.Message? {
        guard isEnabled else { return nil }
        return center.current
    }

    var body: some View {
        VStack {
            if let message = visibleMessage {
                OperationFeedbackCard(message: message)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: reportFrame)
                    .id(message.id)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .accessibilityHidden(visibleMessage == nil)
        .task(id: visibleMessage?.id) {
            guard let message = visibleMessage else { reportFrame(.zero); return }
            UINotificationFeedbackGenerator().notificationOccurred(message.kind == .error ? .error : .success)
            let announcement = [message.text,
                message.fishCoins > 0 ? "鱼币 +%@".appLocalized(String(message.fishCoins)) : nil,
                message.detail].compactMap { $0 }.joined(separator: "，")
            UIAccessibility.post(notification: .announcement, argument: announcement)
            do {
                try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning
                                                  ? max(5, message.duration) : message.duration))
                try Task.checkCancellation()
                center.dismiss(id: message.id)
            } catch { /* 视图切换不消费提示；重新出现后继续展示。 */ }
        }
    }
}
