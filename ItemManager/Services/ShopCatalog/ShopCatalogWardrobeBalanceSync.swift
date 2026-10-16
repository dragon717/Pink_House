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
//  3. 已明确选择团次的记录随该团声明更新，不等待系列进入尾款阶段。
//     未分团系列仍只在 `.balancePending` 同步，保留原有规则。
//
//  4. **窗口来源唯一**：`CatalogBalanceDueApproximation.declaredWindow(of:anchor:)`
//     —— 具体时间直接用；大致时间（上旬/中旬/中下旬/下旬）按「约一个月」基准
//     估算成固定具体日期。锚点 = `series.reservationEndAt`（运营侧事实）；
//     缺锚点或缺关键词 → 跳过该条（缺依据就不猜）。
//     估算不含 `Date()` 输入 → 同一数据重算结果恒定 → 幂等，重复调用零副作用。
//
//  5. **绝不碰的东西**：金额（deposit/balance/priceTotal）、状态（isDepositPlan）、
//     用户已录入的其他字段。同步只在窗口值**确实变化**时写入，备注始终保留用户原文。
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
                  let series = store.seriesForPurchase(id: product.seriesID) else { continue }

            // 多团记录只读取所属团次；旧记录未选团不能套用任意一团的时间。
            guard let schedule = series.paymentSchedule(batchID: clothing.catalogReservationBatchID)
            else { continue }
            // 已选团次的待付记录应随该团声明及时更新，无需等系列进入尾款阶段。
            guard !(series.reservationBatches ?? []).isEmpty ||
                    CatalogSeriesSalePhaseResolver.effectivePhase(of: schedule, now: now) == .balancePending
            else { continue }

            // 窗口来源唯一：声明直接用 / 大致估算成固定具体日期；缺依据 → 跳过
            let batchEventAnchor: Date? = (series.reservationBatches ?? []).isEmpty ? nil
                : (clothing.catalogSaleEventID.flatMap { store.saleEvent(id: $0)?.endAt }
                    ?? store.priceArchive(forProduct: productID).reservation?.endAt)
            guard let window = CatalogBalanceDueApproximation.declaredWindow(
                of: schedule,
                anchor: schedule.reservationEndAt ?? batchEventAnchor) else { continue }

            guard clothing.finalPaymentDate != window.start
                    || clothing.finalPaymentEndDate != window.end else { continue }

            clothing.finalPaymentDate = window.start
            clothing.finalPaymentEndDate = window.end
            report.updatedCount += 1
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
        return report
    }

}
