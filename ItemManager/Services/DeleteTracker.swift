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

    struct ApplyResult {
        var pendingRecordCount = 0
        var matchedRecordCount = 0
        var changedCount = 0

        static let noPending = ApplyResult()

        var didChangeData: Bool {
            changedCount > 0
        }

        mutating func merge(_ other: ApplyResult) {
            pendingRecordCount += other.pendingRecordCount
            matchedRecordCount += other.matchedRecordCount
            changedCount += other.changedCount
        }
    }

    /// 本地 UserDefaults - 删除记录只保存在本地，不同步到 iCloud
    private let userDefaults = UserDefaults.standard

    /// 待处理的 ModelContext
    var pendingContext: ModelContext?

    // MARK: - Keys (使用新的 key 避免读取旧的 iCloud 同步记录)
    private let deletedOutfitsKey = "deletedOutfits_local"  // local: 只保存在本地
    private let deletedClothingsKey = "deletedClothings_local"
    private let deletedClothingSourcesKey = "deletedClothings_sources_local"
    private let deletedBookGroupsKey = "deletedBookGroups_local"
    private let deletedSpaceBookGroupsKey = "deletedSpaceBookGroups_local"
    private let deletedSpaceOutfitsKey = "deletedSpaceOutfits_local"
    private let deletedModel3DsKey = "deletedModel3Ds_local"

    private var allDeleteRecordKeys: [String] {
        [
            deletedOutfitsKey,
            deletedClothingsKey,
            deletedBookGroupsKey,
            deletedSpaceBookGroupsKey,
            deletedSpaceOutfitsKey,
            deletedModel3DsKey
        ]
    }

    var hasPendingDeletes: Bool {
        allDeleteRecordKeys.contains { !getDeletedRecords(for: $0).isEmpty }
    }

    var pendingDeletesFingerprint: String {
        let deleteRecordsFingerprint = allDeleteRecordKeys.map { key in
            let records = getDeletedRecords(for: key)
            let entries = records
                .map { id, timestamp in "\(id):\(Int(timestamp))" }
                .sorted()
                .joined(separator: ",")
            return "\(key)=\(entries)"
        }
        .joined(separator: "|")

        let sourceEntries = getDeletedClothingSources()
            .map { id, source in "\(id):\(source)" }
            .sorted()
            .joined(separator: ",")

        return "\(deleteRecordsFingerprint)|\(deletedClothingSourcesKey)=\(sourceEntries)"
    }

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

    func recordDeletedClothing(id: UUID, source: String? = nil) {
        recordDeletes(ids: [id], key: deletedClothingsKey, typeName: "clothing", clothingDeletionSource: source)
    }

    func recordDeletedClothing(id: UUID, source: ClothingDeletionSource) {
        recordDeletedClothing(id: id, source: source.rawValue)
    }

    func recordDeletedClothings(ids: [UUID], source: String? = nil) {
        recordDeletes(ids: ids, key: deletedClothingsKey, typeName: "clothing", clothingDeletionSource: source)
    }

    func recordDeletedClothings(ids: [UUID], source: ClothingDeletionSource) {
        recordDeletedClothings(ids: ids, source: source.rawValue)
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

    /// 记录删除 - 存储 UUID 和删除时间戳
    private func recordDeletes(ids: [UUID], key: String, typeName: String, clothingDeletionSource: String? = nil) {
        guard !ids.isEmpty else { return }

        let deleteTime = Date()
        var deletedRecords = getDeletedRecords(for: key)

        // 更新或添加删除记录
        for id in ids {
            deletedRecords[id.uuidString] = deleteTime.timeIntervalSince1970
        }

        // 保存到本地
        saveDeletedRecords(records: deletedRecords, key: key)
        if key == deletedClothingsKey {
            saveDeletedClothingSources(ids: ids, source: clothingDeletionSource)
        }

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

    /// 获取删除记录 [UUID: 删除时间戳]
    /// 只从本地 UserDefaults 读取，不再从 iCloud 读取
    private func getDeletedRecords(for key: String) -> [String: Double] {
        return userDefaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private func getDeletedClothingSources() -> [String: String] {
        return userDefaults.dictionary(forKey: deletedClothingSourcesKey) as? [String: String] ?? [:]
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

    private func saveDeletedClothingSources(ids: [UUID], source: String?) {
        guard !ids.isEmpty else { return }

        var sourceRecords = getDeletedClothingSources()
        let normalizedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)

        for id in ids {
            if let normalizedSource, !normalizedSource.isEmpty {
                sourceRecords[id.uuidString] = normalizedSource
            } else {
                sourceRecords.removeValue(forKey: id.uuidString)
            }
        }

        saveDeletedClothingSources(sourceRecords)
    }

    private func saveDeletedClothingSources(_ sourceRecords: [String: String]) {
        if sourceRecords.isEmpty {
            userDefaults.removeObject(forKey: deletedClothingSourcesKey)
        } else {
            userDefaults.set(sourceRecords, forKey: deletedClothingSourcesKey)
        }
    }

    private func removeDeletedClothingSources(idStrings: [String]) {
        guard !idStrings.isEmpty else { return }

        var sourceRecords = getDeletedClothingSources()
        for idString in idStrings {
            sourceRecords.removeValue(forKey: idString)
        }
        saveDeletedClothingSources(sourceRecords)
    }

    // MARK: - 应用删除（基于时间戳比较）

    @discardableResult
    func applyDeletedOutfits(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
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

    @discardableResult
    func applyDeletedClothings(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
        let sourceRecords = getDeletedClothingSources()

        return applyDeletedItems(
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
            let deletionSource = sourceRecords[item.id.uuidString]
            let needsSourceUpdate = item.deletionSource != deletionSource
            let needsDeleteUpdate = !isAlreadyDeleted || item.deletedAt == nil
            
            if needsDeleteUpdate || needsSourceUpdate {
                item.isDeleted = true
                if item.deletedAt == nil {
                    item.deletedAt = deleteTime
                }
                item.deletionSource = deletionSource
                item.lastModified = Date()
                print("DeleteTracker: ✓ Force deleted clothing '\(itemName)' source=\(deletionSource ?? "nil")")
                return true
            } else {
                print("DeleteTracker: ✓ Clothing '\(itemName)' already deleted source=\(item.deletionSource ?? "nil")")
                return false
            }
        }
    }

    @discardableResult
    func applyDeletedBookGroups(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
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

    @discardableResult
    func applyDeletedSpaceBookGroups(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
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

    @discardableResult
    func applyDeletedSpaceOutfits(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
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

    @discardableResult
    func applyDeletedModel3Ds(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
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


    /// 通用的应用删除方法
    /// 注意：此方法在 iCloud 同步期间可能被调用，需要处理对象上下文失效的情况
    private func applyDeletedItems<T: PersistentModel>(
        context: ModelContext,
        key: String,
        typeName: String,
        clearRecords: Bool = true,
        fetchItems: (ModelContext, [UUID]) throws -> [T],
        applyDeleteIfNeeded: (T, Date) -> Bool
    ) -> ApplyResult {
        pruneExpiredRecords(for: key, typeName: typeName)

        let deletedRecords = getDeletedDates(for: key)
        guard !deletedRecords.isEmpty else {
            print("DeleteTracker: No deleted \(typeName) records found")
            return .noPending
        }

        let deletedIDs = Array(deletedRecords.keys)
        print("DeleteTracker: Checking \(deletedRecords.count) deleted \(typeName)(s), IDs: \(deletedIDs.map { $0.uuidString.prefix(8) })")

        var result = ApplyResult(pendingRecordCount: deletedRecords.count)

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
                    result.matchedRecordCount += 1
                    
                    let didChange = applyDeleteIfNeeded(item, deleteTime)
                    
                    if didChange {
                        changedCount += 1
                    }

                    if clearRecords {
                        processedRecords.append(itemID)
                    }
                }
            }

            result.changedCount = changedCount

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

        return result
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
        let expiredIDs = records.compactMap { idString, timestamp in
            now - timestamp > retentionPeriod ? idString : nil
        }

        records = records.filter { _, timestamp in
            now - timestamp <= retentionPeriod
        }

        let removedCount = beforeCount - records.count
        if removedCount > 0 {
            saveDeletedRecords(records: records, key: key)
            if key == deletedClothingsKey {
                removeDeletedClothingSources(idStrings: expiredIDs)
            }
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
        var removedIDStrings: [String] = []

        for id in ids {
            if let timestamp = records[id.uuidString] {
                // 只清理超过24小时的记录
                if now - timestamp > retentionPeriod {
                    records.removeValue(forKey: id.uuidString)
                    removedIDStrings.append(id.uuidString)
                }
            }
        }

        let afterCount = records.count
        let clearedCount = beforeCount - afterCount

        if clearedCount > 0 {
            saveDeletedRecords(records: records, key: key)
            if key == deletedClothingsKey {
                removeDeletedClothingSources(idStrings: removedIDStrings)
            }
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

    private func clearDeletedItems(key: String, typeName: String) {
        userDefaults.removeObject(forKey: key)
        if key == deletedClothingsKey {
            userDefaults.removeObject(forKey: deletedClothingSourcesKey)
        }
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

    private func removeDeletedID(id: UUID, key: String, typeName: String) {
        var records = getDeletedRecords(for: key)
        records.removeValue(forKey: id.uuidString)
        saveDeletedRecords(records: records, key: key)
        if key == deletedClothingsKey {
            removeDeletedClothingSources(idStrings: [id.uuidString])
        }
        print("DeleteTracker: Removed \(typeName) \(id) from delete records")
    }

    // MARK: - 应用所有删除

    @discardableResult
    func applyAllDeletes(context: ModelContext, clearRecords: Bool = true) -> ApplyResult {
        guard hasPendingDeletes else {
            print("DeleteTracker: No tracked deletes pending")
            return .noPending
        }

        print("DeleteTracker: Applying all tracked deletes with timestamp comparison...")

        // 保存 context
        pendingContext = context

        var result = ApplyResult()

        // 应用各类删除
        result.merge(applyDeletedOutfits(context: context, clearRecords: clearRecords))
        result.merge(applyDeletedSpaceOutfits(context: context, clearRecords: clearRecords))
        result.merge(applyDeletedClothings(context: context, clearRecords: clearRecords))
        result.merge(applyDeletedModel3Ds(context: context, clearRecords: clearRecords))
        result.merge(applyDeletedBookGroups(context: context, clearRecords: clearRecords))
        result.merge(applyDeletedSpaceBookGroups(context: context, clearRecords: clearRecords))

        print("DeleteTracker: Finished applying deletes, pending=\(result.pendingRecordCount), matched=\(result.matchedRecordCount), changed=\(result.changedCount)")
        return result
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
            "deletedModel3Ds_v2"
        ]

        for key in oldKeys {
            iCloudStore.removeObject(forKey: key)
        }
        iCloudStore.synchronize()
        print("DeleteTracker: 已清除旧的 iCloud 同步删除记录")
    }
}
