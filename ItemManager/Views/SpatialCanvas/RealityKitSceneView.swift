import SwiftUI
import RealityKit
import simd
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
public typealias UIColor = NSColor
#endif

public enum SceneObjectType {
    case usdzModel
    case primitive
}

public struct SceneObject: Identifiable, Equatable {
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
    
    public static func == (lhs: SceneObject, rhs: SceneObject) -> Bool {
        lhs.id == rhs.id
    }
}

public struct RealityKitSceneView: View {
    
    @Binding var selectedObject: SceneObject?
    @Binding var objects: [SceneObject]
    @Binding var selectedTool: CanvasTool?
    @Binding var transformMode: TransformMode
    var onObjectTap: (SceneObject) -> Void
    var onObjectTransform: (SceneObject) -> Void
    var onCameraControllerReady: ((CameraController) -> Void)?
    var onGizmoDismiss: (() -> Void)?
    
    public func dismissGizmo() {
        _selectedObject.wrappedValue = nil
    }
    
    @StateObject private var cameraController = CameraController()
    @State private var entityCache: [UUID: Entity] = [:]
    @State private var selectionOutlineEntity: Entity?
    @State private var gizmoEntity: Entity?
    @State private var activeGizmoAxis: GizmoAxis? = nil
    @State private var initialDragPosition: SIMD3<Float>? = nil
    @State private var initialObjectTransform: (position: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>)? = nil
    private let maxConcurrentLoads = 3
    
    public init(
        selectedObject: Binding<SceneObject?>,
        objects: Binding<[SceneObject]>,
        selectedTool: Binding<CanvasTool?> = .constant(nil),
        transformMode: Binding<TransformMode> = .constant(.move),
        onObjectTap: @escaping (SceneObject) -> Void = { _ in },
        onObjectTransform: @escaping (SceneObject) -> Void = { _ in },
        onCameraControllerReady: ((CameraController) -> Void)? = nil,
        onGizmoDismiss: (() -> Void)? = nil
    ) {
        self._selectedObject = selectedObject
        self._objects = objects
        self._selectedTool = selectedTool
        self._transformMode = transformMode
        self.onObjectTap = onObjectTap
        self.onObjectTransform = onObjectTransform
        self.onCameraControllerReady = onCameraControllerReady
        self.onGizmoDismiss = onGizmoDismiss
    }
    
