import PhotosUI
import SwiftUI

// MARK: - 上新工作台（樱花小羊系列 · 用户 2026-09-16）
//
// 围绕单个系列的「商品上传上新系统」，与衣橱深度结合：
//   · 录入：名称 / 分类 / 关联款式 / 尺码 / 价格四档 / 备注 / 出处；
//   · 图片：主图宫格（最多 5 张，第 1 张为主图），落盘 ImageManager Images 目录；
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
          Text("主图 → 阶段 → 尺码 → 单品与价格；上架后自动进入「\(series.name)」并可一键加入衣橱")
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

// MARK: - 上新表单（系列主图与信息 → 上新阶段 → 尺码信息 → 单品与价格）
//
// 2026-09-16 晚按用户二次改版重排（原 4 步「类目与信息/系列主图/单品与价格/
// 预览提交」融合重组，不再保留旧 1234 划分）：
//   ① 系列主图与信息：上传系列主图 + 系列标题 + 已知上新日期；
//   ② 选择上新阶段：图透 / 定金 / 尾款 / 出货 / 再贩 / 现货；
//   ③ 尺码信息：可用尺码（小物可不选）；
//   ④ 单品与价格：商品名称 / 分类 / 关联款式 / 价格——价格项与第 2 步的
//     阶段联动（现货价 / 预约价 / 定金 / 尾款 按阶段显示，定金与尾款可按需配置）。
//   · 顶栏「取消 / 存草稿」：任意一步可存草稿续传；
//   · 最后一步直接「发布上架」，必填项逐步校验（标题 / 阶段 / 名称 / 关联款式）。

struct MidsummerListingFormView: View {
  @ObservedObject var store: MidsummerStore
  let series: MidsummerSeriesDTO
  /// 非空 = 编辑模式（预填并保留原状态）。
  var existing: MidsummerListing?

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var listingStore = MidsummerListingStore.shared

  private enum FormStep: Int, CaseIterable {
    case seriesInfo = 0  // ① 系列主图与信息
    case stage = 1       // ② 选择上新阶段
    case sizes = 2       // ③ 尺码信息
    case items = 3       // ④ 单品与价格

    var title: String {
      switch self {
      case .seriesInfo: return "主图与信息"
      case .stage: return "上新阶段"
      case .sizes: return "尺码信息"
      case .items: return "单品与价格"
      }
    }

    var sectionTitle: String {
      switch self {
      case .seriesInfo: return "① 上传系列主图与基本信息"
      case .stage: return "② 选择上新阶段"
      case .sizes: return "③ 设置尺码信息"
      case .items: return "④ 设置单品与价格"
      }
    }
  }

  @State private var step: FormStep = .seriesInfo
  @State private var stepError: String?

  // ① 系列主图与信息
  @State private var launchTitle = ""
  @State private var hasKnownLaunchDate = false
  @State private var launchDate = Date()
  @State private var noteText = ""

  // ② 上新阶段
  @State private var stage: MidsummerLaunchStage?

  // ③ 尺码信息
  @State private var pickedSizes: Set<String> = []

  // ④ 单品与价格
  @State private var name = ""
  @State private var kind: MidsummerItemKind = .op
  @State private var pickedStyleNames: Set<String> = []
  @State private var priceText = ""
  @State private var preorderPriceText = ""
  @State private var depositText = ""
  @State private var balanceText = ""
  @State private var depositMinText = ""
  @State private var depositMaxText = ""
  @State private var priceKind: MidsummerPriceKind = .shop
  @State private var sourceURLText = ""

  // 主图宫格
  @State private var images: [UIImage] = []
  @State private var addPhotoItem: PhotosPickerItem?
  @State private var replaceIndex: Int?
  @State private var replacePhotoItem: PhotosPickerItem?
  @State private var imageError: String?

  private let maxImages = 5
  /// 可用尺码候选：固定 7 项（XS/S/M/L/XL/均码/定制）。
  private let presetSizes = ["XS", "S", "M", "L", "XL", "均码", "定制"]

