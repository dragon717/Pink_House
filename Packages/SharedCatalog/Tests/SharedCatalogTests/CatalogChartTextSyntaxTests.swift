//
//  CatalogChartTextSyntaxTests.swift
//  SharedCatalogTests
//
//  分隔符归一化的回归锁（2026-10-01 缺陷）。
//
//  ## 被测出来的那个缺陷
//
//  用户在 Mac 尺码表里写：
//      XS=，49,85,70,33,20,26,42
//        ↑ 这个逗号是中文输入法的全角「，」
//  报错是「尺码表行「XS」有 7 个值，而列名有 8 个」。
//  用户盯着自己那行看是 8 个数，**完全无从下手** —— 真正不对的是标点，
//  但报错指向的是「值个数」。
//
//  根因：Mac 侧只在**列名**切分里认全角逗号，**行值**里按半角逗号切
//  ⇒ `，49` 被当成一个值 ⇒ 8 个静默变 7 个。
//  而 iOS 侧行值先过 `normalizedSeparators` 才切，同一段文本 iOS 过 / Mac 不过。
//
//  修法：归一化上收到 `CatalogChartTextSyntax`，两端共用；下面的用例把它钉死。
//

import XCTest
@testable import SharedCatalog

final class CatalogChartTextSyntaxTests: XCTestCase {

    // MARK: - 全角 → 半角

