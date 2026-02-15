//
//  SpatialCanvasEditorView.swift
//  ItemManager
//
//  空间画布编辑器 - 支持3D高斯泼溅建模
//

import SwiftUI
import SwiftData
import PhotosUI
import SceneKit
import ARKit
import CoreMotion
import Combine

// MARK: - 主编辑器视图

struct SpatialCanvasEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var spaceOutfit: SpaceOutfit?
    var onSave: ((SpaceOutfit) -> Void)?
    
    // MARK: - State
    
    // 3D场景状态
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var modelNode: SCNNode?
    @State private var gizmoNode: SCNNode? // 变换辅助器
    
    // 选中的3D对象
    @State private var selectedObject: SpatialObject?
    @State private var spatialObjects: [SpatialObject] = []
    
    // 工具栏状态
    @State private var selectedTool: CanvasTool = .select
    @State private var showingToolPanel = false
    
    // 图片采集状态
    @State private var showingImagePicker = false
    @State private var showingCameraCapture = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImages: [UIImage] = []
    
    // 高斯泼溅建模状态
    @State private var isProcessing3DGS = false
    @State private var processingStage: GSProcessingStage = .idle
    @State private var processingProgress: Double = 0.0
    @State private var gsModelPath: String?
    
    // 右侧素材面板
    @State private var showingAssetPanel = true
    @State private var selectedAssetCategory: AssetCategory = .clothing
    
    // 底部操作栏状态
    @State private var showingBottomControls = false
    
    // 变换状态
    @State private var transformMode: TransformMode = .rotate
    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0
    @State private var rotationZ: Double = 0
    @State private var scale: Double = 1.0
    
    // 相机位姿追踪
    @StateObject private var cameraTracker = CameraPoseTracker()

    // 加载状态
    @State private var isSceneReady = false

    // 莫妮卡米白色
    private let monicaBeige = Color(red: 0.96, green: 0.95, blue: 0.93)

    var body: some View {
        ZStack {
            // 背景 - 莫妮卡米白色
            monicaBeige.ignoresSafeArea()

            // 3D场景视图
            GeometryReader { geometry in
                SpatialSceneView(
                    scene: scene,
                    cameraNode: cameraNode,
                    selectedObject: $selectedObject,
                    onObjectTap: handleObjectTap
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(isSceneReady ? 1 : 0)
            }
            .ignoresSafeArea()

            // 加载指示器
            if !isSceneReady {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("加载3D场景中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(monicaBeige)
            }
            
            // 变换辅助器 (Gizmo)
            if selectedObject != nil {
                TransformGizmoOverlay(
                    mode: transformMode,
                    rotationX: $rotationX,
                    rotationY: $rotationY,
                    rotationZ: $rotationZ,
                    scale: $scale,
                    onTransformChange: applyTransform
                )
            }
            
            // 左侧工具栏
            VStack {
                Spacer()
                CanvasToolbar(
                    selectedTool: $selectedTool,
                    onToolTap: handleToolTap
                )
                .padding(.leading, 16)
                .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            
            // 右侧素材面板
            if showingAssetPanel {
                AssetPanel(
                    selectedCategory: $selectedAssetCategory,
                    onAssetSelect: handleAssetSelect
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
            }

            // 底部操作栏
            VStack {
                Spacer()
                
                if selectedObject != nil {
                    BottomControlBar(
                        transformMode: $transformMode,
                        onRotate: { transformMode = .rotate },
                        onScale: { transformMode = .scale },
                        onDelete: { deleteSelectedObject() }
                    )
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom))
                }
            }
            
            // 3DGS处理进度遮罩
            if isProcessing3DGS {
                GSProcessingOverlay(
                    stage: processingStage,
                    progress: processingProgress
                )
            }
        }
        .onAppear {
            setupScene()
            loadExistingData()

            // 使用多次延迟确保 SceneKit 完全准备好
            DispatchQueue.main.async {
                // 强制场景渲染更新
                self.scene.background.contents = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0)

                // 延迟显示，给 SceneKit 足够时间初始化
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        isSceneReady = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            MultiImagePicker(
                selectedItems: $selectedPhotoItems,
                onComplete: handleSelectedImages
            )
        }
        .sheet(isPresented: $showingCameraCapture) {
            ContinuousCameraCaptureView(
                capturedImages: $capturedImages,
                onComplete: handleCapturedImages
            )
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        saveScene()
                    } label: {
                        Label("保存", systemImage: "checkmark.circle")
                    }

                    Button {
                        // 导出功能
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        // 清空场景
                    } label: {
                        Label("清空场景", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Scene Setup
    
    private func setupScene() {
        // 设置场景背景色 - 莫妮卡米白色
        scene.background.contents = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0)
        
        // 设置相机
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 1.5, 5)
        scene.rootNode.addChildNode(cameraNode)
        
        // 添加环境光
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)
        
        // 添加方向光
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 1000
        directionalLight.position = SCNVector3(5, 10, 5)
        directionalLight.eulerAngles = SCNVector3(-Float.pi/3, 0, 0)
        scene.rootNode.addChildNode(directionalLight)
        
        // 添加网格地板
        addGridFloor()
    }
    
    private func addGridFloor() {
        let gridSize: CGFloat = 20
        let gridDivisions: Int = 20
        let gridSpacing = gridSize / CGFloat(gridDivisions)
        
        let floorNode = SCNNode()
        
        // 创建网格线
        for i in 0...gridDivisions {
            let x = -gridSize/2 + CGFloat(i) * gridSpacing
            
            // X方向线
            let lineX = SCNNode()
            let geometryX = SCNCylinder(radius: 0.005, height: gridSize)
            geometryX.firstMaterial?.diffuse.contents = UIColor.gray.withAlphaComponent(0.3)
            lineX.geometry = geometryX
            lineX.position = SCNVector3(x, 0, 0)
            lineX.rotation = SCNVector4(1, 0, 0, Float.pi/2)
            floorNode.addChildNode(lineX)
            
            // Z方向线
            let z = -gridSize/2 + CGFloat(i) * gridSpacing
            let lineZ = SCNNode()
            let geometryZ = SCNCylinder(radius: 0.005, height: gridSize)
            geometryZ.firstMaterial?.diffuse.contents = UIColor.gray.withAlphaComponent(0.3)
            lineZ.geometry = geometryZ
            lineZ.position = SCNVector3(0, 0, z)
            lineZ.rotation = SCNVector4(0, 0, 1, Float.pi/2)
            floorNode.addChildNode(lineZ)
        }
        
        scene.rootNode.addChildNode(floorNode)
    }
    
    // MARK: - Data Loading
    
    private func loadExistingData() {
        guard let outfit = spaceOutfit else { return }
        
        // 加载3D模型
        if let modelPath = outfit.modelPath {
            load3DModel(from: modelPath)
        }
        
        // 恢复相机位置
        cameraNode.position = SCNVector3(outfit.camPosX, outfit.camPosY, outfit.camPosZ)
    }
    
    // MARK: - Tool Handlers
    
    private func handleToolTap(_ tool: CanvasTool) {
        selectedTool = tool
        
        switch tool {
        case .select:
            showingAssetPanel = false
        case .image:
            showingImagePicker = true
        case .camera:
            showingCameraCapture = true
        case .gsModel:
            startGSCapture()
        case .light:
            adjustLighting()
        case .text:
            addTextObject()
        case .material:
            showingAssetPanel = true
            selectedAssetCategory = .material
        case .clothing:
            showingAssetPanel = true
            selectedAssetCategory = .clothing
        case .effect:
            showingAssetPanel = true
            selectedAssetCategory = .effect
        case .template:
            showingAssetPanel = true
            selectedAssetCategory = .template
        case .record:
            startRecording()
        case .settings:
            showSettings()
        }
    }
    
    // MARK: - 3D Gaussian Splatting
    
    private func startGSCapture() {
        // 显示采集选项
        showingCameraCapture = true
    }
    
    private func processGaussianSplatting(images: [UIImage]) {
        guard images.count >= 20 else {
            // 需要至少20张图片
            return
        }
        
        isProcessing3DGS = true
        processingStage = .uploading
        processingProgress = 0.0
        
        Task {
            // 阶段1: 上传图片
            await simulateProcessing(stage: .uploading, duration: 1.0)
            
            // 阶段2: SfM (Structure from Motion)
            processingStage = .sfm
            await simulateProcessing(stage: .sfm, duration: 2.0)
            
            // 阶段3: 训练高斯泼溅模型
            processingStage = .training
            await simulateProcessing(stage: .training, duration: 3.0)
            
            // 阶段4: 优化和导出
            processingStage = .optimizing
            await simulateProcessing(stage: .optimizing, duration: 1.5)
            
            // 完成
            await MainActor.run {
                processingStage = .complete
                isProcessing3DGS = false
                
                // 加载生成的模型
                loadGeneratedGSModel()
            }
        }
    }
    
    private func simulateProcessing(stage: GSProcessingStage, duration: Double) async {
        let steps = 20
        let stepDuration = duration / Double(steps)
        
        for i in 0..<steps {
            await MainActor.run {
                processingProgress = Double(i) / Double(steps)
            }
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
        }
    }
    
    private func loadGeneratedGSModel() {
        // 这里加载生成的PLY/SPLAT文件
        // 实际实现需要使用Metal渲染器
        let placeholderNode = createPlaceholderGSNode()
        scene.rootNode.addChildNode(placeholderNode)
        
        let object = SpatialObject(
            id: UUID(),
            type: .gsModel,
            node: placeholderNode,
            position: SCNVector3(0, 1, 0),
            rotation: SCNVector3(0, 0, 0),
            scale: SCNVector3(1, 1, 1)
        )
        spatialObjects.append(object)
    }
    
    private func createPlaceholderGSNode() -> SCNNode {
        // 创建高斯泼溅占位模型
        let node = SCNNode()
        
        // 主体
        let sphere = SCNSphere(radius: 0.5)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemPink.withAlphaComponent(0.6)
        sphere.firstMaterial?.isDoubleSided = true
        
        let sphereNode = SCNNode(geometry: sphere)
        node.addChildNode(sphereNode)
        
        // 添加粒子效果表示高斯点
        let particleSystem = SCNParticleSystem()
        particleSystem.birthRate = 1000
        particleSystem.particleLifeSpan = 2.0
        particleSystem.particleSize = 0.02
        particleSystem.particleColor = UIColor.white.withAlphaComponent(0.5)
        particleSystem.emitterShape = sphere
        particleSystem.birthLocation = .surface
        
        node.addParticleSystem(particleSystem)
        
        return node
    }
    
    // MARK: - Image Handling
    
    private func handleSelectedImages() {
        Task {
            var images: [UIImage] = []
            for item in selectedPhotoItems {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            
            if images.count >= 20 {
                // 足够图片进行3DGS建模
                processGaussianSplatting(images: images)
            } else {
                // 添加为普通图片对象
                await MainActor.run {
                    for image in images {
                        addImageObject(image: image)
                    }
                }
            }
        }
    }
    
    private func handleCapturedImages() {
        if capturedImages.count >= 20 {
            processGaussianSplatting(images: capturedImages)
        } else {
            for image in capturedImages {
                addImageObject(image: image)
            }
        }
        capturedImages = []
    }
    
    private func addImageObject(image: UIImage) {
        // 保存图片到沙盒
        if let path = ImageManager.shared.saveImage(image, context: modelContext) {
            let plane = SCNPlane(width: 1, height: 1)
            plane.firstMaterial?.diffuse.contents = image
            plane.firstMaterial?.isDoubleSided = true
            
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, 1, 0)
            scene.rootNode.addChildNode(node)
            
            let object = SpatialObject(
                id: UUID(),
                type: .image,
                node: node,
                imagePath: path,
                position: node.position,
                rotation: SCNVector3(0, 0, 0),
                scale: SCNVector3(1, 1, 1)
            )
            spatialObjects.append(object)
        }
    }
    
    // MARK: - Object Management
    
    private func handleObjectTap(_ object: SpatialObject) {
        selectedObject = object
        showingBottomControls = true
        
        // 更新变换状态
        rotationX = Double(object.rotation.x)
        rotationY = Double(object.rotation.y)
        rotationZ = Double(object.rotation.z)
        scale = Double(object.scale.x)
    }
    
    private func handleAssetSelect(_ asset: SpatialAsset) {
        switch asset.type {
        case .clothing:
            addClothingAsset(asset)
        case .material:
            addMaterialAsset(asset)
        case .effect:
            addEffectAsset(asset)
        case .template:
            applyTemplate(asset)
        }
    }
    
    private func addClothingAsset(_ asset: SpatialAsset) {
        // 从抠图添加服饰
        if let cutoutPath = asset.imagePath,
           let image = ImageManager.shared.loadImage(fileName: cutoutPath) {
            addImageObject(image: image)
        }
    }
    
    private func applyTransform() {
        guard let object = selectedObject else { return }
        
        let node = object.node
        
        switch transformMode {
        case .rotate:
            node.eulerAngles = SCNVector3(
                Float(rotationX * .pi / 180),
                Float(rotationY * .pi / 180),
                Float(rotationZ * .pi / 180)
            )
        case .scale:
            node.scale = SCNVector3(Float(scale), Float(scale), Float(scale))
        }
        
        // 更新对象状态
        object.rotation = node.eulerAngles
        object.scale = node.scale
    }
    
    private func deleteSelectedObject() {
        guard let object = selectedObject else { return }
        
        object.node.removeFromParentNode()
        spatialObjects.removeAll { $0.id == object.id }
        selectedObject = nil
        showingBottomControls = false
    }
    
    // MARK: - Save & Export
    
    private func saveScene() {
        // 保存相机位置
        let outfit = spaceOutfit ?? SpaceOutfit(note: "空间穿搭")
        outfit.camPosX = Double(cameraNode.position.x)
        outfit.camPosY = Double(cameraNode.position.y)
        outfit.camPosZ = Double(cameraNode.position.z)
        
        if spaceOutfit == nil {
            modelContext.insert(outfit)
        }
        
        try? modelContext.save()
        onSave?(outfit)
        dismiss()
    }
    
    // MARK: - Placeholder Methods
    
    private func load3DModel(from path: String) {
        // 实现3D模型加载
    }
    
    private func adjustLighting() {}
    private func addTextObject() {}
    private func addMaterialAsset(_ asset: SpatialAsset) {}
    private func addEffectAsset(_ asset: SpatialAsset) {}
    private func applyTemplate(_ asset: SpatialAsset) {}
    private func startRecording() {}
    private func showSettings() {}
}

// MARK: - Supporting Types

enum CanvasTool: String, CaseIterable {
    case select = "选择"
    case image = "图片"
    case camera = "拍照"
    case gsModel = "3D建模"
    case light = "灯光"
    case text = "文本"
    case material = "素材"
    case clothing = "服饰"
    case effect = "特效"
    case template = "模版"
    case record = "记录"
    case settings = "设置"
    
    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .image: return "photo"
        case .camera: return "camera.fill"
        case .gsModel: return "cube.transparent"
        case .light: return "light.max"
        case .text: return "textformat"
        case .material: return "circle.fill"
        case .clothing: return "tshirt"
        case .effect: return "sparkles"
        case .template: return "square.grid.2x2"
        case .record: return "video.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .select: return .gray
        case .image: return .green
        case .camera: return .orange
        case .gsModel: return .purple
        case .light: return .yellow
        case .text: return .blue
        case .material: return .purple
        case .clothing: return .orange
        case .effect: return .pink
        case .template: return .cyan
        case .record: return .red
        case .settings: return .gray
        }
    }
}

