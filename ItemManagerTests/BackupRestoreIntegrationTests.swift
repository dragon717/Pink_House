//
//  BackupRestoreIntegrationTests.swift
//  ItemManagerTests
//
//  Created by Pink House Dev on 1/26/26.
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
            Clothing.self, Brand.self, Tag.self, StoredImage.self, CutoutItem.self, Outfit.self, OutfitItem.self
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
        context.insert(clothing)
        
        // 创建裁剪图
        let cutout = CutoutItem(originalImageHash: "hash123", category: "Skirt", imagePath: "cutout.png", width: 100, height: 100)
        cutout.linkedClothing = clothing
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
        try context.delete(model: Brand.self)
        try context.delete(model: Tag.self)
        try context.delete(model: CutoutItem.self)
        try context.delete(model: StoredImage.self)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Clothing>()).count, 0)
        print("Test: Environment cleared.")
        
        // 4. 执行恢复
        try BackupService.shared.importBackup(from: exportURL, context: context)
        print("Test: Import call finished.")
        
        // 5. 验证模型恢复
        let clothings = try context.fetch(FetchDescriptor<Clothing>())
        XCTAssertEqual(clothings.count, 1)
        let restoredClothing = clothings.first!
        XCTAssertEqual(restoredClothing.name, "Integration Test Skirt")
        
        // 6. 验证关系恢复
        XCTAssertEqual(restoredClothing.brand?.name, "Test Brand")
        XCTAssertEqual(restoredClothing.tags?.first?.name, "Test Tag")
        
        // 7. 验证裁剪图关联
        let cutouts = try context.fetch(FetchDescriptor<CutoutItem>())
        XCTAssertEqual(cutouts.count, 1)
        XCTAssertEqual(cutouts.first?.linkedClothing?.id, restoredClothing.id)
        
        print("Test: All assertions passed!")
        
        // 清理临时备份文件
        try? FileManager.default.removeItem(at: exportURL)
    }
}
