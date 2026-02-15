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
            Brand.self,
            AccessoryItem.self,
            CutoutItem.self,
            Outfit.self,
            OutfitItem.self,
            BookGroup.self,
            SpaceBookGroup.self,
            SpaceOutfit.self
        ])
        
        // 检查 iCloud 同步设置
        // let isCloudSyncEnabled = UserDefaults.standard.bool(forKey: "useCloudSync")
        
        let modelConfiguration: ModelConfiguration
        // if isCloudSyncEnabled {
        //     // 启用 iCloud 同步 (.automatic 通常使用 Application Support 目录)
        //     modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        // } else {
            // 仅本地存储
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        // }
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // 同步数据给小组件
    // 这个方法应该在数据发生变化时调用（如添加、修改、删除衣物后）
    @MainActor
    func syncWidgetData() async {
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
            let totalDeposit = depositPlans.reduce(0) { $0 + ($1.totalDeposit * Decimal($1.stock)) }
            let totalBalance = depositPlans.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
            
            // 3. Recent Items & Image Processing (Optimized)
            // Extract DTOs for background processing
            let recentClothings = Array(clothings.prefix(5))
            let recentDTOs = recentClothings.map { clothing in
                ClothingWidgetDataDTO(
                    id: clothing.id,
                    name: clothing.name,
                    price: clothing.price,
                    stock: clothing.stock,
                    imagePath: clothing.imagePaths.first
                )
            }
            
            // 5. Month Stats (Pre-calculate here to avoid passing objects)
            var monthStats: [WidgetMonthInfo] = []
            for month in 1...12 {
                let monthlyItems = depositPlans.filter { clothing in
                    guard let paymentDate = clothing.finalPaymentDate else { return false }
                    let itemMonth = calendar.component(.month, from: paymentDate)
                    let itemYear = calendar.component(.year, from: paymentDate)
                    return itemMonth == month && itemYear == currentYear
                }
                
                let count = monthlyItems.count
                let mBalance = monthlyItems.reduce(0) { $0 + ($1.totalBalance * Decimal($1.stock)) }
                let mDeposit = monthlyItems.reduce(0) { $0 + ($1.totalDeposit * Decimal($1.stock)) }
                
                monthStats.append(WidgetMonthInfo(
                    month: month,
                    year: currentYear,
                    count: count,
                    totalBalance: mBalance,
                    totalDeposit: mDeposit
                ))
            }
            
            // Run image processing in background
            let widgetData = await Task.detached(priority: .background) {
                let processedItems = SharedPersistence.processWidgetImages(dtos: recentDTOs)
                
                return WidgetData(
                    totalCount: totalCount,
                    totalStyleCount: totalStyleCount,
                    depositCount: depositCount,
                    depositStyleCount: depositStyleCount,
                    totalPrice: totalPrice,
                    totalDeposit: totalDeposit,
                    totalBalance: totalBalance,
                    seriesStats: [],
                    monthStats: monthStats,
                    recentClothings: processedItems,
                    lastUpdated: Date()
                )
            }.value
            
            WidgetDataManager.shared.save(data: widgetData)
            WidgetCenter.shared.reloadAllTimelines()
            print("SharedPersistence: Widget data synced and timeline reloaded.")
            
        } catch {
            print("SharedPersistence: Failed to fetch data for widget sync: \(error)")
        }
    }
    
    // DTO for safe transfer to background task
    struct ClothingWidgetDataDTO: Sendable {
        let id: UUID
        let name: String
        let price: Decimal
        let stock: Int
        let imagePath: String?
    }
    
    // Static function to run in background
    static func processWidgetImages(dtos: [ClothingWidgetDataDTO]) -> [WidgetClothing] {
        var widgetClothings: [WidgetClothing] = []
        
        let fileManager = FileManager.default
        // Assuming images are stored in Documents/Images
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Images"),
              let widgetImagesDir = WidgetDataManager.shared.widgetImagesDirectory else {
            return dtos.map {
                WidgetClothing(id: $0.id, name: $0.name, price: $0.price, stock: $0.stock, imagePath: nil)
            }
        }
        
        for dto in dtos {
            var widgetImagePath: String? = nil
            
            if let originalPath = dto.imagePath {
                let sourceURL = documentsPath.appendingPathComponent(originalPath)
                let destFileName = "thumb_\(originalPath)"
                let destURL = widgetImagesDir.appendingPathComponent(destFileName)
                
                // Compress and Copy if not exists
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
                        
                        // Optimize: Use opaque context if source is opaque
                        let isOpaque: Bool
                        if let alphaInfo = image.cgImage?.alphaInfo {
                            isOpaque = (alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast)
                        } else {
                            isOpaque = false
                        }
                        
                        UIGraphicsBeginImageContextWithOptions(newSize, isOpaque, 1.0)
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
                id: dto.id,
                name: dto.name,
                price: dto.price,
                stock: dto.stock,
                imagePath: widgetImagePath
            ))
        }
        return widgetClothings
    }
}
