import Foundation

// MARK: - 上新工作台 · 单品 listing（用户 2026-09-16）
//
// 与「创作者投稿」（MidsummerContributeView → CloudKit）是两条通道：
//   · 投稿：系列级、云端公共库、白名单门控；
//   · 上新工作台（本文件）：**围绕「樱花小羊」系列**的单品上新，
//     本地持久化（草稿 / 已上架 / 已下架），上架后并入系列 feed。
//
// 深度结合衣橱的关键：上架商品转成 `MidsummerItemDTO` 进入既有渲染链——
// 品牌页卡片、系列详情、规格抽屉、一键入库（含多选配一套）全部自动可用，
// 不需要为新商品另写一条入库路径。

/// 上新工作台单品在 DTO 层的 id 前缀（首页 feed 靠它区分「基础条目」与「上架新品」）。
nonisolated let MidsummerListingItemIDPrefix = "midsummer-listing-"

/// 上架状态机：`draft → listed ⇄ delisted`。`delisted` 可重新上架。
nonisolated enum MidsummerListingStatus: String, Codable, CaseIterable, Sendable {
  case draft
  case listed
  case delisted

  var labelZH: String {
    switch self {
    case .draft: return "草稿"
    case .listed: return "已上架"
    case .delisted: return "已下架"
    }
  }
}

nonisolated struct MidsummerListing: Codable, Identifiable, Equatable, Sendable {
  /// `upload-` 前缀 + 8 位随机串；转 DTO 时再加 `midsummer-listing-` 命名空间。
  let id: String
  /// 目前固定为樱花小羊（`MidsummerStyleChartData.ArchiveContent.seriesID`）。
  var seriesID: String
  var name: String
  var kindRaw: String
  /// 现货价（元）
  var price: Int?
  /// 预约价（全款预约，元）
  var preorderPrice: Int?
  var deposit: Int?
  var balance: Int?
  /// `price` 的口径 raw。nil = 未填现货价。
  var priceKindRaw: String?
  var note: String
  /// 原文出处（合规必填，Apple 5.2）。留空时转 DTO 回退到系列出处。
  var sourceURL: String
  /// 该商品支持的尺码（从小到大排序展示由 DTO 层处理）。
  var sizes: [String]
  /// 关联的系列款式选项名（对应樱花小羊款式组的选项 name 全名，如「现 sk 粉色」）。
  /// 这就是「自动关联该系列的风格与数据」的锚点：规格组、款式对应图、尺码表
  /// 都按它从系列单品里继承。
  var variantOptionNames: [String]
  /// 商品图（ImageManager Images 目录内的文件名）。第 1 张为主图。
  var imageFiles: [String]
  var status: MidsummerListingStatus
  var createdAt: Date
  var updatedAt: Date
  var listedAt: Date?

  var kind: MidsummerItemKind {
    get { MidsummerItemKind(rawValue: kindRaw) ?? .op }
    set { kindRaw = newValue.rawValue }
  }

  var priceKind: MidsummerPriceKind? {
    get { priceKindRaw.flatMap(MidsummerPriceKind.init(rawValue:)) }
    set { priceKindRaw = newValue?.rawValue }
  }

  static func newID() -> String {
    "upload-" + UUID().uuidString.prefix(8).lowercased()
  }

  /// 价格摘要（工作台列表行 / 预览页用）。
  var priceSummary: String {
    if let price { return "¥\(price)" }
    if let preorderPrice { return "预约价 ¥\(preorderPrice)" }
    if deposit != nil || balance != nil {
      return [deposit.map { "定金 ¥\($0)" }, balance.map { "尾款 ¥\($0)" }]
        .compactMap { $0 }.joined(separator: " + ")
    }
    return "价格待填"
  }
}

// MARK: - 转成渲染链消费的 MidsummerItemDTO

extension MidsummerListing {

