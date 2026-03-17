//
//  WidgetDataManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
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
    let totalDeposit: Decimal
}

struct WidgetMonthInfo: Codable, Identifiable {
    var id: String { "\(year)-\(month)" }
    let month: Int
    let year: Int
    let count: Int
    let totalBalance: Decimal
    let totalDeposit: Decimal
}

struct WidgetData: Codable {
    let totalCount: Int
    let totalStyleCount: Int // 新增：总款数
    let depositCount: Int // 新增：心愿尾款总件数
    let depositStyleCount: Int // 新增：心愿尾款总款数
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
    static let appGroupIdentifier = "group.bugod2.ItemManager"
    private let filename = "widget_data.json"
    private let imagesDirectoryName = "WidgetImages"
    
    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
    }
    
    private var fileURL: URL? {
        containerURL?.appendingPathComponent(filename)
    }
    
    var widgetImagesDirectory: URL? {
        guard let container = containerURL else { return nil }
        let dir = container.appendingPathComponent(imagesDirectoryName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func imageURL(for path: String) -> URL? {
        return widgetImagesDirectory?.appendingPathComponent(path)
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
