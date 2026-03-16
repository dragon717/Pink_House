//
//  OOTDCoordinateMigrationService.swift
//  ItemManager
//
//  OOTD坐标版本迁移服务
//  将老数据（version=1，绝对坐标）迁移为新数据（version=2，相对坐标）
//

import Foundation
import SwiftData

/// OOTD坐标迁移服务
/// 在App启动时执行，将老数据的绝对坐标转换为相对坐标
class OOTDCoordinateMigrationService {
    static let shared = OOTDCoordinateMigrationService()
    
    private let canvasWidth: Double = 1080.0
    private let canvasHeight: Double = 1440.0
    
    /// 检查并执行迁移
    /// - Parameter modelContext: SwiftData 上下文
    func migrateIfNeeded(modelContext: ModelContext) async {
        print("[OOTD Migration] 开始检查坐标版本迁移...")
        
        do {
            // 获取所有需要迁移的 OutfitItem（version=1 的）
            let descriptor = FetchDescriptor<OutfitItem>(
                predicate: #Predicate { $0.coordinateVersion == 1 }
            )
            let itemsToMigrate = try modelContext.fetch(descriptor)
            
            guard !itemsToMigrate.isEmpty else {
                print("[OOTD Migration] 没有需要迁移的数据")
                return
            }
            
            print("[OOTD Migration] 发现 \(itemsToMigrate.count) 条需要迁移的数据")
            
            // 执行迁移
            for item in itemsToMigrate {
                // 将绝对坐标转换为相对坐标
                let oldX = item.x
                let oldY = item.y
                
                item.x = oldX / canvasWidth
                item.y = oldY / canvasHeight
                item.coordinateVersion = 2
                
                print("[OOTD Migration] 迁移 item \(item.id): (\(oldX), \(oldY)) -> (\(item.x), \(item.y))")
            }
            
            // 保存更改
            try modelContext.save()
            print("[OOTD Migration] 迁移完成，共迁移 \(itemsToMigrate.count) 条数据")
            
        } catch {
            print("[OOTD Migration] 迁移失败: \(error)")
        }
    }
}
