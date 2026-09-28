//
//  OpsPulledCatalog.swift
//  PinkHouseOps
//
//  「从线上拉回基线」的产物模型与采用判定（方案 §5「当前线上完整基线 + 变更集」/ R07）。
//
//  ## 这一条补的是什么洞
//
//  方案要求发布 = 「当前线上完整基线 + 变更集 → 合成完整 Catalog，保留未改动内容」。
//  但在此之前 App 只有「导入 JSON」一个入口，**没有任何从线上拉回目录的通道**：
//  基线内容全靠人手导出 / 导入。于是运营手里那份内容与线上是什么关系，谁都不知道。
//
//  桥接器因此新增一条**只读**模式 `--mode pull-catalog`：回读线上发布头指向的
//  商店目录分片、按摘要自证、解压后写成一份普通的 `shop-catalog.json`。
//  它的产物就是**一份可以直接导入的目录**，所以下游复用既有导入路径，不另造一条。
//
//  ## 为什么模型与「采用的判定」放在包里而不是 App 里
//
//  Mac App target **没有单测 target**（见 skill `pink-house-xcodebuild-acceptance`）。
//  凡是「写错了要用眼睛看才发现」的东西 —— 比如「哪些情况必须拒绝替换」
//  「替换前必须让运营读到哪几句话」—— 必须放进这个包才有回归锁。
//
//  ## 一条必须显式告知的事（不能静默）
//
//  线上分片是**已下发口径**：`build_release.py` 的 `strip_archived_shop_catalog`
//  已经剔除归档条目与孤儿销售事件，`collect_shop_catalog_media` 把 `local:` 图片引用
//  改写成了 `thmedia:<内容摘要>`。所以拉回来的东西：
//    · **不含归档条目** —— 本地若曾有归档内容，替换之后就没了；
//    · **图片引用不再是本地文件名** —— 本地没有对应文件，预览会缺图。
//  这不是缺陷，是「下发给用户的东西」的定义。但**必须说出来**，否则运营会以为
//  「拉回 = 完整备份」，然后把它当备份用。
//

import Foundation
// MemberImportVisibility 下，用到 `ShopCatalogBaseline` / `ShopCatalogOnlineHead`
// **必须在使用它的那个文件里**显式 import（只靠 `@_exported` 桥接文件在某些编译顺序下不够）。
import SharedCatalog

// MARK: - 单类条数

/// 一类实体的条数（`商品 263`）。**做成结构体而不是元组**：
/// `ForEach(_:id:)` 的 `id` 是 `KeyPath`，而 Swift 的 `KeyPath` **不能指向元组成员**
/// （报 `key path cannot refer to tuple element`），用元组会让视图层写不出来。
public nonisolated struct OpsPulledItemCount: Identifiable, Equatable, Sendable {
    /// 载荷字段名（`products` / `sizeCharts` …），同时充当 `id`
    public let field: String
    /// 中文标签
    public let label: String
    public let count: Int

    public var id: String { field }

    public init(field: String, label: String, count: Int) {
        self.field = field
        self.label = label
        self.count = count
    }
}

// MARK: - 拉回产物

