//
//  ShopCatalogFormStateUITests.swift
//  ItemManagerUITests
//
//  2026-09-24「离开页面再回来，之前填的内容全部消失」的**三场景交互验收**。
//
//  用户原文要求逐一验证：
//    场景一 · 仅切后台再返回
//    场景二 · 去相册选图后返回
//    场景三 · 切换到其他应用后返回
//
//  被测页面：`运营工具 → 店家商品库 → ＋补录上新 → 手动录入` 打开的**批次详情 sheet**
//  （整批归属 + 一站式系列配置）。它的表单值全在 `@State` 里，正是会丢的那一层。
//
//  判定口径：每个场景前先「快照」当前页面上**有值**的字段，场景返回后逐字段比对；
//  只要有一个被重置回占位符，即判定失败。封面图用「视觉与简介」段里的
//  `封面（Bundle 文件名/URL，可空）` 输入框回读 —— 它就是 `configForm.cover` 本身。
//
//  ⚠️ 踩过的坑（别再犯，都花了真实运行时间）：
//   1) **点导航栏标题收不掉键盘**。键盘会一直留着把下方按钮压住 → `isHittable == false`
//      → 怎么滚都点不到。收键盘必须用**回车**（single-line `TextField` 无 `onSubmit`
//      时会失焦）；兜底才切后台再回前台。
//   2) **不要盲点「完成」**。`批次详情` sheet 的导航栏右上角就是「完成」，
//      给「尝试关掉相册」的白名单里带上它，会把 sheet 自己关掉（实测踩过）。
//   3) **点上报 frame 的几何中心不等于点得到**。`.buttonStyle(.bordered)` 的按钮在整行里
//      靠左，上报 frame 是整行 (16,743,370,59.7)，可真实可点区域只有左半边药丸
//      (32,758,141.7,29.7) —— 中心 x=201 已经出界，且 `isHittable` 照样是 `true`。
//      所以点击落在 **dx≈0.25**，不是 0.5；`isHittable` 只当门禁，不当精确命中保证。
//   4) 「可见」判据别自造屏幕坐标窗口（旧版 `maxY <= 高-140` 是整天假失败的元凶）；
//      只要求 `isHittable`，滚动用**受控小步拖动**（约 1/4 屏）。
//      往回滚也要短：长距离 `swipeDown()` 在表单顶部会触发 sheet 下拉关闭。
//   5) 输入一律 ASCII：中文输入法在 `typeText` 下会走 IME，容易「敲了没进去」。
//   6) **系列配置段出现后，`年月` 输入框会合法消失**（`seriesID` 不再为空）——
//      它不是状态丢失，断言要用「场景前快照」的写法，不要写死字段清单。
//

import XCTest

final class ShopCatalogFormStateUITests: XCTestCase {

  private let shopField = "新店家名称（必填）"
  private let seriesField = "系列名称（必填，整批同系列）"
  private let yearMonthField = "年月（选填，如 2026-10 或 2026年10月）"
  private let coverField = "封面（Bundle 文件名/URL，可空）"
  private let coverPickerLabel = "添加封面图片"

  /// ⚠️ 绝不要往里加「完成 / Done」：sheet 自己的完成按钮会中招
  private let pickerCancelLabels = ["取消", "Cancel"]
  /// 相册确认选择的文案（只在**已确认相册打开**之后用）
  private let pickerConfirmLabels = ["添加", "Add"]

  override func setUpWithError() throws {
    // 三场景要一轮全跑完：任一场景失败不阻断后面的场景
    continueAfterFailure = true
  }

  @MainActor
  func testBatchDetailFormSurvivesBackgroundPhotoPickerAndAppSwitch() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-test-enable-creator-mode"]
    app.launch()
    dismissSystemPrompts(app)
    dismissDailyCheckIn(app)
    enterBatchDetail(app)

    // ── 填写表单 ────────────────────────────────────────────────────────────
    typeInto(app, field: shopField, text: "TestShop01")
    typeInto(app, field: seriesField, text: "TestSeries01")
    typeInto(app, field: yearMonthField, text: "2026-10")
    dismissKeyboard(app)
    capture(app, "00-填写完成")
    print("STEP 填写后 快照=\(capturedFields(app))")
    XCTAssertEqual(fieldValue(app, shopField), "TestShop01", "写入后店家应可读回")
    XCTAssertEqual(fieldValue(app, seriesField), "TestSeries01", "写入后系列应可读回")
    XCTAssertEqual(fieldValue(app, yearMonthField), "2026-10", "写入后年月应可读回")

    // ── 场景一：仅切后台再返回 ──────────────────────────────────────────────
    let beforeOne = capturedFields(app)
    XCUIDevice.shared.press(.home)
    sleep(3)
    app.activate()
    XCTAssertTrue(app.navigationBars["批次详情"].waitForExistence(timeout: 12),
                  "场景一：返回后应仍在批次详情页")
    assertUnchanged(app, before: beforeOne, scene: "场景一-仅切后台再返回")

