//
//  TimeHallEntryExplorationUITests.swift
//  ItemManagerUITests
//
//  真实交互验收：把「加入衣橱」「上新工作台入口」这几条链路在模拟器上走一遍并留证。
//
//  为什么需要它：`ImageRenderer` 快照只能证明版式渲染得出来，
//  证不了「点得动、点对了、点完有反应」。本轮三个问题（入口看不见 / 点了没反应 /
//  上传入口不存在）恰恰都是交互层的，所以必须真机式跑。
//
//  访问性标识约定（改产品代码时若改了这些文案，同步改本文件）：
//    · 品牌列表「进店」按钮 → label「进入品牌档案」
//    · 「⋯」更多 → label「更多操作」
//    · 一键入库（卡片/详情） → label「一键入库」
//    · 加入并编辑（详情页） → label「加入并编辑」
//    · 系列详情「上新管理」 → identifier「series-listing-workspace-button」
//      （2026-09-16 深夜起免门控：旧创作者模式引导 / 顶栏「上传上新」/ 投稿表单已删除）
//
//  运行方式：
//    xcodebuild test -scheme ItemManager \
//      -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
//      -only-testing:ItemManagerUITests/TimeHallEntryExplorationUITests \
//      -IDEPackageSupportDisableManifestSandbox=YES \
//      -skipPackagePluginValidation -skipMacroValidation \
//      ENABLE_USER_SCRIPT_SANDBOXING=NO \
//      OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'

import XCTest

final class TimeHallEntryExplorationUITests: XCTestCase {

  override func setUpWithError() throws {
    // 一个用例里的期望落空不应中断后续用例——本轮是排查+验收，要尽量收齐证据。
    continueAfterFailure = true
  }

  // MARK: - 启动与导航工具

  /// 统一入口：每次启动都重置创作者模式存档，保证用例之间互不污染。
  @MainActor
  /// `enableCreatorMode`：开关本机创作者模式（模拟运营白名单放行）。
  /// 双视角切换与上传入口只对它可见——普通用户两种都看不到。
  private func launchApp(enableCreatorMode: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-test-reset-creator-mode"]
    if enableCreatorMode {
      app.launchArguments += ["-ui-test-enable-creator-mode"]
    }
    app.launch()
    dismissSystemPrompts(app)
    return app
  }

  /// 关掉首启的系统权限弹窗。
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

