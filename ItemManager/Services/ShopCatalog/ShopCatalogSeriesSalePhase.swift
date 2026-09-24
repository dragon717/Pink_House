//
//  ShopCatalogSeriesSalePhase.swift
//  ItemManager
//
//  系列「发售阶段」口径（2026-09-23 需求二，2026-09-24 需求三/四扩展；nonisolated 可单测）。
//
//  需求原文要点：
//    §二.1 基础信息处新增「发售阶段」：预约中 / 预约已结束（或 现货）。
//    §二.2 选「预约中」必须填「预约结束时间」；选「预约已结束」隐藏该输入框。
//    §二.3 「系统需增加定时任务或触发机制：一旦当前时间超过了设定的『预约结束时间』，
//           系统自动将该系列的『发售阶段』变更为 预约已结束」。
//    §二.4 **数据保留（最重要）**：预约结束后，预约价 / 定金 / 尾款 / 现货价必须完全保留，
//           不清空、不隐藏；用户仍能看到原预约价，只是不再拿它做定金 + 尾款的分期。
//
//  2026-09-24 需求三（新增「尾款中」）与需求四（预约中可填「尾款时间」）在本文件落地：
//    · 阶段多一个 `.balancePending`（尾款中），排在「预约已结束」与「现货」之间；
//    · 「预约中」可填尾款时间（大致 / 具体，见 `CatalogSeriesBalanceDue`）；
//    · 填了**具体**尾款时间的系列，到点后由「预约中 / 预约已结束」自动流转为「尾款中」。
//
//  ── 为什么用「读取时判定」而不是「定时任务回写存储」 ──
//
//  两种实现都能满足 §二.3 的**效果**，这里选前者，理由是后者会引入两个新问题：
//    1. 回写会**覆盖运营声明**：运营手工把阶段改回「预约中」（例如又开了一批），
//       一个后台任务在下一轮扫描时按旧时间又把它改回「预约已结束」，用户会看到
//       「我改的设置自己变回去了」。
//    2. 回写要动覆盖层（`ShopCatalogDraftStore` 的写入口），涉及落盘失败 / 并发写 /
//       幂等，为一个纯派生结果付这些复杂度不划算。
//
//  读取时判定的真相来源只有一个：`声明值 + 预约结束时间 + 尾款时间 + 当前时间`。
//  不可能出现「存储说预约中、展示说已结束」的不一致，也不需要任何后台调度。
//  新增的「尾款中」自动流转沿用同一条原则（见 `effectivePhase` 的规则表）。
//
//  ── 与需求 N 的关系（2026-09-23 用户拍板） ──
//
//  需求二说「结束后不能用预约价做定金 + 尾款分期」，需求 N 的场景二要求结束后仍提供
//  【加入心愿尾款】（定金 + 尾款）。用户裁定：**结束只改变默认 UI 引导（主推全款），
//  不剥夺用户记录「定金 + 尾款」的能力**，以「全款为主、定金尾款为隐藏备用」实现。
//  因此本模块**不做任何能力门禁**，只提供「主推全款」的引导判据 `prefersFullPayment`。
//

import Foundation

