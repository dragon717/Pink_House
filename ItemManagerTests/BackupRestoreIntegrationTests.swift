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
            Clothing.self, WealthSavingEntry.self, Brand.self, Tag.self, StoredImage.self, CutoutItem.self, Outfit.self, OutfitItem.self, AccessoryItem.self
        ]), configurations: config)
        context = container.mainContext
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
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
        
        // Add Accessory Items
        let acc1 = AccessoryItem(name: "Test Acc 1", price: 100.0, deposit: 30.0, balance: 70.0, sortIndex: 0)
        let acc2 = AccessoryItem(name: "Test Acc 2", price: 50.0, deposit: 0.0, balance: 0.0, sortIndex: 1)
        clothing.accessoryItems = [acc1, acc2]
        
        context.insert(clothing)

        let savingAmount = Decimal(string: "123.45")!
        let savingEntry = WealthSavingEntry(amount: savingAmount, clothingID: clothing.id, note: "备份测试小金库")
        context.insert(savingEntry)
        
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

        let restoredSavingEntries = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(restoredSavingEntries.count, 1)
        XCTAssertEqual(restoredSavingEntries.first?.id, savingEntry.id)
        XCTAssertEqual(restoredSavingEntries.first?.clothingID, restoredClothing.id)
        XCTAssertEqual(restoredSavingEntries.first?.amount, savingAmount)

        try await BackupService.shared.importBackup(from: exportURL, context: context)
        let restoredSavingEntriesAfterSecondImport = try context.fetch(FetchDescriptor<WealthSavingEntry>())
        XCTAssertEqual(restoredSavingEntriesAfterSecondImport.count, 1, "重复恢复同一备份不应重复累加小金库存款")
        
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
}
