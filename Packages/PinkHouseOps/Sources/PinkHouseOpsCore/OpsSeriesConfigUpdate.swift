import Foundation
import SharedCatalog

/// 显式保存的系列字段；应用到每个环境的最新目录，不携带其它本机待发布编辑。
public struct OpsSeriesConfigUpdate: Codable, Equatable, Sendable {
    public enum Field: String, Codable, Sendable { case schedule, cover, priceChart, productOrder }
    public var series: CatalogSeries
    public var shop: CatalogShop?
    public var fields: Set<Field>
    public var assets: [CatalogAsset]
    public var productOrders: [String: Int]? = nil
    /// 已确认发布的商品快照；排序只可补齐这些公开商品，不能把本机新草稿带上线。
    public var publishedOrderCatalog: ShopCatalog? = nil

    public init(series: CatalogSeries, shop: CatalogShop?, fields: Set<Field>, assets: [CatalogAsset] = [],
                productOrders: [String: Int]? = nil, publishedOrderCatalog: ShopCatalog? = nil) {
        self.series = series; self.shop = shop; self.fields = fields; self.assets = assets
        self.productOrders = productOrders
        self.publishedOrderCatalog = publishedOrderCatalog
    }

    /// 查询已证明本次未生效，且线上仍是冻结请求的完整基线时，才可原样续传。
    public static func canRetryFrozenPublish(queryExitCode: Int32?, outcome: ShopCatalogPublishOutcome?,
                                            head: ShopCatalogOnlineHead?, request: ShopCatalogPublishRequest) -> Bool {
        guard queryExitCode == 0, outcome == .failed,
              let head, let baseSeq = request.baseReleaseSeq,
              let baseHash = request.baseRootIndexHash, !baseHash.isEmpty else { return false }
        return head.environment == request.targetEnvironment.rawValue && head.releaseSeq == baseSeq &&
            head.rootIndexHash == baseHash && baseSeq < request.releaseSeq
    }

    public static func coalescing(_ updates: [Self], with update: Self) -> [Self] {
        var result = updates
        if let index = result.firstIndex(where: { $0.series.id == update.series.id }) {
            var combined = update
            combined.fields.formUnion(result[index].fields)
            if !update.fields.contains(.productOrder) {
                combined.productOrders = result[index].productOrders
                combined.publishedOrderCatalog = result[index].publishedOrderCatalog
            }
            let ids = Set(update.assets.map(\.id))
            combined.assets += result[index].assets.filter { !ids.contains($0.id) }
            result[index] = combined
        } else { result.append(update) }
        return result
    }

    public static func applying(_ updates: [Self], to remote: ShopCatalog) throws -> ShopCatalog {
        var result = remote
        for update in updates {
            let source = update.series
            if update.fields.contains(.productOrder) {
                guard let orders = update.productOrders, orders.values.allSatisfy({ $0 >= 0 }),
                      Set(orders.values).count == orders.count else { throw failure("商品排序记录不完整或有重复位置，请重新保存排序。") }
            }
            // 排序不能把尚未发布的系列或商品带上线，也不能恢复已下架内容。
            if update.fields == [.productOrder],
               !result.series.contains(where: { $0.id == source.id })
                || result.removedSeriesIDs.contains(source.id) || result.removedShopIDs.contains(source.shopID) { continue }
            guard !result.removedSeriesIDs.contains(source.id),
                  !result.removedShopIDs.contains(source.shopID) else {
                throw failure("系列「\(source.name)」或店家已在此环境下架，未自动恢复。")
            }
            if update.fields.contains(.schedule), let issue = CatalogReservationBatch.validationError(in: source.reservationBatches ?? []) {
                throw failure(issue)
            }
            if !result.shops.contains(where: { $0.id == source.shopID }), let shop = update.shop {
                result.shops.append(shop)
            }
            if !result.series.contains(where: { $0.id == source.id }) { result.series.append(source) }
            guard let index = result.series.firstIndex(where: { $0.id == source.id }) else { continue }
            if update.fields.contains(.schedule) {
                result.series[index].salePhase = source.salePhase
                result.series[index].reservationStartAt = source.reservationStartAt
                result.series[index].reservationEndAt = source.reservationEndAt
                result.series[index].balanceDueKind = source.balanceDueKind
                result.series[index].balanceDueText = source.balanceDueText
                result.series[index].balanceDueEndText = source.balanceDueEndText
                result.series[index].balanceDueAt = source.balanceDueAt
                result.series[index].balanceDueEndAt = source.balanceDueEndAt
                result.series[index].reservationBatches = source.reservationBatches
            }
            if update.fields.contains(.cover) { result.series[index].cover = source.cover }
            if update.fields.contains(.priceChart) { result.series[index].priceChart = source.priceChart }
            if update.fields.contains(.productOrder), let orders = update.productOrders {
                for p in result.products.indices {
                    guard let rank = orders[result.products[p].id],
                          !result.removedProductIDs.contains(result.products[p].id),
                          result.products[p].archivedAt == nil else { continue }
                    guard result.products[p].seriesID == source.id, result.products[p].shopID == source.shopID else {
                        throw failure("商品归属已变化，请重新打开当前系列的商品排序。")
                    }
                    result.products[p].displayOrder = rank
                }
            }
            for asset in update.assets {
                if let index = result.assets.firstIndex(where: { $0.id == asset.id }) { result.assets[index] = asset }
                else { result.assets.append(asset) }
            }
        }
        if updates.contains(where: { $0.fields.contains(.productOrder) }) {
            result.products = CatalogProductOrdering.publicationOrder(result.products)
        }
        let issues = ShopCatalogCloudSyncValidator.structuralIssues(result, coverageStatus: "complete")
        guard issues.isEmpty else { throw failure(issues.joined(separator: "；")) }
        return result
    }

