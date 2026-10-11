import Foundation
import SharedCatalog

/// 开发环境向线上增量合并；缺席不算删除，线上下架记录优先。
public enum OpsEnvironmentPromotion {
    public enum DifferenceChoice: String, CaseIterable, Identifiable {
        case development, production
        public var id: String { rawValue }
        public var displayName: String {
            self == .development ? "采用开发环境" : "保留线上环境"
        }
    }

    public struct Row: Identifiable, Sendable {
        public let kind: ShopCatalogEntityKind
        public let added: Int
        public let updated: Int
        public let retained: Int
        public var id: String { kind.rawValue }
    }

    public struct Plan: Sendable {
        public let catalog: ShopCatalog
        public let rows: [Row]
        public let differences: [String]
        public let differenceDescriptions: [String]
        public let requiredSourceMedia: [String]
        public var added: Int { rows.reduce(0) { $0 + $1.added } }
        public var updated: Int { rows.reduce(0) { $0 + $1.updated } }
        public var hasChanges: Bool { added > 0 || updated > 0 }
    }

    public static func plan(development: ShopCatalog, production: ShopCatalog,
                            choice: DifferenceChoice) throws -> Plan {
        // 先清除源环境已下架实体及子项，再移除源墓碑，避免把测试删除带到线上。
        var source = try ShopCatalogThreeWayMerge.merge(
            local: development, remote: ShopCatalog(), baseline: nil).catalog
        source.removedShopIDs = []
        source.removedSeriesIDs = []
        source.removedProductIDs = []
        let merged = try ShopCatalogThreeWayMerge.merge(
            local: source, remote: production, baseline: nil,
            preferLocalOnConflict: choice == .development)
        var catalog = merged.catalog
        let products = Set(catalog.products.map(\.id))
        let targetHistory = Set(production.saleEvents.map(\.id))
        // 下架商品的新历史不会进入发布包；已有线上历史仍保留。
        catalog.saleEvents.removeAll { !products.contains($0.productID) && !targetHistory.contains($0.id) }
        // 合并经过 JSON 往返，日期精度须与基线同口径，避免编码舍入被当成编辑。
        let baseline = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: ShopCatalogJSONCoding.encoder().encode(production))
        let delta = ShopCatalogChangeSetCalculator.diff(baseline: baseline, current: catalog)
        let comparison = ShopCatalogChangeSetCalculator.diff(baseline: source, current: production)
        let before = try object(production), after = try object(catalog)
        let fields: [ShopCatalogEntityKind: String] = [.shop: "shops", .series: "series", .product: "products",
            .variant: "variants", .sizeChart: "sizeCharts", .saleEvent: "saleEvents", .asset: "assets", .styleProfile: "styleProfiles"]
        let rows = ShopCatalogEntityKind.allCases.map { kind in
            let field = fields[kind]!
            let old = before[field] as? [[String: Any]] ?? []
            let new = after[field] as? [[String: Any]] ?? []
            let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0["id"] as! String, $0) })
            let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0["id"] as! String, $0) })
            // 实际发布比较持久化字段，不能把 JSON 往返的内存数值精度差异算作编辑。
            let updated = delta.delta(of: kind).modifiedIDs.filter { id in
                guard let previous = oldByID[id], let next = newByID[id] else { return true }
                return !NSDictionary(dictionary: previous).isEqual(to: next)
            }.count
            return Row(kind: kind, added: delta.delta(of: kind).addedIDs.count,
                updated: updated,
                retained: comparison.delta(of: kind).addedIDs.count)
        }
        let targetMedia = Set(mediaHashes(in: production))
        return Plan(catalog: catalog, rows: rows, differences: merged.conflicts,
                    differenceDescriptions: try describe(merged.conflicts, source: source, target: production),
                    requiredSourceMedia: mediaHashes(in: catalog).filter { !targetMedia.contains($0) })
    }

    private static func describe(_ paths: [String], source: ShopCatalog, target: ShopCatalog) throws -> [String] {
        let source = try object(source), target = try object(target)
        let kinds = ["shops": "店家", "series": "系列", "products": "商品", "variants": "规格",
                     "sizeCharts": "尺码表", "assets": "图片资源", "styleProfiles": "款式", "saleEvents": "销售记录"]
        let fields = ["name": "名称", "aliases": "别名", "logo": "图标", "cover": "封面", "images": "图片",
                      "price": "价格", "currency": "币种", "deposit": "定金", "balance": "尾款", "startAt": "开始日期",
                      "endAt": "结束日期", "category": "品类", "description": "说明", "notes": "备注",
                      "originalURL": "原图", "thumbnailURL": "缩略图", "previewURL": "预览图", "mediaKey": "图片内容",
                      "priceCorrection": "价格修正", "priceChart": "价格表", "color": "颜色", "sizes": "尺码"]
        func value(_ item: [String: Any], keys: [Substring]) -> String {
            var current: Any? = item
            for key in keys { current = (current as? [String: Any])?[String(key)] }
            guard let current, !(current is NSNull) else { return "未填写" }
            if let values = current as? [Any] { return "\(values.count) 项内容" }
            if current is [String: Any] { return "已填写" }
            let text = String(describing: current)
            return text.hasPrefix("thmedia:") ? "图片 \(text.dropFirst(8).prefix(12))…" : String(text.prefix(80))
        }
        return paths.map { path in
            let field = String(path.prefix { $0 != "." })
            let items = source[field] as? [[String: Any]] ?? []
            guard let item = items.first(where: { path.hasPrefix(field + "." + ($0["id"] as? String ?? "") + ".") }),
                  let id = item["id"] as? String else { return "目录内容差异" }
            let keys = path.dropFirst((field + "." + id + ".").count).split(separator: ".")
            let other = (target[field] as? [[String: Any]])?.first { $0["id"] as? String == id } ?? [:]
            let name = item["name"] as? String ?? item["designName"] as? String ?? id
            let label = keys.map { fields[String($0)] ?? "内容" }.joined(separator: " · ")
            return "\(kinds[field] ?? "条目")「\(name)」\(label)：线上 \(value(other, keys: keys)) → 开发 \(value(item, keys: keys))"
        }
    }

    private static func object(_ catalog: ShopCatalog) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: ShopCatalogJSONCoding.encoder().encode(catalog)) as! [String: Any]
    }

    public static func mediaHashes(in catalog: ShopCatalog) -> [String] {
        var hashes = Set(ShopCatalogMediaReferences.all(in: catalog).compactMap {
            ShopCatalogSyncProtocol.mediaContentHash(in: $0.reference)
        })
        hashes.formUnion(catalog.assets.compactMap { ShopCatalogSyncProtocol.resolvedMediaKey($0.mediaKey) })
        return hashes.sorted()
    }

    /// 只有源环境新增或更新的媒体随包；线上现存媒体由发布器按目标环境复核。
    public static func archive(plan: Plan, mediaDirectory: URL) throws -> Data {
        let local = ShopCatalogMediaReferences.all(in: plan.catalog).filter { $0.reference.hasPrefix("local:") }
        guard local.isEmpty else {
            throw failure("已发布目录仍含本机图片引用，请先在原环境通过云端更新补齐图片。")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path)
        var entries = [ShopCatalogExportArchive.Entry(name: "shop-catalog.json",
            data: try ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(plan.catalog))]
        for hash in plan.requiredSourceMedia {
            let candidates = names.sorted().filter { ($0 as NSString).deletingPathExtension == hash }
            guard !candidates.isEmpty else {
                throw failure("开发环境图片尚未下载：\(hash.prefix(12))。")
            }
            let verified = candidates.compactMap { name -> (String, Data)? in
                guard let data = try? Data(contentsOf: mediaDirectory.appendingPathComponent(name)),
                      ShopCatalogSyncProtocol.sha256Hex(data) == hash else { return nil }
                return (name, data)
            }.first
            guard let (name, data) = verified else {
                throw failure("图片内容摘要不符：\(hash.prefix(12))。")
            }
            entries.append(.init(name: "images/" + name, data: data))
        }
        return ShopCatalogExportArchive.tarData(entries: entries)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OpsEnvironmentPromotion", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
