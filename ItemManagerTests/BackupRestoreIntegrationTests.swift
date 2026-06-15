//
//  BackupRestoreIntegrationTests.swift
//  ItemManagerTests
//
//  Created by 少女心愿 Dev on 1/26/26.
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class BackupRestoreIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUpWithError() throws {
        // 使用内存数据库
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema([
            Clothing.self,
            WealthSavingEntry.self,
            Item.self,
            Tag.self,
            Brand.self,
            AccessoryItem.self,
            StoredImage.self,
            CutoutItem.self,
            Outfit.self,
            OutfitItem.self,
            BookGroup.self,
            SpaceBookGroup.self,
            SpaceOutfit.self,
            SceneObjectData.self,
            Model3D.self,
            PerlerBeadPattern.self,
            Notice.self,
            ClothingImageSyncRecord.self,
            DepositNotificationRecord.self,
            DepositNotificationSettings.self
        ]), configurations: config)
        context = container.mainContext
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testWealthAggregateSanitizesNegativeImportedFinancialValues() throws {
        let negativeStockClothing = Clothing(
            name: "Dirty Negative Stock OP",
            price: 200,
            stock: 1
        )
        negativeStockClothing.stock = -3
        context.insert(negativeStockClothing)

        let negativeDepositClothing = Clothing(name: "Dirty Deposit JSK")
        negativeDepositClothing.price = -100
        negativeDepositClothing.deposit = -40
        negativeDepositClothing.balance = -60
        negativeDepositClothing.shippingFee = -20
        negativeDepositClothing.isDepositPlan = true
        negativeDepositClothing.stock = -2
        context.insert(negativeDepositClothing)

        let negativeSavingEntry = WealthSavingEntry(
            amount: 1,
            clothingID: nil,
            note: "导入脏数据负数历史财富记录"
        )
        negativeSavingEntry.amount = -999
        context.insert(negativeSavingEntry)
        try context.save()

        let clothings = try context.fetch(FetchDescriptor<Clothing>())
        let savingEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        let total = WealthViewModel.calculateBaseAmountCNY(
            clothings: clothings,
            wealthSavingEntries: savingEntries
        )

        XCTAssertGreaterThanOrEqual(total, 0, "负金额/负库存导入样本经过来财聚合兜底后不应产生负数")
    }

    func testWealthDisplayAmountClampsNegativeBaseAmount() {
        XCTAssertEqual(
            WealthViewModel.displayAmount(
                baseAmountCNY: -123,
                currency: .rmb,
                exchangeRateJPY: 21,
                exchangeRateUSD: 0.14
            ),
            0
        )
        XCTAssertEqual(
            WealthViewModel.displayAmount(
                baseAmountCNY: -123,
                currency: .jpy,
                exchangeRateJPY: 21,
                exchangeRateUSD: 0.14
            ),
            0
        )
    }

    func testWealthAggregateUsesWardrobeTotalValueForReservations() {
        let owned = Clothing(
            name: "Owned JSK",
            price: 100,
            accessoriesPrice: 20,
            shippingFee: 10,
            stock: 2
        )
        let finalPayment = Clothing(
            name: "Final Payment JSK",
            price: 1_000,
            deposit: 200,
            balance: 800,
            accessoriesPrice: 100,
            shippingFee: 30,
            isDepositPlan: true,
            stock: 2
        )
        let fullPaymentReservation = Clothing(
            name: "Full Payment Reservation OP",
            price: 1_000,
            deposit: 1_130,
            balance: 0,
            accessoriesPrice: 100,
            shippingFee: 30,
            isDepositPlan: true,
            stock: 2
        )

        XCTAssertEqual(WealthViewModel.sanitizedWardrobeContribution(for: owned), 230)
        XCTAssertEqual(WealthViewModel.sanitizedWardrobeContribution(for: finalPayment), 2_130)
        XCTAssertEqual(WealthViewModel.sanitizedWardrobeContribution(for: fullPaymentReservation), 2_260)

        let total = WealthViewModel.calculateBaseAmountCNY(
            clothings: [owned, finalPayment, fullPaymentReservation]
        )

        XCTAssertEqual(total, 4_620)
    }

    func testWealthDisplayAmountRoundsConvertedCurrencyAmounts() {
        XCTAssertEqual(
            WealthViewModel.displayAmount(
                baseAmountCNY: 99,
                currency: .rmb,
                exchangeRateJPY: 22.5,
                exchangeRateUSD: 0.14
            ),
            99
        )
        XCTAssertEqual(
            WealthViewModel.displayAmount(
                baseAmountCNY: 99,
                currency: .jpy,
                exchangeRateJPY: 22.5,
                exchangeRateUSD: 0.14
            ),
            2_228
        )
        XCTAssertEqual(
            WealthViewModel.displayAmount(
                baseAmountCNY: 99,
                currency: .usd,
                exchangeRateJPY: 22.5,
                exchangeRateUSD: 0.14
            ),
            14
        )
    }
    
    func testFullBackupRestoreCycle() async throws {
        // 1. 准备复杂的测试数据
        let brand = Brand(name: "Test Brand", colorHex: "#FF0000")
        context.insert(brand)
        
        let tag = Tag(name: "Test Tag", colorHex: "#00FF00")
        context.insert(tag)
        
        // 创建一个模拟 StoredImage
        let img = StoredImage(imageHash: "hash123", fileName: "test_image.jpg")
        context.insert(img)
        
        let clothing = Clothing(name: "Integration Test Skirt")
        clothing.brand = brand
        clothing.tags = [tag]
        clothing.imagePaths = ["test_image.jpg"]
        clothing.note = "这是用于备份恢复验证的备注"
        let expectedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedLastModified = Date(timeIntervalSince1970: 1_700_000_123)
        clothing.updatedAt = expectedUpdatedAt
        clothing.lastModified = expectedLastModified
        clothing.isDepositPlan = true
        clothing.deposit = 100
        clothing.balance = 400
        clothing.finalPaymentInstallmentCount = 0
        
        // Add Accessory Items
        let acc1 = AccessoryItem(name: "Test Acc 1", price: 100.0, deposit: 30.0, balance: 70.0, sortIndex: 0)
        let acc2 = AccessoryItem(name: "Test Acc 2", price: 50.0, deposit: 0.0, balance: 0.0, sortIndex: 1)
        clothing.accessoryItems = [acc1, acc2]
        
        context.insert(clothing)

        let savingAmount = Decimal(string: "123.45")!
        let savingEntry = WealthSavingEntry(amount: savingAmount, clothingID: clothing.id, note: "备份测试历史财富记录")
        context.insert(savingEntry)

        let paymentEntry = WealthSavingEntry(
            amount: 120,
            clothingID: clothing.id,
            note: "备份测试尾款",
            entryKind: .finalPayment,
            paidAt: Date(timeIntervalSince1970: 1_700_000_222)
        )
        context.insert(paymentEntry)
        
        // 创建裁剪图
        let cutout = CutoutItem(originalImageHash: "hash123", category: "Skirt", imagePath: "cutout.png", width: 100, height: 100)
        cutout.linkedClothingID = clothing.id
        context.insert(cutout)
        
        try context.save()
        print("Test Setup: Data created and saved.")
        
        // 2. 导出备份
        // 注意：由于单元测试环境没有真实的 Image 目录，我们预期 export 可能会在文件 IO 处报错或我们需要 Mock
        // 这里我们主要测试数据结构的导出和导入
        
        let exportURL = try await BackupService.shared.exportBackup(container: container)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        print("Test: Export successful at \(exportURL.path)")
        
        // 3. 清空上下文 (模拟删除应用或切换环境)
        try context.delete(model: Clothing.self)
        try context.delete(model: WealthSavingEntry.self)
        try context.delete(model: Brand.self)
        try context.delete(model: Tag.self)
        try context.delete(model: CutoutItem.self)
        try context.delete(model: StoredImage.self)
        try context.delete(model: AccessoryItem.self)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Clothing>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WealthSavingEntry>()).count, 0)
        print("Test: Environment cleared.")
        
        // 4. 执行恢复
        try await BackupService.shared.importBackup(from: exportURL, context: context)
        print("Test: Import call finished.")
        
        // 5. 验证模型恢复
        let clothings = try context.fetch(FetchDescriptor<Clothing>())
        XCTAssertEqual(clothings.count, 1)
        let restoredClothing = clothings.first!
        XCTAssertEqual(restoredClothing.name, "Integration Test Skirt")
        XCTAssertEqual(restoredClothing.note, "这是用于备份恢复验证的备注")
        XCTAssertEqual(restoredClothing.updatedAt, expectedUpdatedAt)
        XCTAssertEqual(restoredClothing.lastModified, expectedLastModified)
        XCTAssertTrue(restoredClothing.isDepositPlan)
        XCTAssertEqual(restoredClothing.finalPaymentInstallmentCount, 0)

        let restoredSavingEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(restoredSavingEntries.count, 2)
        let restoredSavingEntry = restoredSavingEntries.first { $0.id == savingEntry.id }
        XCTAssertEqual(restoredSavingEntry?.clothingID, restoredClothing.id)
        XCTAssertEqual(restoredSavingEntry?.amount, savingAmount)
        let restoredPaymentEntry = restoredSavingEntries.first { $0.id == paymentEntry.id }
        XCTAssertEqual(restoredPaymentEntry?.kind, .finalPayment)
        XCTAssertNil(restoredPaymentEntry?.finalPaymentMode)
        XCTAssertEqual(restoredPaymentEntry?.installmentIndex, 0)
        XCTAssertEqual(restoredPaymentEntry?.installmentCount, 0)

        try await BackupService.shared.importBackup(from: exportURL, context: context)
        let restoredSavingEntriesAfterSecondImport = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(restoredSavingEntriesAfterSecondImport.count, 2, "重复恢复同一备份不应重复累加历史财富记录/尾款账单")
        
        // 6. 验证关系恢复
        XCTAssertEqual(restoredClothing.brand?.name, "Test Brand")
        XCTAssertEqual(restoredClothing.tags?.first?.name, "Test Tag")
        
        // 7. 验证裁剪图关联
        let cutouts = try context.fetch(FetchDescriptor<CutoutItem>())
        XCTAssertEqual(cutouts.count, 1)
        XCTAssertEqual(cutouts.first?.linkedClothingID, restoredClothing.id)
        
        // 7.1 验证 CutoutItem 图片的 StoredImage 记录是否正确恢复
        let restoredCutout = cutouts.first!
        let restoredCutoutImagePath = restoredCutout.imagePath
        let storedImageDescriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.fileName == restoredCutoutImagePath })
        let storedImages = try context.fetch(storedImageDescriptor)
        XCTAssertEqual(storedImages.count, 1, "CutoutItem 图片应该有对应的 StoredImage 记录")
        XCTAssertGreaterThanOrEqual(storedImages.first!.refCount, 1, "StoredImage 的 refCount 应该至少为 1")
        
        // 8. 验证小物恢复
        XCTAssertNotNil(restoredClothing.accessoryItems)
        let restoredAccessories = restoredClothing.accessoryItems!.sorted(by: { $0.sortIndex < $1.sortIndex })
        XCTAssertEqual(restoredAccessories.count, 2)
        
        let rAcc1 = restoredAccessories[0]
        XCTAssertEqual(rAcc1.name, "Test Acc 1")
        XCTAssertEqual(rAcc1.deposit, 30.0)
        XCTAssertEqual(rAcc1.balance, 70.0)
        XCTAssertEqual(rAcc1.price, 100.0)
        
        let rAcc2 = restoredAccessories[1]
        XCTAssertEqual(rAcc2.name, "Test Acc 2")
        XCTAssertEqual(rAcc2.deposit, 0.0)
        
        print("Test: All assertions passed!")
        
        // 清理临时备份文件
        try? FileManager.default.removeItem(at: exportURL)
    }

    func testOOTDRestoreKeepsFlatPagesInOriginalBooks() throws {
        let date = Date(timeIntervalSince1970: 1_700_100_000)
        let defaultBookID = UUID()
        let bookAID = UUID()
        let bookBID = UUID()

        let bookGroups = [
            BookGroupDTO(id: defaultBookID, title: "默认手帐", coverImage: nil, createdAt: date, isDeleted: false, deletedAt: nil, sortIndex: 0, lastModified: date),
            BookGroupDTO(id: bookAID, title: "旅行手帐", coverImage: nil, createdAt: date, isDeleted: false, deletedAt: nil, sortIndex: 1, lastModified: date),
            BookGroupDTO(id: bookBID, title: "茶会手帐", coverImage: nil, createdAt: date, isDeleted: false, deletedAt: nil, sortIndex: 2, lastModified: date)
        ]

        let snapshots = [
            makeSnapshot(note: "少女魔法贴", bookID: defaultBookID, sortSeed: 0, date: date),
            makeSnapshot(note: "旅行第一页", bookID: bookAID, sortSeed: 1, date: date),
            makeSnapshot(note: "旅行第二页", bookID: bookAID, sortSeed: 2, date: date),
            makeSnapshot(note: "茶会第一页", bookID: bookBID, sortSeed: 3, date: date)
        ]

        let manifest = makeOOTDManifest(bookGroups: bookGroups, snapshots: snapshots, date: date)

        try BackupService.shared.restoreFromManifest(manifest: manifest, imageFiles: [:], context: context)

        var restoredBooks = try context.fetch(FetchDescriptor<BookGroup>())
        var restoredOutfits = try context.fetch(FetchDescriptor<Outfit>())
        XCTAssertEqual(restoredBooks.count, 3)
        XCTAssertEqual(restoredOutfits.count, 4)
        XCTAssertEqual(bookTitle(for: "旅行第一页", in: restoredOutfits), "旅行手帐")
        XCTAssertEqual(bookTitle(for: "旅行第二页", in: restoredOutfits), "旅行手帐")
        XCTAssertEqual(bookTitle(for: "茶会第一页", in: restoredOutfits), "茶会手帐")
        XCTAssertEqual(bookTitle(for: "少女魔法贴", in: restoredOutfits), "默认手帐")
        XCTAssertTrue(restoredOutfits.allSatisfy { $0.book != nil }, "新格式 snapshot 带 bookID 时不应产生孤儿书页")

        let report = OOTDOrphanPageRepairService.repairPlanarOrphans(
            context: context,
            activeBooks: restoredBooks,
            allOutfits: restoredOutfits,
            source: "unit-test"
        )
        XCTAssertEqual(report.scannedOrphans, 0)
        XCTAssertEqual(report.movedToDefaultBook, 0)

        try BackupService.shared.restoreFromManifest(manifest: manifest, imageFiles: [:], context: context)
        restoredBooks = try context.fetch(FetchDescriptor<BookGroup>())
        restoredOutfits = try context.fetch(FetchDescriptor<Outfit>())
        XCTAssertEqual(restoredBooks.count, 3, "重复恢复同一备份不应重复创建手帐")
        XCTAssertEqual(restoredOutfits.count, 4, "重复恢复同一备份不应重复创建书页")
        XCTAssertEqual(bookTitle(for: "茶会第一页", in: restoredOutfits), "茶会手帐")
    }

    func testOOTDOrphanRepairDoesNotMoveAmbiguousPagesWhenUserBooksExist() throws {
        let defaultBook = BookGroup(title: "默认手帐", sortIndex: 0)
        let userBook = BookGroup(title: "旅行手帐", sortIndex: 1)
        let ambiguousPage = Outfit(note: "未归属旅行页", canvasType: "blank", book: nil)
        let magicPage = Outfit(note: "少女魔法贴", canvasType: "blank", book: nil)

        context.insert(defaultBook)
        context.insert(userBook)
        context.insert(ambiguousPage)
        context.insert(magicPage)
        try context.save()

        let report = OOTDOrphanPageRepairService.repairPlanarOrphans(
            context: context,
            activeBooks: [defaultBook, userBook],
            allOutfits: [ambiguousPage, magicPage],
            source: "unit-test"
        )

        XCTAssertEqual(report.scannedOrphans, 2)
        XCTAssertEqual(report.movedToDefaultBook, 1)
        XCTAssertEqual(report.deferredAmbiguousOrphans, 1)
        XCTAssertNil(ambiguousPage.book, "多手帐场景中无归属证据的孤儿页不应自动塞进默认手帐")
        XCTAssertEqual(magicPage.book?.id, defaultBook.id, "魔法贴纸专用页仍允许回默认手帐")
    }

    func testOOTDSnapshotDTOMannequinAssetIDIsBackwardCompatible() throws {
        let oldSnapshotJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "createdAt": 0,
          "note": "旧人台书页",
          "snapshotPath": null,
          "canvasType": "mannequin",
          "backgroundImagePath": null,
          "bookID": null,
          "items": [],
          "lastModified": null,
          "isDeleted": null,
          "deletedAt": null
        }
        """

        let oldDTO = try JSONDecoder().decode(OOTDSnapshotDTO.self, from: Data(oldSnapshotJSON.utf8))
        XCTAssertNil(oldDTO.mannequinAssetID)
        XCTAssertEqual(oldDTO.canvasType, "mannequin")

        let newSnapshotJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "createdAt": 0,
          "note": "新人台书页",
          "snapshotPath": null,
          "canvasType": "mannequin",
          "backgroundImagePath": null,
          "mannequinAssetID": "ootd_mannequin_default",
          "bookID": null,
          "items": [],
          "lastModified": null,
          "isDeleted": null,
          "deletedAt": null
        }
        """

        let newDTO = try JSONDecoder().decode(OOTDSnapshotDTO.self, from: Data(newSnapshotJSON.utf8))
        XCTAssertEqual(newDTO.mannequinAssetID, "ootd_mannequin_default")
    }

    private func makeSnapshot(note: String, bookID: UUID, sortSeed: Int, date: Date) -> OOTDSnapshotDTO {
        OOTDSnapshotDTO(
            id: UUID(),
            createdAt: date.addingTimeInterval(TimeInterval(sortSeed)),
            note: note,
            snapshotPath: nil,
            canvasType: "blank",
            backgroundImagePath: nil,
            mannequinAssetID: nil,
            bookID: bookID,
            items: [],
            lastModified: date,
            isDeleted: false,
            deletedAt: nil
        )
    }

    private func makeOOTDManifest(
        bookGroups: [BookGroupDTO],
        snapshots: [OOTDSnapshotDTO],
        date: Date
    ) -> BackupManifest {
        BackupManifest(
            formatVersion: BackupFormatVersion.current.rawValue,
            timestamp: date,
            deviceName: "Unit Test",
            brands: [],
            tags: [],
            clothings: [],
            wealthSavingEntries: [],
            storedImages: [],
            cutouts: [],
            outfits: nil,
            snapshots: snapshots,
            appSettings: nil,
            themeFiles: nil,
            wealthFiles: nil,
            hasWidgetBackground: false,
            hasSmallWidgetBackground: false,
            hasMediumWidgetBackground: false,
            hasLargeWidgetBackground: false,
            externalFileHashes: nil,
            petStatusData: nil,
            chatHistoryData: nil,
            appVersion: "test",
            bookGroups: bookGroups,
            spaceBookGroups: [],
            spaceOutfits: [],
            model3Ds: [],
            userProfile: nil,
            userAvatarFile: nil,
            perlerBeadPatterns: [],
            featureStatuses: nil,
            unlockConditions: nil,
            checkInRecords: nil,
            checkInStats: nil,
            themeColorConfig: nil,
            clothingCount: 0,
            imageCount: 0,
            outfitCount: snapshots.count,
            bookGroupCount: bookGroups.count,
            spaceBookGroupCount: 0,
            spaceOutfitCount: 0,
            model3DCount: 0,
            perlerBeadPatternCount: 0
        )
    }

    private func bookTitle(for note: String, in outfits: [Outfit]) -> String? {
        outfits.first { $0.note == note }?.book?.title
    }
}
