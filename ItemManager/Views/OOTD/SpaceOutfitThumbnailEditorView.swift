//
//  SpaceOutfitThumbnailEditorView.swift
//  ItemManager
//
//  空间书页缩略图设置视图 - 竖向4:3白框
//

import SwiftUI
import RealityKit
import ARKit
import SwiftData
import Combine

/// 空间书页缩略图编辑器 - 参考模型缩略图设置
struct SpaceOutfitThumbnailEditorView: View {
    let page: SpaceOutfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var isSaving = false
    @State private var sceneObjects: [SceneObject] = []
    @StateObject private var cameraController = SpaceOutfitCameraController()
    
    // 竖向 3:4 比例 (宽:高 = 3:4)
    private let thumbnailRatio: CGFloat = 3.0 / 4.0
    
    var body: some View {
        ZStack {
            // 背景色
            (colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.95, blue: 0.93))
                .ignoresSafeArea()
            
            // ARView 场景预览 + 手势层
            if !sceneObjects.isEmpty {
                SpaceOutfitEditorARContainer(
                    objects: sceneObjects,
                    cameraController: cameraController
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("场景为空")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("请先添加3D模型到场景")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 竖向 3:4 白框辅助定位
            GeometryReader { geometry in
                // 计算竖向3:4比例的框尺寸
                let maxHeight = geometry.size.height * 0.7
                let containerHeight = maxHeight
                let containerWidth = containerHeight * thumbnailRatio
                
                ZStack {
                    // 半透明遮罩
                    Color.black.opacity(0.3)
                        .mask(
                            Rectangle()
                                .overlay(
                                    Rectangle()
                                        .frame(width: containerWidth, height: containerHeight)
                                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                        .blendMode(.destinationOut)
                                )
                        )
                    
                    // 白色边框 - 竖向3:4比例
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: containerWidth, height: containerHeight)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    
                    // 角落标记
                    ThumbnailCornerMarkersPortrait(width: containerWidth, height: containerHeight)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .allowsHitTesting(false)
            }
            
            VStack {
                // 顶部标题栏
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("设置书页缩略图")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        saveThumbnail()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.pink)
                                .clipShape(Circle())
                        }
                    }
                    .disabled(isSaving || sceneObjects.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                // 手势提示
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill")
                        Text("单指旋转")
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.up.braille.fill")
                        Text("双指移动")
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.circle.fill")
                        Text("双指缩放")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.bottom, 8)
                
                // 底部按钮栏
                HStack(spacing: 16) {
                    Button {
                        resetCamera()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置视角")
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .task {
            await loadSceneObjects()
            // 加载保存的相机位置，如果没有保存则使用默认值（原点居中）
            if page.camPosX != 0 || page.camPosY != 0 || page.camPosZ != 0 {
                cameraController.distance = Float(page.camPosZ)
                cameraController.target = SIMD3<Float>(
                    Float(page.camPosX),
                    Float(page.camPosY),
                    0
                )
            } else {
                // 默认视角：原点居中，相机在Z轴正方向
                cameraController.distance = 5.0
                cameraController.target = SIMD3<Float>(0, 0, 0)
            }
        }
        // 禁用右滑返回手势
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in }
                .onEnded { _ in },
            including: .all
        )
        .interactiveDismissDisabled()
        .toolbar(.hidden, for: .navigationBar)
    }
    
    private func loadSceneObjects() async {
        let objects = await MainActor.run {
            page.fetchSceneObjects(context: modelContext)
        }
        
        await MainActor.run {
            self.sceneObjects = objects.map { $0.toSceneObject() }
        }
    }
    
    private func resetCamera() {
        cameraController.reset()
    }
    
    private func saveThumbnail() {
        isSaving = true
        
        Task {
            // 保存相机位置到书页
            await MainActor.run {
                page.camPosX = Double(cameraController.target.x)
                page.camPosY = Double(cameraController.target.y)
                page.camPosZ = Double(cameraController.distance)
                page.lastModified = Date()
                
                try? modelContext.save()
            }
            
            // 生成并保存缩略图到缓存（从ARView捕获）
            await generateAndSaveThumbnailFromARView()
            
            isSaving = false
            dismiss()
        }
    }
    
    /// 从ARView捕获缩略图并保存到缓存
    private func generateAndSaveThumbnailFromARView() async {
        // 获取ARView截图
        guard let screenshot = await captureARViewScreenshot() else {
            // 如果截图失败，使用占位图
            generatePlaceholderThumbnail()
            return
        }
        
        // 裁剪为竖向3:4比例
        let croppedImage = cropToPortrait3x4(image: screenshot)
        
        // 保存到缓存
        SpaceOutfitThumbnailCache.shared.saveThumbnail(croppedImage, for: page.id)
        
        // 发送通知，通知预览视图和封面视图更新
        NotificationCenter.default.post(name: .spaceOutfitThumbnailUpdated, object: page.id)
    }
    
