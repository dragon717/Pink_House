import SwiftUI
import RealityKit
import simd

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
            
            for object in objects {
                if let existingEntity = rootEntity.findEntity(named: object.id.uuidString) {
                    updateEntity(existingEntity, from: object)
                } else {
                    Task {
                        if let newEntity = try? await loadEntity(for: object) {
                            newEntity.name = object.id.uuidString
                            rootEntity.addChild(newEntity)
                        }
                    }
                }
            }
            
            let currentIDs = Set(objects.map { $0.id.uuidString })
            for child in rootEntity.children {
                if !currentIDs.contains(child.name) {
                    rootEntity.removeChild(child)
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
                let entity = try await Entity.load(contentsOf: url)
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
