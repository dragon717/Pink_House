//
//  ClothingDuplicateRepairService.swift
//  ItemManager
//
//  Repairs duplicated Clothing rows created by SwiftData/iCloud restore or merge
//  races. The business UUID is the source of truth; duplicates must be removed
//  before wardrobe views build dictionaries, statistics, and image prefetch lists.
//

import Foundation
import SwiftData

@MainActor
final class ClothingDuplicateRepairService {
    static let shared = ClothingDuplicateRepairService()

    private var isRepairing = false
    private var scheduledRepairTask: Task<Void, Never>?

    private init() {}

    static func preferredMap(from clothings: [Clothing]) -> [UUID: Clothing] {
        var result: [UUID: Clothing] = [:]
        result.reserveCapacity(clothings.count)

        for clothing in clothings {
            if let existing = result[clothing.id] {
                if shared.isBetterKeeper(clothing, than: existing) {
                    result[clothing.id] = clothing
                }
            } else {
                result[clothing.id] = clothing
            }
        }

        return result
    }

    func scheduleRepair(
        modelContainer: ModelContainer,
        reason: String,
        delayNanoseconds: UInt64 = 800_000_000
    ) {
        scheduledRepairTask?.cancel()
        scheduledRepairTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            _ = await repairIfNeeded(modelContainer: modelContainer, reason: reason)
        }
    }

    @discardableResult
    func repairIfNeeded(modelContainer: ModelContainer, reason: String) async -> Int {
        guard !isRepairing else {
            print("[ClothingDuplicateRepair] repair already running, skip reason=\(reason)")
            return 0
        }

        #if !WIDGET_EXTENSION
        guard !SwiftDataMigrationManager.shared.isMigrating else {
            print("[ClothingDuplicateRepair] iCloud migration in progress, skip reason=\(reason)")
            return 0
        }
        #endif

        isRepairing = true
        defer { isRepairing = false }

        let startedAt = Date()
        let context = modelContainer.mainContext

        do {
            var descriptor = FetchDescriptor<Clothing>()
            descriptor.includePendingChanges = true
            let allClothings = try context.fetch(descriptor)

            var groupsByID: [UUID: [Clothing]] = [:]
            groupsByID.reserveCapacity(allClothings.count)
            for clothing in allClothings {
                groupsByID[clothing.id, default: []].append(clothing)
            }

            let duplicateGroups = groupsByID.values.filter { $0.count > 1 }
            guard !duplicateGroups.isEmpty else {
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                print("[ClothingDuplicateRepair] no duplicates reason=\(reason) scanned=\(allClothings.count) duration_ms=\(durationMs)")
                return 0
            }

            var removedCount = 0
            var repairedGroupCount = 0

            for group in duplicateGroups {
                guard let keeper = preferredKeeper(from: group) else { continue }
                repairedGroupCount += 1

                for duplicate in group where duplicate !== keeper {
                    merge(duplicate, into: keeper)
                    let duplicateID = duplicate.id
                    duplicate.accessoryItems = []
                    duplicate.tags = []
                    duplicate.brand = nil
                    context.delete(duplicate)
                    removedCount += 1
                    print("[ClothingDuplicateRepair] deleted duplicate Clothing id=\(duplicateID)")
                }

                keeper.lastModified = Date()
            }

            if removedCount > 0 {
                try context.save()
            }

            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClothingDuplicateRepair] repaired reason=\(reason) groups=\(repairedGroupCount) removed=\(removedCount) scanned=\(allClothings.count) duration_ms=\(durationMs)")
            return removedCount
        } catch {
            print("[ClothingDuplicateRepair] failed reason=\(reason) error=\(error)")
            return 0
        }
    }

    private func preferredKeeper(from items: [Clothing]) -> Clothing? {
        guard var keeper = items.first else { return nil }
        for candidate in items.dropFirst() where isBetterKeeper(candidate, than: keeper) {
            keeper = candidate
        }
        return keeper
    }

    private func isBetterKeeper(_ candidate: Clothing, than current: Clothing) -> Bool {
        let candidateDeleted = candidate.isDeleted || candidate.deletedAt != nil
        let currentDeleted = current.isDeleted || current.deletedAt != nil

        if candidateDeleted != currentDeleted {
            return !candidateDeleted
        }

        let candidateScore = contentScore(candidate)
        let currentScore = contentScore(current)
        if candidateScore != currentScore {
            return candidateScore > currentScore
        }

        if candidate.lastModified != current.lastModified {
            return candidate.lastModified > current.lastModified
        }

        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }

        return candidate.createdAt > current.createdAt
    }

    private func contentScore(_ clothing: Clothing) -> Int {
        var score = 0
        score += clothing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 4
        score += clothing.brand == nil ? 0 : 3
        score += min(clothing.imagePaths.count, 8) * 3
        score += min(clothing.tags?.count ?? 0, 8)
        score += min(clothing.accessoryItems?.count ?? 0, 8) * 2
        score += clothing.types.isEmpty ? 0 : 1
        score += clothing.colors.isEmpty ? 0 : 1
        score += clothing.sizes.isEmpty ? 0 : 1
        score += clothing.length.isEmpty ? 0 : 1
        score += clothing.note.isEmpty ? 0 : 1
        score += clothing.sizeChartImagePath == nil ? 0 : 2
        score += clothing.priceChartImagePath == nil ? 0 : 2
        score += clothing.model3DPath == nil ? 0 : 2
        score += clothing.price > 0 ? 2 : 0
        score += clothing.deposit > 0 ? 1 : 0
        score += clothing.balance > 0 ? 1 : 0
        score += clothing.originalPrice > 0 ? 1 : 0
        return score
    }

    private func merge(_ duplicate: Clothing, into keeper: Clothing) {
        mergeText(\.name, from: duplicate, into: keeper)
        mergeText(\.types, from: duplicate, into: keeper)
        mergeText(\.colors, from: duplicate, into: keeper)
        mergeText(\.sizes, from: duplicate, into: keeper)
        mergeText(\.length, from: duplicate, into: keeper)
        mergeText(\.condition, from: duplicate, into: keeper, treatingDefaultAsEmpty: "全新")
        mergeText(\.accessories, from: duplicate, into: keeper)
        mergeText(\.note, from: duplicate, into: keeper)

        mergeImagePaths(from: duplicate, into: keeper)
        mergeCharts(from: duplicate, into: keeper)
        mergeBrand(from: duplicate, into: keeper)
        mergeTags(from: duplicate, into: keeper)
        mergeAccessories(from: duplicate, into: keeper)
        mergePricesAndReservationFields(from: duplicate, into: keeper)
        mergeModelFields(from: duplicate, into: keeper)

        keeper.isShared = keeper.isShared || duplicate.isShared
        keeper.stock = max(keeper.stock, duplicate.stock)
        keeper.createdAt = min(keeper.createdAt, duplicate.createdAt)
        keeper.updatedAt = max(keeper.updatedAt, duplicate.updatedAt)
        keeper.lastModified = max(keeper.lastModified, duplicate.lastModified)

        let keeperIsDeleted = keeper.isDeleted || keeper.deletedAt != nil
        guard keeperIsDeleted else { return }

        if keeper.deletedAt == nil {
            keeper.deletedAt = duplicate.deletedAt
        } else if let duplicateDeletedAt = duplicate.deletedAt,
                  let keeperDeletedAt = keeper.deletedAt {
            keeper.deletedAt = min(keeperDeletedAt, duplicateDeletedAt)
        }
    }

    private func mergeText(
        _ keyPath: ReferenceWritableKeyPath<Clothing, String>,
        from duplicate: Clothing,
        into keeper: Clothing,
        treatingDefaultAsEmpty defaultValue: String? = nil
    ) {
        let current = keeper[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = duplicate[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }

        if current.isEmpty || current == defaultValue {
            keeper[keyPath: keyPath] = duplicate[keyPath: keyPath]
        }
    }

    private func mergeImagePaths(from duplicate: Clothing, into keeper: Clothing) {
        var knownPaths = Set(keeper.imagePaths)
        for path in duplicate.imagePaths where !knownPaths.contains(path) {
            keeper.imagePaths.append(path)
            knownPaths.insert(path)
        }
    }

    private func mergeCharts(from duplicate: Clothing, into keeper: Clothing) {
        if isNilOrEmpty(keeper.sizeChartImagePath),
           let duplicatePath = duplicate.sizeChartImagePath,
           !duplicatePath.isEmpty {
            keeper.sizeChartImagePath = duplicatePath
        }

        if isNilOrEmpty(keeper.priceChartImagePath),
           let duplicatePath = duplicate.priceChartImagePath,
           !duplicatePath.isEmpty {
            keeper.priceChartImagePath = duplicatePath
        }
    }

    private func mergeBrand(from duplicate: Clothing, into keeper: Clothing) {
        if keeper.brand == nil, let duplicateBrand = duplicate.brand {
            keeper.brand = duplicateBrand
        }
    }

    private func mergeTags(from duplicate: Clothing, into keeper: Clothing) {
        var tags = keeper.tags ?? []
        var tagIDs = Set(tags.map(\.id))

        for tag in duplicate.tags ?? [] where !tagIDs.contains(tag.id) {
            tags.append(tag)
            tagIDs.insert(tag.id)
        }

        keeper.tags = tags
    }

    private func mergeAccessories(from duplicate: Clothing, into keeper: Clothing) {
        var accessories = keeper.accessoryItems ?? []
        var accessoryIDs = Set(accessories.map(\.id))

        for item in duplicate.accessoryItems ?? [] where !accessoryIDs.contains(item.id) {
            item.clothing = keeper
            accessories.append(item)
            accessoryIDs.insert(item.id)
        }

        keeper.accessoryItems = accessories.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            return lhs.name < rhs.name
        }
        duplicate.accessoryItems = []
    }

    private func mergePricesAndReservationFields(from duplicate: Clothing, into keeper: Clothing) {
        if keeper.originalPrice == 0, duplicate.originalPrice > 0 {
            keeper.originalPrice = duplicate.originalPrice
        }
        if keeper.originalPriceJPY == 0, duplicate.originalPriceJPY > 0 {
            keeper.originalPriceJPY = duplicate.originalPriceJPY
        }
        if keeper.price == 0, duplicate.price > 0 {
            keeper.price = duplicate.price
        }
        if keeper.deposit == 0, duplicate.deposit > 0 {
            keeper.deposit = duplicate.deposit
        }
        if keeper.balance == 0, duplicate.balance > 0 {
            keeper.balance = duplicate.balance
        }
        if keeper.accessoriesPrice == 0, duplicate.accessoriesPrice > 0 {
            keeper.accessoriesPrice = duplicate.accessoriesPrice
        }
        if keeper.shippingFee == 0, duplicate.shippingFee > 0 {
            keeper.shippingFee = duplicate.shippingFee
        }
        if keeper.shippingFeeJPY == 0, duplicate.shippingFeeJPY > 0 {
            keeper.shippingFeeJPY = duplicate.shippingFeeJPY
        }

        keeper.purchaseDate = min(keeper.purchaseDate, duplicate.purchaseDate)
        if keeper.depositDate == nil {
            keeper.depositDate = duplicate.depositDate
        }
        if keeper.finalPaymentDate == nil {
            keeper.finalPaymentDate = duplicate.finalPaymentDate
        }
        if keeper.finalPaymentEndDate == nil {
            keeper.finalPaymentEndDate = duplicate.finalPaymentEndDate
        }
        keeper.finalPaymentInstallmentCount = 0
        if !keeper.isDepositPlan, duplicate.isDepositPlan {
            keeper.isDepositPlan = true
        }
        keeper.isFinalPaymentSavedToWealth = false
        keeper.finalPaymentSavedAt = nil
    }

    private func mergeModelFields(from duplicate: Clothing, into keeper: Clothing) {
        if keeper.model3DPath == nil {
            keeper.model3DPath = duplicate.model3DPath
        }
        if keeper.model3DType == nil {
            keeper.model3DType = duplicate.model3DType
        }
        if keeper.model3DThumbnailPath == nil {
            keeper.model3DThumbnailPath = duplicate.model3DThumbnailPath
        }
        if keeper.replacedCutoutID == nil {
            keeper.replacedCutoutID = duplicate.replacedCutoutID
        }
    }

    private func isNilOrEmpty(_ value: String?) -> Bool {
        value?.isEmpty ?? true
    }
}
