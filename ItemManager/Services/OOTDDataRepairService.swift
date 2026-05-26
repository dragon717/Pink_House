import Foundation
import SwiftData
import SwiftUI
import CryptoKit

struct OOTDDataRepairReport {
    var scannedCutouts = 0
    var scannedOutfitItems = 0
    var scannedOutfits = 0

    var normalizedCutoutPaths = 0
    var relinkedCutoutPathsByHash = 0
    var regeneratedCutoutImages = 0
    var relinkedCutoutsToClothingByHash = 0
    var unresolvedCutoutFiles = 0
    var unresolvedOutfitItemLinks = 0

    var migratedCoordinates = 0
    var clampedCoordinates = 0

    var rebuiltSnapshots = 0
    var failedSnapshots = 0

    var errors: [String] = []

    var shortSummary: String {
        "已修复：贴纸\(normalizedCutoutPaths + relinkedCutoutPathsByHash + regeneratedCutoutImages)项，快照\(rebuiltSnapshots)张"
    }

    var detailedSummary: String {
        var parts: [String] = []
        parts.append("扫描贴纸 \(scannedCutouts) 条")
        parts.append("扫描贴纸实例 \(scannedOutfitItems) 条")
        parts.append("扫描书页 \(scannedOutfits) 张")
        parts.append("路径规范化 \(normalizedCutoutPaths) 条")
        parts.append("哈希重链 \(relinkedCutoutPathsByHash) 条")
        parts.append("缺图重建 \(regeneratedCutoutImages) 条")
        parts.append("服饰重链 \(relinkedCutoutsToClothingByHash) 条")
        parts.append("坐标迁移 \(migratedCoordinates) 条")
        parts.append("坐标纠偏 \(clampedCoordinates) 条")
        parts.append("快照重建 \(rebuiltSnapshots) 张")

        if unresolvedCutoutFiles > 0 {
            parts.append("仍缺失贴纸文件 \(unresolvedCutoutFiles) 条")
        }
        if unresolvedOutfitItemLinks > 0 {
            parts.append("仍缺失贴纸引用 \(unresolvedOutfitItemLinks) 条")
        }
        if failedSnapshots > 0 {
            parts.append("快照重建失败 \(failedSnapshots) 张")
        }
        if !errors.isEmpty {
            parts.append("错误 \(errors.count) 条")
        }
        return parts.joined(separator: "，")
    }
}

struct OOTDOrphanPageRepairReport {
    var source: String
    var scannedOrphans = 0
    var movedToDefaultBook = 0
    var createdDefaultBook = false
    var deferredAmbiguousOrphans = 0
    var saved = false
    var error: String?

    var summary: String {
        var parts = [
            "source=\(source)",
            "orphans=\(scannedOrphans)",
            "movedToDefault=\(movedToDefaultBook)",
            "deferred=\(deferredAmbiguousOrphans)"
        ]
        if createdDefaultBook {
            parts.append("createdDefaultBook=true")
        }
        if saved {
            parts.append("saved=true")
        }
        if let error {
            parts.append("error=\(error)")
        }
        return parts.joined(separator: ", ")
    }
}

@MainActor
enum OOTDOrphanPageRepairService {
    static let defaultBookTitle = "默认手帐"
    static let magicStickerPageTitle = "少女魔法贴"