  /// 上架商品 → 单品 DTO。
  ///
  /// 继承规则（「自动关联该系列的风格与数据」的具体实现）：
  ///   · **款式组**：从系列单品款式组里挑出 `variantOptionNames` 命中的选项——
  ///     新商品只出现自己关联的款式，不会把全系列 24 个款式都摆进规格抽屉；
  ///   · **尺码组**：从系列尺码组按 `sizes` 匹配（「S」↔「S码」容错）；
  ///     系列没有对应选项时按填写的尺码自建组（新商品可能引入新码）；
  ///   · **价格档位标注组**：原样继承（现货价 / 预约价 / 定金 / 尾款）；
  ///   · **款式对应图**：`imageFiles` 依次映射到关联款式；
  ///   · **尺码表**：继承系列单品里与关联款式同名的条目（大小写不敏感）；
  ///   · SKU 表不继承（nil）——任意搭配合法，价格走单品价。
  ///
  /// - Parameters:
  ///   - sourceItem: 系列现有单品（樱花小羊主条目），继承规格的数据源。
  ///   - seriesSourceURL: 系列出处；表单没填出处时回退（合规兜底）。
  func makeItemDTO(sourceItem: MidsummerItemDTO?, seriesSourceURL: String) -> MidsummerItemDTO {
    let sourceGroups = sourceItem?.specGroups ?? []
    let styleGroup = sourceGroups.first { $0.resolvedRole == .variant }
    let sizeGroup = sourceGroups.first { $0.resolvedRole == .size }
    let pricingGroup = sourceGroups.first { $0.resolvedRole == .other && $0.id == "pricing" }

    var groups: [MidsummerSpecGroup] = []

    // 款式组：只保留关联的款式选项；一个都没命中就不带款式组（退化为无规格单品）。
    if let styleGroup {
      let picked = styleGroup.options.filter { variantOptionNames.contains($0.name) }
      if !picked.isEmpty {
        groups.append(
          MidsummerSpecGroup(id: styleGroup.id, name: styleGroup.name, role: styleGroup.role, options: picked)
        )
      }
    }

    // 尺码组：先按系列选项匹配（「S」匹配「S码」），匹配不上的尺码自建选项。
    if let sizeGroup, !sizes.isEmpty {
      var options: [MidsummerSpecOption] = []
      var unmatched: [String] = []
      for size in sizes {
        if let hit = sizeGroup.options.first(where: { Self.optionName($0.name, matchesSize: size) }) {
          if !options.contains(where: { $0.id == hit.id }) { options.append(hit) }
        } else {
          unmatched.append(size)
        }
      }
      options += unmatched.map {
        MidsummerSpecOption(id: "sz-\($0)", name: "\($0)码", image: nil)
      }
      if !options.isEmpty {
        groups.append(
          MidsummerSpecGroup(id: sizeGroup.id, name: sizeGroup.name, role: sizeGroup.role, options: options)
        )
      }
    }

    // 价格档位标注组：原样继承。
    if let pricingGroup {
      groups.append(pricingGroup)
    }

    // 款式对应图：关联款式与图片按顺序对位（图不够时循环复用，至少每款有图）。
    var variantImages: [String: String] = [:]
    if !imageFiles.isEmpty {
      for (index, styleName) in variantOptionNames.enumerated() {
        variantImages[styleName] = imageFiles[index % imageFiles.count]
      }
    }

    // 尺码表：继承系列单品里与关联款式对应的条目。注意款式表 key 是短名
    // （「SK」「内搭」），而款式选项名是「现 sk 粉色」这类全名——
    // 用「全名包含短名」匹配（大小写不敏感），与详情页归组的口径同源。
    let inheritedCharts = (sourceItem?.sizeChartImages ?? [])?.filter { entry in
      let style = entry.style.lowercased()
      guard !style.isEmpty else { return false }
      return variantOptionNames.contains { $0.lowercased().contains(style) }
    }

    let trimmedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)

    return MidsummerItemDTO(
      id: MidsummerListingItemIDPrefix + id,
      seriesID: seriesID,
      name: name,
      kind: kind,
      price: price,
      preorderPrice: preorderPrice,
      deposit: deposit,
      balance: balance,
      priceKind: price == nil ? nil : priceKind,
      priceCapturedOn: price == nil ? nil : Self.todayStamp(),
      priceNote: nil,
      sizes: sizes,
      colors: [],
      coverImage: imageFiles.first,
      galleryImageNames: imageFiles.count > 1 ? Array(imageFiles.dropFirst()) : nil,
      itemURL: trimmedURL.isEmpty ? nil : trimmedURL,
      sourceURL: trimmedURL.isEmpty ? seriesSourceURL : trimmedURL,
      note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
      sizeChartImages: (inheritedCharts?.isEmpty ?? true) ? nil : inheritedCharts,
      variantImageNames: variantImages.isEmpty ? nil : variantImages,
      specGroups: groups.isEmpty ? nil : groups,
      skus: nil
    )
  }

  /// 尺码匹配：「S」↔「S码」；大小写不敏感。
  static func optionName(_ optionName: String, matchesSize size: String) -> Bool {
    let normalizedOption = optionName
      .replacingOccurrences(of: "码", with: "")
      .trimmingCharacters(in: .whitespaces)
      .lowercased()
    return normalizedOption == size.trimmingCharacters(in: .whitespaces).lowercased()
  }

  /// 价格采集日（`yyyy-MM-dd`）：有价必带采集日，与投稿同一条硬规则。
  static func todayStamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: Date())
  }
}
