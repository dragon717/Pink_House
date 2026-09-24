//
//  BottomDockOcclusionUITests.swift
//  ItemManagerUITests
//
//  2026-09-24「界面元素遮挡」修复的模拟器验收（两项都是用户截图标注过的页面）。
//
//  验收点：
//    A. 商品详情（截图 1）：轮播底部两个悬浮标注（颜色胶囊 / 分页胶囊）必须
//       整体落在图片区内，不得压住下方信息卡顶边与标题首行。
//       量法：截图 → 屏外按像素量「胶囊底边 / 卡片顶边 / 标题顶边」三者关系。
//       （不在用例里对这两个元素取 `.frame`：同屏「配色」行有同名 chip、
//       分页胶囊里的数字也会与尺码表撞名，多匹配会让 `.frame` 直接抛错。）
//
//    B. 系列商品页（截图 2 的真实页面 = 运营端 `ShopCatalogSeriesProductsView`，
//       路径：我 → 运营工具 → 店家 / 系列 / 商品管理 → 系列 → 某个系列）。
//       滚到最底后，最后一行必须完整落在底部悬浮 Dock **之上**。
//       判定用几何量：Dock 顶边 = 底部 dock tab 按钮的 frame.minY。
//
//  数据前提：仓库 Bundle 种子已于 2026-09-24 清空，验收时把
//  `ItemManagerTests/ShopCatalogSeedFixture.swift` 的 JSON + 合成店家 / 合成商品
//  临时注入**构建产物**的 shop-catalog.json（脚本 /tmp/inject_seed.py，不改仓库资源）。
//  合成商品「ZZ 验收商品 NN」全部挂 `series-ag-xueguo-2026`、分类「ZZ验收」——
//  固定品类序里没有这个分类 → 它稳定排在最后一个分区，最后一行可预期。
//

import XCTest

