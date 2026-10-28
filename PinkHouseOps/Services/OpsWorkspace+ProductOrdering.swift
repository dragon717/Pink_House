import Foundation
import SharedCatalog

extension OpsWorkspace {
    /// 已提交商品的排序入口；按 ID 和打开时的排序快照校验，保存失败回到原目录。
    @discardableResult
    func saveProductDisplayOrder(seriesID: String, orderedIDs: [String],
                                 expectedProducts: [CatalogProduct], expectedDraftID: String) -> Bool {
        guard canMutate(), let draft, draft.id == expectedDraftID else {
            lastError = "草稿已切换或不可写，请重新打开商品排序。"; return false
        }
        let current = catalog.products.filter { $0.seriesID == seriesID && $0.archivedAt == nil }
        let currentIDs = Set(current.map(\.id))
        guard !orderedIDs.isEmpty, Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == currentIDs, Set(expectedProducts.map(\.id)) == currentIDs,
              current.allSatisfy({ product in expectedProducts.contains {
                  $0.id == product.id && $0.seriesID == seriesID && $0.category == product.category
                      && $0.displayOrder == product.displayOrder
              } }) else {
            lastError = "商品清单或顺序已变化，请重新打开排序；当前商品未改动。"; return false
        }
        let ranks = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        let previous = catalog
        let revision = draft.draftRevision
        let reviewedRevision = draft.reviewedRevision
        for index in catalog.products.indices where currentIDs.contains(catalog.products[index].id) {
            catalog.products[index].displayOrder = ranks[catalog.products[index].id]
        }
        // 同样的顺序再次保存也须重新核对两个环境，不能因本机未变而漏掉之前未同步的排序。
        if catalog != previous { markDirty() }
        guard saveCatalogEditorChanges(seriesID: seriesID, fields: [.productOrder]) else {
            catalog = previous
            draft.draftRevision = revision
            draft.reviewedRevision = reviewedRevision
            return false
        }
        statusMessage = "商品顺序已保存，正在自动同步开发环境和用户环境中已上架商品的排序。"
        return true
    }

    /// 将向导里的行顺序写进商品事实；旧商品未在本次向导中出现时保持相对顺序、接在后面。
    /// 必须在条目都完成稳定商品 ID 映射后、整份目录落盘前调用。
    func applySeriesProductDisplayOrder(seriesID: String) {
        let existing = catalog.products.filter { $0.seriesID == seriesID }
        let validIDs = Set(existing.map(\.id))
        var seen: Set<String> = []
        var ids = seriesEntry.typeEntries.compactMap(\.committedProductID)
            .filter { validIDs.contains($0) && seen.insert($0).inserted }
        ids += CatalogProductOrdering.ordered(existing).map(\.id).filter { seen.insert($0).inserted }
        let ranks = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        var changed = false
        for index in catalog.products.indices where catalog.products[index].seriesID == seriesID {
            let rank = ranks[catalog.products[index].id]
            if catalog.products[index].displayOrder != rank {
                catalog.products[index].displayOrder = rank
                changed = true
            }
        }
        if changed { markDirty() }
    }
}