    public var body: some View {
        ZStack {
            RealityView { content in
                let rootEntity = Entity()
                rootEntity.name = "sceneRoot"
                content.add(rootEntity)
                
                let cameraEntity = cameraController.setupCamera(in: rootEntity)
                
                onCameraControllerReady?(cameraController)
                
                print("[RealityKitSceneView] 相机设置完成，位置: \(cameraEntity.position)")
                
                let lightEntity = Entity()
                lightEntity.name = "directionalLight"
                var lightComponent = DirectionalLightComponent()
                lightComponent.intensity = 2.0
                lightComponent.color = .white
                lightEntity.components.set(lightComponent)
                lightEntity.orientation = simd_quatf(angle: Float.pi / 4, axis: [1, 0, 0])
                rootEntity.addChild(lightEntity)
                
                let pointLight = Entity()
                pointLight.name = "pointLight"
                pointLight.position = SIMD3<Float>(2, 3, 2)
                var pointLightComponent = PointLightComponent()
                pointLightComponent.intensity = 1.0
                pointLightComponent.color = .white
                pointLight.components.set(pointLightComponent)
                rootEntity.addChild(pointLight)
                
            } update: { content in
                guard let rootEntity = content.entities.first(where: { $0.name == "sceneRoot" }) else {
                    return
                }
                
                let objectsToLoad = objects.filter { entityCache[$0.id] == nil }
                let limitedObjects = Array(objectsToLoad.prefix(maxConcurrentLoads))
                
                for object in objects {
                    if let cachedEntity = entityCache[object.id] {
                        if cachedEntity.parent == nil {
                            cachedEntity.name = object.id.uuidString
                            rootEntity.addChild(cachedEntity)
                        }
                        updateEntity(cachedEntity, from: object)
                    } else if limitedObjects.contains(where: { $0.id == object.id }) {
                        Task {
                            if let newEntity = try? await loadEntity(for: object) {
                                newEntity.name = object.id.uuidString
                                entityCache[object.id] = newEntity
                                rootEntity.addChild(newEntity)
                            }
                        }
                    }
                }
                
                let currentIDs = Set(objects.map { $0.id })
                for (id, entity) in entityCache {
                    if !currentIDs.contains(id) {
                        entity.removeFromParent()
                        entityCache.removeValue(forKey: id)
                    }
                }
                
                if entityCache.count > 10 {
                    let objectsToKeep = Set(objects.map { $0.id })
                    for id in entityCache.keys {
                        if !objectsToKeep.contains(id) {
                            entityCache[id]?.removeFromParent()
                            entityCache.removeValue(forKey: id)
                        }
                    }
                }
                
                updateGizmo(in: rootEntity)
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        handleSpatialTap(value.entity)
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleDragChange(value)
                    }
                    .onEnded { _ in
                        handleDragEnd()
                    }
            )
            .onChange(of: selectedObject) { _, _ in
                DispatchQueue.main.async {
                    updateSelectionOutline()
                }
            }
            .onChange(of: selectedTool) { _, _ in
                DispatchQueue.main.async {
                    updateSelectionOutline()
                }
            }
            .onChange(of: transformMode) { _, _ in
                DispatchQueue.main.async {
                    updateGizmoManually()
                }
            }
            
            if selectedTool != .select {
                CameraGestureView(controller: cameraController)
            }
            
            if selectedTool == .select {
                VStack {
                    HStack {
                        Spacer()
                        SelectionModeHint()
                    }
                    .padding(.top, 110)
                    .padding(.trailing, 16)
                    Spacer()
                }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    CameraControlHint()
                        .padding(.trailing, 16)
                        .padding(.bottom, 100)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
    
    private func loadEntity(for object: SceneObject) async throws -> Entity? {
        switch object.type {
        case .usdzModel:
            if let path = object.usdzModelPath {
                let url = URL(fileURLWithPath: path)
                
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 {
                    let sizeMB = Double(fileSize) / 1024 / 1024
                    print("[RealityKitSceneView] 加载模型: \(path), 大小: \(String(format: "%.2f", sizeMB)) MB")
                    
                    if sizeMB > 50 {
                        print("[RealityKitSceneView] 警告: 模型较大，可能影响性能")
                    }
                }
                
                let entity = try await Entity.load(contentsOf: url)
                optimizeEntityMaterials(entity)
                applyTransform(to: entity, from: object)
                
                addCollisionAndInputComponents(to: entity)
                
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
            
            addCollisionAndInputComponents(to: entity)
            
            return entity
        }
        
        return nil
    }
    
    private func addCollisionAndInputComponents(to entity: Entity) {
        entity.generateCollisionShapes(recursive: true)
        
        if let modelEntity = entity as? ModelEntity {
            modelEntity.components.set(InputTargetComponent())
        }
        
        for child in entity.children {
            addCollisionAndInputComponents(to: child)
        }
    }
    
    private func optimizeEntityMaterials(_ entity: Entity) {
        if let modelEntity = entity as? ModelEntity {
            if var model = modelEntity.model {
                var optimizedMaterials: [RealityKit.Material] = []
                
                for material in model.materials {
                    optimizedMaterials.append(material)
                }
                
                model.materials = optimizedMaterials
                modelEntity.model = model
            }
        }
        
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
    
    private func handleSpatialTap(_ tappedEntity: Entity) {
        guard selectedTool == .select else { return }
        
        if tappedEntity.name.starts(with: "gizmo_") {
            DispatchQueue.main.async {
                if tappedEntity.name.contains("_x") {
                    self.activeGizmoAxis = .x
                } else if tappedEntity.name.contains("_y") {
                    self.activeGizmoAxis = .y
                } else if tappedEntity.name.contains("_z") {
                    self.activeGizmoAxis = .z
                } else if tappedEntity.name.contains("center") {
                    self.activeGizmoAxis = .all
                }
            }
            return
        }
        
        var currentEntity: Entity? = tappedEntity
        while let entity = currentEntity, !entity.name.isEmpty && !objects.contains(where: { $0.id.uuidString == entity.name }) {
            currentEntity = entity.parent
        }
        
        if let targetEntity = currentEntity, 
           let object = objects.first(where: { $0.id.uuidString == targetEntity.name }) {
            DispatchQueue.main.async {
                self.selectedObject = object
                self.onObjectTap(object)
                print("[RealityKitSceneView] 选中对象: \(object.id), 名称: \(targetEntity.name)")
            }
        } else {
            print("[RealityKitSceneView] 未找到匹配的对象，点击实体: \(tappedEntity.name)")
        }
    }
    
    private func updateSelectionOutline() {
        selectionOutlineEntity?.removeFromParent()
        selectionOutlineEntity = nil
        
        guard selectedTool == .select, let selected = selectedObject else { return }
        
        guard let entity = entityCache[selected.id] else { return }
        
        let outline = createSelectionOutline(for: entity, object: selected)
        entity.addChild(outline)
        selectionOutlineEntity = outline
    }
    
    private func createSelectionOutline(for entity: Entity, object: SceneObject) -> Entity {
        let bounds = entity.visualBounds(relativeTo: nil)
        let size = bounds.extents * 1.05
        
        let outlineEntity = Entity()
        
        let lineThickness: Float = 0.006
        let halfSize = size / 2
        
        let vertices = [
            SIMD3<Float>(-halfSize.x, -halfSize.y, -halfSize.z),
            SIMD3<Float>( halfSize.x, -halfSize.y, -halfSize.z),
            SIMD3<Float>( halfSize.x,  halfSize.y, -halfSize.z),
            SIMD3<Float>(-halfSize.x,  halfSize.y, -halfSize.z),
            SIMD3<Float>(-halfSize.x, -halfSize.y,  halfSize.z),
            SIMD3<Float>( halfSize.x, -halfSize.y,  halfSize.z),
            SIMD3<Float>( halfSize.x,  halfSize.y,  halfSize.z),
            SIMD3<Float>(-halfSize.x,  halfSize.y,  halfSize.z)
        ]
        
        let edges = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        
        let outlineColor = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1.0)
        
        for (start, end) in edges {
            let line = createLine(from: vertices[start], to: vertices[end], 
                                 thickness: lineThickness, color: outlineColor)
            outlineEntity.addChild(line)
        }
        
        return outlineEntity
    }
    
    private func createLine(from start: SIMD3<Float>, to end: SIMD3<Float>, 
                           thickness: Float, color: UIColor) -> Entity {
        let lineEntity = Entity()
        
        let midPoint = (start + end) / 2
        let lineLength = length(end - start)
        
        let mesh = MeshResource.generateCylinder(height: lineLength, radius: thickness)
        
        var material = UnlitMaterial(color: color)
        
        let modelEntity = ModelEntity(mesh: mesh, materials: [material])
        
        modelEntity.position = midPoint
        modelEntity.look(at: end, from: start, relativeTo: nil)
        
        lineEntity.addChild(modelEntity)
        return lineEntity
    }
    
    private func updateGizmo(in rootEntity: Entity) {
        rootEntity.children.forEach { child in
            if child.name == "gizmo" || child.name.starts(with: "gizmo_") {
                child.removeFromParent()
            }
        }
        gizmoEntity = nil
        
        guard selectedTool == .select, let selected = selectedObject, let entity = entityCache[selected.id] else { return }
        
        let gizmo = createGizmo(for: transformMode)
        gizmo.position = entity.position
        rootEntity.addChild(gizmo)
        gizmoEntity = gizmo
    }
    
    private func updateGizmoManually() {
        guard let rootEntity = entityCache.values.first?.parent else { return }
        updateGizmo(in: rootEntity)
    }
    
    private func createGizmo(for mode: TransformMode) -> Entity {
        let gizmo = Entity()
        gizmo.name = "gizmo"
        
        let scale: Float = 0.35
        
        switch mode {
        case .move:
            createMoveGizmo(on: gizmo, scale: scale)
        case .rotate:
            createRotateGizmo(on: gizmo, scale: scale)
        case .scale:
            createScaleGizmo(on: gizmo, scale: scale)
        }
        
        return gizmo
    }
    
    private func createMoveGizmo(on gizmo: Entity, scale: Float) {
        let arrowLength: Float = scale
        let arrowRadius: Float = 0.012
        let coneHeight: Float = 0.08
        let coneRadius: Float = 0.035
        
        let xColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        let yColor = UIColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 1.0)
        let zColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        
        let xAxis = createModernArrow(axis: [1, 0, 0], color: xColor, length: arrowLength, arrowRadius: arrowRadius, coneHeight: coneHeight, coneRadius: coneRadius)
        xAxis.name = "gizmo_x"
        gizmo.addChild(xAxis)
        
        let yAxis = createModernArrow(axis: [0, 1, 0], color: yColor, length: arrowLength, arrowRadius: arrowRadius, coneHeight: coneHeight, coneRadius: coneRadius)
        yAxis.name = "gizmo_y"
        gizmo.addChild(yAxis)
        
        let zAxis = createModernArrow(axis: [0, 0, 1], color: zColor, length: arrowLength, arrowRadius: arrowRadius, coneHeight: coneHeight, coneRadius: coneRadius)
        zAxis.name = "gizmo_z"
        gizmo.addChild(zAxis)
        
        let centerSphere = ModelEntity(mesh: .generateSphere(radius: 0.025))
        var centerMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1.0))
        centerSphere.model?.materials = [centerMaterial]
        centerSphere.name = "gizmo_center"
        let collisionShape = ShapeResource.generateSphere(radius: 0.06)
        centerSphere.components.set(CollisionComponent(shapes: [collisionShape]))
        centerSphere.components.set(InputTargetComponent())
        gizmo.addChild(centerSphere)
    }
    
