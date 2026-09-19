import UIKit
import XCTest
@testable import ItemManager

// MARK: - 上新工作台（樱花小羊系列）单测
//
// 覆盖两块纯逻辑（界面全流程由 UI 测试 MidsummerListingFlowUITests 验收）：
//   1. `MidsummerListing.makeItemDTO` 的**继承规则**——这是「自动关联该系列的
//      风格与数据」的实现核心，继承错了会直接污染规格抽屉与一键入库；
//   2. `MidsummerListingStore` 的持久化与状态机（注入临时目录，不碰真实存档）。

@MainActor
final class MidsummerListingTests: XCTestCase {

  override func setUp() {
    super.setUp()
    // 写接口（upsert / 改状态 / 落图）2026-09-18 起统一按创作者角色校验。
    // 本文件验的是持久化与状态机，注入创作者角色让用例继续跑自己的逻辑；
    // 权限矩阵本身由 `CreatorAccessTests` 覆盖。
    CreatorAccess.setTestOverride(.creator)
  }

  override func tearDown() {
    CreatorAccess.setTestOverride(nil)
    super.tearDown()
  }

  // MARK: 测试夹具：模拟樱花小羊主条目的规格结构

  /// 与种子数据同构：款式组（含「现 」前缀全名）、尺码组（选项名带「码」）、
  /// 价格档位标注组、按款式的尺码表。
  private func makeSourceItem() -> MidsummerItemDTO {
    let styleGroup = MidsummerSpecGroup(
      id: "style", name: "颜色分类", role: .variant,
      options: [
        MidsummerSpecOption(id: "sk-pink", name: "现 sk 粉色", image: nil),
        MidsummerSpecOption(id: "sk-cyan", name: "现 sk 蓝绿色", image: nil),
        MidsummerSpecOption(id: "blouse-cream", name: "现 内搭 奶白色", image: nil),
        MidsummerSpecOption(id: "brooch", name: "现 胸针", image: nil),
      ]
    )
    let sizeGroup = MidsummerSpecGroup(
      id: "size", name: "尺码", role: .size,
      options: [
        MidsummerSpecOption(id: "s", name: "S码", image: nil),
        MidsummerSpecOption(id: "m", name: "M码", image: nil),
        MidsummerSpecOption(id: "f", name: "F码", image: nil),
      ]
    )
    let pricingGroup = MidsummerSpecGroup(
      id: "pricing", name: "价格档位", role: .other,
      options: [
        MidsummerSpecOption(id: "spot", name: "现货价", image: nil),
        MidsummerSpecOption(id: "preorder", name: "预约价", image: nil),
        MidsummerSpecOption(id: "deposit", name: "定金", image: nil),
        MidsummerSpecOption(id: "balance", name: "尾款", image: nil),
      ]
    )
    var item = MidsummerItemDTO(
      id: "midsummer-2026-sakura-lamb",
      seriesID: "midsummer-2026-sakura-lamb",
      name: "樱花小羊",
      kind: .jsk,
      price: nil,
      deposit: nil,
      balance: nil,
      priceKind: nil,
      priceCapturedOn: nil,
      priceNote: nil,
      sizes: ["S", "M", "F"],
      colors: ["粉色", "蓝绿色"],
      coverImage: "seed-cover.jpg",
      itemURL: "https://item.taobao.com/sakura",
      sourceURL: "https://item.taobao.com/sakura",
      note: nil,
      specGroups: [styleGroup, sizeGroup, pricingGroup],
      skus: nil
    )
    item.sizeChartImages = [
      .init(style: "SK", imageName: "midsummer-sizechart-sk"),
      .init(style: "内搭", imageName: "midsummer-sizechart-blouse"),
    ]
    return item
  }

  private func makeListing(_ mutate: (inout MidsummerListing) -> Void = { _ in }) -> MidsummerListing {
    var listing = MidsummerListing(
      id: "upload-test0001",
      seriesID: "midsummer-2026-sakura-lamb",
      name: "上新验收 开衫",
      kindRaw: MidsummerItemKind.blouse.rawValue,
      price: 199,
      preorderPrice: nil,
      deposit: nil,
      balance: nil,
      priceKindRaw: MidsummerPriceKind.shop.rawValue,
      note: "验收用",
      sourceURL: "",
      sizes: ["S", "M"],
      variantOptionNames: ["现 sk 粉色"],
      imageFiles: ["listing-a.jpg", "listing-b.jpg"],
      status: .listed,
      createdAt: Date(),
      updatedAt: Date(),
      listedAt: Date()
    )
    mutate(&listing)
    return listing
  }

