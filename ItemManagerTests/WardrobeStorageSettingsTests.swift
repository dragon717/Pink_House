import XCTest
import SwiftUI
@testable import ItemManager

@MainActor
final class WardrobeStorageSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: WardrobeStorageSettings!

    override func setUpWithError() throws {
        suite = "wardrobe-storage-settings-tests-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings = WardrobeStorageSettings(defaults: defaults)
    }
    override func tearDownWithError() throws { defaults.removePersistentDomain(forName: suite) }

    func testNewInstallHasFourDefaultDestinationsAndNoSampleInventory() {
        XCTAssertEqual(settings.destinations.map(\.id), ["wardrobe", "shoes", "bags", "accessories"])
        XCTAssertTrue(settings.cabinets.isEmpty)
        XCTAssertTrue(WardrobeStorageInventory.entries(clothings: [], customCabinets: settings.cabinets).isEmpty)
    }

    func testCustomNameIconAndContentsSurviveReload() throws {
        let destination = try settings.saveCabinet(name: "  礼帽柜  ", icon: .hat)
        let id = try XCTUnwrap(destination.customID)
        let itemID = UUID()
        try settings.include(itemID, in: id)
        let restored = WardrobeStorageSettings(defaults: defaults)
        XCTAssertEqual(restored.cabinets.first?.name, "礼帽柜")
        XCTAssertEqual(restored.cabinets.first?.icon, .hat)
        XCTAssertEqual(restored.cabinets.first?.clothingIDs, [itemID])
        XCTAssertEqual(restored.destinations.last?.id, destination.id)
    }

    func testInvalidAndDuplicateNamesDoNotCreateCabinets() throws {
        XCTAssertThrowsError(try settings.saveCabinet(name: " \n ", icon: .hat))
        XCTAssertThrowsError(try settings.saveCabinet(name: String(repeating: "帽", count: 13), icon: .hat))
        XCTAssertThrowsError(try settings.saveCabinet(name: "鞋柜", icon: .shoes))
        _ = try settings.saveCabinet(name: "My Hats", icon: .hat)
        XCTAssertThrowsError(try settings.saveCabinet(name: "ｍｙ ｈａｔｓ", icon: .hat))
        XCTAssertEqual(settings.cabinets.count, 1)
    }

    func testEditingKeepsIdentityAndMembers() throws {
        let first = try settings.saveCabinet(name: "帽子", icon: .star)
        let id = try XCTUnwrap(first.customID)
        let itemID = UUID()
        try settings.include(itemID, in: id)
        let edited = try settings.saveCabinet(id: id, name: "礼帽柜", icon: .hat)
        XCTAssertEqual(edited.id, first.id)
        XCTAssertEqual(settings.cabinets.count, 1)
        XCTAssertEqual(settings.cabinets.first?.clothingIDs, [itemID])
        XCTAssertEqual(edited.icon, .hat)
    }

    func testMovingToAnotherCustomCabinetNeverDuplicatesInventory() throws {
        let first = try settings.saveCabinet(name: "礼帽柜", icon: .hat)
        let second = try settings.saveCabinet(name: "出游柜", icon: .star)
        let hat = Clothing(name: "玫瑰礼帽", types: "小物", imagePaths: ["hat.jpg"], price: 280)
        try settings.include(hat.id, in: XCTUnwrap(first.customID))
        try settings.include(hat.id, in: XCTUnwrap(second.customID))
        let entries = WardrobeStorageInventory.entries(clothings: [hat], customCabinets: settings.cabinets)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.storageID, second.id)
        XCTAssertEqual(settings.cabinets.first?.clothingIDs, [])
        XCTAssertEqual(entries.first?.price, 280)
        XCTAssertEqual(hat.imagePaths, ["hat.jpg"])
        try savePriceValidation(entries)
        try settings.setContents([], for: XCTUnwrap(second.customID))
        XCTAssertEqual(WardrobeStorageInventory.entries(clothings: [hat], customCabinets: settings.cabinets).first?.storageID,
                       WardrobeStorageCategory.accessories.rawValue)
    }

    func testMainDressSetStaysInWardrobeEvenIfMembershipContainsItsID() throws {
        let cabinet = try settings.saveCabinet(name: "礼帽柜", icon: .hat)
        let dress = Clothing(name: "JSK＋包＋帽", types: "小物，jSk", accessories: "包,礼帽")
        try settings.include(dress.id, in: XCTUnwrap(cabinet.customID))
        let entries = WardrobeStorageInventory.entries(clothings: [dress], customCabinets: settings.cabinets)
        XCTAssertEqual(entries.first?.storageID, "wardrobe")
        XCTAssertEqual(home([dress], settings.cabinets).ids, [dress.id])
    }

    func testRemovedDefaultCategoriesRemainVisibleUntilUserOrganizesThem() throws {
        let perfume = Clothing(name: "玫瑰香水", types: "美妆", price: 420)
        let doll = Clothing(name: "小熊", types: "生活", price: 380)
        XCTAssertEqual(Set(home([perfume, doll], []).ids), Set([perfume.id, doll.id]))
        let cabinet = try settings.saveCabinet(name: "香水柜", icon: .beauty)
        try settings.include(perfume.id, in: XCTUnwrap(cabinet.customID))
        XCTAssertEqual(home([perfume, doll], settings.cabinets).ids, [doll.id])
        let entries = WardrobeStorageInventory.entries(clothings: [perfume, doll], customCabinets: settings.cabinets)
        XCTAssertEqual(entries.filter { $0.storageID == cabinet.id }.map(\.title), [perfume.name])
        XCTAssertEqual(entries.filter { $0.storageID == "wardrobe" }.map(\.title), [doll.name])
        XCTAssertEqual(entries.count, 2)
    }

    func testDeletedMembersStayExcludedAndNewItemCanBeIncluded() throws {
        let destination = try settings.saveCabinet(name: "袜子柜", icon: .star)
        let id = try XCTUnwrap(destination.customID)
        let deleted = Clothing(name: "旧袜子", types: "小物")
        deleted.isDeleted = true
        let item = Clothing(name: "蕾丝袜", types: "小物", price: 88)
        try settings.setContents([deleted.id], for: id)
        try settings.include(item.id, in: id)
        let entries = WardrobeStorageInventory.entries(clothings: [deleted, item], customCabinets: settings.cabinets)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.storageID, destination.id)
        XCTAssertEqual(entries.first?.price, 88)
    }

    private func home(_ items: [Clothing], _ cabinets: [WardrobeStorageCustomCabinet]) -> WardrobeFilterResult {
        WardrobeFilterEngine.evaluate(WardrobeFilterInput(snapshots: items.map(WardrobeClothingSnapshot.init(clothing:)),
            searchText: "", selectedTagIDs: [], selectedBrandIDs: [], selectedTypes: [], selectedColors: [],
            selectedSizes: [], selectedLengths: [], selectedConditions: [], selectedAccessories: [],
            depositStatusFilterRawValue: "all", sortOptionRawValue: "", storageCabinets: cabinets))
    }

    private func savePriceValidation(_ entries: [WardrobeStorageEntry]) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pink-house-storage-price-validation")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for showPrice in [true, false] {
            let renderer = ImageRenderer(content: WardrobeStorageItemLabel(entry: try XCTUnwrap(entries.first), showPrice: showPrice)
                .frame(width: 150).padding(24).background(WardrobeStorageArt.cream).colorScheme(.light))
            renderer.scale = 3
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            try data.write(to: directory.appendingPathComponent(showPrice ? "item-price-visible.png" : "item-price-hidden.png"))
        }
        let icons = ImageRenderer(content: HStack(spacing: 14) {
            ForEach(WardrobeStorageIconKind.allCases) { kind in
                VStack(spacing: 8) {
                    WardrobeStorageIcon(kind: kind, size: 56)
                    Text(kind.title).font(.system(size: 11)).foregroundStyle(WardrobeStorageArt.ink)
                }
            }
        }.padding(20).background(WardrobeStorageArt.cream))
        icons.scale = 3
        try XCTUnwrap(icons.uiImage?.pngData()).write(to: directory.appendingPathComponent("cabinet-icons.png"))
    }
}
