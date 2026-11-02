//
//  CatalogChartRecognitionTests.swift
//  SharedCatalogTests
//
//  尺码表 / 预约价格表「识别成功 / 识别失败」判定与文案（2026-10-01 需求）。
//
//  ## 这份测试要防的是什么
//
//  1. **文案丢主语**：运营常常同时录两张表，只回「识别成功」等于没说 ——
//     两张表各自的 headline 必须自带图表名，且**不能互相串**。
//  2. **该失败却报成功**：门禁（列数 / 填写率 / 数字 / 乱码 / 行列错位 / 说明文字）
//     任一命中都必须落成 `isSuccess == false`，并给出**具体**原因，不许兜成一句
//     「识别失败」了事。
//  3. **失败却不给下一步**：失败必须有 `guidance`，且明确承诺「不会写入任何内容」。
//  4. **迁移把判定改坏了**：本文件是判定从 iOS 迁进共享包之后的**行为回归锁**
//     （`isGarbageToken` 的六条口径逐条钉死）。
//

import XCTest

@testable import SharedCatalog

final class CatalogChartRecognitionTests: XCTestCase {

    // MARK: 夹具

    private func rows(_ pairs: [(String, [String?])]) -> [CatalogSizeRow] {
        pairs.map { CatalogSizeRow(label: $0.0, values: $0.1) }
    }

    private let sizeColumns = ["后裙长（含肩带可调节）", "后上身长", "腰围"]
    private let sizeRows = [
        ("XS", ["81-83", "37-39", "78"]),
        ("S", ["83-85", "38-40", "82"]),
        ("M", ["85-87", "39-41", "86"]),
    ]

    private let priceColumns = ["预约价", "定金", "尾款"]
    private let priceRows = [
        ("三丽鸥家族合作款 美乐蒂斗篷", ["299", "59", "240"]),
        ("三丽鸥家族合作款 美乐蒂背带", ["439", "87", "352"]),
    ]

    func testEditingUnitsDefaultOnlyWhenMissingOrBlank() {
        for unit in [nil, "", " \n\t"] as [String?] {
            XCTAssertEqual(CatalogChartKind.size.unitForEditing(unit), "CM")
            XCTAssertEqual(CatalogChartKind.price.unitForEditing(unit), "元")
        }
        for unit in ["cm", "inch", "¥", "日元"] {
            XCTAssertEqual(CatalogChartKind.size.unitForEditing(unit), unit)
            XCTAssertEqual(CatalogChartKind.price.unitForEditing(unit), unit)
        }
    }

    // MARK: 成功：两种表各自的文案

