import PhotosUI
import SwiftUI

// MARK: - 上传上新 · 四步引导式表单（2026-09-17 重写）
//
// 使用者的明确要求（第一性原理）：
//   1. **四步在同一个界面**：顶部步骤导航 + 进度指示 + 内容区 + 底部上一步/下一步，
//      全程一张页面内切换，不再分页 / 不再另开 sheet；
//   2. ①上传系列主图（多图：预览 / 删除 / 替换）+ 系列标题 + 上新时间；
//   3. ②选择上新阶段（2026-09-17 收敛为 定金/尾款/预约价/现货 四档），它是第 3 步价格配置的联动依据；
//   4. ③尺码信息：支持新增 / 编辑 / 删除尺码项（不再是固定候选勾选）；
//   5. ④单品与价格：现货价 / 预约价 / 定金 / 尾款，定金与尾款为可选项、
//      由开关按需配置；价格项只显示当前阶段对应的那些；
//   6. 四步数据统一在 `MidsummerListingDraft` 里维护，跨步骤零丢失；
//   7. 每步进入下一步前校验必填并就地报错；最后一步提交前做**全量**校验，
//      哪一项不合格就跳回那一步并显示原因。

// MARK: - 统一表单 state

/// 第 3 步的「款式」条目：图片 + 名称 + 该款价格。
///
/// 数据层落地为 `MidsummerListingStyle`——名称进 variant 规格组、图进
/// `variantImageNames`、价格进 SKU 逐款价，衣橱侧因此能按款式归类与显示该款价格。
struct MidsummerListingStyleDraft: Identifiable {
  let id: String
  var name: String
  var image: UIImage?
  /// 已落盘的款式图文件名：编辑回显时带入，用户没换图就继续用它，
  /// 换图后以新落盘的文件为准（避免重复存一份孤儿图）。
  var imageFile: String?
  var priceText: String

  init(
    id: String = UUID().uuidString.lowercased(),
    name: String = "",
    image: UIImage? = nil,
    imageFile: String? = nil,
    priceText: String = ""
  ) {
    self.id = id
    self.name = name
    self.image = image
    self.imageFile = imageFile
    self.priceText = priceText
  }

  /// 展示名：剥「现 」前缀（与规格抽屉同口径），数据层仍用全名。
  var displayName: String {
    name.hasPrefix("现 ") ? String(name.dropFirst("现 ".count)) : name
  }
}

/// 四个步骤共用的唯一数据源：任何一步的编辑都写回这里，
/// 上一步 / 下一步 / 顶部跳转都不丢数据，提交时也从它整体汇总。
struct MidsummerListingDraft {
  // ① 系列主图与信息
  var images: [UIImage] = []
  var launchTitle: String = ""
  var hasKnownLaunchDate: Bool = false
  var launchDate: Date = Date()
  var note: String = ""
  // ② 上新阶段
  var stage: MidsummerLaunchStage?
  // ③ 商品与尺码（用户 2026-09-17 归组：名称 / 分类 / 尺码 / 款式 / 价格 同屏）
  var name: String = ""
  var kind: MidsummerItemKind = .op
  var sizes: [String] = []
  var customSizeText: String = ""
  var styles: [MidsummerListingStyleDraft] = []
  var customStyleText: String = ""
  // 价格（按第 2 步阶段联动）
  var priceText: String = ""
  var preorderText: String = ""
  var depositText: String = ""
  var balanceText: String = ""
  /// 定金 / 尾款是**可选项**：开关打开才配置（第 3 步按需开启）。
  var depositEnabled: Bool = false
  var balanceEnabled: Bool = false
  var depositMinText: String = ""
  var depositMaxText: String = ""
  // 预售时间窗（定金-尾款自动流转的依据；nil = 不自动流转）。
  var depositEndsAt: Date? = nil
  var balanceEndsAt: Date? = nil
  var priceKind: MidsummerPriceKind = .shop
  var sourceURL: String = ""

  /// 当前阶段需要的价格项（定金 / 尾款还要再过一次开关）。
  var visiblePriceFields: [MidsummerPriceConfigField] {
    let base = stage?.priceFields ?? []
    return base.filter { field in
      switch field {
      case .shop, .preorder: return true
      case .deposit: return depositEnabled
      case .balance: return balanceEnabled
      }
    }
  }
}

// MARK: - 步骤定义

enum MidsummerListingFormStep: Int, CaseIterable, Identifiable, Sendable {
  case mainImages = 0
  case stage = 1
  /// ③ 合并步（用户 2026-09-17）：商品名称 / 分类 / 尺码 / 款式 / 价格 同屏，
  ///    不再把尺码单独拆成一步。
  case itemBasics = 2
  /// ④ 确认与发布：原文出处 + 提交汇总 + 发布。
  case confirm = 3

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .mainImages: return "主图与信息"
    case .stage: return "上新阶段"
    case .itemBasics: return "商品与尺码"
    case .confirm: return "确认发布"
    }
  }

  var sectionTitle: String {
    switch self {
    case .mainImages: return "① 上传系列主图与基本信息"
    case .stage: return "② 选择上新阶段"
    case .itemBasics: return "③ 填写商品名称、分类、尺码、款式与价格"
    case .confirm: return "④ 确认信息并发布"
    }
  }

  var iconSystemName: String {
    switch self {
    case .mainImages: return "photo.on.rectangle"
    case .stage: return "calendar.badge.clock"
    case .itemBasics: return "ruler"
    case .confirm: return "checkmark.seal"
    }
  }

  func next() -> MidsummerListingFormStep? {
    MidsummerListingFormStep(rawValue: rawValue + 1)
  }

  func previous() -> MidsummerListingFormStep? {
    MidsummerListingFormStep(rawValue: rawValue - 1)
  }
}

// MARK: - 表单

struct MidsummerListingFormView: View {
  @ObservedObject var store: MidsummerStore
  /// nil = 新建系列模式（上传上新直达，用户 2026-09-17）：提交时用第①步
  /// 填写的系列标题 / 上新时间 / 主图创建自建系列，再把新品挂上去。
  /// 非空 = 既有系列的上新 / 编辑模式。
  let series: MidsummerSeriesDTO?
  /// 非空 = 编辑模式（预填并保留原状态）。
  var existing: MidsummerListing?

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var listingStore = MidsummerListingStore.shared

  /// 四步共用的唯一 state。
  @State private var draft = MidsummerListingDraft()
  @State private var step: MidsummerListingFormStep = .mainImages
  /// 已到达过的最远步骤：顶部步骤条只允许跳到「走过或下一步」，避免跳步漏填。
  @State private var furthestStep: MidsummerListingFormStep = .mainImages
  @State private var stepError: String?
  /// 新建系列模式下，提交时实际创建出来的自建系列 id（幂等：存草稿 / 发布只建一次）。
  @State private var createdSeriesID: String?