    /// 捕获ARView截图
    private func captureARViewScreenshot() async -> UIImage? {
        // 通过通知获取ARView引用
        let notificationName = Notification.Name("SpaceOutfitARViewCaptureRequest")
        
        return await withCheckedContinuation { continuation in
            // 发送截图请求通知
            NotificationCenter.default.post(
                name: notificationName,
                object: nil,
                userInfo: ["completion": { (image: UIImage?) in
                    continuation.resume(returning: image)
                }]
            )
        }
    }
    
    /// 生成占位缩略图（当ARView截图失败时使用）
    private func generatePlaceholderThumbnail() {
        let thumbnailSize = CGSize(width: 300, height: 400)
        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()
        
        // 绘制背景
        context?.setFillColor(UIColor.systemGray6.cgColor)
        context?.fill(CGRect(origin: .zero, size: thumbnailSize))
        
        // 绘制3D图标
        let iconRect = CGRect(x: thumbnailSize.width/2 - 40, y: thumbnailSize.height/2 - 40, width: 80, height: 80)
        context?.setFillColor(UIColor.systemPink.cgColor)
        context?.fillEllipse(in: iconRect)
        
        // 添加文字
        let text = "3D"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: thumbnailSize.width/2 - textSize.width/2, y: thumbnailSize.height/2 - textSize.height/2), withAttributes: attributes)
        
        if let image = UIGraphicsGetImageFromCurrentImageContext() {
            SpaceOutfitThumbnailCache.shared.saveThumbnail(image, for: page.id)
            NotificationCenter.default.post(name: .spaceOutfitThumbnailUpdated, object: page.id)
        }
    }
    
    /// 裁剪图片为竖向3:4比例
    private func cropToPortrait3x4(image: UIImage) -> UIImage {
        let imageSize = image.size
        let targetRatio: CGFloat = 3.0 / 4.0
        
        var cropWidth: CGFloat
        var cropHeight: CGFloat
        
        let imageRatio = imageSize.width / imageSize.height
        
        if imageRatio > targetRatio {
            // 图片太宽，裁剪宽度
            cropHeight = imageSize.height
            cropWidth = cropHeight * targetRatio
        } else {
            // 图片太高，裁剪高度
            cropWidth = imageSize.width
            cropHeight = cropWidth / targetRatio
        }
        
        let cropX = (imageSize.width - cropWidth) / 2
        let cropY = (imageSize.height - cropHeight) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        guard let croppedCGImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - 通知名称扩展

extension Notification.Name {
    static let spaceOutfitThumbnailUpdated = Notification.Name("spaceOutfitThumbnailUpdated")
}

// MARK: - 竖向3:4 角落标记组件

struct ThumbnailCornerMarkersPortrait: View {
    let width: CGFloat
    let height: CGFloat
    let markerLength: CGFloat = 20
    let markerThickness: CGFloat = 3
    
    var body: some View {
        ZStack {
            // 左上角
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle()
                        .frame(width: markerLength, height: markerThickness)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Rectangle()
                        .frame(width: markerThickness, height: markerLength)
                    Spacer()
                }
                Spacer()
            }
            
            // 右上角
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .frame(width: markerLength, height: markerThickness)
                }
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .frame(width: markerThickness, height: markerLength)
                }
                Spacer()
            }
            
            // 左下角
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    Rectangle()
                        .frame(width: markerThickness, height: markerLength)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Rectangle()
                        .frame(width: markerLength, height: markerThickness)
                    Spacer()
                }
            }
            
            // 右下角
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .frame(width: markerThickness, height: markerLength)
                }
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .frame(width: markerLength, height: markerThickness)
                }
            }
        }
        .frame(width: width, height: height)
        .foregroundStyle(.white)
    }
}

// MARK: - Camera Controller (SpaceOutfit专用)

class SpaceOutfitCameraController: ObservableObject {
    @Published var distance: Float = 5.0
    @Published var rotationX: Float = 0.0
    @Published var rotationY: Float = 0.0
    @Published var target: SIMD3<Float> = .zero
    
    let minDistance: Float = 0.5
    let maxDistance: Float = 50.0
    let minPitch: Float = -Float.pi / 2 + 0.1
    let maxPitch: Float = Float.pi / 2 - 0.1
    
    func rotate(deltaX: Float, deltaY: Float) {
        rotationY += deltaX
        rotationX += deltaY
        rotationX = max(minPitch, min(maxPitch, rotationX))
    }
    
    func zoom(delta: Float) {
        distance += delta
        distance = max(minDistance, min(maxDistance, distance))
    }
    
