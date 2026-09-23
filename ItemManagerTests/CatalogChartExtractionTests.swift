//
//  CatalogChartExtractionTests.swift
//  ItemManagerTests
//
//  「价格表 / 尺码表 图片识别不可用」修复契约（2026-09-23 需求 M）。
//
//  用户报的问题（原文）：
//    在「编辑系列 → 预约价格表」上传图片后，自动解析结果完全不可用：
//      1. 只识别出第一列（款式名），后面的定金 / 尾款 / 预约价 / 现货价全部丢失；
//      2. 结果没有结构，出现 `G PROMOTTOI`（英文字母乱码）、`定金:尼款`（错别字）；
//      3. 下方输入框被自动填入这些垃圾数据，还得全部删掉重打。
//    诉求：整段「标签:值」文本能直接粘贴进来按行拆分保存；识别失败要弹窗而不是填乱码。
//
//  下面锁死四件事：
//    A. 质量门禁：任何来源的结果都要过门禁，上面三类垃圾**必须被判为不可用**；
//    B. 多模态回复解析：模型给的规整文本 → 结构化表格；
//    C. 整段粘贴：列名行 + 标签:值 / Excel 制表符 / Markdown 表格 / 全角标点都能识别；
//    D. 与保存链路同源：预览（解析结果）即落库结果。
//

import XCTest
@testable import ItemManager

final class CatalogChartExtractionTests: XCTestCase {

    private func table(_ columns: [String], _ rows: [(String, [String?])]) -> CatalogChartParser.Table {
        CatalogChartParser.Table(columns: columns,
                                 rows: rows.map { CatalogSizeRow(label: $0.0, values: $0.1) })
    }

    // MARK: - A. 质量门禁：三类用户实测垃圾必须被拦下

    func testAcceptsWellFormedPriceTable() throws {
        let outcome = try CatalogChartExtraction.accept(
            kind: .price,
            table: table(["预约价", "定金", "尾款"],
                         [("大蝴蝶结背心裙", ["318", "91", "227"]),
                          ("蝴蝶结半裙", ["268", "80", "188"])]),
            source: .multimodalAI)
        XCTAssertEqual(outcome.table.rows.count, 2)
        XCTAssertEqual(outcome.source, .multimodalAI)
    }

