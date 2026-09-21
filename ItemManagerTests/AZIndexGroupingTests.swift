//
//  AZIndexGroupingTests.swift
//  ItemManagerTests
//
//  A-Z 索引分组纯逻辑单测（不落盘，不触碰沙盒数据）：
//    英文/小写转大写、中文转拼音首字母、符号归 #、分组排序与搜索匹配
//

import XCTest
@testable import ItemManager

final class AZIndexGroupingTests: XCTestCase {

    func test英文与数字混排名称取首字母() {
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "Alice Girl"), "A")
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "PINK HOUSE"), "P")
    }

    func test小写英文转大写() {
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "metamorphose temps de fille"), "M")
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "baby, the Stars Shine Bright"), "B")
    }

    func test中文转拼音首字母() {
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "仲夏物语"), "Z")   // zhòng
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "天使的谎言"), "T") // tiān
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "许愿池"), "X")     // xǔ
    }

    func test空串与符号归井号() {
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: ""), "#")
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "   "), "#")
        XCTAssertEqual(AZIndexGrouping.indexLetter(for: "☆STAR"), "#")
    }

    func test分组顺序为井号加AZ且组内排序() {
        struct Item { let name: String }
        let items = [
            Item(name: "仲夏物语"),
            Item(name: "alice girl"),
            Item(name: "Angelic Pretty"),
            Item(name: "☆符号"),
            Item(name: "Angelic Pretty"),  // 同名验证稳定性（无崩溃即可）
        ]
        let groups = AZIndexGrouping.groups(items) { $0.name }
        XCTAssertEqual(groups.map(\.letter), ["#", "A", "Z"])
        XCTAssertEqual(groups[1].items.map(\.name).first, "alice girl") // 同组内 a < A 的本地化排序
        XCTAssertEqual(groups[2].items.map(\.name), ["仲夏物语"])
    }

    func test搜索匹配名称与别名() {
        XCTAssertTrue(AZIndexGrouping.matches(name: "UNNIQ 许愿池原创",
                                             aliases: ["UNNIQ", "许愿池"],
                                             query: "许愿"))
        XCTAssertTrue(AZIndexGrouping.matches(name: "Alice Girl",
                                             aliases: ["AG", "爱丽丝少女"],
                                             query: "ag"))
        XCTAssertFalse(AZIndexGrouping.matches(name: "Alice Girl",
                                              aliases: ["AG"],
                                              query: "宝贝"))
        XCTAssertTrue(AZIndexGrouping.matches(name: "任意", aliases: [], query: "   ")) // 空查询全匹配
    }
}
