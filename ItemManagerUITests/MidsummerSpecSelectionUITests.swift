//
//  MidsummerSpecSelectionUITests.swift
//  ItemManagerUITests
//
//  规格选择面板（仿淘宝「加入购物车」）的真实交互验收。
//
//  ⚠️ 三条与淘宝**刻意不同**的行为，正是本文件的断言重点：
//    · 面向所有使用者，不要求登录（不需要任何「先登录」前置）
//    · 不限入库数量（一直按 + 都要能加，且原样写入）
//    · 入库不校验、不扣减库存（没有「缺货」这种灰态；灰掉只表示组合不成立）
//
//  为什么必须真跑界面：`ImageRenderer` 快照只证明「版式画得出来」，
//  证明不了「抽屉能升起来、点选项能改选中、点确认真的入库」。
//
//  访问性标识契约（改产品代码时同步改本文件）：
//    · 「面板是否打开」    → 用叶子元素 spec-confirm / spec-option-* 判定。
//      ⚠️ 不要给整个面板挂容器级 identifier：实测它会覆盖直接子元素自己的 identifier
//      （确认按钮的 spec-confirm 曾因此变成容器标识，测试直接找不到它）。
//    · 某个规格选项        → spec-option-<groupID>-<optionID>   例：spec-option-color-sk-white
//    · 数量加减/数值       → spec-quantity-plus / spec-quantity-minus / spec-quantity-value
//    · 确认按钮            → spec-confirm
//    · 收起                → spec-close
//    · 规格缺省提示        → spec-empty-hint
//    · 联动灰化说明        → spec-linkage-hint-<groupID>
//
//  运行方式：
//    xcodebuild test -scheme ItemManager \
//      -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
//      -resultBundlePath /tmp/ph_spec.xcresult \
//      -only-testing:ItemManagerUITests/MidsummerSpecSelectionUITests \
//      -IDEPackageSupportDisableManifestSandbox=YES \
//      -skipPackagePluginValidation -skipMacroValidation \
//      ENABLE_USER_SCRIPT_SANDBOXING=NO \
//      OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'

import XCTest

final class MidsummerSpecSelectionUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = true
  }

  // MARK: - 启动与导航

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

  /// 打开某个商品的详情弹窗。卡片整行点击是 `onTapGesture`，
  /// 所以点标题文字让它冒泡到父视图即可（不要去找不存在的整卡 Button）。
  /// 樱花小羊例外：卡片名与页面上其他「樱花小羊」文案可能重名，
  /// 用卡片的 a11y 标签（「名称，商品页价 ¥区间」）前缀锁定。
  @MainActor
  private func openDetail(_ app: XCUIApplication, itemName: String) -> Bool {
    if itemName.hasPrefix("樱花小羊") {
      let card = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，"))
        .firstMatch
      var swipes = 0
      while !card.exists && swipes < 6 {
        app.swipeUp()
        usleep(500_000)
        swipes += 1
      }
      guard card.exists else {
        dumpHierarchy("00-找不到樱花小羊商品卡片", app: app)
        return false
      }
      card.tap()
      sleep(2)
      return true
    }

    let title = app.staticTexts[itemName]
    var attempts = 0
    while !title.exists && attempts < 12 {
      app.swipeUp()
      usleep(500_000)
      attempts += 1
    }
    guard title.exists else {
      dumpHierarchy("00-找不到商品 \(itemName)", app: app)
      return false
    }
    title.tap()
    sleep(2)
    return true
  }

  @MainActor
  private func isComfortablyVisible(_ element: XCUIElement, app: XCUIApplication) -> Bool {
    guard element.isHittable else { return false }
    let frame = element.frame
    return frame.minY >= 120 && frame.maxY <= app.frame.height - 140
  }

  // MARK: - 用例 1：有规格的单品 · 选规格 → 改数量 → 入库

  @MainActor
  func testSelectSpecsThenInsert() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }
    guard openDetail(app, itemName: "樱花小羊 SK") else { return }
    capture("10-樱花小羊-SK-详情页")

    // 详情页的「一键入库」不再直接落库，而是先开规格面板
    let quickInsert = app.buttons["midsummer-detail-quick-insert"]
    XCTAssertTrue(quickInsert.waitForExistence(timeout: 6), "详情页应当有「一键入库」")
    quickInsert.tap()
    sleep(1)
    capture("11-规格面板展开")

    // 面板起来后，颜色分类与尺码两组选项都在
    // （选项 identifier = spec-option-<组id>-<选项id>；樱花小羊主链种子数据：
    //   颜色分类组 id=style、选项「sk 粉色」（展示名已剥「现 」前缀）等，尺码组 id=size、选项「S码」等）
    let pinkOption = app.buttons["spec-option-style-sk-pink"]
    let cyanOption = app.buttons["spec-option-style-sk-light-cyan"]
    let sizeL = app.buttons["spec-option-size-l"]

    XCTAssertTrue(
      pinkOption.waitForExistence(timeout: 5),
      "规格面板应当出现「颜色分类」的选项（sk 粉色）"
    )
    XCTAssertTrue(cyanOption.exists, "规格面板应当出现「sk 蓝绿色」")
    dumpHierarchy("12-规格面板-层级", app: app)

    // 默认应当已经预选好一套组合（淘宝也是这样，不该让人先面对「请选择」）
    let confirm = app.buttons["spec-confirm"]
    XCTAssertTrue(confirm.exists, "规格面板应当有确认按钮")
    XCTAssertTrue(
      confirm.isEnabled,
      "默认预选主推组合后，确认按钮应当是可用状态（标题：\(confirm.label)）"
    )
    XCTAssertTrue(
      confirm.label.contains("sk 粉色"),
      "确认按钮标题应当带出当前已选规格，实际是：\(confirm.label)"
    )

    // 改选「sk 蓝绿色」→ 选中态跟着变（展示名已剥「现 」前缀，现货价口径不变）
    cyanOption.tap()
    sleep(1)
    capture("13-改选-现sk蓝绿色")
    XCTAssertTrue(
      confirm.label.contains("sk 蓝绿色"),
      "改选配色后确认按钮标题应当更新，实际是：\(confirm.label)"
    )

    // 选尺码 L（颜色分类 16 项是 LazyVGrid，尺码组在滚动区下方、未滚到时不渲染）。
    // 抽屉结构：header + ScrollView(≤330pt) + 确认栏。滚动区底沿紧贴确认栏上方，
    // 所以拖动锚点取确认按钮**上方 0.6 倍按钮高度处**（滚动区内），
    // 自下而上拖动让下方内容滚入视口；app.swipeUp() 的屏幕中央起点会落到
    // 抽屉后面的详情页上，拖不动抽屉。
    let confirmButton = app.buttons["spec-confirm"]
    var sizeScroll = 0
    while !(sizeL.exists && sizeL.isHittable) && sizeScroll < 12 {
      confirmButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.6))
        .press(
          forDuration: 0.05,
          thenDragTo: confirmButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -5.0))
        )
      usleep(500_000)
      sizeScroll += 1
    }
    XCTAssertTrue(sizeL.exists, "规格面板应当出现尺码选项 L（滑动抽屉后）")
    XCTAssertTrue(sizeL.isHittable, "尺码选项 L 应当滚入可视区")
    sizeL.tap()
    sleep(1)
    XCTAssertTrue(
      confirm.label.contains("L"),
      "选完尺码后确认按钮标题应当带出 L，实际是：\(confirm.label)"
    )

    // 数量：无上限，连点几次都要能加
    let plus = app.buttons["spec-quantity-plus"]
    XCTAssertTrue(plus.exists, "规格面板应当有数量加号")
    plus.tap()
    plus.tap()
    sleep(1)
    // `Text` 在 XCUITest 里是 staticText；这里也兜一下 otherElements，
    // 避免因为 SwiftUI 把它包进容器而查不到（查不到时会读出空串，断言信息里能看到）。
    let quantityStatic = app.staticTexts["spec-quantity-value"]
    let quantityOther = app.otherElements["spec-quantity-value"]
    let quantityLabel = quantityStatic.exists
      ? quantityStatic.label
      : (quantityOther.exists ? quantityOther.label : "")
    capture("14-数量改为3")
    XCTAssertTrue(
      quantityLabel.contains("3"),
      "点两次加号后数量应当为 3，实际读到的标签是：\(quantityLabel)"
    )

    // 确认入库
    confirm.tap()
    sleep(3)
    capture("15-确认后的入库反馈")

    let message = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "已加入衣橱")
    ).firstMatch
    XCTAssertTrue(message.exists, "确认后详情页应当给出「已加入衣橱」的就地反馈")

    if message.exists {
      XCTAssertTrue(
        message.label.contains("现 sk 蓝绿色") && message.label.contains("L"),
        "反馈里必须写清实际入库的规格（不能静默替使用者决定），实际是：\(message.label)"
      )
      XCTAssertTrue(
        message.label.contains("×3"),
        "反馈里必须带上数量，实际是：\(message.label)"
      )
    }

    // 面板应当已收起
    XCTAssertFalse(app.buttons["spec-confirm"].exists, "确认后规格面板应当收起")
  }

  // MARK: - 用例 4：多选配一套 · 勾选多件一次入库为同一套

  /// 用户 2026-09-16：把「sk 粉色 S 码 + 开衫 + 胸针」配成一套一次入库。
  /// 开启「多选配一套」后款式组改为勾选，确认按钮带出「N 件一套」，
  /// 确认后吐司写明套装成员；无尺码的小物入库时不带尺码（单测覆盖）。
  @MainActor
  func testMultiSelectSetInsert() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }
    guard openDetail(app, itemName: "樱花小羊") else { return }

    let quickInsert = app.buttons["midsummer-detail-quick-insert"]
    guard quickInsert.waitForExistence(timeout: 6) else {
      dumpHierarchy("40-详情-找不到一键入库", app: app)
      XCTFail("详情页应当有「一键入库」")
      return
    }
    quickInsert.tap()
    sleep(2)

    // 开启多选模式
    let multiToggle = app.buttons["spec-multi-toggle"]
    guard multiToggle.waitForExistence(timeout: 4) else {
      dumpHierarchy("41-抽屉-找不到多选入口", app: app)
      XCTFail("一键入库抽屉应提供「多选配一套」入口")
      return
    }
    multiToggle.tap()
    sleep(1)
    capture("42-多选模式开启")

    // 勾选两件：sk 粉色（首项）+ 内搭 奶白色（首行内，无需滚动）
    let pink = app.buttons["spec-option-style-sk-pink"]
    let blouse = app.buttons["spec-option-style-blouse-cream"]
    XCTAssertTrue(pink.waitForExistence(timeout: 4), "应看到款式首项「sk 粉色」")
    var blouseScrolls = 0
    while !(blouse.exists && blouse.isHittable) && blouseScrolls < 8 {
      app.swipeUp()
      usleep(500_000)
      blouseScrolls += 1
    }
    guard blouse.exists else {
      dumpHierarchy("43-抽屉-找不到内搭选项", app: app)
      XCTFail("应看到「内搭 奶白色」选项")
      return
    }
    pink.tap()
    sleep(1)
    blouse.tap()
    sleep(1)
    capture("44-已勾选两件")

    // 确认按钮带出「2 件一套」
    let confirm = app.buttons["spec-confirm"]
    XCTAssertTrue(confirm.exists, "规格面板应当有确认按钮")
    XCTAssertTrue(
      confirm.label.contains("2 件一套"),
      "勾选两件后确认按钮应带「2 件一套」，实际：\(confirm.label)")
    confirm.tap()
    sleep(3)
    capture("45-套装入库反馈")

    let message = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "已加入衣橱：2 件一套")
    ).firstMatch
    XCTAssertTrue(message.exists, "确认后应给出套装入库反馈，实际层级里无该吐司")
    if message.exists {
      XCTAssertTrue(
        message.label.contains("sk 粉色") && message.label.contains("内搭"),
        "套装反馈应列明成员，实际是：\(message.label)")
    }
    XCTAssertFalse(app.buttons["spec-confirm"].exists, "确认后规格面板应当收起")
  }

  // MARK: - 用例 2：规格缺省的单品 · 面板如实说明并可直接入库

  @MainActor
  func testItemWithoutSpecsStillInserts() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }
    // 小熊博物馆系列的单品在种子数据里没有规格组
    guard openDetail(app, itemName: "小熊博物馆 切替 OP") else { return }
    capture("20-无规格单品-详情页")

    let quickInsert = app.buttons["midsummer-detail-quick-insert"]
    XCTAssertTrue(quickInsert.waitForExistence(timeout: 6))
    quickInsert.tap()
    sleep(1)
    capture("21-无规格单品-规格面板")

    let emptyHint = app.staticTexts["spec-empty-hint"]
    XCTAssertTrue(
      emptyHint.exists || app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "该单品暂无规格可选")
      ).firstMatch.exists,
      "规格缺省时面板必须如实说明「暂无规格可选」，而不是留白或静默跳过"
    )
    XCTAssertFalse(
      app.buttons["spec-option-color-sk-pink"].exists,
      "无规格单品不该出现别的单品的规格选项"
    )

    let confirm = app.buttons["spec-confirm"]
    XCTAssertTrue(confirm.exists, "规格缺省时也应当有确认按钮")
    XCTAssertTrue(confirm.isEnabled, "规格缺省不应卡住入库（没有规格要选）")
    confirm.tap()
    sleep(3)
    capture("22-无规格单品-入库反馈")

    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "已加入衣橱：小熊博物馆 切替 OP")
      ).firstMatch.exists,
      "规格缺省的单品确认后应当直接入库"
    )
  }

  // MARK: - 用例 3：卡片上的 ⊕ 仍是「快速入库」，但吐司要写明规格

  @MainActor
  func testCardQuickInsertReportsChosenSpecs() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterMidsummer(app) else { return }

    // 卡片右侧的 ⊕ 是 label 为「一键入库」的按钮。定点到「小熊博物馆」卡片：
    // 它是单链接系列且带规格组（style+size），吐司必须带出规格；
    // 首屏的樱花小羊已合并为系列入口卡片（不带 ⊕），三丽鸥没有规格组，
    // 「找屏幕上第一个可见的 ⊕」会点错卡片。
    let insertButton = app.buttons["midsummer-card-insert-midsummer-2026-bear-museum"]
    var step = 0
    while !(insertButton.exists && insertButton.isHittable) && step < 25 {
      app.swipeUp()
      step += 1
      usleep(500_000)
    }
    capture("30-找到卡片上的快捷入库入口")
    XCTAssertTrue(
      insertButton.exists,
      "小熊博物馆卡片上应当有「一键入库」（下滚 \(step) 次仍未找到）"
    )
    guard insertButton.isHittable else {
      dumpHierarchy("31-卡片入口不可点", app: app)
      return
    }

    insertButton.tap()
    sleep(3)
    capture("32-卡片快捷入库后的吐司")

    let toast = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "已加入衣橱")
    ).firstMatch
    XCTAssertTrue(toast.exists, "卡片快捷入库后应当出现「已加入衣橱」吐司")
    if toast.exists {
      // 卡片入口走默认规格，必须把规格写出来，不能静默替使用者决定
      XCTAssertTrue(
        toast.label.contains("（") && toast.label.contains("）"),
        "卡片快捷入库的吐司应当带出实际使用的规格，实际是：\(toast.label)"
      )
    }
  }
}