enum TransformMode {
    case rotate, scale
}

enum GSProcessingStage: String {
    case idle = "准备中"
    case uploading = "上传图片"
    case sfm = "计算点云 (SfM)"
    case training = "训练高斯泼溅模型"
    case optimizing = "优化模型"
    case complete = "完成"
    
    var description: String {
        return rawValue
    }
}

enum AssetCategory: String, CaseIterable {
    case clothing = "服饰"
    case effect = "特效"
    case template = "模版"
    case material = "素材"
}

// MARK: - Spatial Object Model

class SpatialObject: Identifiable, ObservableObject {
    let id: UUID
    let type: ObjectType
    let node: SCNNode
    var imagePath: String?
    
    @Published var positionX: Double = 0
    @Published var positionY: Double = 0
    @Published var positionZ: Double = 0
    @Published var rotationX: Double = 0
    @Published var rotationY: Double = 0
    @Published var rotationZ: Double = 0
    @Published var scaleX: Double = 1
    @Published var scaleY: Double = 1
    @Published var scaleZ: Double = 1
    
    var position: SCNVector3 {
        get { SCNVector3(positionX, positionY, positionZ) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
            positionZ = Double(newValue.z)
        }
    }
    
    var rotation: SCNVector3 {
        get { SCNVector3(rotationX, rotationY, rotationZ) }
        set {
            rotationX = Double(newValue.x)
            rotationY = Double(newValue.y)
            rotationZ = Double(newValue.z)
        }
    }
    
    var scale: SCNVector3 {
        get { SCNVector3(scaleX, scaleY, scaleZ) }
        set {
            scaleX = Double(newValue.x)
            scaleY = Double(newValue.y)
            scaleZ = Double(newValue.z)
        }
    }
    
    enum ObjectType {
        case gsModel, image, text, clothing, effect
    }
    
    init(id: UUID, type: ObjectType, node: SCNNode, imagePath: String? = nil,
         position: SCNVector3, rotation: SCNVector3, scale: SCNVector3) {
        self.id = id
        self.type = type
        self.node = node
        self.imagePath = imagePath
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

struct SpatialAsset: Identifiable {
    let id = UUID()
    let type: AssetType
    let name: String
    let imagePath: String?
    let thumbnail: UIImage?
    let metadata: [String: Any]?
    
    enum AssetType {
        case clothing, material, effect, template
    }
}
