//
//  SpatialSceneView.swift
//  ItemManager
//
//  3D场景视图 - Metal渲染器
//

import SwiftUI
import MetalKit
import simd

/// 场景对象类型
public enum SceneObjectType {
    case gsModel    // 高斯泼溅模型
    case primitive  // 基本几何体
    case imported   // 导入的模型
}

/// 场景对象
public struct SceneObject: Identifiable {
    public let id: UUID
    public var type: SceneObjectType
    public var position: SIMD3<Float>
    public var rotation: SIMD3<Float>
    public var scale: SIMD3<Float>
    public var gsModelPath: String?  // 仅用于 GS 模型
    public var color: SIMD4<Float>   // 用于基本几何体
    
    public init(
        id: UUID = UUID(),
        type: SceneObjectType,
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        gsModelPath: String? = nil,
        color: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.gsModelPath = gsModelPath
        self.color = color
    }
}

/// 纯 Metal 3D 场景视图
public struct SpatialSceneView: View {
    
    // MARK: - 属性
    
    @Binding var selectedObject: SceneObject?
    @Binding var objects: [SceneObject]
    var onObjectTap: (SceneObject) -> Void
    var onObjectTransform: (SceneObject) -> Void
    
    @State private var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 5)
    @State private var cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    @State private var cameraUp: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    
    // MARK: - 初始化
    
    public init(
        selectedObject: Binding<SceneObject?>,
        objects: Binding<[SceneObject]>,
        onObjectTap: @escaping (SceneObject) -> Void = { _ in },
        onObjectTransform: @escaping (SceneObject) -> Void = { _ in }
    ) {
        self._selectedObject = selectedObject
        self._objects = objects
        self.onObjectTap = onObjectTap
        self.onObjectTransform = onObjectTransform
    }
    
    // MARK: - 视图
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Metal 渲染层
                MetalSceneRendererView(
                    objects: $objects,
                    selectedObject: $selectedObject,
                    cameraPosition: $cameraPosition,
                    cameraTarget: $cameraTarget,
                    cameraUp: $cameraUp,
                    onObjectTap: onObjectTap
                )
                
                // 选中高亮框
                if let selected = selectedObject,
                   let index = objects.firstIndex(where: { $0.id == selected.id }) {
                    SelectionBoxOverlay(
                        object: $objects[index],
                        cameraPosition: cameraPosition,
                        cameraTarget: cameraTarget,
                        viewSize: geometry.size
                    )
                }
                
                // 相机控制提示
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CameraControlHint()
                            .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Metal 场景渲染器

struct MetalSceneRendererView: UIViewRepresentable {
    
    @Binding var objects: [SceneObject]
    @Binding var selectedObject: SceneObject?
    @Binding var cameraPosition: SIMD3<Float>
    @Binding var cameraTarget: SIMD3<Float>
    @Binding var cameraUp: SIMD3<Float>
    var onObjectTap: (SceneObject) -> Void
    
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.backgroundColor = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.sampleCount = 1
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        
        // 创建渲染器
        let renderer = MetalSceneRenderer(
            metalView: mtkView,
            objects: $objects,
            cameraPosition: $cameraPosition,
            cameraTarget: $cameraTarget,
            cameraUp: $cameraUp
        )
        
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer
        context.coordinator.mtkView = mtkView
        
