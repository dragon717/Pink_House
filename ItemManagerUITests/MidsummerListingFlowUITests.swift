//
//  MidsummerListingFlowUITests.swift
//  ItemManagerUITests
//
//  上新工作台（樱花小羊系列 · 用户 2026-09-16）全流程验收：
//    发布新商品 → ①系列主图与信息（标题 / 日期）→ ②选择上新阶段
//    → ③分类与款式（2026-09-18：分类+款式合并、商品名自动生成可改、
//      预约价 / 定金固定显示、尾款自动核算）
//    → ④确认发布（原文出处 + 提交汇总）→ 发布上架
//    → 上架商品出现在工作台列表（已上架）→ 出现在系列详情商品列表
//    → 详情页一键入库（规格抽屉带出继承的款式组）。
//
//  入口：系列详情「上新管理」对所有用户无条件开放（2026-09-16 深夜起去掉
//  canContribute 门控，旧投稿表单已删除），无需任何启动参数解闸。
//
//  访问性标识契约（改产品代码时同步改本文件）：
//    · 系列详情入口        → series-listing-workspace-button
//    · 工作台发布按钮      → listing-open-form
//    · 顶栏                → listing-cancel / listing-save-draft
//    · ①主图与信息        → listing-launch-title / listing-date-toggle
//                            listing-launch-date / listing-image-add / listing-note
//    · ②上新阶段          → listing-stage-<raw>
//    · ③分类与款式        → listing-name（自动生成可改）/ listing-kind
//                            listing-size-<size> / listing-size-custom / listing-size-add
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

  /// 「全部商品 → 系列列表 → 樱花小羊」进系列详情（上新管理入口在那里）。
  @MainActor
  private func enterSakuraSeries(_ app: XCUIApplication) -> Bool {
    let allEntry = app.buttons["midsummer-entry-all-series"]
    guard allEntry.waitForExistence(timeout: 6) else {
      dumpHierarchy("80-找不到全部商品入口", app: app)
      XCTFail("品牌页应有「全部商品」入口行")
      return false
    }
    allEntry.tap()
    sleep(2)

    let seriesRow = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，"))
      .firstMatch
    guard seriesRow.waitForExistence(timeout: 6) else {
      dumpHierarchy("81-找不到樱花小羊系列行", app: app)
      XCTFail("系列列表应有「樱花小羊」行")
      return false
    }
    seriesRow.tap()
    sleep(2)
    return true
  }

  /// 双向滚动查找（2026-09-18）：先向上滑（找下方内容），不行再向下滑
  ///（找上方内容）。
  /// 安全约束：表单是可下拉关闭的 sheet——内容滚到顶后继续 swipeDown 会把
  /// sheet 拉关。所以向下滑限制 3 次、任何时刻元素消失（sheet 被关）立即返回。
  @MainActor
  private func scrollToElement(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
    var swipes = 0
    while swipes < maxSwipes {
      guard element.exists else { return false }
      if element.isHittable { return true }
      app.swipeUp()
      usleep(400_000)
      swipes += 1
    }
    swipes = 0
    while swipes < 3 {
      guard element.exists else { return false }
      if element.isHittable { return true }
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
    // 唯一商品名：重复跑测试不会与上一轮的存档撞名。
    let itemName = "上新验收\(Int(Date().timeIntervalSince1970) % 100_000) 开衫"

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

    // ④ ③分类与款式（2026-09-18 合并）：分类 chips + 款式 + 自动商品名 + 价格同屏。
    // 操作顺序严格**自上而下**（款式 → 商品名 → 尺码 → 价格）：表单是可下拉
    // 关闭的 sheet，任何「向上回滚」的滑动都可能把 sheet 拉关，全程只向下滚。
    XCTAssertTrue(
      app.textFields["listing-preorder"].exists,
      "价格卡固定显示预约价（全款）输入"
    )
    XCTAssertTrue(
      app.buttons["listing-deposit-toggle"].exists || app.switches["listing-deposit-toggle"].exists,
      "价格卡固定显示定金配置开关"
    )

    // 款式区在分类 chips 下方：先勾选关联款式「sk 粉色」
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

    // 商品名（自动生成可改）在款式区下方
    let nameField = app.textFields["listing-name"]
    guard scrollToElement(nameField, app: app) else {
      dumpHierarchy("89-找不到名称输入框", app: app)
      XCTFail("「分类与款式」步应有自动生成的商品名输入框")
      return
    }
    nameField.tap()
    // 商品名已自动生成（如「现 sk 粉色」）：先按现有长度逐字删除，再输入新名
    //（typeText 是在光标处追加，不清空会拼成「自动名+新名」）。
    if let current = nameField.value as? String, !current.isEmpty {
      nameField.typeText(String(repeating: "\u{8}", count: current.count))
    }
    // 用换行符收起键盘（return 键），不依赖「完成」按钮的存在。
    nameField.typeText(itemName + "\n")
    usleep(500_000)

    // 尺码区在商品名下方：常用尺码 + 自定义入口同屏（归组的核心）
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
    if sizeChip.exists && styleChip.exists {
      XCTAssertLessThan(
        styleChip.frame.minY, sizeChip.frame.minY,
        "款式区应位于尺码选择区上方（2026-09-18 合并卡：分类 → 款式 → 商品名 → 尺码）")
    }

    // 价格卡在最底部：填预约价（全款）；尾款自动算，不再手填（2026-09-18 口径）。
    let preorderField = app.textFields["listing-preorder"]
    if scrollToElement(preorderField, app: app) {
      preorderField.tap()
      preorderField.typeText("199")
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

    // ⑦ 工作台列表应出现已上架行
    let listedRow = app.staticTexts[itemName]
    guard listedRow.waitForExistence(timeout: 6) else {
      dumpHierarchy("93-工作台找不到上架行", app: app)
      XCTFail("发布后工作台应列出「\(itemName)」")
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
      // 多轮测试会在存档里累计多条「上新验收… 开衫」，firstMatch 点中的
      // 可能是上一轮的商品；断言只锁定「商品名 + 继承的规格」这两个本质点。
      XCTAssertTrue(
        toast.label.contains("开衫"),
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

    // ② 定金阶段
    let depositStage = app.buttons["listing-stage-deposit"]
    guard depositStage.waitForExistence(timeout: 5) else {
      XCTFail("应能选择「定金」阶段")
      return
    }
    depositStage.tap()
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
    capture("P1-定金阶段价格配置")
    XCTAssertFalse(
      app.switches["listing-balance-toggle"].exists,
      "尾款已改为自动核算，不应再有手动开关"
    )
    XCTAssertFalse(
      app.textFields["listing-balance"].exists,
      "尾款无需手动填写，不应有尾款金额输入框"
    )

    // 选定金阶段后开关应已自动打开（onChange 默认引导）→ 定金金额框在层级里。
    // 先填定金（此时页面未滚到底部，后续收键盘手势不会拉到 sheet），
    // 再填预约价——顺序反过来会在页面最底部做收键盘滑动，把表单 sheet 拉关。
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

    // 选现货 → ③ 商品与尺码：不填名称 / 款式直接点下一步 → 应就地报错且不前进
    app.buttons["listing-stage-inStock"].tap()
    app.buttons["listing-next"].tap()
    sleep(1)
    app.buttons["listing-next"].tap()
    sleep(1)
    let stepError3 = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-step-error")).firstMatch
    XCTAssertTrue(stepError3.exists, "③ 缺商品名称 / 款式点下一步应就地报错")
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
      usleep(700_000)
      if app.keyboards.firstMatch.exists {
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
}
