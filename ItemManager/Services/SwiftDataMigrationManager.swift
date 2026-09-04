//
//  SwiftDataMigrationManager.swift
//  ItemManager
//
//  Created by AI Assistant on 2/20/26.
//  处理 SwiftData 本地存储和 iCloud 同步之间的数据迁移
//

import Foundation
import SwiftData
import CloudKit
import Combine

/// 数据迁移管理器 - 处理本地数据库和 iCloud 同步数据库之间的无缝迁移
class SwiftDataMigrationManager: ObservableObject {
    static let shared = SwiftDataMigrationManager()
    
    // MARK: - Published Properties
    @Published var isMigrating: Bool = false
    @Published var migrationProgress: Double = 0.0
    @Published var migrationError: String?
    @Published var lastMigrationDate: Date?
    
    // MARK: - Constants
    private let iCloudSyncEnabledKey = "useCloudSync"
    private let migrationCompletedKey = "cloudMigrationCompleted"
    private let lastMigrationDateKey = "lastCloudMigrationDate"
    
    // iCloud Container ID - 需要与项目中的 Capability 配置一致
    private let cloudKitContainerIdentifier = "iCloud.bugod2.ItemManager"
    
    // 数据库文件名
    private let localStoreName = "default.store"
    private let cloudStoreName = "cloud.store"
    
