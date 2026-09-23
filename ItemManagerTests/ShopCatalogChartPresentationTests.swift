//
//  ShopCatalogChartPresentationTests.swift
//  ItemManagerTests
//
//  尺码表 / 价格表展示决策契约（2026-09-23 根因修复，用户反馈：
//  「尺码图不显示，或者错误显示为价格图」）。
//
//  根因：商品详情页两张图表卡各写各的分支——
//    · 价格表卡有原图内嵌分支（Request 14 修过「查看原价格表图片无法显示」）；
//    · 尺码表卡**没有任何图片分支**，只有 `if hasStructuredContent { 表格 }`，
//      原图只能靠「查看原尺码表 >」进全屏查看器。
//  于是带图但未解析出表格的尺码表渲染成「只剩一个链接」，页面上唯一内嵌的
//  图表图是价格表的 —— 被用户读成「尺码图不显示 / 显示成了价格图」。
//
//  本套测试锁死展示决策口径（`ShopCatalogChartPresentation`）：
//    A. 只有原图（hasStructuredContent = false）时**必须**计划出原图，不得判为「暂无数据」
//       —— 这是模型契约 `CatalogSizeChart.hasStructuredContent` 注释的原文要求。
//    B. 表格 + 原图并存时两者都要出。
//    C. 引用不可解析时给出 `.unavailable`（可操作提示），绝不静默留白。
//    D. 引用解析兼容两种合法口径：CatalogAsset id（迁移产物）与文件名 / local:（运营产）。
//    E. 两张卡共用同一函数 → 同输入必得同计划（不可能再各偏一边）。
//
//  第二批（Request D：尺码表原图默认收起）：
//    F. 默认收起——`isExpanded == false` 时不得渲染原图，且必须有唯一入口。
//    G. 无图 → 无入口；图丢失 → 警示直出、不折叠、不给展开入口。
//    H. 折叠只决定「何时给用户看」，**不改变**「卡片有没有内容」（isEmpty 不受影响）。
//

import XCTest
@testable import ItemManager

final class ShopCatalogChartPresentationTests: XCTestCase {

    private func available(_ reference: String) -> Bool { false }
    private func unavailable(_ reference: String) -> Bool { true }

    // MARK: A. 只有原图（本次事故的直接回归点）

    func testImageOnlyChartPlansImageAndIsNotEmpty() {
        let plan = ShopCatalogChartPresentation.plan(
            hasStructuredContent: false,
            reference: "seed-sakura-chart-sk.jpg",
            isImageUnavailable: available)

        XCTAssertFalse(plan.showsTable, "没有结构化内容就不该渲染表格")
        XCTAssertEqual(plan.image, .ready(reference: "seed-sakura-chart-sk.jpg"),
                       "有可解析原图 → 必须内嵌展示（模型契约：只有原图时仅展示原图）")
        XCTAssertFalse(plan.isEmpty,
                       "只有原图也算有内容，不得落进「暂无尺码表数据」——这正是本次用户报的现象")
    }

    func testTrulyEmptyChartIsEmpty() {
        let plan = ShopCatalogChartPresentation.plan(
            hasStructuredContent: false,
            reference: nil,
            isImageUnavailable: available)

        XCTAssertFalse(plan.showsTable)
        XCTAssertEqual(plan.image, .none)
        XCTAssertTrue(plan.isEmpty, "既无表格也无原图，才提示「暂无」")
    }

    // MARK: B. 表格 + 原图并存

    func testTableAndImageAreBothPlanned() {
        let plan = ShopCatalogChartPresentation.plan(
            hasStructuredContent: true,
            reference: "seed-sakura-chart-dingwei-jsk.jpg",
            isImageUnavailable: available)

        XCTAssertTrue(plan.showsTable)
        XCTAssertEqual(plan.image, .ready(reference: "seed-sakura-chart-dingwei-jsk.jpg"))
        XCTAssertFalse(plan.isEmpty)
    }

    func testTableWithoutImageStillShowsTable() {
        let plan = ShopCatalogChartPresentation.plan(
            hasStructuredContent: true,
            reference: nil,
            isImageUnavailable: available)

        XCTAssertTrue(plan.showsTable)
        XCTAssertEqual(plan.image, .none)
        XCTAssertFalse(plan.isEmpty, "有表格就不是空卡")
    }

    // MARK: C. 有引用但解析不到文件 → 可操作提示，不留白