  /// 「真的能点到」的判定，比 `isHittable` 更严。
  ///
  /// 踩过的坑：屏底最后一个卡片上的「一键入库」frame 是 y=855.5、高 32.7，
  /// 而窗口只有 874pt 高——`isHittable` 照样返回 true，但中心点 y≈872
  /// 已经压在底部悬浮 dock / 系统手势区上，tap 下去什么都不会发生。
  /// 本工程底部有悬浮 dock（约从 788pt 起），所以要求元素完整落在它上方。
  @MainActor
  private func isComfortablyVisible(_ element: XCUIElement, app: XCUIApplication) -> Bool {
    guard element.isHittable else { return false }
    let frame = element.frame
    return frame.minY >= 120 && frame.maxY <= app.frame.height - 140
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

  /// 品牌列表按 `TimeHallMerchant.allCases` 顺序：0 Pink House、1 Angelic Pretty、…、5 仲夏物语
  @MainActor
  private func enterBrand(_ app: XCUIApplication, index: Int) -> Bool {
    let query = app.buttons.matching(NSPredicate(format: "label == %@", "进入品牌档案"))
    guard query.count > index else {
      dumpHierarchy("00-进店按钮不足", app: app)
      return false
    }
    query.element(boundBy: index).tap()
    sleep(4)
    return true
  }

  // MARK: - 用例 1：品牌列表主页（图一范式）

  @MainActor
  func testA_BrandListHome() throws {
    let app = launchApp()
    sleep(4)
    capture("01-首屏")

    guard enterTimeHall(app) else { return }
    capture("02-品牌列表主页")

    // 图一版式的几个关键元素
    for label in ["我的品牌", "6个品牌", "全部", "有上新", "国牌", "日牌"] {
      XCTAssertTrue(
        app.staticTexts[label].exists || app.buttons[label].exists,
        "品牌列表主页应当出现「\(label)」"
      )
    }

    // 搜索
    let search = app.textFields.firstMatch
    if search.exists {
      search.tap()
      search.typeText("仲夏")
      sleep(1)
      capture("03-搜索仲夏")
      XCTAssertTrue(app.staticTexts["仲夏物语"].exists, "搜索「仲夏」应当命中仲夏物语")
      XCTAssertFalse(app.staticTexts["Pink House"].exists, "搜索「仲夏」不应命中 Pink House")
    }

    dumpHierarchy("04-品牌列表主页-层级", app: app)
  }

  // MARK: - 用例 2：仲夏物语 · 加入衣橱（本轮主修复点）

  @MainActor
  func testB_MidsummerWardrobeEntries() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterBrand(app, index: 5) else { return }
    capture("10-仲夏物语品牌页")

    // 1) 顶栏不再有「上传上新」入口（旧投稿链路已删除，上新走系列详情「上新管理」）
    XCTAssertFalse(
      app.buttons["上传上新"].exists,
      "顶栏不应再出现「上传上新」（旧投稿链路已删除）"
    )

    // 2) 商品行右侧的加号现在是真按钮，不再只是装饰图标
    let quickInsert = app.buttons.matching(NSPredicate(format: "label == %@", "一键入库"))
    capture("11-仲夏物语商品行")
    XCTAssertTrue(
      quickInsert.count > 0,
      "仲夏物语商品行上应当存在「一键入库」入口（当前 \(quickInsert.count) 个）"
    )
    dumpHierarchy("12-仲夏物语品牌页-层级", app: app)

    // 3) 点商品能打开详情弹窗（验证「外层 Button 套内层 Button」导致点不动的问题已修）。
    //    樱花小羊两条淘宝链接已合并为一张商品卡片，点卡片直接开详情。
    let sakuraCard = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，现货价"))
      .firstMatch
    var openedDetail = false
    if sakuraCard.waitForExistence(timeout: 5) {
      sakuraCard.tap()
      openedDetail = app.buttons["加入并编辑"].waitForExistence(timeout: 5)
      capture("13-仲夏物语单品详情")
      dumpHierarchy("13b-仲夏物语单品详情-层级", app: app)
    }
    XCTAssertTrue(openedDetail, "点仲夏物语商品应当打开详情，且详情里要有「加入并编辑」")

    // 4) 详情页的两种形态都在
    if openedDetail {
      XCTAssertTrue(app.buttons["一键入库"].exists, "详情里应有「一键入库」")
      XCTAssertTrue(app.buttons["加入并编辑"].exists, "详情里应有「加入并编辑」")
      capture("14-双形态按钮")
      // 关掉详情，避免影响后续断言
      if app.buttons["完成"].exists { app.buttons["完成"].tap() }
      sleep(1)
    }

    // 5) 行内直接一点即入橱，并给出可见反馈（关掉详情后停在品牌页首页）。
    //    ⚠️ 屏底悬浮 dock 压住的按钮照样报 isHittable，点下去会命中 dock
    //    （曾把 App 切到「我」tab）——必须要求目标完整落在可见安全区内再点。
    let cardQuickInsert = app.buttons.matching(NSPredicate(format: "label == %@", "一键入库"))
    if cardQuickInsert.count > 0 {
      var tapped = false
      var scrolls = 0
      let safeTop: CGFloat = 120
      let safeBottom = app.frame.height - 160
      while !tapped && scrolls < 10 {
        let candidate = cardQuickInsert.element(boundBy: 0)
        let frame = candidate.exists ? candidate.frame : .zero
        if candidate.exists && candidate.isHittable
          && frame.minY >= safeTop && frame.maxY <= safeBottom {
          candidate.tap()
          tapped = true
        } else {
          app.swipeUp()
          scrolls += 1
          usleep(500_000)
        }
      }
      if tapped {
        sleep(3)
        capture("15-点了一键入库之后")
        let toast = app.staticTexts.matching(
          NSPredicate(format: "label BEGINSWITH %@", "已加入衣橱")
        ).firstMatch
        XCTAssertTrue(toast.exists, "一键入库后应当出现「已加入衣橱」的就地反馈")
      }
    }
  }

  // MARK: - 用例 3：日牌档案页 · 商品卡片上的「一键入库」确实存在且可点