    @discardableResult
    static func repairPlanarOrphans(
        context: ModelContext,
        activeBooks: [BookGroup],
        allOutfits: [Outfit],
        source: String
    ) -> OOTDOrphanPageRepairReport {
        var report = OOTDOrphanPageRepairReport(source: source)
        let orphanOutfits = allOutfits.filter { outfit in
            outfit.book == nil && !outfit.isDeleted && outfit.deletedAt == nil
        }
        report.scannedOrphans = orphanOutfits.count

        guard !orphanOutfits.isEmpty else {
            print("[OOTDOrphanRepair] \(report.summary)")
            return report
        }

        var defaultBook = activeBooks.first { $0.title == defaultBookTitle && !$0.isDeleted && $0.deletedAt == nil }
        let activeNonDefaultBooks = activeBooks.filter {
            $0.title != defaultBookTitle && !$0.isDeleted && $0.deletedAt == nil
        }
        var didChange = false

        func ensureDefaultBook() -> BookGroup {
            if let defaultBook {
                return defaultBook
            }
            let maxSortIndex = activeBooks.map(\.sortIndex).max() ?? -1
            let book = BookGroup(title: defaultBookTitle, sortIndex: maxSortIndex + 1)
            context.insert(book)
            defaultBook = book
            report.createdDefaultBook = true
            didChange = true
            return book
        }

        for outfit in orphanOutfits {
            let shouldMoveToDefault: Bool
            if outfit.note == magicStickerPageTitle {
                shouldMoveToDefault = true
            } else {
                // Legacy safety gate:
                // Only auto-migrate non-magic orphan pages when there are no user-created books.
                // In multi-book restore scenarios, keep ambiguous orphans unmoved so they are not
                // silently misattributed to the default journal.
                shouldMoveToDefault = activeNonDefaultBooks.isEmpty
            }

            guard shouldMoveToDefault else {
                report.deferredAmbiguousOrphans += 1
                print("[OOTDOrphanRepair] Deferred ambiguous orphan page '\(outfit.note)' (\(outfit.id))")
                continue
            }

            let targetBook = ensureDefaultBook()
            outfit.book = targetBook
            outfit.lastModified = Date()
            report.movedToDefaultBook += 1
            didChange = true
        }

        if didChange {
            do {
                context.processPendingChanges()
                try context.save()
                report.saved = true
            } catch {
                report.error = error.localizedDescription
                print("[OOTDOrphanRepair] Failed to save: \(error)")
            }
        }

        print("[OOTDOrphanRepair] \(report.summary)")
        return report
    }
}

struct OOTDIdentityRepairReport {
    var source: String
    var scannedBooks = 0
    var scannedPages = 0
    var scannedPageItems = 0
    var scannedCutouts = 0
    var rekeyedBooks = 0
    var rekeyedPages = 0
    var rekeyedPageItems = 0
    var rekeyedCutouts = 0
    var normalizedBookSort = 0
    var normalizedPageSort = 0
    var saved = false
    var error: String?

    var didChange: Bool {
        rekeyedBooks > 0 ||
        rekeyedPages > 0 ||
        rekeyedPageItems > 0 ||
        rekeyedCutouts > 0 ||
        normalizedBookSort > 0 ||
        normalizedPageSort > 0
    }

    var summary: String {
        var parts = [
            "source=\(source)",
            "books=\(scannedBooks)",
            "pages=\(scannedPages)",
            "items=\(scannedPageItems)",
            "cutouts=\(scannedCutouts)",
            "rekeyedBooks=\(rekeyedBooks)",
            "rekeyedPages=\(rekeyedPages)",
            "rekeyedItems=\(rekeyedPageItems)",
            "rekeyedCutouts=\(rekeyedCutouts)",
            "bookSort=\(normalizedBookSort)",
            "pageSort=\(normalizedPageSort)"
        ]
        if saved {
            parts.append("saved=true")
        }
        if let error {
            parts.append("error=\(error)")
        }
        return parts.joined(separator: ", ")
    }
}

