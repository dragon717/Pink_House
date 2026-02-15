//
//  SpatialCanvasEditorView.swift
//  ItemManager
//
//  空间画布编辑器 - 支持3D高斯泼溅建模 (Metal版)
//

import SwiftUI
import SwiftData
import PhotosUI
import MetalKit
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
    
    // 3D场景状态 - 使用新的 Metal SceneObject
    @State private var sceneObjects: [SceneObject] = []
    @State private var selectedObject: SceneObject?
    
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
    
    // 返回确认
    @State private var showingBackConfirmation = false
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

            // 3D场景视图 - 使用新的 Metal SpatialSceneView
            GeometryReader { geometry in
                SpatialSceneView(
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
                    progress: processingProgress
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
                    // 处理选中的图片
                    handleSelectedImages([])
                }
            )
        }
        .sheet(isPresented: $showingCameraCapture) {
            ContinuousCameraCaptureView(
                capturedImages: $capturedImages,
                onComplete: {
                    // 处理拍摄的图片
                    handleCapturedImages([])
                }
            )
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
                Menu {
                    Button {
                        saveScene()
                        hasUnsavedChanges = false
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
                        sceneObjects.removeAll()
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
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    // MARK: - Data Loading
    
    private func loadExistingData() {
        guard let outfit = spaceOutfit else { return }
        
        // 加载3D模型
        if let modelPath = outfit.modelPath {
            load3DModel(from: modelPath)
        }
    }
    
    private func load3DModel(from path: String) {
        // 创建新的 SceneObject
        let object = SceneObject(
            type: .gsModel,
            position: SIMD3<Float>(0, 0, 0),
            rotation: SIMD3<Float>(0, 0, 0),
            scale: SIMD3<Float>(1, 1, 1),
            gsModelPath: path
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
            showingCameraCapture = true
        case .gsModel:
            // 启动3DGS建模流程
            start3DGSProcessing()
        case .light:
            // TODO: 添加灯光
            break
        case .text:
            // TODO: 添加文字
            break
        case .material:
            // TODO: 选择材质
            break
        case .clothing:
            showingAssetPanel = true
        case .effect:
            // TODO: 添加特效
            break
        case .template:
            // TODO: 选择模板
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
        // 处理素材选择
        hasUnsavedChanges = true
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
    
    // MARK: - 3DGS Processing
    
    private func start3DGSProcessing() {
        guard !capturedImages.isEmpty else { return }
        
        isProcessing3DGS = true
        processingStage = .preparing
        processingProgress = 0.0
        
        // 模拟处理进度
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            processingStage = .processing
            processingProgress = 0.3
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            processingProgress = 0.7
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            processingStage = .finalizing
            processingProgress = 0.9
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            processingStage = .complete
            processingProgress = 1.0
            isProcessing3DGS = false
            
            // 创建示例模型路径 (实际应该从处理结果获取)
            let modelPath = "path/to/generated/model.ply"
            load3DModel(from: modelPath)
        }
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
        // 保存场景数据
        if let outfit = spaceOutfit {
            // 更新现有的 SpaceOutfit
            // outfit.modelPath = ...
            // modelContext.save()
        }
        
        // 调用保存回调
        if let outfit = spaceOutfit {
            onSave?(outfit)
        }
    }
}

// MARK: - 辅助类型



struct AssetItem {
    let id: String
    let name: String
    let category: AssetCategory
}

// MARK: - 占位视图组件