    private func createModernArrow(axis: SIMD3<Float>, color: UIColor, length: Float, arrowRadius: Float, coneHeight: Float, coneRadius: Float) -> Entity {
        let axisEntity = Entity()
        
        let cylinderMesh = MeshResource.generateCylinder(height: length * 0.75, radius: arrowRadius)
        var cylinderMaterial = UnlitMaterial(color: color)
        let cylinder = ModelEntity(mesh: cylinderMesh, materials: [cylinderMaterial])
        cylinder.position = axis * (length * 0.375)
        cylinder.look(at: axis * length, from: [0, 0, 0], relativeTo: axisEntity)
        axisEntity.addChild(cylinder)
        
        let coneMesh = MeshResource.generateCone(height: coneHeight, radius: coneRadius)
        var coneMaterial = UnlitMaterial(color: color)
        let cone = ModelEntity(mesh: coneMesh, materials: [coneMaterial])
        cone.position = axis * (length * 0.75 + coneHeight * 0.5)
        cone.look(at: axis * (length + coneHeight), from: axis * length, relativeTo: axisEntity)
        axisEntity.addChild(cone)
        
        let sphereMesh = MeshResource.generateSphere(radius: coneRadius * 0.7)
        var sphereMaterial = UnlitMaterial(color: color)
        let sphere = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
        sphere.position = axis * (length * 0.75 + coneHeight)
        axisEntity.addChild(sphere)
        
        let collisionShape = ShapeResource.generateSphere(radius: 0.06)
        axisEntity.components.set(CollisionComponent(shapes: [collisionShape]))
        axisEntity.components.set(InputTargetComponent())
        
        return axisEntity
    }
    
