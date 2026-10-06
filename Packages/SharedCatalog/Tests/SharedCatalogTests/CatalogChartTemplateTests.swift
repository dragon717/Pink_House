//
//  CatalogChartTemplateTests.swift
//  SharedCatalogTests
//
//  标准模板（尺码表 / 价格表）**自己还能不能过识别**的回归锁。
//
//  ## 为什么要单独锁「模板」这个东西
//
//  模板是**给人照抄的**：用户会把整段复制进输入框，然后只改数字。
//  所以模板一旦和识别规则脱节，受害的是**每一个**用户，而且看起来像用户自己写错。
//  （2026-10-01 的教训：界面上的示例文案就是隐式规范 ——
//   Mac 价格表的 placeholder 举例 4 列、下面「每一行」提示却写 3 列，
//   用户照着填必然失败；粘贴面板的示例里也有一行值个数不齐。）
//
//  这三层必须**同时**成立，缺一条模板就是坏的：
//    ① 列名只写数据列（首列不是行标签列名）；
//    ② 每行 `= ` 右边的值个数 == 数据列个数，且不留空占位；
//    ③ 整份能过 `CatalogChartQuality` 门禁（填写率 / 乱码 / 行列重名 / 说明文字混入）。
//
//  ⚠️ ③ 是最强的一条：它跑的就是界面上「识别成功 / 识别失败」用的那份判定，
//  所以只要它绿，「照抄就能过」这句话就是机器证明过的，不是文案承诺。
//

import XCTest
@testable import SharedCatalog

final class CatalogChartTemplateTests: XCTestCase {

    // MARK: - 公共契约

    /// 把「模板必须成立的三层」一次跑完。两张表的模板都走这一份，口径不会分叉。
    private func assertTemplatePassesRecognition(
        columnsText: String,
        rowsText: String,
        kind: CatalogChartKind,
        expectedLabels: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let columns = CatalogChartTextSyntax.dataColumns(from: columnsText)

        XCTAssertGreaterThanOrEqual(columns.count, 2,
                                    "识别门禁要求至少 2 个数据列", file: file, line: line)
        XCTAssertFalse(columns.contains(where: CatalogChartTextSyntax.isLabelColumn),
                       "模板列名里不许出现行标签列名（尺码 / 款式 / 项目…）",
                       file: file, line: line)
        XCTAssertFalse(CatalogChartTextSyntax.isLabelColumn(columns.first ?? ""),
                       "模板首列尤其不能是行标签列名 —— 它会被剔除，列数就和值个数对不上了",
                       file: file, line: line)

        let lines = try CatalogChartTextSyntax
            .parseRowLines(rowsText, dataColumnCount: columns.count).get()

        XCTAssertEqual(lines.map(\.label), expectedLabels,
                       "模板的行标签要与常量里声明的一致", file: file, line: line)
        for row in lines {
            XCTAssertEqual(row.values.count, columns.count,
                           "「\(row.label)」的值个数应等于数据列个数 \(columns.count)",
                           file: file, line: line)
            XCTAssertFalse(row.values.contains(nil),
                           "模板不留空占位（那是给用户真实数据的写法）",
                           file: file, line: line)
        }

        // ③ 端到端：模板 → 结构化 → 门禁。这一条绿了才算「照抄就能过」。
        let rows = lines.map { CatalogSizeRow(label: $0.label, values: $0.values) }
        XCTAssertNil(CatalogChartQuality.issue(columns: columns, rows: rows, kind: kind),
                     "模板必须能过识别门禁 —— 界面上的「识别成功」用的就是这一份判定",
                     file: file, line: line)
    }

    // MARK: - 尺码表模板

    func testSizeChartTemplateSatisfiesItsOwnContract() throws {
        try assertTemplatePassesRecognition(
            columnsText: CatalogChartTemplate.SizeChart.columnsText,
            rowsText: CatalogChartTemplate.SizeChart.rowsText,
            kind: .size,
            expectedLabels: CatalogChartTemplate.SizeChart.sizeLabels)
    }

    // MARK: - 价格表模板

    func testPriceChartTemplateSatisfiesItsOwnContract() throws {
        try assertTemplatePassesRecognition(
            columnsText: CatalogChartTemplate.PriceChart.columnsText,
            rowsText: CatalogChartTemplate.PriceChart.rowsText,
            kind: .price,
            expectedLabels: CatalogChartTemplate.PriceChart.rowLabels)
    }

    /// 价格表模板的四列必须正好是应用认识的那四个价格口径。
    ///
    /// 不再是这四列不会「报错」，但会**少录一个口径**：客户端的入橱口径
    /// （预约全款 / 定金+尾款 / 现货全款）就是从这四个价格里派生的，
    /// 少一列就有一种入橱方式在客户端根本选不到。
    func testPriceChartTemplateColumnsMatchTheFourPriceSlots() {
        XCTAssertEqual(CatalogChartTextSyntax.dataColumns(
            from: CatalogChartTemplate.PriceChart.columnsText),
                       ["预约价", "定金", "尾款", "现货价"])
    }

