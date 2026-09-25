//
//  ShopCatalogWardrobeBalanceSync.swift
//  ItemManager
//
//  尾款阶段 → 用户衣橱条目 同步（2026-09-25 需求二/三；@MainActor）。
//
//  ── 需求原文 ──
//
//  「当运营在后台将某内容更新为尾款阶段时，用户衣橱中的对应条目需同步更新至尾款阶段。」
//
//  ── 口径（改动前先读这里） ──
//
//  1. **同步什么**：`Clothing.finalPaymentDate / finalPaymentEndDate`（尾款窗口）。
//     `Clothing` 没有「阶段」字段——用户的尾款阶段就是由「是否还有待补尾款 +
//     尾款窗口」表达的；运营侧进入「尾款中」后，窗口以系列声明为准同步过来。
//
//  2. **只动哪些记录**：带 `catalogProductID` 引用、`isDepositPlan == true`、
//     未软删、且 `isFinalPaymentPlan`（真在定金/尾款流程里）。
//     全款记录（`isFullPaymentReservation`，不生成尾款任务）与已付清记录
//     （`markFinalPaymentCompleted` 之后）一律不动。
//
//  3. **只同步「尾款中」系列**：`CatalogSeriesSalePhaseResolver.effectivePhase`
//     （读取时判定的唯一口径）为 `.balancePending` 才同步——预约中阶段的窗口
//     在加购时已按声明快照（见 DraftBuilder），运营后续微调声明也以到「尾款中」
//     这一时刻为准，避免预约期间反复改写用户记录。
//
//  4. **窗口来源唯一**：`CatalogBalanceDueApproximation.declaredWindow(of:anchor:)`
//     —— 具体时间直接用；大致时间（上旬/中旬/中下旬/下旬）按「约一个月」基准
//     估算成固定具体日期。锚点 = `series.reservationEndAt`（运营侧事实）；
//     缺锚点或缺关键词 → 跳过该条（缺依据就不猜）。
//     估算不含 `Date()` 输入 → 同一数据重算结果恒定 → 幂等，重复调用零副作用。
//
//  5. **绝不碰的东西**：金额（deposit/balance/priceTotal）、状态（isDepositPlan）、
//     用户已录入的其他字段。同步只在窗口值**确实变化**时写入，并往备注追加一条
//     留痕（同一内容不重复追加）。
//
//  6. **数据独立（2026-09-25 需求一）**：商品已被运营删除 / 下架
//     （`store.product(id:) == nil`）→ 跳过，用户记录原样保留——
//     删除发布内容不影响用户衣橱数据，同步也绝不借道改写它们。
//
//  ── 触发点 ──
//
//    · 店家上新首屏 `ShopCatalogBrowseView.task`（云同步落地之后，幂等廉价）；
//    · 运营保存系列配置后（`ShopCatalogBatchDetailView.saveSeriesConfig`，
//      发售阶段/尾款时间变更当机即生效，无需等下一轮云同步）。
//
//  ⚠️ 本类型**不持有默认 ModelContext**：context 必须由调用方显式传入
//  （视图来自 `@Environment(\.modelContext)`，测试来自内存容器）——
//  内部默认拿 `.shared` 生产容器是「单测碰用户真实数据」红线的来源，禁止。
//

import Foundation
import SwiftData

@MainActor
enum ShopCatalogWardrobeBalanceSync {

    struct Report: Equatable {
        /// 扫描到的「在尾款流程里且带 Catalog 引用」的条目数
        var checkedCount = 0
        /// 实际改写了尾款窗口的条目数
        var updatedCount = 0
    }

    /// 把「尾款中」系列的声明窗口同步进用户衣橱条目。幂等，可安全重复调用。
    @discardableResult
    static func syncIfNeeded(store: ShopCatalogStore,
                             modelContext: ModelContext,
                             now: Date = Date()) -> Report {
        var report = Report()

        let descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { clothing in
                clothing.catalogProductID != nil
                    && clothing.isDepositPlan == true
                    && clothing.deletedAt == nil
            }
        )
        let clothings = (try? modelContext.fetch(descriptor)) ?? []
        var didChange = false

        for clothing in clothings {
            // 全款（不生成任务）/ 已付清（markFinalPaymentCompleted 之后）一律不动
            guard clothing.isFinalPaymentPlan else { continue }
            report.checkedCount += 1

            // 数据独立：商品已被运营删除/下架 → 跳过，用户记录原样保留
            guard let productID = clothing.catalogProductID,
                  let product = store.product(id: productID),
                  let series = store.series(id: product.seriesID) else { continue }

            // 只有「尾款中」才同步（生效阶段 = 读取时判定的唯一口径）
            guard CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: now) == .balancePending
            else { continue }

            // 窗口来源唯一：声明直接用 / 大致估算成固定具体日期；缺依据 → 跳过
            guard let window = CatalogBalanceDueApproximation.declaredWindow(
                of: series,
                anchor: series.reservationEndAt) else { continue }

            guard clothing.finalPaymentDate != window.start
                    || clothing.finalPaymentEndDate != window.end else { continue }

            clothing.finalPaymentDate = window.start
            clothing.finalPaymentEndDate = window.end
            appendSyncNote(to: clothing, window: window)
            report.updatedCount += 1
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
        return report
    }

    // MARK: - 备注留痕

    /// 追加一条同步留痕；同一天的同一内容不重复追加（重复触发不刷屏）。
    private static func appendSyncNote(to clothing: Clothing, window: CatalogBalanceDueApproximation.Window) {
        let line = "尾款阶段同步：尾款时间更新为 \(CatalogSeriesBalanceDue.shortDateText(window.start))（\(window.basis)）"
        let existing = clothing.note
        if existing.contains(line) { return }
        clothing.note = existing.isEmpty ? line : existing + "\n" + line
    }
}
