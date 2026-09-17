import XCTest
@testable import ItemManager

// MARK: - 详情页四类价格口径（用户 2026-09-17）
//
// 规则（见 MidsummerItemDTO.detailPriceRows(stage:) 注释）：
//   • 只保留 定金 / 尾款 / 现货价 / 预约价 四类
//   • 定金 + 尾款成对，缺哪类就少哪行（不占位）
//   • 预约价与现货价互斥，系列阶段决定优先级（预售线优先预约价）
//   • 参考价（reference）等不在四类之内的口径不渲染

final class MidsummerDetailPriceDisplayTests: XCTestCase {

  private func makeItem(
    price: Int? = nil,
    preorderPrice: Int? = nil,
    deposit: Int? = nil,
    balance: Int? = nil,
    priceKind: MidsummerPriceKind? = nil,
    skus: [MidsummerSKU]? = nil
  ) -> MidsummerItemDTO {
    MidsummerItemDTO(
      id: "price-test-item",
      seriesID: "price-test-series",
      name: "测试单品",
      kind: .jsk,
      price: price,
      preorderPrice: preorderPrice,
      deposit: deposit,
      balance: balance,
      priceKind: priceKind,
      priceCapturedOn: nil,
      priceNote: nil,
      sizes: [],
      colors: [],
      coverImage: nil,
      itemURL: nil,
      sourceURL: "",
      note: nil,
      specGroups: nil,
      skus: skus
    )
  }

  private func row(_ item: MidsummerItemDTO, stage: MidsummerStage) -> [MidsummerItemDTO.DetailPriceRow] {
    item.detailPriceRows(stage: stage)
  }

  // 定金 + 尾款成对展示
  func testDepositBalancePair() {
    let rows = row(makeItem(deposit: 100, balance: 399), stage: .deposit)
    XCTAssertEqual(rows.map(\.label), ["定金", "尾款"])
    XCTAssertEqual(rows[0].value, "¥100")
    XCTAssertEqual(rows[1].value, "¥399")
  }

  // 只有定金、缺尾款：只一行定金，没有占位文案
  func testDepositWithoutBalanceOmitsRow() {
    let rows = row(makeItem(deposit: 100), stage: .deposit)
    XCTAssertEqual(rows.map(\.label), ["定金"])
    XCTAssertFalse(rows.map(\.value).contains("待补充"))
  }

  // 预售阶段：预约价优先，现货价被互斥掉
  func testPresalePreorderBeatsSpot() {
    let rows = row(makeItem(price: 329, preorderPrice: 299, priceKind: .shop), stage: .deposit)
    XCTAssertEqual(rows.map(\.label), ["预约价"])
    XCTAssertTrue(rows[0].value.contains("¥299"))
  }

  // 现货阶段：现货价优先，预约价被互斥掉
  func testInStockSpotBeatsPreorder() {
    let rows = row(makeItem(price: 329, preorderPrice: 299, priceKind: .shop), stage: .inStock)
    XCTAssertEqual(rows.map(\.label), ["现货价"])
    XCTAssertEqual(rows[0].value, "¥329")
  }

  // 优先类缺数据时退另一类（预售线无预约价但有现货价 → 展示现货价）
  func testPresaleFallsBackToSpotWhenNoPreorder() {
    let rows = row(makeItem(price: 329, priceKind: .shop), stage: .balance)
    XCTAssertEqual(rows.map(\.label), ["现货价"])
  }

  // 参考价不在四类之内：不渲染
  func testReferencePriceHidden() {
    let rows = row(makeItem(price: 329, priceKind: .reference), stage: .shipping)
    XCTAssertTrue(rows.isEmpty, "参考价不应出现在四类价格里")
  }

  // 归集商品：SKU 逐款价口径统一为尾款 → 区间整体按尾款
  func testAggregateSKUBalanceRange() {
    let skus = [
      MidsummerSKU(id: "s1", options: [:], price: 160, priceKind: .balance),
      MidsummerSKU(id: "s2", options: [:], price: 400, priceKind: .balance),
    ]
    let rows = row(makeItem(skus: skus), stage: .deposit)
    XCTAssertEqual(rows.map(\.label), ["尾款"])
    XCTAssertEqual(rows[0].value, "¥160–400")
  }

  // 归集商品：SKU 逐款价口径统一为现货（shop）→ 现货价区间
  func testAggregateSKUShopRange() {
    let skus = [
      MidsummerSKU(id: "s1", options: [:], price: 199, priceKind: .shop),
      MidsummerSKU(id: "s2", options: [:], price: 699, priceKind: .shop),
    ]
    let rows = row(makeItem(skus: skus), stage: .inStock)
    XCTAssertEqual(rows.map(\.label), ["现货价"])
    XCTAssertEqual(rows[0].value, "¥199–699")
  }

  // SKU 口径混合（shop + balance）：无法归类，不硬选，返回空
  func testMixedSKUKindsNotClassified() {
    let skus = [
      MidsummerSKU(id: "s1", options: [:], price: 199, priceKind: .shop),
      MidsummerSKU(id: "s2", options: [:], price: 400, priceKind: .balance),
    ]
    XCTAssertTrue(row(makeItem(skus: skus), stage: .inStock).isEmpty)
  }

  // 四类全空：返回空（视图层显示「价格待补充」诚实态）
  func testNoPriceDataYieldsEmptyRows() {
    XCTAssertTrue(row(makeItem(), stage: .preview).isEmpty)
  }

  // 阶段判定：图透/定金/尾款属预售线
  func testPresaleStageClassification() {
    XCTAssertTrue(MidsummerItemDTO.isPresaleStage(.preview))
    XCTAssertTrue(MidsummerItemDTO.isPresaleStage(.deposit))
    XCTAssertTrue(MidsummerItemDTO.isPresaleStage(.balance))
    XCTAssertFalse(MidsummerItemDTO.isPresaleStage(.shipping))
    XCTAssertFalse(MidsummerItemDTO.isPresaleStage(.restock))
    XCTAssertFalse(MidsummerItemDTO.isPresaleStage(.inStock))
  }
}
