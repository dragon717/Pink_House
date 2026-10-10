import Foundation
import SharedCatalog

/// 阶段声明只控制 salePhase，时间字段独立保存，可用于自动推导阶段。
public struct OpsSeriesSalePhaseInput {
    public var phase: CatalogSeriesSalePhase?
    public var reservationStartAt: Date?
    public var reservationEndAt: Date?
    public var balanceDueKind: CatalogBalanceDueKind?
    public var balanceDueText: String?
    public var balanceDueAt: Date?
    public var balanceDueEndAt: Date?

    public init(declaresPhase: Bool, phase: CatalogSeriesSalePhase,
                reservationStartAt: Date?, reservationEndAt: Date?,
                balanceDueKind: CatalogBalanceDueKind, balanceDueText: String,
                balanceDueAt: Date?, balanceDueEndAt: Date?) {
        self.phase = declaresPhase ? phase : nil
        self.reservationStartAt = reservationStartAt
        self.reservationEndAt = reservationEndAt
        let text = balanceDueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if balanceDueKind == .exact, balanceDueAt != nil || balanceDueEndAt != nil {
            self.balanceDueKind = .exact
            self.balanceDueAt = balanceDueAt
            self.balanceDueEndAt = balanceDueEndAt
        } else if balanceDueKind == .approximate, !text.isEmpty {
            self.balanceDueKind = .approximate
            self.balanceDueText = text
        }
    }
}
