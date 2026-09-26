//
//  ShopCatalogChangeSet.swift
//  SharedCatalog
//
//  变更集：**这一次到底改了什么**（方案 §4.3 / R07 / T14）。
//
//  ## 为什么两套口径都要有
//
//  操作单位是**商品**，发布单位仍是**整包**（方案 §5）。于是有两个问题要回答：
//
//   1. 「本次改动范围」—— 用于发布前给运营确认「我只改了这几个商品」、
//      也用于严格发布策略的作用域（R08：只对**新创建 / 修改**的内容收紧校验，
//      不能用严格规则去追溯阻断存量旧数据）；
//   2. 「与线上基线的差异」—— 用于回答「我这份包发出去会不会把别人的改动抹掉」。
//
//  这两个问题**数据来源不同**，所以本文件定义两份事实：
//
//   · `ShopCatalogTouchedIDs` —— **本地变更追踪**。任何编辑命令都会把实体 id 记进来，
//     落盘在草稿记录上。它不依赖能不能读到线上，永远可用，
//     所以严格策略的作用域靠它，不靠基线；
//   · `ShopCatalogChangeSet` —— **与基线的差分**。需要一份基线目录才有意义；
//     没有基线时 `hasBaseline == false`，界面必须显示「无法比较」而不是「没有改动」。
//
//  ## 差分为什么不比字节
//
//  比「整包 JSON 字节」只能得出「变了 / 没变」，而运营要的是
//  「哪几个商品变了」。所以逐实体按 id 建表比 `Equatable`：
//  同 id 两侧相等 = 未改，只有一侧有 = 新增/删除，两侧不等 = 修改。
//  所有实体都是 `Hashable & Equatable`，不需要再算摘要。
//
//  ⚠️ 墓碑（`removedShopIDs` / `removedSeriesIDs` / `removedProductIDs`）要单独列：
//  它表达的是「下架」，不是「漏传」，2026-09-24 那条 P0 就是回滚时忘了它。
//

import Foundation

// MARK: - 实体类别

/// 目录里可被独立追踪 / 差分的实体类别。
public nonisolated enum ShopCatalogEntityKind: String, Codable, CaseIterable, Sendable {
    case shop
    case series
    case product
    case variant
    case sizeChart
    case saleEvent
    case asset
    case styleProfile

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .shop: return "店家"
        case .series: return "系列"
        case .product: return "商品"
        case .variant: return "规格"
        case .sizeChart: return "尺码表"
        case .saleEvent: return "销售记录"
        case .asset: return "图片资源"
        case .styleProfile: return "款式档案"
        }
    }

    /// 单数形式（报错文案用：「1 个商品」而不是「1 个商品s」）
    public var singularName: String {
        switch self {
        case .shop: return "店家"
        case .series: return "系列"
        case .product: return "商品"
        case .variant: return "规格"
        case .sizeChart: return "尺码表"
        case .saleEvent: return "销售记录"
        case .asset: return "图片资源"
        case .styleProfile: return "款式档案"
        }
    }

    /// 该类别是否有删除墓碑（只有店家 / 系列 / 商品有）
    public var hasTombstone: Bool {
        switch self {
        case .shop, .series, .product: return true
        case .variant, .sizeChart, .saleEvent, .asset, .styleProfile: return false
        }
    }
}

// MARK: - 本地变更追踪

