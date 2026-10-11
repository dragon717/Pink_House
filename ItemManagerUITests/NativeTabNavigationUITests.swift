import XCTest

final class NativeTabNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSystemTabBarSwitchesWardrobeDepositTimeHallAndMe() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-newbieGuide.hasSeenWelcome", "YES",
                                "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let splash = app.buttons["少女心愿，进入应用"]
        if splash.waitForExistence(timeout: 10) { splash.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["不允许", "Don't Allow", "好", "OK"] {
            let button = springboard.buttons[label].firstMatch
            if button.exists { button.tap() }
        }
        let done = app.buttons["完成"].firstMatch
        if done.waitForExistence(timeout: 3), done.isHittable { done.tap() }
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "必须是系统 TabBar，不能退回覆盖式 Dock")
        for title in ["时光馆", "我", "心愿尾款", "衣橱"] {
            let button = bar.buttons[title].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 8))
            button.tap()
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "selected == YES"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                           "系统导航选中态应跟随当前功能：\(title)")
            if title == "时光馆" {
                XCTAssertTrue(app.navigationBars["店家上新"].waitForExistence(timeout: 10))
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "native-tab-" + title
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