/// 一次 `pull-catalog` 的结果描述。字段与桥接器 `catalog` 事件一一对应，
/// 另外补上「来自哪个环境」与「什么时候拉的」—— 基线**按环境**，不能跨环境比。
public nonisolated struct OpsPulledCatalog: Equatable, Sendable {

    /// 写出的 `shop-catalog.json` 路径（App 容器内的绝对路径）
    public var path: String
    /// 这个基线来自哪个环境（`development` / `production` / `localFixture`）
    public var environment: String
    /// 线上发布号（拉回时读到的那一个）
    public var releaseSeq: Int
    /// 线上根清单摘要。nil = 这次没读到（`head_payload` 不保证回吐）——
    /// **不能**据此声称「摘要已核对」。
    public var rootIndexHash: String?
    /// 分片载荷摘要（自证过的那一个）
    public var payloadHash: String?
    /// 各类实体条数（键与 `SHOP_CATALOG_ALL_FIELDS` 同值）
    public var itemCounts: [String: Int]
    /// 拉回时刻
    public var pulledAt: Date

    public init(
        path: String,
        environment: String,
        releaseSeq: Int,
        rootIndexHash: String? = nil,
        payloadHash: String? = nil,
        itemCounts: [String: Int] = [:],
        pulledAt: Date = Date()
    ) {
        self.path = path
        self.environment = environment
        self.releaseSeq = releaseSeq
        self.rootIndexHash = rootIndexHash
        self.payloadHash = payloadHash
        self.itemCounts = itemCounts
        self.pulledAt = pulledAt
    }

    /// 载荷里**实体**的总条数（不含撤回清单：那三个是「删掉了什么」，
    /// 不是「有什么」，混进来会让运营以为拉回来的东西更多）。
    public var entityCount: Int {
        OpsPulledCatalog.entityFields.reduce(0) { $0 + (itemCounts[$1] ?? 0) }
    }

    /// 展示顺序固定的「字段 → 条数」列表（空条目不显示）。
    /// 顺序写死是为了两次截图能逐字节比对 —— 字典遍历序不行。
    public var sortedItemCounts: [OpsPulledItemCount] {
        OpsPulledCatalog.orderedFields.compactMap { field, label in
            guard let count = itemCounts[field], count > 0 else { return nil }
            return OpsPulledItemCount(field: field, label: label, count: count)
        }
    }

    /// 条数摘要（`店家 2 / 系列 9 / 商品 263`）。**不含撤回清单**，理由同上。
    public var countsText: String {
        let parts = sortedItemCounts
            .filter { OpsPulledCatalog.entityFields.contains($0.field) }
            .map { "\($0.label) \($0.count)" }
        return parts.isEmpty ? "（空目录）" : parts.joined(separator: " / ")
    }

    public var hashText: String {
        guard let rootIndexHash, !rootIndexHash.isEmpty else { return "摘要未读到" }
        return String(rootIndexHash.prefix(12)) + "…"
    }

    public var summaryText: String {
        "线上 \(environment) · releaseSeq \(releaseSeq) · \(hashText) · \(countsText)"
    }

    // MARK: 字段口径（唯一来源）

    /// 载荷里的**实体**字段，顺序 = 界面展示顺序。
    public static let entityFields: [String] = [
        "shops", "series", "products", "variants",
        "sizeCharts", "saleEvents", "assets", "styleProfiles",
    ]

    /// 撤回清单字段。**与实体字段分开**，因为它们的含义相反（「删掉了什么」）。
    public static let tombstoneFields: [String] = [
        "removedShopIDs", "removedSeriesIDs", "removedProductIDs",
    ]

    /// 全部字段 + 中文标签（展示顺序固定，不用字典遍历序）。
    public static let orderedFields: [(field: String, label: String)] = [
        ("shops", "店家"),
        ("series", "系列"),
        ("products", "商品"),
        ("variants", "规格"),
        ("sizeCharts", "尺码表"),
        ("saleEvents", "销售记录"),
        ("assets", "图片资源"),
        ("styleProfiles", "款式档案"),
        ("removedShopIDs", "撤回店家"),
        ("removedSeriesIDs", "撤回系列"),
        ("removedProductIDs", "撤回商品"),
    ]

    /// 字段 → 中文标签（未知字段回落到字段名本身，不吞掉）。
    public static func label(for field: String) -> String {
        orderedFields.first { $0.field == field }?.label ?? field
    }

    /// 从一次桥接调用的结果里取出拉回的目录。nil = 这次没有可拉回的东西
    /// （线上确实没有商店目录分片，或跑的不是 `pullCatalog` 模式）。
    ///
    /// 判定**只认 `catalog` 事件给的路径**：不去猜输出目录下的文件名。
    /// 猜的话，一个失败的运行会被当成「拉回来了一份空目录」。
    public static func from(
        result: OpsBridgeRunResult,
        environment: String,
        at date: Date = Date()
    ) -> OpsPulledCatalog? {
        guard let path = result.pulledCatalogPath, !path.isEmpty else { return nil }
        return OpsPulledCatalog(
            path: path,
            environment: environment,
            releaseSeq: result.onlineHead?.releaseSeq ?? 0,
            rootIndexHash: result.onlineHead?.rootIndexHash,
            payloadHash: result.pulledCatalogPayloadHash,
            itemCounts: result.pulledCatalogItemCounts ?? [:],
            pulledAt: date)
    }
}

// MARK: - 采用判定