@MainActor
enum OOTDIdentityRepairService {
    @discardableResult
    static func repairIfNeeded(context: ModelContext, source: String) -> OOTDIdentityRepairReport {
        var report = OOTDIdentityRepairReport(source: source)

        do {
            let books = try context.fetch(FetchDescriptor<BookGroup>())
            let pages = try context.fetch(FetchDescriptor<Outfit>())
            let pageItems = try context.fetch(FetchDescriptor<OutfitItem>())
            let cutouts = try context.fetch(FetchDescriptor<CutoutItem>())
            let now = Date()

            report.scannedBooks = books.count
            report.scannedPages = pages.count
            report.scannedPageItems = pageItems.count
            report.scannedCutouts = cutouts.count

            repairDuplicateBookIDs(books, now: now, report: &report)
            repairDuplicatePageIDs(pages, now: now, report: &report)
            repairDuplicatePageItemIDs(pageItems, report: &report)
            repairDuplicateCutoutIDs(cutouts, now: now, report: &report)
            normalizeBookSort(books, now: now, report: &report)
            normalizePageSort(pages, now: now, report: &report)

            if report.didChange {
                context.processPendingChanges()
                try context.save()
                report.saved = true
            }
        } catch {
            report.error = error.localizedDescription
            print("[OOTDIdentityRepair] Failed: \(error)")
        }

        print("[OOTDIdentityRepair] \(report.summary)")
        return report
    }

