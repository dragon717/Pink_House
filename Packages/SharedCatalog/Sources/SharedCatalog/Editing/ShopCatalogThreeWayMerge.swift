import Foundation

/// 同步按稳定 ID 合并；只有两边都改了同一字段才需明确选择。
/// 数组（图片顺序、尺码表行等）作为一个值，避免拼出没有人编辑过的内容。
public nonisolated enum ShopCatalogThreeWayMerge {
    public struct Result {
        public let catalog: ShopCatalog
        public let conflicts: [String]
    }

    public static func merge(
        local: ShopCatalog, remote: ShopCatalog, baseline: ShopCatalog?,
        mediaHashesByLocalReference: [String: String] = [:],
        preferLocalOnConflict: Bool = false
    ) throws -> Result {
        func object(_ catalog: ShopCatalog) throws -> [String: Any] {
            let data = try ShopCatalogJSONCoding.encoder().encode(catalog)
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        let l = try object(local), r = try object(remote)
        let b = try baseline.map(object)
        var result = r
        var conflicts: [String] = []
        let fields = ["shops", "series", "products", "variants", "sizeCharts", "assets",
                      "styleProfiles", "saleEvents"]
        for field in fields {
            let localItems = l[field] as? [[String: Any]] ?? []
            let remoteItems = r[field] as? [[String: Any]] ?? []
            let baseItems = b?[field] as? [[String: Any]] ?? []
            func index(_ items: [[String: Any]]) throws -> [String: [String: Any]] {
                var output: [String: [String: Any]] = [:]
                for item in items {
                    guard let id = item["id"] as? String, output[id] == nil else {
                        throw NSError(domain: "CatalogMerge", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "\(field) 存在缺失或重复 ID"])
                    }
                    output[id] = item
                }
                return output
            }
            let localIndex = try index(localItems), remoteIndex = try index(remoteItems)
            let baseIndex = try index(baseItems)
            var items: [[String: Any]] = []
            for item in remoteItems {
                let id = item["id"] as! String
                if let localItem = localIndex[id] {
                    items.append(mergeObject(localItem, item, baseIndex[id],
                                             path: "\(field).\(id)", conflicts: &conflicts, mediaHashes: mediaHashesByLocalReference, preferLocal: preferLocalOnConflict))
                } else {
                    items.append(item)
                }
            }
            // 公共包不含归档实体；「没有」不代表「删除」，显式墓碑才代表删除。
            items.append(contentsOf: localItems.filter { remoteIndex[$0["id"] as! String] == nil })
            result[field] = items
        }
        for field in ["removedShopIDs", "removedSeriesIDs", "removedProductIDs"] {
            var seen: Set<String> = []
            result[field] = ((r[field] as? [String] ?? []) + (l[field] as? [String] ?? []))
                .filter { seen.insert($0).inserted }
        }
        var merged = try ShopCatalogJSONCoding.decoder().decode(
            ShopCatalog.self, from: JSONSerialization.data(withJSONObject: result))
        // 删除先于实体；阻止合并把已删商品重新补回来，或制造实体/墓碑冲突。
        let shops = Set(merged.removedShopIDs)
        let series = Set(merged.removedSeriesIDs).union(
            merged.series.filter { shops.contains($0.shopID) }.map(\.id))
        let products = Set(merged.removedProductIDs).union(merged.products.filter {
            shops.contains($0.shopID) || series.contains($0.seriesID)
        }.map(\.id))
        merged.removedSeriesIDs = series.sorted()
        merged.removedProductIDs = products.sorted()
        merged.shops.removeAll { shops.contains($0.id) }
        merged.series.removeAll { series.contains($0.id) }
        merged.products.removeAll { products.contains($0.id) }
        merged.variants.removeAll { products.contains($0.productID) }
        merged.sizeCharts.removeAll { products.contains($0.productID) }
        // 已删商品的销售历史按墓碑保留，合并不改写或删除既有记录。
        merged.styleProfiles.removeAll { series.contains($0.seriesID) }
        return Result(catalog: merged, conflicts: conflicts)
    }

    private static func same(_ lhs: Any?, _ rhs: Any?, mediaHashes: [String: String]) -> Bool {
        func normalized(_ value: Any?) -> Any? {
            if let reference = value as? String, let hash = mediaHashes[reference] {
                return ShopCatalogSyncProtocol.mediaReference(contentHash: hash)
            }
            if let items = value as? [Any] { return items.map { normalized($0) ?? NSNull() } }
            if let object = value as? [String: Any] { return object.mapValues { normalized($0) ?? NSNull() } }
            return value
        }
        let lhs = normalized(lhs), rhs = normalized(rhs)
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?): return NSDictionary(dictionary: ["value": l])
            .isEqual(to: ["value": r])
        default: return false
        }
    }

    private static func mergeObject(
        _ local: [String: Any], _ remote: [String: Any], _ baseline: [String: Any]?,
        path: String, conflicts: inout [String], mediaHashes: [String: String], preferLocal: Bool
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Set(local.keys).union(remote.keys).union(baseline?.keys.map { $0 } ?? []).sorted() {
            let l = local[key], r = remote[key], b = baseline?[key]
            if same(l, r, mediaHashes: mediaHashes) { result[key] = l }
            else if baseline != nil && same(r, b, mediaHashes: mediaHashes) { result[key] = l }
            else if baseline != nil && same(l, b, mediaHashes: mediaHashes) { result[key] = r }
            else if let ld = l as? [String: Any], let rd = r as? [String: Any],
                    let bd = b as? [String: Any] {
                result[key] = mergeObject(ld, rd, bd, path: "\(path).\(key)", conflicts: &conflicts, mediaHashes: mediaHashes, preferLocal: preferLocal)
            } else {
                conflicts.append("\(path).\(key)")
                result[key] = preferLocal ? l : r // 用户在确认时明确选择争议字段的来源。
            }
        }
        return result
    }
}
