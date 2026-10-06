//
//  OpsSeriesPriceChartDraftTests.swift
//  PinkHouseOpsTests
//
//  「系列上新向导 S2 的系列价格表（含上传原图）」在 Mac 侧的**接线检查**
//  （2026-10-07 用户需求：「请把价格表的上传功能集成到当前页面中……」）。
//
//  ## ⚠️ 先读这条：本机跑不起来
//
//  `PinkHouseOpsTests` 是 **App 宿主式**测试，本机 `xcodebuild test` 会在
//  「before establishing connection」处**永久挂起**（2026-10-01 实测 6m37s）。
//  取证见 skill `pink-house-xcodebuild-acceptance` 的
//  `references/mac-xctest-hang-forensics.md`。**别等、别重试、别换 destination。**
//  本机可用的替代：`xcodebuild build-for-testing`（编译这整个文件，
//  抓拼写 / 可见性 / API 变更）+ 应用内快照 harness（真跑，出 PNG）。
//
//  所以本文件只锁**接线**：向导草稿有没有把这几条口径接对、接全。
//  规则本身（切分 / 归一 / 值个数 / 模板格式）住在共享包，由 `swift test` 秒级覆盖。
//
//  ## 为什么「关着开关就不校验」也值得锁
//
//  `declaresPriceChart` 是这次新增的**显式开关**，它同时管两件事：
//  提交时写不写、校验时拦不拦。这两件事一旦对不上（校验拦、提交不写，
//  或反过来），运营看到的就是「明明全绿，价格表却没动」——
//  正是本项目最反复吃亏的那类静默失败。
//

import XCTest
import UniformTypeIdentifiers   // `UTType` 的成员（`.pdf` / `preferredFilenameExtension`）
// ⚠️ 必须在使用文件里显式 import：本工程开了 `MemberImportVisibility`，
// 光靠 `@testable import PinkHouseOps` 拿不到 `UTType` 的成员。
@testable import PinkHouseOps

final class OpsSeriesPriceChartDraftTests: XCTestCase {

    private func draft(declares: Bool = true,
                       columns: String = CatalogChartTemplate.PriceChart.columnsText,
                       rows: String = CatalogChartTemplate.PriceChart.rowsText,
                       images: [String] = []) -> OpsSeriesEntryDraft {
        OpsSeriesEntryDraft(
            declaresPriceChart: declares,
            priceChartUnit: CatalogChartTemplate.PriceChart.unit,
            priceChartColumnsText: columns,
            priceChartRowsText: rows,
            priceChartImageAssetIDs: images)
    }

    /// 与界面完全同路：`draft.parsedPriceChart` → 共享判定。
    private func recognition(for draft: OpsSeriesEntryDraft) -> CatalogChartRecognition {
        let parsed = draft.parsedPriceChart
        return OpsChartRecognition.make(kind: .price,
                                        parsed: parsed.parsed,
                                        issue: parsed.issue)
    }

    // MARK: - ① 标准模板一次通过（模板常量来自共享包，UI 按钮读同一份）

    func testStandardTemplateProducesNoIssueAndIsRecognized() throws {
        let target = draft()
        XCTAssertEqual(OpsSeriesPriceChartValidation.issues(for: target), [])

        let parsed = try XCTUnwrap(target.parsedPriceChart.parsed)
        XCTAssertEqual(parsed.columns.count, 4, "模板是 4 个数据列：预约价/定金/尾款/现货价")
        XCTAssertEqual(parsed.rows.map(\.label), CatalogChartTemplate.PriceChart.rowLabels)
        for row in parsed.rows {
            XCTAssertEqual(row.values.count, 4)
            XCTAssertFalse(row.values.contains(nil), "「\(row.label)」不该有空值占位")
        }
        XCTAssertTrue(recognition(for: target).isSuccess)
    }

    // MARK: - ② ⭐⭐ 开关关着 = 提交不写、**也不校验**（两件事必须同口径）

    func testSwitchedOffDraftIsNeitherValidatedNorWritten() {
        // 故意写一张**半张表**（值个数不齐）：开关关着时它一个字都不该被提
        let target = draft(declares: false, rows: "蝴蝶结半裙 = 268, 80, 188")
        XCTAssertEqual(OpsSeriesPriceChartValidation.issues(for: target), [],
                       "⭐ 关着开关还要拦，「不碰价格表」这个逃生口就不存在了")
    }

    // MARK: - ③ 开着开关却什么都没填 → 必拦（并给出两条出路）

    func testSwitchedOnButEmptyIsRejectedWithActionableMessage() throws {
        let target = draft(columns: "", rows: "")
        let issues = OpsSeriesPriceChartValidation.issues(for: target)
        let message = try XCTUnwrap(issues.first)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(message.contains("上传"), "要说清「可以上传一张原图」：\(message)")
        XCTAssertTrue(message.contains("关掉"), "要给「关掉开关」这条出路：\(message)")
    }

    // MARK: - ④ ⭐ 「只有原图没有表格」是合法状态，不是失败

