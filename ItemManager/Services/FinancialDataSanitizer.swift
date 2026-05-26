//
//  FinancialDataSanitizer.swift
//  ItemManager
//
//  Centralized guards for money and stock values stored in wardrobe models.
//

import Foundation

enum FinancialDataSanitizer {
    static let maxMoney: Decimal = 999_999_999

    static func money(_ value: Decimal) -> Decimal {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, maxMoney)
    }

    static func aggregateMoney(_ value: Decimal) -> Decimal {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }

    static func money(_ value: Double) -> Decimal {
        guard value.isFinite, value > 0 else { return 0 }
        return money(Decimal(value))
    }

    static func stock(_ value: Int) -> Int {
        min(max(value, 1), 999)
    }
}