/// 本次会话中**被动过**的实体 id 集合（新增 / 修改 / 删除都算）。
///
/// 落盘形态是一段 JSON（草稿记录上的 `touchedIDsJSON`），所以本类型 `Codable`。
/// **故意不含时间戳**：它只回答「动过没有」，回答「什么时候动的」是另一个问题，
/// 而这个集合会被频繁合并写回，塞时间戳只会让相等判断变复杂。
public nonisolated struct ShopCatalogTouchedIDs: Codable, Equatable, Sendable {

    public var shopIDs: [String]
    public var seriesIDs: [String]
    public var productIDs: [String]
    public var variantIDs: [String]
    public var sizeChartIDs: [String]
    public var saleEventIDs: [String]
    public var assetIDs: [String]
    public var styleProfileIDs: [String]

    public init(
        shopIDs: [String] = [],
        seriesIDs: [String] = [],
        productIDs: [String] = [],
        variantIDs: [String] = [],
        sizeChartIDs: [String] = [],
        saleEventIDs: [String] = [],
        assetIDs: [String] = [],
        styleProfileIDs: [String] = []
    ) {
        self.shopIDs = shopIDs
        self.seriesIDs = seriesIDs
        self.productIDs = productIDs
        self.variantIDs = variantIDs
        self.sizeChartIDs = sizeChartIDs
        self.saleEventIDs = saleEventIDs
        self.assetIDs = assetIDs
        self.styleProfileIDs = styleProfileIDs
    }

    public var isEmpty: Bool {
        shopIDs.isEmpty && seriesIDs.isEmpty && productIDs.isEmpty && variantIDs.isEmpty
            && sizeChartIDs.isEmpty && saleEventIDs.isEmpty && assetIDs.isEmpty
            && styleProfileIDs.isEmpty
    }

    /// 全部 id（跨类别合并，稳定顺序）。严格策略的作用域直接用它。
    public var allIDs: [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for id in shopIDs + seriesIDs + productIDs + variantIDs
            + sizeChartIDs + saleEventIDs + assetIDs + styleProfileIDs
        where seen.insert(id).inserted {
            output.append(id)
        }
        return output
    }

    /// 按类别取。
    public func ids(of kind: ShopCatalogEntityKind) -> [String] {
        switch kind {
        case .shop: return shopIDs
        case .series: return seriesIDs
        case .product: return productIDs
        case .variant: return variantIDs
        case .sizeChart: return sizeChartIDs
        case .saleEvent: return saleEventIDs
        case .asset: return assetIDs
        case .styleProfile: return styleProfileIDs
        }
    }

    public func contains(_ id: String, in kind: ShopCatalogEntityKind) -> Bool {
        ids(of: kind).contains(id)
    }

    /// 合并一个 id（去重）。
    public mutating func insert(_ id: String, into kind: ShopCatalogEntityKind) {
        guard !id.isEmpty, !contains(id, in: kind) else { return }
        switch kind {
        case .shop: shopIDs.append(id)
        case .series: seriesIDs.append(id)
        case .product: productIDs.append(id)
        case .variant: variantIDs.append(id)
        case .sizeChart: sizeChartIDs.append(id)
        case .saleEvent: saleEventIDs.append(id)
        case .asset: assetIDs.append(id)
        case .styleProfile: styleProfileIDs.append(id)
        }
    }

    /// 合并一批 id。
    public mutating func insert(_ ids: [String], into kind: ShopCatalogEntityKind) {
        for id in ids { insert(id, into: kind) }
    }

    /// 合并另一个集合（并集，顺序稳定）。
    public mutating func formUnion(_ other: ShopCatalogTouchedIDs) {
        for kind in ShopCatalogEntityKind.allCases {
            insert(other.ids(of: kind), into: kind)
        }
    }

    public func union(_ other: ShopCatalogTouchedIDs) -> ShopCatalogTouchedIDs {
        var copy = self
        copy.formUnion(other)
        return copy
    }

    /// 编码成落盘字节。失败时返回 nil，调用方**不得**把 nil 当「没有改动」——
    /// 那会把「记录丢了」伪装成「什么都没改」。
    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    public static func decoded(from data: Data?) -> ShopCatalogTouchedIDs {
        guard let data, !data.isEmpty else { return ShopCatalogTouchedIDs() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ShopCatalogTouchedIDs.self, from: data))
            ?? ShopCatalogTouchedIDs()
    }
}

// MARK: - 逐类别差异

