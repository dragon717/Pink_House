import PhotosUI
import SwiftUI

// MARK: - 创作者自主上传入口
//
// 用户明确要求：「网络信息可能不完整，因此必须额外提供一个供创作者自主上传上新信息的入口」。
//
// 两种模式：
//   1. 新建系列  —— 从零录入一个上新系列（含单品）
//   2. 补录单品  —— 为已有系列补齐缺失的款 / 价格 / 尺码（`existingSeries` 非空时）
//
// 合规约束（见 docs/品牌上新资讯_开发规格.md §7）：
//   • 入口只对 admin 可见（`isAdmin()` 门控，非 admin 打开 App 完全看不到）
//   • 原文出处 sourceURL 必填 —— Apple 5.2 要求可溯源
//   • 封面图长边压到 1200px 再上传，避免吃爆 CloudKit 配额
//   • App 内不做任何爬取，图片由创作者本地选取

struct MidsummerContributeView: View {
  @ObservedObject var store: MidsummerStore
  /// 非空 → 进入「为已有系列补录」模式
  var existingSeries: MidsummerSeriesDTO?

  @Environment(\.dismiss) private var dismiss

  // 系列字段
  @State private var seriesName = ""
  @State private var hasLaunchDate = true
  @State private var launchDate = Date()
  @State private var stage: MidsummerStage = .deposit
  /// 定金区间。价格区间**不在这里填**——它由单品价格自动派生（见 buildSeries）。
  @State private var depositMinText = ""
  @State private var depositMaxText = ""
  @State private var selectedSizes: Set<String> = ["S", "M", "L", "XL"]
  @State private var colorsText = ""
  @State private var summaryText = ""
  @State private var sourceURLText = ""

  // 单品
  @State private var draftItems: [DraftItem] = [DraftItem()]

  // 封面图
  @State private var photoItem: PhotosPickerItem?
  @State private var coverImage: UIImage?

  // 提交状态
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var didSucceed = false

  private let presetSizes = ["XS", "S", "M", "L", "XL", "均码", "定制"]
  private var isSupplementMode: Bool { existingSeries != nil }

