//
//  ShopCatalogSeriesSalePhase.swift
//  ItemManager
//
//  系列「发售阶段」口径（2026-09-23 需求二，nonisolated 可单测）。
//
//  需求原文要点：
//    §二.1 基础信息处新增「发售阶段」：预约中 / 预约已结束（或 现货）。
//    §二.2 选「预约中」必须填「预约结束时间」；选「预约已结束」隐藏该输入框。
//    §二.3 「系统需增加定时任务或触发机制：一旦当前时间超过了设定的『预约结束时间』，
//           系统自动将该系列的『发售阶段』变更为 预约已结束」。
//    §二.4 **数据保留（最重要）**：预约结束后，预约价 / 定金 / 尾款 / 现货价必须完全保留，
//           不清空、不隐藏；用户仍能看到原预约价，只是不再拿它做定金 + 尾款的分期。
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
//  读取时判定的真相来源只有一个：`声明值 + 预约结束时间 + 当前时间`。
//  不可能出现「存储说预约中、展示说已结束」的不一致，也不需要任何后台调度。
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

    // MARK: 生效阶段（§二.3 自动流转）

    /// 生效阶段 = 声明值 + 过期自动流转。
    ///
    /// - 返回 `nil`：该系列**没有声明**发售阶段（旧数据 / 运营未填）
    ///   → 调用方沿用既有推导，绝不凭空替运营做一个决定。
    /// - `.reservationActive` 且当前时间已越过 `reservationEndAt` → `.reservationEnded`
    ///   （这就是 §二.3 要求的「自动变更」，效果等价且不会漂移）。
    /// - 未填结束时间 → 保持 `.reservationActive`（缺依据就不猜）。
    /// - `.reservationEnded` / `.inStock` 不受时间影响，原样返回。
    static func effectivePhase(
        declared: CatalogSeriesSalePhase?,
        reservationEndAt: Date?,
        now: Date
    ) -> CatalogSeriesSalePhase? {
        guard let declared else { return nil }
        guard declared == .reservationActive else { return declared }
        guard let end = reservationEndAt else { return declared }
        return now > end ? .reservationEnded : .reservationActive
    }

    /// `CatalogSeries` 便捷入口（唯一读法，视图别再自己写 `if now > end`）
    static func effectivePhase(of series: CatalogSeries, now: Date) -> CatalogSeriesSalePhase? {
        effectivePhase(declared: series.salePhase,
                       reservationEndAt: series.reservationEndAt,
                       now: now)
    }

    /// 是否已经因为「过了预约结束时间」而自动流转 —— 表单用它给一条提示，
    /// 说明为什么刚填的「预约中」保存后会显示成「预约已结束」。
    ///
    /// **只提示、不拦保存**：结束时间已过本身就是合法状态（预约刚好结束），
    /// 拦下来反而与 §二.3 的自动流转矛盾。
    static func hasAutoFlowed(
        declared: CatalogSeriesSalePhase?,
        reservationEndAt: Date?,
        now: Date
    ) -> Bool {
        declared == .reservationActive
            && reservationEndAt.map { now > $0 } == true
    }

    // MARK: 加购引导（§二 业务背景 + 用户裁定）

    /// 加购时是否**主推全款**。
    ///
    /// - 预约已结束 / 现货 → `true`：全款作为主按钮，`定金 + 尾款` 收进「其他记账方式」。
    /// - 预约中 / 未声明 → `false`：定金与全款并列。
    ///
    /// ⚠️ 这是**引导**口径，不是能力门禁：即便返回 `true`，也必须保留
    /// 「加入心愿尾款（定金 + 尾款）」入口（用户 2026-09-23 拍板）。
    /// 任何「结束后禁止记定金尾款」的实现都偏离了这条裁定。
    static func prefersFullPayment(_ phase: CatalogSeriesSalePhase?) -> Bool {
        switch phase {
        case .reservationEnded, .inStock: return true
        case .reservationActive, .none: return false
        }
    }

    // MARK: 表单口径（§二.2）

    /// 该阶段是否需要（并显示）「预约结束时间」输入框：
    /// 只有「预约中」需要，其余阶段隐藏。
    static func requiresReservationEndAt(_ phase: CatalogSeriesSalePhase?) -> Bool {
        phase == .reservationActive
    }
}
