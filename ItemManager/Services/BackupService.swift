//
//  BackupService.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/25/26.
//

import Foundation
import SwiftData

// MARK: - Backup Service

@MainActor
class BackupService {
    static let shared = BackupService()
    
    enum BackupError: Error, LocalizedError {
        case dataFetchFailed
        case fileCreateFailed
        case imageNotFound(String)
        case archiveFailed
        case invalidArchive
        case compressionFailed
        case decompressionFailed(reason: String)
        case unknownFormat
        case corruptedArchive(reason: String)
        
        var errorDescription: String? {
            switch self {
            case .dataFetchFailed: return "获取数据失败"
            case .fileCreateFailed: return "创建文件失败"
            case .imageNotFound(let name): return "找不到图片: \(name)"
            case .archiveFailed: return "打包存档失败"
            case .invalidArchive: return "无效的备份文件 (找不到 manifest.json)"
            case .compressionFailed: return "压缩失败"
            case .decompressionFailed(let reason): return "解压失败: \(reason)"
            case .unknownFormat: return "无法识别的文件格式。请确保选择的是有效的 .save 或 .json 备份文件。"
            case .corruptedArchive(let reason): return "备份文件已损坏: \(reason)"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Internal Helpers
    
    nonisolated func processByIDs<T: PersistentModel, ResultType>(
        context: ModelContext,
        descriptor: FetchDescriptor<T>,
        entityName: String,
        process: (T) -> ResultType?
    ) throws -> [ResultType] {
        print("### Export: Fetching IDs for \(entityName)...")
        
        context.processPendingChanges()
        
        var safeDescriptor = descriptor
        safeDescriptor.includePendingChanges = false
        
        let allItems = try context.fetch(safeDescriptor)
        let totalCount = allItems.count
        print("### Export: Found \(totalCount) \(entityName) items (Excl. Pending). Starting processing...")
        
        var results: [ResultType] = []
        var successCount = 0
        var failCount = 0
        
        for (index, item) in allItems.enumerated() {
            if index > 0 && index % 100 == 0 {
                print("### Export \(entityName): Processed \(index)/\(totalCount)...")
            }
            
            let id = item.persistentModelID
            
            do {
                guard let safeItem = try context.model(for: id) as? T else {
                    print("### Export \(entityName): 跳过无法加载的对象 (Index: \(index), ID: \(id))")
                    failCount += 1
                    continue
                }
                
                if safeItem.isDeleted {
                    failCount += 1
                    continue
                }
                
                if let result = process(safeItem) {
                    results.append(result)
                    successCount += 1
                } else {
                    failCount += 1
                }
            } catch {
                print("### Export \(entityName): 捕获到失效对象 (ID: \(id)). 已跳过。错误: \(error)")
                failCount += 1
                continue
            }
        }
        
        print("### Export \(entityName): Finished. Success: \(successCount), Skipped/Failed: \(failCount)")
        return results
    }
}
