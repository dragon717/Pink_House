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

    func testReservationKindSeparatesFullPaymentAndFinalPaymentPlans() throws {
        let owned = Clothing(name: "Owned OP")
        let fullPayment = Clothing(
            name: "Full Payment OP",
            price: 1000,
            deposit: 1000,
            balance: 0,
            isDepositPlan: true
        )
        let finalPayment = Clothing(
            name: "Final Payment OP",
            price: 1000,
            deposit: 200,
            balance: 800,
            isDepositPlan: true
        )
        let sold = Clothing(name: "Sold OP", price: 1000, status: .offShelf)

        XCTAssertEqual(owned.reservationKind, .owned)
        XCTAssertFalse(owned.isFinalPaymentPlan)
        XCTAssertEqual(fullPayment.reservationKind, .fullPaymentReservation)
        XCTAssertTrue(fullPayment.isFullPaymentReservation)
        XCTAssertFalse(fullPayment.isFinalPaymentPlan)
        XCTAssertEqual(finalPayment.reservationKind, .depositPlan)
        XCTAssertTrue(finalPayment.isFinalPaymentPlan)
        XCTAssertEqual(sold.reservationKind, .sold)
        XCTAssertEqual(sold.wardrobeValueAmount, 0)
    }

    func testWardrobeStatusFilterSeparatesSoldFromOwned() {
        let owned = Clothing(name: "Owned OP")
        let sold = Clothing(name: "Sold OP", status: .offShelf)

        let soldResult = ClothingFilterService.filter(
            [owned, sold],
            config: .init(depositStatusFilter: .sold)
        )
        let ownedResult = ClothingFilterService.filter(
            [owned, sold],
            config: .init(depositStatusFilter: .owned)
        )

        XCTAssertEqual(soldResult.map(\.id), [sold.id])
        XCTAssertEqual(ownedResult.map(\.id), [owned.id])
    }

    func testOutfitRecommendabilityExcludesReservationsAndPendingFulfillment() throws {
        let owned = Clothing(name: "Owned OP")
        let fullPayment = Clothing(
            name: "Full Payment OP",
            price: 1000,
            deposit: 1000,
            balance: 0,
            isDepositPlan: true
        )
        let finalPayment = Clothing(
            name: "Final Payment OP",
            price: 1000,
            deposit: 200,
            balance: 800,
            isDepositPlan: true
        )
        let pending = Clothing(name: "Shipping OP")
        pending.note = "待收货"

        let recommendable = OutfitRecommendability.recommendableClothings(
            from: [owned, fullPayment, finalPayment, pending]
        )

        XCTAssertEqual(recommendable.map(\.id), [owned.id])
        XCTAssertTrue(OutfitRecommendability.exclusionReasons(for: fullPayment).contains(.reservation))
        XCTAssertTrue(OutfitRecommendability.exclusionReasons(for: finalPayment).contains(.reservation))
        XCTAssertTrue(OutfitRecommendability.exclusionReasons(for: pending).contains(.pendingFulfillment))
    }
}
