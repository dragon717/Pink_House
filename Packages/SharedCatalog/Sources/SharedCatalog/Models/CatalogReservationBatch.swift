import Foundation

/// 同一系列的预约团次。每团独立声明尾款期；不复用运营录入批次或再贩销售记录。
public struct CatalogReservationBatch: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var reservationEndAt: Date?
    public var balanceDueKind: CatalogBalanceDueKind?
    public var balanceDueText: String?
    public var balanceDueEndText: String?
    public var balanceDueAt: Date?
    public var balanceDueEndAt: Date?
    /// 大致时间最近一次录入的基准，仅用于给省略年份的月份固定年份。
    /// 不作为预约结束或具体尾款时间；旧数据缺键仍可解码。
    public var balanceDueReferenceAt: Date?

    public init(id: String = UUID().uuidString, name: String,
                reservationEndAt: Date? = nil,
                balanceDueKind: CatalogBalanceDueKind? = nil,
                balanceDueText: String? = nil, balanceDueEndText: String? = nil,
                balanceDueAt: Date? = nil, balanceDueEndAt: Date? = nil,
                balanceDueReferenceAt: Date? = nil) {
        self.id = id
        self.name = name
        self.reservationEndAt = reservationEndAt
        self.balanceDueKind = balanceDueKind
        self.balanceDueText = balanceDueText
        self.balanceDueEndText = balanceDueEndText
        self.balanceDueAt = balanceDueAt
        self.balanceDueEndAt = balanceDueEndAt
        self.balanceDueReferenceAt = balanceDueReferenceAt
    }

    public func estimatedWindow(anchor: Date? = nil,
                                calendar: Calendar = .current) -> CatalogBalanceDueEstimate.Window? {
        CatalogBalanceDueEstimate.declaredWindow(kind: balanceDueKind,
            text: CatalogBalanceDueEstimate.yearQualifiedText(balanceDueText,
                reference: balanceDueReferenceAt, calendar: calendar),
            endText: CatalogBalanceDueEstimate.yearQualifiedText(balanceDueEndText,
                reference: balanceDueReferenceAt, calendar: calendar),
            at: balanceDueAt, endAt: balanceDueEndAt,
            anchor: reservationEndAt ?? anchor, calendar: calendar)
    }

    public var normalized: Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        func text(_ value: String?) -> String? {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        result.balanceDueText = balanceDueKind == .approximate ? text(balanceDueText) : nil
        result.balanceDueEndText = balanceDueKind == .approximate ? text(balanceDueEndText) : nil
        result.balanceDueAt = balanceDueKind == .exact ? balanceDueAt : nil
        result.balanceDueEndAt = balanceDueKind == .exact ? balanceDueEndAt : nil
        return result
    }

    /// iOS 与运营端共享校验，未公布时间可以留空。
    public static func validationError(in batches: [Self]) -> String? {
        var names = Set<String>()
        var ids = Set<String>()
        for raw in batches {
            let batch = raw.normalized
            if batch.name.isEmpty { return "请填写团次名称（如先行团、一团、二团）" }
            if !names.insert(batch.name).inserted { return "团次名称不能重复：\(batch.name)" }
            if batch.id.isEmpty || !ids.insert(batch.id).inserted { return "团次标识重复，请重新添加团次" }
            switch batch.balanceDueKind {
            case .exact:
                guard let start = batch.balanceDueAt else { return "\(batch.name)：请填写尾款开始时间" }
                if let end = batch.balanceDueEndAt, end < start {
                    return "\(batch.name)：尾款结束不能早于开始时间"
                }
                if let reservationEnd = batch.reservationEndAt, start <= reservationEnd {
                    return "\(batch.name)：尾款时间必须晚于该团预约结束时间"
                }
            case .approximate:
                guard let text = batch.balanceDueText else { return "\(batch.name)：请填写大致尾款时间" }
                if text.count > 30 || (batch.balanceDueEndText?.count ?? 0) > 30 {
                    return "\(batch.name)：大致尾款时间请控制在 30 字以内"
                }
            case .none: break
            }
        }
        return nil
    }
}

extension CatalogSeries {
    /// 多团必须明确选择；只有一团时可直接确定归属。无效 ID 不退回其它团。
    public func reservationBatch(id: String?) -> CatalogReservationBatch? {
        let batches = reservationBatches ?? []
        if let id { return batches.first { $0.id == id } }
        return batches.count == 1 ? batches[0] : nil
    }

    /// 把所选团的声明交给既有尾款计算 / 阶段逻辑。缺团时不使用系列共用日期冒充。
    public func paymentSchedule(batchID: String?) -> CatalogSeries? {
        guard !(reservationBatches ?? []).isEmpty else { return batchID == nil ? self : nil }
        guard let batch = reservationBatch(id: batchID) else { return nil }
        var result = self
        result.reservationBatches = nil
        result.reservationEndAt = batch.reservationEndAt ?? reservationEndAt
        result.balanceDueKind = batch.balanceDueKind
        result.balanceDueText = CatalogBalanceDueEstimate.yearQualifiedText(
            batch.balanceDueText, reference: batch.balanceDueReferenceAt)
        result.balanceDueEndText = CatalogBalanceDueEstimate.yearQualifiedText(
            batch.balanceDueEndText, reference: batch.balanceDueReferenceAt)
        result.balanceDueAt = batch.balanceDueAt
        result.balanceDueEndAt = batch.balanceDueEndAt
        return result
    }
}
