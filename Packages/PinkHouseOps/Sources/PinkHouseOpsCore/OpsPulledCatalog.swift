// 线上拉取产物：发布版本、摘要、目录路径与各类实体数量。
// 桥接器使用普通公共读取路径，验证包摘要和结构后返回本模型。
// 本地编辑与远端基线的三方合并由 OpsWorkspace 执行。

import Foundation

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
    /// 这个基线来自哪个环境（`development` / `production`）
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
