import XCTest
@testable import ItemManager

// MARK: - 定金 → 尾款 预售状态机单测（用户 2026-09-17 业务规则）
//
// 覆盖：相位判定（含全部边界）→ 列表归属 → 写入式流转 → 价格恒等式
// （定金 + 尾款 = 预约价）→ 详情页预售结束双价展示。

@MainActor
final class MidsummerPresalePhaseTests: XCTestCase {

  private let seriesID = "midsummer-2026-sakura-lamb"

  /// 统一的时间基准：以真实「现在」为锚做偏移。store 的写入式流转与
  /// 相位判定共用同一个 now，避免 init 时钟与测试时钟错位。
  private var anchor: Date { Date() }

  /// 以「定金 ¥100 + 尾款 ¥200」为默认价的预售商品夹具。
  /// id 必须唯一：store.upsert 按 id 去重，同 id 会互相覆盖。
  private func makeDepositListing(
    id: String = UUID().uuidString.lowercased(),
    depositEndsAt: Date? = nil, balanceEndsAt: Date? = nil,
    deposit: Int? = 100, balance: Int? = 200,
    status: MidsummerListingStatus = .listed
  ) -> MidsummerListing {
    var listing = MidsummerListing(
      id: id,
      seriesID: seriesID,
      name: "预售验收 JSK",
      kindRaw: MidsummerItemKind.jsk.rawValue,
      price: nil,
      preorderPrice: nil,
      deposit: deposit,
      balance: balance,
      priceKindRaw: nil,
      note: "",
      sourceURL: "",
      sizes: ["S"],
      variantOptionNames: [],
      imageFiles: [],
      status: status,
      createdAt: Date(),
      updatedAt: Date(),
      listedAt: Date()
    )
    listing.stage = .deposit
    listing.depositEndsAt = depositEndsAt
    listing.balanceEndsAt = balanceEndsAt
    return listing
  }

  private func makeBalanceListing(balanceEndsAt: Date? = nil) -> MidsummerListing {
    let listing = makeDepositListing()
    var updated = listing
    updated.stage = .balance
    updated.balanceEndsAt = balanceEndsAt
    return updated
  }

  // MARK: 相位判定 · 定金期

  /// 未配置截止时间 = 定金期不会自动结束，一直停留。
  func testDepositWithoutDeadlineStaysInDeposit() {
    let listing = makeDepositListing()
    XCTAssertEqual(listing.presalePhase(at: .distantFuture), .deposit)
  }

