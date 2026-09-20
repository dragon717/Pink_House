//
//  TimeHallShopCatalogFirstScreenUITests.swift
//  ItemManagerUITests
//
//  重构方案 Phase 1 交互验收：时光馆首屏 = 店家上新，「馆藏档案」为只读次级入口。
//
//  访问性标识约定（改产品代码时若改了这些文案，同步改本文件）：
//    · 店家上新首屏左上角 → label「馆藏档案」（次级只读入口）
//    · 馆藏档案右上角返回 → label「返回店家上新」
//    · fullScreenCover 兼容态左上角 → label「返回时光馆」
//

import XCTest

final class TimeHallShopCatalogFirstScreenUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTimeHallFirstScreenIsShopCatalogWithLegacyArchiveEntry() throws {
    let app = XCUIApplication()
    app.launch()
    dismissSystemPrompts(app)
    dismissDailyCheckIn(app)

    // 1. 底部 dock 切到「时光馆」
    let timeHallTab = app.buttons["时光馆"]
    XCTAssertTrue(timeHallTab.waitForExistence(timeout: 8), "底部 dock 应有时光馆 tab")
    timeHallTab.tap()

    // 2. 首屏应直接是店家上新（导航栏标题）
    let navTitle = app.navigationBars["店家上新"]
    XCTAssertTrue(navTitle.waitForExistence(timeout: 8), "时光馆首屏应为店家上新")
    capture(app, "01-时光馆首屏-店家上新")

    // 3. 左上角「馆藏档案」进入旧馆
    let legacyEntry = app.buttons["馆藏档案"]
    XCTAssertTrue(legacyEntry.exists, "店家上新左上角应有馆藏档案入口")
    legacyEntry.tap()

    let legacyHeader = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "个品牌")).firstMatch
    XCTAssertTrue(legacyHeader.waitForExistence(timeout: 8), "馆藏档案应展示旧品牌列表（我的品牌/N个品牌）")
    capture(app, "02-馆藏档案-旧品牌列表")

    // 4. 右上角返回店家上新
    let backButton = app.buttons["返回店家上新"]
    XCTAssertTrue(backButton.exists, "馆藏档案应有返回店家上新入口")
    backButton.tap()

    XCTAssertTrue(app.navigationBars["店家上新"].waitForExistence(timeout: 8), "应回到店家上新首屏")
    capture(app, "03-返回店家上新")
  }

  // MARK: - 工具

  /// 关掉首启的系统权限弹窗。
  @MainActor
  private func dismissSystemPrompts(_ app: XCUIApplication, timeout: TimeInterval = 8) {
    let labels = ["不允许", "Don't Allow", "好", "OK"]
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      var tapped = false
      for label in labels where app.buttons[label].isHittable {
        app.buttons[label].tap()
        tapped = true
        break
      }
      if !tapped { break }
    }
  }

  /// 每日打卡弹窗：点「完成」关闭（存在才点）。
  @MainActor
  private func dismissDailyCheckIn(_ app: XCUIApplication) {
    let done = app.buttons["完成"]
    if done.waitForExistence(timeout: 5) {
      done.tap()
    }
  }

  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
