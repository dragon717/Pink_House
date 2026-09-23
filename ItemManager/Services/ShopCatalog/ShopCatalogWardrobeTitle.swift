//
//  ShopCatalogWardrobeTitle.swift
//  ItemManager
//
//  衣橱卡片标题口径（2026-09-23 需求 N，nonisolated 可单测）。
//
//  需求原文：「商品加入衣橱后，生成的卡片标题必须严格按照以下固定格式组合：
//  `[系列名] + [款式名] + [颜色]`（示例：`天鹅之歌 段段方领JSK 生成色`）」
//
//  降级规则（需求 §III.2）：
//    · 若无系列名        → `[款式名] + [颜色]`
//    · 若为纯配饰（无颜色）→ `[系列名] + [款式名]`
//    · 若既无系列名又无颜色 → 仅 `[款式名]`
//
//  与 `ShopCatalogTitlePresentation` 的分工（重要，别合并）：
//    · 那里管的是**商品标题**（详情页 / 点菜页 / 商品管理）——标题 = 款式名，
//      颜色只以「· N 色」标注，不写进标题文字。
//    · 这里管的是**写入衣橱的记录名**——记录一旦脱离列表就没有其它线索，
//      必须自带系列 + 款式 + 颜色，用户才能靠名字找回是哪一条。
//      这是 `ShopCatalogTitlePresentation` 头部注释里写明的「有意保留的例外」，
//      需求 N 把该例外升级为固定三段式。
//

import Foundation

nonisolated enum ShopCatalogWardrobeTitle {

    /// 衣橱记录名 = 系列名 + 款式名 + 颜色（空格分隔，缺失项按降级规则自动省略）
    ///
    /// - Parameters:
    ///   - seriesName: 商品所属系列名（可空：无系列 / 旧数据）
    ///   - designName: 款式名（`ShopCatalogSameDesignGrouper.designName(of:)`）
    ///   - color: 颜色（规格色 / 商品名颜色词；纯配饰传 nil）
    static func recordName(seriesName: String?, designName: String, color: String?) -> String {
        let series = normalize(seriesName)
        let design = normalize(designName)
        let tone = normalize(color)

        var parts: [String] = []
        // 防重复：款式名里已经带上了系列名（如「雪国来信 JSK」属于「雪国来信」系列）
        // 时不再前置，否则卡片会出现「雪国来信 雪国来信 JSK 夜空蓝」。
        if let series, let design, design.contains(series) {
            parts.append(design)
        } else if let series {
            parts.append(series)
            if let design { parts.append(design) }
        } else if let design {
            parts.append(design)
        }
        if let tone { parts.append(tone) }
        return parts.joined(separator: " ")
    }

    /// 由商品 + 所属系列名 + 用户选定色解析记录名（唯一入口，加购链路都走这里）
    static func recordName(product: CatalogProduct, seriesName: String?, color: String?) -> String {
        recordName(
            seriesName: seriesName,
            designName: ShopCatalogSameDesignGrouper.designName(of: product),
            color: color
        )
    }

    /// 记录用颜色：用户选定色优先 → 后台规格色（第一个）→ 商品名里的颜色词 → nil
    ///
    /// 「系统自动读取后台数据，不让用户动脑」：详情页单品入库时用户可能没点颜色，
    /// 这里替他从后台规格色里取默认值，保证记录名**总能带上颜色**（同名不同色可区分）。
    /// 纯配饰（既无规格色也无颜色词）返回 nil → 标题自动降级为 `[系列名] + [款式名]`。
    static func resolvedColor(explicit: String?, specColors: [String], productName: String) -> String? {
        var explicitColors: [String] = []
        if let explicit = normalize(explicit) { explicitColors.append(explicit) }
        explicitColors.append(contentsOf: specColors)
        return ShopCatalogColorPresentation.label(explicitColors: explicitColors, name: productName)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
