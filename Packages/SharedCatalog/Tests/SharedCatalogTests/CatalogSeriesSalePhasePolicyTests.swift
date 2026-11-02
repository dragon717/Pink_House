import XCTest
@testable import SharedCatalog

final class CatalogSeriesSalePhasePolicyTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)
    private var start: Date { end.addingTimeInterval(3600) }
    private func series(kind: CatalogBalanceDueKind? = .exact) -> CatalogSeries {
        CatalogSeries(id: "series", shopID: "shop", name: "系列", salePhase: .reservationActive,
                      reservationEndAt: end, balanceDueKind: kind, balanceDueAt: start)
    }

    func testReservationEndsThenWaitsForScheduledBalanceStart() {
        let value = series()
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: end.addingTimeInterval(-1)), .reservationActive)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: end), .reservationActive)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: end.addingTimeInterval(0.001)), .reservationEnded)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start.addingTimeInterval(-0.001)), .reservationEnded)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start), .balancePending)
    }

    func testMissingOrApproximateBalanceDoesNotStartCollection() {
        for kind in [nil, .approximate] as [CatalogBalanceDueKind?] {
            var value = series(kind: kind)
            value.balanceDueText = "圣诞节前"
            XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start.addingTimeInterval(100)), .reservationEnded)
            XCTAssertEqual(CatalogSeriesSalePhasePolicy.transitionDates(of: value), [end.addingTimeInterval(0.001)])
        }
        var exactWithoutDate = series()
        exactWithoutDate.balanceDueAt = nil
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: exactWithoutDate, now: start), .reservationEnded)
    }

    func testEndedDeclarationAlsoAdvancesAtExactStart() {
        var value = series()
        value.salePhase = .reservationEnded
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start), .balancePending)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.transitionDates(of: value), [start])
    }

    func testExplicitBalanceAndStockAreNotOverwrittenByDates() {
        for phase in [CatalogSeriesSalePhase.balancePending, .inStock] {
            var value = series()
            value.salePhase = phase
            XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: end.addingTimeInterval(-100)), phase)
            XCTAssertTrue(CatalogSeriesSalePhasePolicy.transitionDates(of: value).isEmpty)
        }
    }

    func testUndeclaredAndMissingReservationEndKeepExistingContracts() {
        var value = series()
        value.salePhase = nil
        XCTAssertNil(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start))
        value.salePhase = .reservationActive
        value.reservationEndAt = nil
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start), .reservationActive)
    }

    func testEachBatchUsesItsOwnDatesAndDoesNotBorrowAnotherBatch() {
        var value = series()
        value.reservationBatches = [
            CatalogReservationBatch(id: "first", name: "先行团", reservationEndAt: end,
                balanceDueKind: .approximate, balanceDueText: "圣诞节前"),
            CatalogReservationBatch(id: "second", name: "一团", reservationEndAt: end.addingTimeInterval(600),
                balanceDueKind: .exact, balanceDueAt: start),
        ]
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: end.addingTimeInterval(1)), .reservationActive)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: end.addingTimeInterval(601)), .reservationEnded)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start), .balancePending)
        let first = value.paymentSchedule(batchID: "first")!
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.effectivePhase(of: first, now: start), .reservationEnded)
        XCTAssertEqual(CatalogSeriesSalePhasePolicy.transitionDates(of: value), [end.addingTimeInterval(0.001), end.addingTimeInterval(600.001), start])
    }

    func testResolvingDoesNotRewriteStoredPhaseDatesPricesOrBatches() {
        let value = series()
        let original = value
        _ = CatalogSeriesSalePhasePolicy.effectivePhase(of: value, now: start)
        XCTAssertEqual(value, original)
        XCTAssertEqual(value.salePhase, .reservationActive)
    }
}
