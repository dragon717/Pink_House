//
//  SpaceOutfitPreviewView.swift
//  ItemManager
//
//  3D书页预览视图 - 针对小内存iPhone优化
//  支持：实时渲染、缩略图缓存、性能优化、iCloud同步
//

import SwiftUI
import RealityKit
import ARKit
import SwiftData

// MARK: - 缩略图缓存管理器

/// 专门用于3D书页预览的缩略图缓存
@MainActor
class SpaceOutfitThumbnailCache {
    static let shared = SpaceOutfitThumbnailCache()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    // 根据设备内存动态调整缓存限制
    private func configureCacheLimits() {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let limitInMB: Int
        
        if totalMemory <= 2 * 1024 * 1024 * 1024 { // <= 2GB
            limitInMB = 10 // 极小缓存
            memoryCache.countLimit = 10
        } else if totalMemory <= 4 * 1024 * 1024 * 1024 { // <= 4GB
            limitInMB = 30
            memoryCache.countLimit = 20
        } else {
            limitInMB = 50
            memoryCache.countLimit = 30
        }
        
        memoryCache.totalCostLimit = limitInMB * 1024 * 1024
    }
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("SpaceOutfitThumbnails")
        
        configureCacheLimits()
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 内存警告时清理缓存
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }
    
    /// 获取缓存的缩略图
    func getThumbnail(for pageID: UUID) -> UIImage? {
        let key = pageID.uuidString as NSString
        
        // 先检查内存缓存
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        
        // 再检查磁盘缓存
        let fileURL = cacheDirectory.appendingPathComponent("\(pageID.uuidString).jpg")
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // 加载到内存缓存
            memoryCache.setObject(image, forKey: key, cost: data.count)
            return image
        }
        
        return nil
    }
    
    /// 保存缩略图到缓存
    func saveThumbnail(_ image: UIImage, for pageID: UUID) {
        let key = pageID.uuidString as NSString
        
        // 保存到内存缓存
        if let data = image.jpegData(compressionQuality: 0.8) {
            memoryCache.setObject(image, forKey: key, cost: data.count)
            
            // 异步保存到磁盘
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                let fileURL = self.cacheDirectory.appendingPathComponent("\(pageID.uuidString).jpg")
                try? data.write(to: fileURL)
            }
        }
    }
    
    /// 清理过期缓存（保留最近30天）
    func cleanExpiredCache() {
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            let expirationDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30天前
            
            if let files = try? self.fileManager.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for file in files {
                    if let attributes = try? self.fileManager.attributesOfItem(atPath: file.path),
                       let modificationDate = attributes[.modificationDate] as? Date,
                       modificationDate < expirationDate {
                        try? self.fileManager.removeItem(at: file)
                    }
                }
            }
        }
    }
}

// MARK: - 3D书页预览视图

/// 3D书页预览视图 - 针对小内存iPhone优化
struct SpaceOutfitPreviewView: View {
    let page: SpaceOutfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var thumbnailImage: UIImage?
    @State private var isGeneratingThumbnail = false
    @State private var sceneObjects: [SceneObject] = []
    @State private var shouldShowARView = false
    @State private var refreshTrigger = UUID()
    
    // 性能优化：列表/网格场景禁用实时 ARView 预览。
    // 原逻辑在高内存设备上为每个可见书页创建 SpaceOutfitARPreview（RealityKit 每帧渲染），
    // LazyVGrid 滚动时可同时存在多个 ARView，导致 CPU 持续过高；
    // 且 captureThumbnail() 为占位实现，缩略图永远不会生成、ARView 也不会被销毁。
    // 缩略图由编辑器保存/缩略图编辑器生成，并通过 .spaceOutfitThumbnailUpdated 通知刷新。
    // 编辑器的实时渲染走 SpatialCanvasEditorView 独立视图，不受此开关影响。
    private var useARViewPreview: Bool {
        return false
    }
    
    var body: some View {
        ZStack {
            // 背景色
            colorScheme == .dark ? Color(uiColor: .systemGray6) : Color.white
            
            if let thumbnail = thumbnailImage {
                // 显示缓存的缩略图
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if isGeneratingThumbnail {
                // 生成缩略图中
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("生成预览...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            } else if shouldShowARView && useARViewPreview {
                // ARView 实时预览（仅在高内存设备上）
                SpaceOutfitARPreview(objects: sceneObjects, cameraPosition: cameraPosition)
                    .onAppear {
                        // 3秒后自动捕获缩略图
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            captureThumbnail()
                        }
                    }
            } else {
                // 低内存设备或缩略图生成失败时显示占位符
                placeholderView
            }
        }
        .task(id: page.id) {
            await loadPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .spaceOutfitThumbnailUpdated)) { notification in
            // 监听缩略图更新通知
            if let updatedPageID = notification.object as? UUID, updatedPageID == page.id {
                // 重新加载缩略图
                Task {
                    await loadPreview()
                }
            }
        }
    }
    
