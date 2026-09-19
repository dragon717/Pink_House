import Combine
import SwiftUI
import UIKit

// MARK: - 上新工作台 · 本地存储
//
// listing 记录存 JSON（Application Support / 可注入目录），商品图存
// ImageManager 的 Images 目录（`midsummer-listing-` 命名空间，与种子图 /
// 草稿图 / 云端下载图同目录共存，`loadImage(fileName:)` 一条读取路径全通）。
//
// 为什么本地而不是 CloudKit：仲夏物语的上新是运营者自己的日常动作，
// 先保证「录了就能上架、上架就能入库」的闭环；后续要多人协作时再接云端
// （记录结构已按 Codable 设计，迁移成本低）。

@MainActor
final class MidsummerListingStore: ObservableObject {
  static let shared = MidsummerListingStore()

  @Published private(set) var listings: [MidsummerListing] = []

  private let fileURL: URL

  nonisolated static func defaultFileURL() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = support.appendingPathComponent("MidsummerListing", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("listings.json")
  }

  /// 允许注入目录：单测用临时目录，不碰真实存档。
  init(directory: URL? = nil) {
    if let directory {
      fileURL = directory.appendingPathComponent("listings.json")
    } else {
      fileURL = Self.defaultFileURL()
    }
    load()
    // 注意：init 只做纯加载，不在这里跑预售流转——流转的时机应由「用户真的
    // 在看列表」（系列页 / 工作台 onAppear）与「云端刷新」驱动，避免加载
    // 时刻隐式改写存档（单测注入历史时间会被提前流转，语义也难解释）。
  }

  // MARK: 查询

  /// 按更新时间倒序（最近动过的在最上面）。
  var sortedListings: [MidsummerListing] {
    listings.sorted { $0.updatedAt > $1.updatedAt }
  }

  /// 已上架（进系列 feed 的那一批）。
  var listedListings: [MidsummerListing] {
    listings.filter { $0.status == .listed }
  }

  func listings(inSeries seriesID: String) -> [MidsummerListing] {
    listings.filter { $0.seriesID == seriesID }
  }

  func listing(withID id: String) -> MidsummerListing? {
    listings.first { $0.id == id }
  }

  /// 某系列已上架数量（入口行副标题用）。
  func listedCount(inSeries seriesID: String) -> Int {
    listings(inSeries: seriesID).filter { $0.status == .listed }.count
  }

  // MARK: 变更
  //
  // ⚠️ 以下全部是**写接口**，第一行都过 `CreatorAccess.requireCreator`：
  // 界面隐藏入口只是第一层，绕过界面直接调这些接口同样会被拦下（不落盘）。
  // 调用方传入 `operation` 只是为了让拒绝提示能说清是哪一步被拦（发布 / 改价 / 换图）。

  /// 新建或更新（按 id 判定）；同时刷新 `updatedAt`。
  ///
  /// - Parameter operation: 触发本次写入的动作（发布 / 改价 / 编辑），用于权限提示。
  /// - Throws: `CreatorAccessDenied` 非创作者调用时抛出，数据保持不变。
  func upsert(_ listing: MidsummerListing, operation: CreatorOperation = .listingEdit) throws {
    try CreatorAccess.requireCreator(operation)
    write(listing)
  }

  /// 状态迁移：上架 / 下架 / 转草稿。`listed` 会记录上架时间。
  func updateStatus(of id: String, to status: MidsummerListingStatus) throws {
    try CreatorAccess.requireCreator(.listingStatus)
    guard var listing = listing(withID: id) else { return }
    listing.status = status
    listing.listedAt = status == .listed ? Date() : nil
    write(listing)
  }

  /// 删除 listing 并清掉它的商品图文件。
  func delete(_ id: String) throws {
    try CreatorAccess.requireCreator(.listingDelete)
    if let listing = listing(withID: id) {
      deleteImageFiles(of: listing)
    }
    listings.removeAll { $0.id == id }
    persist()
  }

  /// 无校验的落盘通道：**只给系统自动流转**（预售相位推进）用。
  ///
  /// 业务规则里「定金期 → 尾款期」的推进是时间驱动的，不是任何人的编辑动作，
  /// 对普通用户的已上架商品同样生效——它不能走带权限校验的 `upsert`，
  /// 否则普通用户 App 里的预售状态会永远推不动。
  private func write(_ listing: MidsummerListing) {
    var next = listing
    next.updatedAt = Date()
    if let index = listings.firstIndex(where: { $0.id == next.id }) {
      listings[index] = next
    } else {
      listings.append(next)
    }
    persist()
  }

  // MARK: 预售状态自动流转（用户 2026-09-17 业务规则）

