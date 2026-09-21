//
//  ShopCatalogMenuFlowUITests.swift
//  ItemManagerUITests
//
//  V1.2 交互验收（2026-09-21 三项 UI 改动的模拟器走查）：
//    1. 路由收口：店家主页系列卡点击**直达**点菜式选购页
//       （ShopCatalogSeriesMenuView sheet，原合并大卡中转页已删除）；
//    2. 缩略图大图预览：点菜页缩略图（a11y「查看大图」）→ 全屏查看器
//       （a11y「关闭大图」）→ 关闭回到点菜页；
//    3. 行内「>」进商品完整详情仍可达（详情页导航标题 = 商品名）。
//
//  锚点约定（改产品代码时同步本文件）：
//    · 系列卡文字「雪国来信」/ 店家行「Alice Girl」
//    · 点菜页 sheet：navigationTitle「雪国来信」+ 右上角「完成」
//    · 缩略图按钮 a11y「查看大图」；查看器关闭 a11y「关闭大图」
//

import XCTest

final class ShopCatalogMenuFlowUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testSeriesCardOpensMenuDirectlyAndImageViewerWorks() throws {
    let app = launchAndNavigateToShop()

    // 4. 系列卡「雪国来信」→ 直达点菜式选购页（sheet）
    let seriesCard = app.staticTexts["雪国来信"]
    scrollUntilVisible(app, seriesCard)
    XCTAssertTrue(seriesCard.isHittable, "店家主页应有雪国来信系列卡")
    seriesCard.tap()

    // 直达判定：sheet 的导航标题与「完成」按钮出现（无中转页）
    let menuNav = app.navigationBars["雪国来信"]
    XCTAssertTrue(menuNav.waitForExistence(timeout: 8), "系列卡应直达点菜页（sheet 导航标题=系列名）")
    let done = app.buttons["完成"]
    XCTAssertTrue(done.waitForExistence(timeout: 4), "点菜页右上角应有完成按钮")
    capture(app, "01-系列卡直达点菜页")

    // 5. 缩略图大图预览：点第一个「查看大图」
    let viewerButtons = app.buttons.matching(NSPredicate(format: "label == %@", "查看大图"))
    XCTAssertTrue(viewerButtons.count > 0, "点菜页行内应有查看大图按钮")
    let thumb = viewerButtons.element(boundBy: 0)
    scrollUntilVisible(app, thumb)
    thumb.tap()

    // 查看器弹出：黑底大图 + 关闭按钮
    let close = app.buttons["关闭大图"]
    XCTAssertTrue(close.waitForExistence(timeout: 6), "点击缩略图应弹出大图查看器（含关闭大图按钮）")
    capture(app, "02-缩略图大图预览")

    // 6. 关闭大图 → 回到点菜页
    close.tap()
    XCTAssertTrue(done.waitForExistence(timeout: 6), "关闭大图后应回到点菜页")
    capture(app, "03-关闭大图回点菜页")

    // 7. 行内「>」进商品详情（以 JSK 行为例；详情页导航标题固定为「商品详情」）
    let jskRow = app.staticTexts["雪国来信 JSK"]
    scrollUntilVisible(app, jskRow)
    if jskRow.isHittable {
      jskRow.tap()
      let detailNav = app.navigationBars["商品详情"]
      if detailNav.waitForExistence(timeout: 6) {
        capture(app, "04-行内进商品详情")
        // 返回点菜页
        app.navigationBars.buttons.firstMatch.tap()
      } else {
        XCTFail("点商品名应进入商品详情（导航标题=商品详情）")
      }
    } else {
      XCTFail("点菜页应可见 JSK 行商品名")
    }

