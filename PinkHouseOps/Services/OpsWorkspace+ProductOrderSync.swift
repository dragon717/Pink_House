import Foundation
import PinkHouseOpsCore
import SharedCatalog

extension OpsWorkspace {
    /// 只采用已确认的公共快照；本机尚未发布的图片、价格、名称都不混进排序任务。
    func publishedCatalogForProductOrder(seriesID: String) -> ShopCatalog? {
        guard let draft else { return nil }
        let states = draft.environmentBaselines.values.sorted {
            let left = $0.head.observedAt ?? .distantPast, right = $1.head.observedAt ?? .distantPast
            if left != right { return left < right }
            return ($0.head.environment ?? "", $0.head.releaseSeq ?? 0) < ($1.head.environment ?? "", $1.head.releaseSeq ?? 0)
        }
        let fields = ["shops", "series", "products", "variants", "sizeCharts", "saleEvents", "assets", "styleProfiles"]
        var merged: [String: Any] = [:]
        do {
            for state in states {
                let value = try JSONSerialization.jsonObject(with: ShopCatalogJSONCoding.encoder().encode(state.catalog)) as? [String: Any] ?? [:]
                for field in fields {
                    var rows = merged[field] as? [[String: Any]] ?? []
                    for row in value[field] as? [[String: Any]] ?? [] {
                        guard let id = row["id"] as? String else { continue }
                        if let known = state.knownFields, known[field + "." + id]?.contains("*") != true { continue }
                        if let index = rows.firstIndex(where: { $0["id"] as? String == id }) { rows[index] = row }
                        else { rows.append(row) }
                    }
                    merged[field] = rows
                }
            }
            var source = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
                from: JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]))
            source.products = source.products.filter { $0.seriesID == seriesID && $0.archivedAt == nil }
            guard !source.products.isEmpty else { return nil }
            return source
        } catch {
            return nil
        }
    }

    /// 旧版排序回执未核对缺失商品及发布数组顺序，升级后重核对已保存排序。
    /// 不改变工作副本或编辑版本，不采用尚未保存的拖动。
    @discardableResult
    func enqueueLegacyProductOrderRepairIfNeeded() -> Bool {
        guard let draft, !draft.isCorrupted, !hasUnsavedChanges, draft.hasEverPublished,
              (draft.catalogOrderDualSyncVersion ?? 0) < 2, draft.catalogSyncRequestID == nil else { return false }
        let updates = catalog.series.compactMap { series -> OpsSeriesConfigUpdate? in
            let products = catalog.products.filter { $0.seriesID == series.id && $0.archivedAt == nil }
            let pairs = products.compactMap { product in product.displayOrder.map { (product.id, $0) } }
            guard !pairs.isEmpty, pairs.allSatisfy({ $0.1 >= 0 }),
                  Set(pairs.map { $0.1 }).count == pairs.count,
                  let source = publishedCatalogForProductOrder(seriesID: series.id) else { return nil }
            return .init(series: series, shop: nil, fields: [.productOrder],
                         productOrders: Dictionary(uniqueKeysWithValues: pairs), publishedOrderCatalog: source)
        }
        guard !updates.isEmpty else { return false }
        let old = (draft.catalogSyncRequestID, draft.catalogSyncRevision, draft.catalogSyncEnvironment,
                   draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncSeriesReceiptsJSON,
                   draft.catalogSyncProgressJSON, draft.catalogSyncError, draft.catalogOrderDualSyncVersion)
        let id = UUID().uuidString
        let progress = OpsCatalogEditProgress(requestID: id, revision: savedRevision)
        do {
            draft.catalogSyncSeriesUpdatesJSON = try JSONEncoder().encode(updates)
            draft.catalogSyncSeriesReceiptsJSON = nil
            draft.catalogSyncRequestID = id; draft.catalogSyncRevision = savedRevision
            draft.catalogSyncEnvironment = OpsCloudSyncModel.shared.targetEnvironment.rawValue
            draft.catalogSyncError = nil
            draft.catalogSyncProgressJSON = try JSONEncoder().encode(progress)
            draft.catalogOrderDualSyncVersion = 2
            try saveCatalogContext(context)
            catalogEditSyncProgress = progress
            catalogEditSyncMessage = "正在重新核对已保存排序，更新商品列表以兼容现有测试版本…"
            return true
        } catch {
            (draft.catalogSyncRequestID, draft.catalogSyncRevision, draft.catalogSyncEnvironment,
             draft.catalogSyncSeriesUpdatesJSON, draft.catalogSyncSeriesReceiptsJSON,
             draft.catalogSyncProgressJSON, draft.catalogSyncError, draft.catalogOrderDualSyncVersion) = old
            catalogEditSyncMessage = "排序补同步任务尚未保存：\(error.localizedDescription)"
            return false
        }
    }
}
