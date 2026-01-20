//
//  WidgetDataManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import Foundation

// DTOs for Widget
struct WidgetClothing: Codable, Identifiable {
    let id: UUID
    let name: String
    let price: Decimal
    let stock: Int
    let imagePath: String?
}

struct WidgetSeriesInfo: Codable, Identifiable {
    var id: UUID { UUID() } // Dynamic ID for Identifiable conformance
    let name: String
    let count: Int
    let totalBalance: Decimal
}

struct WidgetMonthInfo: Codable, Identifiable {
    var id: String { "\(year)-\(month)" }
    let month: Int
    let year: Int
    let count: Int
    let totalBalance: Decimal
}

struct WidgetData: Codable {
    let totalCount: Int
    let totalPrice: Decimal
    let seriesStats: [WidgetSeriesInfo]
    let monthStats: [WidgetMonthInfo]
    let recentClothings: [WidgetClothing]
    let lastUpdated: Date
    
    static let empty = WidgetData(
        totalCount: 0,
        totalPrice: 0,
        seriesStats: [],
        monthStats: [],
        recentClothings: [],
        lastUpdated: Date()
    )
}

class WidgetDataManager {
    static let shared = WidgetDataManager()
    static let appGroupIdentifier = "group.bugod.ItemManager"
    static let dataKey = "widget_data"
    
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupIdentifier)
    }
    
    func save(data: WidgetData) {
        if let encoded = try? JSONEncoder().encode(data) {
            userDefaults?.set(encoded, forKey: Self.dataKey)
            print("WidgetDataManager: Saved data to App Group \(Self.appGroupIdentifier)")
        } else {
            print("WidgetDataManager: Failed to encode data")
        }
    }
    
    func load() -> WidgetData {
        guard let data = userDefaults?.data(forKey: Self.dataKey),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return .empty
        }
        return decoded
    }
}