    /// 只供缺失实体补齐器选取已发布商品；不会整包覆盖目标环境已有商品。
    public func productOrderDependencySeed() -> OpsCatalogEditorUpdate? {
        guard fields.contains(.productOrder), let orders = productOrders,
              var source = publishedOrderCatalog else { return nil }
        source.products = source.products.filter {
            orders[$0.id] != nil && $0.shopID == series.shopID && $0.seriesID == series.id && $0.archivedAt == nil
                && !source.removedProductIDs.contains($0.id)
        }
        for index in source.products.indices { source.products[index].displayOrder = orders[source.products[index].id] }
        var before = source
        before.products = []
        return .init(before: before, after: source)
    }

    /// 缺商品、缺系列或读回旧顺序都不能算排序同步完成。
    public static func verifyProductOrders(_ updates: [Self], in remote: ShopCatalog) throws {
        for update in updates where update.fields.contains(.productOrder) {
            guard let orders = update.productOrders else { throw failure("商品排序记录缺失，尚未完成核验。") }
            let required = Set(update.publishedOrderCatalog?.products.filter {
                orders[$0.id] != nil && $0.seriesID == update.series.id && $0.shopID == update.series.shopID
                    && $0.archivedAt == nil
            }.map(\.id) ?? Array(orders.keys))
            for id in required {
                guard let product = remote.products.first(where: { $0.id == id }),
                      product.archivedAt == nil, product.seriesID == update.series.id,
                      product.shopID == update.series.shopID,
                      !remote.removedProductIDs.contains(id), !remote.removedSeriesIDs.contains(product.seriesID),
                      !remote.removedShopIDs.contains(product.shopID), product.displayOrder == orders[id] else {
                    throw failure("系列「\(update.series.name)」的已发布商品 \(id) 缺失或顺序与保存不一致，排序同步尚未完成。")
                }
            }
            let visible = remote.products.filter {
                $0.seriesID == update.series.id && $0.shopID == update.series.shopID
                    && $0.archivedAt == nil && !remote.removedProductIDs.contains($0.id)
            }
            guard visible.map(\.id) == CatalogProductOrdering.ordered(visible).map(\.id) else {
                throw failure("系列「\(update.series.name)」商品列表的实际顺序仍与运营排序不一致，尚未确认同步完成。")
            }
        }
    }

    public static func archive(catalog: ShopCatalog, mediaDirectory: URL) throws -> Data {
        var entries = try ShopCatalogExportArchive.completeHandoffEntries(for: catalog, imageDirectory: mediaDirectory)
        let cached = OpsCachedMedia.files(in: mediaDirectory)
        for hash in OpsEnvironmentPromotion.mediaHashes(in: catalog) {
            if let url = cached[hash] {
                entries.append(.init(name: "images/" + url.lastPathComponent, data: try Data(contentsOf: url)))
            }
        }
        // 同一张图可能同时使用 local: 和 thmedia: 引用。
        var names = Set<String>()
        return ShopCatalogExportArchive.tarData(entries: entries.filter { names.insert($0.name).inserted })
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OpsSeriesConfigUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
