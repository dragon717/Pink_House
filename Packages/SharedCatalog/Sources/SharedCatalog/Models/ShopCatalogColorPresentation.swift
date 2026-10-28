import Foundation

/// 颜色标注口径（唯一）：**显式规格色优先 → 商品名里的颜色词 → nil**
///
/// 硬约束：名称里没有颜色词时**必须返回 nil**，不允许把整个款名当颜色返回。
/// `ShopCatalogSameDesignGrouper.colorLabel(for:)` 的兜底正是「回退整名」，
/// 直接当作颜色用会让「大蝴蝶结背心裙」既当标题又当颜色（同款不同色还会
/// 出现颜色 chips 全等于款名）。要兜底，由调用方自己决定兜到什么。
public nonisolated enum ShopCatalogColorPresentation {

    /// 颜色标注：显式规格色优先，其次商品名里的颜色词，两者都没有 → nil
    public static func label(explicitColors: [String], name: String) -> String? {
        if let explicit = explicitColors
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return explicit
        }
        return derivedLabel(forName: name)
    }

    /// 只从商品名推导颜色词（名称里没有颜色词 → nil）
    public static func derivedLabel(forName name: String) -> String? {
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
