
//
//  Model3D.swift
//  ItemManager
//
//  独立的3D模型数据模型
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Model3D {
    @Attribute(.unique) var id: UUID = UUID()
    
    var name: String = ""
    var types: String = ""
    
    var modelPath: String? = nil
    var modelType: String? = nil
    var thumbnailPath: String? = nil
    var sourceImagePaths: [String] = []
    
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    var sortIndex: Int = 0
    
    var cameraPositionX: Float = 0
    var cameraPositionY: Float = 0
    var cameraPositionZ: Float = 3
    var cameraRotationX: Float = 0
    var cameraRotationY: Float = 0
    var cameraRotationZ: Float = 0
    
    init(
        name: String,
        types: String = "3D模型",
        modelPath: String? = nil,
        modelType: String? = nil,
        thumbnailPath: String? = nil,
        sourceImagePaths: [String] = [],
        sortIndex: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.types = types
        self.modelPath = modelPath
        self.modelType = modelType
        self.thumbnailPath = thumbnailPath
        self.sourceImagePaths = sourceImagePaths
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortIndex = sortIndex
        self.cameraPositionX = 0
        self.cameraPositionY = 0
        self.cameraPositionZ = 3
        self.cameraRotationX = 0
        self.cameraRotationY = 0
        self.cameraRotationZ = 0
    }
}

extension Model3D {
    var resolvedModelPath: String? {
        return ModelPathManager.shared.resolvePath(modelPath)
    }
    
    var resolvedModelDirectory: URL? {
        guard let resolvedPath = resolvedModelPath else { return nil }
        let fileURL = URL(fileURLWithPath: resolvedPath)
        return fileURL.deletingLastPathComponent()
    }
    
    func setModelPath(_ absolutePath: String?) {
        modelPath = ModelPathManager.shared.storePath(absolutePath)
    }
    
    var resolvedThumbnailPath: String? {
        return ModelPathManager.shared.resolvePath(thumbnailPath)
    }
    
    func setThumbnailPath(_ absolutePath: String?) {
        thumbnailPath = ModelPathManager.shared.storePath(absolutePath)
    }
    
    var resolvedSourceImagePaths: [String] {
        return sourceImagePaths.compactMap { ModelPathManager.shared.resolvePath($0) }
    }
    
    var modelTypeDescription: String? {
        guard modelPath != nil else { return nil }
        switch modelType {
        case "multi": return "3D"
        case "single": return "单向"
        default: return "3D"
        }
    }
    
    var cameraPosition: SIMD3<Float> {
        get {
            SIMD3<Float>(cameraPositionX, cameraPositionY, cameraPositionZ)
        }
        set {
            cameraPositionX = newValue.x
            cameraPositionY = newValue.y
            cameraPositionZ = newValue.z
        }
    }
    
    var cameraRotation: SIMD3<Float> {
        get {
            SIMD3<Float>(cameraRotationX, cameraRotationY, cameraRotationZ)
        }
        set {
            cameraRotationX = newValue.x
            cameraRotationY = newValue.y
            cameraRotationZ = newValue.z
        }
    }
}
