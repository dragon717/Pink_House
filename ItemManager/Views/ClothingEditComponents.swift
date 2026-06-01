//
//  ClothingEditComponents.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
//

import SwiftUI
import Foundation

// MARK: - Data Models

struct AccessoryItemData: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String
    var price: Double
    var deposit: Double
    var balance: Double
    var imagePaths: [String]? = nil
}

// MARK: - Price Helper

final class ClothingPriceHelper {
    static let shared = ClothingPriceHelper()
    
    private init() {}
    
    func calculateTotal(deposit: Double, balance: Double) -> Double {
        if deposit > 0 && balance > 0 {
            return deposit + balance
        }
        return 0
    }
    
    func validatePrices(total: Double, deposit: Double, balance: Double) -> Bool {
        if deposit > 0 && balance > 0 {
            return abs(total - (deposit + balance)) < 0.01
        }
        return true
    }
}

// MARK: - Reusable Components

struct PriceRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var value: Double
    
    var body: some View {
        HStack {
            if let subtitle = subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.appLocalized)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Text(subtitle.appLocalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                }
            } else {
                Text(title.appLocalized)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
            Spacer()
            TextField("0", value: Binding<Double?>(
                get: { value == 0 ? nil : value },
                set: { value = $0 ?? 0 }
            ), format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("¥")
                .foregroundStyle(.secondary)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
        }
    }
}

struct CurrencyPriceRow: View {
    var title: String
    @Binding var cnyValue: Double
    @Binding var jpyValue: Double
    @Binding var currency: ClothingPriceCurrency
    var exchangeRateJPY: Double

    private var activeValue: Binding<Double> {
        Binding(
            get: {
                switch currency {
                case .cny: return cnyValue
                case .jpy: return jpyValue
                }
            },
            set: { newValue in
                let safeRate = exchangeRateJPY > 0 ? exchangeRateJPY : CurrencyExchangeRateService.defaultJPYRate
                switch currency {
                case .cny:
                    cnyValue = newValue
                    jpyValue = newValue * safeRate
                case .jpy:
                    jpyValue = newValue
                    cnyValue = newValue / safeRate
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title.appLocalized)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Spacer()
                Picker(title.appLocalized, selection: $currency) {
                    Text("人民币".appLocalized)
                        .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                        .tag(ClothingPriceCurrency.cny)
                    Text("日元".appLocalized)
                        .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                        .tag(ClothingPriceCurrency.jpy)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 132)
            }

            HStack(spacing: 8) {
                Spacer()
                TextField("0", value: Binding<Double?>(
                    get: { activeValue.wrappedValue == 0 ? nil : activeValue.wrappedValue },
                    set: { activeValue.wrappedValue = $0 ?? 0 }
                ), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(currency.symbol)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
        }
        .onChange(of: currency) { _, newValue in
            let safeRate = exchangeRateJPY > 0 ? exchangeRateJPY : CurrencyExchangeRateService.defaultJPYRate
            switch newValue {
            case .cny:
                if cnyValue == 0, jpyValue > 0 { cnyValue = jpyValue / safeRate }
            case .jpy:
                if jpyValue == 0, cnyValue > 0 { jpyValue = cnyValue * safeRate }
            }
        }
    }
}
