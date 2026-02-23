import Foundation
import SwiftData
import CoreData

/// 删除追踪器 - 基于时间戳的冲突解决方案
/// 核心思想：记录删除时间戳，在冲突时比较删除时间和数据修改时间
@MainActor
final class DeleteTracker {
    static let shared = DeleteTracker()

    /// iCloud Key-Value Store - 用于跨设备同步删除记录
    private let iCloudStore = NSUbiquitousKeyValueStore.default

    /// 本地 UserDefaults - 作为 iCloud 的备份
    private let userDefaults = UserDefaults.standard

    /// 待处理的 ModelContext（用于 iCloud 同步完成后应用删除）
    private var pendingContext: ModelContext?

    // MARK: - Keys
    private let deletedOutfitsKey = "deletedOutfits_v2"  // v2: 存储 [UUID: Date] 字典
    private let deletedClothingsKey = "deletedClothings_v2"
    private let deletedBookGroupsKey = "deletedBookGroups_v2"
    private let deletedModel3DsKey = "deletedModel3Ds_v2"
    private let deletedPerlerPatternsKey = "deletedPerlerPatterns_v2"

    // MARK: - 初始化

    init() {
        // 监听 iCloud Key-Value Store 的变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquitousKeyValueStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore
        )

        // 监听 SwiftData iCloud 同步完成事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistentStoreRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: nil
        )

        // 同步 iCloud Store
        iCloudStore.synchronize()
    }

    @objc private func ubiquitousKeyValueStoreDidChange(_ notification: Notification) {
        print("DeleteTracker: iCloud Key-Value Store 发生变化")
    }

    @objc private func persistentStoreRemoteChange(_ notification: Notification) {
        print("DeleteTracker: iCloud 同步通知收到，重新应用删除...")
        // iCloud 同步完成后，重新应用删除（防止同步覆盖删除状态）
        // 注意：这里不清除记录，让24小时自动过期机制处理
        if let context = pendingContext {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.applyAllDeletes(context: context, clearRecords: true)
            }
        }
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
    private func getDeletedRecords(for key: String) -> [String: Double] {
        // 优先从 iCloud 读取
        if let cloudDict = iCloudStore.dictionary(forKey: key) as? [String: Double] {
            return cloudDict
        }
        // 回退到本地
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
    private func saveDeletedRecords(records: [String: Double], key: String) {
        userDefaults.set(records, forKey: key)
        iCloudStore.set(records, forKey: key)
        iCloudStore.synchronize()
    }

    // MARK: - 应用删除（基于时间戳比较）

    func applyDeletedOutfits(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedOutfitsKey,
            typeName: "outfit",
            clearRecords: clearRecords
        ) { (item: Outfit, deleteTime: Date) -> Bool in
            // 比较删除时间和数据最后修改时间
            let itemModifiedTime = item.lastModified

            if deleteTime > itemModifiedTime {
                // 删除操作发生在数据修改之后，应该删除
                if !item.isDeleted {
                    item.isDeleted = true
                    item.deletedAt = deleteTime
                    item.lastModified = Date()  // 更新修改时间，确保同步到其他设备
                    print("DeleteTracker: Applied delete to outfit '\(item.note)' (deleted after last modify)")
                }
                return true
            } else {
                // 数据在删除后被修改过，保留数据，清除删除记录
                print("DeleteTracker: Keeping outfit '\(item.note)' (modified after delete)")
                return false
            }
        }
    }

    func applyDeletedClothings(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedClothingsKey,
            typeName: "clothing",
            clearRecords: clearRecords
        ) { (item: Clothing, deleteTime: Date) -> Bool in
            let itemModifiedTime = item.lastModified

            if deleteTime > itemModifiedTime {
                if !item.isDeleted {
                    item.isDeleted = true
                    item.deletedAt = deleteTime
                    item.lastModified = Date()
                    print("DeleteTracker: Applied delete to clothing '\(item.name)' (deleted after last modify)")
                }
                return true
            } else {
                print("DeleteTracker: Keeping clothing '\(item.name)' (modified after delete)")
                return false
            }
        }
    }

    func applyDeletedBookGroups(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedBookGroupsKey,
            typeName: "book group",
            clearRecords: clearRecords
        ) { (item: BookGroup, deleteTime: Date) -> Bool in
            let itemModifiedTime = item.lastModified

            if deleteTime > itemModifiedTime {
                if !item.isDeleted {
                    item.isDeleted = true
                    item.deletedAt = deleteTime
                    item.lastModified = Date()
                    print("DeleteTracker: Applied delete to book group '\(item.title)' (deleted after last modify)")
                }
                return true
            } else {
                print("DeleteTracker: Keeping book group '\(item.title)' (modified after delete)")
                return false
            }
        }
    }

    func applyDeletedModel3Ds(context: ModelContext, clearRecords: Bool = true) {
        applyDeletedItems(
            context: context,
            key: deletedModel3DsKey,
            typeName: "3D model",
            clearRecords: clearRecords
        ) { (item: Model3D, deleteTime: Date) -> Bool in
            let itemModifiedTime = item.lastModified

            if deleteTime > itemModifiedTime {
                if !item.isDeleted {
                    item.isDeleted = true
                    item.deletedAt = deleteTime
                    item.lastModified = Date()
                    print("DeleteTracker: Applied delete to 3D model '\(item.name)' (deleted after last modify)")
                }
                return true
            } else {
                print("DeleteTracker: Keeping 3D model '\(item.name)' (modified after delete)")
                return false
            }
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

            if deleteTime > itemModifiedTime {
                if !item.isDeleted {
                    item.isDeleted = true
                    item.deletedAt = deleteTime
                    item.lastModified = Date()
                    print("DeleteTracker: ✓ Applied delete to '\(item.name)' (deleted after last modify)")
                } else {
                    print("DeleteTracker: ✓ Already deleted '\(item.name)'")
                }
                return true
            } else {
                print("DeleteTracker: ✗ Keeping '\(item.name)' (modified \(abs(timeDiff))s after delete)")
                return false
            }
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
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) \(typeName) deletes")
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
        iCloudStore.removeObject(forKey: key)
        iCloudStore.synchronize()
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

        // 保存 context 用于 iCloud 同步通知
        pendingContext = context

        // 同步 iCloud 数据
        iCloudStore.synchronize()

        // 应用各类删除
        applyDeletedOutfits(context: context, clearRecords: clearRecords)
        applyDeletedClothings(context: context, clearRecords: clearRecords)
        applyDeletedModel3Ds(context: context, clearRecords: clearRecords)
        applyDeletedBookGroups(context: context, clearRecords: clearRecords)
        applyDeletedPerlerPatterns(context: context, clearRecords: clearRecords)

        print("DeleteTracker: Finished applying deletes")
    }
}
