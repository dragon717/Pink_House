//
//  OpsSizeChartTemplateTests.swift
//  PinkHouseOpsTests
//
//  尺码表 / 价格表**文本录入**在 Mac 侧的**接线检查**（2026-10-01 用户报障修复）。
//
//  ## ⚠️ 先读这条：本机跑不起来
//
//  `PinkHouseOpsTests` 是 **App 宿主式**测试，本机 `xcodebuild test` 会在
//  「before establishing connection」处**永久挂起**（2026-10-01 实测 6m37s 后
//  `The test runner hung before establishing connection.`）。
//  取证见 skill `pink-house-xcodebuild-acceptance` 的 `references/mac-xctest-hang-forensics.md`。
//
//  所以：**规则本身不在这里验证**。切分 / 归一化 / 行值个数校验 / 模板格式，
//  全部住在共享包 `CatalogChartTextSyntax` + `CatalogChartTemplate`，
//  由 `Packages/SharedCatalog` 的 `swift test` 秒级覆盖（本机可跑，已验证）。
//  本文件只锁「Mac 有没有把共享规则接上、有没有接错参数」——
//  这类错误光靠共享包测不出来，而它恰恰是历史上反复出错的地方
//  （`SnapshotHarness` 里那句注释：系列价格表因**列数/值数不齐**被录入端挡住，
//   界面上只表现为「价格表：无」，从截图完全看不出是一次失败）。
//
//  ## 用户报障回顾（为什么「接线」也值得测）
//
//  报错原文：「尺码表行「XS」有 7 个值，而列名有 8 个」。
//  两个问题叠在一起：`XS=` 后是全角「，」（值个数少一个），
//  以及「尺码」被写进了列名（它是行标签列，正确位置在「=」左边）。
//  第 2 条更严重：修复前 Mac 会**放行**并落库，而 iOS 渲染时剔掉「尺码」列、
//  行的值却不剔 ⇒ **整列错位**、末值丢弃，界面上还写着「识别成功」。
//

import XCTest
@testable import PinkHouseOps

final class OpsSizeChartTemplateTests: XCTestCase {

    private func entry(columns: String, rows: String) -> OpsSeriesTypeEntry {
        OpsSeriesTypeEntry(category: "JSK",
                           designName: "星月夜",
                           chartUnit: CatalogChartTemplate.SizeChart.unit,
                           chartColumnsText: columns,
                           chartRowsText: rows)
    }

    /// 与界面完全同路：解析 → 共享判定。
    private func recognition(for entry: OpsSeriesTypeEntry) -> CatalogChartRecognition {
        let parsed = OpsSeriesSizeChartParsing.parse(entry: entry)
        return OpsChartRecognition.make(kind: .size,
                                        columns: parsed.chart?.columns ?? [],
                                        rows: parsed.chart?.rows ?? [],
                                        issue: parsed.issue)
    }

    // MARK: - ① 标准模板一次通过（模板常量来自共享包，UI 按钮读同一份）

    func testStandardTemplateIsRecognizedSuccessfully() throws {
        let target = entry(columns: CatalogChartTemplate.SizeChart.columnsText,
                           rows: CatalogChartTemplate.SizeChart.rowsText)
        let result = OpsSeriesSizeChartParsing.parse(entry: target)

        XCTAssertNil(result.issue, "标准模板不该有解析错误，实际：\(result.issue ?? "")")
        let chart = try XCTUnwrap(result.chart)

        XCTAssertEqual(chart.columns.count, 7, "模板是 7 个数据列")
        XCTAssertEqual(chart.rows.map(\.label), CatalogChartTemplate.SizeChart.sizeLabels)
        for row in chart.rows {
            XCTAssertEqual(row.values.count, 7, "「\(row.label)」的值个数应与数据列一样多")
        }
        XCTAssertTrue(recognition(for: target).isSuccess)
    }

    // MARK: - ② 全角逗号不会让值个数少一个（用户报障的直接原因）

