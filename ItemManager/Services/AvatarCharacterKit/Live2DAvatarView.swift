import MetalKit
import SwiftUI
import UIKit

struct Live2DAvatarView: UIViewRepresentable {
    let request: AvatarRenderRequest

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        context.coordinator.attach(view: view)
        context.coordinator.configure(request: request)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.attach(view: uiView)
        context.coordinator.configure(request: request)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var request = AvatarRenderRequest()
        private weak var view: MTKView?
        private var isSystemPaused = false
        private var backgroundObserver: NSObjectProtocol?
        private var foregroundObserver: NSObjectProtocol?

        override init() {
            super.init()
            let center = NotificationCenter.default
            backgroundObserver = center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setSystemPaused(true)
            }
            foregroundObserver = center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setSystemPaused(false)
            }
        }

        deinit {
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
            }
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
        }

        func attach(view: MTKView) {
            self.view = view
            applyPauseState()
        }

        func configure(request: AvatarRenderRequest) {
            self.request = request
            applyPauseState()
        }

        private func setSystemPaused(_ isPaused: Bool) {
            isSystemPaused = isPaused
            applyPauseState()
        }

        private func applyPauseState() {
            view?.isPaused = request.isPaused || isSystemPaused
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            _ = size
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandQueue = view.device?.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
