import XCTest
@testable import ItemManager

@MainActor
final class CurrencyExchangeRateServiceTests: XCTestCase {
    func testParseCNYRatesPayloadReturnsJPYAndUSD() throws {
        let data = Data("""
        {
            "date": "2026-05-05",
            "rates": {
                "JPY": 22.9876,
                "USD": 0.1389
            }
        }
        """.utf8)
        let updatedAt = Date(timeIntervalSince1970: 1_778_000_000)

        let snapshot = try CurrencyExchangeRateService.parseCNYRatesPayload(data, updatedAt: updatedAt)

        XCTAssertEqual(snapshot.cnyToJPYRate, 22.9876)
        XCTAssertEqual(snapshot.cnyToUSDRate, 0.1389)
        XCTAssertEqual(snapshot.updatedAt, updatedAt)
        XCTAssertEqual(snapshot.providerDate, "2026-05-05")
    }

    func testParseCNYRatesPayloadThrowsWhenJPYMissing() throws {
        let data = Data("""
        {
            "rates": {
                "USD": 0.1389
            }
        }
        """.utf8)

        XCTAssertThrowsError(try CurrencyExchangeRateService.parseCNYRatesPayload(data)) { error in
            XCTAssertEqual(error as? CurrencyExchangeRateParseError, .missingJPYRate)
        }
    }

    func testParseCNYRatesPayloadThrowsWhenUSDMissing() throws {
        let data = Data("""
        {
            "rates": {
                "JPY": 22.9876
            }
        }
        """.utf8)

        XCTAssertThrowsError(try CurrencyExchangeRateService.parseCNYRatesPayload(data)) { error in
            XCTAssertEqual(error as? CurrencyExchangeRateParseError, .missingUSDRate)
        }
    }

    func testParseCNYRatesPayloadThrowsForInvalidJSON() throws {
        let data = Data("not json".utf8)

        XCTAssertThrowsError(try CurrencyExchangeRateService.parseCNYRatesPayload(data)) { error in
            XCTAssertEqual(error as? CurrencyExchangeRateParseError, .invalidPayload)
        }
    }
}
