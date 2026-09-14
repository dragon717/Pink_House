import SwiftUI
import XCTest

@testable import ItemManager

/// 渲染冒烟 + 快照导出。
///
/// 两个目的：
///   1. 断言品牌页能真的渲染出图像（布局崩溃、约束死循环、字体缺失会在这里暴露）
///   2. 把 PNG 写到 `NSTemporaryDirectory()/midsummer_snapshots/`，方便人工核对
///      参考图一/图二的版式是否走样
///
/// 这不是像素比对测试——参考图是电商截图，无法也不应做逐像素对比。
///
/// ⚠️ 关于 `ImageRenderer` 的三条硬限制（踩过坑，写在这里免得下次再试）：
///   (a) `UIImage.size` 的单位是**点**，不是像素。`renderer.scale = 2` 只放大 bitmap
///       （`image.cgImage?.width` 才翻倍），`size` 始终等于 frame 的 pt 值。
///   (b) `ScrollView` / `Form` / `List` 这类「只渲染可视区」的容器在 `ImageRenderer`
///       下拿不到真实内容，只能得到空框架。所以整页快照仅作冒烟，
///       真正能人工核对版式的是下面那些**非滚动容器**的区块快照。
///   (c) 被渲染的视图里若有 `.task { await … }` / `.onAppear { … }` 且会在渲染期写状态
///       （例如 `MidsummerContributeView` 的 `.onAppear(perform: prefill)`、
///       `MidsummerBrandView` 的 `.task { await store.refreshFromCloud() }`），会直接
///       触发 `SwiftUICore Fatal error: no current update to enqueue action to` 崩掉测试进程。
///       因此这两类页面**不要**整体丢进 `ImageRenderer`——只渲染无状态的区块组件。
///   (d) `renderer.isOpaque = true` 时，未被内容覆盖的区域会渲染成**黑色**。
///       渲染辅助里统一 `.frame(…, alignment: .top).background(Color.white)` 铺满画布，
///       否则快照会出现黑边、内容还会被垂直居中。
final class MidsummerBrandPageSnapshotTests: XCTestCase {

  // MARK: - 顶栏（含创作者上传入口的可见性闸门）

  /// 不渲染整页 `MidsummerBrandView`：它带 `.task { await store.refreshFromCloud() }`，
  /// 在 `ImageRenderer` 下没有活跃的更新周期，会触发
  /// `SwiftUICore/Logging.swift Fatal error: no current update to enqueue action to` 直接崩测试。
  /// 顶栏是非滚动容器，既能稳定出图，又能核对「上传上新」入口的 admin 闸门。
  @MainActor
  func testTopBarWithContributeEntryExportsSnapshot() throws {
    let view = MidsummerTopBar(
      title: "仲夏物语",
      subtitle: "Midsummer Tale · 2017 年创立",
      showsBack: false,
      canContribute: true,
      onBack: {},
      onClose: {},
      onContribute: {}
    )
    .background(Color.white)
    try render(view, name: "01-topbar-admin", size: CGSize(width: 393, height: 64))
  }

  /// 非 admin：同一个顶栏不应出现「上传上新」入口。
  @MainActor
  func testTopBarWithoutContributeEntryExportsSnapshot() throws {
    let view = MidsummerTopBar(
      title: "仲夏物语",
      subtitle: "Midsummer Tale · 2017 年创立",
      showsBack: false,
      canContribute: false,
      onBack: {},
      onClose: {},
      onContribute: {}
    )
    .background(Color.white)
    try render(view, name: "01b-topbar-guest", size: CGSize(width: 393, height: 64))
  }

  @MainActor
  func testSeriesListRendersAndExportsSnapshot() throws {
    let store = MidsummerStore(bundle: .main)
    try render(
      MidsummerSeriesListView(store: store, onSelectSeries: { _ in }),
      name: "02-series-list"
    )
  }

  @MainActor
  func testSeriesDetailRendersAndExportsSnapshot() throws {
    let store = MidsummerStore(bundle: .main)
    try render(
      MidsummerSeriesDetailView(store: store, seriesID: "midsummer-2022-peter-rabbit"),
      name: "03-series-detail"
    )
  }

  // MARK: - 可人工核对的区块快照（非滚动容器）
  //
  // ⚠️ 这里**没有**贡献表单（`MidsummerContributeView`）的快照，是有意的：
  // 它是 `NavigationStack { Form { … } }` —— `Form` 栅格化不出内容，
  // 而且它的 `.onAppear(perform: prefill)` 会在渲染期写 `@State`，
  // 直接触发 `SwiftUICore Fatal error: no current update to enqueue action to` 崩掉整个测试进程。
  // 上传入口的验收改由 `MidsummerContributeViewTests` 做逻辑断言（见该文件）。