  // MARK: DTO 转换 · 继承规则

  /// 款式组只保留关联的选项；尺码组「S」↔「S码」容错匹配；价格档位组原样继承。
  func testMakeItemDTOInheritsFilteredGroups() {
    let dto = makeListing().makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")

    let groups = dto.specGroups ?? []
    XCTAssertEqual(groups.map(\.id), ["style", "size", "pricing"], "组顺序应为 款式 → 尺码 → 价格档位")

    let styleGroup = groups[0]
    XCTAssertEqual(styleGroup.options.map(\.name), ["现 sk 粉色"], "款式组只应保留关联的款式（全名，不含「现 」剥离）")

    let sizeGroup = groups[1]
    XCTAssertEqual(Set(sizeGroup.options.map(\.name)), ["S码", "M码"], "「S / M」应匹配到系列的「S码 / M码」")
    XCTAssertFalse(sizeGroup.options.map(\.name).contains("F码"), "未勾选的尺码不应出现")

    XCTAssertEqual(groups[2].id, "pricing", "价格档位标注组应原样继承")
  }

  /// 规格抽屉可用性：转换出来的 DTO 应能默认选全（上架商品可直接一键入库）。
  func testConvertedDTOCompletesDefaultSelection() {
    let dto = makeListing().makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    let selection = MidsummerSpecResolver.defaultSelection(of: dto)
    XCTAssertTrue(
      MidsummerSpecResolver.isComplete(selection, of: dto),
      "转换后的 DTO 默认选择应当完整（无需使用者补选即可入库）"
    )
    XCTAssertEqual(MidsummerSpecResolver.price(for: selection, of: dto), 199, "默认选择应命中单品现货价")
  }

  /// 出处回退：表单留空时必须落到系列出处（Apple 5.2 合规兜底）。
  func testSourceURLFallsBackToSeries() {
    let dto = makeListing().makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    XCTAssertEqual(dto.sourceURL, "https://series.example")

    let withOwn = makeListing { $0.sourceURL = "https://own.example" }
      .makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    XCTAssertEqual(withOwn.sourceURL, "https://own.example")
  }

  /// 款式对应图与尺码表继承：图按顺序映射到关联款式；尺码表按款式名（大小写不敏感）过滤。
  func testVariantImagesAndSizeChartsInherited() {
    let dto = makeListing().makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")

    XCTAssertEqual(dto.variantImageNames?["现 sk 粉色"], "listing-a.jpg", "关联款式应映射到第 1 张图（主图）")
    XCTAssertEqual(dto.coverImage, "listing-a.jpg", "第 1 张图应成为主图")
    XCTAssertEqual(dto.galleryImageNames, ["listing-b.jpg"], "其余图进附图宫格")

    let charts = dto.sizeChartImages ?? []
    XCTAssertEqual(charts.map(\.imageName), ["midsummer-sizechart-sk"], "「现 sk 粉色」应继承 SK 的尺码表（大小写不敏感）")
  }

  /// 多款关联：图不够时循环复用；尺码表逐款继承。
  func testMultipleVariants() {
    let listing = makeListing {
      $0.variantOptionNames = ["现 sk 粉色", "现 胸针"]
      $0.imageFiles = ["listing-a.jpg"]
      $0.sizes = []
    }
    let dto = listing.makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")

    XCTAssertEqual(dto.variantImageNames?["现 胸针"], "listing-a.jpg", "只有一张图时循环复用，每款都有图")
    let styleGroup = (dto.specGroups ?? []).first { $0.resolvedRole == .variant }
    XCTAssertEqual(styleGroup?.options.count, 2, "两个关联款式都应进入款式组")
    // 小物不选尺码 → 不带尺码组
    XCTAssertFalse(
      (dto.specGroups ?? []).contains { $0.resolvedRole == .size },
      "未勾选尺码时不应出现尺码组（无尺码小物场景）"
    )
  }

