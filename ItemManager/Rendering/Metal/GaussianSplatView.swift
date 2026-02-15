//
//  GaussianSplatView.swift
//  ItemManager
//
//  SwiftUI 包装的 3D Gaussian Splatting 渲染视图
//

import SwiftUI
import MetalKit
import simd

// MARK: - SwiftUI 视图

public struct GaussianSplatView: UIViewRepresentable {
    
    // MARK: - 属性
    
    /// 相机位置
    @Binding var cameraPosition: SIMD3<Float>
    
    /// 相机目标点
    @Binding var cameraTarget: SIMD3<Float>
    
    /// 是否启用交互
    var enableInteraction: Bool
    
    /// PLY 文件 URL
    var plyURL: URL?
    
    /// 渲染配置
    var configuration: RenderConfiguration
    
    /// 渲染统计回调
    var onRenderStatsUpdate: ((RenderStats) -> Void)?
    
    // MARK: - 初始化
    
    public init(
        cameraPosition: Binding<SIMD3<Float>> = .constant(SIMD3<Float>(0, 0, 5)),
        cameraTarget: Binding<SIMD3<Float>> = .constant(SIMD3<Float>(0, 0, 0)),
        enableInteraction: Bool = true,
        plyURL: URL? = nil,
        configuration: RenderConfiguration = RenderConfiguration(),
        onRenderStatsUpdate: ((RenderStats) -> Void)? = nil
    ) {
        self._cameraPosition = cameraPosition
        self._cameraTarget = cameraTarget
        self.enableInteraction = enableInteraction
        self.plyURL = plyURL
        self.configuration = configuration
        self.onRenderStatsUpdate = onRenderStatsUpdate
    }
    
    // MARK: - UIViewRepresentable
    
    public func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColor(
            red: Double(configuration.backgroundColor.x),
            green: Double(configuration.backgroundColor.y),
            blue: Double(configuration.backgroundColor.z),
            alpha: Double(configuration.backgroundColor.w)
        )
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        
        // 创建渲染器
        guard let renderer = GaussianSplatRenderer(device: device) else {
            fatalError("Failed to create GaussianSplatRenderer")
        }
        
        renderer.configuration = configuration
        renderer.delegate = context.coordinator
        
        // 加载 PLY 文件
        if let url = plyURL {
            do {
                try renderer.loadPLYFile(url: url)
            } catch {
                print("[GaussianSplatView] Failed to load PLY: \(error)")
            }
        }
        
        // 设置相机
        renderer.updateCamera(
            position: cameraPosition,
            target: cameraTarget
        )
        
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.mtkView = mtkView
        
        // 添加手势
        if enableInteraction {
            addGestureRecognizers(to: mtkView, context: context)
        }
        
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        
        // 更新相机
        renderer.updateCamera(
            position: cameraPosition,
            target: cameraTarget
        )
        
        // 更新背景色
        uiView.clearColor = MTLClearColor(
            red: Double(configuration.backgroundColor.x),
            green: Double(configuration.backgroundColor.y),
            blue: Double(configuration.backgroundColor.z),
            alpha: Double(configuration.backgroundColor.w)
        )
        
        // 更新配置
        renderer.configuration = configuration
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - 手势
    
    private func addGestureRecognizers(to view: MTKView, context: Context) {
        // 平移手势 - 旋转相机
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        view.addGestureRecognizer(panGesture)
        
        // 缩放手势
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinchGesture)
        
        // 双击重置
        let doubleTapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
    }
    
    // MARK: - Coordinator
    
    public class Coordinator: NSObject, GaussianSplatRendererDelegate {
        var parent: GaussianSplatView
        weak var renderer: GaussianSplatRenderer?
        weak var mtkView: MTKView?
        
        // 手势状态
        private var lastPanLocation: CGPoint = .zero
        private var initialCameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 5)
        private var initialCameraDistance: Float = 5.0
        private var rotationX: Float = 0
        private var rotationY: Float = 0
        
        init(_ parent: GaussianSplatView) {
            self.parent = parent
            super.init()
        }
        
        // MARK: GaussianSplatRendererDelegate
        
        public func renderer(_ renderer: GaussianSplatRenderer, didUpdateFrameTime frameTime: Double) {
            DispatchQueue.main.async {
                self.parent.onRenderStatsUpdate?(renderer.renderStats)
            }
        }
        
        public func renderer(_ renderer: GaussianSplatRenderer, didEncounterError error: Error) {
            print("[GaussianSplatView] Renderer error: \(error)")
        }
        
        // MARK: 手势处理
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let renderer = renderer else { return }
            
            let location = gesture.location(in: gesture.view)
            let viewSize = gesture.view?.bounds.size ?? CGSize(width: 1, height: 1)
            
            switch gesture.state {
            case .began:
                lastPanLocation = location
                initialCameraPosition = parent.cameraPosition
                
            case .changed:
                let deltaX = Float(location.x - lastPanLocation.x) / Float(viewSize.width)
                let deltaY = Float(location.y - lastPanLocation.y) / Float(viewSize.height)
                
                rotationY -= deltaX * 2.0 // 水平旋转
                rotationX -= deltaY * 2.0 // 垂直旋转
                
                // 限制垂直旋转角度
                rotationX = max(-Float.pi / 2 + 0.1, min(Float.pi / 2 - 0.1, rotationX))
                
                updateCameraPosition()
                lastPanLocation = location
                
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let renderer = renderer else { return }
            
            switch gesture.state {
            case .began:
                initialCameraDistance = length(parent.cameraPosition - parent.cameraTarget)
                
            case .changed:
                let scale = Float(gesture.scale)
                let newDistance = initialCameraDistance / scale
                let clampedDistance = max(0.5, min(50.0, newDistance))
                
                updateCameraPosition(distance: clampedDistance)
                gesture.scale = 1.0
                
            default:
                break
            }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            // 重置相机
            rotationX = 0
            rotationY = 0
            
            DispatchQueue.main.async {
                self.parent.cameraPosition = SIMD3<Float>(0, 0, 5)
                self.parent.cameraTarget = SIMD3<Float>(0, 0, 0)
            }
        }
        
        private func updateCameraPosition(distance: Float? = nil) {
            let dist = distance ?? length(parent.cameraPosition - parent.cameraTarget)
            
            // 球坐标转换
            let x = dist * cos(rotationX) * sin(rotationY)
            let y = dist * sin(rotationX)
            let z = dist * cos(rotationX) * cos(rotationY)
            
            let newPosition = parent.cameraTarget + SIMD3<Float>(x, y, z)
            
            DispatchQueue.main.async {
                self.parent.cameraPosition = newPosition
            }
        }
        
        private func length(_ v: SIMD3<Float>) -> Float {
            return sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        }
    }
}

// MARK: - 预览

struct GaussianSplatView_Previews: PreviewProvider {
    static var previews: some View {
        GaussianSplatView(
            cameraPosition: .constant(SIMD3<Float>(0, 0, 5)),
            cameraTarget: .constant(SIMD3<Float>(0, 0, 0)),
            enableInteraction: true,
            configuration: RenderConfiguration(
                backgroundColor: SIMD4<Float>(0.15, 0.15, 0.15, 1.0)
            )
        )
    }
}
