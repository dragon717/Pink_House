import XCTest

final class StoreScreenshotUITests: XCTestCase {
    /// Capture native pages from the dedicated, populated release-art simulators.
    @MainActor
    func testCaptureCurrentFeatures() throws {
        try capturePages(language: "zh-Hans", locale: "zh_CN", payments: "心愿尾款", statistics: "衣橱统计")
        try capturePages(language: "en", locale: "en_US", payments: "Wishlist Payments", statistics: "Wardrobe Statistics")
        try capturePages(language: "zh-Hant", locale: "zh_TW", payments: "心願尾款", statistics: "衣櫥統計")
    }

    @MainActor
    func testCaptureEnglishStorePage() throws {
        try capturePages(language: "en", locale: "en_US", payments: "Wishlist Payments", statistics: "Wardrobe Statistics")
    }

    @MainActor
    func testCaptureSimplifiedStorePage() throws {
        try capturePages(language: "zh-Hans", locale: "zh_CN", payments: "心愿尾款", statistics: "衣橱统计")
    }

    @MainActor
    func testCaptureTraditionalStorePage() throws {
        try capturePages(language: "zh-Hant", locale: "zh_TW", payments: "心願尾款", statistics: "衣櫥統計")
    }

    @MainActor
    func testCaptureDuoOuterStates() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Pink House Store iPhone Duo")
        continueAfterFailure = false
        for (language, locale) in [("zh-Hans", "zh_CN"), ("en", "en_US"), ("zh-Hant", "zh_TW")] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                   "-app.selected_language", language, "-newbieGuide.hasSeenWelcome", "YES", "-iap_test_mode", "NO"]
            app.launch()
            let stats = app.buttons["wardrobe.detailedStats"]
            waitForEntryControl(stats, in: app, language: language)
            let wardrobe = XCUIScreen.main.screenshot()
            XCTAssertEqual(wardrobe.image.cgImage?.width, 1398, "Close Duo before running outer-display photography")
            capture("\(language)-duo-wardrobe")
            let dress = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Nuit Marine")).firstMatch
            XCTAssertTrue(dress.waitForExistence(timeout: 20))
            dress.tap()
            XCTAssertTrue(app.staticTexts["Nuit Marine"].firstMatch.waitForExistence(timeout: 20))
            capture("\(language)-duo-detail")
            app.terminate()
        }
    }

    @MainActor
    private func capturePages(language: String, locale: String, payments: String, statistics: String) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("Pink House Store ") == true)
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "-app.selected_language", language,
                               "-newbieGuide.hasSeenWelcome", "YES", "-iap_test_mode", "NO"]
        app.launch()
        let plan = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", payments)).firstMatch
        waitForEntryControl(plan, in: app, language: language)
        selectIPadDetail(in: app)
        capture("\(language)-wardrobe")
        plan.tap()
        let paymentTitle = ["zh-Hans": "最近月统计", "zh-Hant": "最近月統計", "en": "Recent Month Stats"][language]!
        let paymentHeading = app.staticTexts[paymentTitle].firstMatch
        if !paymentHeading.waitForExistence(timeout: 5), plan.isHittable { plan.tap() }
        XCTAssertTrue(paymentHeading.waitForExistence(timeout: 15))
        selectIPadDetail(in: app)
        capture("\(language)-payments")

        app.terminate()
        app.launch()
        let statsButton = app.buttons["wardrobe.detailedStats"]
        let heading = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", statistics)).firstMatch
        waitForEntryControl(statsButton, in: app, language: language)
        selectIPadDetail(in: app)
        // Startup can reconfigure the navigation stack after its first layout.
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        statsButton.tap()
        if !heading.waitForExistence(timeout: 3), statsButton.isHittable {
            statsButton.tap()
        }
        XCTAssertTrue(heading.waitForExistence(timeout: 8))
        capture("\(language)-stats")
        app.terminate()
    }

    @MainActor
    private func waitForEntryControl(_ control: XCUIElement, in app: XCUIApplication, language: String) {
        let done = app.buttons[language == "en" ? "Done" : "完成"].firstMatch
        let deadline = Date().addingTimeInterval(60)
        // A new calendar day presents check-in before the underlying page becomes accessible.
        while Date() < deadline {
            if done.exists, done.isHittable { done.tap() }
            if control.exists, control.isHittable { return }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTFail("The page entry control is still unavailable after dismissing startup sheets")
    }

    @MainActor
    private func selectIPadDetail(in app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("iPad") == true else { return }
        let dress = app.staticTexts["Nuit Marine"].firstMatch
        XCTAssertTrue(dress.waitForExistence(timeout: 20))
        dress.tap()
    }

    @MainActor
    private func capture(_ name: String) {
        // Allow the navigation transition, thumbnail decoding and first-use reward to finish.
        // Cold devices need more time to finish the first wardrobe's image cache.
        let settlingTime: TimeInterval = name.hasSuffix("-wardrobe") ? 30 : 6
        RunLoop.current.run(until: Date().addingTimeInterval(settlingTime))
        let done = XCUIApplication().buttons[name.hasPrefix("en-") ? "Done" : "完成"].firstMatch
        if done.exists, done.isHittable {
            done.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
