//
//  ShopCatalogReconcile.swift
//  SharedCatalog
//
//  以**线上那一版**为准，把本地目录逐条对账成同一个样子（2026-09-29 需求）。
//
//  ## 这一条补的是什么洞
//
//  在此之前，「拉回 / 对齐」只有一种做法：**整份替换**。
//
//    · Mac 端 `OpsWorkspace.adoptPulledCatalogContent`（2026-09-29 已改名
//      `alignCatalogToPulledContent`）直接复用 `importCatalog`，
//      界面按钮就叫「用拉回的内容替换当前草稿」，caveat 里明写「不是合并」；
//    · iOS 端本机目录只能靠「云端同步整层替换远端层」+ 三层合并间接变化，
//      没有任何「以线上为准对齐本机」的入口。
//
//  整份替换有两个真问题，而且都**不报错**：
//
//    1. **看不出发生了什么**。替换完只知道「新目录有多少条」，
//       不知道「哪些是加进来的、哪些被覆盖了、哪些被抹掉了」——
//       运营据此无法判断这次拉回有没有伤到自己手里的东西；
//    2. **无从自证结果**。「本地现在等于线上那一版吗」只能靠人眼比两个 JSON。
//
//  所以这里给的是**逐条对账**：
//
//    线上有、本地没有   → 加进来（增量）
//    两边同一个 id      → 用线上那份覆盖
//    本地有、线上没有   → 从本地移除（这就是「被替换掉」的那部分）
//
//  其结果**等于线上那一版**——除了下面两条必须显式说出来的例外。
//
//  ## 两条例外（都不静默，报告里逐条列出）
//
//  1. **销售历史（`saleEvents`）只增不删**。项目硬约束是 append-only
//     （`CatalogSaleEvent` 一旦写入永不改写、`CatalogPriceArchive` 靠它推导价格档案）。
//     线上分片又是**已下发口径**：构建时剔除了归档条目，连带着把归档商品名下的
//     销售事件也剔了。照着线上删，等于**抹掉不可恢复的历史**。所以本地独有的销售事件
//     一律保留并单独列出来。
//  2. **本地独有的下架墓碑（`removed*IDs`）保留**（并集）。墓碑表达的是
//     「这台机器已经声明删掉它了」；丢掉墓碑会让线上还带着的条目在本地**复活**，
//     而运营的本意是删掉它。保留则结果与线上有一处**可见的**差异（报告里会写）。
//
//  ## 差分复用既有口径，不另写一套
//
//  逐 id 的 added / modified / removed / tombstone 判定全部走
//  `ShopCatalogChangeSetCalculator.diff`（`Editing/ShopCatalogChangeSet.swift`）——
//  仓库里已经有这一份「别按字节比、按 id 逐实体比」的口径，这里**只补**
//  「以谁为准」和「结果怎么构造」两件事。再写一份差分 = 两份判定迟早不一致。
//

import Foundation

// MARK: - 单条差异

/// 对账里的一条差异（某一类的某一个实体）。
///
/// `name` 是给人看的可读名（拿不到就回落 id）——报告要能直接念给运营听，
/// 只有一串 `prd-3f9a…` 等于没说。**顺序由产出方给定**（数组是录入顺序，不是字典序）。
public nonisolated struct ShopCatalogReconcileChange: Equatable, Sendable, Identifiable {

    public let kind: ShopCatalogEntityKind
    public let entityID: String
    /// 可读名；空字符串 = 该类没有天然名字（展示时回落 id）
    public let name: String

    /// `ForEach` 用的稳定键：同类同 id 只可能有一条，类别前缀避免跨类撞 id。
    public var id: String { "\(kind.rawValue):\(entityID)" }

    public init(kind: ShopCatalogEntityKind, entityID: String, name: String = "") {
        self.kind = kind
        self.entityID = entityID
        self.name = name
    }

    /// 「商品：小魔女 JSK（prd-1a2b）」；没有名字时就是 id。
    public var displayText: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entityID else { return entityID }
        return "\(trimmed)（\(entityID)）"
    }
}

// MARK: - 对账报告

