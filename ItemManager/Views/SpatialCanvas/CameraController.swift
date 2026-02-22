import SwiftUI
import RealityKit
import simd
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
public class CameraController: ObservableObject {
    @Published public var distance: Float = 3.0
    @Published public var rotationX: Float = 0.0
    @Published public var rotationY: Float = 0.0
    @Published public var target: SIMD3<Float> = .zero
    
    public let minDistance: Float = 0.5
    public let maxDistance: Float = 50.0
    public let minPitch: Float = -Float.pi / 2 + 0.1
    public let maxPitch: Float = Float.pi / 2 - 0.1
    
    private var cameraEntity: Entity?
    
    // 手势状态
    public var lastTranslation: CGSize?
    public var lastPanLocation: CGPoint?
    public var lastPinchScale: CGFloat = 1.0
    
    public init() {}
    
    public func setupCamera(in rootEntity: Entity) -> Entity {
        let cameraEntity = Entity()
        cameraEntity.name = "camera"
        
        var cameraComponent = PerspectiveCameraComponent()
        cameraComponent.fieldOfViewInDegrees = 60
        cameraComponent.near = 0.1
        cameraComponent.far = 1000
        cameraEntity.components.set(cameraComponent)
        
        rootEntity.addChild(cameraEntity)
        self.cameraEntity = cameraEntity
        
        updateCameraTransform()
        
        return cameraEntity
    }
    
    public func updateCameraTransform() {
        guard let cameraEntity = cameraEntity else { return }
        
        let clampedDistance = max(minDistance, min(maxDistance, distance))
        let clampedRotationX = max(minPitch, min(maxPitch, rotationX))
        
        let cosPitch = cos(clampedRotationX)
        let sinPitch = sin(clampedRotationX)
        let cosYaw = cos(rotationY)
        let sinYaw = sin(rotationY)
        
        let position = SIMD3<Float>(
            target.x + clampedDistance * cosPitch * sinYaw,
            target.y + clampedDistance * sinPitch,
            target.z + clampedDistance * cosPitch * cosYaw
        )
        
        cameraEntity.position = position
        
        // 使用 RealityKit 的 look 方法让相机朝向目标
        cameraEntity.look(at: target, from: position, relativeTo: nil)
    }
    
    public func rotate(deltaX: Float, deltaY: Float) {
        rotationY += deltaX
        rotationX += deltaY
        rotationX = max(minPitch, min(maxPitch, rotationX))
        updateCameraTransform()
    }
    
    public func zoom(delta: Float) {
        distance += delta
        distance = max(minDistance, min(maxDistance, distance))
        updateCameraTransform()
    }
    
    public func pan(deltaX: Float, deltaY: Float) {
        let cosYaw = cos(rotationY)
        let sinYaw = sin(rotationY)
        
        let right = SIMD3<Float>(cosYaw, 0, -sinYaw)
        let up = SIMD3<Float>(0, 1, 0)
        
        // 使用固定的平移速度，避免距离影响
        let panSpeed: Float = 0.005
        target += right * deltaX * panSpeed + up * (-deltaY) * panSpeed
        updateCameraTransform()
    }
    
    public func reset() {
        distance = 3.0
        rotationX = 0.0
        rotationY = 0.0
        target = .zero
        updateCameraTransform()
    }
}

public struct CameraGestureView: UIViewRepresentable {
    @ObservedObject var controller: CameraController
    
    public init(controller: CameraController) {
        self.controller = controller
    }
    
    public func makeUIView(context: Context) -> CameraGestureUIView {
        let view = CameraGestureUIView()
        view.controller = controller
        return view
    }
    
    public func updateUIView(_ uiView: CameraGestureUIView, context: Context) {}
}

public class CameraGestureUIView: UIView {
    var controller: CameraController?
    
    private var lastRotationLocation: CGPoint?
    private var lastPanLocation: CGPoint?
    private var lastPinchScale: CGFloat = 1.0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupGestures()
    }
    
    private func setupView() {
        // 允许事件穿透到下层视图
        isUserInteractionEnabled = true
    }
    
    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 只响应手势区域，让点击事件穿透到 RealityView
        return true
    }
    
    private func setupGestures() {
        // 单指旋转
        let singlePanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSinglePan(_:)))
        singlePanGesture.delegate = self
        singlePanGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(singlePanGesture)
        
        // 双指平移
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        addGestureRecognizer(panGesture)
        
        // 双指缩放
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)
        
        // 旋转手势（可选）
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotationGesture.delegate = self
        addGestureRecognizer(rotationGesture)
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard let controller = controller else { return }
        
        switch gesture.state {
        case .changed:
            let rotation = Float(gesture.rotation)
            controller.rotationY += rotation * 0.5
            controller.updateCameraTransform()
            gesture.rotation = 0
        default:
            break
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let controller = controller else { return }
        
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            lastPanLocation = location
        case .changed:
            guard let lastLocation = lastPanLocation else { return }
            let deltaX = Float(location.x - lastLocation.x)
            let deltaY = Float(location.y - lastLocation.y)
            controller.pan(deltaX: deltaX, deltaY: deltaY)
            lastPanLocation = location
        case .ended, .cancelled:
            lastPanLocation = nil
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let controller = controller else { return }
        
        switch gesture.state {
        case .began:
            lastPinchScale = gesture.scale
        case .changed:
            let scale = Float(gesture.scale / lastPinchScale)
            let zoomDelta = (1.0 - scale) * controller.distance * 2
            controller.zoom(delta: zoomDelta)
            lastPinchScale = gesture.scale
        case .ended, .cancelled:
            lastPinchScale = 1.0
        default:
            break
        }
    }
    
    @objc private func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
        guard let controller = controller else { return }
        
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            lastRotationLocation = location
        case .changed:
            guard let lastLocation = lastRotationLocation else { return }
            let deltaX = Float(location.x - lastLocation.x) * 0.01
            let deltaY = Float(location.y - lastLocation.y) * 0.01
            controller.rotate(deltaX: deltaX, deltaY: deltaY)
            lastRotationLocation = location
        case .ended, .cancelled:
            lastRotationLocation = nil
        default:
            break
        }
    }
}

extension CameraGestureUIView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
