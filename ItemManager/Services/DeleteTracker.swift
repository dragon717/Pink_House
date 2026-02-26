import Foundation
import SwiftData
import CoreData
import SwiftUI

/// 删除追踪器 - 基于时间戳的冲突解决方案
/// 核心思想：记录删除时间戳，在冲突时比较删除时间和数据修改时间
/// 注意：删除记录只保存在本地，不同步到 iCloud，避免跨设备删除同步问题
@MainActor
final class DeleteTracker {
    static let shared = DeleteTracker()

    /// 本地 UserDefaults - 删除记录只保存在本地，不同步到 iCloud
    private let userDefaults = UserDefaults.standard

    /// 待处理的 ModelContext
    var pendingContext: ModelContext?

    // MARK: - Keys (使用新的 key 避免读取旧的 iCloud 同步记录)
    private let deletedOutfitsKey = "deletedOutfits_local"  // local: 只保存在本地
    private let deletedClothingsKey = "deletedClothings_local"
    private let deletedBookGroupsKey = "deletedBookGroups_local"
    private let deletedModel3DsKey = "deletedModel3Ds_local"
    private let deletedPerlerPatternsKey = "deletedPerlerPatterns_local"

    // MARK: - 初始化

    init() {
        // 不再监听 iCloud Key-Value Store 的变化，因为删除记录不再同步到 iCloud
        // 保留监听 SwiftData iCloud 同步完成事件，但主要用于其他用途
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistentStoreRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )
    }

    @objc private func persistentStoreRemoteChange(_ notification: Notification) {
        // iCloud 同步完成时的处理，但不再重新应用删除
        // 因为删除记录只保存在本地，不需要跨设备同步删除
    }

    // MARK: - 记录删除（带时间戳）

    func recordDeletedOutfit(id: UUID) {
        recordDelete(id: id, key: deletedOutfitsKey, typeName: "outfit")
    }

    func recordDeletedClothing(id: UUID) {
        recordDelete(id: id, key: deletedClothingsKey, typeName: "clothing")
    }

    func recordDeletedBookGroup(id: UUID) {
        recordDelete(id: id, key: deletedBookGroupsKey, typeName: "book group")
    }

    func recordDeletedModel3D(id: UUID) {
        recordDelete(id: id, key: deletedModel3DsKey, typeName: "3D model")
    }

    func recordDeletedPerlerPattern(id: UUID) {
        recordDelete(id: id, key: deletedPerlerPatternsKey, typeName: "perler pattern")
    }

    /// 记录删除 - 存储 UUID 和删除时间戳
    private func recordDelete(id: UUID, key: String, typeName: String) {
        let deleteTime = Date()
        var deletedRecords = getDeletedRecords(for: key)

        // 更新或添加删除记录
        deletedRecords[id.uuidString] = deleteTime.timeIntervalSince1970

        // 保存到本地和 iCloud
        saveDeletedRecords(records: deletedRecords, key: key)

        print("DeleteTracker: Recorded deleted \(typeName) \(id) at \(deleteTime)")
    }

    // MARK: - 获取删除记录

    func getDeletedOutfitRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedOutfitsKey)
    }

    func getDeletedClothingRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedClothingsKey)
    }

    func getDeletedBookGroupRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedBookGroupsKey)
    }

    func getDeletedModel3DRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedModel3DsKey)
    }

    func getDeletedPerlerPatternRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedPerlerPatternsKey)
    }

    /// 获取删除记录 [UUID: 删除时间戳]
    /// 只从本地 UserDefaults 读取，不再从 iCloud 读取
    private func getDeletedRecords(for key: String) -> [String: Double] {
        return userDefaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    /// 获取格式化的删除记录 [UUID: Date]
    private func getDeletedDates(for key: String) -> [UUID: Date] {
        let records = getDeletedRecords(for: key)
        var result: [UUID: Date] = [:]
        for (idString, timestamp) in records {
            if let uuid = UUID(uuidString: idString) {
                result[uuid] = Date(timeIntervalSince1970: timestamp)
            }
        }
        return result
    }

    /// 保存删除记录
    /// 只保存到本地 UserDefaults，不同步到 iCloud
    private func saveDeletedRecords(records: [String: Double], key: String) {
        userDefaults.set(records, forKey: key)
        // 不再同步到 iCloud，避免跨设备删除同步问题
    }

    // MARK: - 应用删除（基于时间戳比较）

    func applyDeletedOutfits(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedOutfitsKey,
            typeName: "outfit",
            clearRecords: clearRecords
        ) { (item: Outfit, deleteTime: Date) -> Bool in
            // 强制删除策略：只要在删除记录中，就强制删除
            // 避免 iCloud 同步覆盖导致的删除失效
            if !item.isDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted outfit '\(item.note)'")
            } else {
                print("DeleteTracker: ✓ Outfit '\(item.note)' already deleted")
            }
            return true
        }
    }

    func applyDeletedClothings(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedClothingsKey,
            typeName: "clothing",
            clearRecords: clearRecords
        ) { (item: Clothing, deleteTime: Date) -> Bool in
            // 强制删除策略：只要在删除记录中，就强制删除
            if !item.isDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted clothing '\(item.name)'")
            } else {
                print("DeleteTracker: ✓ Clothing '\(item.name)' already deleted")
            }
            return true
        }
    }

    func applyDeletedBookGroups(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedBookGroupsKey,
            typeName: "book group",
            clearRecords: clearRecords
        ) { (item: BookGroup, deleteTime: Date) -> Bool in
            // 强制删除策略：只要在删除记录中，就强制删除
            if !item.isDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted book group '\(item.title)'")
            } else {
                print("DeleteTracker: ✓ Book group '\(item.title)' already deleted")
            }
            return true
        }
    }

    func applyDeletedModel3Ds(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedModel3DsKey,
            typeName: "3D model",
            clearRecords: clearRecords
        ) { (item: Model3D, deleteTime: Date) -> Bool in
            // 强制删除策略：只要在删除记录中，就强制删除
            if !item.isDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted 3D model '\(item.name)'")
            } else {
                print("DeleteTracker: ✓ 3D model '\(item.name)' already deleted")
            }
            return true
        }
    }

    func applyDeletedPerlerPatterns(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedPerlerPatternsKey,
            typeName: "perler pattern",
            clearRecords: clearRecords
        ) { (item: PerlerBeadPattern, deleteTime: Date) -> Bool in
            let itemModifiedTime = item.lastModified
            let timeDiff = deleteTime.timeIntervalSince(itemModifiedTime)

            print("DeleteTracker: [\(item.name)] deleteTime:\(deleteTime), lastModified:\(itemModifiedTime), diff:\(timeDiff)s, isDeleted:\(item.isDeleted)")

            // 策略：如果项目在删除记录中，强制删除（不管时间戳）
            // 因为 iCloud 同步可能会在 DeleteTracker 之前更新 lastModified
            if !item.isDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted '\(item.name)' (in delete record)")
            } else {
                print("DeleteTracker: ✓ Already deleted '\(item.name)'")
            }
            return true
        }
    }

    /// 通用的应用删除方法
    private func applyDeletedItems<T: PersistentModel>(
        context: ModelContext,
        key: String,
        typeName: String,
        shouldDelete: (T, Date) -> Bool,
        clearRecords: Bool = true
    ) {
        let deletedRecords = getDeletedDates(for: key)
        guard !deletedRecords.isEmpty else {
            print("DeleteTracker: No deleted \(typeName) records found")
            return
        }

        print("DeleteTracker: Checking \(deletedRecords.count) deleted \(typeName)(s), IDs: \(Array(deletedRecords.keys).map { $0.uuidString.prefix(8) })")

        do {
            let descriptor = FetchDescriptor<T>()
            let allItems = try context.fetch(descriptor)
            
            print("DeleteTracker: Fetched \(allItems.count) \(typeName)(s) from database")

            var appliedCount = 0
            var clearedRecords: [UUID] = []

            for item in allItems {
                // 获取该 item 的 ID
                guard let itemID = getItemID(item) else {
                    print("DeleteTracker: Warning - Could not get ID for \(typeName)")
                    continue
                }

                if let deleteTime = deletedRecords[itemID] {
                    print("DeleteTracker: Found matching record for \(typeName) ID:\(itemID.uuidString.prefix(8))")
                    if shouldDelete(item, deleteTime) {
                        appliedCount += 1
                        if clearRecords {
                            clearedRecords.append(itemID)
                        }
                    } else {
                        // 数据被修改过，清除删除记录
                        if clearRecords {
                            clearedRecords.append(itemID)
                        }
                    }
                } else {
                    // 检查是否是已删除的项目（ID不在记录中但isDeleted=true）
                    if let perlerPattern = item as? PerlerBeadPattern {
                        if perlerPattern.isDeleted {
                            print("DeleteTracker: \(typeName) '\(perlerPattern.name)' is already deleted (no record)")
                        }
                    }
                }
            }

            if appliedCount > 0 {
                do {
                    try context.save()
                    print("DeleteTracker: ✓ Saved \(appliedCount) \(typeName) deletes to database")
                    
                    // 立即再次保存，确保 iCloud 同步不会覆盖
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        do {
                            try context.save()
                            print("DeleteTracker: ✓ Re-saved \(appliedCount) \(typeName) deletes (anti-race)")
                        } catch {
                            print("DeleteTracker: ✗ Failed to re-save \(typeName) deletes: \(error)")
                        }
                    }
                } catch {
                    print("DeleteTracker: ✗ Failed to save \(typeName) deletes: \(error)")
                }
            } else {
                print("DeleteTracker: No \(typeName) deletes to apply")
            }

            // 清理已处理的删除记录（仅在启动时清理，同步后不清除）
            if clearRecords && !clearedRecords.isEmpty {
                clearProcessedRecords(ids: clearedRecords, key: key, typeName: typeName)
            }

        } catch {
            print("DeleteTracker: Failed to apply \(typeName) deletes: \(error)")
        }
    }

    /// 获取 PersistentModel 的 ID
    private func getItemID<T: PersistentModel>(_ item: T) -> UUID? {
        // 使用类型检查直接访问 id 属性
        if let outfit = item as? Outfit {
            return outfit.id
        } else if let clothing = item as? Clothing {
            return clothing.id
        } else if let bookGroup = item as? BookGroup {
            return bookGroup.id
        } else if let model3D = item as? Model3D {
            return model3D.id
        } else if let perlerPattern = item as? PerlerBeadPattern {
            return perlerPattern.id
        }
        return nil
    }

    /// 清理已处理的删除记录（保留24小时，防止iCloud同步延迟导致的问题）
    private func clearProcessedRecords(ids: [UUID], key: String, typeName: String) {
        guard !ids.isEmpty else { return }

        var records = getDeletedRecords(for: key)
        let beforeCount = records.count

        // 只清理超过24小时的记录，保留最近的删除记录以应对iCloud同步延迟
        let now = Date().timeIntervalSince1970
        let retentionPeriod: Double = 24 * 60 * 60  // 24小时

        for id in ids {
            if let timestamp = records[id.uuidString] {
                // 只清理超过24小时的记录
                if now - timestamp > retentionPeriod {
                    records.removeValue(forKey: id.uuidString)
                }
            }
        }

        let afterCount = records.count
        let clearedCount = beforeCount - afterCount

        if clearedCount > 0 {
            saveDeletedRecords(records: records, key: key)
            print("DeleteTracker: Cleared \(clearedCount) processed \(typeName) delete records (retained recent), \(afterCount) remaining")
        } else {
            print("DeleteTracker: Retained \(ids.count) recent \(typeName) delete records for iCloud sync protection")
        }
    }

    // MARK: - 清理记录

    func clearDeletedOutfits() {
        clearDeletedItems(key: deletedOutfitsKey, typeName: "outfit")
    }

    func clearDeletedClothings() {
        clearDeletedItems(key: deletedClothingsKey, typeName: "clothing")
    }

    func clearDeletedBookGroups() {
        clearDeletedItems(key: deletedBookGroupsKey, typeName: "book group")
    }

    func clearDeletedModel3Ds() {
        clearDeletedItems(key: deletedModel3DsKey, typeName: "3D model")
    }

    func clearDeletedPerlerPatterns() {
        clearDeletedItems(key: deletedPerlerPatternsKey, typeName: "perler pattern")
    }

    private func clearDeletedItems(key: String, typeName: String) {
        userDefaults.removeObject(forKey: key)
        // 不再清理 iCloud 中的记录，因为删除记录不再同步到 iCloud
        print("DeleteTracker: Cleared all \(typeName) delete records")
    }

    // MARK: - 移除单个删除记录（用于恢复操作）

    func removeDeletedOutfit(id: UUID) {
        removeDeletedID(id: id, key: deletedOutfitsKey, typeName: "outfit")
    }

    func removeDeletedClothing(id: UUID) {
        removeDeletedID(id: id, key: deletedClothingsKey, typeName: "clothing")
    }

    func removeDeletedBookGroup(id: UUID) {
        removeDeletedID(id: id, key: deletedBookGroupsKey, typeName: "book group")
    }

    func removeDeletedModel3D(id: UUID) {
        removeDeletedID(id: id, key: deletedModel3DsKey, typeName: "3D model")
    }

    func removeDeletedPerlerPattern(id: UUID) {
        removeDeletedID(id: id, key: deletedPerlerPatternsKey, typeName: "perler pattern")
    }

    private func removeDeletedID(id: UUID, key: String, typeName: String) {
        var records = getDeletedRecords(for: key)
        records.removeValue(forKey: id.uuidString)
        saveDeletedRecords(records: records, key: key)
        print("DeleteTracker: Removed \(typeName) \(id) from delete records")
    }

    // MARK: - 应用所有删除

    func applyAllDeletes(context: ModelContext, clearRecords: Bool = true) {
        print("DeleteTracker: Applying all tracked deletes with timestamp comparison...")

        // 保存 context
        pendingContext = context

        // 应用各类删除
        applyDeletedOutfits(context: context, clearRecords: clearRecords)
        applyDeletedClothings(context: context, clearRecords: clearRecords)
        applyDeletedModel3Ds(context: context, clearRecords: clearRecords)
        applyDeletedBookGroups(context: context, clearRecords: clearRecords)
        applyDeletedPerlerPatterns(context: context, clearRecords: clearRecords)

        print("DeleteTracker: Finished applying deletes")
    }

    // MARK: - 清除旧的 iCloud 同步记录（一次性清理）

    /// 清除旧的 iCloud 同步删除记录，防止之前同步到 iCloud 的记录继续影响当前设备
    /// 这个方法应该在应用升级后调用一次
    func clearOldICloudSyncRecords() {
        let iCloudStore = NSUbiquitousKeyValueStore.default
        let oldKeys = [
            "deletedOutfits_v2",
            "deletedClothings_v2",
            "deletedBookGroups_v2",
            "deletedModel3Ds_v2",
            "deletedPerlerPatterns_v2"
        ]

        for key in oldKeys {
            iCloudStore.removeObject(forKey: key)
        }
        iCloudStore.synchronize()
        print("DeleteTracker: 已清除旧的 iCloud 同步删除记录")
    }
}