    func testUnresolvableReferenceSurfacesAsUnavailable() {
        let plan = ShopCatalogChartPresentation.plan(
            hasStructuredContent: false,
            reference: "local:img-deleted.jpg",
            isImageUnavailable: unavailable)

        XCTAssertEqual(plan.image, .unavailable(reference: "local:img-deleted.jpg"),
                       "沙盒重置丢掉 local: 文件时要明确提示重新上传，而不是渲染空白图")
        XCTAssertFalse(plan.isEmpty,
                       "卡片此时有内容可展示（丢失原因 + 重新上传指引），不该再叠一句「暂无」")
    }

    func testUnresolvableReferenceWithTableKeepsTable() {
        let plan = ShopCatalogChartPresentation.plan(
            hasStructuredContent: true,
            reference: "local:img-deleted.jpg",
            isImageUnavailable: unavailable)

        XCTAssertTrue(plan.showsTable)
        XCTAssertEqual(plan.image, .unavailable(reference: "local:img-deleted.jpg"))
        XCTAssertFalse(plan.isEmpty)
    }

    // MARK: D. 引用解析：两种合法口径 + 边界

    func testReferenceResolvesAssetIDToOriginalURL() {
        // 迁移产物的形态：sourceImage 是 CatalogAsset id
        let assets = ["ms-asset-9178173883a7-45efeb67a7": "seed-sakura-chart-sk.jpg"]
        XCTAssertEqual(
            ShopCatalogChartReference.resolve("ms-asset-9178173883a7-45efeb67a7") { assets[$0] },
            "seed-sakura-chart-sk.jpg")
    }

    func testReferenceKeepsPlainFileNameAndLocalPrefix() {
        // 运营产物的形态：直接就是文件名 / local: 引用（assets 表里查不到）
        XCTAssertEqual(
            ShopCatalogChartReference.resolve("seed-sakura-chart-apron.jpg") { _ in nil },
            "seed-sakura-chart-apron.jpg")
        XCTAssertEqual(
            ShopCatalogChartReference.resolve("local:img-1a2b3c4d.jpg") { _ in nil },
            "local:img-1a2b3c4d.jpg")
        XCTAssertEqual(
            ShopCatalogChartReference.resolve("https://example.com/chart.jpg") { _ in nil },
            "https://example.com/chart.jpg")
    }

    func testReferenceFallsBackToRawWhenMappedURLIsBlank() {
        // 资产在表里但 originalURL 被清空 → 退回原始字符串，不能让引用凭空消失
        XCTAssertEqual(
            ShopCatalogChartReference.resolve("asset-x") { _ in "   " },
            "asset-x")
    }

    func testReferenceIsNilForBlankInput() {
        XCTAssertNil(ShopCatalogChartReference.resolve(nil) { _ in nil })
        XCTAssertNil(ShopCatalogChartReference.resolve("") { _ in nil })
        XCTAssertNil(ShopCatalogChartReference.resolve("   ") { _ in "whatever.jpg" },
                     "空白引用不该因为资产表里有同名项就变成有效引用")
        XCTAssertNil(ShopCatalogChartReference.resolve("\n\t ") { _ in nil })
    }

    // MARK: E. 两张卡同源（尺码表 / 价格表不可能再各偏一边）

    func testSizeChartAndPriceChartShareIdenticalDecision() {
        // 尺码表与价格表的差异只在「数据从哪来」，判定必须完全相同：
        // 同输入 → 同计划；任何一侧单独改分支都会被这条拦住。
        let cases: [(hasTable: Bool, ref: String?, unavailable: Bool)] = [
            (false, "seed-sakura-chart-sk.jpg", false),
            (true,  "seed-sakura-chart-sk.jpg", false),
            (false, nil, false),
            (true,  nil, false),
            (false, "local:gone.jpg", true),
            (true,  "local:gone.jpg", true),
        ]

        for c in cases {
            let check: (String) -> Bool = c.unavailable ? unavailable : available
            let asSizeChart = ShopCatalogChartPresentation.plan(
                hasStructuredContent: c.hasTable, reference: c.ref, isImageUnavailable: check)
            let asPriceChart = ShopCatalogChartPresentation.plan(
                hasStructuredContent: c.hasTable, reference: c.ref, isImageUnavailable: check)
            XCTAssertEqual(asSizeChart, asPriceChart,
                           "尺码表与价格表展示决策必须同源：\(c)")
        }
    }

    func testReferencePresenceAlwaysEntersAnImageState() {
        // 只要有引用，就必定落到 .ready 或 .unavailable —— 绝不会悄悄变成 .none
        // （.none 会让卡片对「已登记的原图」完全失声，就是本次事故的形态）
        for ref in ["seed-sakura-chart-sk.jpg", "local:img-a.jpg", "https://e.com/a.jpg"] {
            let plan = ShopCatalogChartPresentation.plan(
                hasStructuredContent: false, reference: ref, isImageUnavailable: available)
            XCTAssertNotEqual(plan.image, .none, "引用 \(ref) 不该被判为无图")
        }
    }

