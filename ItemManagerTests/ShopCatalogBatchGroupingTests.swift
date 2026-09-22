//
//  ShopCatalogBatchGroupingTests.swift
//  ItemManagerTests
//
//  批次详情「本批单品按系列分组」分组键契约（2026-09-22 默认继承整批系列）：
//    1. 草稿自报系列（关联系列 / 新建系列名）→ 用自己的，整批归属不覆盖
//    2. 草稿未自报 → 继承整批当前选定系列（上方联动）
//    3. 整批也未选定 → 「未指定系列」（原有默认行为）
//    4. seriesID 解析失败 → 原始 id 兜底（仍是自报，优先于整批）
//

import XCTest
@testable import ItemManager

final class ShopCatalogBatchGroupingTests: XCTestCase {

    // MARK: 1. 自报系列优先，不被整批覆盖

    func testDraftOwnSeriesWinsOverBatchSelection() {
        let key = CatalogBatchGrouping.groupKey(
            draftOwnSeriesName: "夜莺 2025 冬", batchSeriesName: "小狗仪仗队")
        XCTAssertEqual(key, "夜莺 2025 冬", "用户手动指定的系列不被整批归属覆盖")
    }

    func testDraftNewSeriesNameCountsAsOwn() {
        let key = CatalogBatchGrouping.groupKey(
            draftOwnSeriesName: "手填新系列", batchSeriesName: "整批系列")
        XCTAssertEqual(key, "手填新系列")
    }

    // MARK: 2. 未自报 → 继承整批

    func testUnspecifiedDraftInheritsBatchSeries() {
        let key = CatalogBatchGrouping.groupKey(
            draftOwnSeriesName: nil, batchSeriesName: "小狗仪仗队")
        XCTAssertEqual(key, "小狗仪仗队", "未指定系列的单品默认继承整批选定系列")
    }

    // MARK: 3. 双方都没有 → 原有默认行为

    func testBothUnspecifiedFallsBackToPlaceholder() {
        let key = CatalogBatchGrouping.groupKey(
            draftOwnSeriesName: nil, batchSeriesName: nil)
        XCTAssertEqual(key, CatalogBatchGrouping.unspecified)
        XCTAssertEqual(CatalogBatchGrouping.unspecified, "未指定系列")
    }

    // MARK: 4. seriesID 解析失败的兜底

    func testUnresolvableSeriesIDFallsBackToRawIDAndStillWins() {
        // store 里查不到的系列 id：展示用原始 id，但仍是「自报」，优先于整批
        let key = CatalogBatchGrouping.groupKey(
            draftOwnSeriesName: "series-ghost-id", batchSeriesName: "整批系列")
        XCTAssertEqual(key, "series-ghost-id")
    }
}