    func pan(deltaX: Float, deltaY: Float) {
        let cosYaw = cos(rotationY)
        let sinYaw = sin(rotationY)
        
        let right = SIMD3<Float>(cosYaw, 0, -sinYaw)
        let up = SIMD3<Float>(0, 1, 0)
        
        let panSpeed: Float = 0.005
        target += right * deltaX * panSpeed + up * (-deltaY) * panSpeed
    }
    
    func reset() {
        distance = 5.0
        rotationX = 0.0
        rotationY = 0.0
        target = .zero
    }
}

// MARK: - AR Container View with Gestures

struct SpaceOutfitEditorARContainer: UIViewRepresentable {
    let objects: [SceneObject]
    @ObservedObject var cameraController: SpaceOutfitCameraController
    
    func makeUIView(context: Context) -> SpaceOutfitARContainerView {
        let containerView = SpaceOutfitARContainerView(frame: .zero)
        containerView.setup(objects: objects, cameraController: cameraController)
        return containerView
    }
    
    func updateUIView(_ uiView: SpaceOutfitARContainerView, context: Context) {}
}

// MARK: - AR Container View with Gesture Support

class SpaceOutfitARContainerView: UIView {
    private var arView: ARView?
    private var cameraController: SpaceOutfitCameraController?
    
    // 手势状态
    private var lastRotationLocation: CGPoint?
    private var lastPanLocation: CGPoint?
    private var lastPinchScale: CGFloat = 1.0
    private var activeGesture: UIGestureRecognizer?
    
    private var cancellables = Set<AnyCancellable>()
    
