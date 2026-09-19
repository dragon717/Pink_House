import UIKit
import XCTest
@testable import ItemManager

// MARK: - 创作者角色与权限单测（用户 2026-09-18）
//
// 覆盖两条链路：
//   1. **角色判定矩阵**（纯函数 `CreatorAccess.resolveRole`）：
//      白名单命中 / 明确排除 / 取不到身份 × 本机开关，谁该是创作者；
//   2. **服务层拦截**：绕过界面直接调写接口时，`MidsummerListingStore` /
//      `MidsummerCustomSeriesStore` 必须抛错且**不改动数据**。
//
// 角色注入走 `CreatorAccess.setTestOverride`，不碰真实白名单判定与本机存档。

@MainActor
final class CreatorAccessTests: XCTestCase {

  private let seriesID = "midsummer-2026-sakura-lamb"

  override func setUp() {
    super.setUp()
    CreatorAccess.setTestOverride(nil)
  }

  override func tearDown() {
    CreatorAccess.setTestOverride(nil)
    CreatorAccess.shared.apply(gate: .unresolved(reason: "单测结束"))
    super.tearDown()
  }

  // MARK: 角色判定矩阵

  func testWhitelistHitIsCreatorEvenWithoutLocalSwitch() {
    let resolved = CreatorAccess.resolveRole(gate: .allowed, localSwitchEnabled: false)
    XCTAssertEqual(resolved.role, .creator)
    XCTAssertEqual(resolved.basis, .whitelist)
  }

  /// 明确不在白名单：本机开关**撬不开**——否则等于人人可自提权。
  func testDeniedStaysViewerEvenWithLocalSwitchOn() {
    let resolved = CreatorAccess.resolveRole(gate: .denied, localSwitchEnabled: true)
    XCTAssertEqual(resolved.role, .viewer)
    XCTAssertEqual(resolved.basis, .whitelistRejected)
  }

  func testUnresolvedFallsBackToLocalSwitch() {
    XCTAssertEqual(
      CreatorAccess.resolveRole(gate: .unresolved(reason: "模拟器"), localSwitchEnabled: true).role,
      .creator, "取不到身份时由本机开关放行（内容维护者在模拟器上的通路）")
    XCTAssertEqual(
      CreatorAccess.resolveRole(gate: .unresolved(reason: "模拟器"), localSwitchEnabled: false).role,
      .viewer, "取不到身份 + 开关关闭 = 普通用户（保守优先）")
  }

  // MARK: 白名单灰度判定（用户 2026-09-19 新版分类与款式表单）

  /// 新版表单布局只认**运营白名单命中**：本机开关（模拟器通路）不放行，
  /// 明确排除与未判定一律不算白名单创作者。
  func testWhitelistedCreatorGateRequiresExplicitAllow() {
    XCTAssertTrue(CreatorAccess.isWhitelistedGate(.allowed), "白名单命中 = 灰度放行")
    XCTAssertFalse(
      CreatorAccess.isWhitelistedGate(.denied),
      "明确不在白名单：本机开关也撬不开灰度能力")
    XCTAssertFalse(
      CreatorAccess.isWhitelistedGate(.unresolved(reason: "模拟器")),
      "未判定（含本机创作者模式开启）不算白名单命中——灰度只认运营名单")
  }

