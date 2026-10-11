import SwiftData

/// 用户确认入橱的唯一入口。纯导入/恢复代码仍使用 Inserter，不产生 UI 或奖励。
@MainActor
enum ShopCatalogWardrobeAddition {
    @discardableResult
    static func add(draft: ClothingEditDraft,
                    selection: ShopCatalogWardrobeDraftBuilder.Selection,
                    store: ShopCatalogStore, modelContext: ModelContext,
                    successMessage: String? = nil) async throws -> Clothing {
        let result = try await addSet(drafts: [(draft, selection)], accessoryProductIDs: [],
                                     store: store, modelContext: modelContext,
                                     successMessage: successMessage)
        return result[0]
    }

    @discardableResult
    static func addSet(
        drafts: [(draft: ClothingEditDraft, selection: ShopCatalogWardrobeDraftBuilder.Selection?)],
        accessoryProductIDs: Set<String>, store: ShopCatalogStore,
        modelContext: ModelContext, successMessage: String? = nil
    ) async throws -> [Clothing] {
        let inserted = try await ShopCatalogWardrobeInserter.insertSetWithImages(
            drafts: drafts, accessoryProductIDs: accessoryProductIDs,
            store: store, modelContext: modelContext)
        WardrobeOperationFeedback.completeTimeHallAddition(inserted, context: modelContext,
                                                          message: successMessage)
        return inserted
    }
}