  /// 价格缺省：不虚构「价格待补充」之外的数字，preorder / deposit / balance 独立成档。
  func testPriceTiersPassThrough() {
    let listing = makeListing {
      $0.price = nil
      $0.preorderPrice = 259
    }
    let dto = listing.makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    XCTAssertNil(dto.price)
    XCTAssertEqual(dto.preorderPrice, 259)
    XCTAssertEqual(dto.priceText, "预约价 ¥259")
    XCTAssertNil(dto.priceKind, "没填现货价就不该带口径")
  }

  // MARK: DTO 转换 · 款式（2026-09-17 新增，衣橱联动口径）

  /// 自定义款式（系列资料里没有的「蓝色 OP」）也要进款式组，
  /// 否则衣橱 / 规格抽屉 / 筛选都认不到它。
  func testCustomStylesEnterVariantGroup() {
    let listing = makeListing {
      $0.styles = [
        MidsummerListingStyle(name: "蓝色 OP", imageFile: "style-blue.jpg", price: 219),
        MidsummerListingStyle(name: "绿色 OP", imageFile: nil, price: nil),
      ]
      $0.variantOptionNames = ["蓝色 OP", "绿色 OP"]
    }
    let dto = listing.makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")

    let styleGroup = (dto.specGroups ?? []).first { $0.resolvedRole == .variant }
    XCTAssertEqual(
      styleGroup?.options.map(\.name), ["蓝色 OP", "绿色 OP"],
      "自定义款式应作为款式组选项进入渲染链（衣橱按它归类）")
    XCTAssertEqual(dto.variantImageNames?["蓝色 OP"], "style-blue.jpg", "款式图应随款式名落到 variantImageNames")
    XCTAssertEqual(dto.variantImageNames?["绿色 OP"], "listing-b.jpg", "没传款式图时按商品图顺序对位（每款都有图）")
  }

  /// 逐款价 → SKU 表：选中该款式时解析出该款价格，未填的款式回退单品价。
  func testStylePriceBecomesSKUPrice() {
    let listing = makeListing {
      $0.styles = [
        MidsummerListingStyle(name: "蓝色 OP", imageFile: "style-blue.jpg", price: 219),
        MidsummerListingStyle(name: "绿色 OP", imageFile: "style-green.jpg", price: nil),
      ]
      $0.variantOptionNames = ["蓝色 OP", "绿色 OP"]
      $0.price = 199
    }
    let dto = listing.makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    let styleGroup = (dto.specGroups ?? []).first { $0.resolvedRole == .variant }!
    let blue = styleGroup.options.first { $0.name == "蓝色 OP" }!
    let green = styleGroup.options.first { $0.name == "绿色 OP" }!

    // 只写了一条 SKU（蓝色有价）；绿色没有逐款价 → 回退单品价。
    XCTAssertEqual(dto.skus?.count, 1, "只有填了价格的款式才落 SKU 逐款价")
    var bluePick = MidsummerSpecSelection()
    bluePick[styleGroup.id] = blue.id
    var greenPick = MidsummerSpecSelection()
    greenPick[styleGroup.id] = green.id
    XCTAssertEqual(MidsummerSpecResolver.price(for: bluePick, of: dto), 219, "选「蓝色 OP」应命中该款逐款价")
    XCTAssertEqual(MidsummerSpecResolver.price(for: greenPick, of: dto), 199, "未填逐款价的款式回退单品价")

    // 选了不存在的组合也不该崩（SKU 只约束款式组）。
    XCTAssertTrue(
      MidsummerSpecResolver.isComplete(greenPick, of: dto),
      "款式组选到未落 SKU 的选项时仍应可入库")
  }

  /// 旧存档（只有 variantOptionNames、styles 为 nil）不能回归：退化成「只有名字」。
  func testLegacyListingWithoutStylesStillWorks() {
    let listing = makeListing { $0.styles = nil }
    let dto = listing.makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    let styleGroup = (dto.specGroups ?? []).first { $0.resolvedRole == .variant }
    XCTAssertEqual(styleGroup?.options.map(\.name), ["现 sk 粉色"], "旧存档按 variantOptionNames 走原口径")
    XCTAssertNil(dto.skus, "旧存档没有逐款价，不生成 SKU")
  }

