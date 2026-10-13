import XCTest
@testable import ItemManager

@MainActor
final class WardrobeStorageInventoryTests: XCTestCase {
    func testExplicitDressTypeWinsOverShoeName() {
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "小白鞋与猫咪 JSK", types: "JSK"), .wardrobe)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "短靴", types: "鞋"), .shoes)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "蕾丝玛丽珍", types: "小物"), .shoes)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "我的收藏"), .wardrobe)
    }

    func testSetUsesMainGarmentAndDoesNotDuplicateItsDetailItems() {
        let dress = Clothing(name: "樱花 JSK＋包＋礼帽（套装）", types: "JSK,小物", accessories: "包,礼帽")
        let bag = AccessoryItem(name: "玫瑰包", price: 260, imagePaths: ["bag.png"])
        dress.accessoryItems = [bag, AccessoryItem(name: "蕾丝礼帽", price: 100)]
        bag.clothing = dress
        let standaloneBag = Clothing(name: "单独收藏", types: "小物", accessories: "包")
        let entries = WardrobeStorageInventory.entries(clothings: [dress, standaloneBag])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.category, .wardrobe)
        XCTAssertEqual(entries.last?.category, .bags)
        XCTAssertFalse(entries.contains { $0.category == .accessories })
        XCTAssertEqual(dress.accessoryItems?.count, 2, "只改变展示归属，不拆分或改写套装")
        XCTAssertEqual(bag.imagePaths, ["bag.png"])
    }

    func testDeletedAreExcludedAndReservationHistoryRemainsReachableInCabinet() {
        let deleted = Clothing(name: "删除鞋", types: "鞋")
        deleted.isDeleted = true
        let recycled = Clothing(name: "回收鞋", types: "鞋")
        recycled.deletedAt = Date()
        let sold = Clothing(name: "售出鞋", types: "鞋", status: .offShelf)
        let future = Clothing(name: "预约鞋", types: "鞋")
        future.isDepositPlan = true
        future.accessoryItems = [AccessoryItem(name: "预约靴子", price: 100)]
        let entries = WardrobeStorageInventory.entries(clothings: [deleted, recycled, sold, future])
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.category == .shoes && $0.quantity == 0 && $0.statusLabel != nil })
        XCTAssertEqual(Set(entries.map(\.title)), ["售出鞋", "预约鞋"])
    }

    func testNewestLinkedCutoutIsUsedWithoutChangingItsMetadata() {
        let shoes = Clothing(name: "白色运动鞋", types: "鞋", imagePaths: ["photo.jpg"])
        let older = CutoutItem(originalImageHash: "older", category: "鞋子", imagePath: "older.png", width: 200, height: 200,
                               linkedClothingID: shoes.id, clothingName: shoes.name)
        let newer = CutoutItem(originalImageHash: "newer", category: "鞋子", imagePath: "newer.png", width: 200, height: 200,
                               linkedClothingID: shoes.id, clothingName: shoes.name)
        older.timestamp = Date(timeIntervalSince1970: 1)
        newer.timestamp = Date(timeIntervalSince1970: 2)
        let entries = WardrobeStorageInventory.entries(clothings: [shoes], cutouts: [older, newer])
        XCTAssertEqual(entries.first?.cutoutImagePath, "newer.png")
        XCTAssertEqual(newer.clothingName, shoes.name)
        XCTAssertEqual(newer.linkedClothingID, shoes.id)
        XCTAssertNil(shoes.replacedCutoutID)
    }

    func testShoeFiltersAndEmptyInventoryNeverCreateDemonstrationItems() {
        XCTAssertTrue(WardrobeShoeFilter.whiteSneakers.matches("白色运动鞋"))
        XCTAssertFalse(WardrobeShoeFilter.whiteSneakers.matches("白色蕾丝靴子"))
        XCTAssertTrue(WardrobeShoeFilter.boots.matches("蕾丝短靴"))
        XCTAssertEqual(WardrobeStorageCategory.defaultCategories, [.wardrobe, .shoes, .bags, .accessories])
        XCTAssertTrue(WardrobeStorageInventory.entries(clothings: []).isEmpty)
    }

    func testBagTagWinsOverBroadAccessoryTypeButNeverOverMainGarment() {
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "收藏 01", types: "小物", accessories: "包,KC"), .bags)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "小白鞋图案包", types: "小物", accessories: "包,小白鞋图案包"), .bags)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "收藏 02", accessories: "KC"), .accessories)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "整套", types: "小物，jSk", accessories: "包,礼帽"), .wardrobe)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "整套", types: "ＯＰ / 小物", accessories: "包"), .wardrobe)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "礼帽", types: "小物"), .accessories)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "收藏", types: "美妆"), .wardrobe)
        XCTAssertEqual(WardrobeStorageCategory.classify(name: "收藏", types: "生活"), .wardrobe)
    }

    func testHomeFilterAndCabinetsPartitionRecordsWithoutDuplicatingSet() {
        let dress = Clothing(name: "JSK＋包＋礼帽（套装）", types: "JSK,小物", accessories: "包,KC")
        dress.accessoryItems = [AccessoryItem(name: "礼帽", price: 20)]
        let items = [dress, Clothing(name: "鞋履", types: "鞋"),
                     Clothing(name: "收藏包", types: "小物", accessories: "包"),
                     Clothing(name: "礼帽", types: "小物"), Clothing(name: "香水", types: "美妆"),
                     Clothing(name: "玩偶", types: "生活")]
        let input = WardrobeFilterInput(snapshots: items.map(WardrobeClothingSnapshot.init(clothing:)),
                                       searchText: "", selectedTagIDs: [], selectedBrandIDs: [],
                                       selectedTypes: [], selectedColors: [], selectedSizes: [],
                                       selectedLengths: [], selectedConditions: [], selectedAccessories: [],
                                       depositStatusFilterRawValue: "all", sortOptionRawValue: "")
        let home = WardrobeFilterEngine.evaluate(input)
        let cabinets = WardrobeStorageInventory.entries(clothings: items).filter { $0.category != .wardrobe }
        XCTAssertEqual(Set(home.ids), Set([dress.id, items[4].id, items[5].id]))
        XCTAssertEqual(home.stats.styleCount, 3)
        XCTAssertEqual(cabinets.count, 3)
        XCTAssertTrue(Set(home.ids).isDisjoint(with: cabinets.compactMap { $0.clothing?.id }))
        XCTAssertEqual(Set(home.ids + cabinets.compactMap { $0.clothing?.id }), Set(items.map(\.id)))
    }
}