    // 8. 完成关闭点菜页 → 回到店家主页
    if done.exists && done.isHittable {
      done.tap()
    }
    XCTAssertTrue(app.staticTexts["雪国来信"].waitForExistence(timeout: 6), "完成后应回到店家主页")
    capture(app, "05-完成回店家主页")
  }

  // MARK: - 四态按钮（真实种子状态实证）

  /// 种子窗口（2026-09-21 视角）：
  ///   · 雪国来信 JSK  预约中（09-10 → 09-28）   → 【加入心愿】+【我已经预约】
  ///   · 雪国来信 单肩包 现货在售（无截止）        → 【加入少女衣橱】（无加入心愿）
  @MainActor
  func testProductDetailActionButtonMatchesSalePhase() throws {
    let app = launchAndNavigateToShop()

    // 进点菜页
    let seriesCard = app.staticTexts["雪国来信"]
    scrollUntilVisible(app, seriesCard)
    seriesCard.tap()
    XCTAssertTrue(app.navigationBars["雪国来信"].waitForExistence(timeout: 8), "应直达点菜页")

    // 1) JSK：预约中 → 加入心愿 + 我已经预约
    let jskRow = app.staticTexts["雪国来信 JSK"]
    scrollUntilVisible(app, jskRow)
    jskRow.tap()
    XCTAssertTrue(app.navigationBars["商品详情"].waitForExistence(timeout: 6), "应进入 JSK 详情")
    let wish = app.buttons["加入心愿"]
    XCTAssertTrue(wish.waitForExistence(timeout: 6), "预约中商品主按钮应为「加入心愿」")
    XCTAssertTrue(app.buttons["我已经预约"].exists, "预约中应显示「我已经预约」次按钮")
    capture(app, "10-四态按钮-预约中")

    // 返回点菜页
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.navigationBars["雪国来信"].waitForExistence(timeout: 6), "应回到点菜页")

    // 2) 单肩包：现货在售 → 加入少女衣橱，且不出现加入心愿
    let bagRow = app.staticTexts["雪国来信 单肩包"]
    scrollUntilVisible(app, bagRow)
    bagRow.tap()
    XCTAssertTrue(app.navigationBars["商品详情"].waitForExistence(timeout: 6), "应进入单肩包详情")
    let wardrobe = app.buttons["加入少女衣橱"]
    XCTAssertTrue(wardrobe.waitForExistence(timeout: 6), "现货在售商品主按钮应为「加入少女衣橱」")
    XCTAssertFalse(app.buttons["加入心愿"].exists, "现货在售不应出现「加入心愿」")
    capture(app, "11-四态按钮-现货在售")
  }

  // MARK: - 导航前置

  /// 启动 → 关弹窗 → 时光馆 tab → 店家列表点 Alice Girl → 店家主页
  @MainActor
  private func launchAndNavigateToShop() -> XCUIApplication {
    let app = XCUIApplication()
    app.launch()
    dismissSystemPrompts(app)
    dismissDailyCheckIn(app)

    let timeHallTab = app.buttons["时光馆"]
    XCTAssertTrue(timeHallTab.waitForExistence(timeout: 10), "底部 dock 应有时光馆 tab")
    timeHallTab.tap()

    XCTAssertTrue(app.navigationBars["店家上新"].waitForExistence(timeout: 8), "时光馆首屏应为店家上新")
    capture(app, "00-店家上新首屏")

    let shopRow = app.staticTexts["Alice Girl"]
    scrollUntilVisible(app, shopRow)
    XCTAssertTrue(shopRow.isHittable, "店家列表应有 Alice Girl")
    shopRow.tap()
    return app
  }

  // MARK: - 工具（沿用工程 UITest 惯例）

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

  @MainActor
  private func dismissDailyCheckIn(_ app: XCUIApplication) {
    let done = app.buttons["完成"]
    if done.waitForExistence(timeout: 5) {
      done.tap()
    }
  }

  /// 滚动直到元素进入可视区（避开底部悬浮 dock 压住区）。
  /// 最多 6 次 swipeUp；元素 exists 且中心点在安全区才认为可见。
  @MainActor
  private func scrollUntilVisible(_ app: XCUIApplication, _ element: XCUIElement) {
    guard !element.exists || !isComfortablyVisible(element, app: app) else { return }
    for _ in 0..<6 {
      guard !(element.exists && isComfortablyVisible(element, app: app)) else { return }
      app.swipeUp(velocity: .fast)
    }
    // 滚过头兜底：往回滚
    for _ in 0..<3 {
      if element.exists && isComfortablyVisible(element, app: app) { return }
      app.swipeDown(velocity: .fast)
    }
  }

  @MainActor
  private func isComfortablyVisible(_ element: XCUIElement, app: XCUIApplication) -> Bool {
    guard element.isHittable else { return false }
    let frame = element.frame
    return frame.minY >= 120 && frame.maxY <= app.frame.height - 140
  }

  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