    func testFullWidthCommaKeepsEveryValue() throws {
        let target = entry(columns: CatalogChartTemplate.SizeChart.columnsText,
                           rows: """
                           XS = ，49, 85, 70, 33, 20, 26, 42
                           S = 50, 89, 74, 34, 20.5, 27, 42
                           """)
        let result = OpsSeriesSizeChartParsing.parse(entry: target)
        XCTAssertNil(result.issue, "全角逗号必须能当分隔符：\(result.issue ?? "-")")

        let chart = try XCTUnwrap(result.chart)
        XCTAssertEqual(chart.rows[0].values.count, 7)
        XCTAssertNil(chart.rows[0].values[0], "「=」后紧跟分隔符 = 第一格留空")
        XCTAssertEqual(chart.rows[0].values[6], "42", "最后一个值不能被吞掉")
    }

    // MARK: - ③ ⭐ 列表口径与 iOS 一致：落库的列名里不许留下行标签列

    func testLeadingLabelColumnIsDroppedFromSavedColumns() throws {
        let target = entry(columns: "尺码, " + CatalogChartTemplate.SizeChart.columnsText,
                           rows: CatalogChartTemplate.SizeChart.rowsText)
        let result = OpsSeriesSizeChartParsing.parse(entry: target)

        XCTAssertNil(result.issue, "剔除行标签列后应能通过：\(result.issue ?? "-")")
        let chart = try XCTUnwrap(result.chart)
        XCTAssertEqual(chart.columns.count, 7)
        XCTAssertFalse(chart.columns.contains("尺码"),
                       "⭐ 落库列名里留着「尺码」⇒ iOS 渲染时剔它、值却不剔 ⇒ 整列错位")
    }

    // MARK: - ④ ⭐⭐ 用户那套原文必须被**拒绝**（而不是静默错位后落库）

    func testUserReportedInputIsRejectedInsteadOfSilentlyMisaligned() throws {
        let target = entry(columns: "尺码,后衣长,胸围,腰围,肩宽,袖长,袖口,领围",
                           rows: "XS = ,49,85,70,33,20,26,42")

        let issue = try XCTUnwrap(OpsSeriesSizeChartParsing.parse(entry: target).issue,
                                  "⭐ 必须拒绝：列名含行标签列 + 每行为它留空位 = 静默整列错位")
        XCTAssertTrue(issue.contains("7"), "要写清数据列是 7 个：\(issue)")
        XCTAssertTrue(issue.contains("行标签列"), "要点明「尺码」是行标签列：\(issue)")

        let verdict = recognition(for: target)
        XCTAssertFalse(verdict.isSuccess)
        XCTAssertEqual(verdict.headline, "尺码表识别失败")
    }

    // MARK: - ⑤ 真缺值仍然拦（不许为迁就用户而静默兜底）

    func testMissingValueIsStillRejected() throws {
        let target = entry(columns: CatalogChartTemplate.SizeChart.columnsText,
                           rows: "XS = 49, 85, 70, 33, 20, 26")
        let issue = try XCTUnwrap(OpsSeriesSizeChartParsing.parse(entry: target).issue)
        XCTAssertTrue(issue.contains("6"), issue)
        XCTAssertTrue(issue.contains("7"), issue)
    }

    // MARK: - ⑥ 价格表同一条口径（「款式」也要剔）

    func testPriceChartDropsLeadingLabelColumn() throws {
        let parsed = OpsChartTextParsing.parse(
            columnsText: "款式, 预约价, 定金, 尾款",
            rowsText: "大蝴蝶结背心裙 = 318, 91, 227")
        XCTAssertNil(parsed.issue, parsed.issue ?? "-")
        XCTAssertEqual(parsed.parsed?.columns, ["预约价", "定金", "尾款"])
    }

    // MARK: - ⑦ 与快照 harness 的夹具同形（避免「只修模板、夹具反而挂了」）

    func testHarnessFixtureShapeStillValid() throws {
        let target = entry(columns: "胸围, 腰围, 衣长",
                           rows: """
                           M = 92, 70, 58
                           L = 98, 76, 60
                           """)
        let result = OpsSeriesSizeChartParsing.parse(entry: target)
        XCTAssertNil(result.issue, result.issue ?? "-")
        XCTAssertEqual(result.chart?.columns, ["胸围", "腰围", "衣长"])
        XCTAssertTrue(recognition(for: target).isSuccess)
    }
}