nonisolated enum CatalogSeriesSalePhaseResolver {

    // MARK: 生效阶段（§二.3 自动流转 + 需求三「尾款中」）

    /// 生效阶段 = 声明值 + 过期自动流转（**唯一判定点**，视图别再自己写 `if now > end`）。
    ///
    /// 规则表（`declared` → 生效阶段）：
    ///
    /// | 声明 | 条件 | 生效 |
    /// |---|---|---|
    /// | `nil` | — | `nil`（未声明：调用方沿用销售记录档期推导，旧行为不变） |
    /// | `预约中` | 未填预约结束时间 | `预约中`（缺依据就不猜） |
    /// | `预约中` | 当前 ≤ 预约结束时间 | `预约中` |
    /// | `预约中` | 已过预约结束时间，且尾款时间**具体**且已到 | `尾款中` |
    /// | `预约中` | 已过预约结束时间，其余情况 | `预约已结束` |
    /// | `预约已结束` | 尾款时间**具体**且已到 | `尾款中` |
    /// | `预约已结束` | 其余情况 | `预约已结束` |
    /// | `尾款中` / `现货` | — | 原样返回（**运营显式声明最优先**，时间不改写它） |
    ///
    /// 两条不变式：
    ///   · 自动流转只会**向后**走（预约中 → 预约已结束 → 尾款中），永不回退；
    ///   · 只有**具体**尾款时间能触发流转（大致时间见 `CatalogSeriesBalanceDue.isDue`）。
    ///     「预约已结束 → 尾款中」这条对「曾在预约中填过尾款时间、后又被手动改成预约已结束」
    ///     的系列同样成立，因为那个时间点是**事实**，保存时不会被清掉。
    static func effectivePhase(
        declared: CatalogSeriesSalePhase?,
        reservationEndAt: Date?,
        balanceDueKind: CatalogBalanceDueKind?,
        balanceDueAt: Date?,
        now: Date
    ) -> CatalogSeriesSalePhase? {
        guard let declared else { return nil }
        // 显式声明「尾款中 / 现货」不被时间改写：运营说了算（同 §二 的「不覆盖声明」）
        guard declared == .reservationActive || declared == .reservationEnded else { return declared }

        if declared == .reservationActive {
            // 未填结束时间 → 保持预约中；已填且未到 → 保持预约中
            guard let end = reservationEndAt else { return .reservationActive }
            guard now > end else { return .reservationActive }
        }
        // 走到这里 = 「预约已结束」的时刻已到（或本来就声明为预约已结束）
        return CatalogSeriesBalanceDue.isDue(kind: balanceDueKind, at: balanceDueAt, now: now)
            ? .balancePending
            : .reservationEnded
    }

    /// 旧签名（不涉及尾款时间）：`effectivePhase(declared:reservationEndAt:now:)`。
    /// **保留**——既有调用方与既有单测的行为必须逐字不变（尾款时间未填时新口径与它等价）。
    static func effectivePhase(
        declared: CatalogSeriesSalePhase?,
        reservationEndAt: Date?,
        now: Date
    ) -> CatalogSeriesSalePhase? {
        effectivePhase(declared: declared,
                       reservationEndAt: reservationEndAt,
                       balanceDueKind: nil,
                       balanceDueAt: nil,
                       now: now)
    }

    /// `CatalogSeries` 便捷入口（唯一读法，视图别再自己拼字段）
    static func effectivePhase(of series: CatalogSeries, now: Date) -> CatalogSeriesSalePhase? {
        effectivePhase(declared: series.salePhase,
                       reservationEndAt: series.reservationEndAt,
                       balanceDueKind: series.balanceDueKind,
                       balanceDueAt: series.balanceDueAt,
                       now: now)
    }

    /// 是否已经因为「过了预约结束时间 / 到了尾款时间」而自动流转 —— 表单用它给一条提示，
    /// 说明为什么刚填的「预约中」保存后会显示成别的阶段。
    ///
    /// **只提示、不拦保存**：结束时间已过本身就是合法状态（预约刚好结束），
    /// 拦下来反而与 §二.3 的自动流转矛盾。
    static func hasAutoFlowed(
        declared: CatalogSeriesSalePhase?,
        reservationEndAt: Date?,
        balanceDueKind: CatalogBalanceDueKind?,
        balanceDueAt: Date?,
        now: Date
    ) -> Bool {
        guard let declared, declared == .reservationActive || declared == .reservationEnded else {
            return false
        }
        return effectivePhase(declared: declared,
                              reservationEndAt: reservationEndAt,
                              balanceDueKind: balanceDueKind,
                              balanceDueAt: balanceDueAt,
                              now: now) != declared
    }

    /// 旧签名（不涉及尾款时间）
    static func hasAutoFlowed(
        declared: CatalogSeriesSalePhase?,
        reservationEndAt: Date?,
        now: Date
    ) -> Bool {
        hasAutoFlowed(declared: declared,
                      reservationEndAt: reservationEndAt,
                      balanceDueKind: nil,
                      balanceDueAt: nil,
                      now: now)
    }

    /// `CatalogSeries` 便捷入口
    static func hasAutoFlowed(of series: CatalogSeries, now: Date) -> Bool {
        hasAutoFlowed(declared: series.salePhase,
                      reservationEndAt: series.reservationEndAt,
                      balanceDueKind: series.balanceDueKind,
                      balanceDueAt: series.balanceDueAt,
                      now: now)
    }

    // MARK: 加购引导（§二 业务背景 + 用户裁定）

    /// 加购时是否**主推全款**。
    ///
    /// - 预约已结束 / 现货 → `true`：全款作为主按钮，`定金 + 尾款` 收进「其他记账方式」。
    /// - **尾款中 → `false`**（2026-09-24 需求三）：这一阶段的业务动作就是「补尾款」，
    ///   默认引导「加入心愿尾款（定金 + 尾款）」，与预约中一致。
    /// - 预约中 / 未声明 → `false`。
    ///
    /// ⚠️ 这是**引导**口径，不是能力门禁：即便返回 `true`，也必须保留
    /// 「加入心愿尾款（定金 + 尾款）」入口（用户 2026-09-23 拍板）。
    /// 任何「结束后禁止记定金尾款」的实现都偏离了这条裁定。
    static func prefersFullPayment(_ phase: CatalogSeriesSalePhase?) -> Bool {
        switch phase {
        case .reservationEnded, .inStock: return true
        case .reservationActive, .balancePending, .none: return false
        }
    }

    // MARK: 表单口径（§二.2 + 需求四）

    /// 该阶段是否需要（并显示）「预约结束时间」输入框：
    /// 只有「预约中」需要，其余阶段隐藏。
    static func requiresReservationEndAt(_ phase: CatalogSeriesSalePhase?) -> Bool {
        phase == .reservationActive
    }

    /// 该阶段是否显示「尾款时间」输入项。
    ///
    /// - 预约中：需求四要求在这里可填（**非必填**，不填 = 不启用尾款时间）；
    /// - 尾款中：允许修正已经宣布的时间（到点自动流转后，运营常需要补一句实际安排）。
    ///
    /// 「预约已结束 / 现货」不显示：前者的尾款时间还没确定，后者已经收完尾款。
    /// 不显示 **不等于清除** —— 保存时只写这三个字段里的新值，隐藏阶段原样保留（事实保留）。
    static func showsBalanceDueInput(_ phase: CatalogSeriesSalePhase?) -> Bool {
        phase == .reservationActive || phase == .balancePending
    }

    /// 「尾款中」的**出口**说明：本阶段的退出条件是**运营声明**（改成「现货」），
    /// 不由时间自动判定 —— 「尾款是否收齐」在现有数据模型里没有可判定的依据，
    /// 硬造一个（例如「尾款事件清零」）会把「有笔尾款还没记」误判成「收齐了」。
    static func balancePhaseExitsByDeclarationOnly(_ phase: CatalogSeriesSalePhase?) -> Bool {
        phase == .balancePending
    }
}