    func testFullWidthCommaIsNormalizedToHalfWidth() {
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators("49，85"), "49,85")
    }

    func testFullWidthColonPipeAndIdeographicSpaceAreNormalized() {
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators("尺码：S"),
                       "尺码:S")
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators("a｜b"), "a|b")
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators("S　M"), "S M")
    }

    func testMarkdownEmphasisAndBackticksAreStripped() {
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators("**S**:80"), "S:80")
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators("`S`:80"), "S:80")
    }

    func testAlreadyNormalizedTextIsUnchanged() {
        let text = "后衣长,胸围,腰围 49,85,70"
        XCTAssertEqual(CatalogChartTextSyntax.normalizedSeparators(text), text)
    }

    // MARK: - ⭐ 值切分：全角逗号必须能切（本次缺陷的直接回归）

    /// 这条就是用户那个 case。**先归一、再切**，8 段一段都不能少。
    func testFullWidthCommaStillYieldsEveryValue() throws {
        let line = CatalogChartTextSyntax.normalizedSeparators("XS=，49,85,70,33,20,26,42")
        // split 会吃掉分隔符本身，所以 parts[1] 就是「=」右边那串
        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 2, "先按「=」切成标签与值两段")

        let values = CatalogChartTextSyntax.splitValues(String(parts[1]))
        XCTAssertEqual(values.count, 8,
                       "全角逗号没被归一 ⇒ 值个数会静默少一个，报出来的却是「值个数与列名不符」")
        XCTAssertNil(values[0], "「=」后紧跟分隔符 = 第一格留空占位，应为 nil")
        XCTAssertEqual(values[1], "49")
        XCTAssertEqual(values[7], "42")
    }

    /// 如果**跳过**归一化直接切，就是这个缺陷的样子 —— 把「为什么必须先归一」钉在测试里。
    func testSplittingWithoutNormalizationLosesOneValue() {
        let raw = "，49,85,70,33,20,26,42"
        XCTAssertEqual(CatalogChartTextSyntax.splitValues(raw).count, 7,
                       "未归一时 `，49` 会被当成一个值（这正是缺陷形态，不是期望行为）")
        XCTAssertEqual(CatalogChartTextSyntax.splitValues(
            CatalogChartTextSyntax.normalizedSeparators(raw)).count, 8,
                       "归一后应恢复为 8 段")
    }

    func testSplitValuesKeepsEmptySegmentsAsNil() {
        // 「用逗号留空占位」的写法成立的前提
        XCTAssertEqual(CatalogChartTextSyntax.splitValues("49,,70"), ["49", nil, "70"])
        XCTAssertEqual(CatalogChartTextSyntax.splitValues("49, 70"), ["49", "70"])
        XCTAssertEqual(CatalogChartTextSyntax.splitValues(" "), [nil])
    }

    // MARK: - 列名切分

    func testSplitColumnsAcceptsCommaAndPipeInBothWidths() {
        XCTAssertEqual(CatalogChartTextSyntax.splitColumns("后衣长,胸围,腰围"),
                       ["后衣长", "胸围", "腰围"])
        XCTAssertEqual(CatalogChartTextSyntax.splitColumns("后衣长，胸围，腰围"),
                       ["后衣长", "胸围", "腰围"])
        XCTAssertEqual(CatalogChartTextSyntax.splitColumns("后衣长|胸围|腰围"),
                       ["后衣长", "胸围", "腰围"])
        XCTAssertEqual(CatalogChartTextSyntax.splitColumns("后衣长｜胸围｜腰围"),
                       ["后衣长", "胸围", "腰围"])
    }

    func testSplitColumnsDropsEmptySegmentsAndTrims() {
        XCTAssertEqual(CatalogChartTextSyntax.splitColumns(" 后衣长 ,, 胸围 , "),
                       ["后衣长", "胸围"])
        XCTAssertEqual(CatalogChartTextSyntax.splitColumns(""), [])
    }

    // MARK: - 数据列：行标签列必须被剔除

    func testDataColumnsDropsLeadingLabelColumn() {
        let columns = CatalogChartTextSyntax.dataColumns(
            from: "尺码, 后衣长, 胸围, 腰围, 肩宽, 袖长, 袖口, 领围")

        XCTAssertEqual(columns.count, 7, "「尺码」是行标签列，不占数据列的名额")
        XCTAssertFalse(columns.contains("尺码"),
                       "⭐ 留着它，iOS 渲染时会剔、行的值却不剔 ⇒ 整列错位（静默数据损坏）")
    }

    func testDataColumnsKeepsOrdinaryColumns() {
        XCTAssertEqual(CatalogChartTextSyntax.dataColumns(from: "胸围, 腰围, 衣长"),
                       ["胸围", "腰围", "衣长"])
        XCTAssertEqual(CatalogChartTextSyntax.dataColumns(from: "预约价, 定金, 尾款"),
                       ["预约价", "定金", "尾款"])
    }

    func testEveryLabelColumnNameIsRecognizedWhenLeading() {
        for name in CatalogChartTextSyntax.labelColumnNames {
            XCTAssertEqual(CatalogChartTextSyntax.dataColumns(from: "\(name), 数据列A, 数据列B"),
                           ["数据列A", "数据列B"],
                           "「\(name)」写在首列时应当被剔除")
        }
    }

    // MARK: - 一行 `标签 = 值1, 值2` 的解析

    func testParseRowLineSplitsLabelAndValues() throws {
        let row = try CatalogChartTextSyntax
            .parseRowLine("XS = 49, 85, 70", dataColumnCount: 3).get()

        XCTAssertEqual(row.label, "XS")
        XCTAssertEqual(row.values, ["49", "85", "70"])
    }

    /// 「缺的那格用逗号留空占位」——空段必须变成 `nil`，而不是被丢掉。
    func testParseRowLineKeepsEmptySegmentsAsNil() throws {
        let row = try CatalogChartTextSyntax
            .parseRowLine("XS = 49, , 70", dataColumnCount: 3).get()
        XCTAssertEqual(row.values, ["49", nil, "70"])
    }

    func testParseRowLineNormalizesFullWidthSeparators() throws {
        let row = try CatalogChartTextSyntax
            .parseRowLine("XS = ，49，85，70", dataColumnCount: 4).get()
        XCTAssertEqual(row.values.count, 4)
        XCTAssertNil(row.values[0])
        XCTAssertEqual(row.values.dropFirst().map { $0 }, ["49", "85", "70"])
    }

    func testParseRowLineRejectsLineWithoutSeparator() {
        let result = CatalogChartTextSyntax.parseRowLine("XS: 49, 85", dataColumnCount: 2)
        guard case .failure(.missingSeparator) = result else {
            return XCTFail("没有「=」的行必须被拒绝，实际：\(result)")
        }
    }

    func testParseRowLineRejectsEmptyLabel() {
        let result = CatalogChartTextSyntax.parseRowLine(" = 49, 85", dataColumnCount: 2)
        guard case .failure(.emptyLabel) = result else {
            return XCTFail("没有标签的行必须被拒绝，实际：\(result)")
        }
    }

    func testParseRowLineRejectsValueCountMismatch() {
        let result = CatalogChartTextSyntax.parseRowLine("XS = 49, 85, 70", dataColumnCount: 4)
        guard case .failure(.valueCountMismatch(let label, let actual, let expected)) = result else {
            return XCTFail("值个数不齐必须被拒绝（这正是防「整列错位」的那道闸），实际：\(result)")
        }
        XCTAssertEqual(label, "XS")
        XCTAssertEqual(actual, 3)
        XCTAssertEqual(expected, 4)
    }

    func testParseRowLineSkipsCountCheckWhenColumnCountUnknown() throws {
        // dataColumnCount == 0 = 还不知道列数（列名为空时）→ 不做个数校验
        let row = try CatalogChartTextSyntax.parseRowLine("XS = 49", dataColumnCount: 0).get()
        XCTAssertEqual(row.values, ["49"])
    }

    func testParseRowLinesStopsAtFirstBadLine() {
        let result = CatalogChartTextSyntax.parseRowLines("""
        XS = 49, 85, 70
        S = 50, 89
        M = 51, 93, 78
        """, dataColumnCount: 3)

        guard case .failure(.valueCountMismatch(let label, _, _)) = result else {
            return XCTFail("坏行必须让整段失败（不许静默跳过），实际：\(result)")
        }
        XCTAssertEqual(label, "S", "应停在第一处错误")
    }

    func testParseRowLinesIgnoresBlankLines() throws {
        let rows = try CatalogChartTextSyntax
            .parseRowLines("XS = 49, 85\n\n  \nS = 50, 89", dataColumnCount: 2).get()
        XCTAssertEqual(rows.map(\.label), ["XS", "S"])
    }

    // MARK: - ⭐ 用户报障原文（2026-10-01）走一遍共享规则

    /// 用户截图里的输入原样重现：
    ///   列名：尺码,后衣长,胸围,腰围,肩宽,袖长,袖口,领围
    ///   XS = ,49,85,70,33,20,26,42
    ///
    /// 修复前 Mac 侧**放行**（按含「尺码」的 8 列去比 8 个值），落库后 iOS 渲染时
    /// 剔掉「尺码」列、行的值却不剔 ⇒ **整列错位**、末值丢弃，界面还写着「识别成功」。
    /// 现在共享规则把两侧口径合到一份：剔除后是 7 列，而这一行有 8 个值 ⇒ 必须拒绝。
    func testUserReportedCaseIsRejectedBySharedRule() {
        let columns = CatalogChartTextSyntax.dataColumns(
            from: "尺码,后衣长,胸围,腰围,肩宽,袖长,袖口,领围")
        XCTAssertEqual(columns.count, 7)

        let result = CatalogChartTextSyntax.parseRowLine("XS = ,49,85,70,33,20,26,42",
                                                         dataColumnCount: columns.count)
        guard case .failure(.valueCountMismatch(let label, let actual, let expected)) = result else {
            return XCTFail("用户的写法必须被拒绝（否则会静默整列错位），实际：\(result)")
        }
        XCTAssertEqual(label, "XS")
        XCTAssertEqual(actual, 8)
        XCTAssertEqual(expected, 7)
    }

    /// 同一套数据，把「尺码」从列名里拿掉（和值一起对齐）就是正确写法 —— 标准模板正是这个形状。
    func testSameDataWithoutLabelColumnInColumnsIsAccepted() throws {
        let columns = CatalogChartTextSyntax.dataColumns(
            from: CatalogChartTemplate.SizeChart.columnsText)
        let rows = try CatalogChartTextSyntax
            .parseRowLines("XS = 49, 85, 70, 33, 20, 26, 42", dataColumnCount: columns.count).get()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].values.count, columns.count)
    }

    // MARK: - 标准模板的契约测试

    // 模板自身「还能不能过识别」的回归锁已移到 `CatalogChartTemplateTests`
    // —— 两张表（尺码表 / 价格表）的模板契约放同一处，改模板时只需要看一个文件。
    // 本文件只管**语法层**（归一化 / 切分 / 行解析）。
}