    // 用于发布更新的 Subject
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.lastMigrationDate = UserDefaults.standard.object(forKey: lastMigrationDateKey) as? Date
    }
    
    // MARK: - Public Properties
    
    /// iCloud 同步是否已启用
    var isCloudSyncEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: iCloudSyncEnabledKey)
        }
    }
    
    /// 迁移是否已完成
    var isMigrationCompleted: Bool {
        get {
            UserDefaults.standard.bool(forKey: migrationCompletedKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: migrationCompletedKey)
        }
    }
    
    // MARK: - Model Schema
    
    /// 获取完整的 Model Schema
    private var fullSchema: Schema {
        #if WIDGET_EXTENSION
        // 小组件扩展使用简化 Schema
        return Schema([
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
        // 主应用使用完整 Schema
        return Schema([
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
            Notice.self,
            ClothingImageSyncRecord.self,
            DepositNotificationRecord.self,
            DepositNotificationSettings.self
        ])
        #endif
    }
    
    /// 获取完整的 Model Schema（用于外部访问）
    func getFullSchema() -> Schema {
        return fullSchema
    }
    
    // MARK: - Store URLs
    
    /// 获取应用 Support 目录
    private var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
    
    /// 本地存储 URL (非 iCloud)
    var localStoreURL: URL {
        applicationSupportURL.appendingPathComponent(localStoreName)
    }
    
    /// iCloud 存储 URL
    var cloudStoreURL: URL {
        applicationSupportURL.appendingPathComponent(cloudStoreName)
    }
    
    /// 检查本地旧数据库是否存在
    var localStoreExists: Bool {
        FileManager.default.fileExists(atPath: localStoreURL.path)
    }
    
    /// 检查 iCloud 数据库是否存在
    var cloudStoreExists: Bool {
        FileManager.default.fileExists(atPath: cloudStoreURL.path)
    }
    
    // MARK: - ModelContainer Creation
    
    /// 创建适合当前配置的 ModelContainer
    /// 这是主要的入口方法，应用启动时调用
    func createModelContainer() throws -> ModelContainer {
        let schema = fullSchema
        
        print("🔄 创建 ModelContainer，iCloud 同步: \(isCloudSyncEnabled ? "启用" : "禁用")")
        
        if isCloudSyncEnabled {
            // 检查 iCloud 账户状态
            let container = CKContainer(identifier: cloudKitContainerIdentifier)
            let semaphore = DispatchSemaphore(value: 0)
            var accountStatus: CKAccountStatus = .couldNotDetermine
            var accountError: Error?
            
            container.accountStatus { status, error in
                accountStatus = status
                accountError = error
                semaphore.signal()
            }
            semaphore.wait()
            
            print("☁️ iCloud 账户状态: \(accountStatus)")
            
            guard accountStatus == .available else {
                print("⚠️ iCloud 账户不可用，回退到本地存储")
                if let error = accountError {
                    print("   错误: \(error.localizedDescription)")
                }
                // iCloud 不可用，自动关闭同步开关
                isCloudSyncEnabled = false
                print("🔄 已自动关闭 iCloud 同步开关")
                return try createLocalModelContainer(schema: schema)
            }
            
            // iCloud 同步模式
            print("☁️ 使用 iCloud 同步模式")
            return try createCloudModelContainer(schema: schema)
        } else {
            // 纯本地模式
            print("💾 使用本地存储模式")
            return try createLocalModelContainer(schema: schema)
        }
    }
    
    /// 创建纯本地 ModelContainer
    private func createLocalModelContainer(schema: Schema) throws -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            
            let container = try ModelContainer(for: schema, configurations: [configuration])
            print("✅ 本地 ModelContainer 创建成功")
            return container
        } catch {
            print("❌ 创建本地 ModelContainer 失败: \(error)")
            throw error
        }
    }
    
    /// 创建支持 iCloud 同步的 ModelContainer
    private func createCloudModelContainer(schema: Schema) throws -> ModelContainer {
        do {
            // 首先创建 iCloud 容器
            print("☁️ 创建 iCloud ModelContainer...")
            print("📦 使用 CloudKit 容器: \(cloudKitContainerIdentifier)")
            
            // 使用明确指定的 CloudKit 容器，确保数据同步到正确的私有数据库
            // 注意：需要确保 entitlements 中配置了正确的 iCloud 容器
            let cloudConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
            
            let cloudContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ iCloud ModelContainer 创建成功")
            
            // 检查是否需要从本地迁移数据
            let needsMigration = localStoreExists && !isMigrationCompleted
            print("🔄 需要迁移: \(needsMigration)，本地存储存在: \(localStoreExists)，迁移已完成: \(isMigrationCompleted)")
            
            if needsMigration {
                // 在后台执行迁移
                Task {
                    await performMigrationAsync(schema: schema, cloudContainer: cloudContainer)
                }
            }
            
            return cloudContainer
        } catch {
            print("❌ 创建 iCloud ModelContainer 失败: \(error)")
            print("⚠️ 错误详情: \(error.localizedDescription)")
            print("🔄 回退到本地存储模式...")
            
            // iCloud 创建失败，自动关闭同步开关
            isCloudSyncEnabled = false
            print("🔄 已自动关闭 iCloud 同步开关")
            
            // 回退到本地存储
            return try createLocalModelContainer(schema: schema)
        }
    }
    
    /// 异步执行迁移
    private func performMigrationAsync(schema: Schema, cloudContainer: ModelContainer) async {
        do {
            // 创建本地容器
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            
            let localContainer = try ModelContainer(for: schema, configurations: [localConfig])
            
            // 执行迁移
            await performMigration(from: localContainer, to: cloudContainer)
            
        } catch {
            print("❌ 创建本地容器失败: \(error)")
            await MainActor.run {
                self.migrationError = "创建本地容器失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Data Migration
    
    /// 执行数据迁移 - 从本地数据库迁移到 iCloud 数据库
    func performMigration(from localContainer: ModelContainer, to cloudContainer: ModelContainer) async {
        guard !isMigrating else { return }
        
        isMigrating = true
        migrationProgress = 0.0
        migrationError = nil
        
        do {
            // 创建上下文
            let localContext = ModelContext(localContainer)
            let cloudContext = ModelContext(cloudContainer)
            
            // 注意：ModelContext 没有 automaticallyMergesChangesFromParent 属性
            // SwiftData 会自动处理变更合并
            
            // 1. 迁移 Clothing
            try await migrateClothing(from: localContext, to: cloudContext)
            migrationProgress = 0.12

            // 1b. 迁移历史财富记录
            try await migrateWealthSavingEntries(from: localContext, to: cloudContext)
            reconcilePaidFinalPayments(in: cloudContext, reason: "wealth-entry-migration")
            migrationProgress = 0.15
            
            // 2. 迁移 Tag
            try await migrateTags(from: localContext, to: cloudContext)
            migrationProgress = 0.25
            
            // 3. 迁移 Brand
            try await migrateBrands(from: localContext, to: cloudContext)
            migrationProgress = 0.35
            
            // 4. 迁移 AccessoryItem
            try await migrateAccessoryItems(from: localContext, to: cloudContext)
            migrationProgress = 0.45
            
            // 5. 迁移 CutoutItem
            try await migrateCutoutItems(from: localContext, to: cloudContext)
            migrationProgress = 0.55
            
            // 6. 迁移 Outfit 相关
            try await migrateOutfits(from: localContext, to: cloudContext)
            migrationProgress = 0.70
            
            // 7. 迁移 BookGroup
            try await migrateBookGroups(from: localContext, to: cloudContext)
            migrationProgress = 0.80
            
            // 8. 迁移 SpaceBookGroup 和 SpaceOutfit
            try await migrateSpaceOutfits(from: localContext, to: cloudContext)
            migrationProgress = 0.90
            
            // 9. 迁移 SceneObjectData 和 Model3D
            try await migrate3DModels(from: localContext, to: cloudContext)
            migrationProgress = 0.95
            
            // 10. 迁移 StoredImage
            try await migrateStoredImages(from: localContext, to: cloudContext)
            migrationProgress = 0.98

            // 10b. 重建衣橱关系。Clothing 先于 Brand/Tag/AccessoryItem 复制，关系需要在目标
            // context 对象都存在后统一补链，避免 iCloud 同步后编辑页看到孤儿小物。
            try rebuildWardrobeRelationships(from: localContext, to: cloudContext)
            reconcilePaidFinalPayments(in: cloudContext, reason: "wardrobe-relationship-rebuild")
            migrationProgress = 0.985

            // 11. 重建 OOTD/手帐关系。前面的复制步骤按实体去重插入，关系对象必须在目标
            // context 全部存在后再统一补链，避免平面书页在 iCloud 迁移后变成孤儿。
            try rebuildOOTDRelationships(from: localContext, to: cloudContext)
            migrationProgress = 0.99
            
            // 保存云端数据
            try cloudContext.save()
            
            // 标记迁移完成
            isMigrationCompleted = true
            lastMigrationDate = Date()
            UserDefaults.standard.set(lastMigrationDate, forKey: lastMigrationDateKey)
            
            // 可选：迁移完成后删除本地数据库（或保留作为备份）
            // try? deleteLocalStore()
            
            migrationProgress = 1.0
            print("✅ 数据迁移完成：本地数据已成功同步到 iCloud")
            
        } catch {
            migrationError = "迁移失败: \(error.localizedDescription)"
            print("❌ 数据迁移失败: \(error)")
        }
        
        isMigrating = false
    }
    
    // MARK: - Entity Migration Methods

    func mergeWardrobePaymentFacts(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        try migrateClothing(from: localContext, to: cloudContext)
        try migrateWealthSavingEntries(from: localContext, to: cloudContext)
        reconcilePaidFinalPayments(in: cloudContext, reason: "wardrobe-payment-facts")
    }
    
    private func migrateClothing(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<Clothing>()
        let items = try localContext.fetch(descriptor)
        let localFinalPaymentEntries = try fetchActiveFinalPaymentEntries(in: localContext)
        var paidFinalPaymentMergedCount = 0
        
        for item in items {
            // 检查云端是否已存在（通过 UUID 查重）
            let id = item.id
            var fetchDescriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            if let existing {
                if Self.FinalPaymentMigrationMerge.applyLocalPaidFinalPaymentFact(
                    from: item,
                    localFinalPaymentEntries: localFinalPaymentEntries,
                    to: existing,
                    at: Date()
                ) {
                    paidFinalPaymentMergedCount += 1
                }
            } else {
                // 创建新实例插入云端
                let newItem = createClothingCopy(from: item)
                if Self.FinalPaymentMigrationMerge.applyLocalPaidFinalPaymentFact(
                    from: item,
                    localFinalPaymentEntries: localFinalPaymentEntries,
                    to: newItem,
                    at: Date()
                ) {
                    paidFinalPaymentMergedCount += 1
                }
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 Clothing 记录，合并已付尾款状态 \(paidFinalPaymentMergedCount) 条")
    }

    private func migrateWealthSavingEntries(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<WealthSavingEntry>()
        let items = try localContext.fetch(descriptor)
        var cloudFinalPaymentEntries = try fetchActiveFinalPaymentEntries(in: cloudContext)
        var skippedDuplicateFinalPayments = 0

        for item in items {
            let id = item.id
            let fetchDescriptor = FetchDescriptor<WealthSavingEntry>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first

            if existing == nil {
                if shouldSkipMigratingDuplicateFinalPayment(item, existingEntries: cloudFinalPaymentEntries) {
                    skippedDuplicateFinalPayments += 1
                    continue
                }

                let newItem = createWealthSavingEntryCopy(from: item)
                cloudContext.insert(newItem)
                if WealthSavingLedger.isFinalPaymentRecord(newItem) {
                    cloudFinalPaymentEntries.append(newItem)
                }
            }
        }

        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 WealthSavingEntry 记录，跳过重复尾款账本 \(skippedDuplicateFinalPayments) 条")
    }

    private func fetchActiveFinalPaymentEntries(in context: ModelContext) throws -> [WealthSavingEntry] {
        let finalPaymentKind = WealthSavingEntryKind.finalPayment.rawValue
        let descriptor = FetchDescriptor<WealthSavingEntry>(
            predicate: #Predicate { entry in
                entry.entryKind == finalPaymentKind && entry.voidedAt == nil
            }
        )
        return try context.fetch(descriptor)
    }

    private func shouldSkipMigratingDuplicateFinalPayment(
        _ source: WealthSavingEntry,
        existingEntries: [WealthSavingEntry]
    ) -> Bool {
        Self.FinalPaymentMigrationMerge.shouldSkipMigratingDuplicateFinalPayment(
            source,
            existingEntries: existingEntries
        )
    }

    private func reconcilePaidFinalPayments(in context: ModelContext, reason: String) {
        let reconciledCount = WealthSavingLedger.reconcilePaidFinalPayments(context: context)
        if reconciledCount > 0 {
            print("  - 智能合并已付尾款状态 (\(reason)): \(reconciledCount) 条")
        }
    }
    
    private func migrateTags(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<Tag>()
        let items = try localContext.fetch(descriptor)
        
        for item in items {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createTagCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 Tag 记录")
    }
    
    private func migrateBrands(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<Brand>()
        let items = try localContext.fetch(descriptor)
        
        for item in items {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<Brand>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createBrandCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 Brand 记录")
    }
    
    private func migrateAccessoryItems(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<AccessoryItem>()
        let items = try localContext.fetch(descriptor)
        
        for item in items {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<AccessoryItem>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createAccessoryItemCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 AccessoryItem 记录")
    }
    
    private func migrateCutoutItems(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<CutoutItem>()
        let items = try localContext.fetch(descriptor)
        
        for item in items {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createCutoutItemCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 CutoutItem 记录")
    }
    
    private func migrateOutfits(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        // 迁移 Outfit
        let outfitDescriptor = FetchDescriptor<Outfit>()
        let outfits = try localContext.fetch(outfitDescriptor)
        
        for item in outfits {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<Outfit>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createOutfitCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(outfits.count) 条 Outfit 记录")
        
        // 迁移 OutfitItem
        let outfitItemDescriptor = FetchDescriptor<OutfitItem>()
        let outfitItems = try localContext.fetch(outfitItemDescriptor)
        
        for item in outfitItems {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<OutfitItem>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createOutfitItemCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(outfitItems.count) 条 OutfitItem 记录")
    }
    
    private func migrateBookGroups(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<BookGroup>()
        let items = try localContext.fetch(descriptor)
        
        for item in items {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<BookGroup>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createBookGroupCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 BookGroup 记录")
    }
    
    private func migrateSpaceOutfits(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        // SpaceBookGroup
        let bookDescriptor = FetchDescriptor<SpaceBookGroup>()
        let books = try localContext.fetch(bookDescriptor)
        
        for item in books {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<SpaceBookGroup>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createSpaceBookGroupCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(books.count) 条 SpaceBookGroup 记录")
        
        // SpaceOutfit
        let outfitDescriptor = FetchDescriptor<SpaceOutfit>()
        let outfits = try localContext.fetch(outfitDescriptor)
        
        for item in outfits {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<SpaceOutfit>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createSpaceOutfitCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(outfits.count) 条 SpaceOutfit 记录")
    }
    
    private func migrate3DModels(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        // SceneObjectData
        let sceneDescriptor = FetchDescriptor<SceneObjectData>()
        let scenes = try localContext.fetch(sceneDescriptor)
        
        for item in scenes {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<SceneObjectData>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createSceneObjectDataCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(scenes.count) 条 SceneObjectData 记录")
        
        // Model3D
        let modelDescriptor = FetchDescriptor<Model3D>()
        let models = try localContext.fetch(modelDescriptor)
        
        for item in models {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<Model3D>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createModel3DCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(models.count) 条 Model3D 记录")
    }
    
    private func migrateStoredImages(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let descriptor = FetchDescriptor<StoredImage>()
        let items = try localContext.fetch(descriptor)
        
        for item in items {
            let id = item.id
            var fetchDescriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.id == id })
            let existing = try? cloudContext.fetch(fetchDescriptor).first
            
            if existing == nil {
                let newItem = createStoredImageCopy(from: item)
                cloudContext.insert(newItem)
            }
        }
        
        try cloudContext.save()
        print("  - 迁移了 \(items.count) 条 StoredImage 记录")
    }

    private func rebuildWardrobeRelationships(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let localClothings = try localContext.fetch(FetchDescriptor<Clothing>())
        let cloudClothings = try cloudContext.fetch(FetchDescriptor<Clothing>())
        let cloudBrands = try cloudContext.fetch(FetchDescriptor<Brand>())
        let cloudTags = try cloudContext.fetch(FetchDescriptor<Tag>())
        let cloudAccessoryItems = try cloudContext.fetch(FetchDescriptor<AccessoryItem>())

        let clothingMap = mapByID(cloudClothings, id: \.id)
        let brandMap = mapByID(cloudBrands, id: \.id)
        let tagMap = mapByID(cloudTags, id: \.id)
        let accessoryMap = mapByID(cloudAccessoryItems, id: \.id)

        var relinkedBrands = 0
        var relinkedTags = 0
        var relinkedAccessories = 0

        for localClothing in localClothings {
            guard let cloudClothing = clothingMap[localClothing.id] else { continue }

            if let localBrandID = localClothing.brand?.id {
                if cloudClothing.brand?.id != localBrandID,
                   let cloudBrand = brandMap[localBrandID] {
                    cloudClothing.brand = cloudBrand
                    relinkedBrands += 1
                }
            } else if cloudClothing.brand != nil {
                cloudClothing.brand = nil
                relinkedBrands += 1
            }

            let localTagIDs = (localClothing.tags ?? []).map(\.id)
            let currentTagIDs = (cloudClothing.tags ?? []).map(\.id)
            if currentTagIDs != localTagIDs {
                cloudClothing.tags = localTagIDs.compactMap { tagMap[$0] }
                relinkedTags += 1
            }

            let localAccessoryIDs = (localClothing.accessoryItems ?? [])
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(\.id)
            let currentAccessoryIDs = (cloudClothing.accessoryItems ?? [])
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(\.id)
            if currentAccessoryIDs != localAccessoryIDs {
                let cloudAccessories = localAccessoryIDs.compactMap { accessoryMap[$0] }
                cloudClothing.accessoryItems = cloudAccessories
                for accessory in cloudAccessories {
                    accessory.clothing = cloudClothing
                }
                relinkedAccessories += 1
            }
        }

        try cloudContext.save()
        print("  - 重建衣橱关系：Clothing.brand \(relinkedBrands)，Clothing.tags \(relinkedTags)，Clothing.accessoryItems \(relinkedAccessories)")
    }

    private func rebuildOOTDRelationships(from localContext: ModelContext, to cloudContext: ModelContext) throws {
        let localOutfits = try localContext.fetch(FetchDescriptor<Outfit>())
        let localOutfitItems = try localContext.fetch(FetchDescriptor<OutfitItem>())
        let localSpaceOutfits = try localContext.fetch(FetchDescriptor<SpaceOutfit>())
        let localSceneObjects = try localContext.fetch(FetchDescriptor<SceneObjectData>())

        let cloudBooks = try cloudContext.fetch(FetchDescriptor<BookGroup>())
        let cloudOutfits = try cloudContext.fetch(FetchDescriptor<Outfit>())
        let cloudOutfitItems = try cloudContext.fetch(FetchDescriptor<OutfitItem>())
        let cloudCutouts = try cloudContext.fetch(FetchDescriptor<CutoutItem>())
        let cloudSpaceBooks = try cloudContext.fetch(FetchDescriptor<SpaceBookGroup>())
        let cloudSpaceOutfits = try cloudContext.fetch(FetchDescriptor<SpaceOutfit>())
        let cloudSceneObjects = try cloudContext.fetch(FetchDescriptor<SceneObjectData>())
        let cloudModel3Ds = try cloudContext.fetch(FetchDescriptor<Model3D>())

        let bookMap = mapByID(cloudBooks, id: \.id)
        let outfitMap = mapByID(cloudOutfits, id: \.id)
        let outfitItemMap = mapByID(cloudOutfitItems, id: \.id)
        let cutoutMap = mapByID(cloudCutouts, id: \.id)
        let spaceBookMap = mapByID(cloudSpaceBooks, id: \.id)
        let spaceOutfitMap = mapByID(cloudSpaceOutfits, id: \.id)
        let sceneObjectMap = mapByID(cloudSceneObjects, id: \.id)
        let model3DMap = mapByID(cloudModel3Ds, id: \.id)

        var relinkedOutfits = 0
        for localOutfit in localOutfits {
            guard let cloudOutfit = outfitMap[localOutfit.id],
                  let localBookID = localOutfit.book?.id else {
                continue
            }
            if cloudOutfit.book?.id != localBookID,
               let cloudBook = bookMap[localBookID] {
                cloudOutfit.book = cloudBook
                relinkedOutfits += 1
            }
        }

        var relinkedItems = 0
        for localItem in localOutfitItems {
            guard let cloudItem = outfitItemMap[localItem.id] else { continue }
            var didRelink = false
            if let localCutoutID = localItem.cutout?.id,
               cloudItem.cutout?.id != localCutoutID,
               let cloudCutout = cutoutMap[localCutoutID] {
                cloudItem.cutout = cloudCutout
                didRelink = true
            }
            if let localOutfitID = localItem.outfit?.id,
               cloudItem.outfit?.id != localOutfitID,
               let cloudOutfit = outfitMap[localOutfitID] {
                cloudItem.outfit = cloudOutfit
                if cloudOutfit.items == nil {
                    cloudOutfit.items = []
                }
                if !(cloudOutfit.items?.contains(where: { $0.id == cloudItem.id }) ?? false) {
                    cloudOutfit.items?.append(cloudItem)
                }
                didRelink = true
            }
            if didRelink {
                relinkedItems += 1
            }
        }

        var relinkedSpaceOutfits = 0
        for localSpaceOutfit in localSpaceOutfits {
            guard let cloudSpaceOutfit = spaceOutfitMap[localSpaceOutfit.id],
                  let localBookID = localSpaceOutfit.book?.id else {
                continue
            }
            if cloudSpaceOutfit.book?.id != localBookID,
               let cloudBook = spaceBookMap[localBookID] {
                cloudSpaceOutfit.book = cloudBook
                relinkedSpaceOutfits += 1
            }
        }

        var relinkedSceneObjects = 0
        for localSceneObject in localSceneObjects {
            guard let cloudSceneObject = sceneObjectMap[localSceneObject.id] else { continue }
            var didRelink = false
            if cloudSceneObject.spaceOutfitID != localSceneObject.spaceOutfitID {
                cloudSceneObject.spaceOutfitID = localSceneObject.spaceOutfitID
                didRelink = true
            }
            if let localModel3DID = localSceneObject.model3D?.id,
               cloudSceneObject.model3D?.id != localModel3DID,
               let cloudModel3D = model3DMap[localModel3DID] {
                cloudSceneObject.model3D = cloudModel3D
                didRelink = true
            }
            if didRelink {
                relinkedSceneObjects += 1
            }
        }

        try cloudContext.save()
        print("  - 重建 OOTD 关系：Outfit.book \(relinkedOutfits)，OutfitItem \(relinkedItems)，SpaceOutfit.book \(relinkedSpaceOutfits)，SceneObjectData \(relinkedSceneObjects)")
    }

    private func mapByID<T>(_ items: [T], id keyPath: KeyPath<T, UUID>) -> [UUID: T] {
        var result: [UUID: T] = [:]
        for item in items {
            let id = item[keyPath: keyPath]
            if result[id] == nil {
                result[id] = item
            }
        }
        return result
    }
    
    // MARK: - Entity Copy Methods
    
    private func createClothingCopy(from source: Clothing) -> Clothing {
        let new = Clothing(
            name: source.name,
            brand: nil, // 关系需要单独处理
            types: source.types,
            colors: source.colors,
            sizes: source.sizes,
            length: source.length,
            condition: source.condition,
            accessories: source.accessories,
            imagePaths: source.imagePaths,
            isShared: source.isShared,
            originalPrice: FinancialDataSanitizer.money(source.originalPrice),
            price: FinancialDataSanitizer.money(source.price),
            deposit: FinancialDataSanitizer.money(source.deposit),
            balance: FinancialDataSanitizer.money(source.balance),
            accessoriesPrice: FinancialDataSanitizer.money(source.accessoriesPrice),
            purchaseDate: source.purchaseDate,
            depositDate: source.depositDate,
            isDepositPlan: source.isDepositPlan,
            finalPaymentDate: source.finalPaymentDate,
            finalPaymentEndDate: source.finalPaymentEndDate,
            note: source.note,
            stock: FinancialDataSanitizer.stock(source.stock),
            status: source.status
        )
        new.copyCurrencyAndShippingMetadata(from: source)
        new.originalPriceJPY = FinancialDataSanitizer.money(source.originalPriceJPY)
        new.shippingFee = FinancialDataSanitizer.money(source.shippingFee)
        new.shippingFeeJPY = FinancialDataSanitizer.money(source.shippingFeeJPY)
        new.id = source.id
        new.sizeChartImagePath = source.sizeChartImagePath
        new.priceChartImagePath = source.priceChartImagePath
        new.sortIndex = source.sortIndex
        new.isDeleted = source.isDeleted
        new.deletedAt = source.deletedAt
        new.deletionSource = source.deletionSource
        new.createdAt = source.createdAt
        new.updatedAt = source.updatedAt
        new.lastModified = source.lastModified
        new.isFinalPaymentSavedToWealth = false
        new.finalPaymentSavedAt = nil
        new.finalPaymentInstallmentCount = 0
        new.model3DPath = source.model3DPath
        new.model3DType = source.model3DType
        new.model3DThumbnailPath = source.model3DThumbnailPath
        new.replacedCutoutID = source.replacedCutoutID
        return new
    }

    private func createWealthSavingEntryCopy(from source: WealthSavingEntry) -> WealthSavingEntry {
        let normalizedKind = source.kind
        let normalizedAmount = FinancialDataSanitizer.money(source.amount)
        let new = WealthSavingEntry(
            amount: normalizedAmount,
            clothingID: source.clothingID,
            note: source.note,
            migrationSource: source.migrationSource,
            entryKind: normalizedKind,
            paidAt: source.paidAt,
            createdAt: source.createdAt
        )
        new.id = source.id
        new.updatedAt = source.updatedAt
        new.usedAt = source.usedAt
        new.voidedAt = source.voidedAt
        new.lastModified = source.lastModified
        return new
    }
    
    private func createTagCopy(from source: Tag) -> Tag {
        let new = Tag(name: source.name, colorHex: source.colorHex)
        new.id = source.id
        return new
    }
    
    private func createBrandCopy(from source: Brand) -> Brand {
        let new = Brand(name: source.name, colorHex: source.colorHex, imagePath: source.imagePath)
        new.id = source.id
        return new
    }
    
    private func createAccessoryItemCopy(from source: AccessoryItem) -> AccessoryItem {
        let new = AccessoryItem(
            name: source.name,
            price: FinancialDataSanitizer.money(source.price),
            deposit: FinancialDataSanitizer.money(source.deposit),
            balance: FinancialDataSanitizer.money(source.balance),
            sortIndex: source.sortIndex,
            imagePaths: source.imagePaths
        )
        new.id = source.id
        return new
    }
    
    private func createCutoutItemCopy(from source: CutoutItem) -> CutoutItem {
        let new = CutoutItem(
            originalImageHash: source.originalImageHash,
            category: source.category,
            imagePath: source.imagePath,
            width: source.width,
            height: source.height,
            linkedClothingID: source.linkedClothingID,
            clothingName: source.clothingName
        )
        new.id = source.id
        new.timestamp = source.timestamp
        new.lastModified = source.lastModified
        return new
    }
    
    private func createOutfitCopy(from source: Outfit) -> Outfit {
        let new = Outfit(
            note: source.note,
            snapshotPath: source.snapshotPath,
            canvasType: source.canvasType,
            backgroundImagePath: source.backgroundImagePath,
            mannequinAssetID: source.mannequinAssetID,
            book: nil // 关系需要单独处理
        )
        new.id = source.id
        new.createdAt = source.createdAt
        new.sortIndex = source.sortIndex
        new.isDeleted = source.isDeleted
        new.deletedAt = source.deletedAt
        new.lastModified = source.lastModified
        return new
    }

    private func createOutfitItemCopy(from source: OutfitItem) -> OutfitItem {
        let new = OutfitItem(
            cutout: nil, // 关系需要单独处理
            x: source.x,
            y: source.y,
            rotation: source.rotation,
            scale: source.scale,
            zIndex: source.zIndex,
            coordinateVersion: source.coordinateVersion
        )
        new.id = source.id
        return new
    }
    
    private func createBookGroupCopy(from source: BookGroup) -> BookGroup {
        let new = BookGroup(title: source.title, coverImage: source.coverImage, sortIndex: source.sortIndex)
        new.id = source.id
        new.createdAt = source.createdAt
        new.isDeleted = source.isDeleted
        new.deletedAt = source.deletedAt
        new.lastModified = source.lastModified
        return new
    }

    private func createSpaceBookGroupCopy(from source: SpaceBookGroup) -> SpaceBookGroup {
        let new = SpaceBookGroup(title: source.title, coverImage: source.coverImage, sortIndex: source.sortIndex)
        new.id = source.id
        new.createdAt = source.createdAt
        new.isDeleted = source.isDeleted
        new.deletedAt = source.deletedAt
        new.lastModified = source.lastModified
        return new
    }

    private func createSpaceOutfitCopy(from source: SpaceOutfit) -> SpaceOutfit {
        let new = SpaceOutfit(
            note: source.note,
            snapshotPath: source.snapshotPath,
            book: nil,
            sortIndex: source.sortIndex
        )
        new.id = source.id
        new.createdAt = source.createdAt
        new.modelPath = source.modelPath
        new.camPosX = source.camPosX
        new.camPosY = source.camPosY
        new.camPosZ = source.camPosZ
        new.lightingIntensity = source.lightingIntensity
        new.isDeleted = source.isDeleted
        new.deletedAt = source.deletedAt
        new.lastModified = source.lastModified
        return new
    }
    
    private func createSceneObjectDataCopy(from source: SceneObjectData) -> SceneObjectData {
        let new = SceneObjectData(
            id: source.id,
            objectType: source.objectType,
            position: source.position,
            rotation: source.rotation,
            scale: source.scale,
            usdzModelPath: source.usdzModelPath,
            color: source.color,
            sortIndex: source.sortIndex,
            spaceOutfitID: nil,
            model3D: nil
        )
        return new
    }
    
    private func createModel3DCopy(from source: Model3D) -> Model3D {
        let new = Model3D(
            name: source.name,
            types: source.types,
            modelPath: source.modelPath,
            modelType: source.modelType,
            thumbnailPath: source.thumbnailPath,
            sourceImagePaths: source.sourceImagePaths,
            sortIndex: source.sortIndex
        )
        new.id = source.id
        new.isDeleted = source.isDeleted
        new.deletedAt = source.deletedAt
        new.createdAt = source.createdAt
        new.updatedAt = source.updatedAt
        new.lastModified = source.lastModified
        new.cameraPositionX = source.cameraPositionX
        new.cameraPositionY = source.cameraPositionY
        new.cameraPositionZ = source.cameraPositionZ
        new.cameraRotationX = source.cameraRotationX
        new.cameraRotationY = source.cameraRotationY
        new.cameraRotationZ = source.cameraRotationZ
        return new
    }
    
    private func createStoredImageCopy(from source: StoredImage) -> StoredImage {
        let new = StoredImage(
            imageHash: source.imageHash,
            fileName: source.fileName
        )
        new.id = source.id
        new.refCount = source.refCount
        new.createdAt = source.createdAt
        new.updatedAt = source.updatedAt
        new.lastModified = source.lastModified
        return new
    }
    
    // MARK: - Toggle iCloud Sync
    
    /// 切换 iCloud 同步开关
    /// 返回 true 表示切换成功，需要重启应用
    func toggleCloudSync(enabled: Bool) async -> Bool {
        guard enabled != isCloudSyncEnabled else { return false }
        
        if enabled {
            // 开启 iCloud 同步
            // 检查 iCloud 账户状态
            let container = CKContainer(identifier: cloudKitContainerIdentifier)
            do {
                let status = try await container.accountStatus()
                guard status == .available else {
                    migrationError = "iCloud 账户不可用，请检查设置"
                    return false
                }
            } catch {
                migrationError = "无法访问 iCloud: \(error.localizedDescription)"
                return false
            }
            
            // 重置迁移标记，下次启动时会执行迁移
            isMigrationCompleted = false
        } else {
            // 关闭 iCloud 同步
            // 数据会保留在本地，但不再同步
            isMigrationCompleted = true
        }
        
        isCloudSyncEnabled = enabled
        return true // 需要重启应用才能生效
    }
    
    // MARK: - Cleanup
    
    /// 删除本地数据库文件（迁移完成后可选调用）
    func deleteLocalStore() throws {
        let fileManager = FileManager.default
        
        // 删除主数据库文件
        if fileManager.fileExists(atPath: localStoreURL.path) {
            try fileManager.removeItem(at: localStoreURL)
        }
        
        // 删除相关的 WAL 和 SHM 文件
        let walURL = localStoreURL.appendingPathExtension("sqlite-wal")
        let shmURL = localStoreURL.appendingPathExtension("sqlite-shm")
        
        if fileManager.fileExists(atPath: walURL.path) {
            try? fileManager.removeItem(at: walURL)
        }
        if fileManager.fileExists(atPath: shmURL.path) {
            try? fileManager.removeItem(at: shmURL)
        }
        
        print("🗑️ 本地数据库已删除")
    }
    
    /// 重置迁移状态（用于调试）
    func resetMigrationState() {
        isMigrationCompleted = false
        lastMigrationDate = nil
        UserDefaults.standard.removeObject(forKey: lastMigrationDateKey)
        print("🔄 迁移状态已重置")
    }
}

extension SwiftDataMigrationManager {
    enum FinalPaymentMigrationMerge {
        @discardableResult
        static func applyLocalPaidFinalPaymentFact(
            from localClothing: Clothing,
            localFinalPaymentEntries: [WealthSavingEntry],
            to cloudClothing: Clothing,
            at date: Date = Date()
        ) -> Bool {
            guard localClothing.id == cloudClothing.id,
                  cloudClothing.isFinalPaymentPlan,
                  WealthSavingLedger.hasPaidFinalPaymentFact(
                    for: localClothing,
                    entries: localFinalPaymentEntries
                  ) else {
                return false
            }

            WealthSavingLedger.markFinalPaymentCompleted(cloudClothing, at: date)
            return true
        }

        static func shouldSkipMigratingDuplicateFinalPayment(
            _ source: WealthSavingEntry,
            existingEntries: [WealthSavingEntry]
        ) -> Bool {
            guard WealthSavingLedger.isFinalPaymentRecord(source),
                  let clothingID = source.clothingID else {
                return false
            }

            return existingEntries.contains { existing in
                isSameMigratedFinalPaymentFact(source, existing, clothingID: clothingID)
            }
        }

        private static func isSameMigratedFinalPaymentFact(
            _ source: WealthSavingEntry,
            _ existing: WealthSavingEntry,
            clothingID: UUID
        ) -> Bool {
            guard WealthSavingLedger.isFinalPaymentRecord(existing),
                  existing.clothingID == clothingID,
                  FinancialDataSanitizer.money(existing.amount) == FinancialDataSanitizer.money(source.amount) else {
                return false
            }

            if let sourcePaidAt = source.paidAt,
               let existingPaidAt = existing.paidAt {
                return sourcePaidAt == existingPaidAt
            }

            let sourceEventDate = source.paidAt ?? source.createdAt
            let existingEventDate = existing.paidAt ?? existing.createdAt
            guard sourceEventDate == existingEventDate else { return false }

            return normalized(source.note) == normalized(existing.note)
                && normalized(source.migrationSource) == normalized(existing.migrationSource)
        }

        private static func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func normalized(_ value: String?) -> String {
            normalized(value ?? "")
        }
    }
}

// MARK: - Helper Extensions

// CKContainer.userRecordID() 扩展定义在 NoticeService.swift 中
