import SwiftUI

/// 所有商品在同一页选好，一次确认后分别保存为独立衣物。
struct ShopCatalogWardrobeIndividualAdditionView: View {
    let addition: ShopCatalogWardrobeIndividualAddition
    @ObservedObject var store: ShopCatalogStore
    let priceChoices: [String: ShopCatalogCardPriceChoice]
    let colorByProduct: [String: String]
    let sizeByProduct: [String: String]
    let onProductsAdded: ([String]) -> Void

    init(addition: ShopCatalogWardrobeIndividualAddition,
         priceChoices: [String: ShopCatalogCardPriceChoice],
         colorByProduct: [String: String], sizeByProduct: [String: String],
         store: ShopCatalogStore, onProductsAdded: @escaping ([String]) -> Void) {
        self.addition = addition
        self.priceChoices = priceChoices
        self.colorByProduct = colorByProduct
        self.sizeByProduct = sizeByProduct
        self.store = store
        self.onProductsAdded = onProductsAdded
    }

    var body: some View {
        NavigationStack {
            ShopCatalogWardrobeMergeView(
                selectedProductIDs: addition.productIDs,
                priceChoices: priceChoices,
                colorByProduct: colorByProduct,
                sizeByProduct: sizeByProduct,
                store: store,
                saveIndividually: true
            ) { _ in
                onProductsAdded(addition.productIDs)
            }
        }
    }
}
