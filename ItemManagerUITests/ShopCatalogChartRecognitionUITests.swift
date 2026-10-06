//
//  ShopCatalogChartRecognitionUITests.swift
//  ItemManagerUITests
//
//  2026-10-01 需求「尺码表 / 价格表识别结果提示 + 移动端可视化板块」的**运行时取证**。
//
//  用户原文：
//    「针对尺码表和价格表的识别功能……用户提交数据后，系统需根据识别结果给出明确提示，
//      区分『识别成功』与『识别失败』两种状态，尺码表和价格表的识别都要分别提供对应的
//      结果提示。同时，该识别功能最终需要在手机端以可视化的板块形式展示出来，
//      请确保移动端的显示效果完整、适配良好。」
//
//  本文件逐条证明（都取真机截图，产物见测试结果附件）：
//    ① **面板内实时出结论**：粘贴内容后立刻出现结论板块，不必等提交；
//    ② **两态可区分**：失败画红「…识别失败」、成功画绿「…识别成功」，且成功时附表格预览；
//    ③ **两张表互不串台**：价格表板块只说「预约价格表」，尺码表板块只说「尺码表」；
//    ④ **提交后仍有明确提示**：失败时工具栏按钮变「仍要填入」（复用已有内容的出口），
//       成功后点「识别并填入」关面板，**面板外常驻的板块**依旧给出结论。
//
//  ⚠️ 判定与文案的唯一来源是共享包 `CatalogChartRecognition`。本用例只读板块
//     `shopCatalog.chartRecognition.headline` 的无障碍 label（= `summaryLine`），
//     **不自己拼「识别成功 / 识别失败」** —— 否则就成了第三套口径。
//
//  ⚠️ 输入一律 ASCII：中文在 `typeText` 下会走 IME，容易「敲了没进去」
//     （沿用 `ShopCatalogFormStateUITests` 的既有结论）。
//
//  ⚠️ **本机模拟器跑不到起点，会在入口处 `XCTSkip`**：承载尺码表 / 价格表识别入口的
//     「运营工具」只对 `creatorAccess.isWhitelistedCreator` 渲染（2026-09-25 起从
//     `isCreator` 收紧：本机的「创作者模式」调试开关不再能撬开它，
//     **未登录 iCloud = 不算白名单**）。模拟器没有 iCloud 登录 ⇒ 恒为 false。
//     这是既有环境限制，与本次改动无关 —— 所以如实 skip，而不是让用例永远红。
//     有白名单创作者身份的机器 / 真机上可直接跑。
//     本机替代取证见 `ItemManagerTests/CatalogChartRecognitionCardSnapshotTests.swift`
//     （离屏快照，还能把宽度与动态字体这两个适配变量钉住）。
//

import XCTest

final class ShopCatalogChartRecognitionUITests: XCTestCase {

  // MARK: - 文案常量（与共享包 `CatalogChartKind.displayName` 对应）

  private let priceHeadlineSuffix = "预约价格表识别成功"
  private let priceHeadlineFailureSuffix = "预约价格表识别失败"
  private let sizeHeadlineSuffix = "尺码表识别成功"
  private let sizeHeadlineFailureSuffix = "尺码表识别失败"

  private let pasteButtonLabel = "粘贴文本录入（推荐，最准）"

  /// 板块结论头的稳定标识（定义在 `CatalogChartRecognitionCard`）
  private let headlineIdentifier = "shopCatalog.chartRecognition.headline"
  /// 板块根容器标识
  private let cardIdentifier = "shopCatalog.chartRecognition.card"

  // 失败样本：列名齐、数据行只填了第一格 → 填写率 2/8 = 0.25 < 门禁 0.4
  private let failingTable = """
  Style,Price,Deposit,Balance
  Dress:318
  Skirt:268
  """

  private let tidyPriceTable = """
  Style,Price,Deposit,Balance
  Dress:318,91,227
  Skirt:268,80,188
  """

  private let failingSizeTable = """
  Size,Bust,Waist,Length
  S:86
  M:92
  """

  private let tidySizeTable = """
  Size,Bust,Waist,Length
  S:86,66,110
  M:92,72,114
  """

  override func setUpWithError() throws {
    // 价格表 / 尺码表两条链路要一轮跑完：任一失败不阻断另一条
    continueAfterFailure = true
  }

  // MARK: - 用例一：预约价格表（批次详情 → 一站式系列配置）

