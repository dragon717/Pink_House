import PhotosUI
import SwiftUI

// MARK: - 上新工作台（樱花小羊系列 · 用户 2026-09-16）
//
// 围绕单个系列的「商品上传上新系统」，与衣橱深度结合：
//   · 录入：名称 / 分类 / 关联款式 / 尺码 / 价格四档 / 备注 / 出处；
//   · 图片：主图宫格（最多 5 张，第 1 张为主图），落盘 ImageManager Images 目录；
//   · 预览：发布前按「系列卡片同款口径」预演名称 / 价格 / 规格；
//   · 状态管理：草稿 → 已上架 ⇄ 已下架，上架商品自动并入系列 feed——
//     品牌页卡片、详情页、规格抽屉、一键入库（含多选配一套）全部走既有链路。
//
// 入口：系列详情页「上新管理」（`store.canContribute` 门控，与投稿入口同一套
// 三态闸门；模拟器里用「创作者模式」开关或 UI 测试启动参数解闸）。
// 视觉全部复用 MidsummerTheme 与投稿表单（MidsummerContributeView）的组件形态：
// wizardCard 白卡、橙色主按钮、chip 多选、主图宫格，保证界面风格统一。

struct MidsummerListingWorkspaceView: View {
  @ObservedObject var store: MidsummerStore
  let series: MidsummerSeriesDTO

  @ObservedObject private var listingStore = MidsummerListingStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var editingListing: MidsummerListing?
  @State private var showingForm = false
  @State private var toast: String?

  private var seriesListings: [MidsummerListing] { listingStore.sortedListings.filter { $0.seriesID == series.id } }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
          publishCard
          if let toast {
            Text(toast)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.freshGreen)
              .frame(maxWidth: .infinity, alignment: .leading)
              .transition(.opacity)
          }
          if seriesListings.isEmpty {
            emptyState
          } else {
            ForEach(seriesListings) { listing in
              listingRow(listing)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .background(MidsummerTheme.pageBackground)
      .navigationTitle("上新管理")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("完成") { dismiss() }
        }
      }
      .sheet(isPresented: $showingForm) {
        MidsummerListingFormView(store: store, series: series)
      }
      .sheet(item: $editingListing) { listing in
        MidsummerListingFormView(store: store, series: series, existing: listing)
      }
      .animation(.easeOut(duration: 0.18), value: toast)
    }
  }

  // MARK: 发布入口卡

  private var publishCard: some View {
    Button {
      editingListing = nil
      showingForm = true
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "plus.square.on.square")
          .font(.system(size: 16, weight: .medium))
        VStack(alignment: .leading, spacing: 2) {
          Text("发布新商品")
            .font(.system(size: 14, weight: .semibold))
          Text("录入 → 图片 → 预览上架；上架后自动进入「\(series.name)」并可一键加入衣橱")
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.onAccent.opacity(0.85))
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(MidsummerTheme.onAccent)
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MidsummerTheme.brandOrange)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("listing-open-form")
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "shippingbox")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Text("还没有上新记录")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Text("点上方「发布新商品」开始第一次上新。")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  // MARK: listing 行

  private func listingRow(_ listing: MidsummerListing) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Group {
        if let cover = listing.imageFiles.first,
          let image = ImageManager.shared.loadImage(fileName: cover)
        {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          ZStack {
            MidsummerTheme.subtleFill
            Image(systemName: "photo")
              .font(.system(size: 14, weight: .light))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
        }
      }
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          statusChip(listing.status)
          Text(listing.name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(2)
        }
        Text("\(listing.kind.shortLabel) · \(listing.priceSummary) · 关联 \(listing.variantOptionNames.count) 个款式")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      // 行内主操作：编辑（状态与危险操作收进菜单，避免误触）。
      Button {
        editingListing = listing
      } label: {
        Text("编辑")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("listing-edit-\(listing.id)")

      Menu {
        switch listing.status {
        case .draft, .delisted:
          Button("上架") { listingStore.updateStatus(of: listing.id, to: .listed) }
            .accessibilityIdentifier("listing-menu-list-\(listing.id)")
        case .listed:
          Button("下架") { listingStore.updateStatus(of: listing.id, to: .delisted) }
            .accessibilityIdentifier("listing-menu-delist-\(listing.id)")
        }
        Button("删除", role: .destructive) {
          listingStore.delete(listing.id)
          showToast("已删除「\(listing.name)」")
        }
        .accessibilityIdentifier("listing-menu-delete-\(listing.id)")
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 16))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
      .accessibilityIdentifier("listing-more-\(listing.id)")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 12,
      showsDecoration: false
    ) {
      MidsummerTheme.surface
    }
  }

  private func statusChip(_ status: MidsummerListingStatus) -> some View {
    let color: Color = {
      switch status {
      case .draft: return MidsummerTheme.secondaryText
      case .listed: return MidsummerTheme.freshGreen
      case .delisted: return MidsummerTheme.brandOrange
      }
    }()
    return Text(status.labelZH)
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
  }

  private func showToast(_ message: String) {
    toast = message
    Task {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }
  }
}

