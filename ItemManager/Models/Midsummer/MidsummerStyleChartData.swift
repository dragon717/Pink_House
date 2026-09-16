import UIKit

// MARK: - 仲夏物语 · 款式资料数据
//
// 「款式分类与尺码表」与「链接原始信息」两个原生页面的数据层。
// 数据源是随包分发的资源 JSON（`midsummer-style-chart.json` /
// `midsummer-link-report.json`），内容转录自淘宝商品详情页原图
// （主链接采集于 2026-09-15，小物链接采集于 2026-09-16）。
// 图片一律引用 bundle 内 `SeedImages/seed-*.jpg` 静态素材，
// 解析顺序与 `MidsummerCoverView` 一致：Bundle 资源 → ImageManager 兜底。

enum MidsummerStyleChartData {

  /// 系列资料的归属系列：「款式分类与尺码表」「链接原始信息」按系列整理，
  /// 目前只有樱花小羊系列有完整资料；其它系列的详情页不显示资料入口。
  nonisolated enum ArchiveContent {
    static let seriesID = "midsummer-2026-sakura-lamb"
  }

  /// 解析静态素材图：bundle 资源优先，找不到再查 ImageManager 的用户目录。
  static func resolvedImage(named name: String) -> UIImage? {
    guard !name.isEmpty else { return nil }
    return UIImage(named: name) ?? ImageManager.shared.loadImage(fileName: name)
  }

  static func load<T: Decodable>(_ filename: String, as type: T.Type) -> T? {
    guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
      return nil
    }
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      print("⚠️ [MidsummerStyleChartData] 解码 \(filename).json 失败: \(error)")
      return nil
    }
  }
}

// MARK: 款式分类与尺码表

struct MidsummerStyleChartCatalog: Codable, Equatable {

  let generatedAt: String
  let sources: [Source]
  let categories: [Category]

  struct Source: Codable, Equatable {
    let label: String
    let shopName: String
    let url: String
    let shortURL: String?
    let capturedOn: String
  }

  struct Category: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    /// 分类级价格；多款分类（如「小物」）为 nil，价格挂在每张表上。
    let price: String?
    let sizes: String?
    let fabrics: String?
    let swatches: [Swatch]
    let headerTips: [String]
    let charts: [Chart]
  }

  struct Swatch: Codable, Equatable {
    let name: String
    let imageName: String
  }

  struct Chart: Codable, Equatable {
    let title: String
    /// 单表价格（多款分类用，如「小物」节里的 立体小脸包 ¥119 / bb帽 ¥229）
    let priceNote: String?
    /// 原尺码表图（bundle 静态素材），点按可放大
    let imageName: String
    let fabrics: String?
    let swatches: [Swatch]?
    let headers: [String]
    let rows: [[String]]
    let tips: [String]
  }

  static func loadFromBundle() -> MidsummerStyleChartCatalog? {
    MidsummerStyleChartData.load("midsummer-style-chart", as: Self.self)
  }
}

// MARK: 链接原始信息

struct MidsummerLinkReport: Codable, Equatable {

  let generatedAt: String
  let links: [Link]

  struct Link: Codable, Equatable, Identifiable {
    let title: String
    let itemID: String
    let url: String
    let shortURL: String?
    let shopName: String
    let capturedOn: String
    let sellCount: String
    let priceRange: String
    let emphParams: [Param]
    let colorOptions: [ColorOption]
    let skuRows: [SKURow]
    let detailImageCount: Int

    var id: String { itemID }
  }

  struct Param: Codable, Equatable {
    let label: String
    let value: String
  }

  struct ColorOption: Codable, Equatable, Identifiable {
    let name: String
    let sizes: [String]
    let prices: [String]
    let logistics: [String]
    let imageName: String

    var id: String { name }
  }

  struct SKURow: Codable, Equatable, Identifiable {
    let color: String
    let size: String
    let price: String
    let quantity: String
    let logistics: String

    var id: String { "\(color)-\(size)" }
  }

  static func loadFromBundle() -> MidsummerLinkReport? {
    MidsummerStyleChartData.load("midsummer-link-report", as: Self.self)
  }
}