  @MainActor
  func testPriceChartRecognitionBoardShowsDistinctSuccessAndFailure() throws {
    let app = launchApp()
    try enterBatchDetail(app)
    materializeSeriesConfig(app)

    openChartPasteSheet(app, navigatingTo: "识别价格表文本")
    capture(app, "价格表-01-面板初始态")

    // ── 识别失败 ────────────────────────────────────────────────────────────
    typePastedText(app, failingTable)
    settleKeyboard(app)

    XCTAssertTrue(waitForHeadline(app, timeout: 8),
                  "粘贴内容后应立刻出现识别结论板块（面板内实时判定）")
    capture(app, "价格表-02-识别失败")
    let failureLabel = headlineLabel(app)
    print("PRICECHART 失败态 headline=\(failureLabel)")
    XCTAssertTrue(failureLabel.contains(priceHeadlineFailureSuffix),
                  "失败态应明确写「\(priceHeadlineFailureSuffix)」，实际=\(failureLabel)")
    XCTAssertFalse(failureLabel.contains("尺码表"),
                   "价格表板块不许提尺码表（两张表的提示不能串台）")
    XCTAssertTrue(app.buttons["仍要填入"].waitForExistence(timeout: 4),
                  "失败且已有内容可填时，出口应是「仍要填入」而不是直接写库")

    // ── 识别成功 ────────────────────────────────────────────────────────────
    clearPastedText(app)
    typePastedText(app, tidyPriceTable)
    settleKeyboard(app)

    XCTAssertTrue(waitForHeadline(app, timeout: 8), "修正文本后应仍能看到识别结论板块")
    capture(app, "价格表-03-识别成功")
    let successLabel = headlineLabel(app)
    print("PRICECHART 成功态 headline=\(successLabel)")
    XCTAssertTrue(successLabel.contains(priceHeadlineSuffix),
                  "成功态应明确写「\(priceHeadlineSuffix)」，实际=\(successLabel)")
    XCTAssertFalse(successLabel.contains("尺码表"),
                   "价格表板块不许提尺码表（两张表的提示不能串台）")
    XCTAssertTrue(app.buttons["识别并填入"].waitForExistence(timeout: 4),
                  "成功时出口应是「识别并填入」")

    // 成功态必须能看见识别到的表格（可视化板块的核心价值）
    scrollUntilVisible(app, app.staticTexts["Dress"], what: "识别到的表格预览行")
    capture(app, "价格表-04-识别成功-表格预览")
    XCTAssertTrue(app.staticTexts["318"].exists || app.staticTexts["91"].exists,
                  "成功态应展示识别到的具体数值，不能只给一句「成功」")

    // ── 提交：关面板后常驻板块仍给结论（用户诉求的「提交后给明确提示」）──────────
    app.buttons["识别并填入"].tap()
    XCTAssertFalse(app.navigationBars["识别价格表文本"].waitForExistence(timeout: 3),
                   "点「识别并填入」后应关闭识别面板")

    let persistentCard = app.descendants(matching: .any)
      .matching(identifier: cardIdentifier).firstMatch
    XCTAssertTrue(scrollUntilVisible(app, persistentCard, what: "面板外常驻的识别结果板块"),
                  "关闭面板后，录入处应常驻显示识别结果板块")
    capture(app, "价格表-05-提交后常驻提示")
    let persistentLabel = headlineLabel(app)
    print("PRICECHART 提交后常驻 headline=\(persistentLabel)")
    XCTAssertTrue(persistentLabel.contains(priceHeadlineSuffix),
                  "提交后常驻板块应仍写明结论，实际=\(persistentLabel)")
  }

  // MARK: - 用例二：尺码表（批次详情 → 补录草稿编辑器）

