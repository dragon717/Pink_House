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
//  2026-09-24 需求三补充「尾款中」（`ShopCatalogPurchasePhase.balancePending`）：
//    该阶段的业务动作**就是补尾款**，所以引导口径与「预约中」同族 ——
//    默认选中「加入心愿尾款（定金 + 尾款）」；两个选项仍同屏可选、不隐藏不置灰
//    （2026-09-23 用户裁定「只改引导，不剥夺能力」继续成立）。
//
//  2026-09-24 需求三补充「现货阶段只提供全款、但价格口径有两个」（本次）：
//    定金 + 尾款阶段结束、进入**现货阶段**后，不再提供「定金 + 尾款」记账（这一阶段
//    已经没有预约窗口可挂计划），只给**全款**，但给出两个价格口径让用户选：
//      · ① 按**预约价**全款加入（`fullPaid`）—— 当时按预约价买断、现在才补记
//      · ② 按**现货价**全款加入（`fullStockPaid`）—— 现在按现货价买断
//    两者都记为衣橱「已全款」、都**不生成心愿尾款任务**，差别只在入橱金额的来源。
//
//  状态标签（需求 §III.3）：`全款` / `已付定` / `转单`。
//

import Foundation

/// 上新窗口状态的小辅助：open / ongoing 都视为「可操作」
/// （2026-09-27 从详情页 fileprivate 提升为 internal：阶段推导共享口径要用它）
extension ShopCatalogStore.SaleWindowStatus {
    var isOpenLike: Bool { self == .open || self == .ongoing }
}

// MARK: - 加购分支

