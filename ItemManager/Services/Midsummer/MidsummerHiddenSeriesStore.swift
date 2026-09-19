import Combine
import SwiftUI

// MARK: - 隐藏系列账本（种子 / 云端系列的「删除」）
//
// 自建系列删除 = 真删除（档案在本地 JSON，删了就是删了）。种子 / 云端系列
// 不一样：资料来自随包 catalog 与云端公共库，本机没有「删除」的写权限，
// 也不应该有——删掉本地缓存只会被下一次 refresh 原样拉回来。
//
// 所以种子系列的「删除」语义是**本机隐藏**：把系列 id 记进这份账本，
// `MidsummerStore.recomputeCatalog()` 合并 catalog 时按账本过滤。
// 云端资料不受影响（其他用户照常可见）；创作者误删可以通过设置页的
// 「恢复隐藏系列」找回来（`restore`），比真删除安全得多。
//
// 与 `MidsummerCustomSeriesStore` 同构：本地优先、JSON 落 Application Support /
// MidsummerListing/，可注入目录供单测使用。

@MainActor
final class MidsummerHiddenSeriesStore: ObservableObject {
  static let shared = MidsummerHiddenSeriesStore()

  @Published private(set) var hiddenIDs: Set<String>

  private let fileURL: URL

  nonisolated static func defaultFileURL() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = support.appendingPathComponent("MidsummerListing", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("hidden-series.json")
  }

  /// 允许注入目录：单测用临时目录，不碰真实存档。
  init(directory: URL? = nil) {
    if let directory {
      fileURL = directory.appendingPathComponent("hidden-series.json")
    } else {
      fileURL = Self.defaultFileURL()
    }
    hiddenIDs = Self.load(from: fileURL)
  }

  // MARK: 查询

  func isHidden(_ seriesID: String) -> Bool {
    hiddenIDs.contains(seriesID)
  }

  // MARK: 变更

  /// 隐藏系列（创作者的「删除种子系列」入口）：属于创作者的系列管理能力，
  /// 非创作者一律拒绝——与 `MidsummerCustomSeriesStore.remove` 同一权限口径。
  func hide(_ seriesID: String) throws {
    try CreatorAccess.requireCreator(.seriesDelete)
    hiddenIDs.insert(seriesID)
    persist()
  }

  /// 恢复被隐藏的系列（误删兜底；同样只允许创作者操作）。
  func restore(_ seriesID: String) throws {
    try CreatorAccess.requireCreator(.seriesDelete)
    hiddenIDs.remove(seriesID)
    persist()
  }

  func removeAllForTesting() {
    hiddenIDs = []
    persist()
  }

  // MARK: 持久化

  private nonisolated static func load(from fileURL: URL) -> Set<String> {
    guard let data = try? Data(contentsOf: fileURL),
      let list = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return Set(list)
  }

  private func persist() {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(hiddenIDs.sorted())
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("⚠️ [MidsummerHiddenSeries] 存档写入失败：\(error.localizedDescription)")
    }
  }
}