    private func createRotateGizmo(on gizmo: Entity, scale: Float) {
        let ringRadius: Float = scale * 0.9
        let ringThickness: Float = 0.008
        
        let xColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        let yColor = UIColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 1.0)
        let zColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        
        let xRing = createModernTorus(ringRadius: ringRadius, tubeRadius: ringThickness, color: xColor, axis: [1, 0, 0])
        xRing.name = "gizmo_x"
        gizmo.addChild(xRing)
        
        let yRing = createModernTorus(ringRadius: ringRadius, tubeRadius: ringThickness, color: yColor, axis: [0, 1, 0])
        yRing.name = "gizmo_y"
        gizmo.addChild(yRing)
        
        let zRing = createModernTorus(ringRadius: ringRadius, tubeRadius: ringThickness, color: zColor, axis: [0, 0, 1])
        zRing.name = "gizmo_z"
        gizmo.addChild(zRing)
        
        let centerSphere = ModelEntity(mesh: .generateSphere(radius: 0.02))
        var centerMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1.0))
        centerSphere.model?.materials = [centerMaterial]
        gizmo.addChild(centerSphere)
    }
    
    private func createModernTorus(ringRadius: Float, tubeRadius: Float, color: UIColor, axis: SIMD3<Float>) -> Entity {
        let torusEntity = Entity()
        
        let segments = 48
        
        for i in 0..<segments {
            let angle = Float(i) / Float(segments) * Float.pi * 2
            let nextAngle = Float(i + 1) / Float(segments) * Float.pi * 2
            
            let x1 = ringRadius * cos(angle)
            let z1 = ringRadius * sin(angle)
            let x2 = ringRadius * cos(nextAngle)
            let z2 = ringRadius * sin(nextAngle)
            
            let p1 = SIMD3<Float>(x1, 0, z1)
            let p2 = SIMD3<Float>(x2, 0, z2)
            
            let line = createLine(from: p1, to: p2, thickness: tubeRadius, color: color)
            torusEntity.addChild(line)
        }
        
        let indicatorAngle: Float = 0
        let indicatorX = ringRadius * cos(indicatorAngle)
        let indicatorZ = ringRadius * sin(indicatorAngle)
        let indicatorPos = SIMD3<Float>(indicatorX, 0, indicatorZ)
        
        let indicatorSphere = ModelEntity(mesh: .generateSphere(radius: tubeRadius * 2.5))
        var indicatorMaterial = UnlitMaterial(color: color)
        indicatorSphere.model?.materials = [indicatorMaterial]
        indicatorSphere.position = indicatorPos
        torusEntity.addChild(indicatorSphere)
        
        if axis.x != 0 {
            torusEntity.orientation = simd_quatf(angle: Float.pi / 2, axis: [0, 0, 1])
        } else if axis.z != 0 {
            torusEntity.orientation = simd_quatf(angle: Float.pi / 2, axis: [1, 0, 0])
        }
        
        let collisionShape = ShapeResource.generateSphere(radius: 0.06)
        torusEntity.components.set(CollisionComponent(shapes: [collisionShape]))
        torusEntity.components.set(InputTargetComponent())
        
        return torusEntity
    }
    
    private func createScaleGizmo(on gizmo: Entity, scale: Float) {
        let handleSize: Float = 0.05
        let handleLength: Float = scale * 0.8
        
        let xColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        let yColor = UIColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 1.0)
        let zColor = UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 1.0)
        let centerColor = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        
        let xHandle = createModernScaleHandle(axis: [1, 0, 0], color: xColor, length: handleLength, size: handleSize)
        xHandle.name = "gizmo_x"
        gizmo.addChild(xHandle)
        
        let yHandle = createModernScaleHandle(axis: [0, 1, 0], color: yColor, length: handleLength, size: handleSize)
        yHandle.name = "gizmo_y"
        gizmo.addChild(yHandle)
        
        let zHandle = createModernScaleHandle(axis: [0, 0, 1], color: zColor, length: handleLength, size: handleSize)
        zHandle.name = "gizmo_z"
        gizmo.addChild(zHandle)
        
        let centerBox = ModelEntity(mesh: .generateBox(size: handleSize * 1.3))
        var centerMaterial = UnlitMaterial(color: centerColor)
        centerBox.model?.materials = [centerMaterial]
        centerBox.name = "gizmo_center"
        let collisionShape = ShapeResource.generateSphere(radius: 0.06)
        centerBox.components.set(CollisionComponent(shapes: [collisionShape]))
        centerBox.components.set(InputTargetComponent())
        gizmo.addChild(centerBox)
    }
    
    private func createModernScaleHandle(axis: SIMD3<Float>, color: UIColor, length: Float, size: Float) -> Entity {
        let handleEntity = Entity()
        
        let line = createLine(from: [0, 0, 0], to: axis * length * 0.8, thickness: 0.012, color: color)
        handleEntity.addChild(line)
        
        let box = ModelEntity(mesh: .generateBox(size: size))
        var boxMaterial = UnlitMaterial(color: color)
        box.model?.materials = [boxMaterial]
        box.position = axis * length * 0.8
        handleEntity.addChild(box)
        
        let smallSphere = ModelEntity(mesh: .generateSphere(radius: size * 0.4))
        var sphereMaterial = UnlitMaterial(color: color)
        smallSphere.model?.materials = [sphereMaterial]
        smallSphere.position = axis * length * 0.95
        handleEntity.addChild(smallSphere)
        
        let collisionShape = ShapeResource.generateSphere(radius: 0.06)
        handleEntity.components.set(CollisionComponent(shapes: [collisionShape]))
        handleEntity.components.set(InputTargetComponent())
        
        return handleEntity
    }
    
    private func handleDragChange(_ value: DragGesture.Value) {
        guard selectedTool == .select, let selected = selectedObject, let entity = entityCache[selected.id] else { return }
        
        if activeGizmoAxis == nil {
            initialDragPosition = SIMD3<Float>(Float(value.translation.width), Float(value.translation.height), 0)
            initialObjectTransform = (
                position: entity.position,
                rotation: entity.orientation,
                scale: entity.scale
            )
        }
        
        guard let axis = activeGizmoAxis, let initial = initialObjectTransform else { return }
        
        let deltaX = Float(value.translation.width - Double(initialDragPosition!.x))
        let deltaY = Float(value.translation.height - Double(initialDragPosition!.y))
        
        switch transformMode {
        case .move:
            var newPosition = initial.position
            
            switch axis {
            case .x:
                newPosition.x += deltaX * 0.005
            case .y:
                newPosition.y -= deltaY * 0.005
            case .z:
                newPosition.z += deltaX * 0.005
            case .all:
                newPosition.x += deltaX * 0.005
                newPosition.y -= deltaY * 0.005
            }
            
            DispatchQueue.main.async {
                if let index = self.objects.firstIndex(where: { $0.id == selected.id }) {
                    self.objects[index].position = newPosition
                    self.selectedObject = self.objects[index]
                    self.onObjectTransform(self.objects[index])
                    self.gizmoEntity?.position = newPosition
                }
            }
            
        case .rotate:
            var newRotation = initial.rotation
            
            switch axis {
            case .x:
                let rotX = simd_quatf(angle: deltaY * 0.01, axis: [1, 0, 0])
                newRotation = rotX * newRotation
            case .y:
                let rotY = simd_quatf(angle: deltaX * 0.01, axis: [0, 1, 0])
                newRotation = rotY * newRotation
            case .z:
                let rotZ = simd_quatf(angle: deltaX * 0.01, axis: [0, 0, 1])
                newRotation = rotZ * newRotation
            case .all:
                let rotX = simd_quatf(angle: deltaY * 0.01, axis: [1, 0, 0])
                let rotY = simd_quatf(angle: deltaX * 0.01, axis: [0, 1, 0])
                newRotation = rotY * rotX * newRotation
            }
            
            DispatchQueue.main.async {
                if let index = self.objects.firstIndex(where: { $0.id == selected.id }) {
                    let euler = newRotation.eulerAngles
                    self.objects[index].rotation = SIMD3<Float>(euler.x, euler.y, euler.z)
                    self.selectedObject = self.objects[index]
                    self.onObjectTransform(self.objects[index])
                }
            }
            
        case .scale:
            var newScale = initial.scale
            let scaleFactor: Float = 1.0 + (deltaX + deltaY) * 0.002
            
            switch axis {
            case .x:
                newScale.x = initial.scale.x * scaleFactor
            case .y:
                newScale.y = initial.scale.y * scaleFactor
            case .z:
                newScale.z = initial.scale.z * scaleFactor
            case .all:
                newScale = initial.scale * scaleFactor
            }
            
            newScale = simd_clamp(newScale, SIMD3<Float>(0.1, 0.1, 0.1), SIMD3<Float>(10, 10, 10))
            
            DispatchQueue.main.async {
                if let index = self.objects.firstIndex(where: { $0.id == selected.id }) {
                    self.objects[index].scale = newScale
                    self.selectedObject = self.objects[index]
                    self.onObjectTransform(self.objects[index])
                }
            }
        }
    }
    
    private func handleDragEnd() {
        DispatchQueue.main.async {
            self.activeGizmoAxis = nil
            self.initialDragPosition = nil
            self.initialObjectTransform = nil
        }
    }
}

