//
//  ItemManagerUITests.swift
//  ItemManagerUITests
//
//  Created by 木鸟 on 1/15/26.
//

import XCTest

final class ItemManagerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLiveDreamDressDetectiveFindsPinkHouseOfficialSources() throws {
        guard ProcessInfo.processInfo.environment["RUN_DREAM_DRESS_UI"] == "1" else {
            throw XCTSkip("Set RUN_DREAM_DRESS_UI=1 for the opt-in live UI test.")
        }

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let timeHall = app.buttons["时光馆"].firstMatch
        if !timeHall.waitForExistence(timeout: 8) {
            let house = app.buttons["House"].firstMatch
            XCTAssertTrue(house.waitForExistence(timeout: 8), app.debugDescription)
            house.tap()
            XCTAssertTrue(timeHall.waitForExistence(timeout: 8), app.debugDescription)
        }
        timeHall.tap()

        let detective = app.buttons["梦裙侦探"].firstMatch
        XCTAssertTrue(detective.waitForExistence(timeout: 12), app.debugDescription)
        detective.tap()

        let brand = app.textFields["品牌名（可选）"]
        XCTAssertTrue(brand.waitForExistence(timeout: 8), app.debugDescription)
        brand.tap()
        brand.typeText("Pink House")
        app.buttons["开始侦查"].tap()

        let officialWebsite = app.buttons["PINK HOUSE 官网"].firstMatch
        XCTAssertTrue(officialWebsite.waitForExistence(timeout: 120), app.debugDescription)
        XCTAssertTrue(app.staticTexts["品牌官网"].firstMatch.exists)
        XCTAssertTrue(app.buttons["官方淘宝店"].firstMatch.exists)

        let openTimeHallItem = app.buttons.matching(identifier: "dreamDressDetective.openTimeHallItem").firstMatch
        for _ in 0..<5 where !openTimeHallItem.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(openTimeHallItem.waitForExistence(timeout: 8), app.debugDescription)
        openTimeHallItem.tap()
        XCTAssertTrue(app.navigationBars["商品详情"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["关闭"].tap()
        XCTAssertTrue(detective.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(detective.isSelected)
        let investigateAgain = app.buttons["开始侦查"].firstMatch
        XCTAssertTrue(investigateAgain.waitForExistence(timeout: 180), app.debugDescription)
        XCTAssertTrue(investigateAgain.isEnabled)

        let verifyWebPage = app.buttons["验证网页以获取图片和价格"].firstMatch
        for _ in 0..<20 where !verifyWebPage.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(verifyWebPage.waitForExistence(timeout: 8), app.debugDescription)
        verifyWebPage.tap()
        let verificationPage = app.navigationBars["验证商品网页"]
        XCTAssertTrue(verificationPage.waitForExistence(timeout: 15), app.debugDescription)
        let readCurrentPage = app.buttons["读取当前网页"]
        XCTAssertTrue(readCurrentPage.waitForExistence(timeout: 15), app.debugDescription)
        readCurrentPage.tap()
        let verificationClosed = NSPredicate(format: "exists == false")
        expectation(for: verificationClosed, evaluatedWith: verificationPage)
        waitForExpectations(timeout: 35)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "DreamDressDetective-PinkHouse-TimeHall"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
