
//
//  Model3DMigrationService.swift
//  ItemManager
//
//  3D模型数据迁移服务 - 将旧的 Clothing 中的 3D 模型迁移到 Model3D
//

import Foundation
import SwiftData

@MainActor
class Model3DMigrationService {
    static let shared = Model3DMigrationService()
    
    private let migrationKey = "Model3DMigrationCompleted"
    
    private init() {}
    
    func migrateIfNeeded(modelContainer: ModelContainer) async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationKey) {
            print("[Model3DMigration] 迁移已完成，跳过")
            return
        }
        
        print("[Model3DMigration] 开始迁移 3D 模型数据...")
        
        let context = modelContainer.mainContext
        
        do {
            let clothingWith3D = try context.fetch(
                FetchDescriptor<Clothing>(
                    predicate: #Predicate<Clothing> { $0.deletedAt == nil && $0.model3DPath != nil }
                )
            )
            
            print("[Model3DMigration] 找到 \(clothingWith3D.count) 个包含 3D 模型的 Clothing")
            
            var migratedCount = 0
            
            for clothing in clothingWith3D {
                let model3D = Model3D(
                    name: clothing.name,
                    types: clothing.types,
                    modelPath: clothing.model3DPath,
                    modelType: clothing.model3DType,
                    thumbnailPath: clothing.model3DThumbnailPath,
                    sourceImagePaths: clothing.imagePaths,
                    sortIndex: clothing.sortIndex
                )
                model3D.createdAt = clothing.createdAt
                model3D.updatedAt = clothing.updatedAt
                
                context.insert(model3D)
                migratedCount += 1
                
                print("[Model3DMigration] 迁移模型: \(clothing.name)")
            }
            
            try context.save()
            
            defaults.set(true, forKey: migrationKey)
            
            print("[Model3DMigration] 迁移完成！共迁移 \(migratedCount) 个模型")
            
        } catch {
            print("[Model3DMigration] 迁移失败: \(error)")
        }
    }
}
