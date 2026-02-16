//
//  SpatialCanvasEditorView.swift
//  ItemManager
//
//  空间画布编辑器 - 支持 Object Capture 3D建模 (RealityKit版)
//

import SwiftUI
import SwiftData
import PhotosUI
import RealityKit
import ARKit
import simd
import Combine

// MARK: - 主编辑器视图

struct SpatialCanvasEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var spaceOutfit: SpaceOutfit?
    var onSave: ((SpaceOutfit) -> Void)?
    
    // MARK: - State
    
    // 当前编辑的 SpaceOutfit（用于新建场景时）
    @State private var currentOutfit: SpaceOutfit?
    
    // 3D场景状态 - 使用新的 Metal SceneObject
    @State private var sceneObjects: [SceneObject] = []
    @State private var selectedObject: SceneObject?
    
    // 工具栏状态
    @State private var selectedTool: CanvasTool = .select
    @State private var showingToolPanel = false
    
    // 图片采集状态
    @State private var showingImagePicker = false
    @State private var showingCameraCapture = false
    @State private var showingObjectCaptureScanner = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var capturedImages: [UIImage] = []
    
    // Object Capture 建模状态
    @State private var isProcessing3DGS = false
    @State private var processingStage: GSProcessingStage = .idle
    
    // 返回确认
    @State private var showingBackConfirmation = false
    @State private var showingClearConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var processingProgress: Double = 0.0
    
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
    
    // 加载状态
    @State private var isSceneReady = false

    // 背景色 - 根据暗黑模式调整
    private var editorBackground: Color {
        colorScheme == .dark 
            ? Color(red: 0.15, green: 0.15, blue: 0.15) 
            : Color(red: 0.96, green: 0.95, blue: 0.93)
    }

    var body: some View {
        ZStack {
            // 背景 - 根据暗黑模式调整
            editorBackground.ignoresSafeArea()

            // 3D场景视图 - 使用 RealityKit
            GeometryReader { geometry in
                RealityKitSceneView(
                    selectedObject: $selectedObject,
                    objects: $sceneObjects,
                    onObjectTap: handleObjectTap,
                    onObjectTransform: handleObjectTransform
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
                .background(editorBackground)
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
                .padding(.leading, 8)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .ignoresSafeArea(edges: .vertical)
            .allowsHitTesting(true)

            // 右侧素材面板
            if showingAssetPanel {
                AssetPanel(
                    selectedCategory: $selectedAssetCategory,
                    onAssetSelect: handleAssetSelect
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .transition(.move(edge: .trailing))
                .allowsHitTesting(true)
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
                    progress: processingProgress,
                    onDismiss: {
                        if case .failed = processingStage {
                            isProcessing3DGS = false
                            processingStage = .idle
                        }
                    }
                )
            }
        }
        .onAppear {
            loadExistingData()
            
            // 延迟显示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.2)) {
                    isSceneReady = true
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            MultiImagePicker(
                selectedItems: $selectedPhotoItems,
                onComplete: {
                    // 从 PhotosPickerItem 异步加载图片
                    loadImagesFromPickerItems(selectedPhotoItems)
                }
            )
        }
        .sheet(isPresented: $showingCameraCapture) {
            ContinuousCameraCaptureView(
                capturedImages: $capturedImages,
                onComplete: {
                    handleCapturedImages(capturedImages)
                }
            )
        }
        .fullScreenCover(isPresented: $showingObjectCaptureScanner) {
            ObjectCaptureScannerView { imageDirectory in
                processObjectCaptureDirectory(imageDirectory)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasUnsavedChanges {
                        showingBackConfirmation = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .foregroundStyle(.primary)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // 保存按钮
                    Button {
                        saveScene()
                    } label: {
                        Label("保存", systemImage: "checkmark.circle")
                            .symbolVariant(hasUnsavedChanges ? .none : .fill)
                    }
                    .foregroundStyle(hasUnsavedChanges ? .purple : .secondary)
                    .disabled(!hasUnsavedChanges)
                    
                    // 清空场景按钮
                    Button {
                        showingClearConfirmation = true
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                    .disabled(sceneObjects.isEmpty)
                    
                    // 更多选项菜单
                    Menu {
                        Button {
                            saveScene()
                        } label: {
                            Label("保存场景", systemImage: "checkmark.circle")
                        }
                        .disabled(!hasUnsavedChanges)

                        Button {
                            showingClearConfirmation = true
                        } label: {
                            Label("清空场景", systemImage: "trash")
                        }
                        .disabled(sceneObjects.isEmpty)

                        Divider()

                        Button {
                            // 导出功能
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .confirmationDialog("确认返回？", isPresented: $showingBackConfirmation, titleVisibility: .visible) {
            Button("保存并返回", role: .none) {
                saveScene()
                hasUnsavedChanges = false
                dismiss()
            }
            Button("不保存返回", role: .destructive) {
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("您有未保存的更改，是否保存？")
        }
        .confirmationDialog("清空场景？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                sceneObjects.removeAll()
                selectedObject = nil
                hasUnsavedChanges = true
                print("[Scene] 场景已清空（未保存）")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要清空场景中的所有模型吗？此操作不会删除已保存的数据。")
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    // MARK: - Data Loading
    
    private func loadExistingData() {
        guard let outfit = spaceOutfit else { return }
        let outfitId = outfit.id
        
        // 从 SceneObjectData 加载所有场景对象
        if let objectDataList = try? modelContext.fetch(
            FetchDescriptor<SceneObjectData>(
                predicate: #Predicate<SceneObjectData> { $0.spaceOutfit?.id == outfitId },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        ) {
            // 清空当前场景
            sceneObjects.removeAll()
            
            // 加载保存的对象
            for objectData in objectDataList {
                let object = objectData.toSceneObject()
                sceneObjects.append(object)
            }
            
            print("[Scene] 加载了 \(objectDataList.count) 个对象")
        }
    }
    
    private func loadUSDZModel(from path: String) {
        let object = SceneObject(
            type: .usdzModel,
            position: SIMD3<Float>(0, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1),
            usdzModelPath: path
        )
        sceneObjects.append(object)
    }
    
    // MARK: - Event Handlers
    
    private func handleObjectTap(_ object: SceneObject) {
        selectedObject = object
        hasUnsavedChanges = true
        
        // 更新变换状态
        rotationX = Double(object.rotation.x)
        rotationY = Double(object.rotation.y)
        rotationZ = Double(object.rotation.z)
        scale = Double(object.scale.x)
    }
    
    private func handleObjectTransform(_ object: SceneObject) {
        hasUnsavedChanges = true
    }
    
    private func handleToolTap(_ tool: CanvasTool) {
        selectedTool = tool
        
        switch tool {
        case .select:
            break
        case .image:
            showingImagePicker = true
        case .gallery:
            showingImagePicker = true
        case .camera:
            showingObjectCaptureScanner = true
        case .usdzModel:
            showingImagePicker = true
        case .light:
            break
        case .text:
            break
        case .material:
            break
        case .clothing:
            showingAssetPanel = true
        case .effect:
            break
        case .template:
            break
        case .transform:
            showingToolPanel = true
        case .record:
            // TODO: 开始录制
            break
        case .settings:
            // TODO: 打开设置
            break
        }
    }
    
    private func handleAssetSelect(_ asset: SpatialAsset) {
        hasUnsavedChanges = true
        
        switch asset.type {
        case .clothing:
            if let modelPath = asset.metadata["modelPath"] {
                loadUSDZModel(from: modelPath)
            }
        case .effect:
            print("[Asset] 选择特效: \(asset.name)")
        case .template:
            print("[Asset] 选择模板: \(asset.name)")
        case .material:
            print("[Asset] 选择材质: \(asset.name)")
        }
    }
    
    private func handleSelectedImages(_ images: [UIImage]) {
        // 处理选中的图片
        capturedImages = images
        start3DGSProcessing()
    }
    
    private func handleCapturedImages(_ images: [UIImage]) {
        // 处理拍摄的图片
        capturedImages = images
        start3DGSProcessing()
    }
    
    /// 从 PhotosPickerItem 异步加载图片
    private func loadImagesFromPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        
        isProcessing3DGS = true
        processingStage = .preparing
        processingProgress = 0.0
        
        Task {
            var loadedImages: [UIImage] = []
            
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loadedImages.append(image)
                }
                
                // 更新进度
                await MainActor.run {
                    processingProgress = Double(index + 1) / Double(items.count) * 0.3
                }
            }
            
            await MainActor.run {
                capturedImages = loadedImages
                start3DGSProcessing()
            }
        }
    }
    
    // MARK: - Object Capture Processing
    
    private func start3DGSProcessing() {
        guard !capturedImages.isEmpty else { return }
        
        isProcessing3DGS = true
        processingStage = .preparing
        processingProgress = 0.0
        
        Task {
            do {
                let usdzURL = try await ObjectCaptureService.shared.processImagesWithFallback(capturedImages)
                
                await MainActor.run {
                    processingStage = .complete
                    processingProgress = 1.0
                    isProcessing3DGS = false
                    
                    saveUSDZModelAndCreateClothing(usdzURL: usdzURL, images: capturedImages)
                }
            } catch {
                await MainActor.run {
                    processingStage = .failed(error.localizedDescription)
                    isProcessing3DGS = false
                    print("[ObjectCapture] 处理失败: \(error)")
                }
            }
        }
    }
    
    private func processObjectCaptureDirectory(_ imageDirectory: URL) {
        isProcessing3DGS = true
        processingStage = .processing
        processingProgress = 0.0
        
        Task {
            do {
                let usdzURL = try await ObjectCaptureService.shared.processImagesFromDirectory(imageDirectory)
                
                await MainActor.run {
                    processingStage = .complete
                    processingProgress = 1.0
                    isProcessing3DGS = false
                    
                    let object = SceneObject(
                        type: .usdzModel,
                        position: SIMD3<Float>(0, 0, 0),
                        rotation: SIMD3<Float>(0, 0, 0),
                        scale: SIMD3<Float>(1, 1, 1),
                        usdzModelPath: usdzURL.path
                    )
                    sceneObjects.append(object)
                    hasUnsavedChanges = true
                    
                    print("[ObjectCapture] 模型已添加到场景: \(usdzURL.path)")
                }
            } catch {
                await MainActor.run {
                    processingStage = .failed(error.localizedDescription)
                    isProcessing3DGS = false
                    print("[ObjectCapture] 处理失败: \(error)")
                }
            }
        }
    }
    
    private func saveUSDZModelAndCreateClothing(usdzURL: URL, images: [UIImage]) {
        let modelID = UUID()
        
        let thumbnailPath = saveThumbnail(from: images.first, modelID: modelID)
        
        let imagePaths = saveSourceImages(images, modelID: modelID)
        
        let clothing = Clothing(
            name: "3D模型 \(modelID.uuidString.prefix(8))",
            types: "3D模型",
            imagePaths: imagePaths,
            status: .onShelf
        )
        clothing.model3DPath = usdzURL.path
        clothing.model3DType = "usdz"
        clothing.model3DThumbnailPath = thumbnailPath
        
        modelContext.insert(clothing)
        
        let object = SceneObject(
            type: .usdzModel,
            position: SIMD3<Float>(0, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1),
            usdzModelPath: usdzURL.path
        )
        sceneObjects.append(object)
        
        hasUnsavedChanges = true
        
        print("[ObjectCapture] 创建3D模型记录: \(modelID)")
    }
    
    /// 保存缩略图
    private func saveThumbnail(from image: UIImage?, modelID: UUID) -> String? {
        guard let image = image else { return nil }
        
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let modelDir = documentsPath.appendingPathComponent("Models/\(modelID.uuidString)")
        try? fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        // 压缩缩略图
        let thumbnailSize = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let thumbnail = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
        
        let thumbnailPath = modelDir.appendingPathComponent("thumbnail.jpg")
        if let data = thumbnail.jpegData(compressionQuality: 0.8) {
            try? data.write(to: thumbnailPath)
            return thumbnailPath.path
        }
        
        return nil
    }
    
    /// 保存源图片
    private func saveSourceImages(_ images: [UIImage], modelID: UUID) -> [String] {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let modelDir = documentsPath.appendingPathComponent("Models/\(modelID.uuidString)/source")
        try? fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        var paths: [String] = []
        for (index, image) in images.enumerated() {
            let imagePath = modelDir.appendingPathComponent("image_\(index).jpg")
            if let data = image.jpegData(compressionQuality: 0.9) {
                try? data.write(to: imagePath)
                paths.append(imagePath.path)
            }
        }
        
        return paths
    }
    
    // MARK: - Transform
    
    private func applyTransform() {
        guard let index = sceneObjects.firstIndex(where: { $0.id == selectedObject?.id }) else { return }
        
        sceneObjects[index].rotation = SIMD3<Float>(
            Float(rotationX),
            Float(rotationY),
            Float(rotationZ)
        )
        sceneObjects[index].scale = SIMD3<Float>(
            Float(scale),
            Float(scale),
            Float(scale)
        )
        
        selectedObject = sceneObjects[index]
        hasUnsavedChanges = true
    }
    
    private func deleteSelectedObject() {
        guard let object = selectedObject,
              let index = sceneObjects.firstIndex(where: { $0.id == object.id }) else { return }
        
        sceneObjects.remove(at: index)
        selectedObject = nil
        hasUnsavedChanges = true
    }
    
    // MARK: - Save
    
    private func saveScene() {
        guard !sceneObjects.isEmpty else {
            print("[Scene] 场景为空，无需保存")
            return
        }
        
        // 获取或创建 SpaceOutfit
        let outfit: SpaceOutfit
        if let existingOutfit = spaceOutfit {
            outfit = existingOutfit
        } else if let current = currentOutfit {
            outfit = current
        } else {
            outfit = SpaceOutfit(note: "3D场景 \(Date().formatted(date: .abbreviated, time: .shortened))")
            modelContext.insert(outfit)
            currentOutfit = outfit
        }
        
        // 删除旧的场景对象数据
        let outfitId = outfit.id
        if let existingObjects = try? modelContext.fetch(
            FetchDescriptor<SceneObjectData>(
                predicate: #Predicate<SceneObjectData> { $0.spaceOutfit?.id == outfitId }
            )
        ) {
            for obj in existingObjects {
                modelContext.delete(obj)
            }
        }
        
        // 保存新的场景对象
        for (index, object) in sceneObjects.enumerated() {
            let objectData = SceneObjectData(
                id: object.id,
                objectType: object.type == .primitive ? "primitive" : "usdzModel",
                position: object.position,
                rotation: object.rotation,
                scale: object.scale,
                usdzModelPath: object.usdzModelPath,
                color: object.color,
                sortIndex: index,
                spaceOutfit: outfit
            )
            modelContext.insert(objectData)
        }
        
        // 保存第一个模型的路径到 SpaceOutfit
        if let firstObject = sceneObjects.first,
           let modelPath = firstObject.usdzModelPath {
            outfit.modelPath = modelPath
        }
        
        // 保存上下文
        do {
            try modelContext.save()
            hasUnsavedChanges = false
            print("[Scene] 场景保存成功，共 \(sceneObjects.count) 个对象")
        } catch {
            print("[Scene] 保存失败: \(error)")
        }
        
        // 调用保存回调
        onSave?(outfit)
    }
}

// MARK: - 辅助类型



struct AssetItem {
    let id: String
    let name: String
    let category: AssetCategory
}

// MARK: - 占位视图组件




