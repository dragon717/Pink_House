import Foundation
import SharedCatalog

/// 显式保存的系列字段；应用到每个环境的最新目录，不携带其它本机待发布编辑。
public struct OpsSeriesConfigUpdate: Codable, Equatable, Sendable {
    public enum Field: String, Codable, Sendable { case schedule, cover, priceChart }
    public var series: CatalogSeries
    public var shop: CatalogShop?
    public var fields: Set<Field>
    public var assets: [CatalogAsset]

    public init(series: CatalogSeries, shop: CatalogShop?, fields: Set<Field>, assets: [CatalogAsset] = []) {
        self.series = series; self.shop = shop; self.fields = fields; self.assets = assets
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
            guard !result.removedSeriesIDs.contains(source.id),
                  !result.removedShopIDs.contains(source.shopID) else {
                throw failure("系列「\(source.name)」或店家已在此环境下架，未自动恢复。")
            }
            if let issue = CatalogReservationBatch.validationError(in: source.reservationBatches ?? []) {
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
            for asset in update.assets {
                if let index = result.assets.firstIndex(where: { $0.id == asset.id }) { result.assets[index] = asset }
                else { result.assets.append(asset) }
            }
        }
        let issues = ShopCatalogCloudSyncValidator.structuralIssues(result, coverageStatus: "complete")
        guard issues.isEmpty else { throw failure(issues.joined(separator: "；")) }
        return result
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
