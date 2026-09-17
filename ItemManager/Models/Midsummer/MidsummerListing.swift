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

/// 上新阶段（类目）：决定这个系列上新出现在时间线上的哪个阶段。
///
/// 2026-09-17 收敛为四档（用户：只保留定金、尾款、现货、预约价）：
///   · 定金 → 尾款：预售定金模式，按先后顺序走；
///   · 预约价：全款预约（不走定金模式的另一条预售线）；
///   · 现货：开售后。
/// 旧的图透 / 出货 / 再贩不再作为可选阶段；旧存档 raw 在 `MidsummerListing.stage`
/// 里做降级映射，解码不会失败。
nonisolated enum MidsummerLaunchStage: String, Codable, CaseIterable, Sendable {
  case deposit   // 定金
  case balance   // 尾款
  case preorder  // 预约价（全款预约）
  case inStock   // 现货

  var labelZH: String {
    switch self {
    case .deposit: return "定金"
    case .balance: return "尾款"
    case .preorder: return "预约价"
    case .inStock: return "现货"
    }
  }

  /// 选择 chip 上的 SF Symbol 图标（与设计稿一致）。
  var iconSystemName: String {
    switch self {
    case .deposit: return "checkmark.circle.fill"
    case .balance: return "creditcard"
    case .preorder: return "clock.arrow.circlepath"
    case .inStock: return "bag"
    }
  }
}

/// 价格配置项（上新工作台第 4 步按阶段联动显示）。
nonisolated enum MidsummerPriceConfigField: String, Codable, CaseIterable, Sendable {
  case shop      // 现货价
  case preorder  // 预约价（全款预约）
  case deposit   // 定金
  case balance   // 尾款

  var labelZH: String {
    switch self {
    case .shop: return "现货价"
    case .preorder: return "预约价（全款预约）"
    case .deposit: return "定金"
    case .balance: return "尾款"
    }
  }
}

extension MidsummerLaunchStage {
  /// 阶段 → 价格配置项联动：第 3 步价格卡只显示当前阶段需要的价格项。
  ///   · 定金：定金 + 尾款（可按需只配其一）+ 定金区间；
  ///   · 尾款：尾款；
  ///   · 预约价：预约价（全款预约）；
  ///   · 现货：现货价。
  var priceFields: [MidsummerPriceConfigField] {
    switch self {
    case .deposit: return [.deposit, .balance]
    case .balance: return [.balance]
    case .preorder: return [.preorder]
    case .inStock: return [.shop]
    }
  }

  /// 价格卡的说明文案（跟阶段走）。
  var priceHint: String {
    switch self {
    case .deposit: return "定金阶段：定金与尾款可按需选择配置；定金区间为该系列的定金范围。"
    case .balance: return "尾款阶段：只需配置尾款金额。"
    case .preorder: return "预约价阶段：配置全款预约价。"
    case .inStock: return "现货阶段：配置现货价。"
    }
  }
}

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