/// 一次「以线上为准对账」会把本地改成什么样。
///
/// 纯值类型、可直接落日志 / 上界面；生成它**不产生任何副作用**
/// （真正的写入由调用方拿着 `ShopCatalogReconcile.aligned(...)` 的结果自己做）。
public nonisolated struct ShopCatalogReconcileOutcome: Equatable, Sendable {

    /// 线上有、本地没有 → 会被加进来
    public let added: [ShopCatalogReconcileChange]
    /// 两边同一个 id 但内容不同 → 会被线上那份覆盖
    public let overwritten: [ShopCatalogReconcileChange]
    /// 本地有、线上没有 → 会从本地移除
    public let removed: [ShopCatalogReconcileChange]
    /// 本地独有的销售事件：**保留**（append-only，删了不可恢复）
    public let keptLocalSaleEvents: [ShopCatalogReconcileChange]
    /// 本地独有的下架墓碑：**保留**（否则线上还带着的条目会在本地复活）
    public let keptLocalTombstones: [ShopCatalogReconcileChange]

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        added: [ShopCatalogReconcileChange] = [],
        overwritten: [ShopCatalogReconcileChange] = [],
        removed: [ShopCatalogReconcileChange] = [],
        keptLocalSaleEvents: [ShopCatalogReconcileChange] = [],
        keptLocalTombstones: [ShopCatalogReconcileChange] = []
    ) {
        self.added = added
        self.overwritten = overwritten
        self.removed = removed
        self.keptLocalSaleEvents = keptLocalSaleEvents
        self.keptLocalTombstones = keptLocalTombstones
    }

    /// 什么都不用改（本地已经等于线上那一版，且没有可保留项）。
    public var isEmpty: Bool {
        added.isEmpty && overwritten.isEmpty && removed.isEmpty
            && keptLocalSaleEvents.isEmpty && keptLocalTombstones.isEmpty
    }

    /// 会不会动到本地已有内容（覆盖或移除）——**要删东西的才需要更重的确认**。
    public var touchesExistingContent: Bool {
        !overwritten.isEmpty || !removed.isEmpty
    }

    /// 需要从本地移除的条数（把「被替换掉」这件事说成一个数）。
    public var removedCount: Int { removed.count }

    /// 一行摘要：`新增 3 · 覆盖 12 · 移除 1`；无变化时给「无差异」。
    public var summaryText: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("新增 \(added.count)") }
        if !overwritten.isEmpty { parts.append("覆盖 \(overwritten.count)") }
        if !removed.isEmpty { parts.append("移除 \(removed.count)") }
        guard !parts.isEmpty else {
            return keptLocalSaleEvents.isEmpty && keptLocalTombstones.isEmpty
                ? "无差异（本地已经是线上那一版）"
                : "无需改动（仅保留本地记录 \(keptLocalSaleEvents.count + keptLocalTombstones.count) 条）"
        }
        var text = parts.joined(separator: " · ")
        let kept = keptLocalSaleEvents.count + keptLocalTombstones.count
        if kept > 0 { text += " · 另有 \(kept) 条本地记录保留" }
        return text
    }

    /// 给运营看的分行说明（第一行永远先说「会删掉什么」）。
    public var summaryLines: [String] {
        var lines: [String] = []
        if isEmpty {
            lines.append("与线上一致：不需要改动。")
        } else if removed.isEmpty {
            lines.append("不会删掉本地任何内容。")
        } else {
            lines.append("会从本地移除 \(removed.count) 条（线上那一版里没有它们）。")
        }
        if !added.isEmpty { lines.append("线上有、本地没有：新增 \(added.count) 条。") }
        if !overwritten.isEmpty { lines.append("两边都有但内容不同：用线上那份覆盖 \(overwritten.count) 条。") }
        if !keptLocalSaleEvents.isEmpty {
            lines.append("本地独有的销售记录 \(keptLocalSaleEvents.count) 条**不会被删**"
                + "（销售历史只增不删；线上分片是已下发口径，归档商品的历史不在其中）。")
        }
        if !keptLocalTombstones.isEmpty {
            lines.append("本地独有的下架记录 \(keptLocalTombstones.count) 条保留："
                + "这些条目线上还带着，但本机声明过删掉，保留后它们在本机仍然不显示。")
        }
        return lines
    }

    /// 明细（每类最多 `limit` 条，超出给「等 N 条」）。空 = 这一类没有差异。
    public func detailLines(limit: Int = 5) -> [String] {
        func section(_ title: String, _ items: [ShopCatalogReconcileChange]) -> [String] {
            guard !items.isEmpty else { return [] }
            var lines = items.prefix(limit).map { "\(title) \($0.kind.singularName)：\($0.displayText)" }
            if items.count > limit { lines.append("\(title) 还有 \(items.count - limit) 条") }
            return lines
        }
        return section("＋", added)
            + section("～", overwritten)
            + section("－", removed)
            + section("＝", keptLocalSaleEvents + keptLocalTombstones)
    }
}

// MARK: - 对账

