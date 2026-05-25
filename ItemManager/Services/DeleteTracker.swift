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
    private let deletedSpaceBookGroupsKey = "deletedSpaceBookGroups_local"
    private let deletedSpaceOutfitsKey = "deletedSpaceOutfits_local"
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
        recordDeletes(ids: [id], key: deletedOutfitsKey, typeName: "outfit")
    }

    func recordDeletedOutfits(ids: [UUID]) {
        recordDeletes(ids: ids, key: deletedOutfitsKey, typeName: "outfit")
    }

    func recordDeletedClothing(id: UUID) {
        recordDeletes(ids: [id], key: deletedClothingsKey, typeName: "clothing")
    }

    func recordDeletedClothings(ids: [UUID]) {
        recordDeletes(ids: ids, key: deletedClothingsKey, typeName: "clothing")
    }

    func recordDeletedBookGroup(id: UUID) {
        recordDeletes(ids: [id], key: deletedBookGroupsKey, typeName: "book group")
    }

    func recordDeletedBookGroups(ids: [UUID]) {
        recordDeletes(ids: ids, key: deletedBookGroupsKey, typeName: "book group")
    }

    func recordDeletedSpaceBookGroup(id: UUID) {
        recordDeletes(ids: [id], key: deletedSpaceBookGroupsKey, typeName: "space book group")
    }

    func recordDeletedSpaceBookGroups(ids: [UUID]) {
        recordDeletes(ids: ids, key: deletedSpaceBookGroupsKey, typeName: "space book group")
    }

    func recordDeletedSpaceOutfit(id: UUID) {
        recordDeletes(ids: [id], key: deletedSpaceOutfitsKey, typeName: "space outfit")
    }

    func recordDeletedSpaceOutfits(ids: [UUID]) {
        recordDeletes(ids: ids, key: deletedSpaceOutfitsKey, typeName: "space outfit")
    }

    func recordDeletedModel3D(id: UUID) {
        recordDeletes(ids: [id], key: deletedModel3DsKey, typeName: "3D model")
    }

    func recordDeletedPerlerPattern(id: UUID) {
        recordDeletes(ids: [id], key: deletedPerlerPatternsKey, typeName: "perler pattern")
    }

    /// 记录删除 - 存储 UUID 和删除时间戳
    private func recordDeletes(ids: [UUID], key: String, typeName: String) {
        guard !ids.isEmpty else { return }

        let deleteTime = Date()
        var deletedRecords = getDeletedRecords(for: key)

        // 更新或添加删除记录
        for id in ids {
            deletedRecords[id.uuidString] = deleteTime.timeIntervalSince1970
        }

        // 保存到本地
        saveDeletedRecords(records: deletedRecords, key: key)

        if ids.count == 1, let id = ids.first {
            print("DeleteTracker: Recorded deleted \(typeName) \(id) at \(deleteTime)")
        } else {
            print("DeleteTracker: Recorded \(ids.count) deleted \(typeName) records at \(deleteTime)")
        }
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

    func getDeletedSpaceBookGroupRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedSpaceBookGroupsKey)
    }

    func getDeletedSpaceOutfitRecords() -> [UUID: Date] {
        return getDeletedDates(for: deletedSpaceOutfitsKey)
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
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<Outfit>(
                    predicate: #Predicate<Outfit> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: Outfit, deleteTime: Date) -> Bool in
            let itemNote = item.note
            let isAlreadyDeleted = item.isDeleted
            
            // 强制删除策略：只要在删除记录中，就强制删除
            // 避免 iCloud 同步覆盖导致的删除失效
            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted outfit '\(itemNote)'")
                return true
            } else {
                print("DeleteTracker: ✓ Outfit '\(itemNote)' already deleted")
                return false
            }
        }
    }

    func applyDeletedClothings(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedClothingsKey,
            typeName: "clothing",
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<Clothing>(
                    predicate: #Predicate<Clothing> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: Clothing, deleteTime: Date) -> Bool in
            let itemName = item.name
            let isAlreadyDeleted = item.isDeleted
            
            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted clothing '\(itemName)'")
                return true
            } else {
                print("DeleteTracker: ✓ Clothing '\(itemName)' already deleted")
                return false
            }
        }
    }

    func applyDeletedBookGroups(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedBookGroupsKey,
            typeName: "book group",
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<BookGroup>(
                    predicate: #Predicate<BookGroup> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: BookGroup, deleteTime: Date) -> Bool in
            let itemTitle = item.title
            let isAlreadyDeleted = item.isDeleted
            
            // 强制删除策略：只要在删除记录中，就强制删除
            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted book group '\(itemTitle)'")
                return true
            } else {
                print("DeleteTracker: ✓ Book group '\(itemTitle)' already deleted")
                return false
            }
        }
    }

    func applyDeletedSpaceBookGroups(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedSpaceBookGroupsKey,
            typeName: "space book group",
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<SpaceBookGroup>(
                    predicate: #Predicate<SpaceBookGroup> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: SpaceBookGroup, deleteTime: Date) -> Bool in
            let itemTitle = item.title
            let isAlreadyDeleted = item.isDeleted

            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted space book group '\(itemTitle)'")
                return true
            } else {
                print("DeleteTracker: ✓ Space book group '\(itemTitle)' already deleted")
                return false
            }
        }
    }

    func applyDeletedSpaceOutfits(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedSpaceOutfitsKey,
            typeName: "space outfit",
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<SpaceOutfit>(
                    predicate: #Predicate<SpaceOutfit> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: SpaceOutfit, deleteTime: Date) -> Bool in
            let itemNote = item.note
            let isAlreadyDeleted = item.isDeleted

            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted space outfit '\(itemNote)'")
                return true
            } else {
                print("DeleteTracker: ✓ Space outfit '\(itemNote)' already deleted")
                return false
            }
        }
    }

    func applyDeletedModel3Ds(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedModel3DsKey,
            typeName: "3D model",
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<Model3D>(
                    predicate: #Predicate<Model3D> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: Model3D, deleteTime: Date) -> Bool in
            let itemName = item.name
            let isAlreadyDeleted = item.isDeleted
            
            // 强制删除策略：只要在删除记录中，就强制删除
            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted 3D model '\(itemName)'")
                return true
            } else {
                print("DeleteTracker: ✓ 3D model '\(itemName)' already deleted")
                return false
            }
        }
    }

    func applyDeletedPerlerPatterns(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedPerlerPatternsKey,
            typeName: "perler pattern",
            clearRecords: clearRecords,
            fetchItems: { context, ids in
                let descriptor = FetchDescriptor<PerlerBeadPattern>(
                    predicate: #Predicate<PerlerBeadPattern> { ids.contains($0.id) }
                )
                return try context.fetch(descriptor)
            }
        ) { (item: PerlerBeadPattern, deleteTime: Date) -> Bool in
            let itemName = item.name
            let itemModifiedTime = item.lastModified
            let isAlreadyDeleted = item.isDeleted
            
            let timeDiff = deleteTime.timeIntervalSince(itemModifiedTime)
            print("DeleteTracker: [\(itemName)] deleteTime:\(deleteTime), lastModified:\(itemModifiedTime), diff:\(timeDiff)s, isDeleted:\(isAlreadyDeleted)")

            // 策略：如果项目在删除记录中，强制删除（不管时间戳）
            // 因为 iCloud 同步可能会在 DeleteTracker 之前更新 lastModified
            if !isAlreadyDeleted {
                item.isDeleted = true
                item.deletedAt = deleteTime
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted '\(itemName)' (in delete record)")
                return true
            } else {
                print("DeleteTracker: ✓ Already deleted '\(itemName)'")
                return false
            }
        }
    }

    /// 通用的应用删除方法
    /// 注意：此方法在 iCloud 同步期间可能被调用，需要处理对象上下文失效的情况
    private func applyDeletedItems<T: PersistentModel>(
        context: ModelContext,
        key: String,
        typeName: String,
        clearRecords: Bool = true,
        fetchItems: (ModelContext, [UUID]) throws -> [T],
        applyDeleteIfNeeded: (T, Date) -> Bool
    ) {
        pruneExpiredRecords(for: key, typeName: typeName)

        let deletedRecords = getDeletedDates(for: key)
        guard !deletedRecords.isEmpty else {
            print("DeleteTracker: No deleted \(typeName) records found")
            return
        }

        let deletedIDs = Array(deletedRecords.keys)
        print("DeleteTracker: Checking \(deletedRecords.count) deleted \(typeName)(s), IDs: \(deletedIDs.map { $0.uuidString.prefix(8) })")

        do {
            let allItems = try fetchItems(context, deletedIDs)
            
            print("DeleteTracker: Fetched \(allItems.count) matching \(typeName)(s) from database")

            var changedCount = 0
            var processedRecords: [UUID] = []

            for item in allItems {
                // 检查对象是否仍然有效（未被 iCloud 同步分离）
                // 通过尝试获取 ID 来验证对象有效性
                guard let itemID = getItemID(item) else {
                    print("DeleteTracker: Warning - Could not get ID for \(typeName), object may be detached")
                    continue
                }

                // 只在需要时访问对象属性，且要做好异常处理
                if let deleteTime = deletedRecords[itemID] {
                    print("DeleteTracker: Found matching record for \(typeName) ID:\(itemID.uuidString.prefix(8))")
                    
                    let didChange = applyDeleteIfNeeded(item, deleteTime)
                    
                    if didChange {
                        changedCount += 1
                    }

                    if clearRecords {
                        processedRecords.append(itemID)
                    }
                }
            }

            if changedCount > 0 {
                do {
                    try context.save()
                    print("DeleteTracker: ✓ Saved \(changedCount) \(typeName) deletes to database")
                    
                    // 立即再次保存，确保 iCloud 同步不会覆盖
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        do {
                            try context.save()
                            print("DeleteTracker: ✓ Re-saved \(changedCount) \(typeName) deletes (anti-race)")
                        } catch {
                            print("DeleteTracker: ✗ Failed to re-save \(typeName) deletes: \(error)")
                        }
                    }
                } catch {
                    print("DeleteTracker: ✗ Failed to save \(typeName) deletes: \(error)")
                }
            } else {
                print("DeleteTracker: No \(typeName) deletes changed data")
            }

            // 清理已处理的删除记录（仅在启动时清理，同步后不清除）
            if clearRecords && !processedRecords.isEmpty {
                clearProcessedRecords(ids: processedRecords, key: key, typeName: typeName)
            }

        } catch {
            print("DeleteTracker: Failed to apply \(typeName) deletes: \(error)")
        }
    }

    /// 获取 PersistentModel 的 ID
    /// 注意：此方法在 iCloud 同步期间可能被调用，需要处理对象上下文失效的情况
    private func getItemID<T: PersistentModel>(_ item: T) -> UUID? {
        // 使用类型检查直接访问 id 属性，避免泛型层全库反射。
        if let outfit = item as? Outfit {
            return outfit.id
        } else if let clothing = item as? Clothing {
            return clothing.id
        } else if let bookGroup = item as? BookGroup {
            return bookGroup.id
        } else if let spaceBookGroup = item as? SpaceBookGroup {
            return spaceBookGroup.id
        } else if let spaceOutfit = item as? SpaceOutfit {
            return spaceOutfit.id
        } else if let model3D = item as? Model3D {
            return model3D.id
        } else if let perlerPattern = item as? PerlerBeadPattern {
            return perlerPattern.id
        }
        return nil
    }

    /// 清理超过保留期的孤儿删除记录，避免历史记录长期触发同步重放扫描
    private func pruneExpiredRecords(for key: String, typeName: String) {
        var records = getDeletedRecords(for: key)
        guard !records.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        let retentionPeriod: Double = 24 * 60 * 60
        let beforeCount = records.count

        records = records.filter { _, timestamp in
            now - timestamp <= retentionPeriod
        }

        let removedCount = beforeCount - records.count
        if removedCount > 0 {
            saveDeletedRecords(records: records, key: key)
            print("DeleteTracker: Pruned \(removedCount) expired \(typeName) delete records")
        }
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

    func clearDeletedSpaceBookGroups() {
        clearDeletedItems(key: deletedSpaceBookGroupsKey, typeName: "space book group")
    }

    func clearDeletedSpaceOutfits() {
        clearDeletedItems(key: deletedSpaceOutfitsKey, typeName: "space outfit")
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

    func removeDeletedSpaceBookGroup(id: UUID) {
        removeDeletedID(id: id, key: deletedSpaceBookGroupsKey, typeName: "space book group")
    }

    func removeDeletedSpaceOutfit(id: UUID) {
        removeDeletedID(id: id, key: deletedSpaceOutfitsKey, typeName: "space outfit")
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
        applyDeletedSpaceOutfits(context: context, clearRecords: clearRecords)
        applyDeletedClothings(context: context, clearRecords: clearRecords)
        applyDeletedModel3Ds(context: context, clearRecords: clearRecords)
        applyDeletedBookGroups(context: context, clearRecords: clearRecords)
        applyDeletedSpaceBookGroups(context: context, clearRecords: clearRecords)
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