    // ── 场景二：去相册选图后返回 ────────────────────────────────────────────
    // 先让「系列配置（视觉与简介 / 价格表）」段落出现 —— 封面入口在该段内
    materializeSeriesConfig(app)
    let beforeTwo = capturedFields(app)
    print("STEP 选图前 快照=\(beforeTwo)")
    XCTAssertEqual(beforeTwo[shopField], "TestShop01", "选图前店家应还有值")
    XCTAssertEqual(beforeTwo[seriesField], "TestSeries01", "选图前系列应还有值")

    let picked = pickCoverPhoto(app)
    print("STEP 选图结果=\(picked ?? "未选中") 快照=\(capturedFields(app))")
    assertUnchanged(app, before: beforeTwo, scene: "场景二-去相册选图后返回")
    if let picked {
      XCTAssertEqual(fieldValue(app, coverField), picked,
                     "场景二：已选封面图绑定被重置了 —— 表单状态丢失")
    }

    // ── 场景三：切换到其他应用后返回 ────────────────────────────────────────
    let beforeThree = capturedFields(app)
    XCUIDevice.shared.press(.home)
    sleep(2)
    let other = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    other.activate()
    XCTAssertTrue(other.wait(for: .runningForeground, timeout: 20),
                  "场景三：应能切到「设置」App")
    sleep(2)
    app.activate()
    XCTAssertTrue(app.navigationBars["批次详情"].waitForExistence(timeout: 15),
                  "场景三：返回后应仍在批次详情页")
    assertUnchanged(app, before: beforeThree, scene: "场景三-切换到其他应用后返回")
  }

  // MARK: - 断言

  /// 快照：当前页面上「有值」的输入框 → 值。
  /// `TextField` 空着时 `value` 就是占位符本身，据此区分「填了」与「被重置成空」。
  /// 页面上本来就不存在的字段（例如系列落地后合法的隐藏）不会被收进快照。
  @MainActor
  private func capturedFields(_ app: XCUIApplication) -> [String: String] {
    var result: [String: String] = [:]
    for field in [shopField, seriesField, yearMonthField, coverField] {
      let element = app.textFields[field]
      guard element.exists, let raw = element.value as? String,
            raw != field, !raw.isEmpty else { continue }
      result[field] = raw
    }
    return result
  }

  /// 场景返回后：场景前有值的字段，一个都不能变（丢了 / 被改成别的都算失败）
  @MainActor
  private func assertUnchanged(_ app: XCUIApplication,
                               before: [String: String],
                               scene: String) {
    capture(app, scene)
    let after = capturedFields(app)
    print("\(scene) 场景前=\(before) 场景后=\(after)")
    XCTAssertFalse(before.isEmpty, "\(scene)：场景前就没有任何可断言的值，用例本身有问题")
    for (field, expected) in before {
      XCTAssertEqual(after[field], expected, "\(scene)：`\(field)` 被重置了 —— 表单状态丢失")
    }
  }

  /// 读单个输入框的值；不存在返回 nil，空框返回 ""
  @MainActor
  private func fieldValue(_ app: XCUIApplication, _ placeholder: String) -> String? {
    let element = app.textFields[placeholder]
    guard element.exists else { return nil }
    let raw = element.value as? String
    return raw == placeholder ? "" : raw
  }

  // MARK: - 导航

  @MainActor
  private func enterBatchDetail(_ app: XCUIApplication) {
    let meTab = app.buttons["我"]
    XCTAssertTrue(meTab.waitForExistence(timeout: 15), "底部 dock 应有「我」tab")
    meTab.tap()

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

  /// 让「系列配置」段落出现 —— 归属文本只写进批次与草稿，系列实体要按
  /// 「创建 / 确认系列并开始配置」才落地，配置段只认已落地的系列。
  @MainActor
  private func materializeSeriesConfig(_ app: XCUIApplication) {
    tapScrollable(app, app.buttons["应用到整批 1 条单品"], what: "应用到整批")
    sleep(2)
    tapScrollable(app, app.buttons["创建 / 确认系列并开始配置"], what: "创建/确认系列")
    sleep(3)
    XCTAssertTrue(app.buttons[coverPickerLabel].waitForExistence(timeout: 10),
                  "归属落地后应出现系列配置段（含「\(coverPickerLabel)」）")
  }

  // MARK: - 录入

  @MainActor
  private func typeInto(_ app: XCUIApplication, field: String, text: String) {
    let element = app.textFields[field]
    XCTAssertTrue(element.waitForExistence(timeout: 10), "找不到输入框：\(field)")
    tapScrollable(app, element, what: field)
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4),
                  "输入框拿不到焦点：\(field)")
    element.typeText(text)
    XCTAssertEqual(fieldValue(app, field), text, "写入后立即回读应一致：\(field)")
  }

  /// 收键盘。
  /// ⚠️ 点导航栏标题**收不掉** SwiftUI 键盘（探针实测），必须用回车；
  /// 回车也无效时才退回「切后台再回前台」（系统必然让第一响应者 resign）。
  @MainActor
  private func dismissKeyboard(_ app: XCUIApplication) {
    guard app.keyboards.firstMatch.exists else { return }
    app.typeText("\n")
    if waitKeyboardGone(app, timeout: 4) { return }
    print("KEYBOARD 回车没收掉，改用切后台兜底")
    XCUIDevice.shared.press(.home)
    sleep(1)
    app.activate()
    _ = waitKeyboardGone(app, timeout: 8)
  }

  @MainActor
  @discardableResult
  private func waitKeyboardGone(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !app.keyboards.firstMatch.exists { return true }
      usleep(200_000)
    }
    return !app.keyboards.firstMatch.exists
  }

  // MARK: - 相册

  /// 场景二本体：进系统相册选一张封面图后返回。
  /// 相册是独立进程的远程视图，但它**在 `app` 层级里可见**（探针实测 `app.buttons["取消"]`
  /// 立刻就能查到），所以不需要额外 `XCUIApplication(bundleIdentifier:)`。
  /// 选不到照片不算失败（只打日志），但「相册到底开没开」必须如实记录。
  @MainActor
  @discardableResult
  private func pickCoverPhoto(_ app: XCUIApplication) -> String? {
    tapScrollable(app, app.buttons[coverPickerLabel], what: coverPickerLabel)

    var opened = false
    for _ in 0..<20 {
      if pickerIsOpen(app) { opened = true; break }
      usleep(1_000_000)
    }
    capture(app, opened ? "场景二-相册已打开" : "场景二-相册没打开")
    print("SCENE2 相册打开=\(opened)")
    if !opened {
      // 相册没开起来时**不敢**乱点：sheet 自己也有「完成」，盲点会把它关掉
      XCTFail("场景二无法真实触发：点「\(coverPickerLabel)」后系统相册未出现")
      return nil
    }

    let pickedCell = tapFirstPhotoCell(app)
    if pickedCell {
      // 多选相册：选完要点「添加」确认（没选图时它是禁用的）
      for label in pickerConfirmLabels {
        let button = app.buttons[label]
        if button.exists, button.isEnabled, button.isHittable { button.tap(); break }
      }
      sleep(3)
    } else {
      for label in pickerCancelLabels {
        let button = app.buttons[label]
        if button.exists, button.isHittable { button.tap(); break }
      }
    }
    waitPickerGone(app)

    let value = fieldValue(app, coverField)
    let resolved = (value?.isEmpty ?? true) ? nil : value
    print("SCENE2 点中照片=\(pickedCell) 封面绑定=\(resolved ?? "空")")
    return resolved
  }

  /// 相册是否已打开：取消按钮出现即可（`批次详情` 的完成按钮在它后面，不参与判断）
  @MainActor
  private func pickerIsOpen(_ app: XCUIApplication) -> Bool {
    pickerCancelLabels.contains { app.buttons[$0].exists }
  }

  @MainActor
  private func waitPickerGone(_ app: XCUIApplication, timeout: TimeInterval = 25) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !pickerIsOpen(app) { break }
      usleep(300_000)
    }
    // 相册确认后要等沙盒落盘 + 回填绑定
    _ = app.textFields[coverField].waitForExistence(timeout: 10)
    sleep(2)
    XCTAssertTrue(app.navigationBars["批次详情"].waitForExistence(timeout: 10),
                  "相册返回后应仍在批次详情 sheet")
  }

  /// 相册里的照片格子。
  /// PHPicker 是远程视图，格子在各 iOS 版本上可能落在 `cells` 或 `images` 里，
  /// 元素类型不稳定 —— 所以最后一级兜底用**坐标**：相册顶栏（取消 / 添加）之下就是网格，
  /// 点左侧靠上那一格必然是照片。App 自己的 `Cell` 是整行长方形，先按「方形」筛掉。
  @MainActor
  private func tapFirstPhotoCell(_ app: XCUIApplication) -> Bool {
    for collection in [app.cells, app.images] {
      for element in collection.allElementsBoundByIndex {
        let frame = element.frame
        let square = abs(frame.width - frame.height) < 20
        if square, frame.width > 60, frame.width < 400, frame.minY > 150, element.isHittable {
          element.tap()
          return true
        }
      }
    }
    // 兜底：网格第一格大致落在窗口 (0.18, 0.32) 附近
    let fallback = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.32))
    fallback.tap()
    // 确认按钮变可用才算真选中
    sleep(1)
    return pickerConfirmLabels.contains { app.buttons[$0].exists && app.buttons[$0].isEnabled }
  }

  // MARK: - 滚动 / 点击工具

  /// 滚到元素可点再点它。
  /// 点击落在 **dx 0.25 / dy 0.4**：靠左的按钮（`.buttonStyle(.bordered)` + `PhotosPicker`）
  /// 上报的是整行 frame，几何中心已在药丸之外 —— 点中心等于点空。dy 偏上是为了避开
  /// 底部悬浮 dock（≈ y 788–852）和系统手势区。
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
        drag(app, from: 0.36, to: 0.50)   // 目标躲到导航栏底下 → 短距离往回滚
      } else {
        drag(app, from: 0.70, to: 0.44)   // 默认向上滚
      }
    }
    XCTFail("滚了 14 次仍点不到：\(what)")
  }

  @MainActor
  private func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
    start.press(forDuration: 0.05, thenDragTo: end)
    usleep(400_000)
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
