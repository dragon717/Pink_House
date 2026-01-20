//
//  SharedPersistence.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import Foundation
import SwiftData
import WidgetKit
import SwiftUI

class SharedPersistence {
    static let shared = SharedPersistence()
    
    // 使用默认配置，即存储在 App 的 Documents/Library 目录，不共享
    // 这样保证了数据安全且无需迁移现有数据
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Clothing.self,
            Item.self,
            Tag.self,
            Brand.self
        ])
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // 同步数据给小组件
    // 这个方法应该在数据发生变化时调用（如添加、修改、删除衣物后）
    @MainActor
    func syncWidgetData() {
        let context = sharedModelContainer.mainContext
        
        do {
            // 1. Fetch Data
            let descriptor = FetchDescriptor<Clothing>(sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
            let clothings = try context.fetch(descriptor)
            
            // 2. Calculate Stats
            let totalCount = clothings.reduce(0) { $0 + $1.stock }
            let totalPrice = clothings.reduce(0) { $0 + ($1.price * Decimal($1.stock)) }
            
            // 3. Recent Items
            let recentItems = clothings.prefix(5).map { clothing in
                WidgetClothing(
                    id: clothing.id,
                    name: clothing.name,
                    price: clothing.price,
                    stock: clothing.stock,
                    imagePath: clothing.imagePaths.first
                )
            }
            
            // 4. Series Stats & Save
            // SeriesAnalyzer might be slow, so we do it async but we need to capture clothings
            // Since clothings are Model objects, they might not be thread safe if passed directly across actors without care.
            // But SeriesAnalyzer.analyzeSeries takes [Clothing].
            // Ideally we should map to simple structs before passing if concurrency is an issue, 
            // but for now let's assume SeriesAnalyzer handles it or run on MainActor.
            // Actually SeriesAnalyzer.analyzeSeries is async.
            
            Task {
                let seriesStats = await SeriesAnalyzer.shared.analyzeSeries(from: clothings)
                let widgetSeries = seriesStats.map { info in
                    WidgetSeriesInfo(name: info.name, count: info.count, totalBalance: info.totalBalance)
                }
                
                // 5. Month Stats
                let calendar = Calendar.current
                let now = Date()
                var monthStats: [WidgetMonthInfo] = []
                
                // Generate for last 12 months
                for i in 0..<12 {
                    if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                        let year = calendar.component(.year, from: date)
                        let month = calendar.component(.month, from: date)
                        
                        let count = clothings.filter { 
                            calendar.isDate($0.purchaseDate, equalTo: date, toGranularity: .month) 
                        }.count
                        
                        monthStats.append(WidgetMonthInfo(month: month, year: year, count: count, totalBalance: 0))
                    }
                }
                
                // 6. Save and Reload
                let widgetData = WidgetData(
                    totalCount: totalCount,
                    totalPrice: totalPrice,
                    seriesStats: widgetSeries,
                    monthStats: monthStats,
                    recentClothings: Array(recentItems),
                    lastUpdated: Date()
                )
                
                WidgetDataManager.shared.save(data: widgetData)
                WidgetCenter.shared.reloadAllTimelines()
                print("SharedPersistence: Widget data synced and timeline reloaded.")
            }
            
        } catch {
            print("SharedPersistence: Failed to fetch data for widget sync: \(error)")
        }
    }
}
