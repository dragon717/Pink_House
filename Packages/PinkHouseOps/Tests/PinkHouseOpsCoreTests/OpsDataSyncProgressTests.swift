import XCTest
import SharedCatalog
@testable import PinkHouseOpsCore

final class OpsDataSyncProgressTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testDownloadCountsAdvanceAndUploadStartsANewPhase() {
        var progress = OpsDataSyncProgress(title: "迁移", now: start)
        progress.receive(.init(type: "progress", stage: .fetchMedia, completed: 37, total: 630),
                         mode: .fetchMedia, environment: .development, now: start.addingTimeInterval(5))
        XCTAssertEqual(progress.title, "下载开发环境图片")
        XCTAssertEqual(progress.countText, "37/630 张")
        XCTAssertEqual(progress.fraction!, 37.0 / 630, accuracy: 0.0001)
        progress.receive(.init(type: "stage", stage: .uploadMedia, state: .started),
                         mode: .publish, environment: .production, now: start.addingTimeInterval(10))
        XCTAssertNil(progress.completed)
        XCTAssertNil(progress.fraction)
        progress.receive(.init(type: "progress", stage: .uploadMedia, completed: 2, total: 600),
                         mode: .publish, environment: .production, now: start.addingTimeInterval(12))
        XCTAssertEqual(progress.title, "上传线上环境图片")
        XCTAssertEqual(progress.countText, "2/600 张")
        XCTAssertEqual(progress.startedAt, start)
    }

    func testRepeatedAndRegressingEventsDoNotHideWaiting() {
        var progress = OpsDataSyncProgress(title: "迁移", now: start)
        let event = ShopCatalogPublishEvent(type: "progress", stage: .fetchMedia, completed: 2, total: 10)
        progress.receive(event, mode: .fetchMedia, environment: .development, now: start)
        progress.receive(event, mode: .fetchMedia, environment: .development, now: start.addingTimeInterval(50))
        progress.receive(.init(type: "stage", stage: .fetchMedia, state: .started),
                         mode: .fetchMedia, environment: .development, now: start.addingTimeInterval(51))
        progress.receive(.init(type: "progress", stage: .fetchMedia, completed: 1, total: 10),
                         mode: .fetchMedia, environment: .development, now: start.addingTimeInterval(52))
        XCTAssertEqual(progress.lastAdvancedAt, start)
        XCTAssertEqual(progress.countText, "2/10 张")
        XCTAssertEqual(progress.timingText(at: start.addingTimeInterval(65)),
                       "已用 1 分 5 秒 · 等待响应 1 分 5 秒，尚未完成")
    }

    func testImageCompletionDoesNotSkipCloudConfirmation() {
        var progress = OpsDataSyncProgress(title: "迁移", now: start)
        progress.receive(.init(type: "progress", stage: .uploadMedia, completed: 10, total: 10),
                         mode: .publish, environment: .production, now: start)
        XCTAssertEqual(progress.fraction, 1)
        progress.receive(.init(type: "stage", stage: .confirmHead, state: .started),
                         mode: .publish, environment: .production, now: start.addingTimeInterval(2))
        XCTAssertEqual(progress.title, "确认线上环境更新结果")
        XCTAssertNil(progress.fraction)
        XCTAssertNil(progress.countText)
    }

    func testInvalidCountsAndEmptyImageStageNeverShowInvalidPercentage() {
        var progress = OpsDataSyncProgress(title: "迁移", now: start)
        progress.receive(.init(type: "progress", stage: .fetchMedia, completed: -1, total: 10),
                         mode: .fetchMedia, environment: .development, now: start)
        XCTAssertNil(progress.fraction)
        progress.receive(.init(type: "progress", stage: .fetchMedia, completed: 0, total: 0),
                         mode: .fetchMedia, environment: .development, now: start)
        XCTAssertNil(progress.fraction)
        progress.receive(.init(type: "progress", stage: .fetchMedia, completed: 20, total: 10),
                         mode: .fetchMedia, environment: .development, now: start)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testBaselineToCatalogAndLocalSaveResetTheImageCounter() {
        var progress = OpsDataSyncProgress(title: "拉取", now: start)
        progress.receive(.init(type: "stage", stage: .baseline, state: .succeeded),
                         mode: .pullCatalog, environment: .production, now: start)
        XCTAssertEqual(progress.title, "下载线上环境目录")
        progress.receive(.init(type: "progress", stage: .fetchMedia, completed: 4, total: 4),
                         mode: .fetchMedia, environment: .production, now: start)
        progress.advance(to: "合并并保存本地数据", now: start.addingTimeInterval(4))
        XCTAssertNil(progress.countText)
        XCTAssertEqual(progress.title, "合并并保存本地数据")
    }

    func testActualRemoteMediaBridgeEventIsRecognized() throws {
        let event = try XCTUnwrap(ShopCatalogPublishEvent.decoded(fromLine:
            #"{"type":"stage","stage":"remoteMedia","state":"started"}"#))
        var progress = OpsDataSyncProgress(title: "迁移", now: start)
        progress.receive(event, mode: .publish, environment: .production, now: start)
        XCTAssertEqual(progress.title, "检查线上环境已有图片")
    }
}