    func testImageOnlyDraftIsAcceptedAndCountsAsContent() {
        let target = draft(columns: "", rows: "", images: ["asset-aaaa"])
        XCTAssertEqual(OpsSeriesPriceChartValidation.issues(for: target), [],
                       "只有原图是模型允许的形态（hasStructuredContent == false），不能当错误拦")
        XCTAssertTrue(target.hasPriceChartContent)
        XCTAssertTrue(target.isPriceChartTextEmpty)
    }

    /// 一条都不填、也没图 → 不算有内容（提交时不许用空表覆盖系列上已有的价格表）
    func testNothingAtAllIsNotContent() {
        XCTAssertFalse(draft(columns: "", rows: "").hasPriceChartContent)
        XCTAssertTrue(draft().hasPriceChartContent)
    }

    // MARK: - ⑤ 半张表要按原话上报（用户报障的形态）

    func testValueCountMismatchIsRejectedAndSurfacesTheReason() throws {
        let target = draft(rows: "蝴蝶结半裙 = 268, 80, 188")   // 列 4 个、值 3 个
        let issues = OpsSeriesPriceChartValidation.issues(for: target)
        let message = try XCTUnwrap(issues.first)
        XCTAssertTrue(message.contains("3"), message)
        XCTAssertTrue(message.contains("4"), message)

        let verdict = recognition(for: target)
        XCTAssertFalse(verdict.isSuccess)
        XCTAssertEqual(verdict.headline, "预约价格表识别失败",
                       "headline 恒带图表名 —— S2 卡片的提示不会和尺码表串台")
    }

    // MARK: - ⑥ ⭐⭐ 旧草稿 JSON 必须照常解开（新字段一律有默认值）

    /// 向导工作副本长期持久化在 `OpsCatalogDraftRecord.seriesEntryJSON` 里。
    /// 新加的键如果没写 `decodeIfPresent` + 默认值，**运营机上的旧草稿会整份解不开**
    /// —— 那不是「少个价格表」，是所有已填内容一起丢。
    func testOldDraftJSONWithoutPriceChartKeysStillDecodes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // 1) 拿一份「新」草稿编码出来，再把这次新增的键**全部删掉**，模拟旧 JSON
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(draft(images: ["asset-aaaa"])))
                as? [String: Any])
        let newKeys = ["declaresPriceChart", "priceChartUnit",
                       "priceChartColumnsText", "priceChartRowsText",
                       "priceChartImageAssetIDs"]
        for key in newKeys {
            XCTAssertNotNil(object.removeValue(forKey: key), "编码结果里应有 \(key)")
        }

        // 2) 旧 JSON 必须能解开，且新字段落到「不碰价格表」的默认态
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try decoder.decode(OpsSeriesEntryDraft.self, from: legacy)
        XCTAssertFalse(decoded.declaresPriceChart, "默认必须是「不动价格表」")
        XCTAssertEqual(decoded.priceChartUnit, "")
        XCTAssertEqual(decoded.priceChartColumnsText, "")
        XCTAssertEqual(decoded.priceChartRowsText, "")
        XCTAssertEqual(decoded.priceChartImageAssetIDs, [])
        XCTAssertEqual(OpsSeriesPriceChartValidation.issues(for: decoded), [])
    }

    // MARK: - ⑦ 上传原图那一侧的格式白名单只有一份

    /// 界面文案、文件选择器过滤器、导入前校验**共用 `priceChartFileTypes`**。
    /// 这条锁的是「说明里写了支持、实际却被拦」这类最让人上火的错。
    func testSupportedFileTypesAndFormatListAgree() {
        let list = OpsWorkspace.priceChartFileFormatList
        for type in OpsWorkspace.priceChartFileTypes {
            guard let ext = type.preferredFilenameExtension else { continue }
            XCTAssertTrue(list.contains(ext.uppercased()),
                          "格式清单里应有 \(ext)：\(list)")
        }
        XCTAssertTrue(list.contains("PNG"))
        XCTAssertTrue(list.contains("JPEG"))

        // 文档类要**能被选中**（用户是拿 Excel 排好表再导出的），但**必须被拦**
        XCTAssertTrue(OpsWorkspace.priceChartPickerTypes.contains(.pdf))
        XCTAssertGreaterThan(OpsWorkspace.priceChartPickerTypes.count,
                             OpsWorkspace.priceChartFileTypes.count,
                             "选择器要刻意比白名单宽，选中后给可执行的拒绝")
        XCTAssertFalse(OpsWorkspace.isSupportedPriceChartFile(
            URL(fileURLWithPath: "/tmp/价格表.pdf")))
        XCTAssertFalse(OpsWorkspace.isSupportedPriceChartFile(
            URL(fileURLWithPath: "/tmp/价格表.xlsx")))
        XCTAssertFalse(OpsWorkspace.isSupportedPriceChartFile(
            URL(fileURLWithPath: "/tmp/没有扩展名")))
        XCTAssertTrue(OpsWorkspace.isSupportedPriceChartFile(
            URL(fileURLWithPath: "/tmp/价格表.PNG")))
        XCTAssertTrue(OpsWorkspace.isSupportedPriceChartFile(
            URL(fileURLWithPath: "/tmp/价格表.jpg")))
    }
}
