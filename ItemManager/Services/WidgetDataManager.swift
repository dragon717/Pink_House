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
    let totalStyleCount: Int // 新增：总款数
    let depositCount: Int // 新增：定尾计划总件数
    let depositStyleCount: Int // 新增：定尾计划总款数
    let totalPrice: Decimal
    let totalDeposit: Decimal
    let totalBalance: Decimal
    let seriesStats: [WidgetSeriesInfo]
    let monthStats: [WidgetMonthInfo]
    let recentClothings: [WidgetClothing]
    let lastUpdated: Date
    
    static let empty = WidgetData(
        totalCount: 0,
        totalStyleCount: 0,
        depositCount: 0,
        depositStyleCount: 0,
        totalPrice: 0,
        totalDeposit: 0,
        totalBalance: 0,
        seriesStats: [],
        monthStats: [],
        recentClothings: [],
        lastUpdated: Date()
    )
}

class WidgetDataManager {
    static let shared = WidgetDataManager()
    static let appGroupIdentifier = "group.bugod.ItemManager"
    private let filename = "widget_data.json"
    
    private var fileURL: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            print("WidgetDataManager: Could not find App Group container for ID: \(Self.appGroupIdentifier)")
            return nil
        }
        return container.appendingPathComponent(filename)
    }
    
    func save(data: WidgetData) {
        guard let url = fileURL else { return }
        
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url, options: .atomic)
            print("WidgetDataManager: Successfully saved data to \(url.path)")
        } catch {
            print("WidgetDataManager: Failed to save data - \(error)")
        }
    }
    
    func load() -> WidgetData {
        guard let url = fileURL else {
            print("WidgetDataManager: No file URL available")
            return .empty
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(WidgetData.self, from: data)
            print("WidgetDataManager: Successfully loaded data from \(url.path)")
            return decoded
        } catch {
            print("WidgetDataManager: Failed to load data (or file doesn't exist) - \(error)")
            return .empty
        }
    }

}
