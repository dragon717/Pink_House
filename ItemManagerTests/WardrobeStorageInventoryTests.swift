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
    func testCabinetsIntersectHomepageTagAndShopFiltersAndRestoreAll() {
        let pinkHouse = Brand(name: "PINK HOUSE")
        let other = Brand(name: "Other")
        let favorite = Tag(name: "心动")
        let matching = Clothing(name: "鞋", types: "鞋")
        matching.brand = pinkHouse
        matching.tags = [favorite]
        let wrongShop = Clothing(name: "包", types: "包")
        wrongShop.brand = other
        wrongShop.tags = [favorite]
        let wrongTag = Clothing(name: "帽", types: "小物")
        wrongTag.brand = pinkHouse
        let items = [matching, wrongShop, wrongTag]
        let config = ClothingFilterService.FilterConfig(selectedTagIDs: [favorite.id], selectedBrandIDs: [pinkHouse.id])
        let filtered = ClothingFilterService.filter(items, config: config)
        let entries = WardrobeStorageInventory.entries(clothings: filtered)
        XCTAssertEqual(entries.compactMap { $0.clothing?.id }, [matching.id])
        XCTAssertEqual(entries.reduce(0) { $0 + $1.quantity }, max(matching.stock, 1))
        XCTAssertEqual(WardrobeStorageInventory.entries(clothings: ClothingFilterService.filter(items, config: .init())).count, 3)
        XCTAssertTrue(ClothingFilterService.filter(items, config: .init(selectedBrandIDs: [UUID()])).isEmpty)
    }

    func testShopPriorityGroupsOtherShopsAndMatchesHomepageEngine() {
        let pinkHouse = Brand(name: "PINK HOUSE")
        let alice = Brand(name: "Alice")
        let baby = Brand(name: "Baby")
        func dress(_ name: String, _ shop: Brand?, _ time: TimeInterval) -> Clothing {
            let item = Clothing(name: name, types: "JSK")
            item.brand = shop
            item.createdAt = Date(timeIntervalSince1970: time)
            return item
        }
        let pinkOld = dress("P旧", pinkHouse, 1)
        let pinkNew = dress("P新", pinkHouse, 2)
        let aliceOld = dress("A旧", alice, 3)
        let aliceNew = dress("A新", alice, 5)
        let babyDress = dress("B", baby, 4)
        let unknown = dress("无店家", nil, 6)
        let items = [unknown, babyDress, pinkOld, aliceOld, pinkNew, aliceNew]
        let expected = [pinkNew, pinkOld, aliceNew, aliceOld, babyDress, unknown].map(\.id)
        XCTAssertEqual(ClothingFilterService.sortByBrand(items, preferredBrandID: pinkHouse.id.uuidString).map(\.id), expected)
        let input = WardrobeFilterInput(snapshots: items.map(WardrobeClothingSnapshot.init(clothing:)),
                                       searchText: "", selectedTagIDs: [], selectedBrandIDs: [],
                                       selectedTypes: [], selectedColors: [], selectedSizes: [],
                                       selectedLengths: [], selectedConditions: [], selectedAccessories: [],
                                       depositStatusFilterRawValue: "all", preferredBrandID: pinkHouse.id.uuidString,
                                       sortOptionRawValue: SortOption.brand.rawValue)
        XCTAssertEqual(WardrobeFilterEngine.evaluate(input).ids, expected)
        let alphabetical = ClothingFilterService.sortByBrand(items, preferredBrandID: "").map(\.id)
        XCTAssertEqual(alphabetical, [aliceNew, aliceOld, babyDress, pinkNew, pinkOld, unknown].map(\.id))
        XCTAssertEqual(ClothingFilterService.sortByBrand(items, preferredBrandID: UUID().uuidString).map(\.id), alphabetical)
    }

    func testPreparedIndexMatchesLiveFiltersAcrossShopTagAndStatusCombinations() {
        let shop = Brand(name: "仲夏物语")
        let tag = Tag(name: "心动")
        let dress = Clothing(name: "裙", types: "JSK", price: 100)
        dress.brand = shop; dress.tags = [tag]
        let plain = Clothing(name: "无标签", types: "OP", price: 80)
        let reserved = Clothing(name: "预约裙", types: "JSK", price: 200, isDepositPlan: true)
        reserved.brand = shop
        let shoes = Clothing(name: "鞋", types: "鞋")
        shoes.brand = shop; shoes.tags = [tag]
        let items = [dress, plain, reserved, shoes]
        let values = items.map(WardrobeClothingSnapshot.init(clothing:))
        let index = WardrobeFilterIndex(snapshots: values, cabinets: [])
        for status in DepositStatusFilter.allCases {
            for brands: Set<UUID> in [[], [shop.id], [ClothingFilterService.noBrandUUID], [UUID()]] {
                for tags: Set<UUID> in [[], [tag.id], [ClothingFilterService.noTagUUID]] {
                    let live = ClothingFilterService.filter(items, config: .init(
                        selectedTagIDs: tags, selectedBrandIDs: brands, depositStatusFilter: status))
                        .filter { WardrobeStorageCategory.classify(name: $0.name, types: $0.types) == .wardrobe }
                    let input = WardrobeFilterInput(snapshots: [], searchText: "", selectedTagIDs: tags,
                        selectedBrandIDs: brands, selectedTypes: [], selectedColors: [], selectedSizes: [],
                        selectedLengths: [], selectedConditions: [], selectedAccessories: [],
                        depositStatusFilterRawValue: status.rawValue, sortOptionRawValue: "添加时间从晚到早")
                    XCTAssertEqual(Set(WardrobeFilterEngine.evaluate(input, index: index).ids), Set(live.map(\.id)))
                }
            }
        }
        // Editing relationships must be reflected after invalidating/rebuilding the value index.
        dress.brand = nil
        let refreshed = WardrobeFilterIndex(snapshots: items.map(WardrobeClothingSnapshot.init(clothing:)), cabinets: [])
        XCTAssertEqual(Set(refreshed.candidates(brandIDs: [shop.id], tagIDs: []).map(\.id)), [reserved.id])
        XCTAssertEqual(Set(index.candidates(brandIDs: [shop.id], tagIDs: []).map(\.id)), [dress.id, reserved.id])
    }

}
