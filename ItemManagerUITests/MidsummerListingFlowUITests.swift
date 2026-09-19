//
//  MidsummerListingFlowUITests.swift
//  ItemManagerUITests
//
//  上新工作台（仲夏物语全系列 · 用户 2026-09-16，2026-09-18 起统一扩展到
//  品牌下所有系列）全流程验收：
//    发布新商品 → ①系列主图与信息（标题 / 日期）→ ②选择上新阶段
//    → ③分类与款式（款式逐款录入、商品名自动取首个款式名、
//      预约价 / 定金固定显示、尾款自动核算）
//    → ④确认发布（原文出处 + 提交汇总）→ 发布上架
//    → 上架商品出现在工作台列表（已上架）→ 出现在系列详情商品列表
//    → 详情页一键入库（规格抽屉带出继承的款式组）。
//
//  入口：系列详情「上新管理」——2026-09-16 深夜起去掉 canContribute 门控
//  （旧投稿表单已删除），2026-09-18 起改为**按创作者角色门控**：
//  普通用户看不到入口，创作者可见可进。本文件用启动参数
//  `-ui-test-enable-creator-mode` 解闸，跑的是创作者视角全流程。
//
//  访问性标识契约（改产品代码时同步改本文件）：
//    · 系列详情入口        → series-listing-workspace-button
//    · 工作台发布按钮      → listing-open-form
//    · 顶栏                → listing-cancel / listing-save-draft
//    · ①主图与信息        → listing-launch-title / listing-date-toggle
//                            listing-launch-date / listing-image-add / listing-note
//    · ②上新阶段          → listing-stage-<raw>
//    · ③分类与款式        → listing-size-<size> / listing-size-custom / listing-size-add
//                            listing-size-input-<i> / listing-size-delete-<i>
//                            listing-style-<optionID> / listing-style-custom / listing-style-add
//                            listing-style-image-<i> / listing-style-name-<i>
//                            listing-style-delete-<i>
//                            listing-style-batch-toggle / -input / -add
//                            listing-preorder / listing-deposit-toggle / listing-deposit
//                            listing-balance-auto / listing-balance-hint / listing-balance-error
//    · ④确认发布          → listing-source
//    · 步骤导航            → listing-next / listing-back / listing-publish
//    · 工作台行            → listing-edit-<id> / listing-more-<id>
//                            listing-price-<id>（改价快捷按钮，2026-09-18）
//    · 价格总表（工作台）  → workspace-price-table / listing-price-row-<id>
//    · 改价面板            → price-edit-shop / price-edit-preorder
//                            price-edit-deposit / price-edit-balance / price-edit-save
//                            price-edit-image-add / price-edit-image-preview-<i>
//    · 系列详情价格总表    → series-price-table / series-price-row-<itemId>（创作者视图可点）
//    · 状态菜单            → listing-menu-list-<id> / listing-menu-delist-<id> / listing-menu-delete-<id>

import XCTest

