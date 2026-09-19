import XCTest
@testable import ItemManager

// MARK: - 隐藏系列账本（种子 / 云端系列「删除 = 本机隐藏」，用户 2026-09-19）

@MainActor
final class MidsummerHiddenSeriesStoreTests: XCTestCase {

  private var directory: URL!
  private var store: MidsummerHiddenSeriesStore!

  override func setUp() async throws {
    // 隐藏系列属于创作者能力（服务层校验角色，与 CustomSeriesStore 同口径）。
    CreatorAccess.setTestOverride(.creator)
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("midsummer-hidden-series-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = MidsummerHiddenSeriesStore(directory: directory)
  }

  override func tearDown() async throws {
    CreatorAccess.setTestOverride(nil)
    try? FileManager.default.removeItem(at: directory)
  }

  /// hide 后 isHidden 为真；restore 后回归可见。
  func testHideAndRestoreRoundTrip() throws {
    let seedID = "syc-2026-spring"  // 樱花小羊这类种子系列 id（无 custom 前缀）
    XCTAssertFalse(store.isHidden(seedID))
    try store.hide(seedID)
    XCTAssertTrue(store.isHidden(seedID), "hide 后应进入隐藏账本")
    try store.restore(seedID)
    XCTAssertFalse(store.isHidden(seedID), "restore 后应从隐藏账本移除")
  }

  /// 重新 init（同一目录）应从 JSON 恢复——隐藏状态可跨启动，且能扛住云端刷新。
  func testPersistsAcrossInstances() throws {
    try store.hide("syc-2026-spring")
    try store.hide("midsummer-custom-abc")
    let reloaded = MidsummerHiddenSeriesStore(directory: directory)
    XCTAssertEqual(reloaded.hiddenIDs, ["syc-2026-spring", "midsummer-custom-abc"])
    XCTAssertTrue(reloaded.isHidden("syc-2026-spring"))
  }

  /// 非创作者调用 hide / restore 必须抛错且不改动数据（服务层权限兜底）。
  func testNonCreatorIsRejected() throws {
    CreatorAccess.setTestOverride(.viewer)
    XCTAssertThrowsError(try store.hide("syc-2026-spring")) { error in
      XCTAssertTrue(error is CreatorAccessDenied, "应抛权限拒绝错误")
    }
    XCTAssertFalse(store.isHidden("syc-2026-spring"), "被拒后账本不得变动")
    CreatorAccess.setTestOverride(.creator)
    try store.hide("syc-2026-spring")
    CreatorAccess.setTestOverride(.viewer)
    XCTAssertThrowsError(try store.restore("syc-2026-spring"))
    XCTAssertTrue(store.isHidden("syc-2026-spring"), "被拒的 restore 不得移除隐藏记录")
  }
}