  // MARK: DTO 转换 · 自建系列（2026-09-19 根因修复）

  /// 自建系列（无基础条目，sourceItem == nil）上新：填了尺码就必须有尺码组，
  /// 填了款式名（颜色揉在款式名里）就必须解析出配色——
  /// 之前尺码组整段丢失，用户侧规格面板没有尺码栏位、入库按单品落。
  func testSelfBuiltSeriesGetsSizeGroupAndColors() {
    let listing = makeListing {
      $0.styles = [
        MidsummerListingStyle(name: "sk 粉色", price: 259, sizes: ["S", "M"]),
        MidsummerListingStyle(name: "sk 蓝色", price: 259, sizes: ["M"]),
      ]
      $0.variantOptionNames = ["sk 粉色", "sk 蓝色"]
      $0.sizes = ["S", "M"]
      $0.price = nil
      $0.preorderPrice = 259
    }
    // 自建系列没有基础条目可继承。
    let dto = listing.makeItemDTO(sourceItem: nil, seriesSourceURL: "")

    let sizeGroup = (dto.specGroups ?? []).first { $0.resolvedRole == .size }
    XCTAssertNotNil(sizeGroup, "系列没有尺码组时应按填写的尺码自建，而不是整组丢弃")
    XCTAssertEqual(sizeGroup?.options.map(\.name), ["S", "M"], "自建尺码组应包含填写的全部尺码")

    let styleGroup = (dto.specGroups ?? []).first { $0.resolvedRole == .variant }
    XCTAssertEqual(styleGroup?.options.map(\.name), ["sk 粉色", "sk 蓝色"])

    XCTAssertEqual(dto.colors, ["粉色", "蓝色"], "颜色应从款式名解析出去重（用户侧「配色」栏位的来源）")

    // 规格面板默认选择应能选全（有款式 + 尺码两组可选）。
    let selection = MidsummerSpecResolver.defaultSelection(of: dto)
    XCTAssertTrue(MidsummerSpecResolver.isComplete(selection, of: dto))

    // 逐款尺码约束：SKU 按「款式 × 尺码」逐组合落。
    XCTAssertEqual(dto.skus?.count, 3, "sk 粉色(S,M) + sk 蓝色(M) 共 3 条 SKU")
  }

  /// 自建系列没填尺码（小物 / 均码）：不出现空尺码组。
  func testSelfBuiltSeriesWithoutSizesHasNoSizeGroup() {
    let listing = makeListing {
      $0.styles = [MidsummerListingStyle(name: "胸针", price: 59, sizes: [])]
      $0.variantOptionNames = ["胸针"]
      $0.sizes = []
    }
    let dto = listing.makeItemDTO(sourceItem: nil, seriesSourceURL: "")
    XCTAssertFalse(
      (dto.specGroups ?? []).contains { $0.resolvedRole == .size },
      "没填尺码时不应出现空尺码组")
  }

  // MARK: 价格档位标注组自建（2026-09-19 根因修复）

  /// 没有可继承的档位组时（自建系列 / 系列单品没整理过档位），按本商品实际
  /// 配置的价格档位自建「价格档位」标注组——否则用户侧规格面板与入库备注
  /// 都缺「价格档位」栏位，与尺码组丢失是同一条根因。
  func testSelfBuiltPricingGroupForDepositStageListing() {
    let listing = makeListing {
      $0.price = nil
      $0.preorderPrice = nil
      $0.deposit = 50
      $0.balance = 209
    }
    // 自建系列：无基础条目可继承 pricing 组。
    let dto = listing.makeItemDTO(sourceItem: nil, seriesSourceURL: "")

    let pricingGroup = (dto.specGroups ?? []).first { $0.id == "pricing" }
    XCTAssertNotNil(pricingGroup, "填了定金/尾款就必须有价格档位标注组，不能依赖继承")
    XCTAssertEqual(pricingGroup?.name, "价格档位")
    XCTAssertEqual(pricingGroup?.options.map(\.name), ["定金", "尾款"], "只保留实际填了的档位")

    // 默认选择落在第一个已填档位（定金），且入库备注的「已选规格」带上档位。
    let selection = MidsummerSpecResolver.defaultSelection(of: dto)
    let mapping = MidsummerSpecResolver.wardrobeMapping(selection, of: dto)
    XCTAssertTrue(
      mapping.specText?.contains("定金") ?? false,
      "入库备注的已选规格应包含价格档位标注")
  }

