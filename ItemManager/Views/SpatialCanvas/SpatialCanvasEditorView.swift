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
import UniformTypeIdentifiers

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
    @State private var selectedTool: CanvasTool? = nil
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
    @State private var selectedAssetCategory: AssetCategory = .models
    
    // 底部操作栏状态
    @State private var showingBottomControls = false
    
    // 顶部模型列表状态
    @State private var showingModelList = true
    
    // USDZ 文件导入状态
    @State private var showingUSDZFilePicker = false
    
    // 变换状态
    @State private var transformMode: TransformMode = .move
    
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
                    selectedTool: $selectedTool,
                    transformMode: $transformMode,
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
            
            // 顶部模型列表
            VStack {
                TopModelListView(
                    objects: $sceneObjects,
                    selectedObject: $selectedObject,
                    selectedTool: $selectedTool,
                    showingModelList: $showingModelList
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(true)
            
            // 左侧工具栏
            VStack {
                Spacer()
                CanvasToolbar(
                    selectedTool: $selectedTool,
                    onToolTap: handleToolTap,
                    onResetCamera: {
                        cameraController?.reset()
                    },
                    onOpenAssetPanel: { category in
                        DispatchQueue.main.async {
                            selectedAssetCategory = category
                            showingAssetPanel = true
                        }
                    }
                )
                .padding(.leading, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                    HStack {
                        Spacer()
                        BottomControlBar(
                            transformMode: $transformMode,
                            onMove: { 
                                DispatchQueue.main.async {
                                    transformMode = .move 
                                }
                            },
                            onRotate: { 
                                DispatchQueue.main.async {
                                    transformMode = .rotate 
                                }
                            },
                            onScale: { 
                                DispatchQueue.main.async {
                                    transformMode = .scale 
                                }
                            },
                            onDelete: { deleteSelectedObject() }
                        )
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom))
                        Spacer()
                    }
                    .padding(.leading, 70)
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
        .fileImporter(isPresented: $showingUSDZFilePicker, allowedContentTypes: [UTType(filenameExtension: "usdz") ?? .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleSelectedUSDZFile(url)
                }
            case .failure(let error):
                print("[USDZ Import] 选择文件失败: \(error.localizedDescription)")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    selectedObject = nil
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
                        selectedObject = nil
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
                selectedObject = nil
                if hasUnsavedChanges {
                    saveScene {
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            }
            Button("不保存返回", role: .destructive) {
                selectedObject = nil
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
    
    private func loadUSDZModel(from path: String, model3DID: UUID? = nil) {
        let object = SceneObject(
            type: .usdzModel,
            position: SIMD3<Float>(0, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1),
            usdzModelPath: path,
            model3DID: model3DID
        )
        sceneObjects.append(object)
    }
    
    // MARK: - Event Handlers
    
    private func handleObjectTap(_ object: SceneObject) {
        DispatchQueue.main.async {
            if selectedObject?.id == object.id {
                selectedObject = nil
                selectedTool = nil
            } else {
                selectedObject = object
                selectedTool = .select
            }
            hasUnsavedChanges = true
        }
    }
    
    private func handleObjectTransform(_ object: SceneObject) {
        DispatchQueue.main.async {
            hasUnsavedChanges = true
        }
    }
    
    private func handleToolTap(_ tool: CanvasTool) {
        print("[SpatialCanvasEditorView] handleToolTap 被调用，工具: \(tool.rawValue), 当前选中: \(selectedTool?.rawValue ?? "nil")")
        
        DispatchQueue.main.async {
            // 如果选择工具已经是选中状态，则取消选中并恢复手势控制
            if tool == .select && selectedTool == .select {
                print("[SpatialCanvasEditorView] 选择工具已选中，取消选择")
                selectedTool = nil
                selectedObject = nil
                print("[SpatialCanvasEditorView] 取消后选中: \(selectedTool?.rawValue ?? "nil")")
                return
            }
            
            // 如果点击的是其他工具，先取消选择模式
            if selectedTool == .select {
                selectedObject = nil
            }
            
            selectedTool = tool
            selectedObject = nil
            print("[SpatialCanvasEditorView] 设置选中为: \(selectedTool?.rawValue ?? "nil")")
            
            switch tool {
            case .select:
                // 选择工具：禁用手势控制视角，启用点击选择模型
                break
            case .image:
                showingImagePicker = true
            case .gallery:
                showingImagePicker = true
            case .camera:
                showingObjectCaptureScanner = true
            case .usdzModel:
                showingUSDZFilePicker = true
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
            case .resetCamera:
                // 重置相机视角已在工具栏按钮中处理
                break
            }
        }
    }
    
    private func handleAssetSelect(_ asset: SpatialAsset) {
        DispatchQueue.main.async {
            hasUnsavedChanges = true
            
            switch asset.type {
            case .model:
                if let modelPath = asset.metadata["modelPath"] {
                    let model3DIDString = asset.metadata["model3DID"]
                    let model3DID = model3DIDString.flatMap { UUID(uuidString: $0) }
                    loadUSDZModel(from: modelPath, model3DID: model3DID)
                }
            case .clothing:
                if let modelPath = asset.metadata["modelPath"] {
                    loadUSDZModel(from: modelPath, model3DID: nil)
                }
            case .effect:
                print("[Asset] 选择特效: \(asset.name)")
            case .template:
                print("[Asset] 选择模板: \(asset.name)")
            case .material:
                print("[Asset] 选择材质: \(asset.name)")
            }
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
                    
                    saveUSDZModelAndCreateModel3D(usdzURL: usdzURL, images: capturedImages)
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
                
                // 从目录加载图片
                var images: [UIImage] = []
                let fileManager = FileManager.default
                if let imageURLs = try? fileManager.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil) {
                    for url in imageURLs {
                        if let data = try? Data(contentsOf: url),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                }
                
                // 取消进度监听
                progressTask.cancel()
                
                await MainActor.run {
                    print("[SpatialCanvasEditorView] 处理完成，USDZ 路径: \(usdzURL.path)")
                    processingStage = .complete
                    processingProgress = 1.0
                    isProcessing3DGS = false
                    
                    // 保存到 Model3D 并创建场景对象
                    saveUSDZModelAndCreateModel3D(usdzURL: usdzURL, images: images)
                    
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
    
    private func saveUSDZModelAndCreateModel3D(usdzURL: URL, images: [UIImage]) {
        let modelID = UUID()
        print("[ObjectCapture] ===== 开始保存 Model3D =====")
        print("[ObjectCapture] modelID: \(modelID)")
        print("[ObjectCapture] usdzURL: \(usdzURL.path)")
        
        let thumbnailPath = saveThumbnail(from: images.first, modelID: modelID)
        print("[ObjectCapture] thumbnailPath: \(thumbnailPath ?? "nil")")
        
        let imagePaths = saveSourceImages(images, modelID: modelID)
        print("[ObjectCapture] sourceImagePaths count: \(imagePaths.count)")
        
        let model3D = Model3D(
            name: "3D模型 \(modelID.uuidString.prefix(8))",
            types: "3D模型",
            modelPath: nil,
            modelType: "usdz",
            thumbnailPath: nil,
            sourceImagePaths: imagePaths
        )
        // 使用相对路径存储
        model3D.setModelPath(usdzURL.path)
        model3D.setThumbnailPath(thumbnailPath)
        
        print("[ObjectCapture] model3D.modelPath after set: \(model3D.modelPath ?? "nil")")
        print("[ObjectCapture] model3D.thumbnailPath after set: \(model3D.thumbnailPath ?? "nil")")
        print("[ObjectCapture] model3D.isDeleted: \(model3D.isDeleted)")
        
        modelContext.insert(model3D)
        print("[ObjectCapture] model3D 已插入 modelContext")
        
        // 保存上下文到数据库
        do {
            try modelContext.save()
            print("[ObjectCapture] ✅ Model3D 已保存到数据库: \(modelID)")
        } catch {
            print("[ObjectCapture] ❌ 保存 Model3D 失败: \(error)")
        }
        
        let object = SceneObject(
            type: .usdzModel,
            position: SIMD3<Float>(0, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1),
            usdzModelPath: usdzURL.path,
            model3DID: model3D.id
        )
        sceneObjects.append(object)
        
        hasUnsavedChanges = true
        
        print("[ObjectCapture] 创建3D模型记录: \(modelID)")
        print("[ObjectCapture] =====================")
    }
    
    private func handleSelectedUSDZFile(_ url: URL) {
        print("[USDZ Import] ===== 开始导入 USDZ 文件 =====")
        print("[USDZ Import] 原始 URL: \(url)")
        
        // 访问安全通报资源
        let canAccess = url.startAccessingSecurityScopedResource()
        print("[USDZ Import] startAccessingSecurityScopedResource: \(canAccess)")
        
        guard canAccess else {
            print("[USDZ Import] ❌ 无法访问文件")
            return
        }
        
        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            do {
                // 复制文件到应用目录
                let modelID = UUID()
                let fileManager = FileManager.default
                guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("[USDZ Import] ❌ 无法获取文档目录")
                    return
                }
                
                let modelDir = documentsPath.appendingPathComponent("Models/\(modelID.uuidString)")
                try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
                
                let destinationURL = modelDir.appendingPathComponent("model.usdz")
                
                // 复制文件
                try fileManager.copyItem(at: url, to: destinationURL)
                print("[USDZ Import] ✅ 文件已复制到: \(destinationURL.path)")
                
                // 创建 Model3D 记录
                let model3D = Model3D(
                    name: url.deletingPathExtension().lastPathComponent,
                    types: "3D模型",
                    modelPath: nil,
                    modelType: "usdz",
                    thumbnailPath: nil,
                    sourceImagePaths: []
                )
                model3D.setModelPath(destinationURL.path)
                
                modelContext.insert(model3D)
                
                // 保存上下文
                try modelContext.save()
                print("[USDZ Import] ✅ Model3D 已保存到数据库: \(modelID)")
                
                await MainActor.run {
                    // 创建场景对象
                    let object = SceneObject(
                        type: .usdzModel,
                        position: SIMD3<Float>(0, 0, 0),
                        rotation: SIMD3<Float>(0, 0, 0),
                        scale: SIMD3<Float>(1, 1, 1),
                        usdzModelPath: destinationURL.path,
                        model3DID: model3D.id
                    )
                    sceneObjects.append(object)
                    hasUnsavedChanges = true
                    print("[USDZ Import] ✅ 场景对象已创建")
                }
                
            } catch {
                print("[USDZ Import] ❌ 导入失败: \(error)")
            }
        }
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
    
    private func deleteSelectedObject() {
        DispatchQueue.main.async {
            guard let object = selectedObject,
                  let index = sceneObjects.firstIndex(where: { $0.id == object.id }) else { return }
            
            sceneObjects.remove(at: index)
            selectedObject = nil
            hasUnsavedChanges = true
        }
    }
    
    // MARK: - Save
    
    private func saveScene(completion: (() -> Void)? = nil) {
        guard !sceneObjects.isEmpty else {
            print("[Scene] 场景为空，无需保存")
            hasUnsavedChanges = false
            completion?()
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
            
            var model3D: Model3D? = nil
            if let model3DID = object.model3DID {
                let descriptor = FetchDescriptor<Model3D>(
                    predicate: #Predicate<Model3D> { $0.id == model3DID && $0.isDeleted == false }
                )
                model3D = try? modelContext.fetch(descriptor).first
            }
            
            let objectData = SceneObjectData(
                id: object.id,
                objectType: object.type == .primitive ? "primitive" : "usdzModel",
                position: object.position,
                rotation: object.rotation,
                scale: object.scale,
                usdzModelPath: nil, // 先设为 nil，下面用 setModelPath 设置相对路径
                color: object.color,
                sortIndex: index,
                spaceOutfit: outfit,
                model3D: model3D
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
            
            // 调用保存回调
            onSave?(outfit)
            completion?()
        } catch {
            print("[Scene] 保存失败: \(error)")
            completion?()
        }
    }
}

// MARK: - 辅助类型



struct AssetItem {
    let id: String
    let name: String
    let category: AssetCategory
}

// MARK: - 顶部模型列表视图

struct TopModelListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Binding var objects: [SceneObject]
    @Binding var selectedObject: SceneObject?
    @Binding var selectedTool: CanvasTool?
    @Binding var showingModelList: Bool
    @State private var model3DCache: [UUID: Model3D] = [:]
    @State private var refreshTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            if showingModelList {
                modelListContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            toggleButton
        }
        .onAppear {
            loadModel3DCache()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onChange(of: objects) { _, _ in
            loadModel3DCache()
        }
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            loadModel3DCache()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func loadModel3DCache() {
        let ids = objects.compactMap { $0.model3DID }
        guard !ids.isEmpty else { return }
        
        do {
            let descriptor = FetchDescriptor<Model3D>(
                predicate: #Predicate<Model3D> { ids.contains($0.id) && $0.isDeleted == false }
            )
            let models = try modelContext.fetch(descriptor)
            model3DCache = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        } catch {
            print("[TopModelListView] 加载 Model3D 缓存失败: \(error)")
        }
    }
    
    private var modelListContent: some View {
        VStack(spacing: 8) {
            HStack {
                Text("场景模型")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(objects.count) 个模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            if objects.isEmpty {
                emptyState
            } else {
                modelList
            }
        }
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
        .padding(.leading, 70)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }
    
    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "cube.box")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("暂无模型")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 24)
    }
    
    private var modelList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(objects) { object in
                    ModelCard(
                        object: object,
                        model3D: object.model3DID.flatMap { model3DCache[$0] },
                        isSelected: selectedObject?.id == object.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedObject?.id == object.id {
                                    selectedObject = nil
                                    selectedTool = nil
                                } else {
                                    selectedObject = object
                                    selectedTool = .select
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 120)
    }
    
    private var toggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingModelList.toggle()
            }
        } label: {
            Image(systemName: showingModelList ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.purple)
                .symbolRenderingMode(.hierarchical)
        }
        .padding(.top, 8)
    }
}

struct ModelCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let object: SceneObject
    let model3D: Model3D?
    let isSelected: Bool
    let onTap: () -> Void
    
    private var thumbnailPath: String? {
        model3D?.resolvedThumbnailPath
    }
    
    private var modelName: String {
        if let name = model3D?.name, !name.isEmpty {
            return name
        }
        return "模型"
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    if let path = thumbnailPath,
                       let uiImage = UIImage(contentsOfFile: path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(12)
                    } else {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                    }
                }
                
                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? 
                          (colorScheme == .dark ? Color.purple.opacity(0.2) : Color.purple.opacity(0.1)) :
                          (colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 占位视图组件




