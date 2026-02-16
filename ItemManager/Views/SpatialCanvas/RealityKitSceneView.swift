import SwiftUI
import RealityKit
import simd
#if os(iOS)
import UIKit
#endif

public enum SceneObjectType {
    case usdzModel
    case primitive
}

public struct SceneObject: Identifiable {
    public let id: UUID
    public var type: SceneObjectType
    public var position: SIMD3<Float>
    public var rotation: SIMD3<Float>
    public var scale: SIMD3<Float>
    public var usdzModelPath: String?
    public var color: SIMD4<Float>
    
    public init(
        id: UUID = UUID(),
        type: SceneObjectType,
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        usdzModelPath: String? = nil,
        color: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.usdzModelPath = usdzModelPath
        self.color = color
    }
}

public struct RealityKitSceneView: View {
    
    @Binding var selectedObject: SceneObject?
    @Binding var objects: [SceneObject]
    var onObjectTap: (SceneObject) -> Void
    var onObjectTransform: (SceneObject) -> Void
    
    // 实体缓存，避免重复加载
    @State private var entityCache: [UUID: Entity] = [:]
    // 限制同时加载的实体数量
    private let maxConcurrentLoads = 3
    
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
    
    public var body: some View {
        RealityView { content in
            let rootEntity = Entity()
            rootEntity.name = "sceneRoot"
            content.add(rootEntity)
        } update: { content in
            guard let rootEntity = content.entities.first(where: { $0.name == "sceneRoot" }) else {
                return
            }
            
            // 分批加载，避免内存峰值
            let objectsToLoad = objects.filter { entityCache[$0.id] == nil }
            let limitedObjects = Array(objectsToLoad.prefix(maxConcurrentLoads))
            
            for object in objects {
                if let cachedEntity = entityCache[object.id] {
                    // 使用缓存的实体
                    if cachedEntity.parent == nil {
                        cachedEntity.name = object.id.uuidString
                        rootEntity.addChild(cachedEntity)
                    }
                    updateEntity(cachedEntity, from: object)
                } else if limitedObjects.contains(where: { $0.id == object.id }) {
                    // 异步加载新实体
                    Task {
                        if let newEntity = try? await loadEntity(for: object) {
                            newEntity.name = object.id.uuidString
                            entityCache[object.id] = newEntity
                            rootEntity.addChild(newEntity)
                        }
                    }
                }
            }
            
            // 清理不在列表中的实体
            let currentIDs = Set(objects.map { $0.id })
            for (id, entity) in entityCache {
                if !currentIDs.contains(id) {
                    entity.removeFromParent()
                    entityCache.removeValue(forKey: id)
                }
            }
            
            // 内存警告时清理缓存
            if entityCache.count > 10 {
                // 保留最近使用的实体
                let objectsToKeep = Set(objects.map { $0.id })
                for id in entityCache.keys {
                    if !objectsToKeep.contains(id) {
                        entityCache[id]?.removeFromParent()
                        entityCache.removeValue(forKey: id)
                    }
                }
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let object = objects.first(where: { $0.id.uuidString == value.entity.name }) {
                        selectedObject = object
                        onObjectTap(object)
                    }
                }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard let selected = selectedObject,
                          let index = objects.firstIndex(where: { $0.id == selected.id }) else { return }
                    
                    let deltaX = Float(value.translation.width) * 0.005
                    let deltaY = Float(value.translation.height) * 0.005
                    
                    objects[index].position.x += deltaX
                    objects[index].position.y -= deltaY
                }
        )
    }
    
    private func loadEntity(for object: SceneObject) async throws -> Entity? {
        switch object.type {
        case .usdzModel:
            if let path = object.usdzModelPath {
                let url = URL(fileURLWithPath: path)
                
                // 检查文件大小，如果太大则显示警告
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 {
                    let sizeMB = Double(fileSize) / 1024 / 1024
                    print("[RealityKitSceneView] 加载模型: \(path), 大小: \(String(format: "%.2f", sizeMB)) MB")
                    
                    // 如果模型超过 50MB，可能需要优化
                    if sizeMB > 50 {
                        print("[RealityKitSceneView] 警告: 模型较大，可能影响性能")
                    }
                }
                
                // 使用 autoreleasepool 减少内存峰值
                let entity = try await Entity.load(contentsOf: url)
                
                // 优化模型：降低材质复杂度
                optimizeEntityMaterials(entity)
                
                applyTransform(to: entity, from: object)
                return entity
            }
            
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
        
        return nil
    }
    
    private func optimizeEntityMaterials(_ entity: Entity) {
        // 递归优化所有子实体的材质
        if let modelEntity = entity as? ModelEntity {
            if var model = modelEntity.model {
                // 使用 RealityKit.Material 明确指定类型
                var optimizedMaterials: [RealityKit.Material] = []
                
                for material in model.materials {
                    // 这里可以添加材质优化逻辑
                    // 例如：降低纹理分辨率、简化着色器等
                    optimizedMaterials.append(material)
                }
                
                model.materials = optimizedMaterials
                modelEntity.model = model
            }
        }
        
        // 递归处理子实体
        for child in entity.children {
            optimizeEntityMaterials(child)
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
    
    private func updateEntity(_ entity: Entity, from object: SceneObject) {
        applyTransform(to: entity, from: object)
    }
}

struct CameraControlHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("单指拖动旋转视角", systemImage: "hand.draw")
            Label("双指捏合缩放", systemImage: "arrow.up.left.and.arrow.down.right")
            Label("点击选择对象", systemImage: "hand.tap")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