    private var placeholderView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "cube.transparent")
                    .font(.system(size: 20))
                    .foregroundStyle(.gray.opacity(0.3))
                Spacer()
            }
            Spacer()
        }
    }
    
    /// 默认相机位置 - 居中视角
    private var cameraPosition: SIMD3<Float> {
        // 如果书页有保存的相机位置，使用保存的位置
        // 否则使用默认居中视角
        if page.camPosX != 0 || page.camPosY != 0 || page.camPosZ != 0 {
            return SIMD3<Float>(
                Float(page.camPosX),
                Float(page.camPosY),
                Float(page.camPosZ)
            )
        }
        // 默认居中视角：相机在Z轴正方向，看向原点
        // 使用 (0, 0, 5) 确保原点 (0,0,0) 在屏幕中心
        return SIMD3<Float>(0, 0, 5)
    }
    
    /// 相机目标点 - 始终看向原点
    private var cameraTarget: SIMD3<Float> {
        SIMD3<Float>(0, 0, 0)
    }
    
    private func loadPreview() async {
        // 1. 先尝试从缓存加载缩略图
        if let cached = SpaceOutfitThumbnailCache.shared.getThumbnail(for: page.id) {
            await MainActor.run {
                self.thumbnailImage = cached
            }
            return
        }
        
        // 2. 无缓存缩略图时，回退到已保存的静态快照图片（避免实时渲染）
        if let snapshotPath = page.snapshotPath,
           let snapshot = await ImageManager.shared.loadImageAsync(fileName: snapshotPath, targetSize: CGSize(width: 320, height: 440)) {
            await MainActor.run {
                self.thumbnailImage = snapshot
            }
            return
        }
        
        // 3. 列表场景已禁用实时 ARView 预览（useARViewPreview == false），
        //    无需加载场景对象，直接显示占位符，等待编辑器生成缩略图后通过通知刷新
        guard useARViewPreview else { return }
        
        // 4. 加载场景对象并显示 ARView（当前不会执行，保留以便日后恢复实时预览）
        let objects = await MainActor.run {
            page.fetchSceneObjects(context: modelContext)
        }
        
        let sceneObjects = objects.map { $0.toSceneObject() }
        
        await MainActor.run {
            self.sceneObjects = sceneObjects
            
            // 如果场景为空，显示占位符
            if sceneObjects.isEmpty {
                return
            }
            
            self.shouldShowARView = true
        }
    }
    
    /// 异步生成缩略图（用于低内存设备）
    private func generateThumbnailAsync() async {
        // 使用后台任务生成缩略图
        let thumbnail = await Task.detached(priority: .background) { () -> UIImage? in
            // 这里可以调用渲染服务生成缩略图
            // 暂时返回nil，使用占位符
            return nil
        }.value
        
        if let thumbnail = thumbnail {
            SpaceOutfitThumbnailCache.shared.saveThumbnail(thumbnail, for: page.id)
            await MainActor.run {
                self.thumbnailImage = thumbnail
                self.isGeneratingThumbnail = false
            }
        } else {
            await MainActor.run {
                self.isGeneratingThumbnail = false
            }
        }
    }
    
    /// 从ARView捕获缩略图
    private func captureThumbnail() {
        // 这个函数会在ARView显示后被调用
        // 实际实现需要在ARPreview中暴露捕获接口
        // 这里作为占位符
    }
}

// MARK: - AR Preview View (优化版)

/// 使用ARView渲染3D场景预览 - 内存优化版
struct SpaceOutfitARPreview: UIViewRepresentable {
    let objects: [SceneObject]
    let cameraPosition: SIMD3<Float>
    
    // 限制同时加载的模型数量
    private let maxConcurrentLoads = 2
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(UIColor.clear)
        
        // 设置相机
        setupCamera(in: arView)
        
        // 添加灯光
        setupLighting(in: arView)
        