final class MidsummerListingFlowUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = true
  }

  // MARK: - 启动与导航

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    // 2026-09-18 起创作者能力（上新管理 / 改价 / 换图）按角色门控：
    // 本文件跑的全是创作者流程，必须先用启动参数解闸，否则入口不渲染。
    // 普通用户「看不到入口」的验收在 TimeHallEntryExplorationUITests
    // `testD2_ListingWorkspaceEntryHiddenForViewer`。
    app.launchArguments += ["-ui-test-reset-creator-mode", "-ui-test-enable-creator-mode"]
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

  /// 「全部商品 → 系列列表 → 指定系列」进系列详情（上新管理入口在那里）。
  /// 仲夏物语全系列共用同一套上新指令链（用户 2026-09-18 扩展），
  /// 入口按系列名参数化；默认樱花小羊（种子数据最全）。
  @MainActor
  private func enterSeries(_ app: XCUIApplication, _ name: String = "樱花小羊") -> Bool {
    let allEntry = app.buttons["midsummer-entry-all-series"]
    guard allEntry.waitForExistence(timeout: 10) else {
      dumpHierarchy("80-找不到全部商品入口", app: app)
      XCTFail("品牌页应有「全部商品」入口行")
      return false
    }
    allEntry.tap()
    sleep(2)

    let seriesRow = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH %@", "\(name)，"))
      .firstMatch
    guard seriesRow.waitForExistence(timeout: 10) else {
      dumpHierarchy("81-找不到\(name)系列行", app: app)
      XCTFail("系列列表应有「\(name)」行")
      return false
    }
    seriesRow.tap()
    sleep(2)
    return true
  }

  /// 兼容旧调用点：樱花小羊入口。
  @MainActor
  private func enterSakuraSeries(_ app: XCUIApplication) -> Bool {
    enterSeries(app, "樱花小羊")
  }

  /// 双向滚动查找（2026-09-18）：先向上滑（找下方内容），不行再向下滑
  ///（找上方内容）。
  /// 安全约束：表单是可下拉关闭的 sheet——内容滚到顶后继续 swipeDown 会把
  /// sheet 拉关。所以向下滑限制 3 次、任何时刻元素消失（sheet 被关）边滚边查（懒容器兼容）。
  @MainActor
  private func scrollToElement(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
    // 懒容器（LazyVGrid / LazyVStack）里的元素在滚进视口前 exists == false，
    // 所以不能先查 exists 再滚动——必须「边滚边查」，否则首屏外的懒元素
    // 会被直接判「不存在」（2026-09-18 表单卡序调整后踩坑）。
    var swipes = 0
    while swipes < maxSwipes {
      if element.exists && element.isHittable { return true }
      app.swipeUp()
      usleep(400_000)
      swipes += 1
    }
    swipes = 0
    while swipes < 3 {
      if element.exists && element.isHittable { return true }
      app.swipeDown()
      usleep(400_000)
      swipes += 1
    }
    return element.exists && element.isHittable
  }

  /// 可靠收起数字键盘：数字键盘没有 return 键，且全屏 swipeDown 的落点
  /// 可能正好在键盘上（手势打在键盘上无效）。改为对 ScrollView 直接下拉——
  /// 表单开了 scrollDismissesKeyboard(.interactively)，下拉内容即跟手收键盘。
  @MainActor
  private func dismissKeyboard(_ app: XCUIApplication) {
    var tries = 0
    while app.keyboards.firstMatch.exists && tries < 5 {
      let scrollView = app.scrollViews.firstMatch
      if scrollView.exists {
        scrollView.swipeDown()
      } else {
        app.swipeDown()
      }
      usleep(600_000)
      tries += 1
    }
    sleep(1)
  }

  // MARK: - 用例：录入 → 上架 → 系列可见 → 一键入库

  @MainActor
  func testPublishListingAndInsertToWardrobe() throws {

    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app), enterSakuraSeries(app) else { return }

    // ① 打开上新工作台
    let workspaceButton = app.buttons["series-listing-workspace-button"]
    guard scrollToElement(workspaceButton, app: app) else {
      dumpHierarchy("82-找不到上新管理入口", app: app)
      XCTFail("樱花小羊系列详情应有「上新管理」入口（creator mode 已解闸）")
      return
    }
    workspaceButton.tap()
    sleep(2)

    let openForm = app.buttons["listing-open-form"]
    guard openForm.waitForExistence(timeout: 5) else {
      dumpHierarchy("83-找不到发布新商品入口", app: app)
      XCTFail("工作台应有「发布新商品」入口")
      return
    }
    openForm.tap()
    sleep(2)
    capture("84-表单-主图与信息")

    // ② ①系列主图与信息：系列标题（主图可选，直接下一步）
    let titleField = app.textFields["listing-launch-title"]
    guard titleField.waitForExistence(timeout: 5) else {
      dumpHierarchy("84-找不到系列标题输入框", app: app)
      XCTFail("表单第一步应有系列标题输入框")
      return
    }
    titleField.tap()
    titleField.typeText("小熊博物馆系列\n")
    usleep(500_000)
    capture("85-表单-主图与信息录入完成")
    app.buttons["listing-next"].tap()
    sleep(1)

    // ③ ②选择上新阶段：选「现货」→ 第 4 步应只显示现货价（联动断言在 ④ 里做）
    let stageChip = app.buttons["listing-stage-inStock"]
    guard stageChip.waitForExistence(timeout: 5) else {
      dumpHierarchy("86-找不到上新阶段选项", app: app)
      XCTFail("第二步应有「选择上新阶段」chips")
      return
    }
    stageChip.tap()
    sleep(1)
    capture("87-表单-上新阶段已选现货")
    app.buttons["listing-next"].tap()
    sleep(1)

    // ④ ③分类与款式（2026-09-18 晚改版）：尺码池在前、款式逐款录入在后。
    // 操作顺序严格**自上而下**（尺码 → 款式 → 价格）：表单是可下拉
    // 关闭的 sheet，任何「向上回滚」的滑动都可能把 sheet 拉关，全程只向下滚。
    // 价格项与阶段联动（2026-09-19）：现货阶段只显示现货价，不显示预约价组。
    XCTAssertTrue(
      app.textFields["listing-spot-price"].exists,
      "现货阶段价格卡应联动显示现货价输入"
    )
    XCTAssertFalse(
      app.textFields["listing-preorder"].exists,
      "现货阶段不应出现预约价（全款）输入（价格项只跟阶段走）"
    )

    // 尺码池在最上面：先选好 S，后面添加的款式会自动带上该尺码（逐款可再调整）
    let sizeChip = app.buttons["listing-size-S"]
    guard scrollToElement(sizeChip, app: app) else {
      dumpHierarchy("88-找不到尺码选项", app: app)
      XCTFail("「商品与尺码」步应有常用尺码 chips（XS/S/M/L/XL/XXL/均码/F）")
      return
    }
    sizeChip.tap()
    sleep(1)
    XCTAssertTrue(
      app.textFields["listing-size-custom"].exists,
      "尺码区应保留「新增尺码」自定义入口"
    )

    // 款式区在尺码池下方：勾选关联款式「sk 粉色」（每款需配尺码，自动带入池里的 S）
    let styleChip = app.buttons["listing-style-sk-pink"]
    guard scrollToElement(styleChip, app: app) else {
      dumpHierarchy("90-找不到款式关联选项", app: app)
      XCTFail("应能勾选关联款式「sk 粉色」")
      return
    }
    styleChip.tap()
    sleep(1)
    XCTAssertTrue(
      app.textFields["listing-style-custom"].exists,
      "款式区应保留自定义新增入口"
    )
    if sizeChip.exists && styleChip.exists {
      XCTAssertLessThan(
        sizeChip.frame.minY, styleChip.frame.minY,
        "尺码池应位于款式区上方（2026-09-18 晚改版：先选尺码池，再逐款录入）")
    }

    // 价格卡在最底部：填现货价（现货阶段的必填口径，2026-09-19 阶段联动）。
    let spotField = app.textFields["listing-spot-price"]
    if scrollToElement(spotField, app: app) {
      spotField.tap()
      spotField.typeText("199")
      dismissKeyboard(app)
    }
    capture("91-表单-商品与尺码录入完成")
    app.buttons["listing-next"].tap()
    sleep(1)

    // ⑥ ④确认发布：汇总 + 发布上架
    let publish = app.buttons["listing-publish"]
    guard publish.waitForExistence(timeout: 4) else {
      dumpHierarchy("92-找不到发布按钮", app: app)
      XCTFail("最后一步应有「发布上架」按钮")
      return
    }
    publish.tap()
    sleep(2)

    // ⑦ 工作台列表应出现已上架行（商品名自动取首个款式名「现 sk 粉色」）
    let listedRow = app.staticTexts["现 sk 粉色"]
    guard listedRow.waitForExistence(timeout: 6) else {
      dumpHierarchy("93-工作台找不到上架行", app: app)
      XCTFail("发布后工作台应列出自动命名的「现 sk 粉色」")
      return
    }
    capture("94-工作台-已上架")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label == %@", "已上架")).firstMatch.exists,
      "新发布商品的状态应为「已上架」"
    )

    // ⑥ 关闭工作台 → 系列详情商品列表应出现新商品
    let done = app.buttons["完成"].firstMatch
    if done.exists { done.tap() }
    // 等工作台 sheet 真正收起（否则屏上会有两处同名文本，tap 报 multiple matches）
    var closeWaits = 0
    while app.buttons["listing-open-form"].exists && closeWaits < 10 {
      usleep(500_000)
      closeWaits += 1
    }
    sleep(2)

    // 价格总表里也有商品名（¥199 行），不能用文案匹配——
    // 用商品行名的 ASCII identifier 前缀锁定（listing 单品 id 带
    // `midsummer-listing-` 命名空间）。
    let seriesItem = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "midsummer-series-item-midsummer-listing-"))
      .firstMatch
    guard scrollToElement(seriesItem, app: app, maxSwipes: 12) else {
      dumpHierarchy("92-系列详情找不到上架商品", app: app)
      XCTFail("上架商品应出现在系列详情的商品列表里")
      return
    }
    capture("93-系列详情-上架商品可见")

    // ⑦ 点开新商品详情 → 一键入库（规格抽屉带出继承的款式组）→ 确认入库
    seriesItem.tap()
    sleep(2)
    let quickInsert = app.buttons["midsummer-detail-quick-insert"]
    guard quickInsert.waitForExistence(timeout: 6) else {
      dumpHierarchy("94-新商品详情找不到一键入库", app: app)
      XCTFail("上架商品的详情页应有「一键入库」（衣橱深度结合的落点）")
      return
    }
    quickInsert.tap()
    sleep(2)

    // 规格抽屉应带出继承的款式组（关联款「现 sk 粉色」，展示名剥「现 」）
    let drawerOption = app.buttons["spec-option-style-sk-pink"]
    XCTAssertTrue(
      drawerOption.waitForExistence(timeout: 5),
      "规格抽屉应继承系列款式组并默认选中关联款「sk 粉色」"
    )
    capture("95-新商品-规格抽屉")

    let confirm = app.buttons["spec-confirm"]
    guard confirm.exists else {
      dumpHierarchy("96-新商品抽屉找不到确认按钮", app: app)
      XCTFail("规格抽屉应有确认按钮")
      return
    }
    confirm.tap()
    sleep(3)
    capture("97-新商品-入库反馈")

    let toast = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "已加入衣橱")
    ).firstMatch
    XCTAssertTrue(toast.exists, "确认后应出现「已加入衣橱」反馈（上架商品走既有入库链路）")
    if toast.exists {
      // 断言锁定「商品名 + 继承的规格」这两个本质点。
      XCTAssertTrue(
        toast.label.contains("现 sk 粉色"),
        "入库反馈应写明商品名，实际是：\(toast.label)")
      XCTAssertTrue(
        toast.label.contains("现 sk 粉色") && toast.label.contains("S码"),
        "入库反馈应带出继承自系列的规格（款式 / 尺码），实际是：\(toast.label)")
    }
  }

  // MARK: - 用例：③尺码项可新增 / 编辑 / 删除（2026-09-17 四步重写）

  @MainActor
  func testSizeItemsCanBeAddedEditedAndDeleted() throws {
    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app), enterSakuraSeries(app) else { return }
    guard openForm(app) else { return }

    // ① 系列标题
    let titleField = app.textFields["listing-launch-title"]
    guard titleField.waitForExistence(timeout: 5) else {
      dumpHierarchy("S0-找不到标题输入框", app: app)
      XCTFail("第一步应有系列标题输入框")
      return
    }
    focusAndType(app, "尺码验收系列\n", into: titleField)
    usleep(400_000)
    app.buttons["listing-next"].tap()
    sleep(1)
    capture("S1-已填标题")

    // ② 上新阶段：现货
    let stageChip = app.buttons["listing-stage-inStock"]
    guard stageChip.waitForExistence(timeout: 5) else {
      XCTFail("第二步应能选上新阶段")
      return
    }
    stageChip.tap()
    app.buttons["listing-next"].tap()
    sleep(1)

    // ③ 尺码：自定义新增
    let customField = app.textFields["listing-size-custom"]
    guard scrollToElement(customField, app: app) else {
      dumpHierarchy("S2-找不到自定义尺码输入框", app: app)
      XCTFail("第三步应有「新增尺码」输入框")
      return
    }
    customField.tap()
    focusAndType(app, "70-75", into: customField)
    app.buttons["listing-size-add"].tap()
    sleep(1)
    capture("S2-新增自定义尺码")
    XCTAssertTrue(
      app.textFields["listing-size-input-0"].exists,
      "新增的尺码应出现在可编辑列表中（listing-size-input-0）"
    )

    // 编辑：焦点落到行内输入框后追加「F」（TextField 本身可编辑；不碰键盘删除键——
    // 中文键盘的删除键可能滚不到可视区，AX 滚动会超时拖垮整条用例）
    let firstRow = app.textFields["listing-size-input-0"]
    if firstRow.waitForExistence(timeout: 4) {
      XCTAssertEqual(firstRow.value as? String, "70-75", "行内输入框应回显刚新增的尺码名")
      focusAndType(app, "F", into: firstRow)
    }
    capture("S3-编辑尺码名")

    // 常用尺码 chip：点一下加入，再点一下移除
    let presetS = app.buttons["listing-size-S"]
    guard scrollToElement(presetS, app: app) else {
      XCTFail("第三步应有常用尺码 chips")
      return
    }
    presetS.tap()
    sleep(1)
    XCTAssertTrue(
      app.textFields["listing-size-input-1"].exists,
      "常用尺码加入后应成为列表里的第 2 个可编辑项"
    )
    capture("S4-常用尺码加入列表")

    // 删除：删掉第 1 项（只剩 1 项）
    app.buttons["listing-size-delete-0"].tap()
    sleep(1)
    XCTAssertFalse(
      app.textFields["listing-size-input-1"].exists,
      "删除后列表应只剩 1 项"
    )
    capture("S5-删除尺码项")
  }

  // MARK: - 用例：定金可选、尾款自动核算（2026-09-18 口径，③分类与款式屏内）

  @MainActor
  func testDepositAndBalanceAreOptionalToggles() throws {
    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app), enterSakuraSeries(app) else { return }
    guard openForm(app) else { return }

    let titleField = app.textFields["listing-launch-title"]
    guard titleField.waitForExistence(timeout: 5) else { return }
    focusAndType(app, "定金阶段验收\n", into: titleField)
    usleep(400_000)
    app.buttons["listing-next"].tap()
    sleep(1)

    // ② 预约价阶段（2026-09-19 阶段收敛：定金+尾款并入预约价，可选阶段只剩预约价/现货）
    let preorderStage = app.buttons["listing-stage-preorder"]
    guard preorderStage.waitForExistence(timeout: 5) else {
      XCTFail("应能选择「预约价」阶段")
      return
    }
    preorderStage.tap()
    app.buttons["listing-next"].tap()
    sleep(1)
    // ③ 分类与款式（价格同屏）：定金开关固定显示；尾款无开关、自动核算
    sleep(1)
    let depositToggle = app.switches["listing-deposit-toggle"]
    guard scrollToElement(depositToggle, app: app) else {
      dumpHierarchy("P0-找不到定金开关", app: app)
      XCTFail("第 3 步价格卡应固定显示「配置定金」开关")
      return
    }
    capture("P1-预约价阶段价格配置")
    XCTAssertFalse(
      app.switches["listing-balance-toggle"].exists,
      "尾款已改为自动核算，不应再有手动开关"
    )
    XCTAssertFalse(
      app.textFields["listing-balance"].exists,
      "尾款无需手动填写，不应有尾款金额输入框"
    )

    // 定金开关默认关闭（2026-09-19 起不再自动打开）：手动打开走「定金+尾款」拆分填法。
    // 先填定金（此时页面未滚到底部，后续收键盘手势不会拉到 sheet），
    // 再填预约价——顺序反过来会在页面最底部做收键盘滑动，把表单 sheet 拉关。
    depositToggle.tap()
    sleep(1)
    let depositField = app.textFields["listing-deposit"]
    XCTAssertTrue(depositField.exists, "定金开关开着时应出现定金金额输入框")
    guard scrollToElement(depositField, app: app) else {
      dumpHierarchy("P1-定金金额输入框不可见", app: app)
      XCTFail("定金金额输入框应能滚动到可见")
      return
    }
    depositField.tap()
    depositField.typeText("50")

    let preorderField = app.textFields["listing-preorder"]
    guard scrollToElement(preorderField, app: app) else {
      dumpHierarchy("P0-找不到预约价输入框", app: app)
      XCTFail("价格卡应有预约价（全款）输入")
      return
    }
    preorderField.tap()
    preorderField.typeText("199")
    dismissKeyboard(app)
    sleep(1)

    // 尾款自动行：预约价 199 − 定金 50 = 尾款 149，区分显示。
    // combine 后是单一任意类型元素，用 any 查询（StaticText 可能查不到）。
    let autoBalance = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-balance-auto")).firstMatch
    XCTAssertTrue(autoBalance.waitForExistence(timeout: 4), "预约价与定金配齐后应出现尾款自动行")
    XCTAssertTrue(
      autoBalance.label.contains("149"),
      "尾款应自动算出 199 − 50 = 149（实际：\(autoBalance.label)）"
    )
    capture("P2-尾款自动核算")

    // 关掉定金开关 → 尾款自动行消失，回到「自动计算」提示
    guard scrollToElement(depositToggle, app: app) else {
      dumpHierarchy("P3-找不到定金开关", app: app)
      XCTFail("关定金断言前应能滚动到定金开关")
      return
    }
    depositToggle.tap()
    sleep(1)
    XCTAssertFalse(
      autoBalance.exists,
      "关掉定金后尾款自动行应消失"
    )
    XCTAssertTrue(
      app.staticTexts["listing-balance-hint"].exists,
      "关掉定金后应显示「填完预约价与定金后自动计算」提示"
    )
    capture("P3-关闭定金开关后")
  }

  // MARK: - 用例：提交前全量校验 + 步骤内报错

  @MainActor
  func testSubmitBlocksAndShowsErrorWhenRequiredMissing() throws {
    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app), enterSakuraSeries(app) else { return }
    guard openForm(app) else { return }

    // ① 什么都不填直接下一步 → 应报错并停在第一步
    app.buttons["listing-next"].tap()
    sleep(1)
    XCTAssertTrue(
      app.staticTexts["listing-step-error"].exists || app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@", "listing-step-error")).firstMatch.exists,
      "未填系列标题点下一步应就地报错"
    )
    capture("V1-第一步必填报错")
    XCTAssertTrue(
      app.buttons["listing-next"].exists,
      "报错后应停留在当前步骤"
    )

    // 填上标题继续
    let titleField = app.textFields["listing-launch-title"]
    focusAndType(app, "校验验收系列\n", into: titleField)
    usleep(400_000)
    app.buttons["listing-next"].tap()
    sleep(1)

    // ② 不选阶段直接下一步 → 报错
    app.buttons["listing-next"].tap()
    sleep(1)
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@", "listing-step-error")).firstMatch.exists,
      "未选上新阶段点下一步应就地报错"
    )
    capture("V2-第二步必填报错")

    // 选现货 → ③ 商品与尺码：不填款式直接点下一步 → 应就地报错且不前进
    app.buttons["listing-stage-inStock"].tap()
    app.buttons["listing-next"].tap()
    sleep(1)
    app.buttons["listing-next"].tap()
    sleep(1)
    let stepError3 = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-step-error")).firstMatch
    XCTAssertTrue(stepError3.exists, "③ 缺款式点下一步应就地报错")
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier == %@", "listing-step-progress")).firstMatch
        .label.contains("第 3 步"),
      "校验不通过应停留在第 3 步（实际：\(progressLabel(app))）")
    capture("V3-发布前全量校验拦截")
  }

  // MARK: - 工具

  /// 打开系列详情里的「上新管理」→「发布新商品」。
  @MainActor
  private func openForm(_ app: XCUIApplication) -> Bool {
    let workspaceButton = app.buttons["series-listing-workspace-button"]
    guard scrollToElement(workspaceButton, app: app) else {
      dumpHierarchy("F0-找不到上新管理入口", app: app)
      XCTFail("系列详情应有「上新管理」入口")
      return false
    }
    workspaceButton.tap()
    sleep(2)
    let openForm = app.buttons["listing-open-form"]
    guard openForm.waitForExistence(timeout: 5) else {
      dumpHierarchy("F1-找不到发布新商品", app: app)
      XCTFail("工作台应有「发布新商品」入口")
      return false
    }
    openForm.tap()
    sleep(2)
    return true
  }

  /// 稳妥输入：tap 后等键盘真弹出再 typeText（tap 偶发不聚焦，
  /// typeText 会在无焦点时直接抛 "Neither element nor any descendant has keyboard focus"）。
  /// 注：本 SDK 的 XCUIElement 没有 hasKeyboardFocus，用键盘是否出现作为焦点信号。
  @MainActor
  private func focusAndType(_ app: XCUIApplication, _ text: String, into field: XCUIElement) {
    for _ in 0..<6 {
      guard field.exists else {
        usleep(600_000)
        continue
      }
      field.tap()
      // 机器负载高时键盘弹出会明显变慢：用 waitForExistence 显式等，
      // 固定 sleep 太短会误判「没聚焦」，随后 typeText 直接抛错（历史踩坑）。
      if app.keyboards.firstMatch.waitForExistence(timeout: 4) {
        field.typeText(text)
        return
      }
    }
    // 最后兜底：直接尝试（失败会抛出，便于暴露真实问题）
    field.typeText(text)
  }

  /// 当前步骤进度文案（如「第 3 步 / 共 4 步」），用于断言「校验不通过不前进」。
  @MainActor
  private func progressLabel(_ app: XCUIApplication) -> String {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-step-progress"))
      .firstMatch.label
  }

  // MARK: - 用例：同一套指令链在另一系列生效（仲夏物语全系列统一 · 2026-09-18）
  //
  // 之前所有上新用例都从樱花小羊进入——那是「种子数据最全」的现实约束，
  // 不是产品边界。本用例换一个系列（小熊博物馆系列）完整走一遍：
  // 批量录入（原样命名，不拼前缀）+ 尾款自动核算 +
  // 预约价/定金（预约价阶段联动显示）+ 尾款自动核算 + 发布上架 → 系列可见，
  // 证明指令链是系列无关的，樱花小羊没有任何特权逻辑。

  @MainActor
  func testPublishListingOnAnotherSeries() throws {
    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app), enterSeries(app, "小熊博物馆系列") else { return }
    guard openForm(app) else { return }

    // ① 系列标题
    let titleField = app.textFields["listing-launch-title"]
    guard titleField.waitForExistence(timeout: 5) else {
      dumpHierarchy("C0-找不到系列标题输入框", app: app)
      XCTFail("第一步应有系列标题输入框（小熊博物馆系列）")
      return
    }
    focusAndType(app, "跨系列验收上新\n", into: titleField)
    usleep(400_000)
    app.buttons["listing-next"].tap()
    sleep(1)

    // ② 上新阶段：选「预约价」（尾款自动核算属于预约价阶段的填法）
    let stageChip = app.buttons["listing-stage-preorder"]
    guard stageChip.waitForExistence(timeout: 5) else {
      dumpHierarchy("C1-找不到上新阶段选项", app: app)
      XCTFail("第二步应有「选择上新阶段」chips")
      return
    }
    stageChip.tap()
    app.buttons["listing-next"].tap()
    sleep(1)

    // ③ 分类与款式：预约价阶段显示预约价 / 定金 / 尾款（阶段联动，跨系列同口径）
    XCTAssertTrue(
      app.textFields["listing-preorder"].exists,
      "跨系列预约价阶段也应显示预约价（全款）输入"
    )
    XCTAssertTrue(
      app.buttons["listing-deposit-toggle"].exists || app.switches["listing-deposit-toggle"].exists,
      "跨系列预约价阶段也应显示定金配置开关"
    )

    // 尺码池在款式区上方：先选一个常用尺码，批量加款式时会自动带上
    let presetSizeIDs = ["listing-size-XS", "listing-size-S", "listing-size-M",
                         "listing-size-L", "listing-size-XL", "listing-size-XXL",
                         "listing-size-均码", "listing-size-F"]
    let customSizeEntry = app.textFields["listing-size-custom"]
    var tappedSize = false
    for _ in 0..<6 {
      guard customSizeEntry.exists else { break }
      let visibleChip = app.buttons.matching(
        NSPredicate(format: "identifier IN %@", presetSizeIDs)
      ).allElementsBoundByIndex.first { $0.isHittable }
      if let chip = visibleChip {
        chip.tap()
        tappedSize = true
        break
      }
      guard customSizeEntry.exists else { break }
      app.swipeUp()
      usleep(400_000)
    }
    guard tappedSize else {
      dumpHierarchy("C6-找不到尺码选项", app: app)
      XCTFail("尺码区应有常用尺码 chips")
      return
    }
    sleep(1)

    // 批量录入款式（该系列没有可勾选的款式 chip，走批量入口）：
    // 输入纯颜色名，原样成为款式行（2026-09-19 起不再自动拼「分类+颜色」前缀）。
    let batchToggle = app.buttons["listing-style-batch-toggle"]
    guard scrollToElement(batchToggle, app: app) else {
      dumpHierarchy("C2-找不到批量录入入口", app: app)
      XCTFail("款式区应有「批量添加」折叠入口")
      return
    }
    batchToggle.tap()
    sleep(1)
    let batchInput = app.textViews["listing-style-batch-input"]
    guard batchInput.waitForExistence(timeout: 4) else {
      dumpHierarchy("C3-找不到批量输入框", app: app)
      XCTFail("批量添加展开后应有输入框")
      return
    }
    batchInput.tap()
    batchInput.typeText("白色、黑色")
    app.buttons["listing-style-batch-add"].tap()
    sleep(1)
    // 批量输入的键盘一直聚焦会让下方内容处于键盘后面（isHittable=false），
    // 且此时滚动位置在表单顶部，不能下拉收键盘（会把 sheet 拉关）。
    // 安全做法：点「收起批量添加」让 TextEditor 失焦、键盘随之收起。
    app.buttons["listing-style-batch-toggle"].tap()
    sleep(1)

    // 自动拼接断言（2026-09-19 更新）：输入什么就是什么，不再自动拼「OP 」前缀。
    // 款式卡容器 identifier（listing-style-card-0）不合并子元素，
    // 名字输入框自身带 listing-style-name-0。
    let styleName0 = app.textFields["listing-style-name-0"]
    guard scrollToElement(styleName0, app: app) else {
      dumpHierarchy("C4-找不到款式行", app: app)
      XCTFail("批量添加后应出现款式行")
      return
    }
    XCTAssertEqual(
      styleName0.value as? String, "白色",
      "批量录入应原样保留输入的颜色名（不再自动拼分类前缀）"
    )

    // 价格：预约价 + 开定金 → 尾款自动核算（跨系列同口径）
    let preorderField = app.textFields["listing-preorder"]
    guard scrollToElement(preorderField, app: app) else {
      dumpHierarchy("C7-找不到预约价输入框", app: app)
      XCTFail("价格卡应有预约价输入")
      return
    }
    preorderField.tap()
    preorderField.typeText("259")
    dismissKeyboard(app)

    let depositToggle = app.switches["listing-deposit-toggle"]
    if !depositToggle.exists {
      // 某些版本 Toggle 落在 buttons 里
      _ = app.buttons["listing-deposit-toggle"]
    }
    let toggleElement = depositToggle.exists ? depositToggle : app.buttons["listing-deposit-toggle"]
    guard scrollToElement(toggleElement, app: app) else {
      dumpHierarchy("C8-找不到定金开关", app: app)
      XCTFail("价格卡应有定金配置开关")
      return
    }
    if toggleElement.value as? String != "1" {
      toggleElement.tap()
      sleep(1)
    }
    let depositField = app.textFields["listing-deposit"]
    guard scrollToElement(depositField, app: app) else {
      dumpHierarchy("C9-找不到定金金额输入框", app: app)
      XCTFail("打开「配置定金」后应出现定金金额输入框")
      return
    }
    depositField.tap()
    depositField.typeText("60")
    dismissKeyboard(app)
    sleep(1)

    let autoBalance = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-balance-auto")).firstMatch
    XCTAssertTrue(autoBalance.waitForExistence(timeout: 4), "跨系列也应出现尾款自动行")
    XCTAssertTrue(
      autoBalance.label.contains("199"),
      "尾款应自动算出 259 − 60 = 199（实际：\(autoBalance.label)）"
    )
    capture("C10-跨系列-尾款自动核算")

    // ④ 发布
    app.buttons["listing-next"].tap()
    sleep(1)
    let publish = app.buttons["listing-publish"]
    guard publish.waitForExistence(timeout: 4) else {
      dumpHierarchy("C11-找不到发布按钮", app: app)
      XCTFail("最后一步应有「发布上架」按钮")
      return
    }
    publish.tap()
    sleep(2)

    // ⑤ 工作台列表出现已上架行（商品名没手动改过，应显示自动生成的「白色」）
    let listedRow = app.staticTexts["白色"]
    guard listedRow.waitForExistence(timeout: 6) else {
      dumpHierarchy("C12-工作台找不到上架行", app: app)
      XCTFail("发布后工作台应列出自动命名的「白色」")
      return
    }
    capture("C13-跨系列-工作台已上架")

    // ⑥ 关闭工作台 → 系列详情商品列表应出现新商品
    let done = app.buttons["完成"].firstMatch
    if done.exists { done.tap() }
    var closeWaits = 0
    while app.buttons["listing-open-form"].exists && closeWaits < 10 {
      usleep(500_000)
      closeWaits += 1
    }
    sleep(2)

    let seriesItem = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "midsummer-series-item-midsummer-listing-"))
      .firstMatch
    guard scrollToElement(seriesItem, app: app, maxSwipes: 12) else {
      dumpHierarchy("C14-系列详情找不到上架商品", app: app)
      XCTFail("上架商品应出现在小熊博物馆系列详情的商品列表里")
      return
    }
    capture("C15-跨系列-系列详情可见")
  }

  // MARK: - 用例：创作者改价入口（用户 2026-09-18）
  //
  // 发布现货商品（预约价 199 走表单必填口径）→ 工作台「系列价格总表」点该商品行
  // → 改价面板回显预约价 199 → 清空预约价、填现货价 399 → 保存
  // → 总表行立即显示「¥399」→ 关闭工作台，系列详情价格总表同步出现「¥399（现货价）」。
  // 商品图上传依赖系统相册权限，UI 用例不覆盖（面板内已带上传 / 替换 / 放大预览入口）。

  @MainActor
  func testEditListingPriceInWorkspace() throws {

    let app = launchApp()
    sleep(4)
    guard enterMidsummer(app), enterSakuraSeries(app) else { return }
    guard openForm(app) else { return }

    // ① 系列标题
    let titleField = app.textFields["listing-launch-title"]
    guard titleField.waitForExistence(timeout: 5) else {
      dumpHierarchy("P0-找不到系列标题输入框", app: app)
      XCTFail("第一步应有系列标题输入框")
      return
    }
    focusAndType(app, "改价验收系列\n", into: titleField)
    usleep(400_000)
    app.buttons["listing-next"].tap()
    sleep(1)

    // ② 上新阶段：预约价（改价面板的「预约价 → 现货价」流转依赖原值为预约价）
    let stageChip = app.buttons["listing-stage-preorder"]
    guard stageChip.waitForExistence(timeout: 5) else {
      dumpHierarchy("P1-找不到上新阶段选项", app: app)
      XCTFail("第二步应能选上新阶段")
      return
    }
    stageChip.tap()
    app.buttons["listing-next"].tap()
    sleep(1)

    // ③ 尺码池（款式之前）→ 关联款式 + 预约价 199（表单必填口径；商品名自动取款式名）
    let presetSizeChip = app.buttons["listing-size-S"]
    guard scrollToElement(presetSizeChip, app: app) else {
      dumpHierarchy("P2-找不到尺码选项", app: app)
      XCTFail("尺码池应有常用尺码 chips")
      return
    }
    presetSizeChip.tap()
    sleep(1)

    let styleChip = app.buttons["listing-style-sk-pink"]
    guard scrollToElement(styleChip, app: app) else {
      dumpHierarchy("P2-找不到款式选项", app: app)
      XCTFail("应能勾选关联款式「sk 粉色」")
      return
    }
    styleChip.tap()
    sleep(1)

    let preorderField = app.textFields["listing-preorder"]
    guard scrollToElement(preorderField, app: app) else {
      dumpHierarchy("P4-找不到预约价输入框", app: app)
      XCTFail("价格卡应有预约价输入")
      return
    }
    preorderField.tap()
    preorderField.typeText("199")
    dismissKeyboard(app)
    app.buttons["listing-next"].tap()
    sleep(1)

    // ④ 发布上架
    let publish = app.buttons["listing-publish"]
    guard publish.waitForExistence(timeout: 4) else {
      dumpHierarchy("P5-找不到发布按钮", app: app)
      XCTFail("最后一步应有「发布上架」按钮")
      return
    }
    publish.tap()
    sleep(2)

    // ⑤ 工作台「系列价格总表」：点该商品行进改价面板
    // （行是 Button，label 含商品名；工作台行不是按钮，不会误匹配）
    // 整行 label 精确匹配 + 挑可点的实例：工作台是卡片 sheet，背后系列详情页
    // 也有一张同口径价格总表，同款商品在底层页面同样有「现 sk 粉色、预约价 ¥199」
    // 一行——firstMatch 会命中被 sheet 盖住的底层行（not hittable，坐标点击
    // 也落在蒙层上），必须在同名行里挑 isHittable 的那一行。
    let priceRowMatches = app.buttons
      .matching(NSPredicate(format: "label == %@", "现 sk 粉色、预约价 ¥199"))
    guard priceRowMatches.firstMatch.waitForExistence(timeout: 6) else {
      dumpHierarchy("P6-工作台价格总表找不到商品行", app: app)
      XCTFail("系列价格总表应列出自动命名的「现 sk 粉色」（预约价 ¥199 组）")
      return
    }
    // isHittable 在卡片 sheet 里对可见元素也会误报 false，改按「frame 落在
    // 屏幕内」挑出 sheet 自己的行（底层页面的同名行都在 y>852 屏外），并
    // 用坐标点击行中心，绕开 hittable 判定。
    let screenBounds = app.frame
    var priceRow: XCUIElement?
    for i in 0..<priceRowMatches.count {
      let candidate = priceRowMatches.element(boundBy: i)
      let f = candidate.frame
      if f.minY >= screenBounds.minY, f.maxY <= screenBounds.maxY, f.width > 0 {
        priceRow = candidate
        break
      }
    }
    guard let onScreenRow = priceRow else {
      dumpHierarchy("P6b-价格总表行均不在屏内", app: app)
      XCTFail("价格总表行均不在屏内（可能只匹配到底层页面的同名行）")
      return
    }
    capture("P6-工作台价格总表")
    onScreenRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    sleep(2)

    // ⑥ 改价面板：回显预约价 199 → 清空、填现货价 399 → 保存
    let preorderEdit = app.textFields["price-edit-preorder"]
    guard preorderEdit.waitForExistence(timeout: 5) else {
      dumpHierarchy("P7-改价面板没打开", app: app)
      XCTFail("价格总表行点击应打开改价面板")
      return
    }
    XCTAssertEqual(preorderEdit.value as? String, "199", "改价面板应回显原预约价")
    capture("P7-改价面板回显")

    preorderEdit.tap()
    if let current = preorderEdit.value as? String {
      preorderEdit.typeText(String(repeating: "\u{8}", count: current.count))
    }
    usleep(300_000)

    let shopEdit = app.textFields["price-edit-shop"]
    guard shopEdit.waitForExistence(timeout: 3) else {
      XCTFail("改价面板应有现货价输入")
      return
    }
    shopEdit.tap()
    shopEdit.typeText("399")

    let save = app.buttons["price-edit-save"]
    guard save.waitForExistence(timeout: 3) else {
      XCTFail("改价面板应有保存按钮")
      return
    }
    capture("P8-改价面板填写完成")
    save.tap()
    sleep(2)

    // ⑦ 保存后总表行立即刷新为「¥399」（现货价组）
    let updatedAmount = app.staticTexts["¥399"]
    guard updatedAmount.waitForExistence(timeout: 6) else {
      dumpHierarchy("P9-保存后总表未刷新", app: app)
      XCTFail("保存后系列价格总表应显示「¥399」")
      return
    }
    capture("P9-保存后总表刷新")

    // ⑧ 关闭工作台 → 系列详情价格总表同步出现「¥399（现货价）」
    let done = app.buttons["完成"].firstMatch
    if done.exists { done.tap() }
    var closeWaits = 0
    while app.buttons["price-edit-save"].exists && closeWaits < 10 {
      usleep(500_000)
      closeWaits += 1
    }
    closeWaits = 0
    while app.buttons["listing-open-form"].exists && closeWaits < 10 {
      usleep(500_000)
      closeWaits += 1
    }
    sleep(2)

    let detailAmount = app.staticTexts
      .matching(NSPredicate(format: "label CONTAINS %@", "¥399")).firstMatch
    guard scrollToElement(detailAmount, app: app, maxSwipes: 12) else {
      dumpHierarchy("P10-系列详情价格总表未同步", app: app)
      XCTFail("系列详情价格总表应同步显示改后的价格（¥399（现货价））")
      return
    }
    XCTAssertTrue(
      detailAmount.label.contains("现货价"),
      "现货价口径应写进总表行文案（实际：\(detailAmount.label)）")
    capture("P10-系列详情价格总表同步")
  }
}
