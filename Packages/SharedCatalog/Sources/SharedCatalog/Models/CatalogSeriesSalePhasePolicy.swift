import Foundation

/// 两端共同的时间推导；不回写运营声明，不改价格或团次资料。
public nonisolated enum CatalogSeriesSalePhasePolicy {
    public static func effectivePhase(declared: CatalogSeriesSalePhase?, reservationEndAt: Date?,
                                      balanceDueKind: CatalogBalanceDueKind?, balanceDueAt: Date?,
                                      now: Date) -> CatalogSeriesSalePhase? {
        guard let declared else { return nil }
        guard declared == .reservationActive || declared == .reservationEnded else { return declared }
        if declared == .reservationActive {
            guard let end = reservationEndAt, now > end else { return .reservationActive }
        }
        if balanceDueKind == .exact, let start = balanceDueAt, now >= start { return .balancePending }
        return .reservationEnded
    }

    public static func effectivePhase(of series: CatalogSeries, now: Date) -> CatalogSeriesSalePhase? {
        if let batches = series.reservationBatches, !batches.isEmpty {
            let phases = batches.compactMap { batch in
                series.paymentSchedule(batchID: batch.id).flatMap { effectivePhase(of: $0, now: now) }
            }
            if phases.contains(.balancePending) { return .balancePending }
            if phases.contains(.reservationActive) { return .reservationActive }
            return phases.first
        }
        return effectivePhase(declared: series.salePhase, reservationEndAt: series.reservationEndAt,
                              balanceDueKind: series.balanceDueKind, balanceDueAt: series.balanceDueAt, now: now)
    }

    /// 精确订阅阶段可能变化的时刻，不用每秒刷新整个工作区。
    /// 预约结束沿用严格超过的兼容边界；尾款开始含边界时刻。
    public static func transitionDates(of series: CatalogSeries) -> [Date] {
        guard series.salePhase == .reservationActive || series.salePhase == .reservationEnded else { return [] }
        if let batches = series.reservationBatches, !batches.isEmpty {
            return Array(Set(batches.flatMap { batch in
                series.paymentSchedule(batchID: batch.id).map { transitionDates(of: $0) } ?? []
            })).sorted()
        }
        var dates: [Date] = []
        if series.salePhase == .reservationActive, let end = series.reservationEndAt {
            dates.append(end.addingTimeInterval(0.001))
        }
        if series.balanceDueKind == .exact, let start = series.balanceDueAt { dates.append(start) }
        return Array(Set(dates)).sorted()
    }
}