        // 添加手势
        addGestureRecognizers(to: mtkView, coordinator: context.coordinator)
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.updateObjects(objects)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func addGestureRecognizers(to view: MTKView, coordinator: Coordinator) {
        // 点击手势 - 选择对象
        let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        // 平移手势 - 移动对象或相机
        let panGesture = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        // 缩放手势
        let pinchGesture = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        // 旋转手势
        let rotationGesture = UIRotationGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleRotation(_:)))
        view.addGestureRecognizer(rotationGesture)
    }
    
    class Coordinator: NSObject {
        weak var renderer: MetalSceneRenderer?
        weak var mtkView: MTKView?
        
        // 手势状态
        private var initialObjectPosition: SIMD3<Float>?
        private var initialCameraPosition: SIMD3<Float>?
        private var lastPanLocation: CGPoint?
        private var initialObjectScale: SIMD3<Float>?
        private var initialObjectRotation: SIMD3<Float>?
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mtkView = mtkView else { return }
            
            let location = gesture.location(in: mtkView)
            
            // 将屏幕坐标转换为归一化设备坐标
            let ndcX = (Float(location.x) / Float(mtkView.bounds.width)) * 2 - 1
            let ndcY = -((Float(location.y) / Float(mtkView.bounds.height)) * 2 - 1)
            
            // 使用渲染器进行射线检测
            if let hitObject = renderer?.raycastObject(ndcX: ndcX, ndcY: ndcY) {
                renderer?.selectObject(hitObject)
            } else {
                renderer?.deselectObject()
            }
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: mtkView)
            let translation = gesture.translation(in: mtkView)
            
            switch gesture.state {
            case .began:
                lastPanLocation = location
                
                // 如果有选中对象，准备移动对象
                if renderer?.selectedObject != nil {
                    initialObjectPosition = renderer?.selectedObject?.position
                } else {
                    // 否则移动相机
                    initialCameraPosition = renderer?.cameraPosition
                }
                
            case .changed:
                guard let lastLocation = lastPanLocation else { return }
                
                let deltaX = Float(location.x - lastLocation.x)
                let deltaY = Float(location.y - lastLocation.y)
                
                if let _ = renderer?.selectedObject {
                    // 移动选中对象
                    moveSelectedObject(deltaX: deltaX * 0.01, deltaY: -deltaY * 0.01)
                } else {
                    // 轨道旋转相机
                    orbitCamera(deltaX: deltaX * 0.01, deltaY: deltaY * 0.01)
                }
                
                lastPanLocation = location
                
            case .ended, .cancelled:
                initialObjectPosition = nil
                initialCameraPosition = nil
                lastPanLocation = nil
                
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialObjectScale = renderer?.selectedObject?.scale
                
            case .changed:
                guard let initialScale = initialObjectScale else {
                    // 如果没有选中对象，缩放相机距离
                    let scale = Float(gesture.scale)
                    zoomCamera(scale: scale)
                    return
                }
                
                let scale = Float(gesture.scale)
                renderer?.updateSelectedObject { object in
                    object.scale = initialScale * scale
                }
                
            case .ended, .cancelled:
                initialObjectScale = nil
                
            default:
                break
            }
        }
        
        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialObjectRotation = renderer?.selectedObject?.rotation
                
            case .changed:
                guard let initialRotation = initialObjectRotation else { return }
                let rotation = Float(gesture.rotation)
                renderer?.updateSelectedObject { object in
                    object.rotation.y = initialRotation.y + rotation
                }
                
            case .ended, .cancelled:
                initialObjectRotation = nil
                
            default:
                break
            }
        }
        
        private func moveSelectedObject(deltaX: Float, deltaY: Float) {
            guard let initialPosition = initialObjectPosition else { return }
            renderer?.updateSelectedObject { object in
                object.position.x = initialPosition.x + deltaX
                object.position.y = initialPosition.y + deltaY
            }
        }
        
        private func orbitCamera(deltaX: Float, deltaY: Float) {
            guard let initialPos = initialCameraPosition else { return }
            
            // 计算球坐标
            let radius = length(initialPos - renderer!.cameraTarget)
            var theta = atan2(initialPos.x, initialPos.z)  // 水平角度
            var phi = acos(initialPos.y / radius)          // 垂直角度
            
            // 更新角度
            theta += deltaX * 0.5
            phi = clamp(phi + deltaY * 0.5, 0.1, Float.pi - 0.1)
            
            // 转换回笛卡尔坐标
            let newX = radius * sin(phi) * sin(theta)
            let newY = radius * cos(phi)
            let newZ = radius * sin(phi) * cos(theta)
            
            renderer?.cameraPosition = SIMD3<Float>(newX, newY, newZ)
        }
        
        private func zoomCamera(scale: Float) {
            guard let initialPos = initialCameraPosition else { return }
            let direction = normalize(initialPos - renderer!.cameraTarget)
            let distance = length(initialPos - renderer!.cameraTarget)
            let newDistance = clamp(distance / scale, 0.5, 50.0)
            renderer?.cameraPosition = renderer!.cameraTarget + direction * newDistance
        }
        
        private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
            return Swift.min(Swift.max(value, min), max)
        }
    }
}

// MARK: - Metal 场景渲染器

class MetalSceneRenderer: NSObject, MTKViewDelegate {
    
    // MARK: - 属性
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    
    @Binding var objects: [SceneObject]
    @Binding var cameraPosition: SIMD3<Float>
    @Binding var cameraTarget: SIMD3<Float>
    @Binding var cameraUp: SIMD3<Float>
    
