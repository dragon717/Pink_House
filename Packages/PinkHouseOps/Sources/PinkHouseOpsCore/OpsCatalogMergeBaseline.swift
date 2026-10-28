import Foundation
import SharedCatalog

/// 内容比较的共同基线，按环境保存。局部发布只能确认相应字段，不能承认整份本地目录。
public struct OpsCatalogMergeBaseline: Codable, Equatable, Sendable {
    public var head: ShopCatalogBaseline
    public var catalog: ShopCatalog
    /// nil 为完整共同基线；否则只信任列出的实体/字段，"*" 表示该实体全部字段（含空值）。
    public var knownFields: [String: Set<String>]?

    public init(head: ShopCatalogBaseline, catalog: ShopCatalog,
                knownFields: [String: Set<String>]? = nil) {
        self.head = head; self.catalog = catalog; self.knownFields = knownFields
    }

    /// 旧草稿没有目标环境基线时，只迁入两份历史证据内容完全一致的实体。
    /// 不把另一环境的不同内容当作目标环境祖先，也不拿本次最新拉取值抹掉冲突。
    public static func commonAncestor(legacy: ShopCatalog?, previouslyConfirmed: ShopCatalog,
                                      head: ShopCatalogBaseline) throws -> Self {
        let encoder = ShopCatalogJSONCoding.encoder()
        func object(_ value: ShopCatalog) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        }
        let old = try legacy.map(object) ?? [:], remote = try object(previouslyConfirmed)
        var known: [String: Set<String>] = [:]
        for field in ["shops", "series", "products", "variants", "assets", "sizeCharts", "styleProfiles", "saleEvents"] {
            let previous = (old[field] as? [[String: Any]] ?? [])
            for item in remote[field] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String,
                      let ancestor = previous.first(where: { $0["id"] as? String == id }),
                      NSDictionary(dictionary: item).isEqual(to: ancestor) else { continue }
                known[field + "." + id] = ["*"]
            }
        }
        return Self(head: head, catalog: previouslyConfirmed, knownFields: known)
    }

    public func acknowledging(_ updates: [OpsSeriesConfigUpdate], head: ShopCatalogBaseline) throws -> Self {
        var result = self
        result.catalog = try OpsSeriesConfigUpdate.applying(updates, to: catalog)
        result.head = head
        if result.knownFields != nil {
            for update in updates {
                let path = "series." + update.series.id
                var keys = result.knownFields?[path] ?? []
                if update.fields.contains(.schedule) {
                    keys.formUnion(["salePhase", "reservationStartAt", "reservationEndAt", "balanceDueKind",
                                    "balanceDueText", "balanceDueEndText", "balanceDueAt", "balanceDueEndAt", "reservationBatches"])
                }
                if update.fields.contains(.cover) { keys.insert("cover") }
                if update.fields.contains(.priceChart) { keys.insert("priceChart") }
                result.knownFields?[path] = keys
                for asset in update.assets { result.knownFields?["assets." + asset.id] = ["*"] }
                if update.fields.contains(.productOrder) {
                    for id in update.productOrders?.keys.sorted() ?? [] where result.catalog.products.contains(where: { $0.id == id }) {
                        result.knownFields?["products." + id, default: []].insert("displayOrder")
                    }
                }
            }
        }
        return result
    }

    /// 只恢复同一草稿、同一冻结载荷且已真实写入并回读确认的任务。
    /// 解包读取的原始输入可能被替换，因此直接从摘要匹配的 USTAR 读取目录。
    public static func recoverConfirmedSeriesJob(at directory: URL, draftID: String,
                                                 legacy: ShopCatalog?, existing: Self? = nil) throws -> Self? {
        let request = try ShopCatalogPublishRequest.decoded(from: Data(contentsOf: directory.appendingPathComponent("publish-request.json")))
        guard request.draftID == draftID, !request.dryRun else { return nil }
        // 路径约束：恢复仅访问该任务目录，不能追随请求去读别处的文件。
        func within(_ path: String) -> Bool {
            URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/")
        }
        guard [request.archivePath, request.receiptPath, request.outputDirectory].allSatisfy(within) else { return nil }
        let receipt = try ShopCatalogPublishReceipt.decoded(from: Data(contentsOf: URL(fileURLWithPath: request.receiptPath)))
        let artifact = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: request.outputDirectory).appendingPathComponent("release.json"))) as? [String: Any]
        guard receipt.applied == true, receipt.readBackConfirmed == true,
              receipt.requestID == request.requestID, receipt.jobID == request.jobID,
              receipt.draftID == request.draftID, receipt.draftRevision == request.draftRevision,
              receipt.environment == request.targetEnvironment.rawValue,
              receipt.releaseSeq == request.releaseSeq, receipt.artifactDigest == request.payloadHash,
              let hash = receipt.rootIndexHash, ShopCatalogSyncProtocol.isPayloadHash(hash),
              artifact?["rootIndexHash"] as? String == hash,
              artifact?["releaseSeq"] as? Int == request.releaseSeq else { return nil }
        let archive = try Data(contentsOf: URL(fileURLWithPath: request.archivePath))
        guard ShopCatalogSyncProtocol.sha256Hex(archive) == request.payloadHash else { return nil }
        let confirmed = try catalogInArchive(archive)
        let prior = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: Data(contentsOf: directory.appendingPathComponent("pulled/shop-catalog.json")))
        let head = ShopCatalogBaseline(releaseSeq: request.releaseSeq, rootIndexHash: hash,
            environment: request.targetEnvironment.rawValue, observedAt: receipt.verifiedAt)
        var seed = try existing ?? commonAncestor(legacy: legacy, previouslyConfirmed: confirmed, head: head)
        // 历史任务未另外存字段清单；只承认旧远端与冻结载荷之间实际变化的受管字段。
        for series in confirmed.series {
            guard let before = prior.series.first(where: { $0.id == series.id }) else {
                if let index = seed.catalog.series.firstIndex(where: { $0.id == series.id }) {
                    seed.catalog.series[index] = series
                } else { seed.catalog.series.append(series) }
                if seed.knownFields != nil { seed.knownFields?["series." + series.id] = ["*"] }
                continue
            }
            var fields: Set<OpsSeriesConfigUpdate.Field> = []
            if series.salePhase != before.salePhase || series.reservationStartAt != before.reservationStartAt
                || series.reservationEndAt != before.reservationEndAt || series.balanceDueKind != before.balanceDueKind
                || series.balanceDueText != before.balanceDueText || series.balanceDueEndText != before.balanceDueEndText
                || series.balanceDueAt != before.balanceDueAt || series.balanceDueEndAt != before.balanceDueEndAt
                || series.reservationBatches != before.reservationBatches { fields.insert(.schedule) }
            if series.cover != before.cover { fields.insert(.cover) }
            if series.priceChart != before.priceChart { fields.insert(.priceChart) }
            if !fields.isEmpty {
                seed = try seed.acknowledging([.init(series: series, shop: nil, fields: fields)], head: head)
            }
        }
        for shop in confirmed.shops where !prior.shops.contains(where: { $0.id == shop.id }) {
            if !seed.catalog.shops.contains(where: { $0.id == shop.id }) { seed.catalog.shops.append(shop) }
            if seed.knownFields != nil { seed.knownFields?["shops." + shop.id] = ["*"] }
        }
        for product in confirmed.products {
            guard let before = prior.products.first(where: { $0.id == product.id }),
                  before.displayOrder != product.displayOrder else { continue }
            if let index = seed.catalog.products.firstIndex(where: { $0.id == product.id }) {
                seed.catalog.products[index].displayOrder = product.displayOrder
                if seed.knownFields != nil { seed.knownFields?["products." + product.id, default: []].insert("displayOrder") }
            }
        }
        for asset in confirmed.assets where prior.assets.first(where: { $0.id == asset.id }) != asset {
            if let index = seed.catalog.assets.firstIndex(where: { $0.id == asset.id }) {
                seed.catalog.assets[index] = asset
            } else { seed.catalog.assets.append(asset) }
            if seed.knownFields != nil { seed.knownFields?["assets." + asset.id] = ["*"] }
        }
        seed.head = head
        return seed
    }

    public static func catalogInArchive(_ archive: Data) throws -> ShopCatalog {
        func invalid() -> NSError { NSError(domain: "OpsBaseline", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "冻结目录归档不完整，未恢复基线"]) }
        guard archive.count >= 512,
              String(decoding: archive[0..<100].prefix { $0 != 0 }, as: UTF8.self) == "shop-catalog.json",
              let size = Int(String(decoding: archive[124..<136].prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces), radix: 8),
              size > 0, size <= 64 * 1024 * 1024, archive.count - 512 >= size else { throw invalid() }
        return try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: archive.subdata(in: 512..<(512 + size)))
    }
}