enum GizmoAxis {
    case x, y, z, all
}

extension simd_quatf {
    var eulerAngles: SIMD3<Float> {
        let sinr_cosp = 2 * (self.vector.w * self.vector.x + self.vector.y * self.vector.z)
        let cosr_cosp = 1 - 2 * (self.vector.x * self.vector.x + self.vector.y * self.vector.y)
        let roll = atan2(sinr_cosp, cosr_cosp)
        
        let sinp = 2 * (self.vector.w * self.vector.y - self.vector.z * self.vector.x)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(Float.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }
        
        let siny_cosp = 2 * (self.vector.w * self.vector.z + self.vector.x * self.vector.y)
        let cosy_cosp = 1 - 2 * (self.vector.y * self.vector.y + self.vector.z * self.vector.z)
        let yaw = atan2(siny_cosp, cosy_cosp)
        
        return SIMD3<Float>(roll, pitch, yaw)
    }
}

struct CameraControlHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("单指拖动旋转视角", systemImage: "hand.draw")
            Label("双指捏合缩放", systemImage: "arrow.up.left.and.arrow.down.right")
            Label("双指拖动平移", systemImage: "hand.tap")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

struct SelectionModeHint: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择模式")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("点击模型进行选中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("再次点击「选择」按钮退出选择模式")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(4)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}
