import Foundation

/// 「同款不同色」识别：从商品名中剥离颜色词得到「款名」。
/// 只匹配「X色」全称（含常见复合色），不匹配单字色，避免误伤
/// 「樱花粉跳跃」这类把颜色嵌进款名的命名（保守优先：识别不出就不合并）。
public nonisolated enum ShopCatalogSameDesignGrouper {

    /// 长词在前：保证「酒红色」先于「红色」被剥离，不会剩下「酒」
    /// 2026-09-23 补充：录入端真实数据里出现「生成色」「粉紫色」这类**不含基础色词**的
    /// 复合颜色名 —— 旧表里没有它们，「生成色一字领OP / 粉紫色一字领OP / 蓝色一字领OP」
    /// 会被派生款名拆成三款（生成色一字领OP / 粉一字领OP / 一字领OP），同款归组与
    /// 尺码表共享全部失效。复合词一律排在基础词之前。
    public static let colorWords: [String] = [
        "生成色", "粉紫色",
        "藏青色", "薄荷色", "奶油色", "香槟色", "烟熏色", "酒红色", "墨绿色",
        "深蓝色", "浅蓝色", "浅粉色", "深粉色", "橘色",
        "红色", "粉色", "白色", "黑色", "蓝色", "绿色", "黄色", "紫色", "灰色",
        "棕色", "褐色", "茶色", "金色", "银色", "橙色", "米色",
    ]

    /// 款名 = 商品名剥离颜色词后的剩余部分（剥离后为空则回退原名）
    public static func baseName(for name: String) -> String {
        var result = name
        for word in colorWords where result.contains(word) {
            result = result.replacingOccurrences(of: word, with: "")
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    /// 颜色 chips 标签：名字里的颜色词；没有颜色词时回退整名（chips 退化为单品名）
    public static func colorLabel(for name: String) -> String {
        for word in colorWords where name.contains(word) { return word }
        return name
    }

    // MARK: 款式归组（2026-09-22 V1.4「同款不同色」全局归类）

    /// 款式名：商品显式 `designName` 优先；未指定时按商品名剥离颜色词派生
    public static func designName(of product: CatalogProduct) -> String {
        if let explicit = product.designName?.trimmingCharacters(in: .whitespaces), !explicit.isEmpty {
            return explicit
        }
        return baseName(for: product.name)
    }

    /// 归组键：品类 + 款式名（同品类同款式 → 同一张合并卡 / 同一条列表组）
    public static func designKey(of product: CatalogProduct) -> String {
        "\(product.category)|\(designName(of: product))"
    }

    /// 款式名落库解析（发布 / 快速建档）：用户显式填写优先；未填时按名称派生
    public static func resolveDesignName(explicit: String?, name: String) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespaces).isEmpty {
            return explicit.trimmingCharacters(in: .whitespaces)
        }
        return baseName(for: name)
    }
}
