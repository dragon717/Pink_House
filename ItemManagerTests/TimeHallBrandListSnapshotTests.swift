import SwiftUI
import XCTest

@testable import ItemManager

/// 时光馆主页（图一品牌列表）的**区块快照**。
///
/// 为什么只做区块、不做整页：`ImageRenderer` 对 `ScrollView` / `Form` / `List`
/// 只能取到可视区框架，整页会渲成空白（上一轮已踩过，见 skill
/// `pink-house-xcodebuild-acceptance`）。所以这里渲染的都是**非滚动容器**的区块，
/// 用来逐项核对图一的版式：方形缩略图 + 绿「新」角标、绿字主指标 + 竖线 + 灰字时间、
/// 橙色「进店」、灰色「⋯」。
///
/// 另外两条已踩过的限制也在这里回避：
///   · 被渲染的视图不能有 `.task` / `.onAppear` 写 `@State`，否则
///     `SwiftUICore Fatal error: no current update to enqueue action to` 崩测试进程
///   · `UIImage.size` 单位是点，不是像素（`renderer.scale = 2` 只放大 bitmap）
@MainActor
final class TimeHallBrandListSnapshotTests: XCTestCase {

  // MARK: - 数据

  /// 用隔离的 UserDefaults 造 followStore：避免宿主机上已有的「已加入」记录
  /// 让快照里的时间文案每次都变。
  private func makeListings() -> [TimeHallBrandListing] {
    let suite = "TimeHallBrandListSnapshotTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    return TimeHallBrandListingsBuilder.makeListings(
      merchants: TimeHallMerchant.allCases,
      metaCatalog: TimeHallBrandMetaSeed.load(),
      inStockCount: { TimeHallBrandStockCounter.shared.inStockCount(for: $0) },
      followStore: TimeHallBrandFollowStore(defaults: defaults)
    )
  }

  private func listing(withNewItems: Bool) throws -> TimeHallBrandListing {
    let listings = makeListings()
    let match = listings.first { $0.hasVerifiedNewItems == withNewItems }
    return try XCTUnwrap(
      match,
      withNewItems ? "应至少有一个品牌带可核验上新" : "应至少有一个品牌没有上新数据"
    )
  }

  // MARK: - 快照

  /// 图一核心行：**有上新**（绿字「N件新品」+ 缩略图左下绿「新」角标）。
  func testBrandRowWithNewItemsSnapshot() throws {
    let row = TimeHallBrandListRow(
      listing: try listing(withNewItems: true),
      onEnter: {},
      onOpenWebsite: {}
    )
    try render(row, name: "01-brand-row-new", size: CGSize(width: 393, height: 88))
  }

  /// 图一核心行：**无上新**（主指标退化为真实在售件数，且**不出现**绿「新」角标）。
  func testBrandRowWithoutNewItemsSnapshot() throws {
    let row = TimeHallBrandListRow(
      listing: try listing(withNewItems: false),
      onEnter: {},
      onOpenWebsite: {}
    )
    try render(row, name: "02-brand-row-stock", size: CGSize(width: 393, height: 88))
  }

  /// 全部品牌叠成一列——最接近图一整体观感的一张，用来核对行距与对齐。
  func testBrandRowStackSnapshot() throws {
    let rows = VStack(spacing: 0) {
      ForEach(makeListings()) { item in
        TimeHallBrandListRow(listing: item, onEnter: {}, onOpenWebsite: {})
      }
    }
    .background(Color.white)
    try render(rows, name: "03-brand-rows", size: CGSize(width: 393, height: 530))
  }

  /// 筛选胶囊：全部 / 有上新 / 国牌 / 日牌，选中态为浅橙底 + 橙字。
  func testFilterChipsSnapshot() throws {
    let chips = HStack(spacing: 8) {
      ForEach(TimeHallBrandListFilter.allCases) { item in
        TimeHallBrandFilterChip(title: item.title, isSelected: item == .hasNew, action: {})
      }
    }
    .padding(.horizontal, 16)
    .background(Color.white)
    try render(chips, name: "04-filter-chips", size: CGSize(width: 393, height: 46))
  }

  /// 加入衣橱的两种形态并列——核对「两种都做出来、无默认偏向」。
  func testWardrobeInsertButtonsSnapshot() throws {
    let buttons = TimeHallWardrobeInsertButtons(
      onQuickInsert: {},
      onOpenEditor: {}
    )
    .padding(16)
    .background(Color.white)
    try render(buttons, name: "05-wardrobe-insert-modes", size: CGSize(width: 393, height: 110))
  }

  // MARK: - 渲染辅助

  private func render<V: View>(_ view: V, name: String, size: CGSize) throws {
    let renderer = ImageRenderer(
      content: view
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    )
    renderer.scale = 2
    // 与背景色一致，避免 `isOpaque = true` 时画布没铺满留下黑边
    renderer.isOpaque = false

    let image = try XCTUnwrap(renderer.uiImage, "\(name) 渲染失败：拿到了 nil 图像")

    // 单位是点（不是像素）
    XCTAssertEqual(image.size.width, size.width, accuracy: 1, "\(name) 宽度不符合预期")
    XCTAssertEqual(image.size.height, size.height, accuracy: 1, "\(name) 高度不符合预期")

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("timehall_brand_snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).png")
    let data = try XCTUnwrap(image.pngData(), "\(name) 无法导出 PNG")
    try data.write(to: url)
    print("📸 \(url.path)")
  }
}
