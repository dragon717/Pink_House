//
//  ShopCatalogStyleProfileSharing.swift
//  ItemManager
//
//  款式（SPU）公共档案口径（2026-09-23 录入端重构，nonisolated 可单测）。
//
//  需求原文：「尺码表、面料、款式描述，这些是款式（SPU）的公共属性，必须在录商品的
//  第一步就填好，只填一次。颜色图片、颜色库存，这些是颜色（SKU）的差异属性，在添加
//  每个颜色时独立填。」
//
//  收口结论：**一个款式一份档案，款式键 = 系列 + 品类 + 款式名。**
//
//    1. 款式键（`styleKey`）与「同款不同色」的归组判定同源（`designKey` + 系列），
//       因此「列表里被合并成一张卡的颜色」与「共享同一份公共档案的颜色」永远是同一批人。
//       少比一个系列就会出现「两个系列下同名款共用一个面料」的串档。
//
//    2. 读（`resolve` / `profile`）：档案优先，商品自身字段兜底 ——
//       存量数据里款式描述可能写在 `CatalogProduct.description` 上（录入端重构之前
//       没有款式级概念），不能因为搬家就让老数据看不见。`fabric` 没有历史来源，只认档案。
//
//    3. 写（`upsertPlan`）：**整款一份**，按键整体替换。这里刻意**不做**像尺码表那样的
//       「扇出到每个颜色一行」—— 档案的 id 就是款式键，天然唯一，扇出只会制造
//       多份需要保持同步的副本。空档案（面料与描述都空）等于「款式没有公共属性」，
//       按清除处理，不留空壳行。
//
//  与尺码表的分工：尺码表的读写仍由 `ShopCatalogSizeChartSharing` 负责（它已经是
//  款式级语义），本文件只负责面料 / 款式描述。调用方（表单 / 详情页）统一从
//  `ShopCatalogStore` 取值，不必知道这层分工。
//

import Foundation

nonisolated enum ShopCatalogStyleProfileSharing {

    // MARK: - 款式键

    /// 款式键：系列 + 品类 + 款式名。
    static func styleKey(seriesID: String, category: String, designName: String) -> String {
        "\(seriesID)|\(category)|\(designName)"
    }

    /// 商品的款式键（款式名按「显式 designName 优先、否则剥离颜色词派生」取）
    static func styleKey(of product: CatalogProduct) -> String {
        styleKey(seriesID: product.seriesID,
                 category: product.category,
                 designName: ShopCatalogSameDesignGrouper.designName(of: product))
    }

    // MARK: - 范围

    /// 同款范围（读用，含归档）：同系列 + 同品类 + 同款式名。
    /// 与 `ShopCatalogSizeChartSharing.designScope` 同一口径，只是那边按 product 两两比，
    /// 这里按键比 —— 键相等天然是等价关系，不必再判 `a.id != b.id`。
    static func designScope(of product: CatalogProduct,
                            among products: [CatalogProduct]) -> [CatalogProduct] {
        let key = styleKey(of: product)
        return products.filter { styleKey(of: $0) == key }
    }

    // MARK: - 读取

    /// 款式公共档案（**唯一读取入口**）。同一款式只有一份，取最后一条即为最新
    /// （与覆盖层「后写胜出」同一口径）。
    static func profile(for product: CatalogProduct,
                        among products: [CatalogProduct],
                        profiles: [CatalogStyleProfile]) -> CatalogStyleProfile? {
        let keys = Set(designScope(of: product, among: products).map(styleKey(of:)))
        let hit = profiles.last { keys.contains($0.id) }
        // 款内一个商品都没匹配上键时（商品数组不完整），退回按自己的键直接找
        return hit ?? profiles.last { $0.id == styleKey(of: product) }
    }

    /// 款式面料：只认档案（没有历史来源可兜底）
    static func fabric(for product: CatalogProduct,
                       among products: [CatalogProduct],
                       profiles: [CatalogStyleProfile]) -> String? {
        clean(profile(for: product, among: products, profiles: profiles)?.fabric)
    }

    /// 款式描述：档案优先，回退商品自身 `description`（录入端重构之前的历史写法）
    static func styleDescription(for product: CatalogProduct,
                                 among products: [CatalogProduct],
                                 profiles: [CatalogStyleProfile]) -> String? {
        if let fromProfile = clean(profile(for: product, among: products,
                                           profiles: profiles)?.styleDescription) {
            return fromProfile
        }
        return clean(product.description)
    }

    /// 空白串按「没有」处理（表单清空后不该留下空字符串假装有内容）
    static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - 写入

    /// 写入产物：要删除的档案 id + 要写入的档案（0 或 1 条）
    struct WritePlan: Equatable {
        var removals: [String] = []
        var upserts: [CatalogStyleProfile] = []
    }

    /// 写入产物（唯一口径）：整款一份，按键整体替换。
    ///   · 面料与描述都为空 → 只删不写（清除该款式档案）。
    ///   · 否则写入一条，`id` = 款式键，`updatedAt` 刷新。
    static func writePlan(fabric: String?,
                          styleDescription: String?,
                          for product: CatalogProduct,
                          among products: [CatalogProduct],
                          profiles: [CatalogStyleProfile],
                          now: Date = Date()) -> WritePlan {
        let key = styleKey(of: product)
        // 款内所有商品的键都相同，但商品数组可能不完整 —— 收集到的键并集一起清，
        // 避免旧档因键的细微差异（例如款式名后被修正）残留成孤儿
        var keys = Set(designScope(of: product, among: products).map(styleKey(of:)))
        keys.insert(key)
        var plan = WritePlan(removals: Array(keys))

        let fabricValue = clean(fabric)
        let descriptionValue = clean(styleDescription)
        guard fabricValue != nil || descriptionValue != nil else { return plan }

        var profile = CatalogStyleProfile(id: key,
                                         seriesID: product.seriesID,
                                         category: product.category,
                                         designName: ShopCatalogSameDesignGrouper.designName(of: product))
        profile.fabric = fabricValue
        profile.styleDescription = descriptionValue
        profile.updatedAt = now
        plan.upserts = [profile]
        return plan
    }
}
