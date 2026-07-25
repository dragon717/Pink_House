import XCTest
@testable import ItemManager

final class CommaSeparatedTokensTests: XCTestCase {
    func testParseJoinRemove() {
        XCTAssertEqual(CommaSeparatedTokens.parse("JSK, OP, ,小物"), ["JSK", "OP", "小物"])
        XCTAssertEqual(CommaSeparatedTokens.join(["JSK", "OP"]), "JSK,OP")
        XCTAssertEqual(CommaSeparatedTokens.remove("OP", from: "JSK,OP,小物"), "JSK,小物")
        XCTAssertEqual(CommaSeparatedTokens.remove("均码", from: "均码"), "")
    }

    func testJoinPreservingOrder() {
        let previous = ["JSK", "OP", "SK"]
        let selected: Set<String> = ["SK", "小物", "JSK"]
        XCTAssertEqual(
            CommaSeparatedTokens.joinPreservingOrder(previous: previous, selected: selected),
            "JSK,SK,小物"
        )
    }

    func testToggleAndInlineTags() {
        XCTAssertEqual(CommaSeparatedTokens.toggle("OP", in: "JSK", allowsMultiple: true), "JSK,OP")
        XCTAssertEqual(CommaSeparatedTokens.toggle("JSK", in: "JSK,OP", allowsMultiple: true), "OP")
        XCTAssertEqual(CommaSeparatedTokens.toggle("长款", in: "短款", allowsMultiple: false), "长款")
        XCTAssertEqual(CommaSeparatedTokens.toggle("长款", in: "长款", allowsMultiple: false), "")
        XCTAssertEqual(
            CommaSeparatedTokens.inlineTags(selected: ["小物"], preferred: ["JSK", "OP", "SK", "小物", "Blouse"], maxCount: 4),
            ["小物", "JSK", "OP", "SK"]
        )
    }
}
