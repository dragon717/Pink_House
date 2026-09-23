//
//  ShopCatalogTitlePresentation.swift
//  ItemManager
//
//  商品标题 / 颜色呈现口径（2026-09-23「内外标题一致」，nonisolated 可单测）。
//
//  用户反馈原文：「我们内外的标题应当保持一致，仅在颜色上加以区分，因为其他方面
//  完全相同。」配图是同一个商品在两处的标题：
//    · 「内」商品详情页 → 「红色大蝴蝶结背心裙」（整名，含颜色）
//    · 「外」点菜式选购 → 「大蝴蝶结背心裙 · 2 色」（款名 + 色数）
//  同款不同色只是颜色不同，标题不该一处带色一处不带。
//
//  收口口径（唯一）：
//    1. **标题文字永远等于款式名**（`ShopCatalogSameDesignGrouper.designName(of:)`），
//       颜色不参与标题文字；同款颜色数 > 1 时，标题后追加「· N 色」**标注**
//       —— 标注说明的是「同款有几个颜色」这个事实，不是颜色值本身。
//    2. **颜色单独呈现**：详情页配色行 / 点菜页颜色 chips / 轮播颜色胶囊 /
//       商品管理颜色标签 —— 入口不同，取值必须走同一个
//       `ShopCatalogColorPresentation.label`，不许各处自己 `colorLabel(for:)`
//       （那个兜底会把整名当颜色返回，标题与颜色会双双退化）。
//    3. **有意保留的例外**：写入心愿尾款 / 少女衣橱的**记录名不是商品标题**，
//       走独立口径 `ShopCatalogWardrobeTitle.recordName` ——
//       2026-09-23 需求 N 把该例外升级为固定三段式
//       ``[系列名] + [款式名] + [颜色]``（缺失项按需求 §III.2 降级）。
//       记录一旦脱离列表就没有其它颜色线索，用户要靠名字找回是哪一条。
//       落点见 `ShopCatalogWardrobeInserter`（`name:` 与套装合并名）。
//

import Foundation

// MARK: - 商品标题

/// 商品标题 = 款式名 + 同款颜色数标注
nonisolated struct ShopCatalogProductTitle: Equatable {
    /// 标题文字（款式名——同款各颜色的标题**完全相同**）
    let text: String
    /// 同款颜色数（含自己，至少 1）
    let colorCount: Int

    /// 是否追加「· N 色」标注
    var showsColorCount: Bool { colorCount > 1 }
    /// 是否属于「同款多色」
    var isMultiColor: Bool { colorCount > 1 }

    /// 「· N 色」标注文案（不需要展示时 nil）
    var colorCountText: String? { showsColorCount ? "· \(colorCount) 色" : nil }

    init(text: String, colorCount: Int) {
        self.text = text
        self.colorCount = max(1, colorCount)
    }
}

/// 标题解析（唯一入口）：详情页 / 点菜页 / 商品管理都从这里取标题，
/// 保证「同一个商品在哪儿看都是同一句话」。
nonisolated enum ShopCatalogTitleResolver {

    /// 由款式名 + 同款颜色数解析
    static func title(designName: String, colorCount: Int) -> ShopCatalogProductTitle {
        ShopCatalogProductTitle(text: designName, colorCount: colorCount)
    }

    /// 由同款商品集合解析（点菜页合并卡 / 商品管理款式组）；空集合 → nil
    static func title(products: [CatalogProduct]) -> ShopCatalogProductTitle? {
        guard let first = products.first else { return nil }
        return ShopCatalogProductTitle(
            text: ShopCatalogSameDesignGrouper.designName(of: first),
            colorCount: products.count)
    }

    /// 由单个商品 + 同款其他颜色商品解析（详情页：自己 + 同款兄弟）
    static func title(product: CatalogProduct, siblings: [CatalogProduct]) -> ShopCatalogProductTitle {
        ShopCatalogProductTitle(
            text: ShopCatalogSameDesignGrouper.designName(of: product),
            colorCount: siblings.count + 1)
    }
}

// MARK: - 颜色呈现

/// 颜色标注口径（唯一）：**显式规格色优先 → 商品名里的颜色词 → nil**
///
/// 硬约束：名称里没有颜色词时**必须返回 nil**，不允许把整个款名当颜色返回。
/// `ShopCatalogSameDesignGrouper.colorLabel(for:)` 的兜底正是「回退整名」，
/// 直接当作颜色用会让「大蝴蝶结背心裙」既当标题又当颜色（同款不同色还会
/// 出现颜色 chips 全等于款名）。要兜底，由调用方自己决定兜到什么。
nonisolated enum ShopCatalogColorPresentation {

    /// 颜色标注：显式规格色优先，其次商品名里的颜色词，两者都没有 → nil
    static func label(explicitColors: [String], name: String) -> String? {
        if let explicit = explicitColors
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return explicit
        }
        return derivedLabel(forName: name)
    }

    /// 只从商品名推导颜色词（名称里没有颜色词 → nil）
    static func derivedLabel(forName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // baseName 剥离后与原名相同 → 名称里没有可识别的颜色词
        let stripped = ShopCatalogSameDesignGrouper.baseName(for: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped != trimmed else { return nil }
        let word = ShopCatalogSameDesignGrouper.colorLabel(for: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return word.isEmpty ? nil : word
    }
}
