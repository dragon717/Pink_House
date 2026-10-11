import Foundation

/// 入橱确认页的选择：主衣物默认入选，小物只由用户勾选。
struct ShopCatalogWardrobeMergeSelection {
    var primaryID: String?
    var accessoryIDs: Set<String> = []

    /// 仅小物入橱时，主条目不能再作为自己的小物重复计价 / 写入。
    var includedAccessoryIDs: Set<String> {
        accessoryIDs.subtracting([primaryID].compactMap { $0 })
    }

    mutating func initializePrimary(in products: [CatalogProduct]) {
        guard primaryID == nil else { return }
        primaryID = products.first { ShopCatalogWardrobeCategory.isPrimary($0.category) }?.id
            ?? products.first?.id
    }

    func includedProducts(in products: [CatalogProduct]) -> [CatalogProduct] {
        products.filter {
            ShopCatalogWardrobeCategory.isPrimary($0.category)
                || $0.id == primaryID || accessoryIDs.contains($0.id)
        }
    }
}
