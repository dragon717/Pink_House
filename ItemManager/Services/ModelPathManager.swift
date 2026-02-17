//
//  ModelPathManager.swift
//  ItemManager
//
//  Created by AI Assistant on 2/16/26.
//

import Foundation

/// 管理模型路径的存储和解析
/// 将绝对路径转换为相对路径存储，避免 App 容器 UUID 变化导致文件找不到
class ModelPathManager {
    static let shared = ModelPathManager()
    
    private init() {}
    
    /// 存储路径的前缀标识
    private let relativePathPrefix = "[RELATIVE]"
    
    /// 将绝对路径转换为相对路径存储
    /// - Parameter absolutePath: 完整的绝对路径
    /// - Returns: 相对路径（以 [RELATIVE] 开头）
    func storePath(_ absolutePath: String?) -> String? {
        guard let absolutePath = absolutePath, !absolutePath.isEmpty else {
            return nil
        }
        
        // 如果已经是相对路径，直接返回
        if absolutePath.hasPrefix(relativePathPrefix) {
            return absolutePath
        }
        
        // 获取 Documents 目录路径
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return absolutePath // 无法获取 Documents 目录，返回原路径
        }
        
        let documentsPath = documentsDir.path
        
        // 如果路径在 Documents 目录下，转换为相对路径
        if absolutePath.hasPrefix(documentsPath) {
            let relativePath = String(absolutePath.dropFirst(documentsPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relativePathPrefix + relativePath
        }
        
        // 不在 Documents 目录下，返回原路径
        return absolutePath
    }
    
    /// 将存储的路径（可能是相对路径）转换为绝对路径
    /// - Parameter storedPath: 存储的路径（可能是相对或绝对）
    /// - Returns: 完整的绝对路径
    func resolvePath(_ storedPath: String?) -> String? {
        guard let storedPath = storedPath, !storedPath.isEmpty else {
            return nil
        }
        
        // 如果是带前缀的相对路径格式
        if storedPath.hasPrefix(relativePathPrefix) {
            let relativePath = String(storedPath.dropFirst(relativePathPrefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            
            return documentsDir.appendingPathComponent(relativePath).path
        }
        
        // 如果是简单相对路径（如 Models/xxx/thumbnail.jpg）
        if !storedPath.hasPrefix("/") && storedPath.contains("/") {
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return documentsDir.appendingPathComponent(storedPath).path
        }
        
        // 兼容旧数据：如果是旧版绝对路径，尝试提取相对部分
        if storedPath.contains("/Documents/") {
            let components = storedPath.components(separatedBy: "/Documents/")
            if components.count > 1 {
                let relativePart = components[1]
                guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    return storedPath // 无法转换，返回原路径
                }
                return documentsDir.appendingPathComponent(relativePart).path
            }
        }
        
        // 已经是绝对路径或无法转换，直接返回
        return storedPath
    }
    
    /// 检查存储的路径对应的文件是否存在
    /// - Parameter storedPath: 存储的路径
    /// - Returns: 文件是否存在
    func fileExists(_ storedPath: String?) -> Bool {
        guard let resolvedPath = resolvePath(storedPath) else {
            return false
        }
        return FileManager.default.fileExists(atPath: resolvedPath)
    }
    
    /// 获取存储路径对应的 URL
    /// - Parameter storedPath: 存储的路径
    /// - Returns: 文件 URL
    func resolveURL(_ storedPath: String?) -> URL? {
        guard let resolvedPath = resolvePath(storedPath) else {
            return nil
        }
        return URL(fileURLWithPath: resolvedPath)
    }
    
    /// 批量转换存储路径为绝对路径
    /// - Parameter storedPaths: 存储的路径数组
    /// - Returns: 有效的绝对路径数组
    func resolvePaths(_ storedPaths: [String]) -> [String] {
        return storedPaths.compactMap { resolvePath($0) }
    }
}

// MARK: - SwiftData Model 扩展

extension SceneObjectData {
    /// 设置模型路径（会自动转换为相对路径存储）
    func setModelPath(_ absolutePath: String?) {
        usdzModelPath = ModelPathManager.shared.storePath(absolutePath)
    }
}

extension SpaceOutfit {
    /// 获取解析后的模型路径（绝对路径）
    var resolvedModelPath: String? {
        return ModelPathManager.shared.resolvePath(modelPath)
    }
    
    /// 设置模型路径（会自动转换为相对路径存储）
    func setModelPath(_ absolutePath: String?) {
        modelPath = ModelPathManager.shared.storePath(absolutePath)
    }
    
    /// 检查模型文件是否存在
    var modelFileExists: Bool {
        return ModelPathManager.shared.fileExists(modelPath)
    }
}

extension Clothing {
    /// 获取解析后的 3D 模型路径（绝对路径）
    var resolvedModel3DPath: String? {
        return ModelPathManager.shared.resolvePath(model3DPath)
    }
    
    /// 设置 3D 模型路径（会自动转换为相对路径存储）
    func setModel3DPath(_ absolutePath: String?) {
        model3DPath = ModelPathManager.shared.storePath(absolutePath)
    }
    
    /// 检查 3D 模型文件是否存在
    var model3DFileExists: Bool {
        return ModelPathManager.shared.fileExists(model3DPath)
    }
    
    /// 获取解析后的缩略图路径（绝对路径）
    var resolvedModel3DThumbnailPath: String? {
        return ModelPathManager.shared.resolvePath(model3DThumbnailPath)
    }
    
    /// 获取解析后的源图片路径数组（绝对路径）
    var resolvedImagePaths: [String] {
        return imagePaths.compactMap { ModelPathManager.shared.resolvePath($0) }
    }
}
