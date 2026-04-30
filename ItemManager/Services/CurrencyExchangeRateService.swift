//
//  CurrencyExchangeRateService.swift
//  ItemManager
//
//  Shared lightweight exchange-rate cache for wardrobe price conversion.
//

import Foundation
import Combine

@MainActor
final class CurrencyExchangeRateService: ObservableObject {
    static let shared = CurrencyExchangeRateService()
    static let defaultJPYRate: Double = 21.0

    @Published private(set) var cnyToJPYRate: Double
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isFetching: Bool = false

    private let rateKey = "currencyExchange.cnyToJPYRate"
    private let updatedAtKey = "currencyExchange.cnyToJPYUpdatedAt"
    private let cacheTTL: TimeInterval = 6 * 60 * 60

    private init() {
        let storedRate = UserDefaults.standard.double(forKey: rateKey)
        cnyToJPYRate = storedRate > 0 ? storedRate : Self.defaultJPYRate
        lastUpdatedAt = UserDefaults.standard.object(forKey: updatedAtKey) as? Date
    }

    @discardableResult
    func refreshJPYRateIfAllowed(force: Bool = false) async -> Double {
        guard !isFetching else { return cnyToJPYRate }

        if !force,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < cacheTTL {
            return cnyToJPYRate
        }

        #if WIDGET_EXTENSION
        let networkAvailable = false
        #else
        let networkAvailable = NetworkSettingsManager.shared.isNetworkAvailable()
        #endif

        guard networkAvailable else {
            return cnyToJPYRate
        }

        isFetching = true
        defer { isFetching = false }

        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/CNY") else {
            return cnyToJPYRate
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rates = json["rates"] as? [String: Double],
               let jpyRate = rates["JPY"],
               jpyRate > 0 {
                cnyToJPYRate = jpyRate
                lastUpdatedAt = Date()
                UserDefaults.standard.set(jpyRate, forKey: rateKey)
                UserDefaults.standard.set(lastUpdatedAt, forKey: updatedAtKey)
            }
        } catch {
            print("CurrencyExchangeRateService: failed to fetch CNY->JPY rate: \(error)")
        }

        return cnyToJPYRate
    }
}
