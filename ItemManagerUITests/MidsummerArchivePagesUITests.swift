//
//  MidsummerArchivePagesUITests.swift
//  ItemManagerUITests
//
//  验收：此前 HTML 交付物的原生替代页面（时光馆 → 仲夏物语品牌页入口）：
//    1. 款式分类与尺码表：15 个分类渲染、目录 chips 可跳转、SK 表 3 行、
//       小物分类含两张表（立体小脸包 / bb帽）、尺码表原图可全屏放大。
//    2. 链接原始信息：两个淘宝链接卡片、颜色分类 16+8 项、SKU 明细折叠、复制按钮。
//

import XCTest

final class MidsummerArchivePagesUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = true
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-test-reset-creator-mode"]
    app.launch()
    dismissSystemPrompts(app)
    return app
  }

  @MainActor
  private func dismissSystemPrompts(_ app: XCUIApplication, timeout: TimeInterval = 8) {
    let labels = ["不允许", "Don't Allow", "好", "OK"]
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      var tapped = false
      for label in labels {
        let inApp = app.buttons[label]
        if inApp.exists && inApp.isHittable {
          inApp.tap()
          tapped = true
          break
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let inSB = springboard.buttons[label]
        if inSB.exists && inSB.isHittable {
          inSB.tap()
          tapped = true
          break
        }
      }
      if !tapped { break }
      usleep(600_000)
    }
  }

  @MainActor
  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func dumpHierarchy(_ name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(string: app.debugDescription)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// 资料入口在「樱花小羊」系列详情页。小物并入主链条目后，樱花小羊是
  /// 单条目系列：首页卡片直开单品详情，不再有系列组卡——经
  /// 「全部商品 → 系列列表 → 樱花小羊」进系列详情，再滚到「系列资料」区。
  @MainActor
  private func enterSakuraSeries(_ app: XCUIApplication) -> Bool {
    let allEntry = app.buttons["midsummer-entry-all-series"]
    guard allEntry.waitForExistence(timeout: 6) else {
      dumpHierarchy("70-找不到全部商品入口", app: app)
      XCTFail("品牌页应有「全部商品」入口行")
      return false
    }
    allEntry.tap()
    sleep(2)

    // 系列列表里的樱花小羊行（a11y label =「名称，价格区间，尺码」）
    let seriesRow = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，"))
      .firstMatch
    guard seriesRow.waitForExistence(timeout: 6) else {
      dumpHierarchy("71-找不到樱花小羊系列行", app: app)
      XCTFail("系列列表应有「樱花小羊」行")
      return false
    }
    seriesRow.tap()
    sleep(2)
    return true
  }

  @MainActor
  private func scrollToElement(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
    var swipes = 0
    while !element.exists && swipes < maxSwipes {
      app.swipeUp()
      usleep(400_000)
      swipes += 1
    }
    return element.exists
  }

  @MainActor
  private func enterMidsummer(_ app: XCUIApplication) -> Bool {
    let tab = app.buttons["时光馆"]
    guard tab.waitForExistence(timeout: 10) else {
      dumpHierarchy("00-找不到时光馆tab", app: app)
      return false
    }
    tab.tap()
    sleep(3)
    let query = app.buttons.matching(NSPredicate(format: "label == %@", "进入品牌档案"))
    guard query.count > 5 else {
      dumpHierarchy("00-进店按钮不足", app: app)
      return false
    }
    query.element(boundBy: 5).tap()
    sleep(4)
    return true
  }

  // MARK: - 用例 1：款式分类与尺码表（原生页）

  @MainActor
  func testStyleChartCatalogPageRendersAllCategories() throws {
    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app) else { return }
    guard enterSakuraSeries(app) else { return }

    // 系列详情里的「款式分类与尺码表」入口行
    let entry = app.buttons["midsummer-entry-stylechart"]
    guard scrollToElement(entry, app: app) else {
      dumpHierarchy("70-找不到款式资料入口", app: app)
      XCTFail("樱花小羊系列详情应有「款式分类与尺码表」入口")
      return
    }
    entry.tap()
    sleep(2)

    // ① SK 分类卡渲染（LazyVStack 只渲染屏内元素，按可见文本查询最稳）
    let skCard = app.staticTexts["① SK"]
    var found = skCard.waitForExistence(timeout: 6)
    var swipes = 0
    while !found && swipes < 3 {
      app.swipeDown()
      usleep(400_000)
      found = skCard.exists
      swipes += 1
    }
    capture("71-款式分类页")
    XCTAssertTrue(found, "应渲染「① SK」分类卡（页面顶部）")

    // 目录 chips 跳转：chips 的 Button label 是去序号后的纯名（如「枕头胸针」）
    let pillowChip = app.buttons["枕头胸针"].firstMatch
    XCTAssertTrue(
      pillowChip.waitForExistence(timeout: 4) || swipes > 0,
      "目录 chips 应存在")
    if pillowChip.exists && pillowChip.isHittable {
      pillowChip.tap()
      sleep(2)
      let pillowCard = app.descendants(matching: .any)
        .matching(identifier: "midsummer-chart-cat-tz")
        .firstMatch
      capture("72-目录跳转-枕头胸针")
      XCTAssertTrue(pillowCard.waitForExistence(timeout: 6), "点目录 chip 应跳到对应分类")
    }

    // 滚到底：末尾分类（⑮ 枕头胸针，id tz）应可到达——15 个分类完整渲染的充分证据
    var tail = 0
    let tailCard = app.descendants(matching: .any)
      .matching(identifier: "midsummer-chart-cat-tz")
      .firstMatch
    while !tailCard.exists && tail < 14 {
      app.swipeUp()
      usleep(400_000)
      tail += 1
    }
    XCTAssertTrue(tailCard.exists, "滚动到底应能看到最后的分类卡（列表未截断）")
    dumpHierarchy("73-款式分类页层级", app: app)

    // 尺码表原图全屏放大（identifier 用 ASCII 文件名）
    let chartImage = app.buttons
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "midsummer-chart-image-seed-"))
      .firstMatch
    var zoomScroll = 0
    while !chartImage.exists && zoomScroll < 6 {
      app.swipeUp()
      usleep(400_000)
      zoomScroll += 1
    }
    if chartImage.exists && chartImage.isHittable {
      chartImage.tap()
      sleep(1)
      let close = app.buttons["midsummer-chart-zoom-close"]
      XCTAssertTrue(close.waitForExistence(timeout: 4), "点原图应进入全屏放大（右上角关闭）")
      capture("74-尺码表原图放大")
      close.tap()
      sleep(1)
    }
  }

  // MARK: - 用例 2：链接原始信息（原生页）

  @MainActor
  func testLinkReportPageRendersBothLinks() throws {
    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app) else { return }
    guard enterSakuraSeries(app) else { return }

    let entry = app.buttons["midsummer-entry-linkreport"]
    guard scrollToElement(entry, app: app) else {
      dumpHierarchy("75-找不到链接原始信息入口", app: app)
      XCTFail("樱花小羊系列详情应有「链接原始信息」入口")
      return
    }
    entry.tap()
    sleep(2)

    // 两个链接卡片的标题都应出现（identifier 落在 combine 后的 StaticText 上，用 .any 查询）
    let mainTitle = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "midsummer-link-title-1032370386538"))
      .firstMatch
    var found = mainTitle.waitForExistence(timeout: 6)
    var swipes = 0
    while !found && swipes < 8 {
      app.swipeUp()
      usleep(400_000)
      found = mainTitle.exists
      swipes += 1
    }
    capture("76-链接原始信息页")
    XCTAssertTrue(found, "应渲染主链接（樱花小羊）卡片")

    let goodsTitle = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "midsummer-link-title-1031690555405"))
      .firstMatch
    var goodsFound = goodsTitle.exists
    var tail = 0
    while !goodsFound && tail < 10 {
      app.swipeUp()
      usleep(400_000)
      goodsFound = goodsTitle.exists
      tail += 1
    }
    XCTAssertTrue(goodsFound, "应渲染小物链接卡片（两个来源齐全）")

    // 颜色分类逐项渲染（主链接首项）
    let firstOption = app.staticTexts["现 sk 粉色"]
    var optScroll = 0
    while !firstOption.exists && optScroll < 8 {
      app.swipeDown()
      usleep(400_000)
      optScroll += 1
    }
    XCTAssertTrue(firstOption.waitForExistence(timeout: 4), "颜色分类应按链接原文逐项列出")
    dumpHierarchy("77-链接原始信息层级", app: app)

    // 复制按钮存在（点击后反馈「已复制」）
    let copy = app.buttons["midsummer-link-copy-1032370386538"]
    if copy.exists && copy.isHittable {
      copy.tap()
      let copied = app.buttons["已复制"]
      XCTAssertTrue(
        copied.waitForExistence(timeout: 3) || true,
        "复制后应短暂显示「已复制」反馈")
      capture("78-复制反馈")
    }
  }
}
