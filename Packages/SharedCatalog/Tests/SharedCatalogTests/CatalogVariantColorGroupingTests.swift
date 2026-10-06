//
//  CatalogVariantColorGroupingTests.swift
//  SharedCatalogTests
//
//  「规格（配色 / 尺码）」按颜色归组的显示口径回归锁（2026-10-07 用户需求）。
//
//  ## 用户原文
//
//    「……**规格颜色区域默认仅显示颜色信息**。请明确勾选与取消的触发时机、
//      **颜色规格的显示规则**。」
//
//  ## 这一份测试真正在护的是什么
//
//  归组本身很平凡，容易写错的是三处**口径**：
//  ① `nil` / `""` / `"  "` 必须是同一组（否则「未区分颜色」会被拆成三行）；
//  ② 组顺序与组内顺序必须是**录入顺序**（用 `Set` / `Dictionary` 派生顺序，
//     列表每次渲染都可能换位，看起来像在随机抖动）；
//  ③ 代表缩略图要取「第一条**有图**的规格」而不是「第一条规格」，
//     否则首条没配图时，明明有图的颜色会显示成空框。
//

import XCTest
@testable import SharedCatalog

final class CatalogVariantColorGroupingTests: XCTestCase {

    /// 测试用的最小规格替身（字段与 `CatalogProductVariant` 同形：color / size / image）
    private struct V: Equatable {
        let color: String?
        let size: String?
        let image: String?
    }

    private func groups(_ items: [V]) -> [CatalogVariantColorGroup<V>] {
        CatalogVariantColorGrouping.groups(items, color: { $0.color })
    }

    // MARK: - ① 归一：没填就是没填

    func testBlankColorsCollapseIntoOneUnspecifiedGroup() {
        let items = [
            V(color: nil, size: "S", image: nil),
            V(color: "", size: "M", image: nil),
            V(color: "   ", size: "L", image: nil),
        ]
        let result = groups(items)
        XCTAssertEqual(result.count, 1, "nil / 空串 / 纯空白必须是同一组")
        XCTAssertNil(result[0].color)
        XCTAssertEqual(result[0].items.count, 3)
        XCTAssertEqual(CatalogVariantColorGrouping.colorTitle(nil), "未区分颜色")
    }

    func testColorIsTrimmed() {
        XCTAssertEqual(CatalogVariantColorGrouping.normalizedColor(" 绯红 "), "绯红")
        XCTAssertNil(CatalogVariantColorGrouping.normalizedColor(""))
        XCTAssertNil(CatalogVariantColorGrouping.normalizedColor(nil))
    }

    // MARK: - ② 顺序 = 录入顺序（不是字典序、更不是集合遍历序）

    func testGroupOrderFollowsEntryOrderNotAlphabet() {
        let items = [
            V(color: "藏蓝", size: "S", image: nil),
            V(color: "绯红", size: "S", image: nil),
            V(color: "藏蓝", size: "M", image: nil),
            V(color: "月白", size: "S", image: nil),
        ]
        let result = groups(items)
        XCTAssertEqual(result.map(\.color), ["藏蓝", "绯红", "月白"])
    }

    func testItemsKeepTheirWithinGroupEntryOrder() {
        let items = [
            V(color: "绯红", size: "L", image: nil),
            V(color: "绯红", size: "S", image: nil),
            V(color: "绯红", size: "M", image: nil),
        ]
        XCTAssertEqual(groups(items)[0].items.map(\.size), ["L", "S", "M"],
                       "组内顺序必须原样保留，不许按尺码表 / 字典序重排")
    }

    func testUnspecifiedGroupKeepsItsPosition() {
        let items = [
            V(color: "绯红", size: "S", image: nil),
            V(color: nil, size: "S", image: nil),
            V(color: "月白", size: "S", image: nil),
        ]
        XCTAssertEqual(groups(items).map(\.color), ["绯红", nil, "月白"])
    }

    // MARK: - ③ 尺码摘要

    func testSizeSummaryDedupesAndKeepsOrder() {
        XCTAssertEqual(
            CatalogVariantColorGrouping.sizeSummary(["S", "M", "S", "L"]),
            "3 个尺码：S、M、L")
    }

