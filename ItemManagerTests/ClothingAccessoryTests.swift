
import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ClothingAccessoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema([
            Clothing.self, Brand.self, Tag.self, StoredImage.self, CutoutItem.self, Outfit.self, OutfitItem.self, AccessoryItem.self
        ]), configurations: config)
        context = container.mainContext
    }
    
    override func tearDownWithError() throws {
        container = nil
        context = nil
    }
    
    func testAccessoryItemCreationAndCalculation() throws {
        // 1. 创建 Clothing
        let clothing = Clothing(name: "Test Dress")
        context.insert(clothing)
        
        // 2. 创建 AccessoryItem
        let acc1 = AccessoryItem(name: "Bow", price: 100.0, deposit: 30.0, balance: 70.0, sortIndex: 0)
        let acc2 = AccessoryItem(name: "Socks", price: 50.0, deposit: 0.0, balance: 0.0, sortIndex: 1)
        
        clothing.accessoryItems = [acc1, acc2]
        try context.save()
        
        // 3. 验证数据持久化
        let fetchedClothing = try context.fetch(FetchDescriptor<Clothing>()).first
        XCTAssertNotNil(fetchedClothing)
        XCTAssertEqual(fetchedClothing?.accessoryItems?.count, 2)
        
        let fetchedAcc1 = fetchedClothing?.accessoryItems?.first(where: { $0.name == "Bow" })
        XCTAssertEqual(fetchedAcc1?.price, 100.0)
        XCTAssertEqual(fetchedAcc1?.deposit, 30.0)
        XCTAssertEqual(fetchedAcc1?.balance, 70.0)
        
        // 4. 模拟 UI 中的自动计算逻辑 (虽然这是 ViewModel/View 的逻辑，但也值得在这里验证数据模型是否支持)
        if let acc = fetchedAcc1 {
            let newDeposit: Decimal = 40.0
            let newBalance: Decimal = 60.0
            acc.deposit = newDeposit
            acc.balance = newBalance
            // UI逻辑: price = deposit + balance
            acc.price = newDeposit + newBalance
            
            XCTAssertEqual(acc.price, 100.0)
        }
    }
}
