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
    store.upsert(makeListing())
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
    store.upsert(listing)
    let id = listing.id

    store.updateStatus(of: id, to: .listed)
    XCTAssertEqual(store.listing(withID: id)?.status, .listed)
    XCTAssertNotNil(store.listing(withID: id)?.listedAt)

    store.updateStatus(of: id, to: .delisted)
    XCTAssertEqual(store.listing(withID: id)?.status, .delisted)
    XCTAssertNil(store.listing(withID: id)?.listedAt)
    XCTAssertTrue(store.listedListings.isEmpty, "已下架商品不进 feed")
  }

  func testUpsertUpdatesInPlace() {
    let store = makeTempStore()
    var listing = makeListing()
    store.upsert(listing)
    listing.name = "改名后的开衫"
    store.upsert(listing)

    XCTAssertEqual(store.listings.count, 1, "同 id upsert 应原地更新而不是追加")
    XCTAssertEqual(store.listing(withID: listing.id)?.name, "改名后的开衫")
  }

  func testDeleteRemovesRecordAndImages() {
    let store = makeTempStore()
    var listing = makeListing()
    let savedNames = store.saveImages([makeSolidImage()], listingID: listing.id)
    XCTAssertFalse(savedNames.isEmpty, "图片应落盘成功")
    listing.imageFiles = savedNames
    store.upsert(listing)

    store.delete(listing.id)
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
    let first = store.saveImages([makeSolidImage(), makeSolidImage()], listingID: listingID)
    let second = store.saveImages([makeSolidImage()], listingID: listingID)

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

  /// 阶段 → 价格配置项联动：第 4 步按阶段显示对应价格项。
  func testStagePriceFieldsLinkage() {
    XCTAssertEqual(MidsummerLaunchStage.teaser.priceFields, [], "图透阶段无价格配置")
    XCTAssertEqual(MidsummerLaunchStage.deposit.priceFields, [.deposit, .balance], "定金阶段显示定金 + 尾款")
    XCTAssertEqual(MidsummerLaunchStage.balance.priceFields, [.balance], "尾款阶段只显示尾款")
    XCTAssertEqual(MidsummerLaunchStage.shipping.priceFields, [.shop], "出货阶段显示现货价")
    XCTAssertEqual(MidsummerLaunchStage.rerun.priceFields, [.shop, .preorder], "再贩阶段显示现货价 + 预约价")
    XCTAssertEqual(MidsummerLaunchStage.inStock.priceFields, [.shop], "现货阶段显示现货价")
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