    func setup(objects: [SceneObject], cameraController: SpaceOutfitCameraController) {
        self.cameraController = cameraController
        
        // 创建 ARView
        let arView = ARView(frame: bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(arView)
        self.arView = arView
        
        // 设置背景色
        arView.environment.background = .color(UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0))
        
        // 加载场景对象
        loadObjects(objects: objects, into: arView)
        
        // 设置相机
        setupCamera()
        
        // 设置手势
        setupGestures()
        
        // 监听 CameraController 的变化
        cameraController.$distance
            .sink { [weak self] _ in self?.updateCamera() }
            .store(in: &cancellables)
        cameraController.$rotationX
            .sink { [weak self] _ in self?.updateCamera() }
            .store(in: &cancellables)
        cameraController.$rotationY
            .sink { [weak self] _ in self?.updateCamera() }
            .store(in: &cancellables)
        cameraController.$target
            .sink { [weak self] _ in self?.updateCamera() }
            .store(in: &cancellables)
        
        // 监听截图请求
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenshotRequest(_:)),
            name: Notification.Name("SpaceOutfitARViewCaptureRequest"),
            object: nil
        )
    }
    
    private func loadObjects(objects: [SceneObject], into arView: ARView) {
        Task {
            for object in objects {
                if let entity = try? await loadEntity(for: object) {
                    await MainActor.run {
                        let anchor = AnchorEntity(world: object.position)
                        anchor.addChild(entity)
                        arView.scene.addAnchor(anchor)
                    }
                }
            }
        }
    }
    
    private func loadEntity(for object: SceneObject) async throws -> Entity? {
        switch object.type {
        case .usdzModel:
            guard let path = object.usdzModelPath else { return nil }
            let url = URL(fileURLWithPath: path)
            let entity = try await Entity.load(contentsOf: url)
            applyTransform(to: entity, from: object)
            return entity
            
        case .primitive:
            let entity = ModelEntity(mesh: .generateBox(size: 0.3))
            var material = SimpleMaterial()
            material.color = SimpleMaterial.BaseColor(tint: UIColor(
                red: CGFloat(object.color.x),
                green: CGFloat(object.color.y),
                blue: CGFloat(object.color.z),
                alpha: CGFloat(object.color.w)
            ))
            entity.model?.materials = [material]
            applyTransform(to: entity, from: object)
            return entity
        }
    }
    
    private func applyTransform(to entity: Entity, from object: SceneObject) {
        entity.position = object.position
        
        let rotation = simd_quatf(
            angle: object.rotation.y,
            axis: [0, 1, 0]
        ) * simd_quatf(
            angle: object.rotation.x,
            axis: [1, 0, 0]
        ) * simd_quatf(
            angle: object.rotation.z,
            axis: [0, 0, 1]
        )
        entity.orientation = rotation
        
        entity.scale = object.scale
    }
    
    private func setupCamera() {
        guard let arView = arView else { return }
        
        let camera = PerspectiveCamera()
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)
        
        updateCamera()
    }
    
    func updateCamera() {
        guard let arView = arView, let controller = cameraController else { return }
        
        let distance = controller.distance
        let rotationX = controller.rotationX
        let rotationY = controller.rotationY
        let target = controller.target
        
        let cosPitch = cos(rotationX)
        let sinPitch = sin(rotationX)
        let cosYaw = cos(rotationY)
        let sinYaw = sin(rotationY)
        
        let position = SIMD3<Float>(
            target.x + distance * cosPitch * sinYaw,
            target.y + distance * sinPitch,
            target.z + distance * cosPitch * cosYaw
        )
        
        if let cameraAnchor = arView.scene.anchors.first(where: { $0.children.contains(where: { $0 is PerspectiveCamera }) }) {
            cameraAnchor.position = position
            cameraAnchor.look(at: target, from: position, relativeTo: nil)
        }
    }
    
    /// 处理截图请求
    @objc private func handleScreenshotRequest(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let completion = userInfo["completion"] as? (UIImage?) -> Void,
              let arView = arView else {
            return
        }
        
        // 使用 ARView 的 snapshot 方法捕获截图
        arView.snapshot(saveToHDR: false) { image in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
    
    private func setupGestures() {
        // 单指旋转 - 不需要等待双指失败，立即响应
        let singlePanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSinglePan(_:)))
        singlePanGesture.maximumNumberOfTouches = 1
        singlePanGesture.delegate = self
        singlePanGesture.name = "singlePan"
        addGestureRecognizer(singlePanGesture)
        
        // 双指平移
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = self
        panGesture.name = "doublePan"
        addGestureRecognizer(panGesture)
        
        // 双指缩放
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        pinchGesture.name = "pinch"
        addGestureRecognizer(pinchGesture)
        
        // 移除互斥要求，让手势立即响应
        // 通过 gestureRecognizerShouldBegin 来控制互斥
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let controller = cameraController else { return }
        
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            activeGesture = gesture
            lastPanLocation = location
        case .changed:
            // 检查是否仍然是活动手势
            guard activeGesture === gesture else { return }
            guard gesture.numberOfTouches == 2 else {
                lastPanLocation = nil
                return
            }
            guard let lastLocation = lastPanLocation else { return }
            let deltaX = Float(location.x - lastLocation.x)
            let deltaY = Float(location.y - lastLocation.y)
            controller.pan(deltaX: deltaX, deltaY: deltaY)
            lastPanLocation = location
        case .ended, .cancelled:
            if activeGesture === gesture {
                activeGesture = nil
            }
            lastPanLocation = nil
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let controller = cameraController else { return }
        
        switch gesture.state {
        case .began:
            activeGesture = gesture
            lastPinchScale = gesture.scale
        case .changed:
            guard activeGesture === gesture else { return }
            let scale = Float(gesture.scale / lastPinchScale)
            let zoomDelta = (1.0 - scale) * controller.distance * 2
            controller.zoom(delta: zoomDelta)
            lastPinchScale = gesture.scale
        case .ended, .cancelled:
            if activeGesture === gesture {
                activeGesture = nil
            }
            lastPinchScale = 1.0
        default:
            break
        }
    }
    
    @objc private func handleSinglePan(_ gesture: UIPanGestureRecognizer) {
        guard let controller = cameraController else { return }
        
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            activeGesture = gesture
            lastRotationLocation = location
        case .changed:
            // 检查是否仍然是活动手势
            guard activeGesture === gesture else { return }
            guard let lastLocation = lastRotationLocation else { return }
            let deltaX = Float(location.x - lastLocation.x) * 0.01
            let deltaY = Float(location.y - lastLocation.y) * 0.01
            controller.rotate(deltaX: deltaX, deltaY: deltaY)
            lastRotationLocation = location
        case .ended, .cancelled:
            if activeGesture === gesture {
                activeGesture = nil
            }
            lastRotationLocation = nil
        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SpaceOutfitARContainerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 只允许双指平移和缩放同时识别
        let isDoublePan = gestureRecognizer.name == "doublePan"
        let isPinch = gestureRecognizer.name == "pinch"
        let otherIsDoublePan = otherGestureRecognizer.name == "doublePan"
        let otherIsPinch = otherGestureRecognizer.name == "pinch"
        
        // 双指平移和缩放可以同时识别
        if (isDoublePan && otherIsPinch) || (isPinch && otherIsDoublePan) {
            return true
        }
        
        // 其他所有手势都不允许同时识别（单指旋转和双指平移互斥）
        return false
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 如果有其他手势正在进行，阻止新手势开始
        if let active = activeGesture, active !== gestureRecognizer {
            return false
        }
        return true
    }
}

// MARK: - Preview

#Preview {
    SpaceOutfitThumbnailEditorView(page: SpaceOutfit(note: "测试页面"))
}