    func testRejectsSingleColumnTable() {
        // 症状 1 的极端形态：只剩一列
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price,
            table: table(["款式"], [("大蝴蝶结背心裙", ["318"])]),
            source: .onDeviceOCR)) { error in
            XCTAssertTrue(error.localizedDescription.contains("只识别出 1 列"),
                          "原因要说清是列数不足：\(error.localizedDescription)")
        }
    }

    func testRejectsTableWithOnlyLabelsRecognized() {
        // 症状 1 的真实形态：列名在，但每行只识别出款式名，数值全丢
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price,
            table: table(["预约价", "定金", "尾款"],
                         [("大蝴蝶结背心裙", [nil, nil, nil]),
                          ("蝴蝶结半裙", [nil, nil, nil])]),
            source: .multimodalAI)) { error in
            XCTAssertTrue(error.localizedDescription.contains("多数单元格没识别出来"),
                          "原因要指出覆盖度不足：\(error.localizedDescription)")
        }
    }

    func testRejectsGarbledLatinHeader() {
        // 症状 2 前半：`G PROMOTTOI` 型 OCR 噪声
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price,
            modelReply: """
            G PROMOTTOI,预约价,定金,尾款
            大蝴蝶结背心裙:318,91,227
            定金:尼款
            """)) { error in
            XCTAssertTrue(error.localizedDescription.contains("乱码"),
                          "原因要指出乱码：\(error.localizedDescription)")
        }
    }

    func testRejectsRowLabelDuplicatingColumnName() {
        // 症状 2 后半：`定金:尼款` 这种行列错位
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price,
            table: table(["预约价", "定金", "尾款"],
                         [("大蝴蝶结背心裙", ["318", "91", "227"]),
                          ("定金", ["尼款", nil, nil])]),
            source: .multimodalAI)) { error in
            XCTAssertTrue(error.localizedDescription.contains("行列可能错位"),
                          "原因要指出错位：\(error.localizedDescription)")
        }
    }

    func testRejectsTableWithoutAnyNumber() {
        // 只识别到文字、没有任何数值 → 对价格表 / 尺码表都没有意义
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price,
            modelReply: """
            款式,预约价,定金
            大蝴蝶结背心裙:见备注,待定
            """)) { error in
            XCTAssertTrue(error.localizedDescription.contains("任何数值"),
                          "原因要指出无数字：\(error.localizedDescription)")
        }
    }

    func testRejectsMetaRows() {
        // 「备注:价格,以店铺为准」——冒号后有分隔符，会被当数据行解析 → 必须由门禁拦下
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price,
            modelReply: """
            款式,预约价,定金
            大蝴蝶结背心裙:318,91
            备注:价格,以店铺为准
            """)) { error in
            XCTAssertTrue(error.localizedDescription.contains("说明文字"),
                          "原因要指出混入说明：\(error.localizedDescription)")
        }
        // 冒号后没有任何分隔符的说明句（「备注:价格以店铺为准」）在清洗阶段就该被丢掉
        let cleaned = CatalogChartModelReply.clean("""
        好的，结果如下：
        款式,预约价,定金
        大蝴蝶结背心裙:318,91
        备注:价格以店铺为准
        """)
        XCTAssertFalse(cleaned.contains("结果如下"), "前言应被丢弃：\(cleaned)")
        XCTAssertFalse(cleaned.contains("备注"), "无分隔符的说明句应被丢弃：\(cleaned)")
    }

    func testRejectsEmptyReplyAndEmptyTable() {
        XCTAssertThrowsError(try CatalogChartExtraction.accept(kind: .price, modelReply: ""))
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price, modelReply: "我没看清这张图片")) { error in
            XCTAssertTrue(error.localizedDescription.contains("找不到列名行")
                          || error.localizedDescription.contains("找不到数据行"),
                          "应说明没找到表格：\(error.localizedDescription)")
        }
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price, table: table(["预约价", "定金"], []), source: .onDeviceOCR))
    }

    func testGarbageTokenDetection() {
        XCTAssertTrue(CatalogChartQuality.isGarbageToken("PROMOTTOI"))
        XCTAssertTrue(CatalogChartQuality.isGarbageToken("G PROMOTTOI"))
        XCTAssertTrue(CatalogChartQuality.isGarbageToken("GXF"))
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("胸围"), "中文不是乱码")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("S"), "单字母尺码不是乱码")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("XL"), "双字母尺码不是乱码")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("Size"), "常见表头英文在白名单里")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("86-92"), "数值不是乱码")
    }

    // MARK: - B. 多模态回复 → 表格

    func testParsesPlainModelReply() throws {
        let parsed = try CatalogChartModelReply.table(from: """
        款式,预约价,定金,尾款
        大蝴蝶结背心裙:318,91,227
        蝴蝶结半裙:268,80,188
        """, kind: .price)
        XCTAssertEqual(parsed.columns, ["预约价", "定金", "尾款"], "「款式」是行标签列，列名里应剔除")
        XCTAssertEqual(parsed.rows.map(\.label), ["大蝴蝶结背心裙", "蝴蝶结半裙"])
        XCTAssertEqual(parsed.rows[0].values, ["318", "91", "227"])
    }

    func testParsesFencedAndPrefixedReply() throws {
        let parsed = try CatalogChartModelReply.table(from: """
        好的，提取结果如下：
        ```
        列名: 款式,预约价,定金
        - 大蝴蝶结背心裙:318,91
        * 蝴蝶结半裙:268,80
        ```
        """, kind: .price)
        XCTAssertEqual(parsed.columns, ["预约价", "定金"])
        XCTAssertEqual(parsed.rows.map(\.label), ["大蝴蝶结背心裙", "蝴蝶结半裙"])
    }

    func testParsesMarkdownTableReply() throws {
        let parsed = try CatalogChartModelReply.table(from: """
        | 款式 | 预约价 | 定金 |
        | --- | --- | --- |
        | 大蝴蝶结背心裙 | 318 | 91 |
        | 蝴蝶结半裙 | 268 | 80 |
        """, kind: .price)
        XCTAssertEqual(parsed.columns, ["预约价", "定金"])
        XCTAssertEqual(parsed.rows[0].values, ["318", "91"])
        XCTAssertEqual(parsed.rows[1].label, "蝴蝶结半裙")
    }

    func testParsesSizeChartReply() throws {
        let parsed = try CatalogChartModelReply.table(from: """
        尺码,前裙长,胸围,推荐胸围
        S:110,96,86-92
        M:114,102,92-98
        """, kind: .size)
        XCTAssertEqual(parsed.columns, ["前裙长", "胸围", "推荐胸围"])
        XCTAssertEqual(parsed.rows[0].values, ["110", "96", "86-92"])
    }

    func testPromptDemandsStructureAndForbidsGuessing() {
        let prompt = CatalogChartModelReply.prompt(for: .price)
        XCTAssertTrue(prompt.contains("第一行：列名"))
        XCTAssertTrue(prompt.contains("行标签:值,值"))
        XCTAssertTrue(prompt.contains("不要 Markdown"))
        XCTAssertTrue(prompt.contains("不要猜测"), "必须明确禁止编造")
        XCTAssertTrue(CatalogChartModelReply.prompt(for: .size).contains("尺码表"))
    }

    // MARK: - C. 整段粘贴（用户核心诉求：能直接复制粘贴的规整文本）

    func testPastesHeaderAndRows() {
        let parsed = CatalogManualChartText.parsePastedText("""
        款式,预约价,定金,尾款,现货价
        大蝴蝶结背心裙,318,91,227,368
        蝴蝶结半裙:268,80,188
        """)
        XCTAssertEqual(parsed.columns, ["预约价", "定金", "尾款", "现货价"])
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0].label, "大蝴蝶结背心裙")
        XCTAssertEqual(parsed.rows[0].values, ["318", "91", "227", "368"],
                       "无冒号的「款名,值,值」行也要能当作数据行")
        XCTAssertEqual(parsed.rows[1].values, ["268", "80", "188"])
        XCTAssertEqual(parsed.columnsText, "款式,预约价,定金,尾款,现货价")
        XCTAssertEqual(parsed.rowsText, """
        大蝴蝶结背心裙:318,91,227,368
        蝴蝶结半裙:268,80,188
        """)
    }

    func testPastesRowsWithoutHeader() {
        let parsed = CatalogManualChartText.parsePastedText("""
        大蝴蝶结背心裙:318,91,227
        蝴蝶结半裙:268,80,188
        """)
        XCTAssertTrue(parsed.columns.isEmpty, "没有列名行时列名为空，由用户在列名框补")
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0].values, ["318", "91", "227"])
    }

    func testPastesTabSeparatedFromSpreadsheet() {
        let parsed = CatalogManualChartText.parsePastedText(
            "尺码\t前裙长\t胸围\nS\t110\t96\nM\t114\t102")
        XCTAssertEqual(parsed.columns, ["前裙长", "胸围"], "制表符列名行必须整体归一成逗号分隔")
        XCTAssertEqual(parsed.rows.map(\.label), ["S", "M"])
        XCTAssertEqual(parsed.rows[0].values, ["110", "96"])
    }

    func testPastesMarkdownTable() {
        let parsed = CatalogManualChartText.parsePastedText("""
        | 尺码 | 胸围 | 衣长 |
        | :--- | ---: | --- |
        | S | 96 | 110 |
        | M | 102 | 114 |
        """)
        XCTAssertEqual(parsed.columns, ["胸围", "衣长"])
        XCTAssertEqual(parsed.rows.map(\.label), ["S", "M"])
        XCTAssertEqual(parsed.rows[0].values, ["96", "110"])
        XCTAssertEqual(parsed.rows[1].values, ["102", "114"])
    }

    func testPasteKeepsRaggedRowsReadable() {
        // 缺格（用户少填一列）不应把后面的值整体左移
        let parsed = CatalogManualChartText.parsePastedText("""
        款式,预约价,定金,尾款
        大蝴蝶结背心裙:318,91,
        蝴蝶结半裙:268
        """)
        XCTAssertEqual(parsed.columns.count, 3)
        XCTAssertEqual(parsed.rows[0].values, ["318", "91", nil])
        XCTAssertEqual(parsed.rows[1].values, ["268"])
    }

    func testPastesFullWidthPunctuation() {
        let parsed = CatalogManualChartText.parsePastedText("""
        款式，预约价，定金
        大蝴蝶结背心裙：318，91
        """)
        XCTAssertEqual(parsed.columns, ["预约价", "定金"])
        XCTAssertEqual(parsed.rows[0].values, ["318", "91"])
    }

    func testPasteIgnoresTitleLinesAndStrayText() {
        let parsed = CatalogManualChartText.parsePastedText("""
        2026 冬季新品价格表
        款式,预约价,定金
        大蝴蝶结背心裙:318,91
        以上价格均含税
        """)
        XCTAssertEqual(parsed.columns, ["预约价", "定金"])
        XCTAssertEqual(parsed.rows.map(\.label), ["大蝴蝶结背心裙"], "无分隔符的标题 / 尾注应被忽略")
    }

    func testPasteOfEmptyTextIsEmpty() {
        XCTAssertTrue(CatalogManualChartText.parsePastedText("   \n\n  ").isEmpty)
        XCTAssertTrue(CatalogManualChartText.parsePastedText("").isEmpty)
    }

    // MARK: - D. 预览即落库：粘贴结果与保存链路同源

    func testPasteResultSurvivesSavePathRoundTrip() {
        // 用户在粘贴面板里看到的就是落库内容：把回填文本再走一遍
        // 「保存价格表」使用的解析链路（parseColumns + parseRows + normalized），结果必须一致。
        let parsed = CatalogManualChartText.parsePastedText("""
        款式,预约价,定金,尾款
        大蝴蝶结背心裙:318,91,227
        """)
        let saved = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(parsed.columnsText),
            rows: CatalogManualChartText.parseRows(parsed.rowsText))
        XCTAssertEqual(saved.columns, parsed.columns)
        XCTAssertEqual(saved.rows, parsed.rows)
    }

    func testGarbageNeverPassesGateEvenWhenItLooksLikeATable() {
        // 汇总回归：用户截图里的那坨结果（只识别第一列 + 英文乱码 + 错别字）
        // 必须抛错 —— 只要抛错，UI 就不会往输入框写任何内容。
        let userScreenshotResult = """
        G PROMOTTOI,定金
        定金:尼款
        """
        XCTAssertThrowsError(try CatalogChartExtraction.accept(
            kind: .price, modelReply: userScreenshotResult))
    }
}