// MARK: - 上新表单（录入 → 图片 → 预览发布）

struct MidsummerListingFormView: View {
  @ObservedObject var store: MidsummerStore
  let series: MidsummerSeriesDTO
  /// 非空 = 编辑模式（预填并保留原状态）。
  var existing: MidsummerListing?

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var listingStore = MidsummerListingStore.shared

  private enum FormStep: Int, CaseIterable {
    case basics = 0
    case images = 1
    case review = 2

    var title: String {
      switch self {
      case .basics: return "基本信息"
      case .images: return "商品图片"
      case .review: return "预览发布"
      }
    }

    var stepTitle: String {
      switch self {
      case .basics: return "① 商品信息录入"
      case .images: return "② 上传商品图片"
      case .review: return "③ 预览与发布"
      }
    }
  }

  @State private var step: FormStep = .basics
  @State private var stepError: String?

  // 基本信息
  @State private var name = ""
  @State private var kind: MidsummerItemKind = .op
  @State private var pickedStyleNames: Set<String> = []
  @State private var pickedSizes: Set<String> = []
  @State private var priceText = ""
  @State private var preorderPriceText = ""
  @State private var depositText = ""
  @State private var balanceText = ""
  @State private var priceKind: MidsummerPriceKind = .shop
  @State private var noteText = ""
  @State private var sourceURLText = ""

  // 图片
  @State private var images: [UIImage] = []
  @State private var addPhotoItem: PhotosPickerItem?
  @State private var replaceIndex: Int?
  @State private var replacePhotoItem: PhotosPickerItem?
  @State private var imageError: String?

  private let maxImages = 5
  private let presetSizes = ["XS", "S", "M", "L", "XL", "XXL", "F"]

  /// 系列款式组（樱花小羊主条目里的「颜色分类」组）。
  private var sourceItem: MidsummerItemDTO? { series.items.first }
  private var styleGroup: MidsummerSpecGroup? {
    (sourceItem?.specGroups ?? []).first { $0.resolvedRole == .variant }
  }
  private var sizeGroup: MidsummerSpecGroup? {
    (sourceItem?.specGroups ?? []).first { $0.resolvedRole == .size }
  }
  /// 尺码候选：预设 + 系列已有尺码，去重。
  private var sizeChoices: [String] {
    var seen = Set<String>()
    let fromSeries = sizeGroup?.options.map(\.name) ?? []
    return (presetSizes + fromSeries).filter { seen.insert($0).inserted }
  }
  private var isEditMode: Bool { existing != nil }