final class BottomDockOcclusionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - A. 商品详情：轮播悬浮标注不得压住信息卡

    @MainActor
    func testProductDetailCarouselOverlaysClearInfoCard() throws {
        let app = XCUIApplication()
        app.launch()
        dismissSystemPrompts(app)
        dismissDailyCheckIn(app)

        navigateToTimeHallShopList(app)

        // Alice Girl → 店家主页
        let shopRow = app.staticTexts["Alice Girl"]
        XCTAssertTrue(shopRow.waitForExistence(timeout: 12), "店家列表应有 Alice Girl（验收种子）")
        shopRow.tap()

        // 系列卡「雪国来信」→ 直达点菜页
        let seriesCard = app.staticTexts["雪国来信"].firstMatch
        XCTAssertTrue(seriesCard.waitForExistence(timeout: 12), "店家主页应有「雪国来信」系列卡")
        seriesCard.tap()
        XCTAssertTrue(app.navigationBars["雪国来信"].waitForExistence(timeout: 12), "应直达点菜页")

        // 行内商品名 → 商品详情
        let productRow = app.staticTexts["雪国来信 JSK"].firstMatch
        XCTAssertTrue(productRow.waitForExistence(timeout: 12), "点菜页应有「雪国来信 JSK」")
        productRow.tap()
        XCTAssertTrue(app.navigationBars["商品详情"].waitForExistence(timeout: 12), "应进入商品详情")

        // 画面稳定后再截图（供屏外像素测量；不在这里取 .frame，理由见文件头）
        Thread.sleep(forTimeInterval: 2)
        capture(app, "A1-商品详情-轮播标注")
        attach(text: """
        [商品详情 · 截图量几何用]
        窗口高度            = \(app.frame.height)
        轮播底部标注留白     = 36(上提量) − 16(卡片间距) + 12(视觉间隙) = 32pt
        卡片顶边(相对轮播底边) = 16 − 36 = −20pt
        → 标注底边应比卡片顶边**高 12pt**，与修复前（留白 12pt → 标注被卡片顶边半埋）同法可比
        """, name: "A-量法定量")
    }

    // MARK: - B. 系列商品页：最后一行必须完整落在 Dock 之上

    @MainActor
    func testSeriesProductsLastRowClearsBottomDock() throws {
        let app = XCUIApplication()
        // 运营工具入口（我 → 运营工具）只对创作者渲染；模拟器取不到 iCloud 身份，
        // 用工程内置的 UI 测试开关解闸门（CreatorMode.enableLaunchArgument）。
        app.launchArguments.append("-ui-test-enable-creator-mode")
        app.launch()
        dismissSystemPrompts(app)
        dismissDailyCheckIn(app)

        let dockTab = try openOpsSeriesProductsPage(app)

        // 滚到最底：固定 5 次受控拖动（列表到底会钳住，不会滚过头）
        let lastRow = app.staticTexts["ZZ 验收商品 12"].firstMatch
        scrollToBottom(app, drags: 5)
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "B1-系列商品页-滚到最底")

        let dockTop = dockTab.frame.minY
        attach(text: """
        [系列商品页 滚到底几何]
        窗口高度      = \(app.frame.height)
        Dock tab 顶边 = \(dockTop)
        最后一行 frame = \(lastRow.frame)
        """, name: "B-几何")

        XCTAssertTrue(lastRow.exists, "验收种子应含最后一个分区的末行「ZZ 验收商品 12」")

        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY, dockTop,
            "最后一行底边(\(lastRow.frame.maxY)) 落进 Dock 区(顶边 \(dockTop))，说明底部避让没生效"
        )

        // 复查：所有可见的合成商品行都不得侵入 Dock 区
        let intruders = app.staticTexts.allElementsBoundByIndex.filter { element in
            element.label.hasPrefix("ZZ 验收商品")
                && element.frame.maxY > dockTop
                && element.frame.minY < app.frame.height
        }.map { "\($0.label) maxY=\($0.frame.maxY)" }
        XCTAssertTrue(intruders.isEmpty, "以下列表行被 Dock 压住：\(intruders)")
    }

    // MARK: - 导航前置

    @MainActor
    @discardableResult
    private func navigateToTimeHallShopList(_ app: XCUIApplication) -> XCUIElement {
        let timeHallTab = app.buttons["时光馆"].firstMatch
        XCTAssertTrue(timeHallTab.waitForExistence(timeout: 12), "底部 dock 应有「时光馆」")
        timeHallTab.tap()
        XCTAssertTrue(app.navigationBars["店家上新"].waitForExistence(timeout: 12),
                      "时光馆首屏应为店家上新")
        capture(app, "00-店家上新首屏")
        return timeHallTab
    }

    /// 我 → 运营工具 → 店家 / 系列 / 商品管理 → 系列分栏 → 点第一个系列 → 系列商品页。
    /// 返回底部 dock 的「时光馆」按钮（用来量 Dock 顶边）。
    @MainActor
    private func openOpsSeriesProductsPage(_ app: XCUIApplication) throws -> XCUIElement {
        // dock 先记下来：切到「我」之后它的几何不变，仍可用作 Dock 顶边基准
        let dockTab = app.buttons["时光馆"].firstMatch
        XCTAssertTrue(dockTab.waitForExistence(timeout: 15), "底部 dock 应有「时光馆」")

        let meTab = app.buttons["我"].firstMatch
        XCTAssertTrue(meTab.waitForExistence(timeout: 10), "底部 dock 应有「我」")
        meTab.tap()

        // 运营工具入口（创作者可见）
        let opsEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "运营工具")).firstMatch
        scrollUntilVisible(app, opsEntry, maxSwipes: 4)
        XCTAssertTrue(opsEntry.isHittable, "「我」页应有「运营工具」入口（需创作者模式）")
        opsEntry.tap()

        let manageEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "商品管理")).firstMatch
        scrollUntilVisible(app, manageEntry, maxSwipes: 4)
        XCTAssertTrue(manageEntry.isHittable, "运营工具页应有「店家 / 系列 / 商品管理」入口")
        manageEntry.tap()

        XCTAssertTrue(app.navigationBars["实体管理"].waitForExistence(timeout: 12),
                      "应进入实体管理页")

        // 分栏切到「系列 N」
        let seriesSegment = app.segmentedControls.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "系列")).firstMatch
        XCTAssertTrue(seriesSegment.waitForExistence(timeout: 8), "实体管理页应有「系列」分栏")
        seriesSegment.tap()

        let seriesRow = app.staticTexts["雪国来信"].firstMatch
        scrollUntilVisible(app, seriesRow, maxSwipes: 4)
        XCTAssertTrue(seriesRow.isHittable, "系列分栏应有「雪国来信」")
        seriesRow.tap()

        XCTAssertTrue(app.navigationBars["雪国来信"].waitForExistence(timeout: 12),
                      "应进入系列商品页（导航标题 = 系列名）")
        // 系列商品页的锚：固定搜索栏 + 「选择 / ＋」工具栏
        XCTAssertTrue(app.buttons["选择"].waitForExistence(timeout: 8), "系列商品页应有「选择」")
        return dockTab
    }

    // MARK: - 工具

    @MainActor
    private func dismissSystemPrompts(_ app: XCUIApplication, timeout: TimeInterval = 8) {
        let labels = ["不允许", "Don't Allow", "好", "OK"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var tapped = false
            for label in labels where app.buttons[label].firstMatch.isHittable {
                app.buttons[label].firstMatch.tap()
                tapped = true
                break
            }
            if !tapped { break }
        }
    }

    @MainActor
    private func dismissDailyCheckIn(_ app: XCUIApplication) {
        let done = app.buttons["完成"].firstMatch
        if done.waitForExistence(timeout: 5) {
            done.tap()
        }
    }

    /// 滚动直到目标可点。
    /// ⚠️ 工程口径（UI 测试踩坑记录）：**不用** `swipeUp(velocity: .fast)`
    /// ——惯性会把惰性条目甩出层级、也会在 List 顶部误触发下拉；用受控 1/4 屏拖动，
    /// 判据只用 `isHittable`（不要再用「屏幕坐标窗口」当可见判据）。
    @MainActor
    private func scrollUntilVisible(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.44))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// 一路拖到列表最底。
    /// 这里**不用「目标可点即停」做判据**：被 dock 压住的元素 `isHittable` 照样是 true
    /// （工程已知坑），会造成提前停下、量到错误的落点。改成固定次数拖动——
    /// `List` 到底会钳住，多拖几次不会滚过头。
    @MainActor
    private func scrollToBottom(_ app: XCUIApplication, drags: Int) {
        for _ in 0..<drags {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func attach(text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