  var body: some View {
    NavigationStack {
      Form {
        // 权限提示：入口现在由「创作者模式」解锁，但**能否写入**仍由 CloudKit 的角色决定。
        // 不把这件事说在前面，使用者会在填完一整页之后才吃到失败，且不知道为什么。
        if !store.isAdminUser {
          Section {
            Label {
              Text("当前 iCloud 账户不在创作者名单中")
                .font(.system(size: 13, weight: .medium))
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MidsummerTheme.brandOrange)
            }
          } footer: {
            Text(
              "你仍可以填写并尝试提交。若提示「当前账号没有上传权限」，"
                + "说明该账户尚未被授予写入权限 —— 把它的 iCloud 账户 ID 加入 CloudKit 的"
                + "创作者角色后即可发布（参见 docs/MIDSUMMER_TALE_CLOUDKIT_SETUP.md）。"
            )
          }
        }

        if isSupplementMode, let existingSeries {
          Section {
            LabeledContent("系列", value: existingSeries.name)
            LabeledContent("当前收录", value: existingSeries.itemCountText)
            if existingSeries.launchedOn.isEmpty {
              Label("该系列上新日期待补充", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(MidsummerTheme.brandOrange)
            }
          } header: {
            Text("补录目标")
          } footer: {
            Text("提交后该系列会立即更新，无需等待云端同步。")
          }
        } else {
          Section {
            TextField("系列名，例如「小熊博物馆系列」", text: $seriesName)
          } header: {
            Text("系列名")
          }
        }

        Section {
          Toggle("已知上新日期", isOn: $hasLaunchDate)
          if hasLaunchDate {
            DatePicker("上新日期", selection: $launchDate, displayedComponents: .date)
              .environment(\.locale, Locale(identifier: "zh_CN"))
          }
          Picker("上新阶段", selection: $stage) {
            ForEach(MidsummerStage.allCases, id: \.self) { stage in
              Label(stage.labelZH, systemImage: stage.symbolName).tag(stage)
            }
          }
        } header: {
          Text("时间与阶段")
        } footer: {
          Text("公开渠道常常查不到确切日期，此时关闭上方开关即可——界面会显示「上新日期待补充」。")
        }

        Section {
          HStack {
            TextField("最低", text: $depositMinText).keyboardType(.numberPad)
            Text("–").foregroundStyle(MidsummerTheme.secondaryText)
            TextField("最高", text: $depositMaxText).keyboardType(.numberPad)
            Text("元").font(.caption).foregroundStyle(MidsummerTheme.secondaryText)
          }
        } header: {
          Text("定金区间（元）")
        } footer: {
          Text(
            "定金常以价格带形式公布（如「定金 7-139 元」），无法归到某一个单品上，所以单独填在这里。"
              + "\n\n参考价 / 现货价的区间**不用填**：它由下方每个单品的价格自动算出，"
              + "改一个单品价，区间会跟着变，不需要两处对齐。"
          )
        }

        Section {
          sizeChips
          TextField("配色，用顿号或逗号分隔，例如「粉色、蓝色」", text: $colorsText)
        } header: {
          Text("尺码与配色")
        }

        Section {
          TextEditor(text: $summaryText)
            .frame(minHeight: 72)
            .font(.system(size: 14))
        } header: {
          Text("系列简介（可选）")
        } footer: {
          Text("写清版型、柄图或联名背景，方便其他人检索。请用自己的话概括，不要直接粘贴店铺文案。")
        }

        itemsSection

        Section {
          PhotosPicker(selection: $photoItem, matching: .images) {
            HStack {
              Label("选择封面图", systemImage: "photo")
              Spacer()
              if coverImage != nil {
                Text("已选择").font(.caption).foregroundStyle(MidsummerTheme.freshGreen)
              }
            }
          }
          if let coverImage {
            Image(uiImage: coverImage)
              .resizable()
              .scaledToFill()
              .frame(height: 140)
              .frame(maxWidth: .infinity)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
        } header: {
          Text("封面图（可选）")
        } footer: {
          Text("上传后会自动压缩到长边 1200px。请只上传你有权使用的图片。")
        }

        Section {
          TextField("原文链接（微博 / 淘宝 / 小红书）", text: $sourceURLText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("原文出处（必填）")
        } footer: {
          Text("必填：内容需要可溯源，这也是商店审核的要求。请勿填写短链或无法访问的地址。")
        }

        Section {
          Button {
            Task { await submit() }
          } label: {
            HStack {
              Spacer()
              if isSubmitting {
                ProgressView().padding(.trailing, 6)
              }
              Text(isSubmitting ? "正在上传…" : "提交到线上内容库")
                .font(.system(size: 15, weight: .semibold))
              Spacer()
            }
          }
          .disabled(isSubmitting)
        } footer: {
          Text("提交后会写入 CloudKit 公共库（iCloud.bugod2.ItemManager），其他用户刷新即可看到。")
        }
      }
      .navigationTitle(isSupplementMode ? "补录单品" : "上传上新")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
        }
      }
      .onChange(of: photoItem) { _, newValue in
        Task { await loadPhoto(newValue) }
      }
      .alert("已提交", isPresented: $didSucceed) {
        Button("好") { dismiss() }
      } message: {
        Text("内容已写入公共库，其他用户刷新后即可看到。")
      }
      .alert(
        "上传失败",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("知道了", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
      .onAppear(perform: prefill)
    }
  }

  // MARK: 尺码多选

  private var sizeChips: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("可用尺码")
        .font(.system(size: 12))
        .foregroundStyle(MidsummerTheme.secondaryText)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 8)], alignment: .leading, spacing: 8) {
        ForEach(presetSizes, id: \.self) { size in
          let on = selectedSizes.contains(size)
          Button {
            if on { selectedSizes.remove(size) } else { selectedSizes.insert(size) }
          } label: {
            Text(size)
              .font(.system(size: 13, weight: on ? .semibold : .regular))
              .foregroundStyle(on ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
              // 与规格抽屉的 chip 同一种形态，复用同一个槽位（筛选胶囊）
              .themeSkinLegibleText(level: on ? .chip : .inline, slot: MidsummerThemeSlot.specOption)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 7)
              .background(on ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: 单品录入

  private var itemsSection: some View {
    Section {
      ForEach($draftItems) { $item in
        VStack(alignment: .leading, spacing: 8) {
          TextField("款名，例如「樱花小羊 SK」", text: $item.name)
            .font(.system(size: 14, weight: .medium))

          Picker("类型", selection: $item.kind) {
            ForEach(MidsummerItemKind.allCases, id: \.self) { kind in
              Text(kind.shortLabel).tag(kind)
            }
          }
          .pickerStyle(.segmented)

          HStack(spacing: 8) {
            TextField("定金", text: $item.depositText).keyboardType(.numberPad)
            TextField("尾款", text: $item.balanceText).keyboardType(.numberPad)
            TextField("现货价", text: $item.priceText).keyboardType(.numberPad)
          }
          .font(.system(size: 13))
          .textFieldStyle(.roundedBorder)

          if Int(item.priceText) != nil {
            Picker("价格口径", selection: $item.priceKind) {
              ForEach(MidsummerPriceKind.allCases, id: \.self) { kind in
                Text(kind.labelZH).tag(kind)
              }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 12))
          }

          TextField("备注（价格差异、批次、待补项说明）", text: $item.noteText)
            .font(.system(size: 12))
        }
        .padding(.vertical, 2)
      }
      .onDelete { draftItems.remove(atOffsets: $0) }

      Button {
        draftItems.append(DraftItem(inheritingSizesFrom: selectedSizes))
      } label: {
        Label("添加一个单品", systemImage: "plus.circle")
      }
    } header: {
      Text("单品（可多条）")
    } footer: {
      Text("单品尺码默认沿用上面的「可用尺码」，如需单独设置可在系列提交后再补录。")
    }
  }

  // MARK: 预填

  private func prefill() {
    guard let existingSeries else { return }
    stage = existingSeries.stage
    if !existingSeries.launchedOn.isEmpty {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.locale = Locale(identifier: "en_US_POSIX")
      if let date = formatter.date(from: existingSeries.launchedOn) {
        launchDate = date
        hasLaunchDate = true
      }
    } else {
      hasLaunchDate = false
    }
    depositMinText = existingSeries.depositMin.map(String.init) ?? ""
    depositMaxText = existingSeries.depositMax.map(String.init) ?? ""
    selectedSizes = Set(existingSeries.sizes)
    colorsText = existingSeries.colors.joined(separator: "、")
    sourceURLText = existingSeries.sourceURL
    draftItems = [DraftItem(inheritingSizesFrom: selectedSizes)]
  }

  private func loadPhoto(_ pickerItem: PhotosPickerItem?) async {
    guard let pickerItem else { return }
    do {
      if let data = try await pickerItem.loadTransferable(type: Data.self),
        let image = UIImage(data: data)
      {
        coverImage = image
      }
    } catch {
      errorMessage = "封面图读取失败，请换一张试试。"
    }
  }

  // MARK: 提交

  private func submit() async {
    errorMessage = nil

    // 校验逻辑抽到 MidsummerContributionValidator，便于单测覆盖（见 MidsummerContributeViewTests）
    if let failure = MidsummerContributionValidator.validate(
      isSupplementMode: isSupplementMode,
      seriesName: seriesName,
      sourceURLText: sourceURLText,
      itemNames: draftItems.map(\.name)
    ) {
      errorMessage = failure.message
      return
    }

    let trimmedSource = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    let validItems = draftItems.compactMap { $0.makeItem(seriesID: "", sizes: Array(selectedSizes)) }
      .filter { !$0.name.isEmpty }

    isSubmitting = true
    defer { isSubmitting = false }

    do {
      let series = buildSeries(sourceURL: trimmedSource, items: validItems)
      try await MidsummerCloudService.shared.publish(series: series, coverImage: coverImage)

      for item in series.items {
        try await MidsummerCloudService.shared.publish(item: item, coverImage: nil)
      }

      // 乐观更新：不等下一次云端刷新，界面立刻显示
      store.applyUploaded(series: series)
      didSucceed = true
    } catch let error as MidsummerUploadError {
      errorMessage = error.errorDescription
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func buildSeries(sourceURL: String, items: [MidsummerItemDTO]) -> MidsummerSeriesDTO {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let launchedOn = hasLaunchDate ? formatter.string(from: launchDate) : ""
    let year = hasLaunchDate
      ? Calendar.current.component(.year, from: launchDate)
      : (existingSeries?.year ?? Calendar.current.component(.year, from: Date()))

    let base = existingSeries
    let id = base?.id ?? "midsummer-\(year)-\(UUID().uuidString.prefix(8).lowercased())"

    let colors = colorsText
      .components(separatedBy: CharacterSet(charactersIn: "、,，/"))
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    let attachedItems = items.map { item -> MidsummerItemDTO in
      MidsummerItemDTO(
        id: item.id.isEmpty
          ? "\(id)-\(UUID().uuidString.prefix(6).lowercased())"
          : item.id,
        seriesID: id,
        name: item.name,
        kind: item.kind,
        price: item.price,
        deposit: item.deposit,
        balance: item.balance,
        priceKind: item.priceKind,
        priceCapturedOn: item.priceCapturedOn,
        priceNote: item.priceNote,
        sizes: item.sizes,
        colors: item.colors,
        coverImage: nil,
        itemURL: item.itemURL,
        sourceURL: item.sourceURL.isEmpty ? sourceURL : item.sourceURL,
        note: item.note,
        specGroups: item.specGroups,
        skus: item.skus
      )
    }

    // 补录模式下沿用原系列已有单品，避免整体替换把历史款抹掉
    let mergedItems = (base?.items ?? []) + attachedItems

    return MidsummerSeriesDTO(
      id: id,
      name: base?.name ?? seriesName.trimmingCharacters(in: .whitespacesAndNewlines),
      year: year,
      launchedOn: launchedOn.isEmpty ? (base?.launchedOn ?? "") : launchedOn,
      stage: stage,
      coverImage: base?.coverImage,
      // 价格区间不在这里算也不再存储：`MidsummerSeriesDTO.priceRange` 会从
      // mergedItems（含每个 SKU 的逐款价）派生，所以这里是唯一一处需要维护的价格数据。
      depositMin: Int(depositMinText) ?? base?.depositMin,
      depositMax: Int(depositMaxText) ?? base?.depositMax,
      priceSource: (Int(depositMinText) != nil || Int(depositMaxText) != nil)
        ? "创作者填写的定金区间"
        : base?.priceSource,
      sizes: Array(selectedSizes).sorted(),
      colors: colors,
      summary: summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? base?.summary
        : summaryText.trimmingCharacters(in: .whitespacesAndNewlines),
      sourceURL: sourceURL,
      sourceKind: "editorial",
      verified: true,
      items: mergedItems
    )
  }
}

// MARK: - 提交校验（抽出来是为了能被单测直接覆盖）
//
// 三条硬规则，对应 docs 里的合规要求与用户对「每个系列含图片/价格/尺码」的验收点：
//   1. 新建系列必须有名字
//   2. 原文出处必须合法可溯源（Apple 5.2）
//   3. 必须至少有一个单品 —— 系列页要展示图片/价格/尺码，空系列无法承载这些信息

nonisolated enum MidsummerContributeFailure: Equatable {
  case missingSeriesName
  case invalidSourceURL
  case noItems

  var message: String {
    switch self {
    case .missingSeriesName:
      return "请填写系列名。"
    case .invalidSourceURL:
      return "请填写有效的原文链接（需以 http:// 或 https:// 开头）。"
    case .noItems:
      return "请至少填写一个单品——系列页需要展示图片、价格与尺码。"
    }
  }
}

nonisolated enum MidsummerContributionValidator {
  static func validate(
    isSupplementMode: Bool,
    seriesName: String,
    sourceURLText: String,
    itemNames: [String]
  ) -> MidsummerContributeFailure? {
    // 补录模式沿用已有系列名，不要求重填
    if !isSupplementMode,
      seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return .missingSeriesName
    }

    let raw = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: raw),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      url.host != nil
    else {
      return .invalidSourceURL
    }

    let hasNamedItem = itemNames.contains {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if !isSupplementMode && !hasNamedItem {
      return .noItems
    }

    return nil
  }
}

// MARK: - 单品草稿

struct DraftItem: Identifiable {
  let id = UUID()
  var name = ""
  var kind: MidsummerItemKind = .op
  var depositText = ""
  var balanceText = ""
  var priceText = ""
  /// `priceText` 的口径。填了价就必须选一个——否则界面只能猜这个数字是什么，
  /// 这也是价格数据「看起来有、实际不可信」的根源之一。
  var priceKind: MidsummerPriceKind = .reference
  var noteText = ""
  var sizes: [String] = []

  init() {}

  init(inheritingSizesFrom sizes: Set<String>) {
    self.sizes = Array(sizes).sorted()
  }

  func makeItem(seriesID: String, sizes fallbackSizes: [String]) -> MidsummerItemDTO? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return MidsummerItemDTO(
      id: "",
      seriesID: seriesID,
      name: trimmed,
      kind: kind,
      price: Int(priceText),
      deposit: Int(depositText),
      balance: Int(balanceText),
      // 口径只在真的填了「现货价 / 参考价」时才有意义；没填就留空，
      // 免得把一个口径挂在没有价格的条目上。
      priceKind: Int(priceText) == nil ? nil : priceKind,
      priceCapturedOn: Int(priceText) == nil ? nil : Self.todayStamp(),
      priceNote: nil,
      sizes: sizes.isEmpty ? fallbackSizes.sorted() : sizes,
      colors: [],
      coverImage: nil,
      itemURL: nil,
      sourceURL: "",
      note: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText,
      // 投稿表单还没有规格输入：新建的单品一律「无规格」。
      // 需要带规格时请改 Bundle 种子，或先补上传表单（见文档「待办」）。
      specGroups: nil,
      skus: nil
    )
  }

  /// 采集日期戳（`yyyy-MM-dd`）。价格会变，没采集日的价格无法判断是否过期，
  /// 所以这里由 App 自动打戳，不依赖填表人记得写。
  private static func todayStamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: Date())
  }
}
