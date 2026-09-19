import XCTest
@testable import ItemManager

// MARK: - 自建系列存储（上传上新直达新建系列，用户 2026-09-17）

@MainActor
final class MidsummerCustomSeriesStoreTests: XCTestCase {

  private var directory: URL!
  private var store: MidsummerCustomSeriesStore!

  override func setUp() async throws {
    // 新建系列属于创作者能力（2026-09-18 起服务层校验角色），注入创作者角色。
    CreatorAccess.setTestOverride(.creator)
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("midsummer-custom-series-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = MidsummerCustomSeriesStore(directory: directory)
  }

  override func tearDown() async throws {
    CreatorAccess.setTestOverride(nil)
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeSeries(id: String = "midsummer-custom-test") -> MidsummerSeriesDTO {
    MidsummerSeriesDTO(
      id: id,
      name: "小熊博物馆系列",
      year: 2026,
      launchedOn: "2026-09-17",
      stage: .deposit,
      coverImage: nil,
      depositMin: nil,
      depositMax: nil,
      priceSource: nil,
      sizes: ["S", "M", "L"],
      colors: [],
      summary: "含大货，定金后 30 天内发货",
      sourceURL: "",
      sourceKind: "editorial",
      verified: false,
      items: []
    )
  }

  /// add 后可按 id 取回；同 id 再 add 覆盖（幂等）。
  func testAddAndLookupRoundTrip() {
    let series = makeSeries()
    try! store.add(series)
    XCTAssertEqual(store.series(withID: series.id)?.name, "小熊博物馆系列")
    XCTAssertEqual(store.series(withID: series.id)?.sizes, ["S", "M", "L"])

    var renamed = makeSeries(id: series.id)
    renamed = MidsummerSeriesDTO(
      id: renamed.id, name: "改名后的系列", year: renamed.year,
      launchedOn: renamed.launchedOn, stage: renamed.stage, coverImage: renamed.coverImage,
      depositMin: nil, depositMax: nil, priceSource: nil, sizes: renamed.sizes,
      colors: [], summary: renamed.summary, sourceURL: "", sourceKind: "editorial",
      verified: false, items: [])
    try! store.add(renamed)
    XCTAssertEqual(store.seriesList.count, 1, "同 id 重复 add 应覆盖而不是追加")
    XCTAssertEqual(store.series(withID: series.id)?.name, "改名后的系列")
  }

  /// 重新 init（同一目录）应从 JSON 恢复——存档落盘可跨启动。
  func testPersistsAcrossInstances() {
    try! store.add(makeSeries())
    let reloaded = MidsummerCustomSeriesStore(directory: directory)
    XCTAssertEqual(reloaded.seriesList.count, 1)
    XCTAssertEqual(reloaded.series(withID: "midsummer-custom-test")?.summary, "含大货，定金后 30 天内发货")
    XCTAssertEqual(reloaded.series(withID: "midsummer-custom-test")?.sourceKind, "editorial")
  }
}
