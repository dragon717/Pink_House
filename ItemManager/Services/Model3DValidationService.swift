//
//  Model3DValidationService.swift
//  ItemManager
//
//  3D模型引用验证服务 - App初始化时检查模型引用完整性
//

import Foundation
import SwiftData

@MainActor
class Model3DValidationService {
    static let shared = Model3DValidationService()
    
    private let validationKey = "Model3DValidationCompleted_v1"
    
    private init() {}
    
    /// 验证模型引用完整性
    /// - 清理指向已删除模型的 SceneObjectData
    /// - 验证模型文件是否存在
    /// - 修复损坏的引用关系
    func validateIfNeeded(modelContainer: ModelContainer) async {
        let defaults = UserDefaults.standard
        // 每次启动都验证，不跳过
        // if defaults.bool(forKey: validationKey) {
        //     print("[Model3DValidation] 验证已完成，跳过")
        //     return
        // }
        
        print("[Model3DValidation] 开始验证 3D 模型引用完整性...")
        
        let context = modelContainer.mainContext
        
        do {
            // 1. 清理指向已删除模型的 SceneObjectData 引用
            try await cleanupDeletedModelReferences(context: context)
            
            // 2. 验证模型文件是否存在
            try await validateModelFiles(context: context)
            
            // 3. 清理孤立的 SceneObjectData（指向不存在的模型）
            try await cleanupOrphanedSceneObjects(context: context)
            
            defaults.set(true, forKey: validationKey)
            
            print("[Model3DValidation] 验证完成！")
            
        } catch {
            print("[Model3DValidation] 验证失败: \(error)")
        }
    }
    
    /// 清理指向已删除模型的 SceneObjectData 引用
    private func cleanupDeletedModelReferences(context: ModelContext) async throws {
        let descriptor = FetchDescriptor<SceneObjectData>()
        let allObjects = try context.fetch(descriptor)
        
        var cleanedCount = 0
        
        for object in allObjects {
            // 检查关联的 Model3D 是否已被软删除
            if let model3D = object.model3D, model3D.isDeleted {
                // 断开引用关系
                object.model3D = nil
                cleanedCount += 1
                print("[Model3DValidation] 清理已删除模型的引用: SceneObjectData \(object.id) -> Model3D \(model3D.id)")
            }
        }
        
        if cleanedCount > 0 {
            try context.save()
            print("[Model3DValidation] 清理了 \(cleanedCount) 个指向已删除模型的引用")
        }
    }
    
    /// 验证模型文件是否存在
    private func validateModelFiles(context: ModelContext) async throws {
        let descriptor = FetchDescriptor<Model3D>(
            predicate: #Predicate<Model3D> { $0.isDeleted == false }
        )
        let models = try context.fetch(descriptor)
        
        var missingCount = 0
        
        for model in models {
            if let resolvedPath = model.resolvedModelPath {
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: resolvedPath) {
                    missingCount += 1
                    print("[Model3DValidation] 模型文件不存在: \(model.name) (ID: \(model.id))")
                    
                    // 标记为已删除（软删除）
                    model.isDeleted = true
                    model.deletedAt = Date()
                }
            }
        }
        
        if missingCount > 0 {
            try context.save()
            print("[Model3DValidation] 标记了 \(missingCount) 个文件丢失的模型为已删除")
        }
    }
    
    /// 清理孤立的 SceneObjectData（指向不存在的模型）
    private func cleanupOrphanedSceneObjects(context: ModelContext) async throws {
        let descriptor = FetchDescriptor<SceneObjectData>()
        let allObjects = try context.fetch(descriptor)
        
        // 获取所有未删除的 SpaceOutfit
        let outfitDescriptor = FetchDescriptor<SpaceOutfit>(
            predicate: #Predicate<SpaceOutfit> { $0.deletedAt == nil }
        )
        let activeOutfitIDs = Set((try? context.fetch(outfitDescriptor))?.map { $0.id } ?? [])
        
        var orphanedCount = 0
        
        for object in allObjects {
            // 检查是否指向不存在的模型且没有有效的模型路径
            let hasValidModelRef = object.model3D != nil && object.model3D?.isDeleted == false
            let hasValidPath = object.resolvedModelPath != nil && ModelPathManager.shared.fileExists(object.resolvedModelPath)
            
            // 如果既没有有效模型引用，也没有有效路径，且属于活跃场景，则标记为需要关注
            if !hasValidModelRef && !hasValidPath && activeOutfitIDs.contains(object.spaceOutfitID ?? UUID()) {
                orphanedCount += 1
                print("[Model3DValidation] 发现孤立场景对象: \(object.id), type: \(object.objectType)")
            }
        }
        
        if orphanedCount > 0 {
            print("[Model3DValidation] 发现 \(orphanedCount) 个孤立的场景对象（建议手动检查）")
        }
    }
    
    /// 获取模型的引用计数（活跃场景中）
    func getModelReferenceCount(modelID: UUID, context: ModelContext) -> Int {
        do {
            // 获取所有未删除的 SpaceOutfit ID
            let outfitDescriptor = FetchDescriptor<SpaceOutfit>(
                predicate: #Predicate<SpaceOutfit> { $0.deletedAt == nil }
            )
            let activeOutfitIDs = Set((try? context.fetch(outfitDescriptor))?.map { $0.id } ?? [])
            
            // 获取所有 SceneObjectData
            let descriptor = FetchDescriptor<SceneObjectData>()
            let allObjects = try context.fetch(descriptor)
            
            // 统计活跃场景中的引用
            return allObjects.filter { 
                $0.model3D?.id == modelID && 
                activeOutfitIDs.contains($0.spaceOutfitID ?? UUID())
            }.count
        } catch {
            print("[Model3DValidation] 获取引用计数失败: \(error)")
            return 0
        }
    }
    
    /// 检查模型是否可以安全删除（没有被任何活跃场景引用）
    func canSafelyDelete(modelID: UUID, context: ModelContext) -> Bool {
        return getModelReferenceCount(modelID: modelID, context: context) == 0
    }
}
