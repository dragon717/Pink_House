import Combine
import SwiftUI

// MARK: - 自建系列 · 本地存储
//
// 「上传上新」改为直达新建系列（用户 2026-09-17）：不再从既有系列里挑，
// 由创作者自己填写系列名 / 上新时间 / 主图并创建新系列。
// 种子与云端目录都不可变，所以自建系列单独落 JSON（Application Support /
// 可注入目录），`MidsummerStore.recomputeCatalog()` 把它们并入 catalog——
// 上架新品挂到自建系列 id 上，走与既有系列完全相同的 feed / 详情 / 入库链路。
//
// 与 `MidsummerListingStore` 同构：本地优先，后续接云端时记录已是 Codable，迁移成本低。

@MainActor
final class MidsummerCustomSeriesStore: ObservableObject {
  static let shared = MidsummerCustomSeriesStore()

  @Published private(set) var seriesList: [MidsummerSeriesDTO] = []

  private let fileURL: URL

  nonisolated static func defaultFileURL() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = support.appendingPathComponent("MidsummerListing", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("custom-series.json")
  }

  /// 允许注入目录：单测用临时目录，不碰真实存档。
  init(directory: URL? = nil) {
    if let directory {
      fileURL = directory.appendingPathComponent("custom-series.json")
    } else {
      fileURL = Self.defaultFileURL()
    }
    load()
  }

  // MARK: 查询

  func series(withID id: String) -> MidsummerSeriesDTO? {
    seriesList.first { $0.id == id }
  }

  // MARK: 变更

  func add(_ series: MidsummerSeriesDTO) {
    seriesList.removeAll { $0.id == series.id }
    seriesList.append(series)
    persist()
  }

  func removeAllForTesting() {
    seriesList = []
    persist()
  }

  // MARK: 持久化

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    seriesList = (try? JSONDecoder().decode([MidsummerSeriesDTO].self, from: data)) ?? []
  }

  private func persist() {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(seriesList)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      print("⚠️ [MidsummerCustomSeries] 存档写入失败：\(error.localizedDescription)")
    }
  }
}