  /// 按当前时间推进「定金 → 尾款」的**写入式**流转。
  ///
  /// 只写一件事：定金期已结束的商品把 `stage` 从 `.deposit` 推进到 `.balance`——
  /// 这样创作者工作台、系列 feed 合并链路读到的是当前真实阶段。
  /// 2026-09-19 阶段收敛后，**预约价阶段配了定金**的商品（定金+尾款拆分填法）
  /// 沿用同一条流转；纯全款预约（没配定金）不参与。
  /// 「预售结束」**不写盘**：相位由 `presalePhase(at:)` 时间函数实时推导，
  /// 创作者事后延长尾款截止时间，商品自动回到尾款期；写成终态就没法回头了。
  ///
  /// - Parameter now: 可注入时间（单测 / 预览），默认当前时刻。
  /// - Returns: 发生阶段流转的商品数量（供调用方决定是否刷新 UI）。
  @discardableResult
  func refreshPresaleTransitions(now: Date = Date()) -> Int {
    var moved = 0
    for (index, listing) in listings.enumerated() {
      let onPresaleLine =
        listing.stage == .deposit
        || (listing.stage == .preorder && listing.deposit != nil)
      guard listing.status == .listed, onPresaleLine,
        let phase = listing.presalePhase(at: now), phase == .balance
      else { continue }
      listings[index].stage = .balance
      moved += 1
    }
    if moved > 0 { persist() }
    return moved
  }

  /// 某系列里按预售相位查询已上架商品。
  /// 返回的 key 有序：`.deposit` 在前（上新列表）、`.balance` 居中（尾款列表）、
  /// `.ended` 收尾；不走状态机的商品不在结果里（它们进「全部商品」）。
  func presaleGrouped(inSeries seriesID: String, now: Date = Date())
    -> [(phase: MidsummerPresalePhase, listings: [MidsummerListing])]
  {
    let order: [MidsummerPresalePhase] = [.deposit, .balance, .ended]
    let grouped = Dictionary(
      grouping: listings(inSeries: seriesID).filter { $0.status == .listed }
    ) { $0.presalePhase(at: now) }
    return order.compactMap { phase in
      grouped[phase].map { (phase, $0.sorted { $0.updatedAt > $1.updatedAt }) }
    }
  }

  /// 详情页 item id（`midsummer-listing-<id>`）反查上架记录。
  func listing(forItemID itemID: String) -> MidsummerListing? {
    guard itemID.hasPrefix(MidsummerListingItemIDPrefix) else { return nil }
    return listing(withID: String(itemID.dropFirst(MidsummerListingItemIDPrefix.count)))
  }

  // MARK: 商品图

  /// 把表单里选的图片落盘（JPEG，主图在前），返回文件名数组。
  /// 同一个 listing 重复保存时旧图先清（替换语义），避免孤儿文件堆积。
  ///
  /// 换图属于创作者能力：权限校验必须在**删旧图之前**，否则被拒时旧图已经没了。
  func saveImages(_ images: [UIImage], listingID: String) throws -> [String] {
    try CreatorAccess.requireCreator(.imageReplace)
    // 清掉这个 listing 之前的图（按命名空间前缀匹配）。
    let prefix = "midsummer-listing-\(listingID)"
    let stale = imageFileNames(withPrefix: prefix)
    for name in stale {
      try? FileManager.default.removeItem(
        at: ImageManager.shared.imagesDirectory.appendingPathComponent(name))
    }

    var names: [String] = []
    for (index, image) in images.enumerated() {
      guard let jpeg = image.jpegData(compressionQuality: 0.85) else { continue }
      let name = "\(prefix)-\(index).jpg"
      do {
        try jpeg.write(
          to: ImageManager.shared.imagesDirectory.appendingPathComponent(name),
          options: .atomic)
        names.append(name)
      } catch {
        print("⚠️ [MidsummerListing] 图片落盘失败：\(error.localizedDescription)")
      }
    }
    return names
  }

  /// 单个**款式图**落盘：`-style-<index>` 与商品主图共用命名空间区分命名。
  ///
  /// 注意调用顺序：必须在 `saveImages` **之后**——它会按前缀清掉这个 listing
  /// 的旧图（含上次保存的款式图），之后重写才不会留下孤儿文件。
  func saveStyleImage(_ image: UIImage, listingID: String, index: Int) throws -> String? {
    try CreatorAccess.requireCreator(.imageReplace)
    let name = "midsummer-listing-\(listingID)-style-\(index).jpg"
    guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
    do {
      try jpeg.write(
        to: ImageManager.shared.imagesDirectory.appendingPathComponent(name),
        options: .atomic)
      return name
    } catch {
      print("⚠️ [MidsummerListing] 款式图落盘失败：\(error.localizedDescription)")
      return nil
    }
  }

  func deleteImageFiles(of listing: MidsummerListing) {
    let names = listing.imageFiles + (listing.styles?.compactMap(\.imageFile) ?? [])
    for name in names {
      try? FileManager.default.removeItem(
        at: ImageManager.shared.imagesDirectory.appendingPathComponent(name))
    }
  }

  private func imageFileNames(withPrefix prefix: String) -> [String] {
    let directory = ImageManager.shared.imagesDirectory
    return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
      .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".jpg") }
  }

  // MARK: 持久化

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    do {
      listings = try JSONDecoder().decode([MidsummerListing].self, from: data)
    } catch {
      print("⚠️ [MidsummerListing] 存档解码失败：\(error.localizedDescription)")
      listings = []
    }
  }

  private func persist() {
    do {
      let data = try JSONEncoder().encode(listings)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("⚠️ [MidsummerListing] 存档写入失败：\(error.localizedDescription)")
    }
  }
}