/// 「用拉回的这份内容替换当前草稿」的判定与告知。
///
/// 全程只做两件事：**拦住真正不该做的**、**把该说的说出来**。
/// 判定本身不产生任何副作用（纯函数），替换动作由调用方显式执行。
public nonisolated enum OpsPulledCatalogAdoption {

    /// 拉回来的东西**是不是一份能用的目录**。
    ///
    /// 空目录不算失败：线上确实可能是空的（首次发布前的状态）。
    /// 但**路径必须指向真读得出的文件** —— 只判 `fileExists` 在沙盒里会骗人
    /// （见 `OpsBridgeSettings.isReadableFile` 的说明），所以这里由调用方
    /// 传「能不能真读」进来，而不是在这里再判一次存在性。
    public static func blockers(
        pulled: OpsPulledCatalog,
        isDraftCorrupted: Bool,
        isCatalogFileReadable: Bool
    ) -> [String] {
        var blockers: [String] = []
        if !isCatalogFileReadable {
            blockers.append("拉回的目录文件读不出来：\(pulled.path)。"
                + "这通常是文件被清理或权限问题，请重新拉一次。")
        }
        if isDraftCorrupted {
            // 与 `importCatalog` 的守卫一致（R03）：只读隔离态下不许覆盖。
            blockers.append("当前草稿处于只读隔离状态，替换内容会覆盖那份损坏记录 —— "
                + "已被拒绝。请先「另存为新草稿」，再在新草稿里拉回。")
        }
        return blockers
    }

    /// 替换之前**必须让运营读到的每一句话**。空 = 没什么特别的。
    ///
    /// 顺序有讲究：先说「要发生什么」（替换），再说「拿不到什么」（已下发口径），
    /// 最后才是数量对比 —— 让人先知道性质，再看数字。
    public static func caveats(
        pulled: OpsPulledCatalog,
        currentItemCounts: [String: Int]? = nil
    ) -> [String] {
        var notes: [String] = []

        notes.append("这一动作会用拉回的内容**替换当前草稿的全部内容**"
            + "（不是合并）。当前草稿里任何未发布的改动都会丢掉。")

        // ⭐ 已下发口径：必须显式说出来，否则会被当成「完整备份」。
        //
        // ⚠️ 这里**不能**把「图片是 thmedia:」写成必然。2026-09-28 实测：dev 线上
        // 那一版（seq 1）的 560 个引用**全是 `local:`，thmedia: 为 0** —— 而受控发布器
        // 的构建必然改写引用（缺图硬报错），所以那一版根本**不是受控发布器产出的**
        // （早期种子发布）。把「引用已改写」说成必然，会让运营以为拉回来的东西图上没问题，
        // 而那种 `local:` 版本是**更糟**的一种：除原始设备外谁也解不出图。
        notes.append("拉回的是**已下发口径**：归档过的店家 / 系列 / 商品"
            + "在构建时就被剔除了，**不会**跟着回来；"
            + "图片引用通常已改写成 thmedia:<内容摘要>（本地没有对应文件，预览会缺图），"
            + "但若线上那一版不是受控发布器产出的（例如早期种子发布），"
            + "引用仍是 local: 文件名 —— 那种情况下除原始设备外都解不出图。")

        if pulled.rootIndexHash?.isEmpty ?? true {
            notes.append("这次没读到线上根清单摘要：只能按发布号记录基线，"
                + "界面上不会写「摘要一致」。")
        }

        if let currentItemCounts, !currentItemCounts.isEmpty {
            let localTotal = OpsPulledCatalog.entityFields
                .reduce(0) { $0 + (currentItemCounts[$1] ?? 0) }
            let pulledTotal = pulled.entityCount
            if localTotal != pulledTotal {
                notes.append("实体条数会从 \(localTotal) 变成 \(pulledTotal)"
                    + "（\(deltaText(from: localTotal, to: pulledTotal))）。"
                    + "数量变少是正常的：归档条目不会回来。")
            }
        }
        return notes
    }

    /// 数量变化的措辞（涨 / 平 / 跌分开，不写「变化了」这种没有方向的说法）。
    public static func deltaText(from old: Int, to new: Int) -> String {
        if new == old { return "条数不变" }
        if new > old { return "净增 \(new - old)" }
        return "净减 \(old - new)"
    }

    /// 采用之后，这份草稿的基线应当记成什么。
    ///
    /// **一定要把环境带上**：拿 Development 的基线去核对 Production 是必然误判
    /// （见 `ShopCatalogBaselineResolver.verdict` 里那条环境分支）。
    public static func baseline(afterAdopting pulled: OpsPulledCatalog) -> ShopCatalogBaseline {
        ShopCatalogBaseline(
            releaseSeq: pulled.releaseSeq,
            rootIndexHash: pulled.rootIndexHash,
            environment: pulled.environment,
            observedAt: pulled.pulledAt)
    }

    /// 采用之后的线上头（供 `ShopCatalogBaselineResolver.verdict` 立刻核对一次）。
    public static func head(afterAdopting pulled: OpsPulledCatalog) -> ShopCatalogOnlineHead {
        ShopCatalogOnlineHead(
            environment: pulled.environment,
            releaseSeq: pulled.releaseSeq,
            rootIndexHash: pulled.rootIndexHash,
            observedAt: pulled.pulledAt)
    }
}