        // 加载场景对象（限制数量）
        loadObjects(into: arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // 更新场景对象
        updateObjects(in: uiView)
    }
    
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) {
        // 清理资源
        uiView.session.pause()
        for anchor in uiView.scene.anchors {
            anchor.removeFromParent()
        }
    }
    
    private func setupCamera(in arView: ARView) {
        let camera = PerspectiveCamera()
        
        // 创建相机锚点，位置在相机位置
        let cameraAnchor = AnchorEntity(world: cameraPosition)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)
        
        // 让相机看向原点 (0,0,0)
        camera.look(at: SIMD3<Float>(0, 0, 0), from: cameraPosition, relativeTo: nil)
    }
    
    private func setupLighting(in arView: ARView) {
        // 简化灯光设置，减少性能开销
        let directionalLight = Entity()
        var directionalLightComponent = DirectionalLightComponent()
        directionalLightComponent.intensity = 1.5
        directionalLightComponent.color = .white
        directionalLight.components.set(directionalLightComponent)
        directionalLight.orientation = simd_quatf(angle: Float.pi / 4, axis: [1, 0, 0])
        
        let lightAnchor = AnchorEntity(world: .zero)
        lightAnchor.addChild(directionalLight)
        arView.scene.addAnchor(lightAnchor)
    }
    
    private func loadObjects(into arView: ARView) {
        // 限制加载对象数量，避免内存溢出
        let objectsToLoad = Array(objects.prefix(maxConcurrentLoads))
        
        Task {
            for object in objectsToLoad {
                if let entity = try? await loadEntity(for: object) {
                    await MainActor.run {
                        let anchor = AnchorEntity(world: object.position)
                        anchor.name = "object_\(object.id.uuidString)"
                        anchor.addChild(entity)
                        arView.scene.addAnchor(anchor)
                    }
                }
            }
        }
    }
    
    private func updateObjects(in arView: ARView) {
        // 移除现有对象
        for anchor in arView.scene.anchors {
            if anchor.name.starts(with: "object_") {
                anchor.removeFromParent()
            }
        }
        
        // 重新加载（限制数量）
        loadObjects(into: arView)
    }
    
    private func loadEntity(for object: SceneObject) async throws -> Entity? {
        switch object.type {
        case .usdzModel:
            guard let path = object.usdzModelPath else { return nil }
            
            // 检查文件大小，大模型跳过
            let fileURL = URL(fileURLWithPath: path)
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 {
                let sizeMB = Double(fileSize) / 1024 / 1024
                // 跳过大于20MB的模型
                if sizeMB > 20 {
                    print("[SpaceOutfitARPreview] 模型过大，跳过加载: \(sizeMB)MB")
                    return createPlaceholderEntity(color: .gray)
                }
            }
            
            let entity = try await Entity.load(contentsOf: fileURL)
            applyTransform(to: entity, from: object)
            return entity
            
        case .primitive:
            return createPrimitiveEntity(for: object)
        }
    }
    
    private func createPrimitiveEntity(for object: SceneObject) -> Entity {
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
    
    private func createPlaceholderEntity(color: UIColor) -> Entity {
        let entity = ModelEntity(mesh: .generateBox(size: 0.2))
        var material = SimpleMaterial()
        material.color = SimpleMaterial.BaseColor(tint: color)
        entity.model?.materials = [material]
        return entity
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
}

// MARK: - iCloud 同步支持扩展

extension SpaceOutfit {
    /// 导出为可同步的数据格式
    func toSyncableData(context: ModelContext) -> SpaceOutfitSyncData {
        let sceneObjects = fetchSceneObjects(context: context)
        
        return SpaceOutfitSyncData(
            id: id,
            createdAt: createdAt,
            note: note,
            sortIndex: sortIndex,
            camPosX: camPosX,
            camPosY: camPosY,
            camPosZ: camPosZ,
            lightingIntensity: lightingIntensity,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            lastModified: lastModified,
            bookID: book?.id,
            sceneObjects: sceneObjects.map { $0.toSyncableData() }
        )
    }
}

extension SceneObjectData {
    /// 导出为可同步的数据格式
    func toSyncableData() -> SceneObjectSyncData {
        SceneObjectSyncData(
            id: id,
            objectType: objectType,
            positionX: positionX,
            positionY: positionY,
            positionZ: positionZ,
            rotationX: rotationX,
            rotationY: rotationY,
            rotationZ: rotationZ,
            scaleX: scaleX,
            scaleY: scaleY,
            scaleZ: scaleZ,
            usdzModelPath: usdzModelPath,
            colorR: colorR,
            colorG: colorG,
            colorB: colorB,
            colorA: colorA,
            sortIndex: sortIndex,
            spaceOutfitID: spaceOutfitID,
            model3DID: model3D?.id,
            lastModified: lastModified
        )
    }
}

// MARK: - 同步数据结构

/// SpaceOutfit 同步数据
struct SpaceOutfitSyncData: Codable {
    let id: UUID
    let createdAt: Date
    let note: String
    let sortIndex: Int
    let camPosX: Double
    let camPosY: Double
    let camPosZ: Double
    let lightingIntensity: Double
    let isDeleted: Bool
    let deletedAt: Date?
    let lastModified: Date
    let bookID: UUID?
    let sceneObjects: [SceneObjectSyncData]
}

/// SceneObjectData 同步数据
struct SceneObjectSyncData: Codable {
    let id: UUID
    let objectType: String
    let positionX: Double
    let positionY: Double
    let positionZ: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let scaleX: Double
    let scaleY: Double
    let scaleZ: Double
    let usdzModelPath: String?
    let colorR: Double
    let colorG: Double
    let colorB: Double
    let colorA: Double
    let sortIndex: Int
    let spaceOutfitID: UUID?
    let model3DID: UUID?
    let lastModified: Date
}

// MARK: - 预览

#Preview {
    SpaceOutfitPreviewView(page: SpaceOutfit(note: "测试页面"))
        .frame(width: 200, height: 267)
}