  @MainActor
  func testSizeChartRecognitionBoardShowsDistinctSuccessAndFailure() throws {
    let app = launchApp()
    try enterBatchDetail(app)
    enterDraftDetailEditor(app)

    openChartPasteSheet(app, navigatingTo: "识别尺码表文本")
    capture(app, "尺码表-01-面板初始态")

    // ── 识别失败 ────────────────────────────────────────────────────────────
    typePastedText(app, failingSizeTable)
    settleKeyboard(app)

    XCTAssertTrue(waitForHeadline(app, timeout: 8),
                  "粘贴内容后应立刻出现识别结论板块（面板内实时判定）")
    capture(app, "尺码表-02-识别失败")
    let failureLabel = headlineLabel(app)
    print("SIZECHART 失败态 headline=\(failureLabel)")
    XCTAssertTrue(failureLabel.contains(sizeHeadlineFailureSuffix),
                  "失败态应明确写「\(sizeHeadlineFailureSuffix)」，实际=\(failureLabel)")
    XCTAssertFalse(failureLabel.contains("价格表"),
                   "尺码表板块不许提价格表（两张表的提示不能串台）")

    // ── 识别成功 ────────────────────────────────────────────────────────────
    clearPastedText(app)
    typePastedText(app, tidySizeTable)
    settleKeyboard(app)

    XCTAssertTrue(waitForHeadline(app, timeout: 8), "修正文本后应仍能看到识别结论板块")
    capture(app, "尺码表-03-识别成功")
    let successLabel = headlineLabel(app)
    print("SIZECHART 成功态 headline=\(successLabel)")
    XCTAssertTrue(successLabel.contains(sizeHeadlineSuffix),
                  "成功态应明确写「\(sizeHeadlineSuffix)」，实际=\(successLabel)")
    XCTAssertFalse(successLabel.contains("价格表"),
                   "尺码表板块不许提价格表（两张表的提示不能串台）")

    scrollUntilVisible(app, app.staticTexts["Bust"], what: "识别到的尺码表列名")
    capture(app, "尺码表-04-识别成功-表格预览")
    XCTAssertTrue(app.staticTexts["86"].exists || app.staticTexts["110"].exists,
                  "成功态应展示识别到的具体数值，不能只给一句「成功」")
  }