  @State private var addPhotoItem: PhotosPickerItem?
  @State private var replacePhotoItem: PhotosPickerItem?
  @State private var replaceIndex: Int?
  /// 款式图：PhotosPicker 的 selection 一次只能挂一个，用「先记目标款式 id、
  /// 再选图」的方式让多个款式条目共用一个 picker。
  @State private var stylePhotoItem: PhotosPickerItem?
  @State private var stylePickerTarget: String?
  @State private var imageError: String?
  @State private var previewIndex: Int?

  private let maxImages = 5
  /// 常用尺码：一键点选加入 / 再点取消（用户 2026-09-17 指定这八档）。
  /// 仍可编辑 / 删除，也不是唯一来源——自定义尺码走「新增尺码」。
  private let presetSizes = ["XS", "S", "M", "L", "XL", "XXL", "均码", "F"]

  private var sourceItem: MidsummerItemDTO? { series?.items.first }
  private var styleGroup: MidsummerSpecGroup? {
    (sourceItem?.specGroups ?? []).first { $0.resolvedRole == .variant }
  }
  private var isEditMode: Bool { existing != nil }
  /// 上传上新直达新建系列：第①步填的就是系列档案本身。
  private var isNewSeries: Bool { series == nil && existing == nil }

  init(store: MidsummerStore, series: MidsummerSeriesDTO? = nil, existing: MidsummerListing? = nil) {
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
          if isNewSeries {
            // 新建系列模式（用户 2026-09-17）：不再从既有系列里挑，
            // 第①步填的系列标题 / 上新时间 / 主图就是新系列的档案。
            Label(
              "这一单会先创建一个新系列：下面的系列标题、上新时间与主图就是系列档案，提交后自动归入「\(store.catalog?.brandName ?? "仲夏物语")」。",
              systemImage: "sparkles"
            )
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(MidsummerTheme.brandOrange)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .accessibilityIdentifier("listing-new-series-hint")
          }
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
    .safeAreaInset(edge: .bottom) { bottomBar }
    .sheet(isPresented: imagePreviewPresented) { imagePreviewSheet }
    .onChange(of: addPhotoItem) { _, newValue in
      loadPicker(newValue) { image in
        guard let image else { return }
        guard draft.images.count < maxImages else {
          imageError = "最多 \(maxImages) 张主图，先删一张再添加。"
          return
        }
        draft.images.append(image)
        imageError = nil
      }
      addPhotoItem = nil
    }
    .onChange(of: replacePhotoItem) { _, newValue in
      loadPicker(newValue) { image in
        guard let image, let index = replaceIndex, draft.images.indices.contains(index) else { return }
        draft.images[index] = image
      }
      replaceIndex = nil
      replacePhotoItem = nil
    }
    .onChange(of: stylePhotoItem) { _, newValue in
      loadPicker(newValue) { image in
        guard let image,
          let target = stylePickerTarget,
          let index = draft.styles.firstIndex(where: { $0.id == target })
        else { return }
        draft.styles[index].image = image
        imageError = nil
      }
      stylePickerTarget = nil
      stylePhotoItem = nil
    }
    .onChange(of: draft.stage) { _, newStage in
      // 阶段变了 → 价格项跟随切换：清掉新阶段用不到的金额，
      // 定金 / 尾款阶段默认把对应开关打开（可再手动关掉）。
      let fields = newStage?.priceFields ?? []
      if !fields.contains(.shop) { draft.priceText = "" }
      if !fields.contains(.preorder) { draft.preorderText = "" }
      if !fields.contains(.deposit) {
        draft.depositText = ""
        draft.depositEnabled = false
        draft.depositMinText = ""
        draft.depositMaxText = ""
      }
      if !fields.contains(.balance) {
        draft.balanceText = ""
        draft.balanceEnabled = false
      }
      if newStage == .deposit { draft.depositEnabled = true }
      if newStage == .balance { draft.balanceEnabled = true }
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

  // MARK: 顶部步骤导航 + 进度指示

  private var stepHeader: some View {
    VStack(spacing: 6) {
      HStack(spacing: 0) {
        ForEach(MidsummerListingFormStep.allCases) { wizardStep in
          if wizardStep.rawValue > 0 {
            Rectangle()
              .fill(wizardStep.rawValue <= step.rawValue ? MidsummerTheme.brandOrange : MidsummerTheme.divider)
              .frame(height: 1.5)
              .frame(maxWidth: .infinity)
              .padding(.top, 11)
          }
          stepNode(wizardStep)
        }
      }

      HStack(spacing: 6) {
        Text("第 \(step.rawValue + 1) 步 / 共 \(MidsummerListingFormStep.allCases.count) 步")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .accessibilityIdentifier("listing-step-progress")
        Spacer(minLength: 0)
        Text("\(completedCount)/\(MidsummerListingFormStep.allCases.count) 项已填写")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)
        ProgressView(value: Double(step.rawValue + 1), total: 4)
          .tint(MidsummerTheme.brandOrange)
          .frame(width: 72)
          .accessibilityIdentifier("listing-step-progressbar")
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 6)
    .padding(.bottom, 10)
  }

  private func stepNode(_ wizardStep: MidsummerListingFormStep) -> some View {
    let isCurrent = wizardStep == step
    let isDone = wizardStep.rawValue < step.rawValue && validationError(for: wizardStep) == nil
    let reachable = wizardStep.rawValue <= furthestStep.rawValue + 1
    return Button {
      jump(to: wizardStep)
    } label: {
      VStack(spacing: 4) {
        ZStack {
          Circle()
            .fill(isCurrent ? MidsummerTheme.brandOrange : (isDone ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill))
            .frame(width: 22, height: 22)
          if isDone && !isCurrent {
            Image(systemName: "checkmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(MidsummerTheme.brandOrange)
          } else {
            Text("\(wizardStep.rawValue + 1)")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(isCurrent ? MidsummerTheme.onAccent : MidsummerTheme.secondaryText)
          }
        }
        Text(wizardStep.title)
          .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
          .foregroundStyle(isCurrent ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
          .multilineTextAlignment(.center)
          .frame(width: 44)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .buttonStyle(.plain)
    .opacity(reachable ? 1 : 0.45)
    .accessibilityIdentifier("listing-step-\(wizardStep.rawValue)")
    .accessibilityLabel("第 \(wizardStep.rawValue + 1) 步 \(wizardStep.title)")
  }

  private var completedCount: Int {
    MidsummerListingFormStep.allCases.filter { validationError(for: $0) == nil }.count
  }

  // MARK: 步骤内容

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .mainImages: mainImagesStep
    case .stage: stageStep
    case .itemBasics: itemBasicsStep
    case .confirm: confirmStep
    }
  }

  private var bottomBar: some View {
    HStack(spacing: 10) {
      if let previous = step.previous() {
        Button {
          withAnimation(.snappy(duration: 0.18)) {
            step = previous
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-back")
      }

      Button {
        advance()
      } label: {
        Text(step == .confirm ? (isEditMode ? "保存修改" : "发布上架") : "下一步")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(MidsummerTheme.onAccent)
          .frame(height: 46)
          .frame(maxWidth: .infinity)
          .background(MidsummerTheme.brandOrange)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .themeSkinLegibleText(level: .hero, slot: MidsummerThemeSlot.primaryButton)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(step == .confirm ? "listing-publish" : "listing-next")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  // MARK: 步骤切换与校验

  private func advance() {
    if let failure = validationError(for: step) {
      stepError = failure
      return
    }
    stepError = nil
    guard let next = step.next() else {
      submit()
      return
    }
    withAnimation(.snappy(duration: 0.18)) {
      step = next
      if next.rawValue > furthestStep.rawValue { furthestStep = next }
    }
  }

  /// 顶部步骤条跳转：向后自由；向前要逐步校验（跳步不能绕过必填）。
  private func jump(to target: MidsummerListingFormStep) {
    guard target != step else { return }
    if target.rawValue < step.rawValue {
      withAnimation(.snappy(duration: 0.18)) {
        step = target
        stepError = nil
      }
      return
    }
    var cursor = step
    while let next = cursor.next(), next.rawValue <= target.rawValue {
      if let failure = validationError(for: cursor) {
        stepError = failure
        step = cursor
        return
      }
      cursor = next
    }
    stepError = nil
    withAnimation(.snappy(duration: 0.18)) {
      step = target
      if target.rawValue > furthestStep.rawValue { furthestStep = target }
    }
  }

  /// 单步必填校验：进入下一步前调用，也用于进度指示与提交前全量校验。
  private func validationError(for target: MidsummerListingFormStep) -> String? {
    switch target {
    case .mainImages:
      let title = trimmed(draft.launchTitle)
      if title.isEmpty { return "请填写系列标题（30 字以内）。" }
      if title.count > 30 { return "系列标题请控制在 30 字以内（当前 \(title.count) 字）。" }
      return nil

    case .stage:
      if draft.stage == nil {
        return "请选择上新阶段——它决定第 3 步出现哪些价格配置项。"
      }
      return nil

    case .itemBasics:
      // ③ 合并步：名称 / 分类 / 尺码 / 款式 / 价格 都在这一屏校验。
      if trimmed(draft.name).isEmpty { return "请填写商品名称。" }

      if draft.sizes.contains(where: { trimmed($0).isEmpty }) {
        return "有尺码项名称为空，请补全或删除该行。"
      }
      let normalized = draft.sizes.map { trimmed($0).lowercased() }
      if Set(normalized).count != normalized.count {
        return "存在重复尺码，请合并后再继续。"
      }

      if draft.styles.isEmpty {
        return "请至少添加一个款式——上架后按款式归类与展示。"
      }
      if draft.styles.contains(where: { trimmed($0.name).isEmpty }) {
        return "有款式条目的名称为空，请补全或删除该行。"
      }
      let styleNames = draft.styles.map { trimmed($0.name).lowercased() }
      if Set(styleNames).count != styleNames.count {
        return "存在重复款式，请合并后再继续。"
      }
      if let bad = draft.styles.first(where: {
        let text = trimmed($0.priceText)
        return !text.isEmpty && Int(text) == nil
      }) {
        return "款式「\(trimmed(bad.name))」的价格需填整数金额（元）。"
      }

      let fields = draft.stage?.priceFields ?? []
      let typed: [(String, String)] = [
        ("现货价", fields.contains(.shop) ? draft.priceText : ""),
        ("预约价", fields.contains(.preorder) ? draft.preorderText : ""),
        ("定金", fields.contains(.deposit) && draft.depositEnabled ? draft.depositText : ""),
        ("尾款", fields.contains(.balance) && draft.balanceEnabled ? draft.balanceText : ""),
      ]
      for (label, text) in typed where !trimmed(text).isEmpty {
        if Int(trimmed(text)) == nil { return "\(label) 需填整数金额（元）。" }
      }
      if !fields.isEmpty && typed.allSatisfy({ trimmed($0.1).isEmpty }) {
        return "请至少填写一项当前阶段的价格：\(fields.map(\.labelZH).joined(separator: " / "))。"
      }

      // 预售时间窗校验：倒挂配置会让定金结束时直接判「预售结束」。
      if let depositEndsAt = draft.depositEndsAt,
        let balanceEndsAt = draft.balanceEndsAt,
        balanceEndsAt <= depositEndsAt
      {
        return "尾款截止需晚于定金截止（第 2 步），否则预售会在定金结束时立即结束。"
      }

      // 定金 + 尾款 = 预约价（硬规则）：两边都配了数字且预约价也填了数，必须相等。
      if draft.depositEnabled, draft.balanceEnabled,
        let deposit = Int(trimmed(draft.depositText)),
        let balance = Int(trimmed(draft.balanceText)),
        let preorder = Int(trimmed(draft.preorderText)),
        preorder != deposit + balance
      {
        return "预约价应为定金 + 尾款 = ¥\(deposit + balance)（当前填了 ¥\(preorder)）。"
      }
      return nil

    case .confirm:
      let url = trimmed(draft.sourceURL)
      if !url.isEmpty {
        guard let parsed = URL(string: url),
          let scheme = parsed.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          parsed.host != nil
        else {
          return "原文出处需以 http:// 或 https:// 开头（留空则沿用系列出处）。"
        }
      }
      return nil
    }
  }

  // MARK: ① 系列主图与信息

  private var mainImagesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard(
        "系列主图宫格（最多 \(maxImages) 张）",
        hint: "第 1 张为主图：上架后用作系列卡片与详情页封面。点图替换、右上角 × 删除、🔍 预览、非主图可「设为主图」。"
      ) {
        imageGrid
      }

      wizardCard("系列标题", hint: "相当于宝贝标题，30 字以内。写清系列主题，方便他人检索。") {
        TextField("系列名，例如「小熊博物馆系列」", text: $draft.launchTitle)
          .font(.system(size: 14))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-launch-title")

        HStack(spacing: 10) {
          Text("上新时间")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
          Spacer(minLength: 0)
          Toggle("已知", isOn: $draft.hasKnownLaunchDate)
            .labelsHidden()
            .tint(MidsummerTheme.accentPink)
            .accessibilityIdentifier("listing-date-toggle")
          if draft.hasKnownLaunchDate {
            DatePicker("", selection: $draft.launchDate, displayedComponents: .date)
              .labelsHidden()
              .environment(\.locale, Locale(identifier: "zh_CN"))
              .accessibilityIdentifier("listing-launch-date")
              .transition(.opacity)
          } else {
            Text("待定")
              .font(.system(size: 12))
              .foregroundStyle(MidsummerTheme.secondaryText)
              .transition(.opacity)
          }
        }
        .animation(.snappy(duration: 0.16), value: draft.hasKnownLaunchDate)
      }

      wizardCard("系列说明", hint: "会展示在上新卡片的描述区；批次、发货节奏等写在这里。") {
        TextField("补充说明，如「含大货，定金后 30 天内发货」", text: $draft.note)
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
    wizardCard(
      "选择上新阶段（类目）",
      hint: "选错阶段会让系列出现在错误的时间线上，提交前可随时回来改；第 3 步的价格配置项跟这里的阶段联动。"
    ) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
        ForEach(MidsummerLaunchStage.allCases, id: \.self) { candidate in
          let on = draft.stage == candidate
          Button {
            draft.stage = on ? nil : candidate
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

      if let stage = draft.stage {
        VStack(alignment: .leading, spacing: 3) {
          Text("该阶段的价格配置：\(stage.priceFields.map(\.labelZH).joined(separator: "、"))")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
          Text(stage.priceHint)
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        .padding(.top, 2)
        .transition(.opacity)
      }

      // 定金-尾款预售时间窗（用户 2026-09-17 自动流转规则）：
      // 定金期结束 → 自动从「上新」列表移除并进入尾款列表；
      // 尾款期也结束 → 预售结束，详情页同时展示预约价与现货价。
      if draft.stage == .deposit || draft.stage == .balance {
        VStack(alignment: .leading, spacing: 8) {
          Text("预售时间窗（到点自动流转；不设置则停留在当前阶段）")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
          if draft.stage == .deposit {
            optionalDatePicker(
              "定金截止", binding: $draft.depositEndsAt, identifier: "listing-deposit-ends")
          }
          optionalDatePicker(
            "尾款截止", binding: $draft.balanceEndsAt, identifier: "listing-balance-ends")
          if let depositEndsAt = draft.depositEndsAt,
            let balanceEndsAt = draft.balanceEndsAt,
            balanceEndsAt <= depositEndsAt
          {
            Text("尾款截止需晚于定金截止，否则定金结束时会直接判定预售结束。")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.priceRed)
          }
        }
        .padding(.top, 4)
      }
    }
    .animation(.snappy(duration: 0.16), value: draft.stage)
  }

  /// 可选时间选择器：默认「未设置」（不自动流转）；打开开关后出现 DatePicker。
  private func optionalDatePicker(
    _ title: String, binding: Binding<Date?>, identifier: String
  ) -> some View {
    HStack(spacing: 10) {
      Toggle(isOn: Binding(
        get: { binding.wrappedValue != nil },
        set: { on in binding.wrappedValue = on ? Date().addingTimeInterval(7 * 86_400) : nil }
      )) {
        Text(title)
          .font(.system(size: 13))
          .foregroundStyle(MidsummerTheme.primaryText)
      }
      .toggleStyle(.switch)
      .labelsHidden()
      .accessibilityIdentifier("\(identifier)-toggle")

      if let date = binding.wrappedValue {
        DatePicker(
          "", selection: Binding(get: { date }, set: { binding.wrappedValue = $0 }),
          displayedComponents: [.date, .hourAndMinute]
        )
        .font(.system(size: 12))
        .labelsHidden()
        .accessibilityIdentifier(identifier)
      } else {
        Text("未设置")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
      Spacer(minLength: 0)
    }
  }

  // MARK: ③ 商品与尺码（名称 / 分类 / 尺码 / 款式 / 价格 同屏）

  private var itemBasicsStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      nameCard
      kindCard
      sizesCard
      stylesCard
      priceCard
    }
  }

  // MARK: ④ 确认与发布

  private var confirmStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      sourceCard
      summaryCard
    }
  }

  private var nameCard: some View {
    wizardCard("商品名称", hint: "同一个系列里的商品名不要重复，例如「樱花小羊 开衫」。") {
      TextField("商品名称", text: $draft.name)
        .font(.system(size: 14))
        .padding(10)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("listing-name")
    }
  }

  private var kindCard: some View {
    wizardCard(
      "商品分类",
      hint: "按「连衣裙 / 内搭 / 小物」三个大类分组，点一下具体类型即可；决定商品在系列页的分组与图标。"
    ) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(MidsummerItemCategory.allCases, id: \.self) { category in
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
              Text(category.labelZH)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MidsummerTheme.primaryText)
              if draft.kind.category == category {
                Circle()
                  .fill(MidsummerTheme.brandOrange)
                  .frame(width: 5, height: 5)
              }
            }
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8
            ) {
              ForEach(MidsummerItemKind.kinds(in: category), id: \.self) { candidate in
                let on = draft.kind == candidate
                Button {
                  draft.kind = candidate
                } label: {
                  Text(candidate.shortLabel)
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(on ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                      RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(on ? MidsummerTheme.brandOrange : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listing-kind-\(candidate.rawValue)")
                .accessibilityLabel("\(category.labelZH) \(candidate.labelZH)")
                .accessibilityAddTraits(on ? .isSelected : [])
              }
            }
          }
        }
      }
    }
  }

  private var sizesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard(
        "尺码项（\(draft.sizes.count)）",
        hint: "名称可直接改；顺序即上架后规格抽屉里的顺序。小物等无尺码商品可以留空直接下一步。"
      ) {
        if draft.sizes.isEmpty {
          Text("还没有尺码项。点下面的常用尺码，或自己新增一个。")
            .font(.system(size: 12))
            .foregroundStyle(MidsummerTheme.secondaryText)
        } else {
          VStack(spacing: 8) {
            ForEach(draft.sizes.indices, id: \.self) { index in
              sizeRow(index)
            }
          }
        }
      }

      wizardCard("常用尺码", hint: "点一下加入尺码项；再点一下移除。加入后仍可改名。") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(presetSizes, id: \.self) { size in
            let on = draft.sizes.contains(size)
            Button {
              togglePreset(size)
            } label: {
              HStack(spacing: 3) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(size)
                  .font(.system(size: 13, weight: on ? .semibold : .regular))
              }
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

      wizardCard("新增尺码", hint: "自定义尺码名，如「F」「70-75」；重复会被拦下。") {
        HStack(spacing: 8) {
          TextField("输入尺码名", text: $draft.customSizeText)
            .font(.system(size: 14))
            .padding(10)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("listing-size-custom")
          Button {
            addCustomSize()
          } label: {
            Text("添加")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(MidsummerTheme.onAccent)
              .padding(.horizontal, 18)
              .padding(.vertical, 10)
              .background(MidsummerTheme.brandOrange)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("listing-size-add")
        }
      }
    }
  }

  // MARK: 款式（尺码区下方：图片 + 名称 + 该款价格）

  private var stylesCard: some View {
    wizardCard(
      "款式（\(draft.styles.count)）",
      hint: "每一款：左边传款式图、右边填该款价格（留空则沿用上面的单品价）。可从系列已有款式里选，也可自己新增，如「蓝色 OP」。上架后按款式在衣橱里归类与筛选。"
    ) {
      if draft.styles.isEmpty {
        Text("还没有款式条目。点下面的系列款式加入，或自己新增一个。")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      } else {
        VStack(spacing: 8) {
          ForEach(draft.styles) { style in
            styleRow(style.id)
          }
        }
      }

      if let styleGroup, !styleGroup.options.isEmpty {
        Text("系列已有款式（点一下加入 / 再点移除）")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
          .padding(.top, 2)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
          ForEach(styleGroup.options) { option in
            let added = draft.styles.contains { $0.name == option.name }
            Button {
              toggleSeriesStyle(option)
            } label: {
              Text(Self.displayStyleName(option.name))
                .font(.system(size: 11, weight: added ? .semibold : .regular))
                .foregroundStyle(added ? MidsummerTheme.brandOrange : MidsummerTheme.primaryText)
                .themeSkinLegibleText(level: added ? .chip : .inline, slot: MidsummerThemeSlot.specOption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(added ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(added ? MidsummerTheme.brandOrange : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listing-style-\(option.id)")
            .accessibilityLabel(Self.displayStyleName(option.name))
            .accessibilityAddTraits(added ? .isSelected : [])
          }
        }
      }

      HStack(spacing: 8) {
        TextField("输入款式名，如「蓝色 OP」", text: $draft.customStyleText)
          .font(.system(size: 14))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("listing-style-custom")
        Button {
          addCustomStyle()
        } label: {
          Text("添加")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MidsummerTheme.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(MidsummerTheme.brandOrange)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-style-add")
      }
    }
  }

  private func styleRow(_ id: String) -> some View {
    let index = draft.styles.firstIndex(where: { $0.id == id }) ?? 0
    return HStack(spacing: 8) {
      PhotosPicker(selection: $stylePhotoItem, matching: .images) {
        Group {
          if let image = draft.styles.indices.contains(index) ? draft.styles[index].image : nil {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            VStack(spacing: 2) {
              Image(systemName: "photo.badge.plus")
                .font(.system(size: 15))
              Text("款式图")
                .font(.system(size: 8))
            }
            .foregroundStyle(MidsummerTheme.secondaryText)
          }
        }
        .frame(width: 52, height: 52)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(MidsummerTheme.divider, style: StrokeStyle(lineWidth: 1, dash: [3]))
        )
      }
      .simultaneousGesture(TapGesture().onEnded { stylePickerTarget = id })
      .accessibilityIdentifier("listing-style-image-\(index)")
      .accessibilityLabel("上传款式图")

      TextField("款式名", text: styleNameBinding(id: id))
        .font(.system(size: 14))
        .padding(10)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("listing-style-name-\(index)")

      VStack(alignment: .leading, spacing: 2) {
        Text("价格")
          .font(.system(size: 9))
          .foregroundStyle(MidsummerTheme.secondaryText)
        TextField("留空沿用", text: stylePriceBinding(id: id))
          .keyboardType(.numberPad)
          .multilineTextAlignment(.center)
          .font(.system(size: 13, weight: .medium))
          .padding(.vertical, 6)
          .frame(width: 76)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          .accessibilityIdentifier("listing-style-price-\(index)")
      }

      Button {
        removeStyle(id: id)
      } label: {
        Image(systemName: "minus.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(MidsummerTheme.priceRed)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("listing-style-delete-\(index)")
      .accessibilityLabel("删除款式")
    }
    .accessibilityIdentifier("listing-style-row-\(index)")
  }

  private func styleNameBinding(id: String) -> Binding<String> {
    Binding(
      get: { draft.styles.first(where: { $0.id == id })?.name ?? "" },
      set: { newValue in
        guard let index = draft.styles.firstIndex(where: { $0.id == id }) else { return }
        draft.styles[index].name = newValue
      }
    )
  }

  private func stylePriceBinding(id: String) -> Binding<String> {
    Binding(
      get: { draft.styles.first(where: { $0.id == id })?.priceText ?? "" },
      set: { newValue in
        guard let index = draft.styles.firstIndex(where: { $0.id == id }) else { return }
        draft.styles[index].priceText = newValue
      }
    )
  }

  private func toggleSeriesStyle(_ option: MidsummerSpecOption) {
    if let index = draft.styles.firstIndex(where: { $0.name == option.name }) {
      draft.styles.remove(at: index)
      return
    }
    draft.styles.append(
      MidsummerListingStyleDraft(
        name: option.name,
        image: seriesStyleImage(for: option.name),
        imageFile: sourceItem?.variantImageNames?[option.name],
        priceText: ""
      )
    )
  }

  /// 系列款式自带的对应图（有就预填，省一次上传）。
  private func seriesStyleImage(for name: String) -> UIImage? {
    guard let fileName = sourceItem?.variantImageNames?[name], !fileName.isEmpty else { return nil }
    return ImageManager.shared.loadImage(fileName: fileName)
  }

  private func addCustomStyle() {
    let name = trimmed(draft.customStyleText)
    guard !name.isEmpty else {
      stepError = "请先输入款式名再点添加。"
      return
    }
    guard !draft.styles.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
      stepError = "款式「\(name)」已经在列表里了。"
      return
    }
    draft.styles.append(MidsummerListingStyleDraft(name: name))
    draft.customStyleText = ""
    stepError = nil
  }

  private func removeStyle(id: String) {
    draft.styles.removeAll { $0.id == id }
  }

  private func sizeRow(_ index: Int) -> some View {
    HStack(spacing: 8) {
      VStack(spacing: 2) {
        Button {
          moveSize(from: index, to: index - 1)
        } label: {
          Image(systemName: "chevron.up")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        .disabled(index == 0)
        .accessibilityIdentifier("listing-size-up-\(index)")
        Button {
          moveSize(from: index, to: index + 1)
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        .disabled(index == draft.sizes.count - 1)
        .accessibilityIdentifier("listing-size-down-\(index)")
      }
      .buttonStyle(.plain)

      TextField("尺码名", text: sizeBinding(at: index))
        .font(.system(size: 14))
        .padding(10)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("listing-size-input-\(index)")

      Button {
        removeSize(at: index)
      } label: {
        Image(systemName: "minus.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(MidsummerTheme.priceRed)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("listing-size-delete-\(index)")
      .accessibilityLabel("删除尺码")
    }
  }

  // MARK: 价格卡（只显示第 2 步所选阶段对应的价格项；定金 / 尾款带开关按需配置）
  private var priceCard: some View {
    let stageFields = draft.stage?.priceFields ?? []
    return wizardCard(
      "价格（元）",
      hint: draft.stage?.priceHint ?? "先在第 2 步选择上新阶段，价格配置项会按阶段联动显示。"
    ) {
      if stageFields.isEmpty {
        Label("该阶段暂无价格配置项，可直接发布；开定金后回来补即可。", systemImage: "info.circle")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
          if stageFields.contains(.shop) {
            priceField("现货价", text: $draft.priceText, identifier: "listing-price")
          }
          if stageFields.contains(.preorder) {
            priceField("预约价（全款预约）", text: $draft.preorderText, identifier: "listing-preorder")
          }
        }

        if stageFields.contains(.shop) {
          Picker("现货价口径", selection: $draft.priceKind) {
            ForEach(MidsummerPriceKind.allCases, id: \.self) { candidate in
              Text(candidate.labelZH).tag(candidate)
            }
          }
          .pickerStyle(.segmented)
          .font(.system(size: 12))
        }

        // 定金 / 尾款：可选项，按需开关
        if stageFields.contains(.deposit) || stageFields.contains(.balance) {
          VStack(alignment: .leading, spacing: 10) {
            if stageFields.contains(.deposit) {
              optionalPriceToggleRow(
                "定金", isOn: $draft.depositEnabled, identifier: "listing-deposit-toggle"
              )
              if draft.depositEnabled {
                priceField("定金金额", text: $draft.depositText, identifier: "listing-deposit")
                depositRangeRow
              }
            }
            if stageFields.contains(.balance) {
              optionalPriceToggleRow(
                "尾款", isOn: $draft.balanceEnabled, identifier: "listing-balance-toggle"
              )
              if draft.balanceEnabled {
                priceField("尾款金额", text: $draft.balanceText, identifier: "listing-balance")
              }
            }
            // 定金 + 尾款 = 预约价（硬规则）：两项都配齐后自动算出预约价，
            // 详情页预售结束时的「预约价 + 现货价」双价展示用的就是它。
            if draft.depositEnabled, draft.balanceEnabled,
              let deposit = Int(trimmed(draft.depositText)),
              let balance = Int(trimmed(draft.balanceText))
            {
              Text("定金 ¥\(deposit) + 尾款 ¥\(balance) = 预约价 ¥\(deposit + balance)（自动核算）")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MidsummerTheme.freshGreen)
            }
          }
          .onChange(of: draft.depositText) { _, _ in syncPreorderFromDepositBalance() }
          .onChange(of: draft.balanceText) { _, _ in syncPreorderFromDepositBalance() }
          .onChange(of: draft.depositEnabled) { _, _ in syncPreorderFromDepositBalance() }
          .onChange(of: draft.balanceEnabled) { _, _ in syncPreorderFromDepositBalance() }
        }
      }
    }
  }

  private func optionalPriceToggleRow(
    _ title: String, isOn: Binding<Bool>, identifier: String
  ) -> some View {
    HStack {
      Text("配置\(title)（可选）")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)
      Spacer(minLength: 0)
      Toggle("", isOn: isOn)
        .labelsHidden()
        .tint(MidsummerTheme.accentPink)
        .accessibilityIdentifier(identifier)
    }
  }

  /// 定金 + 尾款 = 预约价的自动核算：两项都配齐时把预约价回填进 draft
  /// （预约价输入框不在定金阶段的价格项里，落盘走这里回填的值）。
  /// 两项没配齐则不动预约价，避免把半成品价格写进存档。
  private func syncPreorderFromDepositBalance() {
    guard draft.depositEnabled, draft.balanceEnabled,
      let deposit = Int(trimmed(draft.depositText)),
      let balance = Int(trimmed(draft.balanceText))
    else { return }
    draft.preorderText = String(deposit + balance)
  }

  private var depositRangeRow: some View {
    HStack(spacing: 8) {
      Text("定金区间")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)
      TextField("最低", text: $draft.depositMinText)
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
      TextField("最高", text: $draft.depositMaxText)
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
  }

  private var sourceCard: some View {
    wizardCard("原文出处", hint: "合规必填（Apple 5.2）；留空沿用系列出处。") {
      TextField("原文出处（可选，留空沿用系列出处）", text: $draft.sourceURL)
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

  /// 提交前的汇总预览：四步数据一览，避免「点完才发现填错」。
  private var summaryCard: some View {
    wizardCard("提交汇总", hint: "确认无误后点下方「发布上架」。") {
      VStack(alignment: .leading, spacing: 5) {
        summaryRow("系列标题", draft.launchTitle)
        summaryRow("上新时间", draft.hasKnownLaunchDate ? Self.dateText(draft.launchDate) : "待定")
        summaryRow("上新阶段", draft.stage?.labelZH ?? "未选择")
        if draft.depositEndsAt != nil || draft.balanceEndsAt != nil {
          summaryRow(
            "预售时间窗",
            [
              draft.depositEndsAt.map { "定金至 \(Self.dateText($0))" },
              draft.balanceEndsAt.map { "尾款至 \(Self.dateText($0))" },
            ]
            .compactMap { $0 }
            .joined(separator: "；")
          )
        }
        summaryRow("尺码", draft.sizes.isEmpty ? "无（小物 / 均码）" : draft.sizes.joined(separator: " / "))
        summaryRow("商品名称", draft.name)
        summaryRow("款式", styleSummaryText)
        summaryRow("价格", priceSummaryText)
        summaryRow("主图", "\(draft.images.count) 张")
      }
    }
  }

  private func summaryRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Text("\(label)：")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Text(value.isEmpty ? "待填" : value)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(value.isEmpty ? MidsummerTheme.priceRed : MidsummerTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var priceSummaryText: String {
    var parts: [String] = []
    if let price = Int(trimmed(draft.priceText)) { parts.append("现货价 ¥\(price)") }
    if let preorder = Int(trimmed(draft.preorderText)) { parts.append("预约价 ¥\(preorder)") }
    if draft.depositEnabled, let deposit = Int(trimmed(draft.depositText)) { parts.append("定金 ¥\(deposit)") }
    if draft.balanceEnabled, let balance = Int(trimmed(draft.balanceText)) { parts.append("尾款 ¥\(balance)") }
    return parts.joined(separator: " + ")
  }

  /// 款式汇总：款式名（逐款价），没填逐款价的只显示名字（沿用单品价）。
  private var styleSummaryText: String {
    guard !draft.styles.isEmpty else { return "" }
    return draft.styles.map { style in
      let name = trimmed(style.name)
      guard !name.isEmpty else { return nil }
      if let price = Int(trimmed(style.priceText)) { return "\(Self.displayStyleName(name)) ¥\(price)" }
      return Self.displayStyleName(name)
    }
    .compactMap { $0 }
    .joined(separator: " / ")
  }

  // MARK: 主图宫格（多图上传 / 预览 / 删除 / 替换）

  private var imageGrid: some View {
    VStack(spacing: 8) {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
        ForEach(draft.images.indices, id: \.self) { index in
          imageCell(index)
        }
        if draft.images.count < maxImages {
          PhotosPicker(selection: $addPhotoItem, matching: .images) {
            VStack(spacing: 3) {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
              Text("添加主图")
                .font(.system(size: 10))
              Text("\(draft.images.count)/\(maxImages)")
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
      // 点图 = 替换（保持与改版前一致的手感）
      PhotosPicker(selection: $replacePhotoItem, matching: .images) {
        Image(uiImage: draft.images[index])
          .resizable()
          .scaledToFill()
          .frame(height: 88)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .simultaneousGesture(TapGesture().onEnded { replaceIndex = index })
      .accessibilityIdentifier("listing-image-cell-\(index)")

      HStack(spacing: 4) {
        Button {
          previewIndex = index
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .shadow(radius: 2)
            .padding(3)
            .background(.black.opacity(0.35))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-image-preview-\(index)")
        .accessibilityLabel("预览主图")

        Button {
          _ = draft.images.remove(at: index)
          imageError = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-image-delete-\(index)")
        .accessibilityLabel("删除主图")
      }
      .padding(4)
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
            let image = draft.images.remove(at: index)
            draft.images.insert(image, at: 0)
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("listing-image-setmain-\(index)")
      }
    }
  }

  private var imagePreviewPresented: Binding<Bool> {
    Binding(
      get: { previewIndex != nil },
      set: { if !$0 { previewIndex = nil } }
    )
  }

  private var imagePreviewSheet: some View {
    NavigationStack {
      Group {
        if let index = previewIndex, draft.images.indices.contains(index) {
          Image(uiImage: draft.images[index])
            .resizable()
            .scaledToFit()
            .padding()
        } else {
          Text("图片已删除")
            .font(.system(size: 13))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(MidsummerTheme.pageBackground)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭") { previewIndex = nil }
            .accessibilityIdentifier("listing-image-preview-close")
        }
        if let index = previewIndex, index > 0 {
          ToolbarItem(placement: .topBarTrailing) {
            Button("设为主图") {
              let image = draft.images.remove(at: index)
              draft.images.insert(image, at: 0)
              previewIndex = nil
            }
            .accessibilityIdentifier("listing-image-preview-setmain")
          }
        }
      }
    }
  }

  // MARK: 尺码编辑操作

  private func sizeBinding(at index: Int) -> Binding<String> {
    Binding(
      get: { draft.sizes.indices.contains(index) ? draft.sizes[index] : "" },
      set: { newValue in
        guard draft.sizes.indices.contains(index) else { return }
        draft.sizes[index] = newValue
      }
    )
  }

  private func togglePreset(_ size: String) {
    if let index = draft.sizes.firstIndex(of: size) {
      draft.sizes.remove(at: index)
    } else {
      draft.sizes.append(size)
    }
  }

  private func addCustomSize() {
    let name = trimmed(draft.customSizeText)
    guard !name.isEmpty else {
      stepError = "请先输入尺码名再点添加。"
      return
    }
    guard !draft.sizes.contains(where: { $0.lowercased() == name.lowercased() }) else {
      stepError = "尺码「\(name)」已经在列表里了。"
      return
    }
    draft.sizes.append(name)
    draft.customSizeText = ""
    stepError = nil
  }

  private func removeSize(at index: Int) {
    guard draft.sizes.indices.contains(index) else { return }
    draft.sizes.remove(at: index)
    if previewIndex == index { previewIndex = nil }
  }

  private func moveSize(from index: Int, to target: Int) {
    guard draft.sizes.indices.contains(index), draft.sizes.indices.contains(target) else { return }
    draft.sizes.swapAt(index, target)
  }

  // MARK: 提交 / 存草稿

  /// 提交：先做**全量**四步校验，哪一项不合格就跳回那一步并说明原因。
  private func submit() {
    for candidate in MidsummerListingFormStep.allCases {
      if let failure = validationError(for: candidate) {
        stepError = failure
        step = candidate
        return
      }
    }
    stepError = nil
    listingStore.upsert(assembledListing(forceDraft: false))
    dismiss()
  }

  private func saveDraft() {
    listingStore.upsert(assembledListing(forceDraft: true))
    dismiss()
  }

  /// 汇总统一 state 为 listing。`forceDraft = true` 时跳过校验存草稿：
  /// 新建保持 draft（listedAt 为空），编辑保留原状态。
  private func assembledListing(forceDraft: Bool) -> MidsummerListing {
    let seriesID = ensureCustomSeries()
    let id = existing?.id ?? MidsummerListing.newID()
    var listing = existing ?? MidsummerListing(
      id: id,
      seriesID: seriesID,
      name: "",
      kindRaw: draft.kind.rawValue,
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

    let trimmedName = trimmed(draft.name)
    listing.name = trimmedName.isEmpty && forceDraft ? "未命名草稿" : trimmedName
    listing.kind = draft.kind
    listing.price = Int(trimmed(draft.priceText))
    listing.preorderPrice = Int(trimmed(draft.preorderText))
    listing.deposit = draft.depositEnabled ? Int(trimmed(draft.depositText)) : nil
    listing.balance = draft.balanceEnabled ? Int(trimmed(draft.balanceText)) : nil
    // 定金 + 尾款 = 预约价：配齐后预约价以合计为准（onChange 已回填 draft，
    // 这里再兜一次底，直接从存档编辑等绕过表单 onChange 的路径也正确）。
    if listing.deposit != nil, listing.balance != nil {
      listing.preorderPrice = listing.expectedPreorderPrice
    } else {
      listing.preorderPrice = Int(trimmed(draft.preorderText))
    }
    listing.priceKind = Int(trimmed(draft.priceText)) == nil ? nil : draft.priceKind
    listing.note = draft.note
    listing.sourceURL = trimmed(draft.sourceURL)
    listing.sizes = draft.sizes.map { trimmed($0) }.filter { !$0.isEmpty }

    listing.stage = draft.stage
    listing.launchTitle = trimmed(draft.launchTitle)
    listing.hasKnownLaunchDate = draft.hasKnownLaunchDate
    listing.launchDate = draft.hasKnownLaunchDate ? draft.launchDate : nil
    listing.depositMin = draft.depositEnabled ? Int(trimmed(draft.depositMinText)) : nil
    listing.depositMax = draft.depositEnabled ? Int(trimmed(draft.depositMaxText)) : nil
    // 预售时间窗：只对定金-尾款线生效；其它阶段清空，避免残留脏配置。
    if draft.stage == .deposit {
      listing.depositEndsAt = draft.depositEndsAt
      listing.balanceEndsAt = draft.balanceEndsAt
    } else if draft.stage == .balance {
      listing.depositEndsAt = nil
      listing.balanceEndsAt = draft.balanceEndsAt
    } else {
      listing.depositEndsAt = nil
      listing.balanceEndsAt = nil
    }

    let savedNames = listingStore.saveImages(draft.images, listingID: id)
    if !savedNames.isEmpty || !draft.images.isEmpty {
      listing.imageFiles = savedNames
    }

    // 款式：名 / 图 / 逐款价。图必须在 saveImages 之后落盘——
    // saveImages 会按前缀清掉这个 listing 的旧图（含上次保存的款式图）。
    let styleEntries: [MidsummerListingStyle] = draft.styles.enumerated().compactMap { index, style in
      let styleName = trimmed(style.name)
      guard !styleName.isEmpty else { return nil }
      let file =
        style.image.flatMap { listingStore.saveStyleImage($0, listingID: id, index: index) }
        ?? style.imageFile
      return MidsummerListingStyle(
        id: style.id,
        name: styleName,
        imageFile: file,
        price: Int(trimmed(style.priceText))
      )
    }
    listing.styles = styleEntries
    // `variantOptionNames` 是旧存档口径（只有款式名），保持同步，
    // 老代码 / 旧数据读到它也能拿到同样的款式列表。
    listing.variantOptionNames = styleEntries.map(\.name)

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

  // MARK: 新建系列（上传上新直达，用户 2026-09-17）

  /// 幂等创建自建系列并返回其 id：
  /// 既有系列 / 编辑模式直接用原 id；新建模式只在第一次提交时创建一次。
  private func ensureCustomSeries() -> String {
    if let existing { return existing.seriesID }
    if let series { return series.id }
    if let createdSeriesID { return createdSeriesID }

    let id = "midsummer-custom-" + UUID().uuidString.lowercased()
    let title = trimmed(draft.launchTitle)
    let calendar = Calendar.current
    let referenceDate = draft.hasKnownLaunchDate ? draft.launchDate : Date()
    let dto = MidsummerSeriesDTO(
      id: id,
      name: title.isEmpty ? "未命名系列" : title,
      year: calendar.component(.year, from: referenceDate),
      launchedOn: draft.hasKnownLaunchDate ? Self.dateText(draft.launchDate) : "",
      stage: draft.stage.flatMap { Self.stageMapping[$0] } ?? .preview,
      coverImage: saveCoverImage(seriesID: id),
      depositMin: nil,
      depositMax: nil,
      priceSource: nil,
      sizes: draft.sizes.map { trimmed($0) }.filter { !$0.isEmpty },
      colors: [],
      summary: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
      sourceURL: "",
      sourceKind: "editorial",
      verified: false,
      items: []
    )
    MidsummerCustomSeriesStore.shared.add(dto)
    createdSeriesID = id
    return id
  }

  /// 第①步首图即系列封面：复用 Images 目录一条读取路径。
  private func saveCoverImage(seriesID: String) -> String? {
    guard let image = draft.images.first,
      let jpeg = image.jpegData(compressionQuality: 0.85)
    else { return nil }
    let name = "midsummer-custom-series-\(seriesID).jpg"
    do {
      try jpeg.write(
        to: ImageManager.shared.imagesDirectory.appendingPathComponent(name),
        options: .atomic)
      return name
    } catch {
      print("⚠️ [MidsummerListing] 系列封面落盘失败：\(error.localizedDescription)")
      return nil
    }
  }

  /// 上新阶段（表单）→ 系列阶段（目录档案）的同名映射。
  private static let stageMapping: [MidsummerLaunchStage: MidsummerStage] = [
    .deposit: .deposit,
    .balance: .balance,
    .preorder: .preorder,
    .inStock: .inStock,
  ]

  // MARK: 预填 / 工具

  private func prefill() {
    guard let existing else { return }
    draft.name = existing.name
    draft.kind = existing.kind
    draft.sizes = existing.sizes
    // 款式回显：新存档带图与逐款价；旧存档（只有 variantOptionNames）降级成「只有名字」。
    if let styles = existing.styles, !styles.isEmpty {
      draft.styles = styles.map {
        MidsummerListingStyleDraft(
          id: $0.id,
          name: $0.name,
          image: $0.imageFile.flatMap { ImageManager.shared.loadImage(fileName: $0) },
          imageFile: $0.imageFile,
          priceText: $0.price.map(String.init) ?? ""
        )
      }
    } else {
      draft.styles = existing.variantOptionNames.map { name in
        MidsummerListingStyleDraft(
          name: name,
          image: seriesStyleImage(for: name),
          imageFile: sourceItem?.variantImageNames?[name],
          priceText: ""
        )
      }
    }
    draft.priceText = existing.price.map(String.init) ?? ""
    draft.preorderText = existing.preorderPrice.map(String.init) ?? ""
    draft.depositText = existing.deposit.map(String.init) ?? ""
    draft.balanceText = existing.balance.map(String.init) ?? ""
    draft.depositEnabled = existing.deposit != nil
    draft.balanceEnabled = existing.balance != nil
    draft.priceKind = existing.priceKind ?? .shop
    draft.note = existing.note
    draft.sourceURL = existing.sourceURL == series?.sourceURL ? "" : existing.sourceURL
    draft.images = existing.imageFiles.compactMap { ImageManager.shared.loadImage(fileName: $0) }

    draft.stage = existing.stage
    draft.launchTitle = existing.launchTitle ?? ""
    draft.hasKnownLaunchDate = existing.hasKnownLaunchDate ?? false
    draft.launchDate = existing.launchDate ?? Date()
    draft.depositMinText = existing.depositMin.map(String.init) ?? ""
    draft.depositMaxText = existing.depositMax.map(String.init) ?? ""
    draft.depositEndsAt = existing.depositEndsAt
    draft.balanceEndsAt = existing.balanceEndsAt
  }

  private func loadPicker(
    _ pickerItem: PhotosPickerItem?,
    apply: @escaping (UIImage?) -> Void
  ) {
    guard let pickerItem else { return }
    Task {
      do {
        if let data = try await pickerItem.loadTransferable(type: Data.self) {
          apply(UIImage(data: data))
        } else {
          apply(nil)
          imageError = "商品图读取失败，请换一张试试。"
        }
      } catch {
        apply(nil)
        imageError = "商品图读取失败，请换一张试试。"
      }
    }
  }

  private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 款式展示名：剥「现 」前缀（与规格抽屉同口径），数据层仍用全名。
  static func displayStyleName(_ name: String) -> String {
    name.hasPrefix("现 ") ? String(name.dropFirst("现 ".count)) : name
  }

  static func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
  }

  // MARK: 通用白卡

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
}
