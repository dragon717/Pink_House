//
//  ShopCatalogProductCardLogic.swift
//  ItemManager
//
//  点菜式选购「商品卡片」纯逻辑（2026-09-22，nonisolated 可单测）：
//    · 同款合并：同名仅颜色词不同的商品 → 同一张卡片（卡片内颜色 chips 切换）
//    · 价格阶段：预约期间默认按预约价加入；预约结束且双价并存 → 用户自选现货/预约
//

import Foundation

// MARK: - 同款商品合并（卡片分组键）

/// 「同款不同色」识别：从商品名中剥离颜色词得到「款名」。
/// 只匹配「X色」全称（含常见复合色），不匹配单字色，避免误伤
/// 「樱花粉跳跃」这类把颜色嵌进款名的命名（保守优先：识别不出就不合并）。
nonisolated enum ShopCatalogSameDesignGrouper {

    /// 长词在前：保证「酒红色」先于「红色」被剥离，不会剩下「酒」
    static let colorWords: [String] = [
        "藏青色", "薄荷色", "奶油色", "香槟色", "烟熏色", "酒红色", "墨绿色",
        "深蓝色", "浅蓝色", "浅粉色", "深粉色", "橘色",
        "红色", "粉色", "白色", "黑色", "蓝色", "绿色", "黄色", "紫色", "灰色",
        "棕色", "褐色", "茶色", "金色", "银色", "橙色", "米色",
    ]

    /// 款名 = 商品名剥离颜色词后的剩余部分（剥离后为空则回退原名）
    static func baseName(for name: String) -> String {
        var result = name
        for word in colorWords where result.contains(word) {
            result = result.replacingOccurrences(of: word, with: "")
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    /// 颜色 chips 标签：名字里的颜色词；没有颜色词时回退整名（chips 退化为单品名）
    static func colorLabel(for name: String) -> String {
        for word in colorWords where name.contains(word) { return word }
        return name
    }

    // MARK: 款式归组（2026-09-22 V1.4「同款不同色」全局归类）

    /// 款式名：商品显式 `designName` 优先；未指定时按商品名剥离颜色词派生
    static func designName(of product: CatalogProduct) -> String {
        if let explicit = product.designName?.trimmingCharacters(in: .whitespaces), !explicit.isEmpty {
            return explicit
        }
        return baseName(for: product.name)
    }

    /// 归组键：品类 + 款式名（同品类同款式 → 同一张合并卡 / 同一条列表组）
    static func designKey(of product: CatalogProduct) -> String {
        "\(product.category)|\(designName(of: product))"
    }

    /// 款式名落库解析（发布 / 快速建档）：用户显式填写优先；未填时按名称派生
    static func resolveDesignName(explicit: String?, name: String) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespaces).isEmpty {
            return explicit.trimmingCharacters(in: .whitespaces)
        }
        return baseName(for: name)
    }
}

// MARK: - 卡片价格阶段（预约期间 / 预约结束双价自选）

/// 加购价格口径（映射到 `ShopCatalogWardrobeDraftBuilder.PriceMode`）
nonisolated enum ShopCatalogCardPriceChoice: Equatable {
    case stock        // 按现货价加入（已拥有）
    case reservation  // 按预约价加入（生成定金 + 尾款计划）
}

/// 卡片所处的销售阶段，决定价格展示与加购默认口径
nonisolated enum ShopCatalogCardPricePhase: Equatable {
    /// 预约期间（存在进行中的预约窗口）：默认直接按预约价加入
    case reservationOpen
    /// 预约结束且现货 / 预约双价并存：用户自选按哪种价格加入（默认现货）
    case chooseAfterEnded
    /// 只有预约价（无论窗口状态）
    case reservationOnly
    /// 只有现货价
    case spotOnly
    /// 两种价格都没有
    case noPrice

    /// 该阶段是否允许用户在 现货 / 预约 之间自选
    var allowsChoice: Bool { self == .chooseAfterEnded }

    /// 加购默认口径：预约期间 / 仅预约 → 预约价；其余 → 现货价（缺价由展示层兜底）
    var defaultChoice: ShopCatalogCardPriceChoice {
        switch self {
        case .reservationOpen, .reservationOnly: return .reservation
        case .chooseAfterEnded, .spotOnly, .noPrice: return .stock
        }
    }

    /// - Parameters:
    ///   - stockPrice: 当前现货价（修正后口径）
    ///   - reservationPrice: 当前预约价（修正后口径）
    ///   - reservationOpen: 是否存在**进行中**的预约销售窗口
    static func of(stockPrice: Decimal?, reservationPrice: Decimal?,
                   reservationOpen: Bool) -> ShopCatalogCardPricePhase {
        switch (stockPrice, reservationPrice) {
        case (.some, .some):
            return reservationOpen ? .reservationOpen : .chooseAfterEnded
        case (nil, .some):
            return .reservationOnly
        case (.some, nil):
            return .spotOnly
        default:
            return .noPrice
        }
    }
}
