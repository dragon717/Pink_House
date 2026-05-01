import MetalKit
import SwiftUI

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
        view.isPaused = request.isPaused
        view.delegate = context.coordinator
        context.coordinator.configure(request: request)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isPaused = request.isPaused
        context.coordinator.configure(request: request)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var request = AvatarRenderRequest()

        func configure(request: AvatarRenderRequest) {
            self.request = request
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
