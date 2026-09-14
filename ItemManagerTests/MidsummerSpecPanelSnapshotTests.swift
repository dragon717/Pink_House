import SwiftUI
import XCTest

@testable import ItemManager

/// 规格面板的渲染冒烟 + 版式快照。
///
/// 只渲染 `MidsummerSpecGroupsSection`（**不含** `ScrollView`）：
/// `ImageRenderer` 渲染滚动容器只能拿到空框架，而面板本体内含一个纵向 `ScrollView`，
/// 整体丢进去会截出一张几乎空白的图，核对不出任何东西。
/// （同一模式见 `MidsummerYearRailContent`。）
///
/// PNG 落在 `NSTemporaryDirectory()/midsummer_spec_snapshots/`，用于人工核对：
/// 选中态是不是橙底橙字、灰化态是不是明显更淡、无图占位是否与有色块区分得开。
final class MidsummerSpecPanelSnapshotTests: XCTestCase {

  // MARK: - 夹具

  private func option(_ id: String, _ name: String, image: String? = nil) -> MidsummerSpecOption {
    MidsummerSpecOption(id: id, name: name, image: image)
  }

  private func group(
    _ id: String, _ name: String, role: MidsummerSpecRole?, _ options: [MidsummerSpecOption]
  ) -> MidsummerSpecGroup {
    MidsummerSpecGroup(id: id, name: name, role: role, options: options)
  }

  private func item(
    specGroups: [MidsummerSpecGroup]?,
    skus: [MidsummerSKU]? = nil
  ) -> MidsummerItemDTO {
    MidsummerItemDTO(
      id: "snapshot-item",
      seriesID: "snapshot-series",
      name: "樱花小羊 SK",
      kind: .skirt,
      price: 119,
      deposit: nil,
      balance: nil,
      priceKind: .reference,
      priceCapturedOn: "2026-09-15",
      priceNote: nil,
      sizes: ["S", "M", "L", "XL"],
      colors: ["白色", "浅粉"],
      coverImage: nil,
      itemURL: nil,
      sourceURL: "https://example.com",
      note: nil,
      specGroups: specGroups,
      skus: skus
    )
  }

  private var colorGroupWithImages: MidsummerSpecGroup {
    group("color", "颜色分类", role: .color, [
      option("sk-pink", "Sk粉色", image: "spec_sk_pink"),
      option("sk-white", "Sk白色", image: "spec_sk_white"),
    ])
  }

  private var sizeGroup: MidsummerSpecGroup {
    group("size", "尺码", role: .size, [
      option("s", "S"), option("m", "M"), option("l", "L"), option("xl", "XL"),
    ])
  }

  // MARK: - 用例

  /// 有缩略图 + 文字 chip 两组：核对同屏两种格子是否协调，以及选中态。
  @MainActor
  func testSpecGroupsWithThumbnailsExportsSnapshot() throws {
    let item = self.item(specGroups: [colorGroupWithImages, sizeGroup])
    let view = MidsummerSpecGroupsSection(
      item: item,
      series: nil,
      selection: MidsummerSpecSelection(picks: ["color": "sk-white", "size": "l"]),
      onPick: { _, _ in }
    )
    .padding(16)
    .background(Color.white)

    try render(view, name: "01-带缩略图-选中Sk白色与L", size: CGSize(width: 393, height: 320))
  }

  /// 无图选项应当用明确的「无图」占位，而不是品牌的粉色水印渐变——
  /// 否则使用者分不清「这个规格有专属图」和「这个规格还没图」。
  @MainActor
  func testSpecGroupsWithoutImagesUseExplicitPlaceholder() throws {
    let bare = self.group("color", "颜色分类", role: .color, [
      option("sk-pink", "Sk粉色"),
      option("sk-white", "Sk白色"),
    ])
    let item = self.item(specGroups: [bare])
    let view = MidsummerSpecGroupsSection(
      item: item,
      series: nil,
      selection: MidsummerSpecSelection(picks: ["color": "sk-pink"]),
      onPick: { _, _ in }
    )
    .padding(16)
    .background(Color.white)

    try render(view, name: "02-无图占位", size: CGSize(width: 393, height: 170))
  }

  /// 多规格联动：只有「粉色×M」「白色×L」存在，所以选粉色后 S/L/XL 应当灰掉，
  /// 并出现「灰掉的选项与当前已选无法组成同一套规格」的说明。
  @MainActor
  func testLinkageGreyingExportsSnapshot() throws {
    let item = self.item(
      specGroups: [colorGroupWithImages, sizeGroup],
      skus: [
        MidsummerSKU(id: "pink-m", options: ["color": "sk-pink", "size": "m"], image: nil, price: nil),
        MidsummerSKU(id: "white-l", options: ["color": "sk-white", "size": "l"], image: nil, price: nil),
      ]
    )
    let view = MidsummerSpecGroupsSection(
      item: item,
      series: nil,
      selection: MidsummerSpecSelection(picks: ["color": "sk-pink", "size": "m"]),
      onPick: { _, _ in }
    )
    .padding(16)
    .background(Color.white)

    try render(view, name: "03-联动灰化", size: CGSize(width: 393, height: 320))
  }

  /// 规格缺省：必须给出一句明确说明，不能是空白。
  @MainActor
  func testEmptySpecHintExportsSnapshot() throws {
    let item = self.item(specGroups: nil)
    let view = MidsummerSpecGroupsSection(
      item: item,
      series: nil,
      selection: .empty,
      onPick: { _, _ in }
    )
    .padding(16)
    .background(Color.white)

    try render(view, name: "04-规格缺省提示", size: CGSize(width: 393, height: 100))
  }

  // MARK: - 渲染辅助
  //
  // `isOpaque = true` 时未被内容覆盖的区域会渲染成黑色，所以统一铺白底 + 顶部对齐；
  // 断言用「点」而不是像素（`UIImage.size` 是点，`cgImage.width` 才是像素）。

  @MainActor
  @discardableResult
  private func render(
    _ view: some View,
    name: String,
    size: CGSize
  ) throws -> UIImage {
    let renderer = ImageRenderer(
      content: view
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    )
    renderer.scale = 2
    renderer.isOpaque = true

    let image = try XCTUnwrap(renderer.uiImage, "\(name) 渲染失败：拿到了 nil 图像")

    XCTAssertEqual(image.size.width, size.width, accuracy: 4, "\(name) 宽度点数不符")
    XCTAssertEqual(image.size.height, size.height, accuracy: 4, "\(name) 高度点数不符")

    if let cgImage = image.cgImage {
      XCTAssertEqual(CGFloat(cgImage.width), size.width * 2, accuracy: 4, "\(name) 像素宽度不符")
      XCTAssertEqual(CGFloat(cgImage.height), size.height * 2, accuracy: 4, "\(name) 像素高度不符")
    }

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("midsummer_spec_snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(name).png")
    try XCTUnwrap(image.pngData()).write(to: url)
    print("SNAPSHOT → \(url.path)")

    return image
  }
}