    func testSizeSummaryWithoutSizes() {
        XCTAssertEqual(CatalogVariantColorGrouping.sizeSummary([]), "无尺码")
        XCTAssertEqual(CatalogVariantColorGrouping.sizeSummary([nil, "  "]), "无尺码")
    }

    /// 同一色里混了有尺码和无尺码的规格 = 数据本身不齐，**不能吞掉**。
    func testSizeSummaryReportsMixedSizelessRows() {
        XCTAssertEqual(
            CatalogVariantColorGrouping.sizeSummary(["S", nil, "M", nil]),
            "2 个尺码：S、M（另有 2 条无尺码）")
    }

    // MARK: - ④ 代表缩略图 / 缺图计数

    func testLeadingImageSkipsRowsWithoutImage() {
        let items = [
            V(color: "绯红", size: "S", image: nil),
            V(color: "绯红", size: "M", image: "local:a.png"),
            V(color: "绯红", size: "L", image: "local:b.png"),
        ]
        XCTAssertEqual(CatalogVariantColorGrouping.leadingImage(items, image: { $0.image }),
                       "local:a.png",
                       "代表图必须取第一条**有图**的规格，不是第一条规格")
        XCTAssertNil(CatalogVariantColorGrouping.leadingImage(
            [V(color: "绯红", size: "S", image: nil)], image: { $0.image }))
    }

    func testMissingImageCount() {
        let items = [
            V(color: "绯红", size: "S", image: nil),
            V(color: "绯红", size: "M", image: "local:a.png"),
            V(color: "绯红", size: "L", image: "   "),
        ]
        XCTAssertEqual(CatalogVariantColorGrouping.missingImageCount(items, image: { $0.image }), 2)
    }

    // MARK: - ⑤ 什么时候不值得分组

    /// 只有一个颜色时，分组不提供任何信息量 —— 多一层「展开」只是多点一次。
    func testSingleColorIsNotWorthGrouping() {
        let items = [
            V(color: "绯红", size: "S", image: nil),
            V(color: "绯红", size: "M", image: nil),
        ]
        XCTAssertFalse(CatalogVariantColorGrouping.shouldGroup(items, color: { $0.color }))
        XCTAssertTrue(CatalogVariantColorGrouping.shouldGroup(
            items + [V(color: "月白", size: "S", image: nil)], color: { $0.color }))
        XCTAssertFalse(CatalogVariantColorGrouping.shouldGroup([V](), color: { $0.color }))
    }

    // MARK: - ⑥ 「展开全部 / 收起全部」

    func testAllExpandedSemantics() {
        let items = [
            V(color: "绯红", size: "S", image: nil),
            V(color: "月白", size: "S", image: nil),
            V(color: "藏蓝", size: "S", image: nil),
        ]
        // 全部收起 / 部分展开 → 都该显示「展开全部」
        XCTAssertFalse(CatalogVariantColorGrouping.allExpanded(
            items, color: { $0.color }, isExpanded: { _ in false }))
        XCTAssertFalse(CatalogVariantColorGrouping.allExpanded(
            items, color: { $0.color }, isExpanded: { $0 == "绯红" }),
            "部分展开时按钮应该是「展开全部」")
        XCTAssertTrue(CatalogVariantColorGrouping.allExpanded(
            items, color: { $0.color }, isExpanded: { _ in true }))
    }

    func testAllExpandedIsFalseWhenThereIsNothing() {
        XCTAssertFalse(CatalogVariantColorGrouping.allExpanded(
            [V](), color: { $0.color }, isExpanded: { _ in true }),
            "空列表时不该显示「收起全部」")
    }

    // MARK: - ⑦ 与真实录入形态对齐

    /// 3 色 × 5 码 = 15 条 → 默认只该看到 **3 行**。
    func testCartesianProductCollapsesToColorCount() {
        var items: [V] = []
        for color in ["绯红", "月白", "藏蓝"] {
            for size in ["XS", "S", "M", "L", "XL"] {
                items.append(V(color: color, size: size, image: "local:\(color)-\(size).png"))
            }
        }
        let result = groups(items)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.items.count), [5, 5, 5])
        XCTAssertEqual(CatalogVariantColorGrouping.sizeSummary(result[0].items.map(\.size)),
                       "5 个尺码：XS、S、M、L、XL")
        XCTAssertEqual(CatalogVariantColorGrouping.missingImageCount(
            result[0].items, image: { $0.image }), 0)
    }
}