    private static func repairDuplicateBookIDs(_ books: [BookGroup], now: Date, report: inout OOTDIdentityRepairReport) {
        var usedIDs = Set(books.map(\.id))
        let groups = Dictionary(grouping: books, by: \.id)
        for duplicates in groups.values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredBook)
            for book in ordered.dropFirst() {
                book.id = makeUniqueID(usedIDs: &usedIDs)
                book.lastModified = now
                report.rekeyedBooks += 1
            }
        }
    }

    private static func repairDuplicatePageIDs(_ pages: [Outfit], now: Date, report: inout OOTDIdentityRepairReport) {
        var usedIDs = Set(pages.map(\.id))
        let groups = Dictionary(grouping: pages, by: \.id)
        for duplicates in groups.values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredPage)
            for page in ordered.dropFirst() {
                page.id = makeUniqueID(usedIDs: &usedIDs)
                page.lastModified = now
                report.rekeyedPages += 1
            }
        }
    }

    private static func repairDuplicatePageItemIDs(_ pageItems: [OutfitItem], report: inout OOTDIdentityRepairReport) {
        var usedIDs = Set(pageItems.map(\.id))
        let groups = Dictionary(grouping: pageItems, by: \.id)
        for duplicates in groups.values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredPageItem)
            for item in ordered.dropFirst() {
                item.id = makeUniqueID(usedIDs: &usedIDs)
                report.rekeyedPageItems += 1
            }
        }
    }

    private static func repairDuplicateCutoutIDs(_ cutouts: [CutoutItem], now: Date, report: inout OOTDIdentityRepairReport) {
        var usedIDs = Set(cutouts.map(\.id))
        let groups = Dictionary(grouping: cutouts, by: \.id)
        for duplicates in groups.values where duplicates.count > 1 {
            let ordered = duplicates.sorted(by: preferredCutout)
            for cutout in ordered.dropFirst() {
                cutout.id = makeUniqueID(usedIDs: &usedIDs)
                cutout.lastModified = now
                report.rekeyedCutouts += 1
            }
        }
    }

    private static func normalizeBookSort(_ books: [BookGroup], now: Date, report: inout OOTDIdentityRepairReport) {
        let activeBooks = books
            .filter { isActiveBook($0) }
            .sorted(by: stableBookOrder)

        for (index, book) in activeBooks.enumerated() where book.sortIndex != index {
            book.sortIndex = index
            book.lastModified = now
            report.normalizedBookSort += 1
        }
    }

    private static func normalizePageSort(_ pages: [Outfit], now: Date, report: inout OOTDIdentityRepairReport) {
        let activePages = pages.filter { isActivePage($0) && $0.book != nil }
        let pagesByBook = Dictionary(grouping: activePages) { page in
            persistentKey(page.book)
        }

        for pagesInBook in pagesByBook.values {
            let orderedPages = pagesInBook.sorted(by: stablePageOrder)
            for (index, page) in orderedPages.enumerated() where page.sortIndex != index {
                page.sortIndex = index
                page.lastModified = now
                page.book?.lastModified = now
                report.normalizedPageSort += 1
            }
        }
    }

    private static func makeUniqueID(usedIDs: inout Set<UUID>) -> UUID {
        var newID = UUID()
        while usedIDs.contains(newID) {
            newID = UUID()
        }
        usedIDs.insert(newID)
        return newID
    }

    private static func isActiveBook(_ book: BookGroup) -> Bool {
        !book.isDeleted && book.deletedAt == nil
    }

    private static func isActivePage(_ page: Outfit) -> Bool {
        !page.isDeleted && page.deletedAt == nil
    }

    private static func preferredBook(_ lhs: BookGroup, _ rhs: BookGroup) -> Bool {
        if isActiveBook(lhs) != isActiveBook(rhs) {
            return isActiveBook(lhs)
        }
        if lhs.lastModified != rhs.lastModified {
            return lhs.lastModified > rhs.lastModified
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return persistentKey(lhs) < persistentKey(rhs)
    }

    private static func preferredPage(_ lhs: Outfit, _ rhs: Outfit) -> Bool {
        if isActivePage(lhs) != isActivePage(rhs) {
            return isActivePage(lhs)
        }
        if (lhs.book != nil) != (rhs.book != nil) {
            return lhs.book != nil
        }
        if lhs.lastModified != rhs.lastModified {
            return lhs.lastModified > rhs.lastModified
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return persistentKey(lhs) < persistentKey(rhs)
    }

    private static func preferredPageItem(_ lhs: OutfitItem, _ rhs: OutfitItem) -> Bool {
        if (lhs.outfit != nil) != (rhs.outfit != nil) {
            return lhs.outfit != nil
        }
        if lhs.zIndex != rhs.zIndex {
            return lhs.zIndex < rhs.zIndex
        }
        return persistentKey(lhs) < persistentKey(rhs)
    }

    private static func preferredCutout(_ lhs: CutoutItem, _ rhs: CutoutItem) -> Bool {
        if lhs.lastModified != rhs.lastModified {
            return lhs.lastModified > rhs.lastModified
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return persistentKey(lhs) < persistentKey(rhs)
    }

    private static func stableBookOrder(_ lhs: BookGroup, _ rhs: BookGroup) -> Bool {
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return persistentKey(lhs) < persistentKey(rhs)
    }

    private static func stablePageOrder(_ lhs: Outfit, _ rhs: Outfit) -> Bool {
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return persistentKey(lhs) < persistentKey(rhs)
    }

    private static func persistentKey(_ model: (any PersistentModel)?) -> String {
        guard let model else { return "" }
        return String(describing: model.persistentModelID)
    }
}

@MainActor
final class OOTDDataRepairService {
    static let shared = OOTDDataRepairService()

    private let canvasWidth: Double = 1080
    private let canvasHeight: Double = 1440

    private init() {}

    func deepRepair(
        context: ModelContext,
        progress: ((String) -> Void)? = nil
    ) async -> OOTDDataRepairReport {
        var report = OOTDDataRepairReport()
        let fileManager = FileManager.default

        let cutoutDescriptor = FetchDescriptor<CutoutItem>()
        let clothingDescriptor = FetchDescriptor<Clothing>()
        let itemDescriptor = FetchDescriptor<OutfitItem>()
        let outfitDescriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate<Outfit> { $0.isDeleted == false }
        )

        let cutouts = (try? context.fetch(cutoutDescriptor)) ?? []
        let clothings = (try? context.fetch(clothingDescriptor)) ?? []
        let outfitItems = (try? context.fetch(itemDescriptor)) ?? []
        let outfits = (try? context.fetch(outfitDescriptor)) ?? []

        report.scannedCutouts = cutouts.count
        report.scannedOutfitItems = outfitItems.count
        report.scannedOutfits = outfits.count

        let clothingMap = ClothingDuplicateRepairService.preferredMap(from: clothings)
        let clothingByImageHash = buildClothingHashMap(clothings: clothings)
        var affectedOutfitIDs = Set<UUID>()

        func normalizeFileName(_ path: String) -> String {
            (path as NSString).lastPathComponent
        }

        func fileExists(_ pathOrFileName: String) -> Bool {
            let trimmed = pathOrFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if fileManager.fileExists(atPath: trimmed) { return true }
            let fileName = normalizeFileName(trimmed)
            guard !fileName.isEmpty else { return false }
            let inImages = ImageManager.shared.imagesDirectory.appendingPathComponent(fileName)
            return fileManager.fileExists(atPath: inImages.path)
        }

        var existingPathByHash: [String: String] = [:]
        for cutout in cutouts {
            let hash = cutout.originalImageHash.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = normalizeFileName(cutout.imagePath)
            if !hash.isEmpty, !fileName.isEmpty, fileExists(fileName) {
                existingPathByHash[hash] = fileName
            }
        }

        progress?("正在扫描贴纸文件...")
        for (index, cutout) in cutouts.enumerated() {
            if index % 20 == 0 {
                progress?("正在修复贴纸 \(index + 1)/\(cutouts.count)...")
            }

            var cutoutChanged = false
            if cutout.linkedClothingID == nil {
                let cutoutHash = cutout.originalImageHash.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cutoutHash.isEmpty,
                   let matchedClothing = clothingByImageHash[cutoutHash] {
                    cutout.linkedClothingID = matchedClothing.id
                    cutout.clothingName = matchedClothing.name
                    report.relinkedCutoutsToClothingByHash += 1
                    cutoutChanged = true
                }
            }
            let rawPath = cutout.imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPath = normalizeFileName(rawPath)

            if !normalizedPath.isEmpty, normalizedPath != rawPath {
                cutout.imagePath = normalizedPath
                report.normalizedCutoutPaths += 1
                cutoutChanged = true
            }

            var currentPath = cutout.imagePath.trimmingCharacters(in: .whitespacesAndNewlines)

            if !currentPath.isEmpty, !fileExists(currentPath) {
                let hash = cutout.originalImageHash.trimmingCharacters(in: .whitespacesAndNewlines)
                if !hash.isEmpty,
                   let mappedPath = existingPathByHash[hash],
                   fileExists(mappedPath) {
                    cutout.imagePath = mappedPath
                    currentPath = mappedPath
                    report.relinkedCutoutPathsByHash += 1
                    cutoutChanged = true
                }
            }

            if (currentPath.isEmpty || !fileExists(currentPath)),
               let linkedClothingID = cutout.linkedClothingID,
               let clothing = clothingMap[linkedClothingID],
               let sourcePath = clothing.imagePaths.first {
                let sourceName = normalizeFileName(sourcePath)
                if let sourceImage = ImageManager.shared.loadImage(fileName: sourceName) {
                    do {
                        try await CutoutService.shared.reprocessItem(
                            item: cutout,
                            with: sourceImage,
                            context: context
                        )
                        report.regeneratedCutoutImages += 1
                        cutoutChanged = true
                    } catch {
                        report.errors.append("重建贴纸失败 \(cutout.id): \(error.localizedDescription)")
                    }
                }
            }

            let finalPath = cutout.imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalPath.isEmpty || !fileExists(finalPath) {
                report.unresolvedCutoutFiles += 1
            } else {
                let hash = cutout.originalImageHash.trimmingCharacters(in: .whitespacesAndNewlines)
                if !hash.isEmpty {
                    existingPathByHash[hash] = normalizeFileName(finalPath)
                }
            }

            if cutoutChanged, let linkedItems = cutout.outfitItems {
                for item in linkedItems {
                    if let outfitID = item.outfit?.id {
                        affectedOutfitIDs.insert(outfitID)
                    }
                }
            }
        }

        progress?("正在修复贴纸坐标与引用...")
        for (index, item) in outfitItems.enumerated() {
            if index % 50 == 0 {
                progress?("正在修复实例 \(index + 1)/\(outfitItems.count)...")
            }

            if item.cutout == nil {
                report.unresolvedOutfitItemLinks += 1
                if let outfitID = item.outfit?.id {
                    affectedOutfitIDs.insert(outfitID)
                }
            } else if let cutout = item.cutout,
                      !cutout.imagePath.isEmpty,
                      !fileExists(cutout.imagePath),
                      let outfitID = item.outfit?.id {
                affectedOutfitIDs.insert(outfitID)
            }

            if normalizeCoordinatesIfNeeded(item: item, report: &report),
               let outfitID = item.outfit?.id {
                affectedOutfitIDs.insert(outfitID)
            }
        }

        progress?("正在重建书页预览...")
        for (index, outfit) in outfits.enumerated() {
            if index % 10 == 0 {
                progress?("正在重建快照 \(index + 1)/\(outfits.count)...")
            }

            let snapshotPath = outfit.snapshotPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let shouldRebuild = snapshotPath.isEmpty || !fileExists(snapshotPath) || affectedOutfitIDs.contains(outfit.id)

            guard shouldRebuild else { continue }

            if rebuildSnapshot(for: outfit, context: context) {
                report.rebuiltSnapshots += 1
            } else {
                report.failedSnapshots += 1
            }
        }

        do {
            try context.save()
        } catch {
            report.errors.append("保存修复结果失败: \(error.localizedDescription)")
        }

        progress?("修复完成")
        return report
    }

    private func normalizeCoordinatesIfNeeded(item: OutfitItem, report: inout OOTDDataRepairReport) -> Bool {
        var changed = false

        if item.coordinateVersion == 1 {
            item.x = item.x / canvasWidth
            item.y = item.y / canvasHeight
            item.coordinateVersion = 2
            report.migratedCoordinates += 1
            changed = true
        } else if abs(item.x) > 1.2 || abs(item.y) > 1.2 {
            if abs(item.x) <= canvasWidth * 1.5, abs(item.y) <= canvasHeight * 1.5 {
                item.x = item.x / canvasWidth
                item.y = item.y / canvasHeight
                report.migratedCoordinates += 1
                changed = true
            }
        }

        let clampedX = min(max(item.x, 0), 1)
        let clampedY = min(max(item.y, 0), 1)
        if clampedX != item.x || clampedY != item.y {
            item.x = clampedX
            item.y = clampedY
            report.clampedCoordinates += 1
            changed = true
        }

        return changed
    }

    private func rebuildSnapshot(for outfit: Outfit, context: ModelContext) -> Bool {
        let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
        renderer.scale = 0.5

        guard let image = renderer.uiImage,
              let newPath = ImageManager.shared.saveImage(image, context: context) else {
            return false
        }

        if let oldPath = outfit.snapshotPath, oldPath != newPath {
            ImageManager.shared.deleteImage(fileName: oldPath, context: context)
        }

        outfit.snapshotPath = newPath
        outfit.lastModified = Date()
        return true
    }

    private func buildClothingHashMap(clothings: [Clothing]) -> [String: Clothing] {
        var map: [String: Clothing] = [:]
        for clothing in clothings {
            guard let firstPath = clothing.imagePaths.first else { continue }
            let fileName = (firstPath as NSString).lastPathComponent
            guard !fileName.isEmpty,
                  let image = ImageManager.shared.loadImage(fileName: fileName),
                  let data = image.jpegData(compressionQuality: 0.5) else {
                continue
            }
            let digest = SHA256.hash(data: data)
            let hash = digest.map { String(format: "%02x", $0) }.joined()
            if map[hash] == nil {
                map[hash] = clothing
            }
        }
        return map
    }
}
