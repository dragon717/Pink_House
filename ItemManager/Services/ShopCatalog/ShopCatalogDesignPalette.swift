//
//  ShopCatalogDesignPalette.swift
//  ItemManager
//
//  「同款商品集合」与「同款颜色集合」的**唯一口径**（2026-09-23，nonisolated 可单测）。
//
//  背景（用户报的系统性 Bug）：
//    详情页标题写着「段段方领 JSK · 3色」，但下方**没有「配色」这一行**；
//    而同款另一条数据「段段长Jsk · 2色」却有「配色：红色 粉色」。
//
//  根因不是某处 if 写漏，而是**同一件事有两个数据源**：
//    · 标题的「· N 色」 = 同款商品集合推导（`siblings.count + 1`）；
//    · 「配色」行        = `store.colors(forProduct:)`，即**本商品自己的规格色**。
//  SPU/SKU 结构下每个颜色是独立商品 → 本商品只有自己那一色；纯名称命名（没建规格）时
//  一条规格都没有 → `colors` 为空 → 整行消失。标题说 3 色、配色行一行没有，就是这么来的。
//
//  修法：把「同款商品集合」收敛到本文件，标题 / 配色行 / 轮播兄弟图 都从它取，
//  再据它推导「同款颜色集合」—— 两者不可能再对不上。
//
//  ⚠️ 与 `ShopCatalogSameDesignGrouper.designKey` 的关系：
//  那个是**展示层归组键**（品类 + 款式名，不含系列）；本文件的同款判定多一层
//  「同系列 + 未归档」的限定 —— 详情页要在同一个系列里找兄弟商品，跨系列的
//  同名款不该被算作同一款的颜色（否则「· N 色」会把别的系列也数进来）。
//

import Foundation

nonisolated enum ShopCatalogDesignPalette {

    /// 同款其他颜色商品：**同系列 + 同品类 + 同款式名 + 未归档**，排除自己。
    /// 保持传入顺序（= 目录顺序，不排序）。
    static func sameDesignProducts(of product: CatalogProduct,
                                   among products: [CatalogProduct]) -> [CatalogProduct] {
        let design = ShopCatalogSameDesignGrouper.designName(of: product)
        return products.filter {
            $0.id != product.id
                && $0.seriesID == product.seriesID
                && $0.category == product.category
                && $0.archivedAt == nil
                && ShopCatalogSameDesignGrouper.designName(of: $0) == design
        }
    }

    /// 同款颜色集合（去重、保序）：**本商品在前**，同款其他颜色商品依次追加。
    ///
    /// 单个商品贡献的颜色分两种数据形态，都要覆盖：
    ///   · **多规格色**（旧形态：一个商品自带红色 + 粉色两个规格，即参考图里那条正常数据）
    ///     → 全部列出；
    ///   · **单一颜色只写在商品名里**（新形态：SPU/SKU，每个颜色一个商品且没建规格行）
    ///     → 从商品名剥离颜色词兜底，否则这一色贡献为空、整行消失。
    ///
    /// 刻意**不**用「整名兜底」：名称里没有颜色词就不贡献颜色，避免「大蝴蝶结背心裙」
    /// 既当款式名又当颜色。
    ///
    /// - Parameter explicitColors: 由调用方提供「某商品自己的规格色」查法
    ///   （生产环境注入 `ShopCatalogStore.colors(forProduct:)`）。
    static func colors(of product: CatalogProduct,
                       among products: [CatalogProduct],
                       explicitColors: (CatalogProduct) -> [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ color: String?) {
            guard let color = color?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !color.isEmpty,
                  seen.insert(color).inserted else { return }
            result.append(color)
        }

        func contribute(_ item: CatalogProduct) {
            let explicit = explicitColors(item)
            if explicit.isEmpty {
                append(ShopCatalogColorPresentation.derivedLabel(forName: item.name))
            } else {
                explicit.forEach { append($0) }
            }
        }

        contribute(product)
        for sibling in sameDesignProducts(of: product, among: products) {
            contribute(sibling)
        }
        return result
    }

    /// 单个商品的颜色标注（显式规格色优先 → 商品名颜色词 → nil）——只要一个颜色的场景用
    static func label(of product: CatalogProduct, explicitColors: [String]) -> String? {
        ShopCatalogColorPresentation.label(explicitColors: explicitColors, name: product.name)
    }
}