  /// 单行卡片是最容易看出「像不像参考图」的粒度，单独导一张。
  @MainActor
  func testSeriesRowRendersAndExportsSnapshot() throws {
    let store = MidsummerStore(bundle: .main)
    let garden = try XCTUnwrap(store.series(withID: "midsummer-2025-bow-eternal-garden"))
    let strawberry = try XCTUnwrap(store.series(withID: "midsummer-2023-strawberry-chirp"))
    let view = VStack(spacing: 0) {
      MidsummerSeriesRow(series: garden, isFresh: true, onTap: {})
      MidsummerSeriesRow(series: strawberry, isFresh: false, onTap: {})
    }
    .background(Color.white)
    try render(view, name: "05-series-row", size: CGSize(width: 393, height: 250))
  }

  /// 图一左侧年份栏（选中态：橙字 + 橙竖条 + 白底）。
  /// 渲染的是 `MidsummerYearRailContent` 而不是 `MidsummerYearRail`——
  /// 后者外面套着 `ScrollView`，`ImageRenderer` 会给你一张只有背景色的空图。
  @MainActor
  func testYearRailRendersAndExportsSnapshot() throws {
    let store = MidsummerStore(bundle: .main)
    let view = MidsummerYearRailContent(
      entries: store.yearEntries,
      activeYear: store.yearEntries.first(where: { $0.year == 2025 })?.year,
      onSelect: { _ in }
    )
    .frame(width: 86)
    .background(MidsummerTheme.railBackground)
    try render(view, name: "06-year-rail", size: CGSize(width: 86, height: 360))
  }

  /// 图一顶部系列 chips（选中态：浅橙底 + 橙字）。
  @MainActor
  func testSeriesChipsRenderAndExportsSnapshot() throws {
    let view = VStack(alignment: .leading, spacing: 10) {
      MidsummerSeriesChip(title: "全部", isSelected: true, action: {})
      MidsummerSeriesChip(title: "2.9 小熊博物馆系列", isSelected: false, action: {})
      MidsummerSeriesChip(title: "5.8 蝴蝶结·永恒花园", isSelected: true, action: {})
      MidsummerSeriesChip(title: "草莓肥啾", isSelected: false, action: {})
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white)
    try render(view, name: "07-series-chips", size: CGSize(width: 393, height: 240))
  }

  /// 图一的核心元素——商品卡片（左方图 + 右标题/价格/尺码）。
  /// 一次导三张，覆盖「有价格」「无价格」「定金起」三种状态。
  @MainActor
  func testItemCardsRenderAndExportSnapshot() throws {
    let store = MidsummerStore(bundle: .main)

    let priced = try XCTUnwrap(store.series(withID: "midsummer-2023-strawberry-chirp"))
    let pricedItem = try XCTUnwrap(priced.items.first)

    let depositSeries = try XCTUnwrap(store.series(withID: "midsummer-2026-sakura-lamb"))
    let depositItem = try XCTUnwrap(depositSeries.items.first)

    // 无价格的系列：验证「价格待补充」标记不崩
    let pendingSeries = try XCTUnwrap(store.series(withID: "midsummer-2023-cardcaptor"))
    let pendingItem = try XCTUnwrap(pendingSeries.items.first)

    let view = VStack(spacing: 0) {
      MidsummerItemCard(series: priced, item: pricedItem, onTap: {})
      Divider()
      MidsummerItemCard(series: depositSeries, item: depositItem, onTap: {})
      Divider()
      MidsummerItemCard(series: pendingSeries, item: pendingItem, onTap: {})
    }
    .background(Color.white)
    try render(view, name: "08-item-cards", size: CGSize(width: 393, height: 400))
  }

  // MARK: - 渲染辅助

  @MainActor
  @discardableResult
  private func render(
    _ view: some View,
    name: String,
    size: CGSize = CGSize(width: 393, height: 852)
  ) throws -> UIImage {
    let renderer = ImageRenderer(
      content: view
        .frame(width: size.width, height: size.height, alignment: .top)
        // 整块画布铺白：`isOpaque = true` 时未被内容覆盖的区域会渲染成黑色，
        // 快照图会出现难看的黑边（踩过）。alignment: .top 让内容顶部对齐而非垂直居中。
        .background(Color.white)
        .environment(\.colorScheme, .light)
    )
    renderer.scale = 2
    renderer.isOpaque = true

    let image = try XCTUnwrap(renderer.uiImage, "\(name) 渲染失败：拿到了 nil 图像")

    // size 是「点」，等于 frame 的 pt 值（不是 size * scale）
    XCTAssertEqual(image.size.width, size.width, accuracy: 4, "\(name) 宽度点数不符")
    XCTAssertEqual(image.size.height, size.height, accuracy: 4, "\(name) 高度点数不符")

    // bitmap 才是像素：scale=2 时应为点数的两倍
    if let cgImage = image.cgImage {
      XCTAssertEqual(CGFloat(cgImage.width), size.width * 2, accuracy: 4, "\(name) 像素宽度不符")
      XCTAssertEqual(CGFloat(cgImage.height), size.height * 2, accuracy: 4, "\(name) 像素高度不符")
    }

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("midsummer_snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).png")
    try XCTUnwrap(image.pngData(), "\(name) PNG 编码失败").write(to: url, options: .atomic)
    print("📸 [Midsummer] 快照：\(url.path)")

    return image
  }
}
