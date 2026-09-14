import XCTest

@testable import ItemManager

/// 创作者上传入口的验收测试。
///
/// 用户明确要求「必须额外提供一个供创作者自主上传上新信息的入口」，
/// 所以这个入口的**准入规则**必须被测试钉住，而不是只靠界面看起来对：
///   • 新建系列必须有名字
///   • 原文出处必须合法（Apple 5.2 可溯源）
///   • 必须至少一个单品（否则系列页展示不出图片/价格/尺码）
///
/// 注意：界面本体是 `NavigationStack { Form { … } }`，`Form` 底层是 UICollectionView，
/// `ImageRenderer` 无法栅格化它，所以这里只测逻辑、不测像素。
///
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，`DraftItem` 未标 `nonisolated`，
/// 因此涉及它的用例需要 `@MainActor`。`MidsummerContributionValidator` 已标 `nonisolated`。
final class MidsummerContributeViewTests: XCTestCase {

  private let okURL = "https://weibo.com/u/5902942009"

  // MARK: - 新建系列

  func testNewSeriesWithoutNameIsRejected() {
    let failure = MidsummerContributionValidator.validate(
      isSupplementMode: false,
      seriesName: "   ",
      sourceURLText: okURL,
      itemNames: ["草莓肥啾 JSK"]
    )
    XCTAssertEqual(failure, .missingSeriesName)
  }

  func testNewSeriesWithoutItemsIsRejected() {
    // 空系列在详情页只能渲染出一堆「待补充」，满足不了「每个系列含图片/价格/尺码」
    XCTAssertEqual(
      MidsummerContributionValidator.validate(
        isSupplementMode: false,
        seriesName: "只有名字的系列",
        sourceURLText: okURL,
        itemNames: []
      ),
      .noItems
    )

    // 全是空白的单品等于没有单品
    XCTAssertEqual(
      MidsummerContributionValidator.validate(
        isSupplementMode: false,
        seriesName: "只有名字的系列",
        sourceURLText: okURL,
        itemNames: ["   ", ""]
      ),
      .noItems
    )
  }

  func testValidNewSeriesPasses() {
    XCTAssertNil(
      MidsummerContributionValidator.validate(
        isSupplementMode: false,
        seriesName: "草莓肥啾",
        sourceURLText: okURL,
        itemNames: ["草莓肥啾 小高腰 JSK"]
      ))
  }

  // MARK: - 出处合规（Apple 5.2）

  func testSourceURLIsRequiredAndMustBeWebURL() {
    let cases: [(raw: String, why: String)] = [
      ("", "空出处"),
      ("   ", "只有空白"),
      ("lolitalibrary.com/library/detail/1621", "缺 scheme"),
      ("ftp://example.com/a", "非 http/https"),
      ("https://", "缺 host"),
      ("not a url", "根本不是 URL"),
    ]

    for (raw, why) in cases {
      XCTAssertEqual(
        MidsummerContributionValidator.validate(
          isSupplementMode: false,
          seriesName: "草莓肥啾",
          sourceURLText: raw,
          itemNames: ["草莓肥啾 JSK"]
        ),
        .invalidSourceURL,
        "\(why) 未被拦下"
      )
    }
  }

  func testValidationOrderReportsSeriesNameBeforeOtherIssues() {
    // 全空时应先报「缺系列名」——这是创作者最先要补的字段
    XCTAssertEqual(
      MidsummerContributionValidator.validate(
        isSupplementMode: false,
        seriesName: "",
        sourceURLText: "",
        itemNames: []
      ),
      .missingSeriesName
    )
  }

  // MARK: - 补录模式

  func testSupplementModeOnlyRequiresSourceURL() {
    // 补录已有系列时不重填系列名，也不强制再加单品（可能只是补价格/尺码）
    XCTAssertNil(
      MidsummerContributionValidator.validate(
        isSupplementMode: true,
        seriesName: "",
        sourceURLText: okURL,
        itemNames: []
      ))

    XCTAssertEqual(
      MidsummerContributionValidator.validate(
        isSupplementMode: true,
        seriesName: "",
        sourceURLText: "",
        itemNames: []
      ),
      .invalidSourceURL,
      "补录同样要求可溯源出处"
    )
  }

  // MARK: - 错误文案

  func testFailureMessagesAreNonEmptyAndActionable() {
    for failure in [
      MidsummerContributeFailure.missingSeriesName,
      .invalidSourceURL,
      .noItems,
    ] {
      XCTAssertFalse(failure.message.isEmpty)
    }
    XCTAssertTrue(MidsummerContributeFailure.invalidSourceURL.message.contains("http"))
    XCTAssertTrue(MidsummerContributeFailure.noItems.message.contains("单品"))
  }

  // MARK: - 单品草稿

  @MainActor
  func testDraftItemWithoutNameProducesNoItem() throws {
    var draft = DraftItem()
    XCTAssertNil(draft.makeItem(seriesID: "s", sizes: ["S"]), "没填款名不应造出一条空单品")

    draft.name = "  草莓肥啾 JSK  "
    let item = try XCTUnwrap(draft.makeItem(seriesID: "s", sizes: ["S", "M"]))
    XCTAssertEqual(item.name, "草莓肥啾 JSK", "款名应去掉首尾空白")
    XCTAssertEqual(item.seriesID, "s")
  }

  @MainActor
  func testDraftItemInheritsSeriesSizesWhenUnset() throws {
    let draft = DraftItem(inheritingSizesFrom: ["L", "S", "M"])
    XCTAssertEqual(draft.sizes, ["L", "M", "S"], "继承的尺码应排序稳定")

    var named = draft
    named.name = "樱花小羊 SK"
    let withOwnSizes = try XCTUnwrap(named.makeItem(seriesID: "s", sizes: ["XL"]))
    XCTAssertEqual(withOwnSizes.sizes, ["L", "M", "S"], "已设尺码优先于兜底尺码")

    var blank = DraftItem()
    blank.name = "小熊博物馆 JSK"
    let fallbackSizes = try XCTUnwrap(blank.makeItem(seriesID: "s", sizes: ["XL", "S"]))
    XCTAssertEqual(fallbackSizes.sizes, ["S", "XL"], "未设尺码时用系列尺码兜底")
  }

  @MainActor
  func testDraftItemKeepsPricesSeparateForDepositFlow() throws {
    var draft = DraftItem()
    draft.name = "小熊博物馆 切替 OP"
    draft.kind = .op
    draft.depositText = "47"
    draft.balanceText = "160"
    draft.priceText = ""

    let item = try XCTUnwrap(draft.makeItem(seriesID: "s", sizes: ["S"]))
    XCTAssertEqual(item.deposit, 47)
    XCTAssertEqual(item.balance, 160)
    XCTAssertNil(item.price)
    XCTAssertEqual(item.priceText, "定金 ¥47 · 尾款 ¥160")
  }
}
