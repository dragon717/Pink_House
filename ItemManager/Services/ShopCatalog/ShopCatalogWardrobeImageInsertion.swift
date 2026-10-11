import SwiftData

extension ShopCatalogWardrobeInserter {
    /// 先完整保存图片，再提交衣橱记录。失败时释放本次取得的图片引用。
    @MainActor
    static func insertWithImages(
        draft: ClothingEditDraft,
        selection: ShopCatalogWardrobeDraftBuilder.Selection,
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) async throws -> Clothing {
        let result = try await insertSetWithImages(
            drafts: [(draft, selection)], accessoryProductIDs: [],
            store: store, modelContext: modelContext)
        return result[0]
    }

    @MainActor
    static func insertSetWithImages(
        drafts: [(draft: ClothingEditDraft, selection: ShopCatalogWardrobeDraftBuilder.Selection?)],
        accessoryProductIDs: Set<String>,
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) async throws -> [Clothing] {
        var prepared = drafts
        var acquiredPaths: [String] = []
        var accessoryImages: [String: [String]] = [:]
        do {
            for (index, entry) in drafts.enumerated() {
                guard entry.draft.imagePaths.isEmpty, let selection = entry.selection else { continue }
                guard let product = store.product(id: selection.productID) else {
                    throw ShopCatalogWardrobeError.productNotFound(selection.productID)
                }
                let paths = try await ShopCatalogWardrobeImageImporter.materialize(
                    product: product, store: store, modelContext: modelContext)
                acquiredPaths += paths
                prepared[index].draft = entry.draft.with(imagePaths: paths)
            }
            for id in accessoryProductIDs.sorted() {
                guard let product = store.product(id: id) else {
                    throw ShopCatalogWardrobeError.productNotFound(id)
                }
                let paths = try await ShopCatalogWardrobeImageImporter.materialize(
                    product: product, store: store, modelContext: modelContext)
                acquiredPaths += paths
                accessoryImages[id] = paths
            }
            try Task.checkCancellation()
            let inserted = try insertSet(drafts: prepared, accessoryProductIDs: accessoryProductIDs,
                                         store: store, modelContext: modelContext,
                                         accessoryImagePaths: accessoryImages)
            if !ShopCatalogAutoRefresh.isTestHost {
                Task { await ClothingImageSyncService.shared.syncPendingImages() }
            }
            return inserted
        } catch {
            ShopCatalogWardrobeImageImporter.release(acquiredPaths, modelContext: modelContext)
            throw error
        }
    }
}