/// 「以线上那一版为准」把本地对账成同一个样子。
///
/// **唯一口径**：iOS 运营端与 Mac 运营端都调这里，不许各自实现一遍合并
/// （2026-09-28 已经因为两端各手拼一份引用字段清单而双双漏掉 174 张图）。
public nonisolated enum ShopCatalogReconcile {

    // MARK: 结果

    /// 对账后的目录：**实体层等于 `remote`**，另加上两条例外（见文件头）。
    ///
    /// 顺序也照 `remote`（远端是权威，本地录入顺序不再保留）——
    /// 顺序会影响「系列分区顺序」等展示派生，必须只有一处真相。
    public static func aligned(local: ShopCatalog, remote: ShopCatalog) -> ShopCatalog {
        var result = remote
        // 例外 1：销售历史只增不删（线上在前、本地独有按本地顺序追加，按 id 去重）
        result.saleEvents = unionSaleEvents(remote.saleEvents, local.saleEvents)
        // 例外 2：墓碑并集（任一来源声明下架即生效）
        result.removedShopIDs = union(remote.removedShopIDs, local.removedShopIDs)
        result.removedSeriesIDs = union(remote.removedSeriesIDs, local.removedSeriesIDs)
        result.removedProductIDs = union(remote.removedProductIDs, local.removedProductIDs)
        return result
    }

    /// 对账结果 + 报告，一步到位（调用方通常只需要这一个入口）。
    public static func align(
        local: ShopCatalog,
        remote: ShopCatalog
    ) -> (catalog: ShopCatalog, outcome: ShopCatalogReconcileOutcome) {
        (aligned(local: local, remote: remote), outcome(local: local, remote: remote))
    }

    /// 分层结构（iOS：`base → remote → overlay`）里的等价做法：
    /// 把**覆盖层**收敛成「只剩本地必须保留的部分」，实体全部交给远端层去提供。
    ///
    /// ## 为什么不能把整个对账结果写进覆盖层
    ///
    /// 覆盖层的优先级**高于**远端层。把 `aligned(local:remote:)` 的结果整份写进覆盖层，
    /// 等于给本机内容盖了一层**快照**：之后线上再发新版本时，同 id 的实体
    /// 会被这层旧的副本挡住（覆盖层赢），而界面上完全看不出来 ——
    /// 「与线上一样」就只成立于点对齐按钮的那一刻。
    ///
    /// 收敛成「只剩两条例外」之后：
    ///   · 实体与重叠的销售事件由**远端层**提供 → 线上更新能直接生效；
    ///   · 本地独有的销售事件（append-only，删了不可恢复）留在覆盖层；
    ///   · 本地独有的下架墓碑留在覆盖层（否则线上还带着的条目会在本机复活）。
    /// 生效目录（三层合并结果）仍然等于线上那一版 —— 由 `isAligned` 自证。
    public static func localOnlyRemainder(local: ShopCatalog, remote: ShopCatalog) -> ShopCatalog {
        let remoteEventIDs = Set(remote.saleEvents.map(\.id))
        let remoteShopTombstones = Set(remote.removedShopIDs)
        let remoteSeriesTombstones = Set(remote.removedSeriesIDs)
        let remoteProductTombstones = Set(remote.removedProductIDs)
        return ShopCatalog(
            saleEvents: local.saleEvents.filter { !remoteEventIDs.contains($0.id) },
            removedShopIDs: local.removedShopIDs.filter { !remoteShopTombstones.contains($0) },
            removedSeriesIDs: local.removedSeriesIDs.filter { !remoteSeriesTombstones.contains($0) },
            removedProductIDs: local.removedProductIDs.filter { !remoteProductTombstones.contains($0) })
    }

    /// 对账之后**结果是否已经等于线上那一版**（自证用，不猜）。
    ///
    /// 判据只看实体层：八类实体必须 id 集合与内容逐条相等，且不再有
    /// 「本地有、线上没有」的实体。销售事件与墓碑按上面的例外**只要求包含**
    /// 线上那份（本地可以多，不可以少）。
    public static func isAligned(_ catalog: ShopCatalog, with remote: ShopCatalog) -> Bool {
        let delta = ShopCatalogChangeSetCalculator.diff(baseline: catalog, current: remote)
        for kind in ShopCatalogEntityKind.allCases {
            let d = delta.delta(of: kind)
            switch kind {
            case .saleEvent:
                // 本地可以多（append-only），但线上有的必须一条不少
                if !d.addedIDs.isEmpty { return false }
            default:
                if !d.addedIDs.isEmpty || !d.removedIDs.isEmpty || !d.modifiedIDs.isEmpty {
                    return false
                }
            }
        }
        for kind in ShopCatalogEntityKind.allCases where kind.hasTombstone {
            let remoteIDs = tombstones(of: kind, in: remote)
            let localIDs = Set(tombstones(of: kind, in: catalog))
            if !remoteIDs.allSatisfy({ localIDs.contains($0) }) { return false }
        }
        return true
    }

    // MARK: 报告

    /// 算出「从本地变成线上那一版」要做哪些事。**不产生副作用**。
    public static func outcome(
        local: ShopCatalog,
        remote: ShopCatalog
    ) -> ShopCatalogReconcileOutcome {
        // baseline = 本地（参照物）、current = 线上（新内容）：
        //   added      = 线上有本地没有 → 加进来
        //   modified   = 同 id 内容不同 → 线上覆盖
        //   removed    = 本地有线上没有 → 从本地移除
        let delta = ShopCatalogChangeSetCalculator.diff(baseline: local, current: remote)

        var added: [ShopCatalogReconcileChange] = []
        var overwritten: [ShopCatalogReconcileChange] = []
        var removed: [ShopCatalogReconcileChange] = []
        var keptLocalSaleEvents: [ShopCatalogReconcileChange] = []

        for kind in ShopCatalogEntityKind.allCases {
            let d = delta.delta(of: kind)
            added.append(contentsOf: d.addedIDs.map {
                ShopCatalogReconcileChange(kind: kind, entityID: $0, name: name(of: kind, id: $0, in: remote))
            })
            overwritten.append(contentsOf: d.modifiedIDs.map {
                ShopCatalogReconcileChange(kind: kind, entityID: $0, name: name(of: kind, id: $0, in: remote))
            })
            if kind == .saleEvent {
                // ⭐ 销售事件**不删**：本地独有的转成「保留」，绝不出现在 removed 里。
                keptLocalSaleEvents.append(contentsOf: d.removedIDs.map {
                    ShopCatalogReconcileChange(
                        kind: kind, entityID: $0, name: name(of: kind, id: $0, in: local))
                })
                continue
            }
            removed.append(contentsOf: d.removedIDs.map {
                ShopCatalogReconcileChange(kind: kind, entityID: $0, name: name(of: kind, id: $0, in: local))
            })
        }

        // 本地独有的墓碑：线上没有声明删、本地声明了 → 保留（单独列出）
        var keptLocalTombstones: [ShopCatalogReconcileChange] = []
        for kind in ShopCatalogEntityKind.allCases where kind.hasTombstone {
            let remoteIDs = Set(tombstones(of: kind, in: remote))
            for id in tombstones(of: kind, in: local) where !remoteIDs.contains(id) {
                keptLocalTombstones.append(
                    ShopCatalogReconcileChange(kind: kind, entityID: id, name: ""))
            }
        }

        return ShopCatalogReconcileOutcome(
            added: added,
            overwritten: overwritten,
            removed: removed,
            keptLocalSaleEvents: keptLocalSaleEvents,
            keptLocalTombstones: keptLocalTombstones)
    }

    // MARK: 内部

    /// 并集，**保序**（先 `first` 再 `second`，按 id 去重）。
    /// 不用 `Set`/`Dictionary` 遍历序派生顺序 —— 那会随进程哈希种子变（仓库红线）。
    private static func union(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for id in first + second where seen.insert(id).inserted { output.append(id) }
        return output
    }

    /// 销售事件并集：线上在前（权威优先），本地独有的按本地顺序追加。
    /// 同 id 两侧都有但内容不同 → **保留先出现的（线上那份）**，不改写已写入的历史。
    private static func unionSaleEvents(
        _ remote: [CatalogSaleEvent],
        _ local: [CatalogSaleEvent]
    ) -> [CatalogSaleEvent] {
        var seen = Set<String>()
        var output: [CatalogSaleEvent] = []
        for event in remote + local where seen.insert(event.id).inserted { output.append(event) }
        return output
    }

    private static func tombstones(of kind: ShopCatalogEntityKind, in catalog: ShopCatalog) -> [String] {
        switch kind {
        case .shop: return catalog.removedShopIDs
        case .series: return catalog.removedSeriesIDs
        case .product: return catalog.removedProductIDs
        default: return []
        }
    }

    /// 可读名（拿不到就空串 → 展示时回落 id）。
    /// 只做「一眼能认出是哪条」的程度，不引入任何新的展示口径。
    private static func name(
        of kind: ShopCatalogEntityKind,
        id: String,
        in catalog: ShopCatalog
    ) -> String {
        switch kind {
        case .shop:
            return catalog.shops.first { $0.id == id }?.name ?? ""
        case .series:
            return catalog.series.first { $0.id == id }?.name ?? ""
        case .product:
            return catalog.products.first { $0.id == id }?.name ?? ""
        case .variant:
            guard let variant = catalog.variants.first(where: { $0.id == id }) else { return "" }
            let parts = [variant.color, variant.size].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.joined(separator: " / ")
        case .sizeChart:
            return catalog.sizeCharts.first { $0.id == id }?.productID ?? ""
        case .saleEvent:
            return catalog.saleEvents.first { $0.id == id }?.productID ?? ""
        case .asset:
            return catalog.assets.first { $0.id == id }?.originalURL ?? ""
        case .styleProfile:
            return catalog.styleProfiles.first { $0.id == id }?.designName ?? ""
        }
    }
}
