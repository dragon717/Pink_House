import Foundation

/// 一次确认、一批保存；每个勾选商品（包括小物）均生成独立衣橱记录。
struct ShopCatalogWardrobeIndividualAddition: Identifiable {
    let id = UUID()
    let productIDs: [String]

    init(productIDs: [String]) {
        var seen = Set<String>()
        self.productIDs = productIDs.filter { seen.insert($0).inserted }
    }

    @MainActor
    func makeDrafts(selections: [ShopCatalogWardrobeDraftBuilder.Selection],
                    store: ShopCatalogStore, note: String = "") throws
        -> [(draft: ClothingEditDraft, selection: ShopCatalogWardrobeDraftBuilder.Selection)] {
        guard !productIDs.isEmpty else { throw ShopCatalogWardrobeError.emptySelection }
        let choices = Dictionary(selections.map { ($0.productID, $0) }, uniquingKeysWith: { first, _ in first })
        return try productIDs.map { id in
            guard let selection = choices[id],
                  let draft = ShopCatalogWardrobeDraftBuilder.makeDraft(selection: selection, store: store)
            else { throw ShopCatalogWardrobeError.productNotFound(id) }
            return (draft.with(note: note), selection)
        }
    }
}