  /// 截止时间未到 → 仍在定金期（用户规则 1：上新区可见）。
  func testDepositBeforeDeadlineIsDeposit() {
    let now = anchor
    let listing = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(86_400))
    XCTAssertEqual(listing.presalePhase(at: now), .deposit)
  }

  // MARK: 相位判定 · 定金结束 → 尾款期

  /// 定金截止（未配尾款截止）→ 尾款期（用户规则 2+3：自动移出上新区、进尾款列表）。
  func testDepositEndedWithoutBalanceDeadlineMovesToBalance() {
    let now = anchor
    let listing = makeDepositListing(depositEndsAt: now.addingTimeInterval(-1))
    XCTAssertEqual(listing.presalePhase(at: now), .balance)
  }

  /// 定金截止、尾款未截止 → 尾款期。
  func testDepositEndedBalanceRunningIsBalance() {
    let now = anchor
    let listing = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(-3_600),
      balanceEndsAt: now.addingTimeInterval(3_600))
    XCTAssertEqual(listing.presalePhase(at: now), .balance)
  }

  /// 卡点时刻（now == depositEndsAt）算定金结束。
  func testExactDeadlineBoundaryCountsAsEnded() {
    let deadline = anchor
    let listing = makeDepositListing(depositEndsAt: deadline)
    XCTAssertEqual(listing.presalePhase(at: deadline), .balance)
  }

  // MARK: 相位判定 · 预售结束

  /// 定金与尾款均结束 → 预售结束（用户规则 4：详情双价展示）。
  func testBothDeadlinesPassedIsEnded() {
    let now = anchor
    let listing = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(-7_200),
      balanceEndsAt: now.addingTimeInterval(-3_600))
    XCTAssertEqual(listing.presalePhase(at: now), .ended)
  }

  /// 倒挂配置（尾款截止 ≤ 定金截止）：定金结束时尾款期已被压成 0，
  /// 不产生瞬时尾款期，直接判预售结束。
  func testInvertedDeadlinesEndImmediatelyAfterDeposit() {
    let now = anchor
    let listing = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(-3_600),
      balanceEndsAt: now.addingTimeInterval(-7_200))
    XCTAssertEqual(listing.presalePhase(at: now), .ended)
  }

  /// 尾款阶段 + 尾款截止已过 → 预售结束；未配截止 → 一直尾款期。
  func testBalanceStageDeadline() {
    let now = anchor
    XCTAssertEqual(
      makeBalanceListing(balanceEndsAt: nil).presalePhase(at: now), .balance)
    XCTAssertEqual(
      makeBalanceListing(balanceEndsAt: now.addingTimeInterval(-1)).presalePhase(at: now), .ended)
    XCTAssertEqual(
      makeBalanceListing(balanceEndsAt: now.addingTimeInterval(1)).presalePhase(at: now), .balance)
  }

  /// 预约价 / 现货阶段不走定金-尾款状态机（返回 nil，展示逻辑各走各的）。
  func testNonPresaleStagesReturnNil() {
    var listing = makeDepositListing()
    listing.stage = .preorder
    XCTAssertNil(listing.presalePhase(at: .distantFuture))
    listing.stage = .inStock
    XCTAssertNil(listing.presalePhase(at: .distantFuture))
    listing.stage = nil
    XCTAssertNil(listing.presalePhase(at: .distantFuture))
  }

  // MARK: 价格恒等式：定金 + 尾款 = 预约价

  func testExpectedPreorderPriceIsDepositPlusBalance() {
    var listing = makeDepositListing(deposit: 100, balance: 200)
    XCTAssertEqual(listing.expectedPreorderPrice, 300)
    listing.balance = nil
    XCTAssertNil(listing.expectedPreorderPrice, "缺尾款算不出全款，不硬凑")
    listing.deposit = nil
    XCTAssertNil(listing.expectedPreorderPrice)
  }

  // MARK: 写入式流转

  /// 定金到期 → refreshPresaleTransitions 把 stage 写成 .balance；
  /// 预售结束不写盘（相位由时间函数实时推导，创作者改日期可复活）。
  func testRefreshTransitionsWritesDepositToBalanceOnly() {
    let now = anchor
    let ended = makeBalanceListing(balanceEndsAt: now.addingTimeInterval(-1))
    let depositDue = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(-1), deposit: nil, balance: nil)
    let depositRunning = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(3_600), deposit: nil, balance: nil)

    let store = MidsummerListingStore(directory: temporaryDirectory())
    store.upsert(ended)
    store.upsert(depositDue)
    store.upsert(depositRunning)

    let moved = store.refreshPresaleTransitions(now: now)
    XCTAssertEqual(moved, 1, "只有到期的定金商品发生流转")
    XCTAssertEqual(store.listing(withID: depositDue.id)?.stage, .balance)
    XCTAssertEqual(
      store.listing(withID: ended.id)?.stage, .balance,
      "预售结束不写入终态——保持 .balance，由相位函数判 ended")
  }

  /// 草稿 / 已下架不参与自动流转。
  func testRefreshTransitionsSkipsUnlisted() {
    let now = anchor
    let draft = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(-1), status: .draft)
    let store = MidsummerListingStore(directory: temporaryDirectory())
    store.upsert(draft)
    XCTAssertEqual(store.refreshPresaleTransitions(now: now), 0)
    XCTAssertEqual(store.listing(withID: draft.id)?.stage, .deposit)
  }

  /// 创作者延长尾款截止 → ended 相位自动复活回尾款期（不落死的关键）。
  func testExtendingBalanceDeadlineRevivesPhase() {
    let now = anchor
    var listing = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(-7_200),
      balanceEndsAt: now.addingTimeInterval(-3_600))
    XCTAssertEqual(listing.presalePhase(at: now), .ended)
    listing.balanceEndsAt = now.addingTimeInterval(3_600)
    XCTAssertEqual(listing.presalePhase(at: now), .balance, "延期后应回到尾款期")
  }

  // MARK: 列表归属查询

  func testPresaleGroupedOrdersDepositBalanceEnded() {
    let now = anchor
    let deposit = makeDepositListing(
      depositEndsAt: now.addingTimeInterval(3_600), deposit: nil, balance: nil)
    let balance = makeBalanceListing(balanceEndsAt: now.addingTimeInterval(3_600))
    let ended = makeBalanceListing(balanceEndsAt: now.addingTimeInterval(-1))
    var spot = makeDepositListing(deposit: nil, balance: nil)
    spot.stage = .inStock

    let store = MidsummerListingStore(directory: temporaryDirectory())
    for listing in [deposit, balance, ended, spot] { store.upsert(listing) }

    let groups = store.presaleGrouped(inSeries: seriesID, now: now)
    XCTAssertEqual(groups.map(\.phase), [.deposit, .balance, .ended])
    XCTAssertEqual(groups[0].listings.map(\.id), [deposit.id])
    XCTAssertEqual(groups[1].listings.map(\.id), [balance.id])
    XCTAssertEqual(groups[2].listings.map(\.id), [ended.id])
  }

  /// 详情页 item id 反查：只有带 `midsummer-listing-` 前缀的 id 能查到。
  func testListingForItemIDRequiresPrefix() {
    let listing = makeDepositListing()
    let store = MidsummerListingStore(directory: temporaryDirectory())
    store.upsert(listing)
    XCTAssertNotNil(store.listing(forItemID: MidsummerListingItemIDPrefix + listing.id))
    XCTAssertNil(store.listing(forItemID: listing.id), "裸 listing id 不该命中")
    XCTAssertNil(store.listing(forItemID: "seed-item"), "种子商品不在上架记录里")
  }

  // MARK: 详情页预售结束双价（业务规则 4）

  /// 预售结束：预约价与现货价同时展示，预约价在前；缺哪类少哪行。
  func testDetailPriceRowsShowBothAfterPresaleEnded() {
    let ended = makeItem(price: 329, preorderPrice: 399)
      .detailPriceRows(stage: .inStock, presaleEnded: true)
    // 预约价在前（预售成交口径），现货价在后（当前购买口径）。
    XCTAssertEqual(ended.map(\.label), ["预约价", "现货价"])
    XCTAssertEqual(ended[0].value, "¥399（全款预约）")
    XCTAssertEqual(ended[1].value, "¥329")

    // 缺现货价就少一行，不占位。
    let preorderOnly = makeItem(price: nil, preorderPrice: 399)
      .detailPriceRows(stage: .inStock, presaleEnded: true)
    XCTAssertEqual(preorderOnly.map(\.label), ["预约价"])
  }

  /// 不传 presaleEnded 时维持互斥口径（回归保护）。
  func testDefaultRowsKeepMutualExclusion() {
    let item = makeItem(price: 329, preorderPrice: 399)
    XCTAssertEqual(
      item.detailPriceRows(stage: .inStock).map(\.label), ["现货价"])
    XCTAssertEqual(
      item.detailPriceRows(stage: .deposit).map(\.label), ["预约价"])
  }

  // MARK: 工具

  private func makeItem(price: Int?, preorderPrice: Int?) -> MidsummerItemDTO {
    MidsummerItemDTO(
      id: "presale-detail-item",
      seriesID: seriesID,
      name: "预售验收 JSK",
      kind: .jsk,
      price: price,
      preorderPrice: preorderPrice,
      deposit: nil,
      balance: nil,
      priceKind: price == nil ? nil : .shop,
      priceCapturedOn: price == nil ? nil : "2026-09-17",
      priceNote: nil,
      sizes: ["S"],
      colors: [],
      coverImage: nil,
      itemURL: nil,
      sourceURL: "https://item.taobao.com/presale",
      note: nil,
      specGroups: nil,
      skus: nil
    )
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("presale-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
