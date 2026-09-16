//
//  MidsummerGoodsItemUITests.swift
//  ItemManagerUITests
//
//  验收：小物配件（淘宝 item 1031690555405，草帽/袜子/项链/立体胸针/花丸/
//  枕头胸针）并入主链条目后的呈现——两个淘宝链接合并为一个「樱花小羊」条目：
//    1. 品牌页只有一张「樱花小羊」卡片（a11y 标签 =「名称，现货价 ¥59–999」，
//       区间取两页并集），不再出现「樱花小羊 小物」独立条目。
//    2. 详情页：名称 → 现货价 → 预约价行纵向有序（徽章已按用户要求移除）；
//       「包含款式」行已移除；尺码从小到大（XS/S/M/L/XL/XXL/F）、
//       单品尺码表入口齐备；款式对应图按款式归组、组内嵌尺码表。
//    3. 一键入库 → 规格面板：颜色分类 (24) 逐项可选，小物选项（现 草帽 生成色）
//       与 F 码都在同一面板里。
//

import XCTest

final class MidsummerGoodsItemUITests: XCTestCase {

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

  @MainActor
  private func enterTimeHall(_ app: XCUIApplication) -> Bool {
    let tab = app.buttons["时光馆"]
    guard tab.waitForExistence(timeout: 10) else {
      dumpHierarchy("00-找不到时光馆tab", app: app)
      return false
    }
    tab.tap()
    sleep(3)
    return true
  }

  /// 仲夏物语在 `TimeHallMerchant.allCases` 里是第 5 个（0-based）。
  @MainActor
  private func enterMidsummer(_ app: XCUIApplication) -> Bool {
    let query = app.buttons.matching(NSPredicate(format: "label == %@", "进入品牌档案"))
    guard query.count > 5 else {
      dumpHierarchy("00-进店按钮不足", app: app)
      return false
    }
    query.element(boundBy: 5).tap()
    sleep(4)
    return true
  }

  // MARK: - 用例：两条链接合并为一个条目 + 合并后的详情与规格面板