  /// 系列款式组（樱花小羊主条目里的「颜色分类」组）。
  private var sourceItem: MidsummerItemDTO? { series.items.first }
  private var styleGroup: MidsummerSpecGroup? {
    (sourceItem?.specGroups ?? []).first { $0.resolvedRole == .variant }
  }

  private var isEditMode: Bool { existing != nil }

  init(store: MidsummerStore, series: MidsummerSeriesDTO, existing: MidsummerListing? = nil) {
    self.store = store
    self.series = series
    self.existing = existing
  }

  var body: some View {
    VStack(spacing: 0) {
      topBar
      stepHeader
      Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text(step.sectionTitle)
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

  // MARK: 顶栏（取消 / 存草稿）

  private var topBar: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Text("取消")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
          .padding(.horizontal, 18)
          .padding(.vertical, 9)
          .overlay(Capsule().stroke(MidsummerTheme.divider, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("listing-cancel")

      Spacer()

      Button {
        saveDraft()
      } label: {
        Text("存草稿")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MidsummerTheme.accentPink)
          .padding(.horizontal, 18)
          .padding(.vertical, 9)
          .overlay(Capsule().stroke(MidsummerTheme.divider, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("listing-save-draft")
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  // MARK: 步骤条（4 节点 · 双行标签）

  private var stepHeader: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(FormStep.allCases, id: \.self) { wizardStep in
        if wizardStep.rawValue > 0 {
          Rectangle()
            .fill(wizardStep.rawValue <= step.rawValue ? MidsummerTheme.brandOrange : MidsummerTheme.divider)
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .padding(.top, 11)
        }
        let isCurrent = wizardStep == step
        VStack(spacing: 4) {
          ZStack {
            Circle()
              .fill(isCurrent ? MidsummerTheme.brandOrange : MidsummerTheme.subtleFill)
              .frame(width: 22, height: 22)
            Text("\(wizardStep.rawValue + 1)")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(isCurrent ? MidsummerTheme.onAccent : MidsummerTheme.secondaryText)
          }
          Text(wizardStep.title)
            .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("listing-step-\(wizardStep.rawValue)")
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .padding(.bottom, 10)
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .seriesInfo: seriesInfoStep
    case .stage: stageStep
    case .sizes: sizesStep
    case .items: itemsStep
    }
  }

  private var bottomBar: some View {
    HStack(spacing: 10) {
      if step != .seriesInfo {
        Button {
          withAnimation(.snappy(duration: 0.18)) {
            step = FormStep(rawValue: step.rawValue - 1) ?? .seriesInfo
            stepError = nil
          }
        } label: {
          Text("上一步")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .frame(height: 46)
            .frame(width: 96)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityIdentifier("listing-back")
      }

      Button {
        advance()
      } label: {
        Text(step == .items ? (isEditMode ? "保存修改" : "发布上架") : "下一步")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MidsummerTheme.onAccent)
          .frame(height: 46)
          .frame(maxWidth: .infinity)
          .background(MidsummerTheme.brandOrange)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .themeSkinLegibleText(level: .hero, slot: MidsummerThemeSlot.primaryButton)
      }
      .accessibilityIdentifier(step == .items ? "listing-publish" : "listing-next")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private func advance() {
    if let failure = validateCurrentStep() {
      stepError = failure
      return
    }
    stepError = nil
    if step == .items {
      submit()
    } else {
      withAnimation(.snappy(duration: 0.18)) {
        step = FormStep(rawValue: step.rawValue + 1) ?? .items
      }
    }
  }

  private func validateCurrentStep() -> String? {
    switch step {
    case .seriesInfo:
      let title = launchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      if title.isEmpty {
        return "请填写系列标题。"
      }
      if title.count > 30 {
        return "系列标题请控制在 30 字以内。"
      }
      return nil
    case .stage:
      if stage == nil {
        return "请选择上新阶段——选错阶段会让系列出现在错误的时间线上。"
      }
      return nil
    case .sizes:
      return nil
    case .items:
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
    }
  }

  // MARK: ① 系列主图与信息

  private var seriesInfoStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard(
        "系列主图宫格（最多 \(maxImages) 张）",
        hint: "第 1 张为主图：上架后用作系列卡片与详情页封面；点图替换、右上角 × 删除、非主图可「设为主图」。"
      ) {
        imageGrid
      }

      wizardCard("系列标题", hint: "相当于宝贝标题，30 字以内。写清系列主题，方便他人检索。") {
        TextField("系列名，例如「小熊博物馆系列」", text: $launchTitle)
          .font(.system(size: 14))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-launch-title")

        HStack(spacing: 10) {
          Text("已知上新日期")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
          Spacer(minLength: 0)
          Toggle("", isOn: $hasKnownLaunchDate)
            .labelsHidden()
            .tint(MidsummerTheme.accentPink)
            .accessibilityIdentifier("listing-date-toggle")
          if hasKnownLaunchDate {
            DatePicker("", selection: $launchDate, displayedComponents: .date)
              .labelsHidden()
              .environment(\.locale, Locale(identifier: "zh_CN"))
              .accessibilityIdentifier("listing-launch-date")
              .transition(.opacity)
          }
        }
        .animation(.snappy(duration: 0.16), value: hasKnownLaunchDate)
      }

      wizardCard("系列说明", hint: "会展示在上新卡片的描述区；批次、发货节奏等写在这里。") {
        TextField("补充说明，如「含大货，定金后 30 天内发货」", text: $noteText)
          .font(.system(size: 12))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-note")
      }
    }
  }

  // MARK: ② 选择上新阶段

  private var stageStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard("选择上新阶段（类目）", hint: "选错阶段会让系列出现在错误的时间线上，提前前可随时回来改；下一步的价格配置项会跟这里的阶段联动。") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
          ForEach(MidsummerLaunchStage.allCases, id: \.self) { candidate in
            let on = stage == candidate
            Button {
              stage = on ? nil : candidate
            } label: {
              HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : candidate.iconSystemName)
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(on ? MidsummerTheme.onAccent : MidsummerTheme.secondaryText)
                Text(candidate.labelZH)
                  .font(.system(size: 13, weight: on ? .semibold : .regular))
                  .foregroundStyle(on ? MidsummerTheme.onAccent : MidsummerTheme.primaryText)
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 9)
              .background(on ? MidsummerTheme.brandOrange : MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listing-stage-\(candidate.rawValue)")
            .accessibilityLabel("上新阶段 \(candidate.labelZH)")
            .accessibilityAddTraits(on ? .isSelected : [])
          }
        }

        if let stage {
          Text("该阶段的价格配置：\(stage.priceFields.map(\.labelZH).joined(separator: "、"))")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .padding(.top, 2)
            .transition(.opacity)
        }
      }
      .animation(.snappy(duration: 0.16), value: stage)
    }
  }

  // MARK: ③ 尺码信息

  private var sizesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard("可用尺码", hint: "小物可不选——上架后不出现尺码组；转 DTO 时按「S」↔「S码」与系列尺码容错匹配。") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(sizeChoices, id: \.self) { size in
            let on = pickedSizes.contains(size)
            Button {
              if on { pickedSizes.remove(size) } else { pickedSizes.insert(size) }
            } label: {
              Text(size)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listing-size-\(size)")
            .accessibilityAddTraits(on ? .isSelected : [])
          }
        }
      }
    }
  }

  /// 可用尺码候选：固定 7 项，与改版稿完全一致。
  private var sizeChoices: [String] { presetSizes }

  // MARK: ④ 单品与价格（价格项与阶段联动）

  private var itemsStep: some View {
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

      priceCard
      sourceCard
    }
  }

  /// 价格卡：按第 2 步所选阶段联动显示 现货价 / 预约价 / 定金 / 尾款；
  /// 定金与尾款可按需选择配置；定金阶段附设定金区间。
  private var priceCard: some View {
    let fields = stage?.priceFields ?? []
    return wizardCard("价格（元）", hint: stage?.priceHint ?? "先在上一步选择上新阶段，价格配置项会按阶段联动显示。") {
      if fields.isEmpty {
        Label("该阶段暂无价格配置项，可直接下一步；开定金后回来补即可。", systemImage: "info.circle")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
          if fields.contains(.shop) {
            priceField("现货价", text: $priceText, identifier: "listing-price")
          }
          if fields.contains(.preorder) {
            priceField("预约价（全款预约）", text: $preorderPriceText, identifier: "listing-preorder")
          }
          if fields.contains(.deposit) {
            priceField("定金（可选）", text: $depositText, identifier: "listing-deposit")
          }
          if fields.contains(.balance) {
            priceField("尾款（可选）", text: $balanceText, identifier: "listing-balance")
          }
        }

        if fields.contains(.shop) {
          Picker("现货价口径", selection: $priceKind) {
            ForEach(MidsummerPriceKind.allCases, id: \.self) { candidate in
              Text(candidate.labelZH).tag(candidate)
            }
          }
          .pickerStyle(.segmented)
          .font(.system(size: 12))
        }

        if fields.contains(.deposit) {
          HStack(spacing: 8) {
            Text("定金区间")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(MidsummerTheme.primaryText)
            TextField("最低", text: $depositMinText)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.center)
              .font(.system(size: 13, weight: .medium))
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity)
              .background(MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              .accessibilityIdentifier("listing-deposit-min")
            Text("–")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(MidsummerTheme.secondaryText)
            TextField("最高", text: $depositMaxText)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.center)
              .font(.system(size: 13, weight: .medium))
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity)
              .background(MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              .accessibilityIdentifier("listing-deposit-max")
            Text("元")
              .font(.system(size: 13))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
          .padding(.top, 2)
        }
      }
    }
  }

  private var sourceCard: some View {
    wizardCard("原文出处", hint: "合规必填（Apple 5.2）；留空沿用系列出处。") {
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

  // MARK: 主图宫格

  private var imageGrid: some View {
    VStack(spacing: 8) {
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

  // MARK: 提交 / 存草稿

  /// 汇总当前表单为 listing。`forceDraft = true` 时跳过校验存草稿：
  /// 新建保持 draft（listedAt 为空），编辑保留原状态。
  private func assembledListing(forceDraft: Bool) -> MidsummerListing {
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

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    listing.name = trimmedName.isEmpty && forceDraft ? "未命名草稿" : trimmedName
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

    // 系列级上新信息
    listing.stage = stage
    listing.launchTitle = launchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    listing.hasKnownLaunchDate = hasKnownLaunchDate
    listing.launchDate = hasKnownLaunchDate ? launchDate : nil
    listing.depositMin = Int(depositMinText)
    listing.depositMax = Int(depositMaxText)

    // 图片落盘（主图在前）；编辑时宫格为空则保留原图（没有动图 ≠ 清图）。
    let savedNames = listingStore.saveImages(images, listingID: id)
    if !savedNames.isEmpty || !images.isEmpty {
      listing.imageFiles = savedNames
    }

    if forceDraft {
      if existing == nil {
        listing.status = .draft
        listing.listedAt = nil
      }
    } else if !isEditMode {
      listing.status = .listed
      listing.listedAt = Date()
    }
    listing.updatedAt = Date()
    return listing
  }

  private func submit() {
    listingStore.upsert(assembledListing(forceDraft: false))
    dismiss()
  }

  private func saveDraft() {
    listingStore.upsert(assembledListing(forceDraft: true))
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

    stage = existing.stage
    launchTitle = existing.launchTitle ?? ""
    hasKnownLaunchDate = existing.hasKnownLaunchDate ?? false
    launchDate = existing.launchDate ?? Date()
    depositMinText = existing.depositMin.map(String.init) ?? ""
    depositMaxText = existing.depositMax.map(String.init) ?? ""
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
