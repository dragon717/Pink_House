import Foundation
import SwiftData
import simd

@Model
final class SceneObjectData {
    @Attribute(.unique) var id: UUID = UUID()
    
    var objectType: String = "usdzModel"
    
    var positionX: Double = 0.0
    var positionY: Double = 0.0
    var positionZ: Double = 0.0
    
    var rotationX: Double = 0.0
    var rotationY: Double = 0.0
    var rotationZ: Double = 0.0
    
    var scaleX: Double = 1.0
    var scaleY: Double = 1.0
    var scaleZ: Double = 1.0
    
    var usdzModelPath: String? = nil
    
    var colorR: Double = 0.8
    var colorG: Double = 0.8
    var colorB: Double = 0.8
    var colorA: Double = 1.0
    
    var sortIndex: Int = 0
    
    @Relationship(deleteRule: .cascade)
    var spaceOutfit: SpaceOutfit?
    
    init(
        id: UUID = UUID(),
        objectType: String = "usdzModel",
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        usdzModelPath: String? = nil,
        color: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.8, 1.0),
        sortIndex: Int = 0,
        spaceOutfit: SpaceOutfit? = nil
    ) {
        self.id = id
        self.objectType = objectType
        self.positionX = Double(position.x)
        self.positionY = Double(position.y)
        self.positionZ = Double(position.z)
        self.rotationX = Double(rotation.x)
        self.rotationY = Double(rotation.y)
        self.rotationZ = Double(rotation.z)
        self.scaleX = Double(scale.x)
        self.scaleY = Double(scale.y)
        self.scaleZ = Double(scale.z)
        self.usdzModelPath = usdzModelPath
        self.colorR = Double(color.x)
        self.colorG = Double(color.y)
        self.colorB = Double(color.z)
        self.colorA = Double(color.w)
        self.sortIndex = sortIndex
        self.spaceOutfit = spaceOutfit
    }
    
    var position: SIMD3<Float> {
        get { SIMD3<Float>(Float(positionX), Float(positionY), Float(positionZ)) }
        set {
            positionX = Double(newValue.x)
            positionY = Double(newValue.y)
            positionZ = Double(newValue.z)
        }
    }
    
    var rotation: SIMD3<Float> {
        get { SIMD3<Float>(Float(rotationX), Float(rotationY), Float(rotationZ)) }
        set {
            rotationX = Double(newValue.x)
            rotationY = Double(newValue.y)
            rotationZ = Double(newValue.z)
        }
    }
    
    var scale: SIMD3<Float> {
        get { SIMD3<Float>(Float(scaleX), Float(scaleY), Float(scaleZ)) }
        set {
            scaleX = Double(newValue.x)
            scaleY = Double(newValue.y)
            scaleZ = Double(newValue.z)
        }
    }
    
    var color: SIMD4<Float> {
        get { SIMD4<Float>(Float(colorR), Float(colorG), Float(colorB), Float(colorA)) }
        set {
            colorR = Double(newValue.x)
            colorG = Double(newValue.y)
            colorB = Double(newValue.z)
            colorA = Double(newValue.w)
        }
    }
    
    func toSceneObject() -> SceneObject {
        let type: SceneObjectType
        switch objectType {
        case "primitive": type = .primitive
        default: type = .usdzModel
        }
        
        return SceneObject(
            id: id,
            type: type,
            position: position,
            rotation: rotation,
            scale: scale,
            usdzModelPath: usdzModelPath,
            color: color
        )
    }
    
    func update(from object: SceneObject) {
        self.objectType = object.type == .primitive ? "primitive" : "usdzModel"
        self.position = object.position
        self.rotation = object.rotation
        self.scale = object.scale
        self.usdzModelPath = object.usdzModelPath
        self.color = object.color
    }
}

extension SpaceOutfit {
    var sceneObjects: [SceneObjectData] {
        return []
    }
}
