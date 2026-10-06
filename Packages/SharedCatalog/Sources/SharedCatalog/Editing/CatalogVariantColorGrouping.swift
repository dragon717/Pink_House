//
//  CatalogVariantColorGrouping.swift
//  SharedCatalog
//
//  「规格（配色 / 尺码）」在**商品档案页**里的显示口径（2026-10-07 用户需求）。
//
//  ## 用户原文
//
//    「……规格颜色区域默认仅显示颜色信息。请明确勾选与取消的触发时机、
//      颜色规格的显示规则。」
//
//  ## 要解决的问题
//
//  规格是「颜色 × 尺码」的笛卡尔积：3 色 × 5 码 = 15 行。
//  商品档案页原本把 15 条**平铺**出来，用户想确认「这个款有哪几个颜色」
//  得自己数 15 行；想改某一条还得在 15 行里找。而真正要天天看的
//  「有哪几个颜色」只有一个数量级更小的答案。
//
//  ## 显示规则（这就是「颜色规格的显示规则」本身）
//
//  1. **默认只显示颜色**：一行 = 一个颜色。行内给：该颜色的代表缩略图、
//     颜色名、**尺码摘要**、缺图条数。展开某一行才逐条列出 (色 / 码) 与操作按钮。
//  2. **颜色归一**：`nil` / 空串 / 纯空白 → 同一个「未区分颜色」组
//     （和 `variantLabel` 里 `(nil, nil) → "未区分"` 是同一个立场：
//      没填就是没填，不许凭空造一个颜色名）。
//  3. **顺序 = 首次录入顺序**。绝不按颜色名排序、更绝不用 `Set` / `Dictionary`
//     遍历序 —— 后者每次渲染都可能变，看起来像列表在随机抖动。
//  4. **代表缩略图 = 该颜色里第一条有图的规格**，不是「第一条规格」。
//     否则第一行刚好没配图时，明明有图的颜色会显示成空框。
//
//  ## 为什么这条规则住在共享包
//
//  它是**判定 + 口径文案**，不是布局。写在 Mac target 里就永远没有自动验证 ——
//  `PinkHouseOpsTests` 是 App 宿主式，本机 `xcodebuild test` 会永久挂起
//  （见 skill `pink-house-xcodebuild-acceptance` §1f）。放进共享包后
//  `swift test` 秒级覆盖；Mac 那边只剩「怎么摆」。
//

import Foundation

/// 按颜色归组后的一个分组。
///
/// `color == nil` 表示**未区分颜色**（录入时颜色留空），不是「没有颜色」。
///
/// 刻意**不加 `Equatable` 约束**：那会把 `Item: Equatable` 传染给
/// `groups(_:color:)` 这类纯归组方法，逼得调用方为「比颜色」去满足「比规格」。
public struct CatalogVariantColorGroup<Item> {
    /// 归一后的颜色名（`nil` = 未区分）
    public let color: String?
    /// 属于这个颜色的规格，**保持录入顺序**
    public let items: [Item]

    public init(color: String?, items: [Item]) {
        self.color = color
        self.items = items
    }
}

public enum CatalogVariantColorGrouping {

    /// 单值归一：`nil` / 空串 / 纯空白 → `nil`。
    public static func normalizedColor(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 按颜色归组。**组的顺序 = 该颜色第一次出现的顺序**；
    /// 组内的顺序 = 传入顺序（对规格来说就是录入顺序）。
    public static func groups<Item>(
        _ items: [Item],
        color: (Item) -> String?
    ) -> [CatalogVariantColorGroup<Item>] {
        var order: [String?] = []
        var buckets: [String?: [Item]] = [:]
        for item in items {
            let key = normalizedColor(color(item))
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(item)
        }
        return order.map { key in
            CatalogVariantColorGroup(color: key, items: buckets[key] ?? [])
        }
    }

    /// 分组标题。未区分颜色时给一个**明确**的说法，不用空字符串
    ///（空白行看着像渲染出错，用户也不知道该不该去补颜色）。
    public static func colorTitle(_ color: String?) -> String {
        normalizedColor(color) ?? "未区分颜色"
    }

    /// 尺码摘要：`"5 个尺码：S、M、L、XL、XXL"` / `"无尺码"`。
    ///
    /// 去重且**按首次出现顺序**；同一组里混了「有尺码」和「无尺码」的规格时，
    /// 额外报一句「另有 N 条无尺码」—— 这是数据本身不齐，不能吞掉。
    public static func sizeSummary(_ sizes: [String?]) -> String {
        let normalized = sizes.map { normalizedColor($0) }
        var seen = Set<String>()
        var named: [String] = []
        for size in normalized {
            guard let size, !seen.contains(size) else { continue }
            seen.insert(size)
            named.append(size)
        }
        let unsized = normalized.filter { $0 == nil }.count
        guard !named.isEmpty else { return "无尺码" }
        var text = "\(named.count) 个尺码：\(named.joined(separator: "、"))"
        if unsized > 0 { text += "（另有 \(unsized) 条无尺码）" }
        return text
    }

    /// 缺图条数：`image` 返回 `nil` / 空白即算缺。
    public static func missingImageCount<Item>(
        _ items: [Item],
        image: (Item) -> String?
    ) -> Int {
        items.filter { normalizedColor(image($0)) == nil }.count
    }

    /// 该组的**代表图**：第一条有图的规格的图引用。
    /// 全都没图 → `nil`（界面该显示占位，而不是显示成「这一色没有图」）。
    public static func leadingImage<Item>(
        _ items: [Item],
        image: (Item) -> String?
    ) -> String? {
        for item in items {
            if let reference = normalizedColor(image(item)) { return reference }
        }
        return nil
    }

    /// 值不值得分组显示。
    /// 只有一个颜色时分组没有任何信息量 —— 多一层「展开」只是多点一次。
    public static func shouldGroup<Item>(
        _ items: [Item],
        color: (Item) -> String?
    ) -> Bool {
        groups(items, color: color).count > 1
    }

    /// 「展开全部 / 收起全部」按钮该显示成哪个动作。
    /// 全部已展开 → 显示「收起全部」；否则显示「展开全部」（含「部分展开」）。
    public static func allExpanded<Item>(
        _ items: [Item],
        color: (Item) -> String?,
        isExpanded: (String?) -> Bool
    ) -> Bool {
        let all = groups(items, color: color)
        guard !all.isEmpty else { return false }
        return all.allSatisfy { isExpanded($0.color) }
    }
}