  /// 现货商品：自建档位组只含「现货价」；一个价格都没填就不造空组。
  func testSelfBuiltPricingGroupInStockAndEmpty() {
    let inStock = makeListing {
      $0.price = 199
      $0.preorderPrice = nil
      $0.deposit = nil
      $0.balance = nil
    }
    let inStockDTO = inStock.makeItemDTO(sourceItem: nil, seriesSourceURL: "")
    XCTAssertEqual(
      (inStockDTO.specGroups ?? []).first { $0.id == "pricing" }?.options.map(\.name),
      ["现货价"],
      "现货商品自建档位组只含现货价")

    let noPrice = makeListing {
      $0.price = nil
      $0.preorderPrice = nil
      $0.deposit = nil
      $0.balance = nil
    }
    let noPriceDTO = noPrice.makeItemDTO(sourceItem: nil, seriesSourceURL: "")
    XCTAssertNil(
      (noPriceDTO.specGroups ?? []).first { $0.id == "pricing" },
      "一个价格都没填时不造空档位组")
  }

  /// 有基础条目可继承时走原口径：档位组原样继承（含全部四个选项），不受自建逻辑影响。
  func testInheritedPricingGroupStillWinsOverSelfBuilt() {
    let listing = makeListing {
      $0.price = nil
      $0.deposit = 50
      $0.balance = 209
    }
    let dto = listing.makeItemDTO(sourceItem: makeSourceItem(), seriesSourceURL: "https://series.example")
    let pricingGroup = (dto.specGroups ?? []).first { $0.id == "pricing" }
    XCTAssertEqual(
      pricingGroup?.options.map(\.name),
      ["现货价", "预约价", "定金", "尾款"],
      "系列自带档位组时原样继承，保持既有口径")
  }

  /// 云端往返（2026-09-19 根因修复）：specGroups / skus 序列化成 JSON 字符串后
  /// 必须能无损还原——否则创作者投稿、改价整条重写、跨设备同步后商品退化成
  /// 「无规格单品」，用户看不到颜色分类 / 尺码栏位。
  func testSpecGroupsCloudJSONRoundTrip() throws {
    let source = makeSourceItem()
    let skus = [
      MidsummerSKU(id: "sku-1", options: ["style": "sk-pink", "size": "s"], image: nil, price: 219, priceKind: .shop)
    ]

    let groupsJSON = MidsummerCloudService.specGroupsJSON(source.specGroups)
    XCTAssertNotNil(groupsJSON, "非空规格组应序列化成功")
    let decodedGroups = MidsummerCloudService.decodeSpecGroups(from: groupsJSON)
    XCTAssertEqual(decodedGroups, source.specGroups, "规格组 JSON 往返应无损")

    let skusJSON = MidsummerCloudService.skusJSON(skus)
    XCTAssertEqual(MidsummerCloudService.decodeSkus(from: skusJSON), skus, "SKU 表 JSON 往返应无损")

    // 边界：nil / 空 / 脏数据都安全落 nil，与「无规格」同口径。
    XCTAssertNil(MidsummerCloudService.specGroupsJSON(nil))
    XCTAssertNil(MidsummerCloudService.specGroupsJSON([]))
    XCTAssertNil(MidsummerCloudService.skusJSON(nil))
    XCTAssertNil(MidsummerCloudService.decodeSpecGroups(from: nil))
    XCTAssertNil(MidsummerCloudService.decodeSpecGroups(from: "not-json"))
    XCTAssertNil(MidsummerCloudService.decodeSkus(from: "not-json"))
  }

  // MARK: 存储与状态机