/// 加购记账分支（详情页操作区按场景渲染其中的两个）
nonisolated enum ShopCatalogWardrobeEntryOption: Equatable, CaseIterable {
    /// 加入心愿：未付任何款，全部记为待付尾款
    case wishlist
    /// 支付定金加购 → 衣橱「已付定」，心愿尾款里自动生成待补任务
    case depositPaid
    /// 支付全款加购（金额 = 后台**预约价**）→ 衣橱「已全款」，不生成任何心愿尾款任务
    case fullPaid
    /// 支付全款加购（金额 = 后台**现货价**）→ 衣橱「已全款」，不生成任何心愿尾款任务
    ///
    /// 现货阶段（2026-09-24 需求）：定金 + 尾款阶段结束后已经没有预约计划可挂，
    /// 只提供全款，但「按哪个价记」这件事仍要用户自己定 —— 见 `fullPaymentOptions`。
    case fullStockPaid

    /// 是否落成「定金 + 尾款」计划（只有它会在心愿尾款里留任务）
    var createsFinalPaymentTask: Bool {
        switch self {
        case .wishlist, .depositPaid: return true
        case .fullPaid, .fullStockPaid: return false
        }
    }

    /// 是否属于「全款一次记清」口径（两个价格口径都算，都不生成尾款任务）
    var isFullPayment: Bool {
        switch self {
        case .fullPaid, .fullStockPaid: return true
        case .wishlist, .depositPaid: return false
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
        case .reservationActive, .reservationEnded, .balancePending:
            // 预约期内 / 预约期结束 / 尾款中：都是「定金 + 尾款」与「全款」两条路，
            // 两条都从**预约价档案**取数（现货价在这一阶段不是可选项）→
            // 没有预约价就一条都不给，由调用方回退既有的现货入库路径。
            guard hasReservationPrice else { return [] }
            return [.depositPaid, .fullPaid]
        case .inStock:
            // 现货阶段（2026-09-24 需求）：**只有全款**，但两个价格口径都要给
            return fullPaymentOptions(
                hasReservationPrice: hasReservationPrice, hasStockPrice: hasStockPrice)
        case .reservationUpcoming:
            // 预约未开始：还没有可记的成交价，只能先入心愿（= 开售提醒）
            return [.wishlist]
        case .neutral:
            return fullPaymentOptions(
                hasReservationPrice: hasReservationPrice, hasStockPrice: hasStockPrice)
        }
    }

    /// 现货阶段的全款两个价格口径（顺序 = 界面顺序）：
    ///   ① 按预约价全款加入（有预约价档案时）② 按现货价全款加入（有现货价时）
    ///
    /// 两个口径都**不生成心愿尾款任务**（`createsFinalPaymentTask == false`），
    /// 差别只在入橱金额取自哪份价格档案；缺档的口径直接不出现在列表里
    /// （宁可不给，也不给一个点下去必然取不到数的选项）。
    static func fullPaymentOptions(
        hasReservationPrice: Bool,
        hasStockPrice: Bool
    ) -> [ShopCatalogWardrobeEntryOption] {
        var result: [ShopCatalogWardrobeEntryOption] = []
        if hasReservationPrice { result.append(.fullPaid) }
        if hasStockPrice { result.append(.fullStockPaid) }
        return result
    }

    /// 分支的按钮文案（不与 `.depositPaid` 复用，避免「我已经预约 / 加入心愿尾款」混淆）
    ///
    /// 说明文字（点明「钱去哪了 / 会不会生成尾款任务」）由视图按场景整段给出：
    /// 详情页两条分支同屏展示时，合并成一句话比逐按钮挂小字更清楚。
    static func buttonTitle(for option: ShopCatalogWardrobeEntryOption, phase: ShopCatalogPurchasePhase) -> String {
        // 「预约已结束 / 尾款中 / 现货」都已过预约窗口，文案用「加入…」而不是「付定金加购」
        let afterReservationWindow = phase != .reservationActive && phase != .reservationUpcoming
        switch option {
        case .wishlist:
            return "加入心愿"
        case .depositPaid:
            return afterReservationWindow ? "加入心愿尾款" : "付定金加购"
        case .fullPaid, .fullStockPaid:
            return afterReservationWindow ? "加入衣橱" : "全款加购"
        }
    }

    // MARK: 阶段化「加入衣橱」选择弹窗（2026-09-24 需求）

    /// 选择弹窗里选项的标题（**按阶段取文案**）：
    ///   · 预约中 / 预约已结束 / 尾款中：
    ///       depositPaid → 「加入心愿尾款（定金+尾款）」、fullPaid → 「预约价全款预约」
    ///   · 现货阶段：
    ///       fullPaid → 「按预约价全款加入」、fullStockPaid → 「按现货价全款加入」
    ///       （这一阶段已经没有「预约」这个动作了，两个选项是**价格口径**而不是付款方式，
    ///        所以不能沿用「预约价全款预约」这句会让人以为还在预约期的文案）
    static func choiceTitle(
        for option: ShopCatalogWardrobeEntryOption,
        phase: ShopCatalogPurchasePhase
    ) -> String {
        switch option {
        case .depositPaid: return "加入心愿尾款（定金+尾款）"
        case .fullPaid: return phase == .inStock ? "按预约价全款加入" : "预约价全款预约"
        case .fullStockPaid: return "按现货价全款加入"
        case .wishlist: return "加入心愿"
        }
    }

    /// 选择弹窗里选项的一句话说明（钱去哪了 / 会不会生成尾款任务）
    static func choiceCaption(for option: ShopCatalogWardrobeEntryOption) -> String {
        switch option {
        case .depositPaid: return "按后台已付定金记账，尾款自动进入心愿尾款等你补款"
        case .fullPaid: return "按后台预约价一次记清，衣橱记为「已全款」，不生成尾款任务"
        case .fullStockPaid: return "按后台现货价一次记清，衣橱记为「已全款」，不生成尾款任务"
        case .wishlist: return "先收藏，付款计划稍后再定"
        }
    }

    /// 选择弹窗的**默认选中**口径（2026-09-24 需求，nonisolated 可单测）。
    ///
    /// 返回值同时是「**要不要弹选择弹窗**」的判据：nil = 该阶段没有可选项，走各自原路径。
    ///
    ///   · 预约中（reservationActive）   → 「加入心愿尾款（定金 + 尾款）」
    ///   · 尾款中（balancePending）      → 「加入心愿尾款（定金 + 尾款）」
    ///     —— 这一阶段的主动作就是补尾款，与「预约中」同族引导（需求三）
    ///   · 预约已结束（reservationEnded）→ 「预约价全款预约」
    ///   · **现货（inStock）→ 「按现货价全款加入」**（没有现货价才退回「按预约价全款加入」）
    ///     —— 现货阶段只提供全款，但两个价格口径都要给用户选（需求：现货阶段仅全款）。
    ///     默认选现货价：用户此刻买的就是现货价，按预约价记是「补记当年预约时买断」的少数情形。
    ///   · 预约未开始（reservationUpcoming）→ nil（加入心愿 = 开售提醒）
    ///
    /// 关键交互约束：预约中 / 预约已结束 / 尾款中 / 现货四个阶段**不得静默默认**任何一种
    /// 付款方式直接加入，必须先弹出选择弹窗，由用户选定并确认后才落库。
    static func defaultChoiceOption(
        phase: ShopCatalogPurchasePhase,
        hasReservationPrice: Bool,
        hasStockPrice: Bool
    ) -> ShopCatalogWardrobeEntryOption? {
        switch phase {
        case .reservationActive, .balancePending:
            return hasReservationPrice ? .depositPaid : nil
        case .reservationEnded:
            return hasReservationPrice ? .fullPaid : nil
        case .inStock:
            if hasStockPrice { return .fullStockPaid }
            return hasReservationPrice ? .fullPaid : nil
        case .reservationUpcoming:
            return nil
        case .neutral:
            // 无窗口但有价档案：同样只提供全款，默认现货价
            if hasStockPrice { return .fullStockPaid }
            return hasReservationPrice ? .fullPaid : nil
        }
    }

    // MARK: 多入口统一的「加入方式」选择（2026-09-27 需求）

    /// 商品当前购买阶段的**唯一共享口径**（2026-09-27 起）。
    ///
    /// 详情页操作区与多选确认页（`ShopCatalogWardrobeMergeView`）的「加入方式」候选
    /// 都必须从这里取，禁止各自再写一套阶段推导——否则同一商品两个入口给出的
    /// 选项不一致，确认页里看到的会跟详情页说的对不上。
    ///
    /// 判定顺序（与详情页原实现逐字等价，只是搬进来共享）：
    ///   1. 系列层「发售阶段」声明优先（`CatalogSeriesSalePhaseResolver.effectivePhase`，
    ///      读取时判定：过了预约结束 → 预约已结束；具体尾款时间到点 → 尾款中）；
    ///   2. 未声明 → 按销售事件档期推导（`ShopCatalogPurchasePhase.resolve`）。
    @MainActor
    static func purchasePhase(
        for productID: String,
        series: CatalogSeries?,
        store: ShopCatalogStore,
        now: Date = Date()
    ) -> ShopCatalogPurchasePhase {
        if let series,
           let declared = CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now) {
            switch declared {
            case .reservationActive: return .reservationActive
            case .reservationEnded: return .reservationEnded
            case .balancePending: return .balancePending
            case .inStock: return .inStock
            }
        }
        let events = store.saleEvents(forProduct: productID)
        let reservationStatuses = events
            .filter { $0.type == .reservation }
            .map { store.windowStatus(of: $0, now: now) }
        let stockWindowOpen = events.contains {
            $0.type != .reservation && store.windowStatus(of: $0, now: now).isOpenLike
        }
        let archive = store.priceArchive(forProduct: productID)
        return ShopCatalogPurchasePhase.resolve(
            reservationStatuses: reservationStatuses,
            stockWindowOpen: stockWindowOpen,
            hasStockPrice: archive.currentStockPrice != nil,
            hasReservationPrice: archive.reservation != nil
        )
    }

    /// 多选确认页里每件商品的**初始选中项**（nonisolated 可单测）。
    ///
    /// 优先级：
    ///   1. 点菜页自选口径的偏好（`reservation` → 定金+尾款；`stock` → 现货价全款），
    ///      前提是它在该阶段的候选里；
    ///   2. 否则阶段默认（`defaultChoiceOption`）；
    ///   3. 都不在候选里 → 候选第一项；
    ///   4. 候选为空（无任何可用价格档案）→ `nil`，调用方回退现货兜底。
    static func mergeEntryInitialOption(
        preferredCardChoice: ShopCatalogCardPriceChoice?,
        phase: ShopCatalogPurchasePhase,
        hasReservationPrice: Bool,
        hasStockPrice: Bool
    ) -> ShopCatalogWardrobeEntryOption? {
        // 「加入心愿」不是衣橱确认页的加入方式（它没有金额口径可记）——
        // options() 只在预约未开始阶段返回它，这里统一过滤，避免确认页
        // 给出一个「选定后落不了库」的候选。
        let candidates = options(
            phase: phase,
            hasReservationPrice: hasReservationPrice,
            hasStockPrice: hasStockPrice
        ).filter { $0 != .wishlist }
        guard !candidates.isEmpty else { return nil }
        let preferred: ShopCatalogWardrobeEntryOption?
        switch preferredCardChoice {
        case .reservation: preferred = .depositPaid
        case .stock: preferred = .fullStockPaid
        case nil: preferred = nil
        }
        if let preferred, candidates.contains(preferred) { return preferred }
        if let fallback = defaultChoiceOption(
            phase: phase,
            hasReservationPrice: hasReservationPrice,
            hasStockPrice: hasStockPrice
        ), candidates.contains(fallback) {
            return fallback
        }
        return candidates.first
    }

    /// 加入方式 → 落库 `PriceMode`：多选确认页与详情页确认弹窗的**同一份映射**。
    static func priceMode(
        for option: ShopCatalogWardrobeEntryOption,
        backendDeposit: Decimal
    ) -> ShopCatalogWardrobeDraftBuilder.PriceMode {
        switch option {
        case .fullPaid: return .fullReservation
        case .fullStockPaid: return .fullStock
        case .depositPaid, .wishlist: return .reservation(depositPaid: backendDeposit)
        }
    }

    /// 后台已付定金（修正后口径）：`currentDeposit`（含价格修正）优先，缺省 0，
    /// 并钳制在预约价以内——与详情页确认弹窗同一份算法，不许两端各算各的。
    static func backendDeposit(
        currentDeposit: Decimal?,
        reservationPrice: Decimal
    ) -> Decimal {
        min(max(0, currentDeposit ?? 0), max(0, reservationPrice))
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