  @MainActor
  func testC_DedicatedBrandCommerceQuickInsert() throws {
    let app = launchApp()
    sleep(4)

    // Angelic Pretty 走通用 catalogue 版式（curatedBrandHall）
    guard enterTimeHall(app), enterBrand(app, index: 1) else { return }
    capture("20-AngelicPretty档案页")
    dumpHierarchy("20b-刚进档案页-层级", app: app)

    // ⚠️ 单看 `exists` 不够（LazyVGrid 会预渲染屏外单元），单看 `isHittable` 也不够
    // （屏底压着 dock 的按钮照样报 true，但点下去落在系统手势区，什么都不会发生）。
    // 所以要求目标**完整落在可见区**，这跟真实使用者「滑到看得见再点」是一致的。
    let quickInsert = app.buttons.matching(NSPredicate(format: "label == %@", "一键入库"))
    var target: XCUIElement?
    var step = 0
    while target == nil && step < 30 {
      for index in 0..<quickInsert.count {
        let candidate = quickInsert.element(boundBy: index)
        if isComfortablyVisible(candidate, app: app) {
          target = candidate
          break
        }
      }
      if target == nil {
        app.swipeUp()
        step += 1
        usleep(600_000)
      }
    }

    // 把「待点元素」的坐标也留档：这样失败时能区分
    // 「压根没点中按钮」和「点中了但页面没反应」两种完全不同的原因。
    if let target {
      let info = XCTAttachment(string: """
        下滚次数: \(step)
        同名按钮总数: \(quickInsert.count)
        待点按钮 frame: \(target.frame)
        isHittable: \(target.isHittable)
        """)
      info.name = "21a-待点按钮信息"
      info.lifetime = .keepAlways
      add(info)
    }
    capture("21-找到可点的一键入库")
    dumpHierarchy("21b-点前-层级", app: app)

    XCTAssertNotNil(
      target,
      "日牌档案页的商品卡片上应当能看到并点到「一键入库」入口（下滚 \(step) 次后仍未找到可点项）"
    )

    guard let target else {
      dumpHierarchy("22-没找到一键入库-层级", app: app)
      return
    }

    // 用归一化坐标点元素中心，避免 query 重新解析带来的帧漂移
    target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    sleep(3)
    capture("23-点了日牌卡片一键入库")
    dumpHierarchy("23b-点后-层级", app: app)

    // 三种结局要能区分开，否则「失败」会被笼统报成一句「没有已加入衣橱」
    let inserted = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "已加入衣橱")
    ).firstMatch
    let insertFailed = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "加入失败")
    ).firstMatch

    if inserted.exists {
      capture("24-入库成功反馈")
    } else if insertFailed.exists {
      XCTFail("点日牌卡片的一键入库后显示「加入失败」——写库抛错，需要看 App 日志里的 TimeHall 一键入库失败")
    } else {
      XCTFail("点日牌卡片的一键入库后既没有「已加入衣橱」也没有「加入失败」——点击很可能没落到按钮上")
    }
  }

  // MARK: - 用例 4：上新工作台入口（免门控直达 · 用户 2026-09-16 深夜改版）

  /// 旧版 testD 验的是「创作者模式 → 顶栏上传上新 → 投稿表单」，该链路已整体删除。
  /// 现在上新上传只有一条路：系列详情「上新管理」→ 上新工作台 → 4 步表单，
  /// 且对所有用户无条件开放（不再需要创作者模式 / 白名单）。
  @MainActor
  func testD_ListingWorkspaceEntryWithoutGate() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterBrand(app, index: 5) else { return }

    // 旧版页脚「开启创作者模式」引导应已删除
    XCTAssertFalse(
      app.buttons["midsummer-enable-creator-mode"].exists,
      "页脚不应再有「开启创作者模式」引导（旧投稿链路已删除）"
    )

    // 经「全部商品 → 系列列表 → 樱花小羊」进系列详情（与 ListingFlowUITests 同路）
    let allEntry = app.buttons["midsummer-entry-all-series"]
    guard allEntry.waitForExistence(timeout: 6) else {
      dumpHierarchy("30-找不到全部商品入口", app: app)
      XCTFail("品牌页应有「全部商品」入口行")
      return
    }
    allEntry.tap()
    sleep(2)

    let seriesRow = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH %@", "樱花小羊，"))
      .firstMatch
    guard seriesRow.waitForExistence(timeout: 6) else {
      dumpHierarchy("31-找不到樱花小羊系列行", app: app)
      XCTFail("系列列表应有「樱花小羊」行")
      return
    }
    seriesRow.tap()
    sleep(2)

    // 「上新管理」入口无条件出现：滚动到完整可见再点（dock 压住的按钮点了没反应）
    let entry = app.buttons["series-listing-workspace-button"]
    var tapped = false
    for _ in 0..<25 {
      if entry.exists && isComfortablyVisible(entry, app: app) {
        entry.tap()
        tapped = true
        break
      }
      app.swipeUp()
      usleep(600_000)
    }
    capture("30-系列详情的上新管理入口")
    XCTAssertTrue(tapped, "系列详情应有可见可点的「上新管理」入口（免门控）")
    guard tapped else {
      dumpHierarchy("30b-找不到上新管理入口-层级", app: app)
      return
    }
    sleep(2)

    // 工作台要真的打开：锚点用首屏必然可见的「发布新商品」发布卡按钮
    let publish = app.buttons["listing-open-form"]
    XCTAssertTrue(
      publish.waitForExistence(timeout: 6),
      "点「上新管理」应当打开上新工作台（含「发布新商品」入口）"
    )
    capture("31-上新工作台")

    guard publish.exists else {
      dumpHierarchy("31b-工作台没打开-层级", app: app)
      return
    }
    publish.tap()
    sleep(2)

    // 4 步表单第一步（新版）：锚点「取消 / 存草稿」顶栏 + 步骤条节点
    let saveDraft = app.buttons["listing-save-draft"]
    let stepOne = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-step-0"))
      .firstMatch
    XCTAssertTrue(
      saveDraft.waitForExistence(timeout: 6) || stepOne.exists,
      "点「发布新商品」应当打开新版 4 步上新表单（① 系列主图与信息）"
    )
    capture("32-新版4步表单第一步")
    dumpHierarchy("32b-表单-层级", app: app)
  }

  /// 稳妥输入：tap 后等键盘弹出再 typeText（与 MidsummerListingFlowUITests 同实现）。
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
    field.typeText(text)
  }

  // MARK: - 用例 5：品牌首页右上角「上传上新」主操作入口（用户 2026-09-17）

  @MainActor
  func testE_BrandTopRightUploadEntry() throws {
    let app = launchApp(enableCreatorMode: true)
    sleep(4)

    guard enterTimeHall(app), enterBrand(app, index: 5) else { return }

    // 双视角切换：默认用户视图，切到创作者视图后出现上传入口。
    let creatorToggle = app.buttons["创作者视图"]
    XCTAssertTrue(
      creatorToggle.waitForExistence(timeout: 6),
      "运营白名单应看到顶栏右上角的「用户 / 创作者」视角切换"
    )
    capture("40-双视角切换-默认用户视图")
    XCTAssertFalse(
      app.buttons["brand-upload-entry"].exists,
      "用户视图下不应出现上传入口"
    )
    creatorToggle.tap()
    sleep(1)
    capture("41-切换到创作者视图")

    // 顶栏右上角常驻入口：不上折叠菜单、不放二级弹窗。
    let upload = app.buttons["brand-upload-entry"]
    XCTAssertTrue(
      upload.waitForExistence(timeout: 6) && upload.isHittable,
      "品牌首页顶栏右上角应有可点的「上传上新」主操作入口"
    )
    capture("40-品牌首页右上角上传入口")

    upload.tap()
    sleep(2)

    // 直达新建系列（用户 2026-09-17）：不再弹「选择要上新的系列」，
    // 直接进新版 4 步表单第①步，并出现「创建新系列」说明条。
    XCTAssertFalse(
      app.navigationBars["选择要上新的系列"].exists,
      "不应再出现选系列弹窗——上传直达新建系列"
    )
    let newSeriesHint = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-new-series-hint"))
      .firstMatch
    let saveDraft = app.buttons["listing-save-draft"]
    let stepOne = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-step-0"))
      .firstMatch
    XCTAssertTrue(
      saveDraft.waitForExistence(timeout: 6) && (newSeriesHint.exists || stepOne.exists),
      "点「上传上新」应直达新建系列的四步表单第①步"
    )
    capture("41-直达新建系列表单第一步")

    // 填系列标题 → 下一步，确认「创建系列 → 继续上新」链路可走。
    let titleField = app.textFields["listing-launch-title"]
    XCTAssertTrue(titleField.waitForExistence(timeout: 5), "第①步应有系列标题输入框")
    focusAndType(app, "米团新建系列验收\n", into: titleField)
    capture("42-填写系列标题")
    usleep(500_000)
    app.swipeDown()
    usleep(400_000)

    let next = app.buttons["listing-next"]
    XCTAssertTrue(next.waitForExistence(timeout: 5), "底部应有「下一步」按钮")
    next.tap()
    sleep(2)
    let stepTwo = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@", "listing-step-1"))
      .firstMatch
    XCTAssertTrue(
      stepTwo.exists || app.buttons["listing-stage-teaser"].exists,
      "系列标题填完应能进入第②步（上新阶段）"
    )
    capture("43-新建系列-进入第②步")
  }

  // MARK: - 用例 6：普通用户看不到双视角切换与上传入口（用户 2026-09-17）

  @MainActor
  func testF_NormalUserSeesNoCreatorControls() throws {
    let app = launchApp()
    sleep(4)

    guard enterTimeHall(app), enterBrand(app, index: 5) else { return }

    XCTAssertFalse(
      app.buttons["用户视图"].exists || app.buttons["创作者视图"].exists,
      "普通用户不应看到创作者视图 / 用户视图的切换控件"
    )
    XCTAssertFalse(
      app.buttons["创作者视图"].exists,
      "普通用户不应看到「创作者」视角按钮"
    )
    XCTAssertFalse(
      app.buttons["brand-upload-entry"].exists,
      "普通用户不应看到上传入口"
    )
    capture("50-普通用户-无创作者控件")
  }
}
