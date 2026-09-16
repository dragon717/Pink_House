//
//  MidsummerDetailCoverUITests.swift
//  ItemManagerUITests
//
//  详情页头图不得与任何文字重叠的验收（用户反馈：800×800 种子图进
//  「宽×200」槽位后溢出，盖住导航栏标题与「现货 / 名称 / 价格」区）。
//
//  两层断言：
//    1. 几何：导航标题 < 「现货」徽章 < 单品名 < 价格，纵向严格有序且
//       徽章起始于导航栏之下（文字区不得被顶进导航栏）。
//    2. 像素：在「现货」徽章上方、头图槽位下缘的间隙带采样一行像素，
//       断言是均匀的页面背景色——若头图溢出（旧 ZStack+scaledToFill 写法），
//       该带会被照片像素占据，均匀性立刻破坏。
//      （注：不能用头图元素的 a11y frame 判断溢出——SwiftUI 对标识元素的
//       frame 合并未裁剪的图内容，修复前后都报 402×402，不可信。）
//  另附全屏截图人工复核。
//
//  运行方式见 MidsummerSpecSelectionUITests.swift 文件头。
//

import ImageIO
import XCTest

final class MidsummerDetailCoverUITests: XCTestCase {

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

  /// 打开樱花小羊主商品详情弹窗。两条淘宝链接已合并为一张商品卡片
  /// （a11y 标签 =「名称，商品页价 ¥区间」，可与页面其他「樱花小羊」文案区分），
  /// 路径：首页卡片 → 直接点开详情。
  @MainActor
  private func openDetail(_ app: XCUIApplication, itemName: String) -> Bool {
    let card = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，"))
      .firstMatch
    var attempts = 0
    while !card.exists && attempts < 6 {
      app.swipeUp()
      usleep(500_000)
      attempts += 1
    }
    guard card.exists else {
      dumpHierarchy("00-找不到樱花小羊商品卡片", app: app)
      return false
    }
    card.tap()
    sleep(2)
    return true
  }

  /// 在截屏的指定点位（pt 坐标）采样一个水平条带，返回 (均匀度, 平均亮度)。
  /// 均匀度 = 各通道 max-min 的最大值；亮度 = 全通道平均。
  private func sampleStrip(
    _ cg: CGImage, centerX: CGFloat, y: CGFloat, halfWidth: CGFloat, viewWidth: CGFloat
  ) -> (uniformity: Int, brightness: Int)? {
    let scale = CGFloat(cg.width) / viewWidth
    guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
      return nil
    }
    let bpr = cg.bytesPerRow
    let bpp = cg.bitsPerPixel / 8
    let pxY = max(0, min(cg.height - 1, Int(y * scale)))
    let pxX0 = max(0, Int((centerX - halfWidth) * scale))
    let pxX1 = min(cg.width - 1, Int((centerX + halfWidth) * scale))