    var selectedObject: SceneObject? {
        didSet {
            selectedObjectID = selectedObject?.id
        }
    }
    private var selectedObjectID: UUID?
    
    // GS 渲染器缓存
    private var gsRenderers: [UUID: GaussianSplatRenderer] = [:]
    
    // MARK: - 初始化
    
    init(
        metalView: MTKView,
        objects: Binding<[SceneObject]>,
        cameraPosition: Binding<SIMD3<Float>>,
        cameraTarget: Binding<SIMD3<Float>>,
        cameraUp: Binding<SIMD3<Float>>
    ) {
        self.device = metalView.device!
        self.commandQueue = device.makeCommandQueue()!
        self._objects = objects
        self._cameraPosition = cameraPosition
        self._cameraTarget = cameraTarget
        self._cameraUp = cameraUp
        
        super.init()
        
        setupPipeline()
        setupDepthStencilState()
        loadInitialObjects()
    }
    
    private func setupPipeline() {
        // 基础几何体渲染管线设置
        // 这里简化处理，实际应该创建完整的 shader
    }
    
    private func setupDepthStencilState() {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: descriptor)
    }
    
    private func loadInitialObjects() {
        for object in objects {
            loadObject(object)
        }
    }
    
    private func loadObject(_ object: SceneObject) {
        guard object.type == .gsModel,
              let path = object.gsModelPath else { return }
        
        // 创建或获取 GS 渲染器
        if gsRenderers[object.id] == nil {
            // 注意：这里需要异步加载 PLY 文件
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                    let parser = PLYParser()
                    let url = URL(fileURLWithPath: path)
                    let pointCloud = try parser.parse(url: url)
                    DispatchQueue.main.async {
                        guard let renderer = GaussianSplatRenderer(device: self.device) else {
                            print("[MetalSceneRenderer] Failed to create renderer")
                            return
                        }
                        renderer.loadPointCloud(pointCloud)
                        self.gsRenderers[object.id] = renderer
                    }
                } catch {
                    print("[MetalSceneRenderer] Failed to load PLY: \(error)")
                }
            }
        }
    }
    
    // MARK: - 更新
    
    func updateObjects(_ newObjects: [SceneObject]) {
        // 检测新增对象
        for object in newObjects {
            if !objects.contains(where: { $0.id == object.id }) {
                loadObject(object)
            }
        }
        
        // 更新选中状态
        if let selectedID = selectedObjectID,
           let object = newObjects.first(where: { $0.id == selectedID }) {
            selectedObject = object
        }
    }
    
    func selectObject(_ object: SceneObject) {
        selectedObject = object
    }
    
    func deselectObject() {
        selectedObject = nil
    }
    
    func updateSelectedObject(_ update: (inout SceneObject) -> Void) {
        guard var object = selectedObject,
              let index = objects.firstIndex(where: { $0.id == object.id }) else { return }
        
        update(&object)
        objects[index] = object
        selectedObject = object
    }
    
    // MARK: - 射线检测
    
    func raycastObject(ndcX: Float, ndcY: Float) -> SceneObject? {
        // 构建射线
        let viewMatrix = lookAt(cameraPosition, cameraTarget, cameraUp)
        let projectionMatrix = perspective(fov: Float.pi / 4, aspect: 1.0, near: 0.1, far: 100.0)
        let invVP = (projectionMatrix * viewMatrix).inverse
        
        let rayStart = SIMD4<Float>(ndcX, ndcY, -1, 1)
        let rayEnd = SIMD4<Float>(ndcX, ndcY, 1, 1)
        
        let worldStart = invVP * rayStart
        let worldEnd = invVP * rayEnd
        
        let origin = worldStart.xyz / worldStart.w
        let direction = normalize(worldEnd.xyz / worldEnd.w - origin)
        
        // 简单的包围盒检测
        var closestObject: SceneObject?
        var closestDistance: Float = Float.infinity
        
        for object in objects {
            // 简化的球形包围盒检测
            let toObject = object.position - origin
            let projection = dot(toObject, direction)
            
            if projection > 0 {
                let distance = length(toObject - direction * projection)
                let radius: Float = 0.5 * max(object.scale.x, object.scale.y, object.scale.z)
                
                if distance < radius && projection < closestDistance {
                    closestDistance = projection
                    closestObject = object
                }
            }
        }
        
        return closestObject
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 处理尺寸变化
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // 渲染 GS 模型
        for object in objects where object.type == .gsModel {
            if let gsRenderer = gsRenderers[object.id] {
                // 更新 GS 渲染器的相机
                gsRenderer.updateCamera(
                    position: cameraPosition,
                    target: cameraTarget,
                    up: cameraUp
                )
                
                // 渲染到当前 render pass
                gsRenderer.render(to: renderPassDescriptor, commandBuffer: commandBuffer)
            }
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - 矩阵辅助函数
    
    private func lookAt(_ eye: SIMD3<Float>, _ target: SIMD3<Float>, _ up: SIMD3<Float>) -> float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        
        return float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
    
    private func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let tanHalfFov = tan(fov / 2)
        
        return float4x4(
            SIMD4<Float>(1 / (aspect * tanHalfFov), 0, 0, 0),
            SIMD4<Float>(0, 1 / tanHalfFov, 0, 0),
            SIMD4<Float>(0, 0, (far + near) / (near - far), -1),
            SIMD4<Float>(0, 0, (2 * far * near) / (near - far), 0)
        )
    }
}