    /// 模板示例里的数字要满足应用自己的价格口径：**定金 + 尾款 == 预约价**。
    ///
    /// 用户多半直接改数字。若模板先给一组自相矛盾的价格，
    /// 照着填出来的数据在客户端就是算不平的。
    ///
    /// ⚠️ 这里**不是**在复刻校验规则（那条在 `OpsSeriesEntryValidator` / 各端的录入校验里），
    /// 只是断言「模板给的那组示例数字自己算得平」。
    func testPriceChartTemplateNumbersAddUp() throws {
        let columns = CatalogChartTextSyntax.dataColumns(from: CatalogChartTemplate.PriceChart.columnsText)
        let rows = try CatalogChartTextSyntax
            .parseRowLines(CatalogChartTemplate.PriceChart.rowsText,
                           dataColumnCount: columns.count).get()

        let reservation = try XCTUnwrap(columns.firstIndex(of: "预约价"))
        let deposit = try XCTUnwrap(columns.firstIndex(of: "定金"))
        let balance = try XCTUnwrap(columns.firstIndex(of: "尾款"))

        for row in rows {
            func amount(_ index: Int) -> Decimal? {
                row.values[index].flatMap { Decimal(string: $0) }
            }
            let total = try XCTUnwrap(amount(reservation), "「\(row.label)」的预约价不是数字")
            let paid = try XCTUnwrap(amount(deposit), "「\(row.label)」的定金不是数字")
            let rest = try XCTUnwrap(amount(balance), "「\(row.label)」的尾款不是数字")
            XCTAssertEqual(paid + rest, total,
                           "「\(row.label)」的定金 + 尾款应等于预约价（模板示例数字要自洽）")
        }
    }

    /// 「想加一列备注」必须同样能过 —— 列名是自由文本，加列是允许的用法，
    /// 模板要给出一个证明过的样例，否则用户会以为「只能四列」。
    func testExtendedPriceChartTemplateWithNoteColumnAlsoPasses() throws {
        try assertTemplatePassesRecognition(
            columnsText: CatalogChartTemplate.PriceChart.extendedColumnsText,
            rowsText: CatalogChartTemplate.PriceChart.extendedRowsText,
            kind: .price,
            expectedLabels: CatalogChartTemplate.PriceChart.rowLabels)

        XCTAssertEqual(CatalogChartTextSyntax.dataColumns(
            from: CatalogChartTemplate.PriceChart.extendedColumnsText).last, "备注")
    }

    /// 两张表的「单位」不是一回事：尺码表是长度，价格表是金额。
    /// （Mac 价格表卡片的 placeholder 曾写成「如 cm / inch」，就是从尺码表抄过来的。）
    func testTwoTemplatesUseDifferentUnits() {
        XCTAssertEqual(CatalogChartTemplate.SizeChart.unit, "cm")
        XCTAssertEqual(CatalogChartTemplate.PriceChart.unit, "元")
        XCTAssertNotEqual(CatalogChartTemplate.SizeChart.unit, CatalogChartTemplate.PriceChart.unit)
    }

    /// 界面上的「每一行一条：…」提示读的就是 `sampleRowText`。
    ///
    /// 提示必须与列名**对得上** —— 2026-10-01 的报障里，
    /// Mac 价格表 placeholder 举例 4 列、紧挨着的「每一行」提示却写 3 列，
    /// 两句话互相矛盾，用户照哪句填都可能失败。提示与模板同源即不可能再漂移。
    func testSampleRowTextsAgreeWithTheirColumnCounts() throws {
        let cases: [(name: String, sample: String, columnsText: String, valueCount: Int)] = [
            ("尺码表", CatalogChartTemplate.SizeChart.sampleRowText,
             CatalogChartTemplate.SizeChart.columnsText, 7),
            ("价格表", CatalogChartTemplate.PriceChart.sampleRowText,
             CatalogChartTemplate.PriceChart.columnsText, 4),
        ]

        for item in cases {
            XCTAssertFalse(item.sample.isEmpty, "\(item.name)的首行样例不能为空")
            let columns = CatalogChartTextSyntax.dataColumns(from: item.columnsText)
            let line = try CatalogChartTextSyntax
                .parseRowLine(item.sample, dataColumnCount: columns.count).get()
            XCTAssertEqual(line.values.count, columns.count,
                           "\(item.name)的提示样例值个数必须等于列名个数")
            XCTAssertEqual(line.values.count, item.valueCount)
            XCTAssertFalse(line.values.contains(nil), "提示样例不应含空占位")
        }
    }
}
