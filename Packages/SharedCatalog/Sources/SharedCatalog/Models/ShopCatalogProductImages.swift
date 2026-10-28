import Foundation

/// 入橱与全目录检查共用配色选图规则。多种配色可以明确绑定同一张合照。
public enum ShopCatalogProductImages {
    public static func references(product: CatalogProduct, variants: [CatalogProductVariant],
                                  selectedColor: String?, asset: (String) -> CatalogAsset?) -> [String] {
        func colorKey(_ value: String?) -> String? {
            CatalogVariantColorGrouping.normalizedColor(value)?
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        }
        func identity(_ reference: String) -> String {
            let source = ShopCatalogImageSource.resolve(reference, asset: asset)
            return source.mediaKey.map { "media/" + $0 } ?? source.references.first ?? reference
        }
        let variants = variants.filter { $0.productID == product.id }
        guard let selected = colorKey(selectedColor) else {
            return product.images.isEmpty ? variants.compactMap(\.imageAssetID) : product.images
        }
        let colors = Set(variants.compactMap { colorKey($0.color) })
        guard colors.isEmpty || colors.contains(selected) else { return [] }
        let matching = variants.filter { colorKey($0.color) == selected }
            .compactMap { CatalogVariantColorGrouping.normalizedColor($0.imageAssetID) }
        let matchingImages = Set(matching.map(identity))
        let otherImages = Set(variants.filter {
            colorKey($0.color).map { $0 != selected } ?? false
        }.compactMap { CatalogVariantColorGrouping.normalizedColor($0.imageAssetID) }.map(identity))
        var seen = Set<String>()
        return (matching + product.images).filter {
            let key = identity($0)
            // 所选颜色的明确绑定优先；仅属于其它配色的图才排除。
            return (matchingImages.contains(key) || !otherImages.contains(key)) && seen.insert(key).inserted
        }
    }
}