// MARK: - 选中框覆盖层

struct SelectionBoxOverlay: View {
    @Binding var object: SceneObject
    var cameraPosition: SIMD3<Float>
    var cameraTarget: SIMD3<Float>
    var viewSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            // 计算对象在屏幕上的投影位置
            let screenPos = projectToScreen(
                position: object.position,
                cameraPosition: cameraPosition,
                cameraTarget: cameraTarget,
                viewSize: viewSize
            )
            
            // 绘制选中框
            Rectangle()
                .strokeBorder(Color.pink, lineWidth: 2)
                .frame(width: 100 * CGFloat(object.scale.x), height: 100 * CGFloat(object.scale.y))
                .position(x: screenPos.x, y: screenPos.y)
                .opacity(screenPos.visible ? 1 : 0)
        }
    }
    
    private func projectToScreen(
        position: SIMD3<Float>,
        cameraPosition: SIMD3<Float>,
        cameraTarget: SIMD3<Float>,
        viewSize: CGSize
    ) -> (x: CGFloat, y: CGFloat, z: Float, visible: Bool) {
        // 简化的投影计算
        let viewMatrix = lookAt(cameraPosition, cameraTarget, SIMD3<Float>(0, 1, 0))
        let projectionMatrix = perspective(fov: Float.pi / 4, aspect: Float(viewSize.width / viewSize.height), near: 0.1, far: 100.0)
        
        let viewPos = viewMatrix * SIMD4<Float>(position, 1)
        let clipPos = projectionMatrix * viewPos
        
        let ndc = clipPos.xyz / clipPos.w
        let screenX = (CGFloat(ndc.x) + 1) * 0.5 * viewSize.width
        let screenY = (1 - CGFloat(ndc.y)) * 0.5 * viewSize.height
        let depth = ndc.z
        let visible = ndc.x >= -1 && ndc.x <= 1 && ndc.y >= -1 && ndc.y <= 1 && depth >= 0 && depth <= 1
        
        return (x: screenX, y: screenY, z: depth, visible: visible)
    }
    
    private func lookAt(_ eye: SIMD3<Float>, _ target: SIMD3<Float>, _ up: SIMD3<Float>) -> float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        
        return float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
    
    private func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let tanHalfFov = tan(fov / 2)
        
        return float4x4(
            SIMD4<Float>(1 / (aspect * tanHalfFov), 0, 0, 0),
            SIMD4<Float>(0, 1 / tanHalfFov, 0, 0),
            SIMD4<Float>(0, 0, (far + near) / (near - far), -1),
            SIMD4<Float>(0, 0, (2 * far * near) / (near - far), 0)
        )
    }
}

// MARK: - 相机控制提示

struct CameraControlHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("相机控制")
                .font(.caption)
                .fontWeight(.bold)
            Text("拖动: 旋转视角")
                .font(.caption2)
            Text("双指缩放: 缩放视角")
                .font(.caption2)
            Text("选中对象后拖动: 移动对象")
                .font(.caption2)
        }
        .padding(8)
        .background(Color.black.opacity(0.6))
        .foregroundColor(.white)
        .cornerRadius(8)
    }
}

// MARK: - 扩展

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(x, y, z)
    }
}