/// 上架表单第 3 步的「款式」条目：款式名 + 该款式图 + 该款式价格。
///
/// 与衣橱**同一口径**（用户 2026-09-17）：
///   · 名称 → 写进 variant 规格组（`resolvedRole == .variant`），不在系列资料里的
///     新款式（如「蓝色 OP」）也会自建选项，衣橱 / 规格抽屉 / 筛选才认得到；
///   · 图   → 写进 `variantImageNames`，详情页按款式给图；
///   · 价格 → 写进 SKU 逐款价，选中该款式时显示该款价格（未填则回退单品价）。
nonisolated struct MidsummerListingStyle: Codable, Identifiable, Equatable, Sendable {
  var id: String
  var name: String
  /// 该款式图（`ImageManager` Images 目录内的文件名）。
  var imageFile: String?
  /// 该款式价格（元）；nil = 沿用单品价。
  var price: Int?

  init(
    id: String = UUID().uuidString.lowercased(),
    name: String,
    imageFile: String? = nil,
    price: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.imageFile = imageFile
    self.price = price
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
  // MARK: 系列级上新信息（上新工作台第 1 步「类目与信息」，2026-09-16 改版新增）
  // 全部可选 + 默认 nil：旧存档 JSON 解码不受影响（Codable 对可选字段走 decodeIfPresent）。
  /// 上新阶段（图透 / 定金 / 尾款 / 出货 / 再贩 / 现货）。
  var stageRaw: String? = nil
  /// 系列标题（时间线上展示的主标题，30 字以内）。
  var launchTitle: String? = nil
  /// 是否已知确定上新日期；false = 待定 / 团长还没公布。
  var hasKnownLaunchDate: Bool? = nil
  /// 上新日期（`hasKnownLaunchDate == true` 时有效）。
  var launchDate: Date? = nil
  /// 定金区间下限 / 上限（元）。
  var depositMin: Int? = nil
  var depositMax: Int? = nil
  var note: String
  /// 原文出处（合规必填，Apple 5.2）。留空时转 DTO 回退到系列出处。
  var sourceURL: String
  /// 该商品支持的尺码（从小到大排序展示由 DTO 层处理）。
  var sizes: [String]
  /// 关联的系列款式选项名（对应樱花小羊款式组的选项 name 全名，如「现 sk 粉色」）。
  /// 这就是「自动关联该系列的风格与数据」的锚点：规格组、款式对应图、尺码表
  /// 都按它从系列单品里继承。
  var variantOptionNames: [String]
  /// 款式条目（名 / 图 / 价）。`nil` = 旧存档（只有 `variantOptionNames`），
  /// 此时图与逐款价都拿不到，按老口径回退。
  var styles: [MidsummerListingStyle]? = nil
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

  var stage: MidsummerLaunchStage? {
    get {
      if let stage = stageRaw.flatMap(MidsummerLaunchStage.init(rawValue:)) { return stage }
      // 旧存档降级映射（2026-09-17 阶段收敛为四档前的 raw）：
      //   出货 → 现货；再贩 → 预约价；图透语义（未开卖）已不存在，置空让创作者重选。
      switch stageRaw {
      case "shipping": return .inStock
      case "rerun": return .preorder
      default: return nil
      }
    }
    set { stageRaw = newValue?.rawValue }
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

    // 款式条目：新存档带图与逐款价；旧存档（styles 为 nil）退化成「只有名字」。
    let styleEntries: [(name: String, imageFile: String?, price: Int?)] =
      styles.map { $0.map { ($0.name, $0.imageFile, $0.price) } }
      ?? variantOptionNames.map { ($0, nil, nil) }
    let styleNames = styleEntries.map(\.name)

    var groups: [MidsummerSpecGroup] = []

    // 款式组：保留关联的系列选项，**再补上系列资料里没有的新款式选项**——
    // 创作者自己新增的「蓝色 OP」不在系列款式表里，不补就进不了衣橱的款式归类。
    if let styleGroup {
      let picked = styleGroup.options.filter { styleNames.contains($0.name) }
      var options = picked
      let knownNames = Set(picked.map(\.name))
      for entry in styleEntries where !knownNames.contains(entry.name) {
        options.append(
          MidsummerSpecOption(id: "st-\(entry.name)", name: entry.name, image: entry.imageFile)
        )
      }
      if !options.isEmpty {
        groups.append(
          MidsummerSpecGroup(id: styleGroup.id, name: styleGroup.name, role: styleGroup.role, options: options)
        )
      }
    } else if !styleEntries.isEmpty {
      // 系列完全没有款式资料（自建系列）：自建款式组，口径与系列款式组一致。
      groups.append(
        MidsummerSpecGroup(
          id: "variant",
          name: "款式",
          role: .variant,
          options: styleEntries.map {
            MidsummerSpecOption(id: "st-\($0.name)", name: $0.name, image: $0.imageFile)
          }
        )
      )
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

    // 款式对应图：优先用该款式自己上传的图，没有才按商品图顺序对位
    //（图不够时循环复用，至少每款有图）。
    var variantImages: [String: String] = [:]
    for entry in styleEntries {
      if let file = entry.imageFile, !file.isEmpty { variantImages[entry.name] = file }
    }
    if !imageFiles.isEmpty {
      for (index, entry) in styleEntries.enumerated() where variantImages[entry.name] == nil {
        variantImages[entry.name] = imageFiles[index % imageFiles.count]
      }
    }

    // 尺码表：继承系列单品里与关联款式对应的条目。注意款式表 key 是短名
    // （「SK」「内搭」），而款式选项名是「现 sk 粉色」这类全名——
    // 用「全名包含短名」匹配（大小写不敏感），与详情页归组的口径同源。
    let inheritedCharts = (sourceItem?.sizeChartImages ?? [])?.filter { entry in
      let style = entry.style.lowercased()
      guard !style.isEmpty else { return false }
      return styleNames.contains { $0.lowercased().contains(style) }
    }

    // SKU 逐款价：填了价格的款式各写一条（只约束款式组，不写尺码组——
    // SKU 未提及的组不构成否决，尺码仍可自由搭配）。
    let skus: [MidsummerSKU]? = {
      guard let variantGroup = groups.first(where: { $0.resolvedRole == .variant }) else { return nil }
      let priced = styleEntries.compactMap { entry -> MidsummerSKU? in
        guard let price = entry.price else { return nil }
        let optionID =
          variantGroup.options.first(where: { $0.name == entry.name })?.id ?? "st-\(entry.name)"
        return MidsummerSKU(
          id: "style-\(optionID)",
          options: [variantGroup.id: optionID],
          image: entry.imageFile,
          price: price,
          priceKind: priceKind ?? .shop
        )
      }
      return priced.isEmpty ? nil : priced
    }()

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
      skus: skus
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
