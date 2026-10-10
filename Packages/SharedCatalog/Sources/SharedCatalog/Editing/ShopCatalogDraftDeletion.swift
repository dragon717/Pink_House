import Foundation

/// 运营草稿的显式删除：清理下级实体，并记录发布同步所需的删除墓碑。
/// 图片资源可能被其他实体共用，保留资源与文件，避免级联误删共用图片。
public enum ShopCatalogDraftDeletion {
    public struct Summary: Equatable {
        public let seriesCount: Int
        public let productCount: Int
    }

    /// 店家下的商品取「直接归属店家」和「归属其系列」的并集，兼容归属字段不一致的旧数据。
    public static func removeShop(id: String, from catalog: inout ShopCatalog) -> Summary? {
        guard catalog.shops.contains(where: { $0.id == id }) else { return nil }
        let seriesIDs = catalog.series.filter { $0.shopID == id }.map(\.id)
        let seriesSet = Set(seriesIDs)
        let productIDs = catalog.products.filter {
            $0.shopID == id || seriesSet.contains($0.seriesID)
        }.map(\.id)

        removeProducts(ids: productIDs, from: &catalog)
        removeSeries(ids: seriesIDs, from: &catalog)
        catalog.shops.removeAll { $0.id == id }
        appendTombstones([id], to: &catalog.removedShopIDs)
        return Summary(seriesCount: seriesSet.count, productCount: Set(productIDs).count)
    }

    public static func removeSeries(id: String, from catalog: inout ShopCatalog) -> Summary? {
        guard catalog.series.contains(where: { $0.id == id }) else { return nil }
        let productIDs = catalog.products.filter { $0.seriesID == id }.map(\.id)
        removeProducts(ids: productIDs, from: &catalog)
        removeSeries(ids: [id], from: &catalog)
        return Summary(seriesCount: 1, productCount: Set(productIDs).count)
    }

    @discardableResult
    public static func removeProduct(id: String, from catalog: inout ShopCatalog) -> Bool {
        guard catalog.products.contains(where: { $0.id == id }) else { return false }
        removeProducts(ids: [id], from: &catalog)
        return true
    }

    private static func removeProducts(ids: [String], from catalog: inout ShopCatalog) {
        let idsSet = Set(ids)
        catalog.products.removeAll { idsSet.contains($0.id) }
        catalog.variants.removeAll { idsSet.contains($0.productID) }
        catalog.sizeCharts.removeAll { idsSet.contains($0.productID) }
        catalog.saleEvents.removeAll { idsSet.contains($0.productID) }
        appendTombstones(ids, to: &catalog.removedProductIDs)
    }

    private static func removeSeries(ids: [String], from catalog: inout ShopCatalog) {
        let idsSet = Set(ids)
        catalog.series.removeAll { idsSet.contains($0.id) }
        catalog.styleProfiles.removeAll { idsSet.contains($0.seriesID) }
        appendTombstones(ids, to: &catalog.removedSeriesIDs)
    }

    private static func appendTombstones(_ ids: [String], to tombstones: inout [String]) {
        var seen = Set(tombstones)
        for id in ids where seen.insert(id).inserted { tombstones.append(id) }
    }
}
