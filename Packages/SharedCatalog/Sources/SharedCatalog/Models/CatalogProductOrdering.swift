import Foundation

/// Mac 录入类型顺序与用户侧商品展示共用口径；显式发布顺序优先。
public nonisolated enum CatalogProductOrdering {
    public static let operatorCategories = [
        "OP", "JSK", "SK", "开衫", "衬衫", "内搭", "围裙/罩裙", "斗篷", "小物", "包", "其他"
    ]

    // 旧目录保留英文类型及鞋，放在对应语义位置；不增加 Mac 固定录入选项。
    private static let legacyCategories: [String] = {
        var result = operatorCategories.filter { $0 != "其他" }
        for (legacy, before) in [("Blouse", "内搭"), ("KC", "小物"), ("鞋", "包")] {
            result.insert(legacy, at: result.firstIndex(of: before) ?? result.endIndex)
        }
        return result
    }()

    public static func categories(in products: [CatalogProduct]) -> [String] {
        let ranked = byRank(products)
        var seen: Set<String> = []
        let present = ranked.map(\.category).filter { seen.insert($0).inserted }
        if ranked.contains(where: { validRank($0) != nil }) { return present }
        let fixed = legacyCategories.filter { seen.contains($0) }
        return fixed + present.filter { !legacyCategories.contains($0) && $0 != "其他" }
            + (seen.contains("其他") ? ["其他"] : [])
    }

    public static func ordered(_ products: [CatalogProduct]) -> [CatalogProduct] {
        let ranked = byRank(products)
        let groups = Dictionary(grouping: ranked, by: \.category)
        return categories(in: ranked).flatMap { groups[$0] ?? [] }
    }

    /// 发布数组也必须承载已保存顺序，兼容尚不识别 displayOrder 的客户端。
    /// 仅重排有明确顺序的系列自身占据的位置，不改其它系列或未排序目录。
    public static func publicationOrder(_ products: [CatalogProduct]) -> [CatalogProduct] {
        let groups = Dictionary(grouping: products, by: { Scope(shopID: $0.shopID, seriesID: $0.seriesID) })
            .mapValues { group in group.contains { validRank($0) != nil } ? ordered(group) : group }
        var offsets: [Scope: Int] = [:]
        return products.map { product in
            let key = Scope(shopID: product.shopID, seriesID: product.seriesID)
            let offset = offsets[key, default: 0]
            offsets[key] = offset + 1
            return groups[key]?[offset] ?? product
        }
    }

    private struct Scope: Hashable {
        let shopID: String
        let seriesID: String
    }

    private static func validRank(_ product: CatalogProduct) -> Int? {
        product.displayOrder.flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func byRank(_ products: [CatalogProduct]) -> [CatalogProduct] {
        products.enumerated().sorted { left, right in
            switch (validRank(left.element), validRank(right.element)) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.offset < right.offset
            }
        }.map(\.element)
    }
}
