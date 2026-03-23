import XCTest
@testable import ItemManager

final class NoticeLogicTests: XCTestCase {
    func testReadTrackingKeyChangesAfterUpdate() {
        let notice = Notice(title: "标题", content: "内容")
        let originalKey = notice.readTrackingKey

        notice.version += 1
        notice.updatedAt = notice.updatedAt.addingTimeInterval(5)

        XCTAssertNotEqual(originalKey, notice.readTrackingKey)
    }

    func testLegacyFallbackOnlyForUnmodifiedNotice() {
        let notice = Notice(title: "标题", content: "内容")
        XCTAssertTrue(notice.shouldUseLegacyReadFallback)

        notice.version += 1
        notice.updatedAt = notice.updatedAt.addingTimeInterval(5)

        XCTAssertFalse(notice.shouldUseLegacyReadFallback)
    }

    func testBuiltinMediaURLString() {
        XCTAssertEqual(
            Notice.builtinMediaURLString(for: "notice_bg"),
            "builtin://notice_bg"
        )
    }
}
