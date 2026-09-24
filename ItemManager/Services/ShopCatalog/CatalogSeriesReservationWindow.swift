//
//  CatalogSeriesReservationWindow.swift
//  ItemManager
//
//  系列「预约期」的唯一口径（2026-09-24 需求五）。
//
//  ── 需求原文 ──
//
//  「在预约功能中，『预约中』和『尾款中』这两个状态都需要同时包含开始时间和结束时间，
//    不能只提供开始时间。」
//
//  原先「预约中」只有 `reservationEndAt` 一个点（只写了什么时候结束）。
//  本模块补上 `reservationStartAt`，把预约变成一个**区间**，与尾款期（见
//  `CatalogSeriesBalanceDue`）对称。
//
//  ── 三条口径 ──
//
//  1. **开始时间选填、结束时间必填**（预约中）。结束时间是自动流转 `预约中 → 预约已结束`
//     的唯一依据，缺了它这个阶段就永远出不去；开始时间只用于展示与区间校验，
//     强行必填会逼运营去猜一个记不清的日子 —— 缺依据就不猜，是全项目一贯口径。
//  2. **不新增「预约未开始」阶段**：开始时间在将来时，生效阶段仍是「预约中」。
//     加一个阶段要动 `allCases`、动既有持久化 enum 的语义、动所有 switch，
//     而需求只要求「同时能填开始与结束」，没有要求新状态。
//  3. **开始时间不参与任何自动流转**：只有结束时间驱动流转（既有行为不变）。
//     开始时间用于展示（「预约期：3-01 — 3-31」）与「开始时间不得晚于结束时间」的校验。
//
//  ── 隔离约定 ──
//
//  纯逻辑（校验 / 展示 / 区间判定）是 `nonisolated`，可单测；
//  依赖 `LanguageManager.shared.locale` 的前缀文案放 `@MainActor` 扩展。
//

import Foundation

nonisolated enum CatalogSeriesReservationWindow {

    // MARK: - 校验（表单唯一入口）

    /// 校验预约期。返回 `nil` = 通过；否则返回**可直接显示**的中文错误文案。
    ///
    /// 规则：
    ///   · 开始时间未填 → 通过（选填；「未声明」是合法状态）；
    ///   · 两者都有且 `start > end` → 报错。
    ///     **相等放行**：同一天的 00:00 开、00:00 结是运营的真实写法，
    ///     从这里拦下来只会制造无意义的摩擦。
    static func validationErrorText(start: Date?, end: Date?) -> String? {
        guard let start, let end else { return nil }
        if start > end {
            return "预约开始时间不能晚于预约结束时间（预约结束：\(shortDate(end))）"
        }
        return nil
    }

    // MARK: - 展示

    /// 区间文本：`2026-03-01 — 2026-03-31`。
    /// 只有结束（存量数据形态）→ 只显示结束，**不补一个假的开始**。
    static func windowText(start: Date?, end: Date?) -> String? {
        switch (start, end) {
        case let (start?, end?):
            return "\(shortDate(start)) — \(shortDate(end))"
        case let (start?, nil):
            return shortDate(start)
        case let (nil, end?):
            return shortDate(end)
        case (nil, nil):
            return nil
        }
    }

    // MARK: - 区间判定（只用于提示，不驱动流转）

    /// 预约是否已经开始。**未填开始时间 → true**（缺依据不猜，不能凭空说「还没开始」）
    static func hasStarted(start: Date?, now: Date) -> Bool {
        guard let start else { return true }
        return now >= start
    }

    /// 预约窗口是否还开放。**未填结束时间 → true**（同上理由）
    static func isOpen(end: Date?, now: Date) -> Bool {
        guard let end else { return true }
        return now <= end
    }

    /// 短日期（与 `CatalogSeriesBalanceDue.shortDateText` 同一模板，两处必须一致）
    private static func shortDate(_ date: Date) -> String {
        CatalogSeriesBalanceDue.shortDateText(date)
    }
}

// MARK: - 系列便捷入口

extension CatalogSeriesReservationWindow {

    /// 预约期区间文本（未填 → nil）
    static func windowText(of series: CatalogSeries) -> String? {
        windowText(start: series.reservationStartAt, end: series.reservationEndAt)
    }
}

// MARK: - 文案（跟随默认 MainActor 隔离，同 `CatalogSeriesBalanceDue` 的写法）

extension CatalogSeriesReservationWindow {

    /// 「预约期：2026-03-01 — 2026-03-31」整行文案；未填 → `nil`
    static func displayText(of series: CatalogSeries) -> String? {
        windowText(of: series).map { "预约期：".appLocalized + $0 }
    }
}