  // MARK: - 启动与导航

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-test-enable-creator-mode"]
    app.launch()
    dismissSystemPrompts(app)
    dismissDailyCheckIn(app)
    return app
  }

  @MainActor
  private func enterBatchDetail(_ app: XCUIApplication) throws {
    let meTab = app.buttons["我"]
    XCTAssertTrue(meTab.waitForExistence(timeout: 15), "底部 dock 应有「我」tab")
    meTab.tap()
    sleep(2)

    // 入口被白名单门控挡住时**如实跳过**，详见文件头注释。
    guard app.staticTexts["运营工具"].waitForExistence(timeout: 10) else {
      throw XCTSkip("本机模拟器拿不到「运营工具」入口：该入口只对 isWhitelistedCreator 渲染，"
        + "模拟器未登录 iCloud ⇒ 恒为 false（2026-09-25 起，调试开关撬不开）。"
        + "请在具备白名单创作者身份的机器 / 真机上重跑；本机替代取证见 "
        + "ItemManagerTests/CatalogChartRecognitionCardSnapshotTests.swift。")
    }

    tapScrollable(app, app.staticTexts["运营工具"], what: "运营工具入口")
    XCTAssertTrue(app.navigationBars["店家商品库"].waitForExistence(timeout: 12),
                  "应进入店家商品库")

    let addMenu = app.buttons["＋ 补录上新"]
    XCTAssertTrue(addMenu.waitForExistence(timeout: 8), "应有「＋ 补录上新」入口")
    addMenu.tap()

    let manual = app.buttons["手动录入（可连续添加多件）"]
    XCTAssertTrue(manual.waitForExistence(timeout: 6), "菜单里应有「手动录入」")
    manual.tap()

    XCTAssertTrue(app.navigationBars["批次详情"].waitForExistence(timeout: 12),
                  "应打开批次详情 sheet")
  }

  /// 让「系列配置」段落出现（价格表入口在该段内）
  @MainActor
  private func materializeSeriesConfig(_ app: XCUIApplication) {
    tapScrollable(app, app.buttons["应用到整批 1 条单品"], what: "应用到整批")
    sleep(2)
    tapScrollable(app, app.buttons["创建 / 确认系列并开始配置"], what: "创建/确认系列")
    sleep(3)
    XCTAssertTrue(app.buttons["添加封面图片"].waitForExistence(timeout: 10),
                  "归属落地后应出现系列配置段")
  }

  /// 批次详情 → 点入本批唯一那条草稿，进入「补录草稿」编辑器（尺码表入口在那里）
  @MainActor
  private func enterDraftDetailEditor(_ app: XCUIApplication) {
    let row = app.staticTexts["（未命名单品）"]
    XCTAssertTrue(scrollUntilVisible(app, row, what: "本批单品行「（未命名单品）」"),
                  "批次详情应列出本批草稿行")
    tapScrollable(app, row, what: "草稿行")
    XCTAssertTrue(app.navigationBars["补录草稿"].waitForExistence(timeout: 12),
                  "点入草稿行后应打开「补录草稿」编辑器")
  }

  /// 打开识别面板并核对标题（标题即「两张表各自出提示」的第一层：面板主语就不同）
  @MainActor
  private func openChartPasteSheet(_ app: XCUIApplication, navigatingTo title: String) {
    tapScrollable(app, app.buttons[pasteButtonLabel], what: "「\(pasteButtonLabel)」入口")
    XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 12),
                  "应打开标题为「\(title)」的识别面板")
  }

  // MARK: - 输入

  @MainActor
  private func typePastedText(_ app: XCUIApplication, _ text: String) {
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 10), "找不到粘贴文本输入区")
    editor.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                  "粘贴输入区拿不到焦点")
    editor.typeText(text)
  }

  @MainActor
  private func clearPastedText(_ app: XCUIApplication) {
    let clear = app.buttons["清空"]
    XCTAssertTrue(clear.waitForExistence(timeout: 5), "有内容时应出现「清空」按钮")
    clear.tap()
    sleep(1)
  }

  /// 收键盘。
  ///
  /// ⚠️ **不能用回车**：这里是 `TextEditor`，回车会往正文里插一个换行
  /// （`ShopCatalogFormStateUITests` 那套「回车收键盘」只适用于单行 `TextField`）。
  /// 所以直接走那条用例验证过的兜底：切后台再回前台，系统必然让第一响应者 resign。
  @MainActor
  private func settleKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.firstMatch.exists else { return }
    XCUIDevice.shared.press(.home)
    sleep(1)
    app.activate()
    _ = waitKeyboardGone(app, timeout: 8)
  }

  @MainActor
  private func waitKeyboardGone(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !app.keyboards.firstMatch.exists { return true }
      usleep(200_000)
    }
    return !app.keyboards.firstMatch.exists
  }

  // MARK: - 结论板块读取

  @MainActor
  private func headlineElement(_ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: headlineIdentifier).firstMatch
  }

  @MainActor
  private func headlineLabel(_ app: XCUIApplication) -> String {
    headlineElement(app).label
  }

  @MainActor
  private func waitForHeadline(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
    scrollUntilVisible(app, headlineElement(app), what: "识别结论板块", maxDrags: 6)
  }

  // MARK: - 滚动 / 点击工具

  /// 滚到元素可点再点它（口径与 `ShopCatalogFormStateUITests` 一致：
  /// 点击落在 dx 0.25 / dy 0.4，避开靠左按钮的整行 frame 与底部悬浮 dock）。
  @MainActor
  private func tapScrollable(_ app: XCUIApplication, _ element: XCUIElement, what: String) {
    XCTAssertTrue(element.waitForExistence(timeout: 10), "找不到元素：\(what)")
    dismissKeyboard(app)
    for _ in 0..<14 {
      if element.exists, element.isHittable {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4)).tap()
        return
      }
      if element.exists, element.frame.midY < 150 {
        drag(app, from: 0.36, to: 0.50)
      } else {
        drag(app, from: 0.70, to: 0.44)
      }
    }
    XCTFail("滚了 14 次仍点不到：\(what)")
  }

  /// 滚到元素**存在**（不要求可点）——用于「板块画出来了没有」这类断言。
  @MainActor
  @discardableResult
  private func scrollUntilVisible(_ app: XCUIApplication,
                                  _ element: XCUIElement,
                                  what: String,
                                  maxDrags: Int = 10) -> Bool {
    for _ in 0..<maxDrags {
      if element.exists { return true }
      drag(app, from: 0.60, to: 0.32)
    }
    if element.exists { return true }
    XCTFail("滚动 \(maxDrags) 次仍未找到：\(what)")
    return false
  }

  @MainActor
  private func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
    start.press(forDuration: 0.05, thenDragTo: end)
    usleep(400_000)
  }

  @MainActor
  private func dismissKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.firstMatch.exists else { return }
    app.typeText("\n")
    if waitKeyboardGone(app, timeout: 3) { return }
    XCUIDevice.shared.press(.home)
    sleep(1)
    app.activate()
    _ = waitKeyboardGone(app, timeout: 8)
  }

  // MARK: - 启动期弹窗

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
    if done.waitForExistence(timeout: 5) { done.tap() }
  }

  // MARK: - 取证

  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
