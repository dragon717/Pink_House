//
//  ShopCatalogChartPasteExampleTests.swift
//  ItemManagerTests
//
//  「粘贴文本录入」面板里那段**示例文本**必须自己就是合法的。
//
//  ## 为什么值得为「一段提示文案」写测试
//
//  示例是用户唯一会照着抄的东西 —— 它比十条说明更能决定用户怎么写
//  （2026-10-01 的教训：Mac 价格表 placeholder 举例 4 列、紧挨着的提示却写 3 列，
//   用户照哪句填都可能失败）。
//  本文件原来的价格表示例正是坏的：列名行 4 列，第二行只给了 3 个值
//  （`蝴蝶结半裙:268,80,188`）—— 在 iOS 上恰好能混过填写率门禁，
//  但用户把同一段贴进 Mac 就会撞「值个数与列名不符」。
//
//  所以这里把「示例必须过识别」钉死：任何一端改模板/改示例，这条先红。
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogChartPasteExampleTests: XCTestCase {

    /// 面板上两个用途都要检查（尺码表 + 预约价格表各自出示例，不共用一段）。
    private let kinds: [ShopCatalogChartPasteKind] = [.priceChart, .sizeChart]

    func testEveryExampleIsItselfRecognizable() throws {
        for kind in kinds {
            let lines = kind.example
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.count >= 2 else {
                return XCTFail("\(kind.title) 的示例至少要有一行列名 + 一行数据")
            }

            let columns = CatalogManualChartText.parseColumns(lines[0])
            XCTAssertGreaterThanOrEqual(columns.count, 2,
                                        "\(kind.title)：示例列名行至少要 2 个数据列")
            XCTAssertFalse(columns.contains(where: CatalogManualChartText.isLabelColumn),
                           "\(kind.title)：示例列名里不许出现行标签列名（款式 / 尺码 / 项目…）")

            let rowLines = lines.dropFirst()
            let rows = CatalogManualChartText.parseRows(rowLines.joined(separator: "\n"))
            XCTAssertEqual(rows.count, rowLines.count,
                           "\(kind.title)：示例的每一行都该被解析成一条数据行")

            for row in rows {
                XCTAssertEqual(row.values.count, columns.count,
                               "\(kind.title)：示例行「\(row.label)」的值个数 "
                               + "(\(row.values.count)) 与列名个数 (\(columns.count)) 不符 —— "
                               + "用户照着抄必然失败")
                XCTAssertFalse(row.values.contains(nil),
                               "\(kind.title)：示例行「\(row.label)」不该留空占位")
            }

            // 最终判据：示例必须判「识别成功」。判定用的就是界面上那一份。
            XCTAssertNil(CatalogChartQuality.issue(columns: columns, rows: rows, kind: kind.chartKind),
                         "\(kind.title)：示例文本必须能过识别门禁")
        }
    }

    /// 示例的行语法必须是 **iOS 的冒号**（`款式:值1,值2`），不能把 Mac 的等号模板直接贴过来。
    /// `CatalogManualChartText.parseRows` 只按冒号切，混进等号会让整行变成「标签 = 整行」。
    func testExamplesUseColonSyntaxNotEquals() {
        for kind in kinds {
            XCTAssertFalse(kind.example.contains(" = "),
                           "\(kind.title)：iOS 粘贴示例不能出现 Mac 的「 = 」语法")
            XCTAssertTrue(kind.example.contains(":"),
                          "\(kind.title)：iOS 粘贴示例要用冒号分隔标签与值")
        }
    }

    /// 负向对照：**修复前**那段示例必须被判为不合格。
    ///
    /// 没有这条，上面那些断言有可能是「恒真」的 ——
    /// 比如解析压根没工作、行列都解析成空的，`for row in rows` 一次都不进，测试照样绿。
    /// 这里拿 2026-10-01 那份真实坏示例跑同一套口径，要求它**对不上**。
    func testOldBrokenExampleIsRejectedByTheseAssertions() {
        let old = """
        款式,预约价,定金,尾款,现货价
        大蝴蝶结背心裙:318,91,227,368
        蝴蝶结半裙:268,80,188
        """
        let lines = old.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let columns = CatalogManualChartText.parseColumns(lines[0])
        let rows = CatalogManualChartText.parseRows(
            lines.dropFirst().joined(separator: "\n"))

        XCTAssertEqual(columns.count, 4, "「款式」是行标签列，应被剔除，剩 4 个数据列")
        XCTAssertEqual(rows.count, 2, "对照组要真的解析出两行，否则这条本身是空跑")
        XCTAssertEqual(rows.last?.values.count, 3)
        XCTAssertNotEqual(rows.last?.values.count, columns.count,
                          "旧示例正是「列名 4 个、值 3 个」；它必须与列数不符，"
                          + "否则上面那些断言就是在空转")
    }

    /// 列名提示与示例的列名行要**说的是同一件事** ——
    /// 否则又回到「placeholder 与提示互相矛盾」那种局面。
    func testColumnHintAndExampleAgreeOnColumnCount() throws {
        for kind in kinds {
            let exampleColumns = CatalogManualChartText.parseColumns(
                try XCTUnwrap(kind.example.split(separator: "\n").first).trimmingCharacters(in: .whitespaces))

            // 提示里「如：A, B, C」那一段的列数（尺码表提示用的是子集，只比它不超过示例即可）
            guard let hintPart = kind.columnHint.components(separatedBy: "如：").last else {
                return XCTFail("\(kind.title)：列名提示里应给出「如：…」示例")
            }
            let hintColumns = CatalogManualChartText.parseColumns(
                hintPart.replacingOccurrences(of: "）", with: ""))
            XCTAssertGreaterThanOrEqual(hintColumns.count, 2,
                                        "\(kind.title)：提示里的示例至少要有 2 列")
            XCTAssertLessThanOrEqual(hintColumns.count, exampleColumns.count,
                                     "\(kind.title)：提示里的示例列数不该多于示例文本的列数")
        }
    }
}
