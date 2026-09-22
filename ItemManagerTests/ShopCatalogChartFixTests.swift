//
//  ShopCatalogChartFixTests.swift
//  ItemManagerTests
//
//  尺码表 / 价格表解析修复契约（2026-09-22，用户反馈四项）：
//    A. OCR 包围盒重建行（Vision 把单元格拆成独立 observation 时不再丢数据行）
//    B. 词元尾冒号清洗（「86-92:」→「86-92」，不再产生脏值 / 多余空列）
//    C. 手动列头首列「尺码」= 行标签列 → 剔除（不再出现重复「尺码」列 + 整体错位）
//    D. 用户实测数据端到端：列头「尺码,前裙长,胸围,推荐胸围」+ 行「S:110,96,86-92:」
//       → 渲染列 = 前裙长/胸围/推荐胸围，S 行 = 110/96/86-92
//

import XCTest
@testable import ItemManager

final class ShopCatalogChartFixTests: XCTestCase {

    // MARK: A. OCR 包围盒重建行

    private func cell(_ text: String, x: CGFloat, yFromTop: CGFloat, h: CGFloat = 0.04) -> CatalogChartParser.Cell {
        // Vision 坐标系原点在左下：yFromTop 需转换为 midY = 1 - yFromTop
        CatalogChartParser.Cell(text: text,
                                box: CGRect(x: x, y: 1 - yFromTop - h / 2, width: 0.1, height: h))
    }

    func testReconstructRowsFromScatteredCells() {
        // 单元格乱序输入（Vision 输出顺序不保证）：应按行聚类、行内按 x 排序
        let cells = [
            cell("96", x: 0.4, yFromTop: 0.5),
            cell("尺码", x: 0.1, yFromTop: 0.2),
            cell("110", x: 0.3, yFromTop: 0.5),
            cell("S", x: 0.05, yFromTop: 0.5),
            cell("前裙长", x: 0.3, yFromTop: 0.2),
            cell("M", x: 0.05, yFromTop: 0.7),
            cell("114", x: 0.3, yFromTop: 0.7),
        ]
        let lines = CatalogChartParser.reconstructLineTexts(from: cells)
        XCTAssertEqual(lines, [
            "尺码\t前裙长",
            "S\t110\t96",
            "M\t114",
        ], "行自上而下、列自左而右")
    }

    func testParseTextWithTabSeparatedCells() throws {
        // 重建输出的 \t 分隔行直接进 parseText
        let table = try CatalogChartParser.parseText([
            "尺码\t前裙长\t胸围\t推荐胸围",
            "S\t110\t96\t86-92",
            "M\t114\t102\t92-98",
        ])
        XCTAssertEqual(table.columns, ["前裙长", "胸围", "推荐胸围"])
        XCTAssertEqual(table.rows[0].label, "S")
        XCTAssertEqual(table.rows[0].values, ["110", "96", "86-92"])
    }

    // MARK: B. 词元尾冒号清洗

    func testParseTextStripsTrailingColons() throws {
        let table = try CatalogChartParser.parseText([
            "尺码 前裙长 胸围 推荐胸围",
            "S 110 96 86-92:",
            "M 114 102 92-98:",
        ])
        XCTAssertEqual(table.rows[0].values, ["110", "96", "86-92"], "尾冒号应被清洗")
        XCTAssertEqual(table.rows[1].values[2], "92-98")
    }

    func testCleanTokenVariants() {
        XCTAssertEqual(CatalogManualChartText.cleanToken("86-92:"), "86-92")
        XCTAssertEqual(CatalogManualChartText.cleanToken("86-92："), "86-92")
        XCTAssertEqual(CatalogManualChartText.cleanToken("110,"), "110")
        XCTAssertEqual(CatalogManualChartText.cleanToken("110"), "110")
        XCTAssertEqual(CatalogManualChartText.cleanToken(":"), "", "纯冒号清洗后为空")
    }

    // MARK: C. 首列行标签列剔除

    func testParseColumnsDropsLeadingLabelColumn() {
        XCTAssertEqual(
            CatalogManualChartText.parseColumns("尺码,前裙长,胸围,推荐胸围"),
            ["前裙长", "胸围", "推荐胸围"],
            "首列「尺码」是行标签列，剔除后不会与角落标签列重复")
        XCTAssertEqual(
            CatalogManualChartText.parseColumns("前裙长,胸围"),
            ["前裙长", "胸围"],
            "首列不是标签列时保持原样")
        XCTAssertEqual(
            CatalogManualChartText.parseColumns("项目,预约价,定金,尾款"),
            ["预约价", "定金", "尾款"],
            "价格表同理（项目 = 行标签列）")
    }

    func testParseRowsCleansTrailingColonAndEmpty() {
        let rows = CatalogManualChartText.parseRows("S:110,96,86-92:\nM:114,102,92-98:,")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].values, ["110", "96", "86-92"], "尾冒号清洗，不再产生尾部空值")
        XCTAssertEqual(rows[1].values, ["114", "102", "92-98", nil], "行中段空值仍保留为 nil")
    }

    // MARK: D. 用户实测数据端到端（修复重复「尺码」列 + 错位）

    func testUserReportedMisalignmentFixedEndToEnd() {
        // 深度编辑页用户输入（图2）
        let columns = CatalogManualChartText.parseColumns("尺码,前裙长,胸围,推荐胸围")
        let rows = CatalogManualChartText.parseRows("S:110,96,86-92:\nM:114,102,92-98:")
        let normalized = CatalogManualChartText.normalized(columns: columns, rows: rows)
        XCTAssertEqual(normalized.columns, ["前裙长", "胸围", "推荐胸围"])
        XCTAssertEqual(normalized.rows[0].label, "S")
        XCTAssertEqual(normalized.rows[0].values, ["110", "96", "86-92"])
        XCTAssertEqual(normalized.rows[1].values, ["114", "102", "92-98"])
    }

    func testNormalizedFixesAlreadySavedBadData() {
        // 旧数据已按错误口径落库（列含「尺码」+ 值整体左移）：渲染前规范化同样能对齐
        let badColumns = ["尺码", "前裙长", "胸围", "推荐胸围"]
        let badRows = [
            CatalogSizeRow(label: "S", values: ["110", "96", "86-92:", nil]),
            CatalogSizeRow(label: "M", values: ["114", "102", "92-98:", nil]),
        ]
        let normalized = CatalogManualChartText.normalized(columns: badColumns, rows: badRows)
        XCTAssertEqual(normalized.columns, ["前裙长", "胸围", "推荐胸围"],
                       "重复的行标签列被剔除，详情页不再多出一个「尺码」列")
        XCTAssertEqual(normalized.rows[0].values, ["110", "96", "86-92", nil],
                       "值保持原序，前裙长=110 / 胸围=96 / 推荐胸围=86-92 正确对齐")
    }

    func testNormalizedKeepsWellFormedChartUntouched() {
        let columns = ["前裙长", "胸围"]
        let rows = [CatalogSizeRow(label: "S", values: ["110", "96"])]
        let normalized = CatalogManualChartText.normalized(columns: columns, rows: rows)
        XCTAssertEqual(normalized.columns, columns)
        XCTAssertEqual(normalized.rows[0].values, ["110", "96"])
    }
}
