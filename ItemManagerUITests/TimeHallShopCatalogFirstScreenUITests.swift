//
//  TimeHallShopCatalogFirstScreenUITests.swift
//  ItemManagerUITests
//
//  时光馆首屏验收：时光馆只保留「店家上新」。
//  2026-09-24 旧馆（馆藏档案 / 我的品牌品牌列表）已整体移除，
//  本用例同时守住「旧入口不再出现」这一删除口径。
//
//  访问性标识约定（改产品代码时若改了这些文案，同步改本文件）：
//    · 时光馆首屏导航栏标题 → 「店家上新」
//    · 「馆藏档案」入口 → 已删除，不得再出现
//

import XCTest

final class TimeHallShopCatalogFirstScreenUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTimeHallFirstScreenIsShopCatalogWithoutLegacyArchive() throws {
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

    // 3. 旧馆入口已随旧馆代码移除，不得再出现
    let legacyEntry = app.buttons["馆藏档案"]
    XCTAssertFalse(legacyEntry.exists, "馆藏档案入口已移除，不应出现")
    let legacyHeader = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "个品牌")).firstMatch
    XCTAssertFalse(legacyHeader.exists, "「我的品牌 / N个品牌」品牌列表已移除，不应出现")
    capture(app, "02-旧馆入口已移除")
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
