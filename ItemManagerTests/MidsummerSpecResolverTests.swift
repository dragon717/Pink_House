import SwiftData
import XCTest

@testable import ItemManager

/// 规格选择的纯逻辑测试。
///
/// 覆盖四种容易出错的状态迁移（对应 `MidsummerSpecResolver` 顶部的注释）：
///   1. 规格缺省
///   2. 有规格组但没有 SKU 表（无联动约束）
///   3. 多规格联动（某个选项与当前已选无法组成合法组合 → 灰掉）
///   4. 选中状态变化（改 A 组后 B 组的旧选择必须被清掉，不能留假选中）
///
/// 另外单独校验「不限数量、不校验库存」这条与淘宝的差异有没有落到草稿上。
@MainActor
final class MidsummerSpecResolverTests: XCTestCase {

  var container: ModelContainer!
  var context: ModelContext!

  override func setUpWithError() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    container = try ModelContainer(for: Schema([Clothing.self, Brand.self, Tag.self]), configurations: config)
    context = container.mainContext
  }

  override func tearDownWithError() throws {
    container = nil
    context = nil
  }

  // MARK: - 夹具

  private func option(_ id: String, _ name: String, image: String? = nil) -> MidsummerSpecOption {
    MidsummerSpecOption(id: id, name: name, image: image)
  }

  private func group(
    _ id: String,
    _ name: String,
    role: MidsummerSpecRole? = nil,
    _ options: [MidsummerSpecOption]
  ) -> MidsummerSpecGroup {
    MidsummerSpecGroup(id: id, name: name, role: role, options: options)
  }

  private var colorGroup: MidsummerSpecGroup {
    group("color", "颜色分类", role: .color, [
      option("sk-pink", "Sk粉色", image: "spec_sk_pink"),
      option("sk-white", "Sk白色", image: "spec_sk_white"),
    ])
  }

  private var sizeGroup: MidsummerSpecGroup {
    group("size", "尺码", role: .size, [
      option("s", "S"), option("m", "M"), option("l", "L"),
    ])
  }

  private func sku(_ id: String, _ picks: [String: String], image: String? = nil, price: Int? = nil) -> MidsummerSKU {
    MidsummerSKU(id: id, options: picks, image: image, price: price)
  }

  private func makeItem(
    specGroups: [MidsummerSpecGroup]? = nil,
    skus: [MidsummerSKU]? = nil,
    colors: [String] = ["白色", "浅粉"],
    sizes: [String] = ["S", "M", "L", "XL"],
    price: Int? = 119,
    coverImage: String? = nil
  ) -> MidsummerItemDTO {
    MidsummerItemDTO(
      id: "item-1",
      seriesID: "series-1",
      name: "樱花小羊 SK",
      kind: .skirt,
      price: price,
      deposit: nil,
      balance: nil,
      priceKind: price == nil ? nil : .reference,
      priceCapturedOn: price == nil ? nil : "2026-09-15",
      priceNote: nil,
      sizes: sizes,
      colors: colors,
      coverImage: coverImage,
      itemURL: nil,
      sourceURL: "https://example.com",
      note: nil,
      specGroups: specGroups,
      skus: skus
    )
  }

  // MARK: - 1. 规格缺省

  func testNoSpecGroupsMeansNothingToChoose() {
    let item = makeItem()

    XCTAssertFalse(MidsummerSpecResolver.hasSpecs(item))
    XCTAssertTrue(MidsummerSpecResolver.groups(of: item).isEmpty)
    XCTAssertEqual(MidsummerSpecResolver.defaultSelection(of: item), .empty)

    // 没有规格也要「可入库」——这是规格缺省的关键：不能因为没得选就卡住流程
    XCTAssertTrue(MidsummerSpecResolver.isComplete(.empty, of: item))
    XCTAssertTrue(MidsummerSpecResolver.missingGroupNames(.empty, of: item).isEmpty)
    XCTAssertNil(MidsummerSpecResolver.summary(.empty, of: item))
    XCTAssertEqual(MidsummerSpecResolver.selectionSummaryText(.empty, of: item), "该单品暂无规格可选")

    // 图片回退到单品封面（这里也没有 → nil，由界面渲染占位）
    XCTAssertNil(MidsummerSpecResolver.image(for: .empty, of: item))
  }

  /// 只有空组的单品等同于「无规格」——空标题不该渲染出来。
  func testEmptyGroupIsTreatedAsNoSpecs() {
    let item = makeItem(specGroups: [group("color", "颜色分类", role: .color, [])])

    XCTAssertFalse(MidsummerSpecResolver.hasSpecs(item))
    XCTAssertTrue(MidsummerSpecResolver.isComplete(.empty, of: item))
  }

  // MARK: - 2. 有规格组、没有 SKU 表（无联动约束）

  func testSpecsWithoutSKUTableAllowEveryCombination() throws {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])

    XCTAssertTrue(MidsummerSpecResolver.hasSpecs(item))
    XCTAssertEqual(MidsummerSpecResolver.groups(of: item).count, 2)

    // 默认选每组第一项
    let selection = MidsummerSpecResolver.defaultSelection(of: item)
    XCTAssertEqual(selection["color"], "sk-pink")
    XCTAssertEqual(selection["size"], "s")
    XCTAssertTrue(MidsummerSpecResolver.isComplete(selection, of: item))

    // 任意组合都可用（没有组合表 → 没有约束）
    for color in ["sk-pink", "sk-white"] {
      for size in ["s", "m", "l"] {
        XCTAssertTrue(
          MidsummerSpecResolver.isAvailable(
            groupID: "size", optionID: size,
            given: MidsummerSpecSelection(picks: ["color": color]),
            of: item
          ),
          "无 SKU 表时 \(color)/\(size) 不该被灰掉"
        )
      }
    }
  }

  // MARK: - 3. 多规格联动

  /// 只有「粉色×M」「白色×L」两种组合存在。
  private func linkedItem() -> MidsummerItemDTO {
    makeItem(
      specGroups: [colorGroup, sizeGroup],
      skus: [
        sku("sku-pink-m", ["color": "sk-pink", "size": "m"]),
        sku("sku-white-l", ["color": "sk-white", "size": "l"]),
      ]
    )
  }

  func testLinkageGraysOutOptionsThatCannotCombine() {
    let item = linkedItem()

    // 选了粉色之后，尺码只应该有 M 可选
    let givenPink = MidsummerSpecSelection(picks: ["color": "sk-pink"])
    XCTAssertTrue(
      MidsummerSpecResolver.isAvailable(groupID: "size", optionID: "m", given: givenPink, of: item)
    )
    XCTAssertFalse(
      MidsummerSpecResolver.isAvailable(groupID: "size", optionID: "s", given: givenPink, of: item),
      "粉色没有 S/M 之外的组合，S 必须被灰掉"
    )
    XCTAssertFalse(
      MidsummerSpecResolver.isAvailable(groupID: "size", optionID: "l", given: givenPink, of: item)
    )

    // 反过来：选了 L 之后，颜色只应该有白色可选
    let givenL = MidsummerSpecSelection(picks: ["size": "l"])
    XCTAssertTrue(
      MidsummerSpecResolver.isAvailable(groupID: "color", optionID: "sk-white", given: givenL, of: item)
    )
    XCTAssertFalse(
      MidsummerSpecResolver.isAvailable(groupID: "color", optionID: "sk-pink", given: givenL, of: item)
    )
  }

  func testLinkageIgnoresGroupsTheSKUDoesNotMention() {
    // SKU 只约束颜色组，尺码组不参与 → 尺码不该被全判死
    let item = makeItem(
      specGroups: [colorGroup, sizeGroup, group("length", "裙长", role: .other, [option("short", "短款")])],
      skus: [sku("only-color", ["color": "sk-pink"])]
    )

    let given = MidsummerSpecSelection(picks: ["color": "sk-pink"])
    for size in ["s", "m", "l"] {
      XCTAssertTrue(
        MidsummerSpecResolver.isAvailable(groupID: "size", optionID: size, given: given, of: item),
        "SKU 没提到尺码组时，尺码不应被这条 SKU 约束"
      )
    }
    XCTAssertFalse(
      MidsummerSpecResolver.isAvailable(groupID: "color", optionID: "sk-white", given: given, of: item)
    )
  }

  func testDefaultSelectionPrefersFirstSKU() {
    let item = linkedItem()
    let selection = MidsummerSpecResolver.defaultSelection(of: item)

    XCTAssertEqual(selection["color"], "sk-pink")
    XCTAssertEqual(selection["size"], "m", "默认组合应当来自 SKU 表第一条，而不是每组第一项（S）")
    XCTAssertTrue(MidsummerSpecResolver.isComplete(selection, of: item))
  }

  // MARK: - 4. 选中状态变化

  func testChangingColorClearsSizeThatNoLongerCombines() {
    let item = linkedItem()

    // 先选「白色 + L」（合法）
    var selection = MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l"])
    XCTAssertTrue(MidsummerSpecResolver.isComplete(selection, of: item))

    // 改选粉色：白色×L 的组合不存在了，L 必须被清掉
    selection = MidsummerSpecResolver.selecting(
      groupID: "color", optionID: "sk-pink", in: selection, of: item
    )

    XCTAssertEqual(selection["color"], "sk-pink")
    XCTAssertNil(selection["size"], "改配色后失效的尺码必须清掉，不能留下假选中")
    XCTAssertFalse(MidsummerSpecResolver.isComplete(selection, of: item))
    XCTAssertEqual(MidsummerSpecResolver.missingGroupNames(selection, of: item), ["尺码"])
    XCTAssertEqual(
      MidsummerSpecResolver.selectionSummaryText(selection, of: item),
      "已选 Sk粉色 · 请选择 尺码",
      "只选了一部分时不能只报「已选 Sk粉色」，那会让人以为已经选好了"
    )

    // 再选 M（与粉色相容）→ 恢复完整
    selection = MidsummerSpecResolver.selecting(
      groupID: "size", optionID: "m", in: selection, of: item
    )
    XCTAssertTrue(MidsummerSpecResolver.isComplete(selection, of: item))
    XCTAssertEqual(MidsummerSpecResolver.summary(selection, of: item), "Sk粉色 / M")
  }

  func testNormalizeDropsUnknownOptionIDs() {
    let item = linkedItem()
    let dirty = MidsummerSpecSelection(picks: ["color": "已下架的旧配色", "size": "m"])
    let cleaned = MidsummerSpecResolver.normalized(dirty, of: item)

    XCTAssertNil(cleaned["color"], "选项 id 不存在时必须丢弃")
    XCTAssertEqual(cleaned["size"], "m")
  }

  func testSelectionWithNoSKUTableIsAlwaysComplete() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    let selection = MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l"])
    let normalized = MidsummerSpecResolver.normalized(selection, of: item)
    XCTAssertEqual(normalized["color"], "sk-white")
    XCTAssertEqual(normalized["size"], "l")
  }

  /// 一个都没选时，提示要把所有待选的组名都列出来。
  func testSummaryTextWhenNothingPicked() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    XCTAssertEqual(
      MidsummerSpecResolver.selectionSummaryText(.empty, of: item),
      "请选择：颜色分类、尺码"
    )
    XCTAssertEqual(
      MidsummerSpecResolver.selectionSummaryText(.empty, of: item),
      "请选择：颜色分类、尺码"
    )
  }

  /// 选全了才用「已选：」这种完成态口径。
  func testSummaryTextWhenFullyPicked() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    XCTAssertEqual(
      MidsummerSpecResolver.selectionSummaryText(
        MidsummerSpecSelection(picks: ["color": "sk-pink", "size": "s"]), of: item
      ),
      "已选：Sk粉色 / S"
    )
  }

  // MARK: - 图片回退链

  func testImageFallsBackFromSKUToOptionToItemCover() {
    // 1) SKU 组合图优先
    let withSKUImage = makeItem(
      specGroups: [colorGroup, sizeGroup],
      skus: [sku("combo", ["color": "sk-white", "size": "l"], image: "spec_white_l")],
      coverImage: "item_cover"
    )
    XCTAssertEqual(
      MidsummerSpecResolver.image(
        for: MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l"]), of: withSKUImage
      ),
      "spec_white_l",
      "命中 SKU 时应优先用组合图"
    )

    // 2) 没有 SKU 图 → 用已选选项自己的图
    let optionOnly = makeItem(specGroups: [colorGroup, sizeGroup], coverImage: "item_cover")
    XCTAssertEqual(
      MidsummerSpecResolver.image(
        for: MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l"]), of: optionOnly
      ),
      "spec_sk_white",
      "选项自带图时应当用它（Sk白色 显示 Sk白色 的图）"
    )

    // 3) 选项也没图 → 回退到单品封面
    let noOptionImage = makeItem(
      specGroups: [
        group("color", "颜色分类", role: .color, [option("a", "无图配色")]),
      ],
      coverImage: "item_cover"
    )
    XCTAssertEqual(
      MidsummerSpecResolver.image(for: MidsummerSpecSelection(picks: ["color": "a"]), of: noOptionImage),
      "item_cover"
    )

    // 4) 全都没有 → nil（界面渲染「无图」占位）
    let bare = makeItem(specGroups: [group("color", "颜色分类", role: .color, [option("a", "无图配色")])])
    XCTAssertNil(MidsummerSpecResolver.image(for: MidsummerSpecSelection(picks: ["color": "a"]), of: bare))
  }

  /// 空串等同于没填，不能当成一个真实图名去加载。
  func testEmptyImageStringIsTreatedAsMissing() {
    let item = makeItem(
      specGroups: [group("color", "颜色分类", role: .color, [option("a", "配色", image: "")])],
      coverImage: "item_cover"
    )
    XCTAssertEqual(
      MidsummerSpecResolver.image(for: MidsummerSpecSelection(picks: ["color": "a"]), of: item),
      "item_cover"
    )
  }

  // MARK: - 价格

  func testPricePrefersSKUPriceThenItemPrice() {
    let withSKUPrice = makeItem(
      specGroups: [colorGroup, sizeGroup],
      skus: [sku("cheap", ["color": "sk-white", "size": "l"], price: 99)],
      price: 119
    )
    XCTAssertEqual(
      MidsummerSpecResolver.price(for: MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l"]), of: withSKUPrice),
      99
    )
    // 没命中 SKU 的组合沿用单品价
    XCTAssertEqual(
      MidsummerSpecResolver.price(for: MidsummerSpecSelection(picks: ["color": "sk-pink", "size": "m"]), of: withSKUPrice),
      119
    )
    XCTAssertEqual(
      MidsummerSpecResolver.priceText(for: MidsummerSpecSelection(picks: ["color": "sk-pink", "size": "m"]), of: withSKUPrice),
      "¥119"
    )

    let noPrice = makeItem(specGroups: [colorGroup, sizeGroup], price: nil)
    XCTAssertNil(MidsummerSpecResolver.price(for: .empty, of: noPrice))
    XCTAssertEqual(MidsummerSpecResolver.priceText(for: .empty, of: noPrice), "价格待补充")
  }

  // MARK: - 角色推断

  func testRoleIsInferredFromGroupNameWhenMissing() {
    XCTAssertEqual(group("size", "尺码", role: nil, [option("m", "M")]).resolvedRole, .size)
    XCTAssertEqual(group("size", "Size", role: nil, [option("m", "M")]).resolvedRole, .size)
    XCTAssertEqual(group("color", "颜色分类", role: nil, [option("m", "M")]).resolvedRole, .color)
    XCTAssertEqual(group("color", "配色", role: nil, [option("m", "M")]).resolvedRole, .color)
    XCTAssertEqual(group("length", "裙长", role: nil, [option("m", "短款")]).resolvedRole, .other)
    // 显式声明的优先，即使名字里没有关键词
    XCTAssertEqual(group("g1", "款式", role: .color, [option("m", "M")]).resolvedRole, .color)
  }

  func testWardrobeMappingSeparatesColorSizeAndOther() {
    let item = makeItem(
      specGroups: [
        colorGroup,
        sizeGroup,
        group("length", "裙长", role: .other, [option("short", "短款"), option("long", "长款")]),
      ]
    )
    let mapping = MidsummerSpecResolver.wardrobeMapping(
      MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l", "length": "long"]),
      of: item
    )

    XCTAssertEqual(mapping.colors, "Sk白色", "颜色组 → 衣橱的配色字段")
    XCTAssertEqual(mapping.sizes, "L", "尺码组 → 衣橱的尺码字段")
    XCTAssertEqual(mapping.specText, "Sk白色 / L / 长款", "其它规格只进备注，不硬塞进配色")
  }

  func testWardrobeMappingFallsBackToItemLevelValues() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    let mapping = MidsummerSpecResolver.wardrobeMapping(.empty, of: item)

    XCTAssertEqual(mapping.colors, "白色, 浅粉")
    XCTAssertEqual(mapping.sizes, "S, M, L, XL")
    XCTAssertNil(mapping.specText)
  }

  // MARK: - 草稿：数量不限、不动库存

  func testDraftCarriesQuantityWithoutAnyStockCheck() throws {
    let series = MidsummerSeriesDTO(
      id: "series-1",
      name: "樱花小羊",
      year: 2026,
      launchedOn: "",
      stage: .inStock,
      coverImage: nil,
      depositMin: 7,
      depositMax: 139,
      priceSource: "榜单定金价带",
      sizes: ["S", "M", "L", "XL"],
      colors: ["白色", "浅粉"],
      summary: nil,
      sourceURL: "https://example.com",
      sourceKind: "public",
      verified: true,
      items: []
    )
    let item = makeItem(specGroups: [colorGroup, sizeGroup])

    // 一个远大于任何真实库存的数量，也必须原样写入——「不限入库数量」
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: item,
      series: series,
      brandName: "仲夏物语",
      selection: MidsummerSpecSelection(picks: ["color": "sk-pink", "size": "m"]),
      quantity: 999,
      modelContext: context
    )

    XCTAssertEqual(draft.stock, 999, "数量必须原样保留，不能因为没有库存数据被截断")
    XCTAssertEqual(draft.colors, "Sk粉色")
    XCTAssertEqual(draft.sizes, "M")
    XCTAssertTrue(draft.note.contains("已选规格：Sk粉色 / M"), "规格要写进备注，便于日后核对：\(draft.note)")
  }

  func testDraftClampsQuantityToAtLeastOne() throws {
    let series = MidsummerSeriesDTO(
      id: "series-1", name: "樱花小羊", year: 2026, launchedOn: "", stage: .inStock,
      coverImage: nil, depositMin: nil, depositMax: nil, priceSource: nil,
      sizes: [], colors: [], summary: nil,
      sourceURL: "https://example.com", sourceKind: "public", verified: true, items: []
    )
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: makeItem(), series: series, brandName: "仲夏物语",
      selection: .empty, quantity: 0, modelContext: context
    )
    XCTAssertEqual(draft.stock, 1, "数量下限为 1")
  }

  // MARK: - 5. 点已选项 = 取消选中

  /// 使用者的明确规则：选中印花后再点一次同一项应**取消**选中。
  func testTogglingThePickedOptionClearsIt() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    var selection = MidsummerSpecResolver.defaultSelection(of: item)
    XCTAssertEqual(selection["color"], "sk-pink")

    selection = MidsummerSpecResolver.toggling(
      groupID: "color", optionID: "sk-pink", in: selection, of: item)
    XCTAssertNil(selection["color"], "再点一次已选项必须取消选中")
    XCTAssertEqual(selection["size"], "s", "取消一个组不该牵连其它组已选")
  }

  func testTogglingAnUnpickedOptionSelectsIt() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    let selection = MidsummerSpecResolver.toggling(
      groupID: "color", optionID: "sk-white", in: .empty, of: item)
    XCTAssertEqual(selection["color"], "sk-white")
  }

  // MARK: - 8. 多选配一套：单品级选择构造

  /// 多选套装入库（用户 2026-09-16）：为每个勾选款式生成单品级选择——
  /// 尺码只对「存在带尺码 SKU 的款式」沿用（小物不带尺码），
  /// 价格档位这类标注组恒定沿用（对套装每件都成立的备注）。
  func testPerVariantSelectionDropsSizeForSizelessVariants() {
    let styleGroup = group("style", "颜色分类", role: .variant, [
      option("sk-pink", "sk 粉色"), option("accessory", "胸针"),
    ])
    let sizeGroup = group("size", "尺码", role: .size, [option("s", "S码"), option("m", "M码")])
    let pricing = group("pricing", "价格档位", role: .other, [
      option("spot", "现货价"), option("deposit", "定金"),
    ])
    let item = makeItem(
      specGroups: [styleGroup, sizeGroup, pricing],
      skus: [
        sku("sk-s", ["style": "sk-pink", "size": "s"], price: 449),
        // 胸针没有尺码：SKU 只约束款式
        sku("pin-only", ["style": "accessory"], price: 59),
      ],
      price: nil
    )
    let base = MidsummerSpecSelection(picks: [
      "style": "sk-pink", "size": "s", "pricing": "spot",
    ])

    // 裙装款：尺码 + 档位都带上，命中自己的 SKU 价
    let dress = MidsummerSpecResolver.perVariantSelection(for: "sk-pink", base: base, of: item)
    XCTAssertEqual(dress["style"], "sk-pink")
    XCTAssertEqual(dress["size"], "s")
    XCTAssertEqual(dress["pricing"], "spot")
    XCTAssertEqual(MidsummerSpecResolver.price(for: dress, of: item), 449)
    XCTAssertEqual(MidsummerSpecResolver.wardrobeMapping(dress, of: item).sizes, "S码")

    // 胸针款：不带尺码（SKU 表里它根本没有尺码），档位照带，命中自己的价
    let pin = MidsummerSpecResolver.perVariantSelection(for: "accessory", base: base, of: item)
    XCTAssertEqual(pin["style"], "accessory")
    XCTAssertNil(pin["size"], "无尺码款不得把基础选择里的尺码写进记录")
    XCTAssertEqual(pin["pricing"], "spot")
    XCTAssertEqual(MidsummerSpecResolver.price(for: pin, of: item), 59)
    XCTAssertEqual(MidsummerSpecResolver.wardrobeMapping(pin, of: item).sizes, "S, M, L, XL",
      "尺码缺省时回退单品自带尺码，与单件入库同规则")
  }

  // MARK: - 7. 标注组（价格档位）：SKU 未提及的组可选、不挡价格

  /// 「现货价 / 预约价 / 定金 / 尾款」不参与 SKU 组合（没有任何 SKU 提及）：
  /// 不选它不算缺失、不影响默认选择与价格命中；选中值只进规格备注。
  /// 用户 2026-09-16 加价格档位组时确立——否则点掉档位已选项，顶部会丢价格。
  func testAnnotationGroupIsOptionalAndDoesNotBlockPrice() {
    let pricingGroup = group("pricing", "价格档位", role: .other, [
      option("spot", "现货价"), option("preorder", "预约价"),
      option("deposit", "定金"), option("balance", "尾款"),
    ])
    let item = makeItem(
      specGroups: [colorGroup, pricingGroup, sizeGroup],
      skus: [
        sku("white-l", ["color": "sk-white", "size": "l"], price: 449),
        sku("pink-s", ["color": "sk-pink", "size": "s"], price: 449),
      ],
      price: nil
    )

    // 默认选择只含 SKU 提及的组，档位组不被强选
    let def = MidsummerSpecResolver.defaultSelection(of: item)
    XCTAssertEqual(def["color"], "sk-white")
    XCTAssertEqual(def["size"], "l")
    XCTAssertNil(def["pricing"], "SKU 未提及的标注组不该被默认选中")

    // 不选档位 = 完整状态，不进缺失提示
    XCTAssertTrue(MidsummerSpecResolver.isComplete(def, of: item))
    XCTAssertEqual(MidsummerSpecResolver.missingGroupNames(def, of: item), [])

    // 不选档位照样命中 SKU 价格（这是本次改动的根因回归）
    XCTAssertEqual(MidsummerSpecResolver.price(for: def, of: item), 449)

    // 选了档位：只进备注，不影响配色 / 尺码映射，也不影响价格
    var picks = def.picks
    picks["pricing"] = "spot"
    let selection = MidsummerSpecSelection(picks: picks)
    XCTAssertTrue(MidsummerSpecResolver.isComplete(selection, of: item))
    XCTAssertEqual(MidsummerSpecResolver.price(for: selection, of: item), 449)
    let mapping = MidsummerSpecResolver.wardrobeMapping(selection, of: item)
    XCTAssertEqual(mapping.colors, "Sk白色")
    XCTAssertEqual(mapping.sizes, "L")
    XCTAssertEqual(mapping.specText, "Sk白色 / 现货价 / L")

    // 档位组也能随时取消（点已选项 = 取消），取消后仍是完整状态
    let cancelled = MidsummerSpecResolver.toggling(
      groupID: "pricing", optionID: "spot", in: selection, of: item)
    XCTAssertNil(cancelled["pricing"])
    XCTAssertTrue(MidsummerSpecResolver.isComplete(cancelled, of: item))
    XCTAssertEqual(MidsummerSpecResolver.price(for: cancelled, of: item), 449)
  }

  /// 「允许不选中任何选项」：三组全清空之后仍然是合法状态，不能被悄悄补回来。
  func testEveryGroupCanBeLeftUnselected() {
    let item = makeItem(specGroups: [colorGroup, sizeGroup])
    var selection = MidsummerSpecResolver.defaultSelection(of: item)

    for (groupID, optionID) in [("color", "sk-pink"), ("size", "s")] {
      selection = MidsummerSpecResolver.toggling(
        groupID: groupID, optionID: optionID, in: selection, of: item)
    }

    XCTAssertEqual(selection, .empty, "全部取消后必须允许停在空选择上")
    XCTAssertFalse(MidsummerSpecResolver.isComplete(selection, of: item))
    XCTAssertEqual(
      MidsummerSpecResolver.missingGroupNames(selection, of: item), ["颜色分类", "尺码"])
    // 空选择下入库仍然成立：配色 / 尺码退回单品自带值
    let mapping = MidsummerSpecResolver.wardrobeMapping(selection, of: item)
    XCTAssertEqual(mapping.colors, "白色, 浅粉")
    XCTAssertEqual(mapping.sizes, "S, M, L, XL")
  }

  func testToggleIsIdempotentBackAndForth() {
    let item = makeItem(specGroups: [sizeGroup])
    let start = MidsummerSpecResolver.defaultSelection(of: item)
    let cleared = MidsummerSpecResolver.toggling(
      groupID: "size", optionID: "s", in: start, of: item)
    let restored = MidsummerSpecResolver.toggling(
      groupID: "size", optionID: "s", in: cleared, of: item)
    XCTAssertEqual(restored, start, "取消后再点回来应回到同一状态")
  }

  // MARK: - 6. 归集商品：小物这类「没有尺码」的款

  /// 归集商品里「小物」没有尺码，它的 SKU 只写款式 + 颜色。
  /// 匹配必须和 `isAvailable` 用同一条规则：SKU 没提及的组不参与匹配，
  /// 否则小物永远命中不了自己的 SKU，明明有价却显示「价格待补充」。
  func testSKUMatchingIgnoresGroupsTheSKUDidNotMention() {
    let styleGroup = group("style", "款式", role: .variant, [
      option("dress", "切替 JSK"), option("accessory", "小物"),
    ])
    let colors = group("color", "颜色分类", role: .color, [option("pink", "粉色")])
    let sizes = group("size", "尺码", role: .size, [option("s", "S"), option("m", "M")])

    let item = makeItem(
      specGroups: [styleGroup, colors, sizes],
      skus: [
        sku("dress-pink-s", ["style": "dress", "color": "pink", "size": "s"], price: 152),
        sku("dress-pink-m", ["style": "dress", "color": "pink", "size": "m"], price: 152),
        // 小物没有尺码：这条 SKU 只约束款式
        sku("accessory-only", ["style": "accessory"], price: 28),
      ],
      price: nil
    )

    let accessory = MidsummerSpecSelection(picks: [
      "style": "accessory", "color": "pink", "size": "m",
    ])
    XCTAssertEqual(
      MidsummerSpecResolver.price(for: accessory, of: item), 28,
      "小物必须命中自己那条 SKU，而不是退回「价格待补充」"
    )

    let dress = MidsummerSpecSelection(picks: [
      "style": "dress", "color": "pink", "size": "m",
    ])
    XCTAssertEqual(MidsummerSpecResolver.price(for: dress, of: item), 152)
  }

  /// 多选套装入库走 extraNoteLines 写套装标记；不传时备注与旧版逐字一致。
  func testMakeDraftAppendsExtraNoteLinesOnlyWhenProvided() throws {
    let series = MidsummerSeriesDTO(
      id: "series-1", name: "樱花小羊", year: 2026, launchedOn: "", stage: .inStock,
      coverImage: nil, depositMin: nil, depositMax: nil, priceSource: nil,
      sizes: [], colors: [], summary: nil,
      sourceURL: "https://example.com", sourceKind: "public", verified: true, items: []
    )
    let plain = MidsummerWardrobeDraftBuilder.makeDraft(
      for: makeItem(), series: series, brandName: "仲夏物语",
      selection: .empty, quantity: 1, modelContext: context
    )
    XCTAssertFalse(plain.note.contains("套装入库"), "普通入库不得出现套装标记")

    let setDraft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: makeItem(), series: series, brandName: "仲夏物语",
      selection: .empty, quantity: 1,
      extraNoteLines: ["套装入库：2026-09-16 18:00（2 件一套）", "套装成员：A、B"],
      modelContext: context
    )
    XCTAssertTrue(setDraft.note.contains("套装入库：2026-09-16 18:00（2 件一套）"))
    XCTAssertTrue(setDraft.note.hasSuffix("套装成员：A、B"), "套装行追加在备注末尾")
  }
}
