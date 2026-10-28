import Foundation
import SharedCatalog

/// 一次显式保存的字段差分。每个环境仅应用这些字段，不复制整份工作区。
public struct OpsCatalogEditorUpdate: Codable, Equatable, Sendable {
    public var before: ShopCatalog
    public var after: ShopCatalog
    public init(before: ShopCatalog, after: ShopCatalog) { self.before = before; self.after = after }
    private static let fields = ["shops", "series", "products", "variants", "sizeCharts", "saleEvents", "assets", "styleProfiles"]

    public var isEmpty: Bool {
        guard let previous = try? Self.object(before), let next = try? Self.object(after) else { return false }
        return NSDictionary(dictionary: previous).isEqual(to: next)
    }

    /// 远端已是目标值时幂等成功；并发改了同一字段时明确失败，保留新远端值。
    public static func applying(_ updates: [Self], to remote: ShopCatalog,
                                mediaHashes: [String: String] = [:]) throws -> ShopCatalog {
        var result = try object(remote)
        func equal(_ a: Any?, _ b: Any?) -> Bool { Self.equal(a, b, mediaHashes: mediaHashes) }
        // 多次保存按「字段」合并，只取各字段最后的目标值；保留全部已知中间值供幂等重试。
        struct Change {
            var desired: [String: Any]?
            var keys: Set<String> = []
            var history: [[String: Any]] = []
            var isAddition = false
        }
        for field in fields {
            func index(_ object: [String: Any]) throws -> [String: [String: Any]] {
                var result: [String: [String: Any]] = [:]
                for item in object[field] as? [[String: Any]] ?? [] {
                    guard let id = item["id"] as? String, result[id] == nil else {
                        throw failure("\(field) 中有缺失或重复 ID，未同步。")
                    }
                    result[id] = item
                }
                return result
            }
            var changes: [String: Change] = [:]
            for update in updates {
                let old = try index(object(update.before)), new = try index(object(update.after))
                for id in Set(old.keys).union(new.keys).sorted() where !equal(old[id], new[id]) {
                    var change = changes[id] ?? Change(desired: old[id], isAddition: old[id] == nil)
                    if let previous = old[id] { change.history.append(previous) }
                    if let next = new[id] { change.history.append(next) }
                    if let previous = old[id], let next = new[id] {
                        for key in Set(previous.keys).union(next.keys) where !equal(previous[key], next[key]) {
                            change.keys.insert(key)
                            change.desired?[key] = next[key]
                        }
                    } else {
                        change.desired = new[id]
                        change.keys.formUnion(new[id]?.keys.map { $0 } ?? [])
                    }
                    changes[id] = change
                }
            }
            var current = try index(result)
            var order = (result[field] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            if field == "styleProfiles" {
                // 改名只是档案换键，各环境自己的面料/描述要随自己的档案迁移。
                // 不能把源环境旧档案整行复制到已有的新键，或把不同面料误判成名称冲突。
                for update in updates {
                    for oldProduct in update.before.products {
                        guard let next = update.after.products.first(where: { $0.id == oldProduct.id }) else { continue }
                        let oldKey = ShopCatalogStyleProfileSharing.styleKey(of: oldProduct)
                        let newKey = ShopCatalogStyleProfileSharing.styleKey(of: next)
                        guard oldKey != newKey,
                              let old = update.before.styleProfiles.first(where: { $0.id == oldKey }),
                              let new = update.after.styleProfiles.first(where: { $0.id == newKey }),
                              old.fabric == new.fabric, old.styleDescription == new.styleDescription else { continue }
                        if var source = current[oldKey] {
                            if var target = current[newKey] {
                                for key in ["fabric", "styleDescription"] where target[key] == nil { target[key] = source[key] }
                                current[newKey] = target
                            } else {
                                source["id"] = newKey; source["category"] = new.category
                                source["designName"] = new.designName
                                current[newKey] = source
                                order.append(newKey)
                            }
                            current[oldKey] = nil
                        }
                        changes[oldKey] = nil; changes[newKey] = nil
                    }
                }
            }
            for id in changes.keys.sorted() {
                let change = changes[id]!
                if let desired = change.desired {
                    if var online = current[id] {
                        if change.isAddition {
                            guard equal(online, desired) || change.history.contains(where: { equal($0, online) }) else {
                                throw failure("\(field).\(id) 已存在不同内容，未自动覆盖。")
                            }
                        }
                        for key in change.keys {
                            guard equal(online[key], desired[key]) || change.history.contains(where: { equal($0[key], online[key]) }) else {
                                throw failure("\(field).\(id).\(key) 在该环境也被修改，请核对后再保存；未覆盖远端。")
                            }
                            online[key] = desired[key]
                        }
                        current[id] = online
                    } else if desired["archivedAt"] != nil {
                        // 公共包不下发归档实体；本机归档颜色的改名仍保留在草稿中。
                        continue
                    } else if change.isAddition { current[id] = desired; order.append(id) }
                    else { throw failure("\(field).\(id) 在该环境不存在，请先发布该商品或系列。") }
                } else if let online = current[id] {
                    guard change.history.contains(where: { equal($0, online) }) else {
                        throw failure("\(field).\(id) 已在该环境修改，删除未同步。")
                    }
                    current[id] = nil
                }
            }
            result[field] = order.compactMap { current[$0] }
        }
        for update in updates {
            let before = try object(update.before), after = try object(update.after)
            for field in ["removedShopIDs", "removedSeriesIDs", "removedProductIDs"] {
                let old = Set(before[field] as? [String] ?? []), new = Set(after[field] as? [String] ?? [])
                var current = Set(result[field] as? [String] ?? [])
                current.formUnion(new.subtracting(old)); current.subtract(old.subtracting(new))
                result[field] = current.sorted()
            }
        }
        let decoded = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
        let cleaned = try ShopCatalogThreeWayMerge.merge(local: decoded, remote: ShopCatalog(), baseline: nil).catalog
        let issues = ShopCatalogCloudSyncValidator.structuralIssues(cleaned, coverageStatus: "complete")
        guard issues.isEmpty else { throw failure(issues.joined(separator: "；")) }
        return cleaned
    }

    /// 旧版可能只把商品发布到了一个环境。补齐本次编辑涉及的缺失商品及其引用闭包，
    /// 只新增缺失行，不复制其它商品、不覆盖目标环境已有字段，也不复活删除标记。
    public static func missingProductDependencies(_ updates: [Self], in remote: ShopCatalog,
                                                   confirmedSource: ShopCatalog? = nil) throws -> Self? {
        var sources = try object(confirmedSource ?? ShopCatalog())
        var changed: Set<String> = []
        var desired: [String: [String: Any]] = [:]
        for update in updates {
            let before = try object(update.before), after = try object(update.after)
            var old: [String: [String: Any]] = [:]
            for item in before["products"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String, old[id] == nil else { throw failure("商品 ID 缺失或重复，未同步。") }
                old[id] = item
            }
            var seen: Set<String> = []
            for item in after["products"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String, seen.insert(id).inserted else { throw failure("商品 ID 缺失或重复，未同步。") }
                if !equal(old[id], item, mediaHashes: [:]) { changed.insert(id) }
                desired[id] = item
            }
            for field in fields {
                var items = sources[field] as? [[String: Any]] ?? []
                for item in after[field] as? [[String: Any]] ?? [] {
                    if let index = items.firstIndex(where: { $0["id"] as? String == item["id"] as? String }) { items[index] = item }
                    else { items.append(item) }
                }
                sources[field] = items
            }
        }
        let existing = Set(remote.products.map(\.id))
        let ids = changed.subtracting(existing).filter { desired[$0]?["archivedAt"] == nil }
        guard !ids.isEmpty else { return nil }
        var result = try object(remote)
        func append(_ field: String, _ item: [String: Any]) {
            var rows = result[field] as? [[String: Any]] ?? []
            if !rows.contains(where: { $0["id"] as? String == item["id"] as? String }) { rows.append(item) }
            result[field] = rows
        }
        func source(_ field: String, _ id: String) -> [String: Any]? {
            (sources[field] as? [[String: Any]] ?? []).first { $0["id"] as? String == id }
        }
        for id in ids.sorted() {
            guard let product = desired[id], let shopID = product["shopID"] as? String,
                  let seriesID = product["seriesID"] as? String,
                  !remote.removedProductIDs.contains(id), !remote.removedShopIDs.contains(shopID),
                  !remote.removedSeriesIDs.contains(seriesID) else {
                throw failure("缺失商品已有下架标记，未自动恢复；请核对后明确重新上架。")
            }
            for (field, parentID) in [("shops", shopID), ("series", seriesID)] {
                if (result[field] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == parentID }) { continue }
                guard let parent = source(field, parentID), parent["archivedAt"] == nil else {
                    throw failure("缺失商品的店家或系列资料不完整，尚未同步。")
                }
                append(field, parent)
            }
            append("products", product)
            for field in ["variants", "sizeCharts", "saleEvents"] {
                for item in sources[field] as? [[String: Any]] ?? [] where item["productID"] as? String == id {
                    append(field, item)
                }
            }
        }
        let products = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])).products.filter { ids.contains($0.id) }
        let profileKeys = Set(products.map { ShopCatalogStyleProfileSharing.styleKey(of: $0) })
        for profile in sources["styleProfiles"] as? [[String: Any]] ?? [] where profileKeys.contains(profile["id"] as? String ?? "") {
            append("styleProfiles", profile)
        }
        var hydrated = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
        let refs = Set(ShopCatalogMediaReferences.all(in: hydrated).map(\.reference))
        for asset in sources["assets"] as? [[String: Any]] ?? [] where refs.contains(asset["id"] as? String ?? "") {
            append("assets", asset)
        }
        hydrated = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self,
            from: JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
        return .init(before: remote, after: hydrated)
    }

    /// 回读后的业务字段也必须与保存一致，不能只认发布号或进程退出码。
    public static func verify(_ updates: [Self], in remote: ShopCatalog,
                              mediaHashes: [String: String] = [:]) throws {
        let reapplied = try applying(updates, to: remote, mediaHashes: mediaHashes)
        guard try equivalent(reapplied, remote, mediaHashes: mediaHashes) else {
            throw failure("回读商品字段仍与已保存修改不一致，尚未确认同步完成。")
        }
    }

    public static func equivalent(_ lhs: ShopCatalog, _ rhs: ShopCatalog,
                                  mediaHashes: [String: String] = [:]) throws -> Bool {
        try equal(object(lhs), object(rhs), mediaHashes: mediaHashes)
    }

    private static func equal(_ a: Any?, _ b: Any?, mediaHashes: [String: String]) -> Bool {
            func normalized(_ value: Any?) -> Any {
                guard let value else { return NSNull() }
                if let ref = value as? String {
                    if let hash = mediaHashes[ref] ?? ShopCatalogSyncProtocol.mediaContentHash(in: ref) {
                        return ShopCatalogSyncProtocol.mediaReference(contentHash: hash)
                    }
                }
                if let array = value as? [Any] { return array.map { normalized($0) } }
                if let object = value as? [String: Any] { return object.mapValues { normalized($0) } }
                return value
            }
            return NSDictionary(dictionary: ["v": normalized(a)]).isEqual(to: ["v": normalized(b)])
        }

    private static func object(_ value: ShopCatalog) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: ShopCatalogJSONCoding.encoder().encode(value)) as! [String: Any]
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OpsCatalogEditorUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