    // MARK: F. 尺码表原图默认收起（Request D）

    func testReadyImageIsCollapsedByDefault() {
        // 需求原文：「默认状态下尺码表图片处于收起（隐藏）状态，仅显示一个可点击的触发入口」
        let disclosure = ShopCatalogChartDisclosure.plan(
            image: .ready(reference: "seed-sakura-chart-sk.jpg"),
            isExpanded: false)

        XCTAssertEqual(disclosure.trigger, .expand, "收起态必须给出唯一入口")
        XCTAssertTrue(disclosure.showsTrigger, "入口可见，否则用户无从展开")
        XCTAssertFalse(disclosure.showsImage, "默认不得渲染原图——这正是本次要改的行为")
        XCTAssertFalse(disclosure.showsMissingHint, "图好好的，不该出现丢失警示")
    }

    func testExpandedImageRendersImageAndOffersCollapse() {
        let disclosure = ShopCatalogChartDisclosure.plan(
            image: .ready(reference: "seed-sakura-chart-sk.jpg"),
            isExpanded: true)

        XCTAssertEqual(disclosure.trigger, .collapse, "展开后入口应变成收起，状态明确")
        XCTAssertTrue(disclosure.showsImage, "展开就是要看到完整原图")
        XCTAssertFalse(disclosure.showsMissingHint)
    }

    func testTogglingDisclosureOnlySwitchesWhichSideIsShown() {
        // 收起 ⇄ 展开 是同一份内容的两态，不可能出现「又渲染图又显示入口在展开态」
        let ready = ShopCatalogChartPresentation.ImageState.ready(reference: "chart.jpg")
        let collapsed = ShopCatalogChartDisclosure.plan(image: ready, isExpanded: false)
        let expanded = ShopCatalogChartDisclosure.plan(image: ready, isExpanded: true)

        XCTAssertNotEqual(collapsed.trigger, expanded.trigger)
        XCTAssertNotEqual(collapsed.showsImage, expanded.showsImage)
        XCTAssertEqual(collapsed.showsMissingHint, expanded.showsMissingHint)
    }

    // MARK: G. 无图 / 图丢失两种情形的折叠口径

    func testNoReferenceHasNoTriggerAtAll() {
        // 没有原图 → 既没有入口也没有空框；折叠状态怎么变都一样
        for expanded in [false, true] {
            let disclosure = ShopCatalogChartDisclosure.plan(image: .none, isExpanded: expanded)
            XCTAssertEqual(disclosure.trigger, .none, "没图就不该有可点入口（expanded=\(expanded)）")
            XCTAssertFalse(disclosure.showsTrigger)
            XCTAssertFalse(disclosure.showsImage)
            XCTAssertFalse(disclosure.showsMissingHint)
        }
    }

    func testUnavailableHintIsNeverCollapsed() {
        // 文件丢失是「待办提示」而不是图片内容：折起来用户就永远不知道要重新上传。
        // 因此它必须直出，且**不提供**展开入口（没有图可展开）。
        for expanded in [false, true] {
            let disclosure = ShopCatalogChartDisclosure.plan(
                image: .unavailable(reference: "local:gone.jpg"),
                isExpanded: expanded)
            XCTAssertEqual(disclosure.trigger, .none, "丢失警示不折叠、也不给展开入口")
            XCTAssertTrue(disclosure.showsMissingHint, "警示必须直出（expanded=\(expanded)）")
            XCTAssertFalse(disclosure.showsImage)
        }
    }

    // MARK: H. 折叠只决定「何时看」，不改变「有没有内容」

    func testCollapseNeverAffectsWhetherCardHasContent() {
        // 折叠是展示时机，不是内容判定。带原图的尺码表在**收起态**也绝不能落进
        // 「暂无尺码表数据」——那会把「有图但收起」误报成「没有数据」。
        let imageOnly = ShopCatalogChartPresentation.plan(
            hasStructuredContent: false,
            reference: "seed-sakura-chart-sk.jpg",
            isImageUnavailable: available)
        let collapsed = ShopCatalogChartDisclosure.plan(image: imageOnly.image, isExpanded: false)

        XCTAssertFalse(collapsed.showsImage)
        XCTAssertTrue(collapsed.showsTrigger, "收起态靠入口表达「这里有内容」")
        XCTAssertFalse(imageOnly.isEmpty, "内容判定与折叠状态无关，只有原图也算有内容")
    }
}
