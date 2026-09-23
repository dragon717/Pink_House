//
//  ShopCatalogWardrobeEntryPolicy.swift
//  ItemManager
//
//  加购记账状态机 + 衣橱状态标签口径（2026-09-23 需求 N，nonisolated 可单测）。
//
//  核心业务前提（需求 §I）：
//    · 本应用为纯记账 / 收藏 / 进度管理工具，不涉及真实支付。
//    · **所有金额（定金、尾款、预约价）必须由系统自动读取后台数据，用户绝不手动输入。**
//    · 加购时按「预约期是否结束」给出清晰分支。
//
//  加购记账逻辑（需求 §II）：
//    场景一 预约期内：
//      · 支付定金加购 → 衣橱「已付定」+ 心愿尾款自动生成待补任务（尾款读后台）
//      · 支付全款加购 → 衣橱「已全款」（读预约价 / 现货价），**绝不生成心愿尾款任务**
//    场景二 预约期结束后：
//      · 分支 A【加入心愿尾款】→ 默认定金+尾款 → 衣橱「已付定」+ 心愿尾款任务
//      · 分支 B【加入衣橱】→ 默认全款（预约价）→ 衣橱「已全款」，**绝不生成心愿尾款任务**
//
//  状态标签（需求 §III.3）：`全款` / `已付定` / `转单`。
//

import Foundation

// MARK: - 加购分支

/// 加购记账分支（详情页操作区按场景渲染其中的两个）
nonisolated enum ShopCatalogWardrobeEntryOption: Equatable, CaseIterable {
    /// 加入心愿：未付任何款，全部记为待付尾款
    case wishlist
    /// 支付定金加购 → 衣橱「已付定」，心愿尾款里自动生成待补任务
    case depositPaid
    /// 支付全款加购 → 衣橱「已全款」，不生成任何心愿尾款任务
    case fullPaid

    /// 是否落成「定金 + 尾款」计划（只有它会在心愿尾款里留任务）
    var createsFinalPaymentTask: Bool {
        switch self {
        case .wishlist, .depositPaid: return true
        case .fullPaid: return false
        }
    }
}

nonisolated enum ShopCatalogWardrobeEntryPolicy {

    /// 某个场景下可用的加购分支（顺序 = 界面按钮顺序）
    ///
    /// - Parameters:
    ///   - phase: 商品当前购买阶段
    ///   - hasReservationPrice: 后台是否有预约价（定金 / 尾款来源）
    ///   - hasStockPrice: 后台是否有现货价
    static func options(
        phase: ShopCatalogPurchasePhase,
        hasReservationPrice: Bool,
        hasStockPrice: Bool
    ) -> [ShopCatalogWardrobeEntryOption] {
        switch phase {
        case .reservationActive, .reservationEnded:
            // 预约期内 / 预约期结束：都是「定金 + 尾款」与「全款」两条路
            var result: [ShopCatalogWardrobeEntryOption] = []
            if hasReservationPrice { result.append(.depositPaid) }
            if hasReservationPrice || hasStockPrice { result.append(.fullPaid) }
            return result
        case .inStock:
            // 现货在售：直接按现货价全款入库
            return hasStockPrice ? [.fullPaid] : []
        case .reservationUpcoming:
            // 预约未开始：还没有可记的成交价，只能先入心愿（= 开售提醒）
            return [.wishlist]
        case .neutral:
            return hasStockPrice || hasReservationPrice ? [.fullPaid] : []
        }
    }

    /// 分支的按钮文案（不与 `.depositPaid` 复用，避免「我已经预约 / 加入心愿尾款」混淆）
    ///
    /// 说明文字（点明「钱去哪了 / 会不会生成尾款任务」）由视图按场景整段给出：
    /// 详情页两条分支同屏展示时，合并成一句话比逐按钮挂小字更清楚。
    static func buttonTitle(for option: ShopCatalogWardrobeEntryOption, phase: ShopCatalogPurchasePhase) -> String {
        switch option {
        case .wishlist:
            return "加入心愿"
        case .depositPaid:
            return phase == .reservationEnded ? "加入心愿尾款" : "付定金加购"
        case .fullPaid:
            return phase == .reservationEnded ? "加入衣橱" : "全款加购"
        }
    }
}

// MARK: - 待补尾款口径（需求 §II：金额一律读后台，且只有一处算法）

/// 加购记账的**金额取值**唯一口径。
///
/// 需求原文：「尾款金额自动读取后台录入的『尾款』数据」。
/// 后台 `CatalogSaleEvent` 本来就存了独立的 `balance`（尾款）字段，
/// 所以**不能再拿「预约价 − 已付定金」现算**——后台三价不自洽时
/// （例如录入定金 128 + 尾款 300 但预约价写成 430），算出来的尾款
/// 会与用户真正要补的钱差 2 元，直接违反验收标准「心愿尾款里出现金额完全正确的待办任务」。
///
/// 取数顺序：**后台录入的尾款**（`CatalogPriceArchive.currentBalance`，含价格修正值）
/// → 后台没录尾款 → 退回「预约价 − 已付定金」推导。
///
/// `ShopCatalogWardrobeDraftBuilder`（落库）与 `ShopCatalogReservationSheet`（弹窗预览）
/// 必须共用这一份，否则「弹窗显示 302、落库写 300」这种自相矛盾迟早出现。
nonisolated enum ShopCatalogWardrobeAmount {

    /// 待补尾款（全款口径调用方自行传 0，不走这里）
    static func pendingBalance(
        backendBalance: Decimal?,
        reservationPrice: Decimal,
        depositPaid: Decimal
    ) -> Decimal {
        if let backendBalance { return max(0, backendBalance) }
        return max(0, reservationPrice - depositPaid)
    }

    /// 后台三价是否不自洽（定金 + 尾款 ≠ 预约价）
    ///
    /// 不做拦截（数据本来就这么录的，记不下账比记一个自洽的假数更糟），
    /// 只用来决定要不要在记录备注里如实留一句提示。
    static func isBackendPriceInconsistent(
        deposit: Decimal?,
        balance: Decimal?,
        reservationPrice: Decimal
    ) -> Bool {
        guard let deposit, let balance else { return false }
        return deposit + balance != reservationPrice
    }
}

// MARK: - 衣橱卡片状态标签（需求 §III.3）

/// 衣橱卡片状态小标签：`全款` / `已付定` / `转单`（另有沿用中的 `已售出`）
nonisolated enum ShopCatalogWardrobeStatusTag: String, Equatable, CaseIterable {
    case sold = "已售出"
    case fullPaid = "全款"
    case depositPaid = "已付定"
    case resaleTransfer = "转单"

    /// 付款状态 + 来源状态合成卡片标签（付款标签在前，来源标签在后）
    ///
    /// - `已售出` 优先（下架即售出，不再关心付款口径）
    /// - 付款口径：`isFullPaymentReservation` → 全款；`isDepositPlan`（且有尾款）→ 已付定
    /// - `转单` 与付款口径**互相独立**，可同时出现（例：闲鱼收来的转单 + 定金尾款）
    static func chips(
        isSold: Bool,
        isFullPaymentReservation: Bool,
        isDepositPlan: Bool,
        isResaleTransfer: Bool
    ) -> [ShopCatalogWardrobeStatusTag] {
        var result: [ShopCatalogWardrobeStatusTag] = []
        if isSold {
            result.append(.sold)
        } else if isFullPaymentReservation {
            result.append(.fullPaid)
        } else if isDepositPlan {
            result.append(.depositPaid)
        }
        if isResaleTransfer {
            result.append(.resaleTransfer)
        }
        return result
    }
}
