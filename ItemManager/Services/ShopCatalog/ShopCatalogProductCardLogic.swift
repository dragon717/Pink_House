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

// 同款归组已迁入 SharedCatalog/Models/ShopCatalogSameDesignGrouper.swift，Mac 与 iOS 共用。

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
