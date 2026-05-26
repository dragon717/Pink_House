//
//  SharedPersistence.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import Foundation
import SwiftData
import WidgetKit
import SwiftUI
import CoreData
import os

private enum SharedPersistencePerformanceConfig {
    static let lowMemoryThresholdBytes: UInt64 = 3_500_000_000

    static var isLowMemoryDevice: Bool {
        ProcessInfo.processInfo.physicalMemory <= lowMemoryThresholdBytes
    }
}

@MainActor
class SharedContainer {
    static let shared = SharedContainer()
    private let widgetLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pinkhouse.itemmanager",
        category: "WidgetSync"
    )
    private var deleteReplayTask: Task<Void, Never>?
    
    // 使用 MigrationManager 创建 ModelContainer，支持本地和 iCloud 双模式
    let container: ModelContainer
    
    var sharedModelContainer: ModelContainer { container }
    
    // 便捷访问点，与旧代码兼容
    static var sharedModelContainer: ModelContainer {
        return shared.container
    }
    
    private init() {
        // 使用 SwiftDataMigrationManager 创建合适的 ModelContainer
        do {
            #if WIDGET_EXTENSION
            // 小组件扩展使用简化的本地存储配置
            self.container = try Self.createWidgetModelContainer()
            print("✅ 小组件 ModelContainer 创建成功")
            #else
            // 主应用使用 MigrationManager
            self.container = try SwiftDataMigrationManager.shared.createModelContainer()
            
            // ⚠️ 关键：延迟应用删除，确保数据已经从 iCloud 同步过来
            // 因为 ModelContainer 创建后，iCloud 同步是异步的，需要等待一段时间
            let context = self.container.mainContext
            DeleteTracker.shared.pendingContext = context
            iCloudSyncManager.shared.startMonitoring(with: self.container)
            setupDeleteTrackerAfterSync()
            ClothingDuplicateRepairService.shared.scheduleRepair(
                modelContainer: self.container,
                reason: "container-startup",
                delayNanoseconds: 1_500_000_000
            )
            
            // 延迟5秒首次应用删除，确保 iCloud 同步完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                print("DeleteTracker: 首次应用删除...")
                DeleteTracker.shared.applyAllDeletes(context: context)
            }
            
            // 10秒后再次应用删除（处理同步延迟较大的情况）
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                print("DeleteTracker: 第二次应用删除...")
                DeleteTracker.shared.applyAllDeletes(context: context)
            }
            #endif
        } catch {
            // 最后的回退方案 - 如果 MigrationManager 也失败了
            print("⚠️ MigrationManager 创建失败: \(error)")
            print("🔄 使用最后的回退方案...")
            
            do {
                #if WIDGET_EXTENSION
                // 小组件扩展使用简化的 schema
                let schema = Schema([
                    Clothing.self,
                    WealthSavingEntry.self,
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
                #else
                // 主应用使用完整的 schema
                let schema = Schema([
                    Clothing.self,
                    WealthSavingEntry.self,
                    Item.self,
                    Tag.self,
                    Brand.self,
                    AccessoryItem.self,
                    CutoutItem.self,
                    Outfit.self,
                    OutfitItem.self,
                    BookGroup.self,
                    SpaceBookGroup.self,
                    SpaceOutfit.self,
                    SceneObjectData.self,
                    Model3D.self,
                    StoredImage.self,
                    PerlerBeadPattern.self,
                    Notice.self,
                    ClothingImageSyncRecord.self,
                    DepositNotificationRecord.self,
                    DepositNotificationSettings.self
                ])
                #endif
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                self.container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                print("✅ 回退到本地存储成功")
            } catch {
                fatalError("无法创建 ModelContainer: \(error)")
            }
        }
    }
    
    #if WIDGET_EXTENSION
    /// 为小组件扩展创建简化的 ModelContainer
    private static func createWidgetModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Clothing.self,
            WealthSavingEntry.self,
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
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }
    #endif
    
    /// 重新创建 ModelContainer（切换 iCloud 同步设置后调用）
    func recreateModelContainer() throws {
        #if !WIDGET_EXTENSION
        // 注意：这里不能直接重新赋值 let container，需要其他方式来处理重新创建
        // 暂时保留原有逻辑，实际使用时需要重构
        print("⚠️ recreateModelContainer 需要重新设计以支持 let container")
        #endif
    }
    
    #if !WIDGET_EXTENSION
    /// 设置 iCloud 同步完成后的删除追踪器
    /// 在 iCloud 同步完成后应用删除，避免访问失效对象导致崩溃
    private func setupDeleteTrackerAfterSync() {
        // 监听 iCloud 同步完成事件
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            print("☁️ iCloud 同步完成通知收到，准备应用删除...")
            
            Task { @MainActor [weak self] in
                self?.scheduleDeleteReplayAfterCloudSync(reason: "icloud-remote-change", delay: 1.0)
            }
        }
        
        // 同时监听导入完成事件（从 iCloud 恢复数据时）
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreDidImportUbiquitousContentChanges,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            print("☁️ iCloud 内容导入完成，准备应用删除...")
            
            Task { @MainActor [weak self] in
                self?.scheduleDeleteReplayAfterCloudSync(reason: "icloud-import", delay: 1.0)
            }
        }

        NotificationCenter.default.addObserver(
            forName: iCloudSyncManager.syncStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            guard iCloudSyncManager.shared.syncStatus == .synced else { return }

            Task { @MainActor [weak self] in
                self?.scheduleDeleteReplayAfterCloudSync(reason: "icloud-synced", delay: 0.5)
            }
        }
    }

    @MainActor
    private func scheduleDeleteReplayAfterCloudSync(reason: String, delay: TimeInterval) {
        deleteReplayTask?.cancel()
        deleteReplayTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }

            print("DeleteTracker: iCloud 同步稳定后应用删除保护 (\(reason))...")
            self.replayDeletesAfterCloudSync(reason: reason)
        }
    }

    @MainActor
    private func replayDeletesAfterCloudSync(reason: String) {
        Task {
            DeleteTracker.shared.applyAllDeletes(context: container.mainContext, clearRecords: false)
            ClothingDuplicateRepairService.shared.scheduleRepair(
                modelContainer: container,
                reason: reason,
                delayNanoseconds: 700_000_000
            )
            OOTDIdentityRepairService.repairIfNeeded(
                context: container.mainContext,
                source: reason
            )
            await syncWidgetData(reason: reason)
        }
    }
    #endif
    
    // 同步数据给小组件
    // 这个方法应该在数据发生变化时调用（如添加、修改、删除衣物后）
    @MainActor
    func syncWidgetData(reason: String = "default") async {
        #if !WIDGET_EXTENSION
        guard !SwiftDataMigrationManager.shared.isMigrating else {
            widgetLogger.info("sync_skip reason=\(reason) cloud_migration_in_progress=true")
            return
        }
        #endif

        let startedAt = Date()
        let context = sharedModelContainer.mainContext
        
        do {
            // 1. Fetch Data (只获取未删除的数据)
            let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
            let clothings = try context.fetch(descriptor)
            
            // 2. Calculate Stats
            let totalCount = clothings.reduce(0) { $0 + $1.stock }
            let totalStyleCount = clothings.count
            let totalPrice = clothings.reduce(Decimal(0)) { $0 + $1.inventoryTotalPrice }
            
            // Calculate Deposit and Balance for active plans
            // Note: App default view filters by current year. Widget should match this to be less confusing.
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: Date())
            
            let depositPlans = clothings.filter { clothing in
                guard clothing.isFinalPaymentPlan else { return false }
                // Filter by current year if finalPaymentDate exists
                if let paymentDate = clothing.finalPaymentDate {
                    let year = calendar.component(.year, from: paymentDate)
                    return year == currentYear
                }
                return false
            }
            
            let depositCount = depositPlans.reduce(0) { $0 + $1.stock }
            let depositStyleCount = depositPlans.count // Number of unique clothing items (styles) in the plan
            // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
            let totalDeposit = depositPlans.reduce(0) { $0 + $1.totalDeposit }
            let totalBalance = depositPlans.reduce(0) { $0 + $1.totalBalance }
            
            // 3. Recent Items & Image Processing (Optimized)
            // Extract DTOs for background processing
            let recentItemLimit = SharedPersistencePerformanceConfig.isLowMemoryDevice ? 3 : 5
            let recentClothings = Array(clothings.prefix(recentItemLimit))
            let recentDTOs = recentClothings.map { clothing in
                ClothingWidgetDataDTO(
                    id: clothing.id,
                    name: clothing.name,
                    price: clothing.unitTotalPrice,
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
                
                let count = monthlyItems.reduce(0) { $0 + $1.stock }
                // 注意：totalDeposit 和 totalBalance 已经包含了 stock 的乘法，所以这里直接使用
                let mBalance = monthlyItems.reduce(0) { $0 + $1.totalBalance }
                let mDeposit = monthlyItems.reduce(0) { $0 + $1.totalDeposit }
                
                monthStats.append(WidgetMonthInfo(
                    month: month,
                    year: currentYear,
                    count: count,
                    totalBalance: mBalance,
                    totalDeposit: mDeposit
                ))
            }
            
            // 获取 widgetImagesDirectory 路径（在主线程）
            guard let widgetImagesDir = WidgetDataManager.shared.widgetImagesDirectory else {
                widgetLogger.error("sync_abort reason=\(reason) widget_directory_missing=true")
                return
            }
            
            // Run image processing in background
            let widgetData = await Task.detached(priority: .background) {
                let processedItems = SharedContainer.processWidgetImages(dtos: recentDTOs, widgetImagesDir: widgetImagesDir)
                
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
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            widgetLogger.info("sync_finish reason=\(reason) duration_ms=\(durationMs) clothing_count=\(clothings.count) deposit_plan_count=\(depositPlans.count) recent_item_limit=\(recentItemLimit) low_memory=\(SharedPersistencePerformanceConfig.isLowMemoryDevice)")
            
        } catch {
            widgetLogger.error("sync_failed reason=\(reason) error=\(error.localizedDescription)")
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
    // 标记为 nonisolated 允许从后台任务调用
    nonisolated static func processWidgetImages(dtos: [ClothingWidgetDataDTO], widgetImagesDir: URL) -> [WidgetClothing] {
        var widgetClothings: [WidgetClothing] = []
        
        let fileManager = FileManager.default
        // Assuming images are stored in Documents/Images
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Images") else {
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

// MARK: - 向后兼容的类型别名
typealias SharedPersistence = SharedContainer