  private func makeTempStore() -> MidsummerListingStore {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("listing-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return MidsummerListingStore(directory: directory)
  }

  func testStorePersistsAndRestores() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("listing-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let store = MidsummerListingStore(directory: directory)
    try! store.upsert(makeListing())
    XCTAssertEqual(store.listings.count, 1)

    // 新实例从磁盘恢复（进程重启等价）。
    let reloaded = MidsummerListingStore(directory: directory)
    XCTAssertEqual(reloaded.listings.count, 1)
    XCTAssertEqual(reloaded.listings.first?.name, "上新验收 开衫")
    XCTAssertEqual(reloaded.listedListings.count, 1, "已上架 listing 恢复后仍在 feed 合并范围")
  }

  func testStatusTransitions() {
    let store = makeTempStore()
    let listing = makeListing { $0.status = .draft }
    try! store.upsert(listing)
    let id = listing.id

    try! store.updateStatus(of: id, to: .listed)
    XCTAssertEqual(store.listing(withID: id)?.status, .listed)
    XCTAssertNotNil(store.listing(withID: id)?.listedAt)

    try! store.updateStatus(of: id, to: .delisted)
    XCTAssertEqual(store.listing(withID: id)?.status, .delisted)
    XCTAssertNil(store.listing(withID: id)?.listedAt)
    XCTAssertTrue(store.listedListings.isEmpty, "已下架商品不进 feed")
  }

  func testUpsertUpdatesInPlace() {
    let store = makeTempStore()
    var listing = makeListing()
    try! store.upsert(listing)
    listing.name = "改名后的开衫"
    try! store.upsert(listing)

    XCTAssertEqual(store.listings.count, 1, "同 id upsert 应原地更新而不是追加")
    XCTAssertEqual(store.listing(withID: listing.id)?.name, "改名后的开衫")
  }

  func testDeleteRemovesRecordAndImages() {
    let store = makeTempStore()
    var listing = makeListing()
    let savedNames = try! store.saveImages([makeSolidImage()], listingID: listing.id)
    XCTAssertFalse(savedNames.isEmpty, "图片应落盘成功")
    listing.imageFiles = savedNames
    try! store.upsert(listing)

    try! store.delete(listing.id)
    XCTAssertTrue(store.listings.isEmpty)

    for name in savedNames {
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: ImageManager.shared.imagesDirectory.appendingPathComponent(name).path),
        "删除 listing 应连同它的商品图一起清掉"
      )
    }
  }

  /// 同一 listing 重复保存图片：旧图清理（替换语义），不留孤儿文件。
  /// 文件名按槽位下标确定性命名，所以用「2 张 → 1 张」验证被裁撤的旧槽位真的删了。
  func testSaveImagesReplacesPreviousFiles() {
    let store = makeTempStore()
    let listingID = "upload-replace-test"
    let first = try! store.saveImages([makeSolidImage(), makeSolidImage()], listingID: listingID)
    let second = try! store.saveImages([makeSolidImage()], listingID: listingID)

    XCTAssertEqual(first.count, 2)
    XCTAssertEqual(second.count, 1)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: ImageManager.shared.imagesDirectory.appendingPathComponent(first[1]).path),
      "重复保存后被裁撤的旧槽位（第 2 张）应被清理"
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: ImageManager.shared.imagesDirectory.appendingPathComponent(second[0]).path),
      "新主图应正常落盘"
    )
    store.deleteImageFiles(of: MidsummerListing(
      id: listingID, seriesID: "", name: "", kindRaw: "op", price: nil, preorderPrice: nil,
      deposit: nil, balance: nil, priceKindRaw: nil, note: "", sourceURL: "", sizes: [],
      variantOptionNames: [], imageFiles: second, status: .draft,
      createdAt: Date(), updatedAt: Date(), listedAt: nil))
  }

  // MARK: 系列级上新信息（2026-09-16 改版新增字段）

  /// 新字段（阶段 / 系列标题 / 上新日期 / 定金区间）编解码往返不丢。
  func testLaunchFieldsRoundtrip() throws {
    var listing = makeListing()
    let date = Date(timeIntervalSince1970: 1_789_000_000)
    listing.stage = .deposit
    listing.launchTitle = "小熊博物馆系列"
    listing.hasKnownLaunchDate = true
    listing.launchDate = date
    listing.depositMin = 30
    listing.depositMax = 80

    let data = try JSONEncoder().encode(listing)
    let decoded = try JSONDecoder().decode(MidsummerListing.self, from: data)

    XCTAssertEqual(decoded.stage, .deposit)
    XCTAssertEqual(decoded.launchTitle, "小熊博物馆系列")
    XCTAssertEqual(decoded.hasKnownLaunchDate, true)
    XCTAssertEqual(decoded.launchDate, date)
    XCTAssertEqual(decoded.depositMin, 30)
    XCTAssertEqual(decoded.depositMax, 80)
  }

  /// 旧存档 JSON（没有新字段键）解码不炸：新字段全部落 nil（向后兼容）。
  func testLegacyJSONDecodesWithNilLaunchFields() throws {
    let legacy = """
      {"id":"upload-legacy01","seriesID":"midsummer-2026-sakura-lamb","name":"旧存档",
       "kindRaw":"op","price":199,"preorderPrice":null,"deposit":null,"balance":null,
       "priceKindRaw":"shop","note":"","sourceURL":"","sizes":["S"],
       "variantOptionNames":["现 sk 粉色"],"imageFiles":[],"status":"listed",
       "createdAt":600000000.0,"updatedAt":600000000.0,"listedAt":600000000.0}
      """
    let decoded = try JSONDecoder().decode(MidsummerListing.self, from: Data(legacy.utf8))

    XCTAssertEqual(decoded.name, "旧存档")
    XCTAssertNil(decoded.stage)
    XCTAssertNil(decoded.launchTitle)
    XCTAssertNil(decoded.hasKnownLaunchDate)
    XCTAssertNil(decoded.launchDate)
    XCTAssertNil(decoded.depositMin)
    XCTAssertNil(decoded.depositMax)
  }

  /// 阶段收敛（2026-09-19）：可选阶段只有 预约价/现货 两档；
  /// 预约价阶段下预约全款与定金+尾款拆分两种填法都开放（价格配置项联动）。
  func testStagePriceFieldsLinkage() {
    XCTAssertEqual(
      MidsummerLaunchStage.selectableCases, [.preorder, .inStock],
      "表单可选阶段应只有 预约价 / 现货 两档（定金+尾款并入预约价）")
    XCTAssertEqual(
      MidsummerLaunchStage.preorder.priceFields, [.preorder, .deposit, .balance],
      "预约价阶段：全款直填，或配定金、尾款自动核算")
    XCTAssertEqual(MidsummerLaunchStage.inStock.priceFields, [.shop], "现货阶段显示现货价")
  }

  /// 预约价阶段 + 配了定金：沿用定金 → 尾款自动流转（2026-09-19 新口径）。
  func testPreorderStageWithDepositFlowsPresale() {
    let now = Date()
    var listing = MidsummerListing(
      id: "upload-preorder-flow",
      seriesID: "midsummer-2026-sakura-lamb",
      name: "预约价拆分填法验收",
      kindRaw: MidsummerItemKind.jsk.rawValue,
      price: nil,
      preorderPrice: 259,
      deposit: 50,
      balance: 209,
      priceKindRaw: nil,
      note: "",
      sourceURL: "",
      sizes: [],
      variantOptionNames: [],
      imageFiles: [],
      status: .listed,
      createdAt: Date(),
      updatedAt: Date(),
      listedAt: Date()
    )
    listing.stage = .preorder
    listing.depositEndsAt = now.addingTimeInterval(3_600)
    listing.balanceEndsAt = now.addingTimeInterval(86_400)
    XCTAssertEqual(listing.presalePhase(at: now), .deposit, "定金期未结束 → 定金期")

    listing.depositEndsAt = now.addingTimeInterval(-1)
    XCTAssertEqual(listing.presalePhase(at: now), .balance, "定金结束 → 尾款期")

    // 写入式流转同样覆盖新口径：到期后 stage 推进为 .balance。
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("listing-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = MidsummerListingStore(directory: directory)
    try! store.upsert(listing)
    XCTAssertEqual(store.refreshPresaleTransitions(now: now), 1)
    XCTAssertEqual(store.listing(withID: listing.id)?.stage, .balance)

    // 纯全款预约（没配定金）不参与状态机。
    listing.deposit = nil
    listing.balance = nil
    XCTAssertNil(listing.presalePhase(at: now), "纯全款预约不走定金尾款状态机")
  }

  /// 旧存档阶段 raw 降级映射：出货 → 现货、再贩 → 预约价、图透置空。
  func testLegacyStageRawMapping() {
    func decode(_ raw: String?) -> MidsummerLaunchStage? {
      var listing = makeListing()
      listing.stageRaw = raw
      return listing.stage
    }
    XCTAssertEqual(decode("shipping"), .inStock, "旧「出货」应降级为现货")
    XCTAssertEqual(decode("rerun"), .preorder, "旧「再贩」应降级为预约价")
    XCTAssertNil(decode("teaser"), "旧「图透」语义已不存在，应置空由创作者重选")
    XCTAssertNil(decode("未知raw"), "未知 raw 不应崩溃，返回 nil")
  }

  // MARK: 多选分类（2026-09-18，对照商品详情模板）

  /// kinds setter 同步主分类：kindRaws 存全量、kindRaw 存首个，旧代码读 kind 不失效。
  func testMultiKindSetterSyncsPrimaryKind() {
    var listing = makeListing()
    listing.kinds = [.skirt, .blouse, .accessory]
    XCTAssertEqual(listing.kinds, [.skirt, .blouse, .accessory], "多选分类应按写入顺序保留")
    XCTAssertEqual(listing.kind, .skirt, "首个分类应成为主分类")
    XCTAssertEqual(listing.kindRaw, MidsummerItemKind.skirt.rawValue, "kindRaw 同步主分类，旧代码口径不变")
    XCTAssertEqual(
      listing.kindRaws,
      [MidsummerItemKind.skirt.rawValue, MidsummerItemKind.blouse.rawValue, MidsummerItemKind.accessory.rawValue]
    )
  }

  /// 旧存档（kindRaws 为 nil）回退单一 kind，解码与展示都不炸。
  func testMultiKindLegacyFallback() {
    var listing = makeListing()
    XCTAssertNil(listing.kindRaws, "旧存档没有多选分类字段")
    XCTAssertEqual(listing.kinds, [listing.kind], "旧存档的 kinds 应回退为单一主分类")
  }

  /// kinds setter 去重：重复写入同一分类只保留一份。
  func testMultiKindDeduplicates() {
    var listing = makeListing()
    listing.kinds = [.skirt, .skirt, .blouse]
    XCTAssertEqual(listing.kinds, [.skirt, .blouse], "重复分类应去重")
  }

  /// kinds 里存在无效 raw 时跳过、全无效再回退单一 kind（不出现空数组）。
  func testMultiKindToleratesUnknownRaws() {
    var listing = makeListing()
    listing.kindRaws = ["不存在的分类", MidsummerItemKind.blouse.rawValue]
    XCTAssertEqual(listing.kinds, [.blouse], "无效 raw 应被跳过")

    listing.kindRaws = ["不存在的分类"]
    XCTAssertEqual(listing.kinds, [listing.kind], "全无效 raw 应回退单一主分类")
  }

  /// 批量款式名解析（纯函数）：换行 / 顿号 / 中英文逗号 / 分号分隔，去空、保空格。
  func testParseBatchStyleNames() {
    let parsed = MidsummerListingFormView.parseBatchStyleNames(
      "sk 粉色\nsk 蓝绿色、内搭 奶白色，定位花jsk 粉色, 无腰op 蓝绿色；段段jsk 粉色"
    )
    XCTAssertEqual(
      parsed,
      ["sk 粉色", "sk 蓝绿色", "内搭 奶白色", "定位花jsk 粉色", "无腰op 蓝绿色", "段段jsk 粉色"],
      "五种分隔符都应拆开，款式名内部空格保留，空白项丢弃")
    XCTAssertTrue(MidsummerListingFormView.parseBatchStyleNames("  \n 、，").isEmpty, "纯空白输入应解析为空")
  }

  // MARK: 工具

  private func makeSolidImage() -> UIImage {
    let size = CGSize(width: 40, height: 40)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      UIColor.systemPink.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }
}
