//
//  ClothingTests.swift
//  ItemManagerTests
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ClothingTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        modelContainer = try ModelContainer(for: schema, configurations: config)
        modelContext = modelContainer.mainContext
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
    }

    func testClothingCreation() throws {
        let clothing = Clothing(
            name: "Test Dress",
            types: "JSK",
            price: 100,
            stock: 10
        )
        
        modelContext.insert(clothing)
        
        let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.name == "Test Dress" })
        let fetchedClothings = try modelContext.fetch(descriptor)
        
        XCTAssertEqual(fetchedClothings.count, 1)
        XCTAssertEqual(fetchedClothings.first?.name, "Test Dress")
        XCTAssertEqual(fetchedClothings.first?.status, .onShelf) // Default status
    }
    
    func testClothingUpdate() throws {
        let clothing = Clothing(name: "Old Name")
        modelContext.insert(clothing)
        
        clothing.name = "New Name"
        
        XCTAssertEqual(clothing.name, "New Name")
    }
}
