//
//  CurrencyExchangeRateService.swift
//  ItemManager
//
//  Shared lightweight exchange-rate cache for wardrobe price conversion.
//

import Foundation
import Combine

struct CurrencyExchangeRateSnapshot: Equatable, Sendable {
    let cnyToJPYRate: Double
    let cnyToUSDRate: Double
    let updatedAt: Date
    let providerDate: String?
}

struct CurrencyExchangeRateRefreshResult: Equatable, Sendable {
    let snapshot: CurrencyExchangeRateSnapshot
    let didFetchFromNetwork: Bool
    let errorMessage: String?

    var isSuccess: Bool {
        errorMessage == nil
    }
}

enum CurrencyExchangeRateParseError: LocalizedError, Equatable, Sendable {
    case invalidPayload
    case missingRates
    case missingJPYRate
    case missingUSDRate

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "汇率接口返回格式异常"
        case .missingRates:
            return "汇率接口未返回 rates"
        case .missingJPYRate:
            return "汇率接口未返回 JPY 汇率"
        case .missingUSDRate:
            return "汇率接口未返回 USD 汇率"
        }
    }
}

@MainActor
final class CurrencyExchangeRateService: ObservableObject {
    static let shared = CurrencyExchangeRateService()
    static let defaultJPYRate: Double = 21.0
    static let defaultUSDRate: Double = 0.14

    @Published private(set) var cnyToJPYRate: Double
    @Published private(set) var cnyToUSDRate: Double
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastProviderDate: String?
    @Published private(set) var isFetching: Bool = false

    private let rateKey = "currencyExchange.cnyToJPYRate"
    private let usdRateKey = "currencyExchange.cnyToUSDRate"
    private let updatedAtKey = "currencyExchange.cnyToJPYUpdatedAt"
    private let providerDateKey = "currencyExchange.cnyRatesProviderDate"
    private let cacheTTL: TimeInterval = 6 * 60 * 60

    private init() {
        let storedJPYRate = UserDefaults.standard.double(forKey: rateKey)
        let storedUSDRate = UserDefaults.standard.double(forKey: usdRateKey)
        cnyToJPYRate = storedJPYRate > 0 ? storedJPYRate : Self.defaultJPYRate
        cnyToUSDRate = storedUSDRate > 0 ? storedUSDRate : Self.defaultUSDRate
        lastUpdatedAt = UserDefaults.standard.object(forKey: updatedAtKey) as? Date
        lastProviderDate = UserDefaults.standard.string(forKey: providerDateKey)
    }

    @discardableResult
    func refreshJPYRateIfAllowed(force: Bool = false) async -> Double {
        let result = await refreshCNYRates(force: force)
        return result.snapshot.cnyToJPYRate
    }

    @discardableResult
    func refreshCNYRates(force: Bool = false) async -> CurrencyExchangeRateRefreshResult {
        guard !isFetching else {
            return CurrencyExchangeRateRefreshResult(
                snapshot: currentSnapshot(),
                didFetchFromNetwork: false,
                errorMessage: force ? "汇率正在刷新中，请稍后再试" : nil
            )
        }

        if !force,
           let lastUpdatedAt,
           Calendar.current.isDate(lastUpdatedAt, inSameDayAs: Date()),
           Date().timeIntervalSince(lastUpdatedAt) < cacheTTL {
            return CurrencyExchangeRateRefreshResult(
                snapshot: currentSnapshot(),
                didFetchFromNetwork: false,
                errorMessage: nil
            )
        }

#if WIDGET_EXTENSION
        return CurrencyExchangeRateRefreshResult(
            snapshot: currentSnapshot(),
            didFetchFromNetwork: false,
            errorMessage: "小组件暂不刷新实时汇率"
        )
#else

        isFetching = true
        defer { isFetching = false }

        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/CNY") else {
            return CurrencyExchangeRateRefreshResult(
                snapshot: currentSnapshot(),
                didFetchFromNetwork: false,
                errorMessage: "汇率接口地址无效"
            )
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let snapshot = try Self.parseCNYRatesPayload(data, updatedAt: Date())
            apply(snapshot)
            return CurrencyExchangeRateRefreshResult(
                snapshot: snapshot,
                didFetchFromNetwork: true,
                errorMessage: nil
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("CurrencyExchangeRateService: failed to fetch CNY rates: \(message)")
            return CurrencyExchangeRateRefreshResult(
                snapshot: currentSnapshot(),
                didFetchFromNetwork: false,
                errorMessage: message
            )
        }
#endif
    }

    nonisolated static func parseCNYRatesPayload(_ data: Data, updatedAt: Date = Date()) throws -> CurrencyExchangeRateSnapshot {
        let payload: Any
        do {
            payload = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CurrencyExchangeRateParseError.invalidPayload
        }

        guard let json = payload as? [String: Any] else {
            throw CurrencyExchangeRateParseError.invalidPayload
        }

        guard let rates = json["rates"] as? [String: Any] else {
            throw CurrencyExchangeRateParseError.missingRates
        }

        guard let jpyRate = rateValue(from: rates["JPY"]) else {
            throw CurrencyExchangeRateParseError.missingJPYRate
        }

        guard let usdRate = rateValue(from: rates["USD"]) else {
            throw CurrencyExchangeRateParseError.missingUSDRate
        }

        return CurrencyExchangeRateSnapshot(
            cnyToJPYRate: jpyRate,
            cnyToUSDRate: usdRate,
            updatedAt: updatedAt,
            providerDate: json["date"] as? String
        )
    }

    private nonisolated static func rateValue(from value: Any?) -> Double? {
        if let double = value as? Double, double > 0 {
            return double
        }
        if let number = value as? NSNumber, number.doubleValue > 0 {
            return number.doubleValue
        }
        return nil
    }

    private func currentSnapshot() -> CurrencyExchangeRateSnapshot {
        CurrencyExchangeRateSnapshot(
            cnyToJPYRate: cnyToJPYRate,
            cnyToUSDRate: cnyToUSDRate,
            updatedAt: lastUpdatedAt ?? Date(),
            providerDate: lastProviderDate
        )
    }

    private func apply(_ snapshot: CurrencyExchangeRateSnapshot) {
        cnyToJPYRate = snapshot.cnyToJPYRate
        cnyToUSDRate = snapshot.cnyToUSDRate
        lastUpdatedAt = snapshot.updatedAt
        lastProviderDate = snapshot.providerDate

        UserDefaults.standard.set(snapshot.cnyToJPYRate, forKey: rateKey)
        UserDefaults.standard.set(snapshot.cnyToUSDRate, forKey: usdRateKey)
        UserDefaults.standard.set(snapshot.updatedAt, forKey: updatedAtKey)
        UserDefaults.standard.set(snapshot.providerDate, forKey: providerDateKey)
    }
}