public nonisolated struct ShopCatalogEntityDelta: Equatable, Sendable {
    public var kind: ShopCatalogEntityKind
    /// 基线里没有、当前有（新增）
    public var addedIDs: [String]
    /// 基线里有、当前没有（真删除；与墓碑不同）
    public var removedIDs: [String]
    /// 两侧都有但内容不同
    public var modifiedIDs: [String]
    /// 删除墓碑（`removed*IDs`），仅 shop / series / product 非空
    public var tombstoneIDs: [String]

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        kind: ShopCatalogEntityKind,
        addedIDs: [String] = [],
        removedIDs: [String] = [],
        modifiedIDs: [String] = [],
        tombstoneIDs: [String] = []
    ) {
        self.kind = kind
        self.addedIDs = addedIDs
        self.removedIDs = removedIDs
        self.modifiedIDs = modifiedIDs
        self.tombstoneIDs = tombstoneIDs
    }

    public var isEmpty: Bool {
        addedIDs.isEmpty && removedIDs.isEmpty && modifiedIDs.isEmpty && tombstoneIDs.isEmpty
    }

    public var changedCount: Int {
        addedIDs.count + removedIDs.count + modifiedIDs.count + tombstoneIDs.count
    }

    public var affectedIDs: [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for id in addedIDs + removedIDs + modifiedIDs + tombstoneIDs where seen.insert(id).inserted {
            output.append(id)
        }
        return output
    }

    /// 人话一行，如「商品：新增 1 · 修改 2 · 下架 1」
    public var summaryLine: String {
        var parts: [String] = []
        if !addedIDs.isEmpty { parts.append("新增 \(addedIDs.count)") }
        if !modifiedIDs.isEmpty { parts.append("修改 \(modifiedIDs.count)") }
        if !removedIDs.isEmpty { parts.append("删除 \(removedIDs.count)") }
        if !tombstoneIDs.isEmpty { parts.append("下架 \(tombstoneIDs.count)") }
        guard !parts.isEmpty else { return "\(kind.displayName)：无变化" }
        return "\(kind.displayName)：\(parts.joined(separator: " · "))"
    }
}

// MARK: - 变更集

public nonisolated struct ShopCatalogChangeSet: Equatable, Sendable {

    /// 是否真的有一份基线可比。`false` = 界面只能显示「无法比较」，
    /// **不能**显示「没有改动」。
    public var hasBaseline: Bool
    public var deltas: [ShopCatalogEntityDelta]
    /// 本地变更追踪（与基线无关，永远可用）
    public var touched: ShopCatalogTouchedIDs

    // 跨模块构造入口（同 `ShopCatalogEntityDelta`）。
    public init(
        hasBaseline: Bool,
        deltas: [ShopCatalogEntityDelta] = [],
        touched: ShopCatalogTouchedIDs = ShopCatalogTouchedIDs()
    ) {
        self.hasBaseline = hasBaseline
        self.deltas = deltas
        self.touched = touched
    }

    public var isEmpty: Bool {
        deltas.allSatisfy(\.isEmpty) && touched.isEmpty
    }

    public var totalChanged: Int {
        deltas.reduce(0) { $0 + $1.changedCount }
    }

    public func delta(of kind: ShopCatalogEntityKind) -> ShopCatalogEntityDelta {
        deltas.first { $0.kind == kind } ?? ShopCatalogEntityDelta(kind: kind)
    }

    /// 受影响商品的 id（差分 ∪ 本地追踪）—— **严格发布策略的作用域**。
    public var changedProductIDs: [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for id in delta(of: .product).affectedIDs + touched.productIDs where seen.insert(id).inserted {
            output.append(id)
        }
        return output
    }

    /// 受影响图片资源的 id。
    public var changedAssetIDs: [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for id in delta(of: .asset).affectedIDs + touched.assetIDs where seen.insert(id).inserted {
            output.append(id)
        }
        return output
    }

    /// 严格策略的完整作用域（实体 id 全集，跨类别）。
    public var strictScopeIDs: Set<String> {
        var set = Set(deltas.flatMap(\.affectedIDs))
        set.formUnion(touched.allIDs)
        return set
    }

    /// 给运营看的逐行摘要（第一行永远是基线的真实状态）。
    public var summaryLines: [String] {
        var lines: [String] = []
        if hasBaseline {
            let changed = deltas.filter { !$0.isEmpty }
            if changed.isEmpty {
                lines.append("与基线相比：没有差异（这份包等于线上当前内容）")
            } else {
                lines.append(contentsOf: changed.map(\.summaryLine))
            }
        } else {
            lines.append("没有可用于比较的基线 —— **无法说明这份包相对线上改了什么**。"
                + "请先在「发布中心」读取线上基线。")
        }
        if !touched.isEmpty {
            let count = ShopCatalogEntityKind.allCases
                .map { "\($0.singularName) \(touched.ids(of: $0).count)" }
                .filter { !$0.hasSuffix(" 0") }
            lines.append("本机本次动过：" + (count.isEmpty ? "无" : count.joined(separator: " · ")))
        }
        return lines
    }

    /// 空集（用于「没有基线也没有本地变更」的初值）。
    public static var empty: ShopCatalogChangeSet {
        ShopCatalogChangeSet(hasBaseline: false)
    }
}