  init(store: MidsummerStore, series: MidsummerSeriesDTO, existing: MidsummerListing? = nil) {
    self.store = store
    self.series = series
    self.existing = existing
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        stepHeader
        Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)

        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            Text(step.stepTitle)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(MidsummerTheme.primaryText)
            if let stepError {
              Label(stepError, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MidsummerTheme.priceRed)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MidsummerTheme.orangeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("listing-step-error")
            }
            stepContent
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .background(MidsummerTheme.pageBackground)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Text(series.name)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .lineLimit(1)
        }
      }
      .safeAreaInset(edge: .bottom) {
        bottomBar
      }
      .onChange(of: addPhotoItem) { _, newValue in
        loadPicker(newValue, failureMessage: "商品图读取失败，请换一张试试。") { image in
          guard let image, images.count < maxImages else { return }
          images.append(image)
        }
        addPhotoItem = nil
      }
      .onChange(of: replacePhotoItem) { _, newValue in
        loadPicker(newValue, failureMessage: "商品图读取失败，请换一张试试。") { image in
          guard let image, let index = replaceIndex, images.indices.contains(index) else { return }
          images[index] = image
        }
        replaceIndex = nil
        replacePhotoItem = nil
      }
      .onAppear { prefill() }
    }
  }

  // MARK: 步骤条（与投稿表单同一形态）

  private var stepHeader: some View {
    HStack(alignment: .center, spacing: 0) {
      ForEach(FormStep.allCases, id: \.self) { wizardStep in
        if wizardStep.rawValue > 0 {
          Rectangle()
            .fill(wizardStep.rawValue <= step.rawValue ? MidsummerTheme.brandOrange : MidsummerTheme.divider)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
        }
        let isCurrent = wizardStep == step
        HStack(spacing: 5) {
          ZStack {
            Circle()
              .fill(isCurrent ? MidsummerTheme.brandOrange : MidsummerTheme.subtleFill)
              .frame(width: 22, height: 22)
            Text("\(wizardStep.rawValue + 1)")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(isCurrent ? MidsummerTheme.onAccent : MidsummerTheme.secondaryText)
          }
          Text(wizardStep.title)
            .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
        }
        .accessibilityIdentifier("listing-step-\(wizardStep.rawValue)")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(MidsummerTheme.surface)
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .basics: basicsStep
    case .images: imagesStep
    case .review: reviewStep
    }
  }

  private var bottomBar: some View {
    VStack(spacing: 0) {
      Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)
      HStack(spacing: 10) {
        if step != .basics {
          Button {
            withAnimation(.snappy(duration: 0.18)) {
              step = FormStep(rawValue: step.rawValue - 1) ?? .basics
              stepError = nil
            }
          } label: {
            Text("上一步")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(MidsummerTheme.primaryText)
              .frame(height: 42)
              .frame(width: 96)
              .background(MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .accessibilityIdentifier("listing-back")
        }

        Button {
          advance()
        } label: {
          Text(step == .review ? (isEditMode ? "保存修改" : "发布上架") : "下一步")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MidsummerTheme.onAccent)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .background(MidsummerTheme.brandOrange)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .themeSkinLegibleText(level: .hero, slot: MidsummerThemeSlot.primaryButton)
        }
        .accessibilityIdentifier(step == .review ? "listing-publish" : "listing-next")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(MidsummerTheme.surface)
    }
  }

  private func advance() {
    if let failure = validateCurrentStep() {
      stepError = failure
      return
    }
    stepError = nil
    if step == .review {
      submit()
    } else {
      withAnimation(.snappy(duration: 0.18)) {
        step = FormStep(rawValue: step.rawValue + 1) ?? .review
      }
    }
  }

  private func validateCurrentStep() -> String? {
    switch step {
    case .basics:
      if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "请填写商品名称。"
      }
      if pickedStyleNames.isEmpty {
        return "请至少关联一个款式——上架后按款式进入系列规格与尺码表。"
      }
      let trimmed = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        guard let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          url.host != nil
        else {
          return "原文出处需以 http:// 或 https:// 开头（可回退使用系列出处，直接留空即可）。"
        }
      }
      return nil
    case .images, .review:
      return nil
    }
  }

  // MARK: ① 基本信息录入

  private var basicsStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard("商品名称", hint: "同一个系列里的商品名不要重复，例如「樱花小羊 开衫」。") {
        TextField("商品名称", text: $name)
          .font(.system(size: 14))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-name")
      }

      wizardCard("商品分类", hint: "决定商品在系列页的分组与图标。") {
        Picker("分类", selection: $kind) {
          ForEach(MidsummerItemKind.allCases, id: \.self) { candidate in
            Text(candidate.labelZH).tag(candidate)
          }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("listing-kind")
      }

      wizardCard(
        "关联款式（自动继承系列资料）",
        hint: "勾选后自动继承该款式的规格选项、款式对应图与尺码表；可多选（一个商品含多款时）。"
      ) {
        if let styleGroup {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
            ForEach(styleGroup.options) { option in
              let on = pickedStyleNames.contains(option.name)
              Button {
                if on { pickedStyleNames.remove(option.name) } else { pickedStyleNames.insert(option.name) }
              } label: {
                Text(Self.displayStyleName(option.name))
                  .font(.system(size: 11, weight: on ? .semibold : .regular))
                  .foregroundStyle(on ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
                  .themeSkinLegibleText(level: on ? .chip : .inline, slot: MidsummerThemeSlot.specOption)
                  .lineLimit(1)
                  .minimumScaleFactor(0.75)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
                  .background(on ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
                  .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                  .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                      .stroke(on ? MidsummerTheme.brandOrange : Color.clear, lineWidth: 1)
                  )
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("listing-style-\(option.id)")
              .accessibilityLabel(Self.displayStyleName(option.name))
            }
          }
        } else {
          Text("该系列暂无款式资料，商品将以无规格单品上架（仍可一键加入衣橱）。")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
      }

      wizardCard("支持尺码", hint: "小物可不选——上架后不出现尺码组。") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(sizeChoices, id: \.self) { size in
            let on = pickedSizes.contains(size)
            Button {
              if on { pickedSizes.remove(size) } else { pickedSizes.insert(size) }
            } label: {
              Text(size)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(on ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listing-size-\(size)")
          }
        }
      }

      wizardCard("价格（元）", hint: "按经营方式选填；现货价的口径在下方选择。") {
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            priceField("现货价", text: $priceText, identifier: "listing-price")
            priceField("预约价（全款预约）", text: $preorderPriceText, identifier: "listing-preorder")
          }
          HStack(spacing: 8) {
            priceField("定金", text: $depositText, identifier: "listing-deposit")
            priceField("尾款", text: $balanceText, identifier: "listing-balance")
          }
        }
        if Int(priceText) != nil {
          Picker("现货价口径", selection: $priceKind) {
            ForEach(MidsummerPriceKind.allCases, id: \.self) { candidate in
              Text(candidate.labelZH).tag(candidate)
            }
          }
          .pickerStyle(.segmented)
          .font(.system(size: 12))
        }
      }

      wizardCard("备注与出处", hint: nil) {
        TextField("备注（批次、待补项说明）", text: $noteText)
          .font(.system(size: 12))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-note")

        TextField("原文出处（可选，留空沿用系列出处）", text: $sourceURLText)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.system(size: 12))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-source")
      }
    }
  }

  private func priceField(_ title: String, text: Binding<String>, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
      TextField("0", text: text)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 14, weight: .medium))
        .padding(.vertical, 7)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityIdentifier(identifier)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: ② 商品图片

  private var imagesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard(
        "主图宫格（最多 \(maxImages) 张）",
        hint: "第 1 张为主图：上架后用作系列卡片与详情页封面；点图替换、右上角 × 删除、非主图可「设为主图」。"
      ) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(images.indices, id: \.self) { index in
            imageCell(index)
          }
          if images.count < maxImages {
            PhotosPicker(selection: $addPhotoItem, matching: .images) {
              VStack(spacing: 3) {
                Image(systemName: "plus")
                  .font(.system(size: 18, weight: .medium))
                Text("添加主图")
                  .font(.system(size: 10))
                Text("\(images.count)/\(maxImages)")
                  .font(.system(size: 9))
                  .foregroundStyle(MidsummerTheme.secondaryText)
              }
              .foregroundStyle(MidsummerTheme.secondaryText)
              .frame(height: 88)
              .frame(maxWidth: .infinity)
              .background(MidsummerTheme.subtleFill)
              .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .strokeBorder(MidsummerTheme.divider, style: StrokeStyle(lineWidth: 1, dash: [4]))
              )
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityIdentifier("listing-image-add")
          }
        }
        if let imageError {
          Text(imageError)
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.brandOrange)
        }
      }
    }
  }

  private func imageCell(_ index: Int) -> some View {
    ZStack(alignment: .topTrailing) {
      PhotosPicker(selection: $replacePhotoItem, matching: .images) {
        Image(uiImage: images[index])
          .resizable()
          .scaledToFill()
          .frame(height: 88)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .simultaneousGesture(TapGesture().onEnded { replaceIndex = index })
      .accessibilityIdentifier("listing-image-cell-\(index)")

      Button {
        _ = images.remove(at: index)
        imageError = nil
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.white)
          .shadow(radius: 2)
      }
      .accessibilityIdentifier("listing-image-delete-\(index)")
    }
    .overlay(alignment: .bottomLeading) {
      if index == 0 {
        Text("主图")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(MidsummerTheme.brandOrange)
          .clipShape(Capsule())
          .padding(4)
      } else {
        Button {
          withAnimation(.snappy(duration: 0.16)) {
            let image = images.remove(at: index)
            images.insert(image, at: 0)
          }
        } label: {
          Text("设为主图")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(4)
        }
        .accessibilityIdentifier("listing-image-setmain-\(index)")
      }
    }
  }

  // MARK: ③ 预览与发布

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard("商品预览", hint: "按系列卡片同款口径预演；上架后立即生效。") {
        HStack(spacing: 10) {
          Group {
            if let image = images.first {
              Image(uiImage: image).resizable().scaledToFill()
            } else {
              ZStack {
                MidsummerTheme.subtleFill
                Image(systemName: "photo")
                  .font(.system(size: 14, weight: .light))
                  .foregroundStyle(MidsummerTheme.secondaryText)
              }
            }
          }
          .frame(width: 64, height: 64)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

          VStack(alignment: .leading, spacing: 4) {
            Text(name.isEmpty ? "（未命名商品）" : name)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(MidsummerTheme.primaryText)
            Text("\(kind.shortLabel) · \(priceSummaryText)")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(MidsummerTheme.priceRed)
            Text(specSummary)
              .font(.system(size: 10))
              .foregroundStyle(MidsummerTheme.secondaryText)
              .lineLimit(2)
          }
          Spacer(minLength: 0)
        }
      }

      wizardCard("继承的系列资料", hint: nil) {
        LabeledContent("关联款式", value: styleSummary)
        LabeledContent("尺码", value: pickedSizes.sorted().joined(separator: " / ").isEmpty ? "（无）" : pickedSizes.sorted().joined(separator: " / "))
        if let charts = sourceItem?.sizeChartImages, !charts.isEmpty {
          let inherited = charts.filter { pickedStyleNames.contains($0.style) || pickedStyleNames.map({ $0.lowercased() }).contains($0.style.lowercased()) }
          LabeledContent("随附尺码表", value: inherited.isEmpty ? "待补充" : "\(inherited.count) 张")
        }
        LabeledContent("状态", value: isEditMode ? (existing?.status.labelZH ?? "草稿") + "（保持不变）" : "发布后：已上架")
      }

      if isEditMode {
        Text("编辑模式：保存后保持原状态；需要改变上下架状态请在列表行的菜单里操作。")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
    }
  }

  private var priceSummaryText: String {
    if let price = Int(priceText) { return "\(priceKind.labelZH) ¥\(price)" }
    if let preorder = Int(preorderPriceText) { return "预约价 ¥\(preorder)" }
    let deposit = Int(depositText), balance = Int(balanceText)
    if deposit != nil || balance != nil {
      return [deposit.map { "定金 ¥\($0)" }, balance.map { "尾款 ¥\($0)" }].compactMap { $0 }.joined(separator: " + ")
    }
    return "价格待填"
  }

  private var styleSummary: String {
    pickedStyleNames.map(Self.displayStyleName).sorted().joined(separator: "、")
  }

  private var specSummary: String {
    var parts: [String] = []
    if !pickedStyleNames.isEmpty { parts.append("关联 \(pickedStyleNames.count) 个款式") }
    if !pickedSizes.isEmpty { parts.append("尺码 \(pickedSizes.sorted().joined(separator: "/"))") }
    return parts.isEmpty ? "无规格（可直接入库）" : parts.joined(separator: " · ")
  }

  // MARK: 提交

  private func submit() {
    let id = existing?.id ?? MidsummerListing.newID()
    var listing = existing ?? MidsummerListing(
      id: id,
      seriesID: series.id,
      name: "",
      kindRaw: kind.rawValue,
      price: nil,
      preorderPrice: nil,
      deposit: nil,
      balance: nil,
      priceKindRaw: nil,
      note: "",
      sourceURL: "",
      sizes: [],
      variantOptionNames: [],
      imageFiles: [],
      status: .draft,
      createdAt: Date(),
      updatedAt: Date(),
      listedAt: nil
    )
    listing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    listing.kind = kind
    listing.price = Int(priceText)
    listing.preorderPrice = Int(preorderPriceText)
    listing.deposit = Int(depositText)
    listing.balance = Int(balanceText)
    listing.priceKind = Int(priceText) == nil ? nil : priceKind
    listing.note = noteText
    listing.sourceURL = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    listing.sizes = pickedSizes.sorted()
    listing.variantOptionNames = styleGroup?.options.filter { pickedStyleNames.contains($0.name) }.map(\.name) ?? []

    // 图片落盘（主图在前）；编辑时宫格为空则保留原图（没有动图 ≠ 清图）。
    let savedNames = listingStore.saveImages(images, listingID: id)
    if !savedNames.isEmpty || !images.isEmpty {
      listing.imageFiles = savedNames
    }

    if !isEditMode {
      listing.status = .listed
      listing.listedAt = Date()
    }
    listingStore.upsert(listing)
    dismiss()
  }

  // MARK: 预填 / 工具

  private func prefill() {
    guard let existing else {
      sourceURLText = ""
      return
    }
    name = existing.name
    kind = existing.kind
    pickedStyleNames = Set(existing.variantOptionNames)
    pickedSizes = Set(existing.sizes)
    priceText = existing.price.map(String.init) ?? ""
    preorderPriceText = existing.preorderPrice.map(String.init) ?? ""
    depositText = existing.deposit.map(String.init) ?? ""
    balanceText = existing.balance.map(String.init) ?? ""
    priceKind = existing.priceKind ?? .shop
    noteText = existing.note
    sourceURLText = existing.sourceURL == series.sourceURL ? "" : existing.sourceURL
    images = existing.imageFiles.compactMap { ImageManager.shared.loadImage(fileName: $0) }
  }

  private func loadPicker(
    _ pickerItem: PhotosPickerItem?,
    failureMessage: String,
    apply: @escaping (UIImage?) -> Void
  ) {
    guard let pickerItem else { return }
    Task {
      do {
        if let data = try await pickerItem.loadTransferable(type: Data.self) {
          apply(UIImage(data: data))
        } else {
          apply(nil)
          imageError = failureMessage
        }
      } catch {
        apply(nil)
        imageError = failureMessage
      }
    }
  }

  /// 款式展示名：剥「现 」前缀（与规格抽屉同口径），数据层仍用全名。
  static func displayStyleName(_ name: String) -> String {
    name.hasPrefix("现 ") ? String(name.dropFirst("现 ".count)) : name
  }

  // MARK: 通用白卡（与投稿表单同款）

  private func wizardCard(
    _ title: String,
    hint: String?,
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
      content()
      if let hint {
        Text(hint)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 14,
      showsDecoration: true
    ) {
      MidsummerTheme.surface
    }
  }
}