  @MainActor
  func testMergedSakuraItemCoversBothLinks() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }

    // 1. 品牌页 feed：只有一张「樱花小羊」卡片，价格是两页并集 ¥59–999（现货价口径）；
    //    小物不再以独立条目出现。
    let mergedCard = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，现货价"))
      .firstMatch
    var cardFound = mergedCard.waitForExistence(timeout: 6)
    var cardSwipes = 0
    while !cardFound && cardSwipes < 4 {
      app.swipeUp()
      usleep(500_000)
      cardFound = mergedCard.exists
      cardSwipes += 1
    }
    capture("60-品牌页-合并后的樱花小羊卡片")
    XCTAssertTrue(cardFound, "品牌页应有合并后的「樱花小羊」条目卡片")
    if cardFound {
      XCTAssertTrue(
        mergedCard.label.contains("¥59–999"),
        "合并条目价格应为两页并集 ¥59–999，实际：\(mergedCard.label)")
    }
    XCTAssertFalse(
      app.staticTexts["樱花小羊 小物"].exists,
      "小物不应再以独立条目出现在品牌页（已并入主链条目）")
    dumpHierarchy("61-品牌页-层级", app: app)
    mergedCard.tap()
    sleep(2)

    // 2. 详情页：徽章已按用户要求移除——名称在最上、价格其下，纵向有序；
    //    价格写清并集口径且以「现货价」为前缀，价格行下紧跟「预约价」行。
    let done = app.buttons["完成"]
    XCTAssertTrue(done.waitForExistence(timeout: 6), "详情页应以弹窗形式打开（右上角「完成」）")

    let nameQuery = app.staticTexts.matching(
      NSPredicate(format: "label == %@", "樱花小羊"))
    guard nameQuery.count > 0 else {
      dumpHierarchy("62-详情-找不到名称", app: app)
      XCTFail("详情页正文应有名称")
      return
    }
    var bodyName = nameQuery.element(boundBy: 0)
    for index in 1..<nameQuery.count {
      let candidate = nameQuery.element(boundBy: index)
      if candidate.frame.minY < bodyName.frame.minY { bodyName = candidate }
    }
    let priceQuery = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "现货价"))
    var bodyPrice: XCUIElement?
    for index in 0..<priceQuery.count {
      let candidate = priceQuery.element(boundBy: index)
      if bodyPrice == nil || candidate.frame.minY < bodyPrice!.frame.minY {
        bodyPrice = candidate
      }
    }
    guard let bodyPrice else {
      dumpHierarchy("62-详情-找不到价格", app: app)
      XCTFail("详情页正文应有「现货价」前缀的价格行")
      return
    }
    XCTAssertLessThanOrEqual(
      bodyName.frame.maxY, bodyPrice.frame.minY + 1, "名称与价格不得重叠（徽章已移除，名称在最上）")
    XCTAssertTrue(
      bodyPrice.label.contains("¥59–999"),
      "详情页价格应为两页并集 ¥59–999，实际：\(bodyPrice.label)")
    XCTAssertTrue(
      bodyPrice.label.hasPrefix("现货价"),
      "价格行应以「现货价」为口径前缀，实际：\(bodyPrice.label)")

    // 2b. 预约价行：价格下方独立成行；樱花小羊未采集预约价，如实标注「待补充」。
    let preorderRow = app.staticTexts["预约价"]
    var preorderScroll = 0
    while !preorderRow.exists && preorderScroll < 6 {
      app.swipeUp()
      usleep(500_000)
      preorderScroll += 1
    }
    XCTAssertTrue(preorderRow.exists, "详情页应在现货价下方渲染「预约价」行")
    if preorderRow.exists {
      XCTAssertGreaterThanOrEqual(
        preorderRow.frame.minY, bodyPrice.frame.minY,
        "预约价行应在价格行之下（价格行之后才出现）")
    }

    // 3. 信息行齐备：尺码（从小到大）。
    //    「包含款式」行与「单品尺码表」入口均已按用户要求移除
    //    （尺码表统一由款式对应图各组内嵌承载）——反而断言它们不存在，防止回归。
    let containsVariants = app.staticTexts["包含款式"]
    let sizesRow = app.staticTexts["尺码"]
    let sizesValue = app.staticTexts["XS / S / M / L / XL / XXL / F"]
    let chartEntry = app.staticTexts["单品尺码表"]
    var scrolled = 0
    while !sizesValue.exists && scrolled < 8 {
      app.swipeUp()
      usleep(500_000)
      scrolled += 1
    }
    capture("62-详情-信息区")
    XCTAssertFalse(
      containsVariants.exists, "「包含款式」行应已移除（用户 2026-09-16 要求）")
    XCTAssertFalse(
      chartEntry.exists, "「单品尺码表」折叠入口应已移除（与款式对应图组内尺码表重复）")
    XCTAssertTrue(sizesRow.exists, "应显示「尺码」行")
    XCTAssertTrue(
      sizesValue.exists,
      "尺码应从小到大排（XS / S / M / L / XL / XXL / F），实际未找到该排序文案")
    dumpHierarchy("63-详情-层级", app: app)

    // 3b. 款式对应图按款式归组：同款不同色一组（sk 粉+蓝绿 → 组「SK」），
    //     每组下方内嵌该款尺码表（组数应远小于 24 个款式，16 组各带一张表）。
    var groupScroll = 0
    let groupMarker = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "个配色")
    )
    let skChart = app.descendants(matching: .any)
      .matching(identifier: "midsummer-sizechart-SK")
      .firstMatch
    while !(groupMarker.count >= 2 && skChart.exists) && groupScroll < 10 {
      app.swipeUp()
      usleep(500_000)
      groupScroll += 1
    }
    capture("63b-详情-款式归组与组内尺码表")
    XCTAssertGreaterThanOrEqual(
      groupMarker.count, 2,
      "款式对应图应按款式归组（应有多组「N 个配色」标题），实际 \(groupMarker.count) 组")
    XCTAssertTrue(
      skChart.exists,
      "「SK」组下方应内嵌该款尺码表（midsummer-sizechart-SK 应在层级中）")

    // 4. 一键入库 → 规格面板：颜色分类 (24)，小物选项与 F 码同面板可选。
    let quickInsert = app.buttons["midsummer-detail-quick-insert"]
    guard quickInsert.waitForExistence(timeout: 5) else {
      dumpHierarchy("64-详情-找不到一键入库", app: app)
      XCTFail("详情页应有一键入库按钮")
      return
    }
    while !quickInsert.isHittable && scrolled < 12 {
      app.swipeUp()
      usleep(500_000)
      scrolled += 1
    }
    quickInsert.tap()
    sleep(2)

    let styleGroup = app.staticTexts["颜色分类"]
    let styleCount = app.staticTexts["(24)"]
    // 小物首项「草帽 生成色」（展示名已剥「现 」前缀）在选项网格后段，可能要滚动。
    let goodsOption = app.staticTexts["草帽 生成色"]
    // 价格档位组（用户 2026-09-16 新增）：颜色分类之后、尺码之前，四个档位选项；
    // 不被 SKU 引用 → 可选标注，不默认选中、不挡价格。
    let pricingGroup = app.staticTexts["价格档位"]
    let spotOption = app.buttons["spec-option-pricing-spot"]
    var drawerScroll = 0
    while !(styleGroup.exists && goodsOption.exists) && drawerScroll < 8 {
      app.swipeUp()
      usleep(500_000)
      drawerScroll += 1
    }
    capture("64-合并条目-规格面板")
    dumpHierarchy("65-规格面板层级", app: app)
    XCTAssertTrue(styleGroup.exists, "规格面板应渲染「颜色分类」组")
    XCTAssertTrue(styleCount.exists, "颜色分类组应带选项总数 (24)")
    XCTAssertTrue(goodsOption.exists, "颜色分类应含小物选项「草帽 生成色」（已并入主条目）")

    var pricingScroll = 0
    while !(pricingGroup.exists && spotOption.exists) && pricingScroll < 6 {
      app.swipeUp()
      usleep(500_000)
      pricingScroll += 1
    }
    XCTAssertTrue(pricingGroup.exists, "规格面板应在颜色分类后渲染「价格档位」组")
    XCTAssertTrue(spotOption.exists, "价格档位应含「现货价」选项")

    // 「F码」选项是按钮（缩略格子版式），不是 staticText——按任意元素类型查询。
    let sizeOption = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "F码"))
      .firstMatch
    var sizeScroll = 0
    while !sizeOption.exists && sizeScroll < 6 {
      app.swipeUp()
      usleep(500_000)
      sizeScroll += 1
    }
    XCTAssertTrue(sizeOption.exists, "尺码组应含 F 码（小物均为均码）")
  }
}
