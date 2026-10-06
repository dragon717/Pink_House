//
//  CatalogSizeSelectionPolicyTests.swift
//  SharedCatalogTests
//
//  「可售尺码」自动勾选口径的回归锁（2026-10-07 用户需求）。
//
//  ## 用户原文
//
//    「实现尺码表识别上传成功后的自动勾选逻辑：当尺码表识别并上传成功后，
//      自动勾选下方对应的可售尺码选项，**同时允许用户手动取消已勾选的尺码**……
//      请明确勾选与取消的触发时机、颜色规格的显示规则。」
//
//  ## 这一份测试真正在护的是什么
//
//  用户句子的后半段（「同时允许用户手动取消」）才是难点：
//  自动勾选很容易顺手写成「每次都补齐成整张表」—— 那样用户取消掉的尺码会被
//  **反复勾回来**，而且看起来像「我的点击没生效」。所以下面每一条
//  「不该动」的用例，都与「该补」的用例同等重要。
//

import XCTest
@testable import SharedCatalog

final class CatalogSizeSelectionPolicyTests: XCTestCase {

    private let chart = ["XS", "S", "M", "L", "XL"]

    // MARK: - ① 空 → 补齐为整张表（用户要的自动勾选）

    func testEmptySelectionIsFilledWithEveryLabelInChartOrder() {
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled([], allLabels: chart), chart)
    }

    /// 顺序必须是**尺码表顺序**，不是当前选择里的顺序、也不是集合遍历序。
    /// （勾选项在界面上就按这个顺序渲染 —— 用无序集合派生顺序会觉得在随机抖动。）
    func testFillOrderFollowsTheChartNotTheInput() {
        XCTAssertEqual(CatalogSizeSelectionPolicy.normalized(["XL", "S"], allLabels: chart),
                       ["S", "XL"])
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled([], allLabels: chart), chart)
    }

    // MARK: - ② ⭐⭐ 只勾了一部分 = 用户的选择，一个字都不许动

    /// 这是本文件最重要的一条：**手动取消的尺码不许被自动勾回来**。
    func testPartialSelectionIsNeverBackfilled() {
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(["S", "M"], allLabels: chart),
                       ["S", "M"],
                       "缺 XS/L/XL 是用户取消的结果，不是需要补齐的空状态")
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(["XS"], allLabels: chart), ["XS"])
    }

    /// 幂等：同一个输入反复过它，结果不再变化 ——
    /// 所以调用方可以在任意多个动作节点上重复调，不必自己记「第几次」。
    func testAutoFillIsIdempotent() {
        let once = CatalogSizeSelectionPolicy.autoFilled([], allLabels: chart)
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(once, allLabels: chart), once)
        let partial = CatalogSizeSelectionPolicy.autoFilled(["M"], allLabels: chart)
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(partial, allLabels: chart), partial)
    }

    // MARK: - ③ 换过尺码表：旧标签全部失效 → 视为「没勾」→ 应当补齐

    func testStaleLabelsFromAPreviousChartCountAsNoSelection() {
        // 上一张表勾的是 S/M/L；新表换成了数字码
        let newChart = ["80", "85", "90"]
        XCTAssertTrue(CatalogSizeSelectionPolicy.hasNoSelection(["S", "M", "L"], allLabels: newChart))
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(["S", "M", "L"], allLabels: newChart),
                       newChart)
    }

    /// 旧标签混在里面但**仍有一个有效勾选** → 不补齐，只把它归一掉。
    func testStaleLabelsAreNormalizedAwayWithoutTriggeringAFill() {
        XCTAssertFalse(CatalogSizeSelectionPolicy.hasNoSelection(["S", "XXL"], allLabels: chart))
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(["S", "XXL"], allLabels: chart), ["S"])
    }

    // MARK: - ④ 空尺码表：不许把「空」当成「全勾」

    func testEmptyChartYieldsEmptySelection() {
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled(["S"], allLabels: []), [])
        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled([], allLabels: []), [])
        XCTAssertTrue(CatalogSizeSelectionPolicy.missing(["S"], allLabels: []).isEmpty)
    }

    // MARK: - ⑤ 缺哪些（只报事实，界面据此提示，不替用户决定）

    func testMissingReportsWhatIsNotCheckedInChartOrder() {
        XCTAssertEqual(CatalogSizeSelectionPolicy.missing(["S", "M"], allLabels: chart),
                       ["XS", "L", "XL"])
        XCTAssertTrue(CatalogSizeSelectionPolicy.missing(chart, allLabels: chart).isEmpty)
        XCTAssertEqual(CatalogSizeSelectionPolicy.missing([], allLabels: chart), chart)
    }

    // MARK: - ⑥ 「全选」是显式动作：与自动补齐刻意不同（无条件覆盖）

    func testSelectAllOverwritesEvenWhenSomethingIsAlreadyChecked() {
        XCTAssertEqual(CatalogSizeSelectionPolicy.selectAll(allLabels: chart), chart)
        // 对照：同样是「点了那个按钮」，manual 覆盖 vs auto 只补空
        XCTAssertNotEqual(CatalogSizeSelectionPolicy.autoFilled(["M"], allLabels: chart),
                          CatalogSizeSelectionPolicy.selectAll(allLabels: chart))
    }

    // MARK: - ⑦ 与真实模板/真实尺码表同形（避免只测自己造的理想输入）

    func testWorksWithTheStandardSizeChartTemplate() throws {
        let columns = CatalogChartTextSyntax.dataColumns(from: CatalogChartTemplate.SizeChart.columnsText)
        let lines = try CatalogChartTextSyntax
            .parseRowLines(CatalogChartTemplate.SizeChart.rowsText, dataColumnCount: columns.count)
            .get()
        let labels = lines.map(\.label)
        XCTAssertEqual(labels, CatalogChartTemplate.SizeChart.sizeLabels)

        XCTAssertEqual(CatalogSizeSelectionPolicy.autoFilled([], allLabels: labels), labels)
        XCTAssertEqual(CatalogSizeSelectionPolicy.missing(["S", "M"], allLabels: labels),
                       ["XS", "L", "XL"])
    }
}