    func testSizeChartSuccessHeadlineNamesTheSizeChart() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .pastedText, columns: sizeColumns, rows: rows(sizeRows))

        XCTAssertTrue(recognition.isSuccess)
        XCTAssertEqual(recognition.headline, "尺码表识别成功")
        XCTAssertFalse(recognition.headline.contains("预约价格表"),
                       "尺码表的结论里不许出现价格表的字样")
    }

    func testPriceChartSuccessHeadlineNamesThePriceChart() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .price, source: .multimodalAI, columns: priceColumns, rows: rows(priceRows))

        XCTAssertTrue(recognition.isSuccess)
        XCTAssertEqual(recognition.headline, "预约价格表识别成功")
        XCTAssertFalse(recognition.headline.hasPrefix("尺码表"),
                       "价格表的结论不许被当成尺码表")
    }

    func testSuccessDetailCarriesSourceRowColumnAndFillRate() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .onDeviceOCR, columns: sizeColumns, rows: rows(sizeRows))

        XCTAssertTrue(recognition.detail.contains("本机文字识别"), recognition.detail)
        XCTAssertTrue(recognition.detail.contains("3 行"), recognition.detail)
        XCTAssertTrue(recognition.detail.contains("3 列"), recognition.detail)
        XCTAssertTrue(recognition.detail.contains("9/9 格有内容"), recognition.detail)
    }

    func testBNTAccessoryIsAcceptedByEveryRecognitionSource() {
        for label in ["BNT", "bnt", "Bnt", " BNT "] {
            XCTAssertFalse(CatalogChartQuality.isGarbageToken(label), label)
            let accessoryRows = rows([(label, ["99", "20", "79"])])
            for source in CatalogChartRecognition.Source.allCases {
                let recognition = CatalogChartRecognition.verdict(
                    kind: .price, source: source,
                    columns: priceColumns, rows: accessoryRows)

                XCTAssertTrue(recognition.isSuccess, "\(source) / \(label): \(recognition.detail)")
                XCTAssertEqual(recognition.recognizedRows, accessoryRows)
            }
        }
    }

    func testSuccessHasNoGuidanceAndExposesRecognizedContent() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .price, source: .pastedText, columns: priceColumns, rows: rows(priceRows))

        XCTAssertNil(recognition.guidance, "成功不需要引导话术")
        XCTAssertTrue(recognition.hasRecognizedContent)
        XCTAssertEqual(recognition.recognizedColumns, priceColumns)
        XCTAssertEqual(recognition.recognizedRows, rows(priceRows))
    }

    // MARK: 失败：每一种门禁都要落成「失败」并给出具体原因

    func testFailureHeadlineNamesTheChartAndKeepsTheReason() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .pastedText, columns: ["胸围"], rows: rows([("S", ["80"])]))

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertEqual(recognition.headline, "尺码表识别失败")
        XCTAssertEqual(recognition.detail, "只识别出 1 列（至少需要 2 列）")
    }

    func testEmptyContentIsAFailureNotAnIdleState() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .price, source: .pastedText, columns: [], rows: [])

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertTrue(recognition.detail.contains("没有可识别的表格内容"), recognition.detail)
    }

    func testHeaderWithoutDataRowsFails() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .pastedText, columns: sizeColumns, rows: [])

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertEqual(recognition.detail, "没有识别到任何数据行")
    }

    func testLowFillRatioFailsAsMostCellsMissing() {
        // 3 列 × 3 行 = 9 格，只有 2 格有值 → 0.22 < 0.4
        let sparse = rows([
            ("XS", ["81-83", "37-39", nil]),
            ("S", [nil, nil, nil]),
            ("M", [nil, nil, nil]),
        ])
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .multimodalAI, columns: sizeColumns, rows: sparse)

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertTrue(recognition.detail.contains("多数单元格没识别出来"), recognition.detail)
        XCTAssertTrue(recognition.detail.contains("2/9"), recognition.detail)
    }

    func testNoNumericValueFails() {
        let textOnly = rows([
            ("XS", ["长", "宽", "细"]),
            ("S", ["长", "宽", "细"]),
            ("M", ["长", "宽", "细"]),
        ])
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .pastedText, columns: sizeColumns, rows: textOnly)

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertEqual(recognition.detail, "没有识别到任何数值")
    }

    func testGarbageLabelsFailButNormalLatinHeadersDoNot() {
        let garbageRows = rows([
            ("XS", ["81-83", "37-39", "78"]),
            ("PROMOTTOI", ["83-85", "38-40", "82"]),
        ])
        let garbage = CatalogChartRecognition.verdict(
            kind: .size, source: .onDeviceOCR, columns: sizeColumns, rows: garbageRows)
        XCTAssertFalse(garbage.isSuccess)
        XCTAssertTrue(garbage.detail.contains("疑似乱码"), garbage.detail)

        let latinRows = rows([
            ("XS", ["81-83", "37-39", "78"]),
            ("S", ["83-85", "38-40", "82"]),
        ])
        let latinColumns = ["Length", "Bust", "Waist"]
        let latin = CatalogChartRecognition.verdict(
            kind: .size, source: .onDeviceOCR, columns: latinColumns, rows: latinRows)
        XCTAssertTrue(latin.isSuccess, "Size / Bust 这类正常英文表头不许被误杀：\(latin.detail)")
    }

    func testRowLabelMatchingColumnNameFailsAsMisalignment() {
        // 「定金:尼款」型错位的暴露点
        let misaligned = rows([
            ("预约价", ["299", "59", "240"]),
            ("定金", ["439", "87", "352"]),
        ])
        let recognition = CatalogChartRecognition.verdict(
            kind: .price, source: .multimodalAI, columns: priceColumns, rows: misaligned)

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertTrue(recognition.detail.contains("行列可能错位"), recognition.detail)
    }

    func testMetaTextFailsAndNamesTheChart() {
        let withNote = rows([
            ("三丽鸥家族合作款 美乐蒂斗篷", ["299", "59", "240"]),
            ("备注", ["价格以店铺为准", "—", "—"]),
        ])
        let recognition = CatalogChartRecognition.verdict(
            kind: .price, source: .multimodalAI, columns: priceColumns, rows: withNote)

        XCTAssertFalse(recognition.isSuccess)
        XCTAssertTrue(recognition.detail.contains("说明文字"), recognition.detail)
        XCTAssertTrue(recognition.detail.contains("预约价格表"), recognition.detail)
    }

    // MARK: 失败必须给下一步，并且分通道给

    func testPasteFailureGuidancePointsAtThePastedTextAndPromisesNoWipe() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .pastedText, columns: ["胸围"], rows: rows([("S", ["80"])]))

        let guidance = recognition.guidance ?? ""
        XCTAssertFalse(guidance.isEmpty, "失败必须给下一步")
        XCTAssertTrue(guidance.contains("不会解析") || guidance.contains("没有解析成完整的"),
                      guidance)
        XCTAssertTrue(guidance.contains("不会被清空"), "必须承诺不覆盖用户已填内容：\(guidance)")
    }

    func testImageChannelFailureGuidancePromisesNoWriteAndSuggestsAnotherScreenshot() {
        let recognition = CatalogChartRecognition.rejected(
            kind: .price, source: .multimodalAI, reason: "AI 识别不可用：网络超时")

        let guidance = recognition.guidance ?? ""
        XCTAssertEqual(recognition.headline, "预约价格表识别失败")
        XCTAssertTrue(recognition.detail.contains("网络超时"), recognition.detail)
        XCTAssertTrue(guidance.contains("不会写入任何内容"), guidance)
        XCTAssertTrue(guidance.contains("截图"), "图像通道应引导重传截图：\(guidance)")
        XCTAssertTrue(guidance.contains("预约价格表"), guidance)
    }

    func testRejectedWithoutSourceStillGivesGuidance() {
        let recognition = CatalogChartRecognition.rejected(kind: .size, source: nil, reason: "  ")
        XCTAssertFalse(recognition.isSuccess)
        XCTAssertEqual(recognition.detail, "未能提取出可用的表格内容", "空原因要兜底成一句人话")
        XCTAssertNotNil(recognition.guidance)
    }

    // MARK: idle

    func testIdleIsNotSuccessAndCarriesNoContent() {
        let recognition = CatalogChartRecognition.idle(kind: .price)
        XCTAssertFalse(recognition.isSuccess)
        XCTAssertNil(recognition.source)
        XCTAssertFalse(recognition.hasRecognizedContent)
        XCTAssertTrue(recognition.recognizedRows.isEmpty)
    }

    // MARK: summaryLine

    func testSummaryLineCombinesHeadlineAndDetail() {
        let recognition = CatalogChartRecognition.verdict(
            kind: .size, source: .pastedText, columns: sizeColumns, rows: rows(sizeRows))
        XCTAssertEqual(recognition.summaryLine,
                       "尺码表识别成功：\(recognition.detail)")
    }

    // MARK: 迁移回归锁：乱码判定的六条口径一字未改

    func testGarbageTokenRulesSurvivedTheMoveToSharedPackage() {
        XCTAssertTrue(CatalogChartQuality.isGarbageToken("PROMOTTOI"))
        XCTAssertTrue(CatalogChartQuality.isGarbageToken("G PROMOTTOI"))
        XCTAssertTrue(CatalogChartQuality.isGarbageToken("GXF"))
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("胸围"), "中文不是乱码")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("S"), "单字母尺码不是乱码")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("XL"), "双字母尺码不是乱码")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("Size"), "常见表头英文在白名单里")
        XCTAssertFalse(CatalogChartQuality.isGarbageToken("86-92"), "数值不是乱码")
    }

    func testKindDisplayNamesAreTheContractForEveryHeadline() {
        XCTAssertEqual(CatalogChartKind.size.displayName, "尺码表")
        XCTAssertEqual(CatalogChartKind.price.displayName, "预约价格表")
        for kind in CatalogChartKind.allCases {
            let success = CatalogChartRecognition.verdict(
                kind: kind, source: .pastedText,
                columns: priceColumns, rows: rows(priceRows))
            XCTAssertEqual(success.headline, kind.displayName + "识别成功")
        }
    }
}
