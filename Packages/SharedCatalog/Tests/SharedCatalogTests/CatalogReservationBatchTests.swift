import XCTest
@testable import SharedCatalog

final class CatalogReservationBatchTests: XCTestCase {
    func testLegacySeriesDecodesWithoutBatches() throws {
        let data = Data(#"{"id":"series","shopID":"shop","name":"旧系列"}"#.utf8)
        let series = try JSONDecoder().decode(CatalogSeries.self, from: data)
        XCTAssertNil(series.reservationBatches)
        XCTAssertEqual(series.paymentSchedule(batchID: nil), series)
    }

    func testBatchesRoundTripAndRequireExplicitSelection() throws {
        let first = CatalogReservationBatch(id: "first", name: "先行团", balanceDueKind: .exact,
                                            balanceDueAt: Date(timeIntervalSince1970: 100))
        let second = CatalogReservationBatch(id: "second", name: "二团", balanceDueKind: .exact,
                                             balanceDueAt: Date(timeIntervalSince1970: 200))
        let series = CatalogSeries(id: "series", shopID: "shop", name: "分团系列",
                                   reservationBatches: [first, second])
        let decoded = try JSONDecoder().decode(CatalogSeries.self, from: JSONEncoder().encode(series))
        XCTAssertEqual(decoded, series)
        XCTAssertNil(decoded.paymentSchedule(batchID: nil))
        XCTAssertNil(decoded.paymentSchedule(batchID: "missing"))
        XCTAssertEqual(decoded.paymentSchedule(batchID: "second")?.balanceDueAt, second.balanceDueAt)
    }

    func testSingleBatchCanBeResolvedButDoesNotInheritCommonDueDate() {
        let series = CatalogSeries(id: "series", shopID: "shop", name: "单团",
            balanceDueKind: .exact, balanceDueAt: Date(timeIntervalSince1970: 100),
            reservationBatches: [CatalogReservationBatch(id: "first", name: "一团")])
        XCTAssertEqual(series.reservationBatch(id: nil)?.id, "first")
        XCTAssertNil(series.paymentSchedule(batchID: nil)?.balanceDueAt)
        XCTAssertNil(series.paymentSchedule(batchID: "deleted"))
    }

    func testValidationRejectsDuplicateNamesAndInvertedDates() {
        let first = CatalogReservationBatch(id: "first", name: "一团")
        let duplicate = CatalogReservationBatch(id: "other", name: " 一团 ")
        XCTAssertNotNil(CatalogReservationBatch.validationError(in: [first, duplicate]))
        let invalid = CatalogReservationBatch(name: "二团", balanceDueKind: .exact,
            balanceDueAt: Date(timeIntervalSince1970: 200), balanceDueEndAt: Date(timeIntervalSince1970: 100))
        XCTAssertNotNil(CatalogReservationBatch.validationError(in: [invalid]))
        XCTAssertNil(CatalogReservationBatch.validationError(in: [first]))
    }

    func testNormalizationClearsInactiveFieldsAndKeepsID() {
        let batch = CatalogReservationBatch(id: "stable", name: " 一团 ", balanceDueKind: .approximate,
            balanceDueText: " 11月上旬 ", balanceDueAt: Date())
        XCTAssertEqual(batch.normalized.name, "一团")
        XCTAssertEqual(batch.normalized.balanceDueText, "11月上旬")
        XCTAssertNil(batch.normalized.balanceDueAt)
        XCTAssertEqual(batch.normalized.id, "stable")
    }
}