// MARK: - 计算

public nonisolated enum ShopCatalogChangeSetCalculator {

    /// 逐类别差分。
    ///
    /// - Parameters:
    ///   - baseline: 线上基线目录。nil = 没有基线（`hasBaseline` 为 false）。
    ///   - current: 当前草稿目录。
    ///   - touched: 本地变更追踪（与基线无关）。
    public static func diff(
        baseline: ShopCatalog?,
        current: ShopCatalog,
        touched: ShopCatalogTouchedIDs = ShopCatalogTouchedIDs()
    ) -> ShopCatalogChangeSet {
        var deltas: [ShopCatalogEntityDelta] = []
        for kind in ShopCatalogEntityKind.allCases {
            deltas.append(delta(kind, baseline: baseline, current: current))
        }
        return ShopCatalogChangeSet(
            hasBaseline: baseline != nil,
            deltas: deltas,
            touched: touched)
    }

    /// 单类别差分。`baseline == nil` 时返回全空 delta（而不是「全部新增」）——
    /// 把「没有基线」误报成「所有内容都是新增」会让运营以为要重发整个目录。
    public static func delta(
        _ kind: ShopCatalogEntityKind,
        baseline: ShopCatalog?,
        current: ShopCatalog
    ) -> ShopCatalogEntityDelta {
        guard let baseline else { return ShopCatalogEntityDelta(kind: kind) }
        let tombstones = kind.hasTombstone ? self.tombstones(kind, in: current) : []
        switch kind {
        case .shop:
            return diffByID(kind, baseline: baseline.shops, current: current.shops,
                            id: { $0.id }, tombstones: tombstones)
        case .series:
            return diffByID(kind, baseline: baseline.series, current: current.series,
                            id: { $0.id }, tombstones: tombstones)
        case .product:
            return diffByID(kind, baseline: baseline.products, current: current.products,
                            id: { $0.id }, tombstones: tombstones)
        case .variant:
            return diffByID(kind, baseline: baseline.variants, current: current.variants,
                            id: { $0.id })
        case .sizeChart:
            return diffByID(kind, baseline: baseline.sizeCharts, current: current.sizeCharts,
                            id: { $0.id })
        case .saleEvent:
            return diffByID(kind, baseline: baseline.saleEvents, current: current.saleEvents,
                            id: { $0.id })
        case .asset:
            return diffByID(kind, baseline: baseline.assets, current: current.assets,
                            id: { $0.id })
        case .styleProfile:
            return diffByID(kind, baseline: baseline.styleProfiles, current: current.styleProfiles,
                            id: { $0.id })
        }
    }

    // MARK: 内部

    /// 逐实体按 id 比 `Equatable`。
    ///
    /// · 顺序按**当前目录的录入顺序**产出（数组是录入顺序不是字典序，见仓库红线），
    ///   删除项按基线的录入顺序；**绝不用字典遍历序**（随进程哈希种子变，冷启动会换排法）；
    /// · id → 值 用 `for` 赋值建表，不用 `Dictionary(uniqueKeysWithValues:)`
    ///   （坏数据里重复 id 会让它直接抛错）。
    private static func diffByID<T: Equatable>(
        _ kind: ShopCatalogEntityKind,
        baseline: [T],
        current: [T],
        id: (T) -> String,
        tombstones: [String] = []
    ) -> ShopCatalogEntityDelta {
        var old: [String: T] = [:]
        for item in baseline { old[id(item)] = item }
        var new: [String: T] = [:]
        for item in current { new[id(item)] = item }

        let currentIDs = unique(current.map(id))
        var added: [String] = []
        var modified: [String] = []
        for key in currentIDs {
            guard let before = old[key] else { added.append(key); continue }
            guard let after = new[key] else { continue }
            if before != after { modified.append(key) }
        }
        let removed = unique(baseline.map(id)).filter { new[$0] == nil }

        return ShopCatalogEntityDelta(
            kind: kind,
            addedIDs: added,
            removedIDs: removed,
            modifiedIDs: modified,
            tombstoneIDs: tombstones)
    }

    private static func tombstones(_ kind: ShopCatalogEntityKind, in catalog: ShopCatalog) -> [String] {
        switch kind {
        case .shop: return catalog.removedShopIDs
        case .series: return catalog.removedSeriesIDs
        case .product: return catalog.removedProductIDs
        default: return []
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