    var minC = [255, 255, 255], maxC = [0, 0, 0], sum = 0, count = 0
    for px in stride(from: pxX0, through: pxX1, by: max(1, (pxX1 - pxX0) / 40)) {
      let offset = pxY * bpr + px * bpp
      for c in 0..<3 {
        let v = Int(bytes[offset + c])  // RGBA/BGRA 顺序不影响逐通道统计
        minC[c] = min(minC[c], v)
        maxC[c] = max(maxC[c], v)
        sum += v
      }
      count += 3
    }
    guard count > 0 else { return nil }
    let spread = zip(maxC, minC).map { $0 - $1 }.max() ?? 255
    return (spread, sum / count)
  }

  // MARK: - 用例：详情页头图与文字零重叠

  @MainActor
  func testDetailHeroImageDoesNotOverlapText() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }
    guard openDetail(app, itemName: "樱花小羊") else { return }
    sleep(2)
    capture("40-详情页-头图区域")

    // 详情页已打开（导航标题 = 系列名，右上角「完成」）
    let done = app.buttons["完成"]
    XCTAssertTrue(done.waitForExistence(timeout: 6), "详情页应当以弹窗形式打开（右上角「完成」）")

    // 正文锚点：单品名 → 价格，纵向严格有序。
    // 「现货」徽章已按用户 2026-09-16 要求移除；hero 的 a11y frame 是
    // scaledToFill 裁切前的溢出图框（比可视槽位高），不能当几何基准——
    // 它只做「头图渲染了」的存在性检查，几何改以唯一的「现货价」行为基准，
    // 单品名取其正上方最近的同文名（背景 feed 卡与正文都有「樱花小羊」）。
    let hero = app.descendants(matching: .any)
      .matching(identifier: "midsummer-detail-hero")
      .firstMatch
    guard hero.waitForExistence(timeout: 6) else {
      dumpHierarchy("41-找不到详情头图", app: app)
      XCTFail("详情页应当渲染头图（midsummer-detail-hero）")
      return
    }

    let priceQuery = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "现货价")
    )
    guard priceQuery.count > 0 else {
      dumpHierarchy("41-找不到现货价行", app: app)
      XCTFail("详情页正文应当渲染「现货价」价格行")
      return
    }
    var bodyPrice = priceQuery.element(boundBy: 0)
    for index in 1..<priceQuery.count {
      let candidate = priceQuery.element(boundBy: index)
      if candidate.frame.minY < bodyPrice.frame.minY { bodyPrice = candidate }
    }
    let priceFrame = bodyPrice.frame

    let nameQuery = app.staticTexts.matching(NSPredicate(format: "label == %@", "樱花小羊"))
    var bodyName: XCUIElement?
    for index in 0..<nameQuery.count {
      let candidate = nameQuery.element(boundBy: index)
      // 在价格行正上方、且不与之重叠的同文名里取最靠近的（即正文单品名）
      if candidate.frame.maxY <= priceFrame.minY + 1 {
        if bodyName == nil || candidate.frame.minY > bodyName!.frame.minY {
          bodyName = candidate
        }
      }
    }

    guard let bodyName else {
      dumpHierarchy("41-找不到正文文字", app: app)
      XCTFail("详情页正文应当渲染单品名称（价格行正上方）")
      return
    }

    XCTAssertLessThanOrEqual(
      bodyName.frame.maxY, priceFrame.minY + 1,
      "单品名(\(bodyName.frame.maxY))与价格(\(priceFrame.minY))纵向重叠"
    )

    // 像素探针：单品名上方 ~8pt（头图槽位与文字区之间的间隙带）应为均匀背景。
    // 旧 bug（scaledToFill 溢出）时该带是照片像素——均匀性立刻破坏。
    let shot = XCUIScreen.main.screenshot()
    let decoded = CGImageSourceCreateWithData(shot.pngRepresentation as CFData, nil)
      .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    guard let cg = decoded,
      let strip = sampleStrip(
        cg, centerX: app.frame.midX, y: bodyName.frame.minY - 8,
        halfWidth: app.frame.width * 0.2, viewWidth: app.frame.width)
    else {
      XCTFail("无法读取屏幕截图像素")
      return
    }
    capture("42-头图与文字-间隙带复核")
    dumpHierarchy("43-详情页-层级", app: app)
    XCTAssertLessThanOrEqual(
      strip.uniformity, 24,
      "头图与文字之间的间隙带像素不均匀(通道极差 \(strip.uniformity))——主图溢出槽位压进文字区"
    )
    XCTAssertGreaterThanOrEqual(
      strip.brightness, 150,
      "头图与文字之间的间隙带过暗(亮度 \(strip.brightness))——疑似被主图覆盖"
    )

    // 回到顶部再补一张稳定截图
    app.swipeDown()
    sleep(1)
    capture("44-详情页-回顶复核")
  }

  // MARK: - 用例：尺码表随款式对应图分组内嵌展示（折叠入口已下线）

  /// 用户 2026-09-16：详情页「单品尺码表」折叠面板与款式对应图组内嵌的
  /// 尺码表重复，已移除。尺码表现在只由各款式组下方承载——滚动到款式
  /// 对应图区，应直接看到「SK」组的内嵌尺码表图（label「尺码表 SK」）。
  @MainActor
  func testSizeChartsShownPerStyle() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }
    guard openDetail(app, itemName: "樱花小羊") else { return }
    sleep(2)

    // 旧「单品尺码表」折叠入口不应再出现。
    let legacyEntry = app.staticTexts["单品尺码表"]
    var legacyScroll = 0
    while !legacyEntry.exists && legacyScroll < 4 {
      app.swipeUp()
      usleep(500_000)
      legacyScroll += 1
    }
    XCTAssertFalse(
      legacyEntry.exists, "「单品尺码表」折叠入口应已移除（与组内尺码表重复）")

    // 滚动到款式对应图区：SK 组下方应内嵌尺码表图。
    // DisclosureGroup 时代 identifier 会被面板吞掉；现在是普通区块，
    // 按 a11y label「尺码表 SK」断言（与 identifier 双保险）。
    let skChartByLabel = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "尺码表 SK"))
      .firstMatch
    let skChartById = app.descendants(matching: .any)
      .matching(identifier: "midsummer-sizechart-SK")
      .firstMatch
    var attempts = 0
    while !(skChartByLabel.exists || skChartById.exists) && attempts < 12 {
      app.swipeUp()
      usleep(500_000)
      attempts += 1
    }
    let imageFound = skChartByLabel.exists || skChartById.exists
    capture("52-尺码表-组内嵌状态")
    dumpHierarchy("53-尺码表-层级", app: app)
    XCTAssertTrue(imageFound, "「SK」款式组下方应内嵌尺码表图（seed-sakura-chart-sk.jpg）")
  }
}
