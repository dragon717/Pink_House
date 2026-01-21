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
            let totalStyleCount = clothings.count
            let totalPrice = clothings.reduce(0) { $0 + ($1.price * Decimal($1.stock)) }
            
            // Calculate Deposit and Balance for active plans
            // Note: App default view filters by current year. Widget should match this to be less confusing.
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: Date())
            
            let depositPlans = clothings.filter { clothing in
                guard clothing.isDepositPlan else { return false }
                // Filter by current year if finalPaymentDate exists
                if let paymentDate = clothing.finalPaymentDate {
                    let year = calendar.component(.year, from: paymentDate)
                    return year == currentYear
                }
                return false
            }
            
            let depositCount = depositPlans.reduce(0) { $0 + $1.stock }
            let depositStyleCount = depositPlans.count // Number of unique clothing items (styles) in the plan
            // Note: Use stock count for price calculation
            let totalDeposit = depositPlans.reduce(0) { $0 + ($1.deposit * Decimal($1.stock)) }
            let totalBalance = depositPlans.reduce(0) { $0 + ($1.balance * Decimal($1.stock)) }
            
            // 3. Recent Items & Image Processing
            let recentItems = processWidgetImages(clothings)
            
            // 4. Series Stats & Save
            // SeriesAnalyzer might be slow, so we do it async but we need to capture clothings
            // Since clothings are Model objects, they might not be thread safe if passed directly across actors without care.
            // But SeriesAnalyzer.analyzeSeries takes [Clothing].
            // Ideally we should map to simple structs before passing if concurrency is an issue, 
            // but for now let's assume SeriesAnalyzer handles it or run on MainActor.
            // Actually SeriesAnalyzer.analyzeSeries is async.
            
            Task {
                // 5. Month Stats
                var monthStats: [WidgetMonthInfo] = []
                
                // Generate for current year (1-12) to match App's year view
                // Since we already filtered depositPlans by currentYear, we can just iterate months of currentYear
                
                for month in 1...12 {
                    // Construct a date for this month/year for display purposes
                    // We need to find items in depositPlans that match this month
                    
                    let monthlyItems = depositPlans.filter { clothing in
                        guard let paymentDate = clothing.finalPaymentDate else { return false }
                        let itemMonth = calendar.component(.month, from: paymentDate)
                        let itemYear = calendar.component(.year, from: paymentDate)
                        return itemMonth == month && itemYear == currentYear
                    }
                    
                    let count = monthlyItems.count
                    let totalBalance = monthlyItems.reduce(0) { $0 + ($1.balance * Decimal($1.stock)) }
                    let totalDeposit = monthlyItems.reduce(0) { $0 + ($1.deposit * Decimal($1.stock)) }
                    
                    monthStats.append(WidgetMonthInfo(
                        month: month, 
                        year: currentYear, 
                        count: count, 
                        totalBalance: totalBalance,
                        totalDeposit: totalDeposit
                    ))
                }
                
                // 6. Save and Reload
                let widgetData = WidgetData(
                    totalCount: totalCount,
                    totalStyleCount: totalStyleCount,
                    depositCount: depositCount,
                    depositStyleCount: depositStyleCount,
                    totalPrice: totalPrice,
                    totalDeposit: totalDeposit,
                    totalBalance: totalBalance,
                    seriesStats: [], // No longer calculating series stats for widget
                    monthStats: monthStats,
                    recentClothings: recentItems,
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
    
    private func processWidgetImages(_ clothings: [Clothing]) -> [WidgetClothing] {
        // Take top 5 recent items
        let recent = clothings.prefix(5)
        var widgetClothings: [WidgetClothing] = []
        
        let fileManager = FileManager.default
        // Assuming images are stored in Documents/Images as per ImageManager
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Images"),
              let widgetImagesDir = WidgetDataManager.shared.widgetImagesDirectory else {
            return recent.map { 
                WidgetClothing(id: $0.id, name: $0.name, price: $0.price, stock: $0.stock, imagePath: nil) 
            }
        }
        
        for clothing in recent {
            var widgetImagePath: String? = nil
            
            if let originalPath = clothing.imagePaths.first {
                let sourceURL = documentsPath.appendingPathComponent(originalPath)
                let destFileName = "thumb_\(originalPath)"
                let destURL = widgetImagesDir.appendingPathComponent(destFileName)
                
                // Compress and Copy if not exists or if source is newer (simplified: just check existence)
                if !fileManager.fileExists(atPath: destURL.path) {
                    if let image = UIImage(contentsOfFile: sourceURL.path) {
                        // Compress to max 300px width/height and low quality to save memory
                        let size = image.size
                        let maxDimension: CGFloat = 300
                        var newSize = size
                        if size.width > maxDimension || size.height > maxDimension {
                            let ratio = size.width / size.height
                            if size.width > size.height {
                                newSize = CGSize(width: maxDimension, height: maxDimension / ratio)
                            } else {
                                newSize = CGSize(width: maxDimension * ratio, height: maxDimension)
                            }
                        }
                        
                        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                        image.draw(in: CGRect(origin: .zero, size: newSize))
                        let newImage = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        
                        if let data = newImage?.jpegData(compressionQuality: 0.5) {
                            try? data.write(to: destURL)
                            widgetImagePath = destFileName
                        }
                    }
                } else {
                    widgetImagePath = destFileName
                }
            }
            
            widgetClothings.append(WidgetClothing(
                id: clothing.id,
                name: clothing.name,
                price: clothing.price,
                stock: clothing.stock,
                imagePath: widgetImagePath
            ))
        }
        return widgetClothings
    }
}