  /// 本机开关真的写进 UserDefaults 时，服务层同步校验也要立刻认。
  func testLocalSwitchIsReadLiveByServiceLayer() {
    let key = CreatorMode.storageKey
    let previous = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.set(true, forKey: key)
    defer {
      if let previous {
        UserDefaults.standard.set(previous, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    CreatorAccess.shared.apply(gate: .unresolved(reason: "未登录 iCloud"))
    XCTAssertTrue(CreatorAccess.shared.isCreator)
    XCTAssertNoThrow(try CreatorAccess.requireCreator(.priceEdit))
  }

  func testDeniedGateLocksLocalSwitchOutOfServiceLayer() {
    CreatorAccess.shared.apply(gate: .denied)
    XCTAssertFalse(CreatorAccess.shared.isCreator)
    XCTAssertThrowsError(try CreatorAccess.requireCreator(.priceEdit)) { error in
      guard let denied = error as? CreatorAccessDenied else {
        return XCTFail("应抛 CreatorAccessDenied，实际是 \(error)")
      }
      XCTAssertEqual(denied.operation, .priceEdit)
      XCTAssertTrue(
        denied.errorDescription?.contains("修改价格") ?? false,
        "提示要能说清是哪一步被拦：\(denied.errorDescription ?? "")")
    }
  }

  // MARK: 服务层拦截（绕过界面直接调用）

  /// 普通用户直接 upsert：抛错，且**不写入**任何记录。
  func testViewerCannotUpsertListing() {
    CreatorAccess.setTestOverride(.viewer)
    let store = makeTempStore()
    XCTAssertThrowsError(try store.upsert(makeListing())) { error in
      XCTAssertTrue(error is CreatorAccessDenied, "应被权限校验拦下：\(error)")
    }
    XCTAssertTrue(store.listings.isEmpty, "被拒时不能留下半条记录")
  }

  func testViewerCannotChangeStatusOrDelete() {
    CreatorAccess.setTestOverride(.creator)
    let store = makeTempStore()
    let listing = makeListing()
    try! store.upsert(listing)

    CreatorAccess.setTestOverride(.viewer)
    XCTAssertThrowsError(try store.updateStatus(of: listing.id, to: .delisted))
    XCTAssertEqual(store.listing(withID: listing.id)?.status, .listed, "状态未被改动")
    XCTAssertThrowsError(try store.delete(listing.id))
    XCTAssertEqual(store.listings.count, 1, "记录未被删掉")
  }

  /// 换图：拒绝发生在**删旧图之前**，被拒不该把原图清掉。
  func testViewerCannotReplaceImages() {
    CreatorAccess.setTestOverride(.creator)
    let store = makeTempStore()
    let listing = makeListing()
    let saved = try! store.saveImages([makeSolidImage()], listingID: listing.id)
    XCTAssertFalse(saved.isEmpty)

    CreatorAccess.setTestOverride(.viewer)
    XCTAssertThrowsError(try store.saveImages([makeSolidImage()], listingID: listing.id))
    XCTAssertThrowsError(
      try store.saveStyleImage(makeSolidImage(), listingID: listing.id, index: 0))
    for name in saved {
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: ImageManager.shared.imagesDirectory.appendingPathComponent(name).path),
        "权限被拒时原图必须还在")
    }
  }

  func testViewerCannotCreateCustomSeries() {
    CreatorAccess.setTestOverride(.viewer)
    let store = MidsummerCustomSeriesStore(directory: temporaryDirectory())
    XCTAssertThrowsError(try store.add(makeSeriesDTO()))
    XCTAssertTrue(store.seriesList.isEmpty)
  }

  func testCreatorCanWriteAllTheWay() {
    CreatorAccess.setTestOverride(.creator)
    let store = makeTempStore()
    var listing = makeListing()
    try! store.upsert(listing, operation: .listingPublish)
    XCTAssertEqual(store.listings.count, 1)

    listing.price = 288
    try! store.upsert(listing, operation: .priceEdit)
    XCTAssertEqual(store.listing(withID: listing.id)?.price, 288)

    try! store.updateStatus(of: listing.id, to: .listed)
    XCTAssertEqual(store.listing(withID: listing.id)?.status, .listed)

    let seriesStore = MidsummerCustomSeriesStore(directory: temporaryDirectory())
    try! seriesStore.add(makeSeriesDTO())
    XCTAssertEqual(seriesStore.seriesList.count, 1)
  }

  /// 预售相位自动流转是**系统行为**，不能被权限校验挡住：
  /// 普通用户的 App 里到期的定金商品也要推进到尾款期。
  func testPresaleAutoTransitionIgnoresPermission() {
    CreatorAccess.setTestOverride(.creator)
    let store = makeTempStore()
    let now = Date()
    var listing = makeListing()
    listing.stage = .deposit
    listing.depositEndsAt = now.addingTimeInterval(-1)
    try! store.upsert(listing)

    CreatorAccess.setTestOverride(.viewer)
    let moved = store.refreshPresaleTransitions(now: now)
    XCTAssertEqual(moved, 1, "自动流转与角色无关，不能被权限门控挡住")
    XCTAssertEqual(store.listing(withID: listing.id)?.stage, .balance)
  }

  // MARK: 夹具

  private func makeTempStore() -> MidsummerListingStore {
    MidsummerListingStore(directory: temporaryDirectory())
  }

  private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("creator-access-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func makeListing() -> MidsummerListing {
    MidsummerListing(
      id: "upload-\(UUID().uuidString.lowercased())",
      seriesID: seriesID,
      name: "权限验收 JSK",
      kindRaw: MidsummerItemKind.jsk.rawValue,
      price: 288,
      preorderPrice: nil,
      deposit: nil,
      balance: nil,
      priceKindRaw: MidsummerPriceKind.shop.rawValue,
      note: "",
      sourceURL: "",
      sizes: ["S"],
      variantOptionNames: [],
      imageFiles: [],
      status: .listed,
      createdAt: Date(),
      updatedAt: Date(),
      listedAt: Date()
    )
  }

  private func makeSeriesDTO() -> MidsummerSeriesDTO {
    MidsummerSeriesDTO(
      id: "midsummer-custom-\(UUID().uuidString.lowercased())",
      name: "权限验收系列",
      year: 2026,
      launchedOn: "",
      stage: .preview,
      coverImage: nil,
      depositMin: nil,
      depositMax: nil,
      priceSource: nil,
      sizes: [],
      colors: [],
      summary: nil,
      sourceURL: "",
      sourceKind: "editorial",
      verified: false,
      items: []
    )
  }

  private func makeSolidImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
      .image { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
      }
  }
}
