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
    var currentBook: SpaceBookGroup?  // 当前书，用于新建页面时关联
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
    
    // 保存成功提示
    @State private var showingSaveSuccess = false
    
    // 右侧素材面板
    @State private var showingAssetPanel = false
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
    
    // 相机控制器
    @State private var cameraController: CameraController?

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
                    onObjectTransform: handleObjectTransform,
                    onCameraControllerReady: { controller in
                        cameraController = controller
                    }
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
                    onToolTap: handleToolTap,
                    onResetCamera: {
                        cameraController?.reset()
                    }
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
            
            // 清理旧的模型文件，释放磁盘空间
            Task {
                let sizeBefore = await ObjectCaptureService.shared.getModelsDirectorySize()
                await ObjectCaptureService.shared.cleanupOldModels(keepRecent: 10)
                let sizeAfter = await ObjectCaptureService.shared.getModelsDirectorySize()
                print("[SpatialCanvasEditorView] 磁盘空间清理完成: \(String(format: "%.1f", sizeBefore)) MB -> \(String(format: "%.1f", sizeAfter)) MB")
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
                // 先关闭扫描界面，再处理图像
                showingObjectCaptureScanner = false
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
        .alert("保存成功", isPresented: $showingSaveSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("场景已成功保存到数据库")
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    // MARK: - Data Loading
    
    private func loadExistingData() {
        guard let outfit = spaceOutfit else {
            print("[Scene] 没有现有的 spaceOutfit，无需加载")
            return
        }
        let outfitId = outfit.id
        print("[Scene] 开始加载现有数据，outfit.id: \(outfitId)")
        print("[Scene] outfit.modelPath (stored): \(outfit.modelPath ?? "nil")")
        print("[Scene] outfit.modelPath (resolved): \(outfit.resolvedModelPath ?? "nil")")
        
        // 从 SceneObjectData 加载所有场景对象
        do {
            let objectDataList = try modelContext.fetch(
                FetchDescriptor<SceneObjectData>(
                    predicate: #Predicate<SceneObjectData> { $0.spaceOutfit?.id == outfitId },
                    sortBy: [SortDescriptor(\.sortIndex)]
                )
            )
            
            print("[Scene] 从数据库获取到 \(objectDataList.count) 个对象")
            
            // 清空当前场景
            sceneObjects.removeAll()
            
            // 加载保存的对象
            for (index, objectData) in objectDataList.enumerated() {
                var object = objectData.toSceneObject()
                
                // 使用解析后的路径（支持相对路径）
                if let resolvedPath = objectData.resolvedModelPath {
                    object.usdzModelPath = resolvedPath
                    print("[Scene] 加载对象 \(index + 1): id=\(object.id), type=\(object.type)")
                    print("[Scene]   stored path: \(objectData.usdzModelPath ?? "nil")")
                    print("[Scene]   resolved path: \(resolvedPath)")
                } else {
                    print("[Scene] 加载对象 \(index + 1): id=\(object.id), type=\(object.type), path=nil")
                }
                
                sceneObjects.append(object)
            }
            
            print("[Scene] 成功加载了 \(objectDataList.count) 个对象到场景")
            
            // 验证模型文件是否存在
            if let firstObject = sceneObjects.first,
               let modelPath = firstObject.usdzModelPath {
                let fileExists = FileManager.default.fileExists(atPath: modelPath)
                print("[Scene] 模型文件是否存在: \(fileExists), 路径: \(modelPath)")
            }
        } catch {
            print("[Scene] 加载数据失败: \(error)")
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
        print("[SpatialCanvasEditorView] 开始处理扫描目录: \(imageDirectory.path)")
        
        isProcessing3DGS = true
        processingStage = .processing
        processingProgress = 0.0
        
        // 创建进度监听任务
        let progressTask = Task {
            while !Task.isCancelled {
                await MainActor.run {
                    self.processingProgress = ObjectCaptureService.shared.progress
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        
        Task {
            do {
                print("[SpatialCanvasEditorView] 调用 ObjectCaptureService 处理图像...")
                let usdzURL = try await ObjectCaptureService.shared.processImagesFromDirectory(imageDirectory)
                
                // 取消进度监听
                progressTask.cancel()
                
                await MainActor.run {
                    print("[SpatialCanvasEditorView] 处理完成，USDZ 路径: \(usdzURL.path)")
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
                    
                    print("[SpatialCanvasEditorView] 模型已添加到场景，当前对象数: \(sceneObjects.count)")
                    
                    // 自动保存场景
                    print("[SpatialCanvasEditorView] 自动保存场景...")
                    saveScene()
                }
            } catch let error as ObjectCaptureError {
                progressTask.cancel()
                await MainActor.run {
                    print("[SpatialCanvasEditorView] 处理失败: \(error)")
                    processingStage = .failed(error.localizedDescription)
                    isProcessing3DGS = false
                }
            } catch {
                progressTask.cancel()
                await MainActor.run {
                    print("[SpatialCanvasEditorView] 处理失败: \(error)")
                    processingStage = .failed("处理失败: \(error.localizedDescription)")
                    isProcessing3DGS = false
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
        // 使用相对路径存储
        clothing.setModel3DPath(usdzURL.path)
        clothing.model3DType = "usdz"
        clothing.model3DThumbnailPath = thumbnailPath
        
        modelContext.insert(clothing)
        
        // 保存上下文到数据库
        do {
            try modelContext.save()
            print("[ObjectCapture] Clothing 已保存到数据库: \(modelID)")
        } catch {
            print("[ObjectCapture] 保存 Clothing 失败: \(error)")
        }
        
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
    
    /// 保存缩略图，返回相对路径
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
        
        let thumbnailFileName = "thumbnail.jpg"
        let thumbnailPath = modelDir.appendingPathComponent(thumbnailFileName)
        if let data = thumbnail.jpegData(compressionQuality: 0.8) {
            try? data.write(to: thumbnailPath)
            // 返回相对路径
            return "Models/\(modelID.uuidString)/\(thumbnailFileName)"
        }
        
        return nil
    }
    
    /// 保存源图片，返回相对路径数组
    private func saveSourceImages(_ images: [UIImage], modelID: UUID) -> [String] {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let modelDir = documentsPath.appendingPathComponent("Models/\(modelID.uuidString)/source")
        try? fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        var paths: [String] = []
        for (index, image) in images.enumerated() {
            let imageFileName = "image_\(index).jpg"
            let imagePath = modelDir.appendingPathComponent(imageFileName)
            if let data = image.jpegData(compressionQuality: 0.9) {
                try? data.write(to: imagePath)
                // 返回相对路径
                paths.append("Models/\(modelID.uuidString)/source/\(imageFileName)")
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
        
        print("[Scene] 开始保存场景，对象数: \(sceneObjects.count)")
        
        // 获取或创建 SpaceOutfit
        let outfit: SpaceOutfit
        if let existingOutfit = spaceOutfit {
            outfit = existingOutfit
            print("[Scene] 使用现有的 SpaceOutfit: \(outfit.id)")
        } else if let current = currentOutfit {
            outfit = current
            print("[Scene] 使用当前的 SpaceOutfit: \(outfit.id)")
        } else {
            // 创建新的 SpaceOutfit，关联到当前书
            outfit = SpaceOutfit(
                note: "3D场景 \(Date().formatted(date: .abbreviated, time: .shortened))",
                book: currentBook
            )
            modelContext.insert(outfit)
            currentOutfit = outfit
            print("[Scene] 创建新的 SpaceOutfit: \(outfit.id), book: \(currentBook?.id.uuidString ?? "nil")")
        }
        
        // 删除旧的场景对象数据
        let outfitId = outfit.id
        if let existingObjects = try? modelContext.fetch(
            FetchDescriptor<SceneObjectData>(
                predicate: #Predicate<SceneObjectData> { $0.spaceOutfit?.id == outfitId }
            )
        ) {
            print("[Scene] 删除 \(existingObjects.count) 个旧对象")
            for obj in existingObjects {
                modelContext.delete(obj)
            }
        }
        
        // 保存新的场景对象
        for (index, object) in sceneObjects.enumerated() {
            print("[Scene] 保存对象 \(index + 1)/\(sceneObjects.count): type=\(object.type), path=\(object.usdzModelPath ?? "nil")")
            let objectData = SceneObjectData(
                id: object.id,
                objectType: object.type == .primitive ? "primitive" : "usdzModel",
                position: object.position,
                rotation: object.rotation,
                scale: object.scale,
                usdzModelPath: nil, // 先设为 nil，下面用 setModelPath 设置相对路径
                color: object.color,
                sortIndex: index,
                spaceOutfit: outfit
            )
            // 使用相对路径存储
            objectData.setModelPath(object.usdzModelPath)
            modelContext.insert(objectData)
        }
        
        // 保存第一个模型的路径到 SpaceOutfit（使用相对路径）
        if let firstObject = sceneObjects.first,
           let modelPath = firstObject.usdzModelPath {
            outfit.setModelPath(modelPath)
            print("[Scene] 设置 outfit.modelPath (stored): \(outfit.modelPath ?? "nil")")
            print("[Scene] 设置 outfit.modelPath (resolved): \(outfit.resolvedModelPath ?? "nil")")
        }
        
        // 保存上下文
        do {
            try modelContext.save()
            hasUnsavedChanges = false
            showingSaveSuccess = true
            print("[Scene] 场景保存成功，共 \(sceneObjects.count) 个对象，outfit.id: \(outfit.id)")
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




