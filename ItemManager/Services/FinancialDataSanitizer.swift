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

    /// 衣物单价随数量累加；附属小物已逐条录入，只计算一次。
    static func orderTotal(unitAmount: Decimal, stock quantity: Int, attachedAmount: Decimal) -> Decimal {
        money(unitAmount) * Decimal(stock(quantity)) + aggregateMoney(attachedAmount)
    }
}
