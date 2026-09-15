import PhotosUI
import SwiftUI

// MARK: - 创作者自主上传入口（千牛「发布宝贝」式分步流程）
//
// 用户要求：严格参照千牛后台商家「发布宝贝」的完整流程——分步填写、
// 每步校验、底部固定操作栏、存草稿、发布成功页。
//
// 两种模式：
//   1. 新建系列  —— 走完整四步：类目与信息 → 系列主图 → 单品与价格 → 预览提交
//   2. 补录单品  —— 系列已存在，直接从「单品与价格」步骤进入（等价于千牛的「编辑宝贝」）
//
// 千牛流程要点 → 本页步骤的对应：
//   千牛第 1 步「选择类目」        → 步骤①：上新阶段（类目的等价物）+ 标题（系列名）
//   千牛第 3 步「基本信息/属性」    → 步骤①：日期、定金区间、尺码配色、简介、原文出处
//   千牛第 4 步「上传图片」        → 步骤②：系列封面（主图位，白底/方图建议）
//   千牛第 5 步「设置 SKU」        → 步骤③：每个单品一张 SKU 卡（款名/类型/价格/主图宫格/尺码表）
//   千牛「提交审核」+ 成功页       → 步骤④：预览汇总 → 提交 → 发布成功页（继续发布 / 完成）
//
// 合规约束（见 docs/品牌上新资讯_开发规格.md §7）：
//   • 入口只对 admin 可见（`isAdminUser` 门控，非 admin 打开 App 完全看不到）
//   • 原文出处 sourceURL 必填 —— Apple 5.2 要求可溯源
//   • 图片长边压到 1200px 再上传，避免吃爆 CloudKit 配额
//   • App 内不做任何爬取，图片由创作者本地选取

struct MidsummerContributeView: View {
  @ObservedObject var store: MidsummerStore
  /// 非空 → 进入「为已有系列补录」模式
  var existingSeries: MidsummerSeriesDTO?

  @Environment(\.dismiss) private var dismiss

  // MARK: 步骤状态

  private enum WizardStep: Int, CaseIterable, Hashable {
    /// 千牛第 1 步：选择类目 + 基本信息与属性
    case basics = 0
    /// 千牛第 4 步：上传图片（这里是系列封面位）
    case cover = 1
    /// 千牛第 5 步：设置 SKU（单品与价格）
    case items = 2
    /// 千牛「提交」前的确认 + 成功页入口
    case review = 3

    var title: String {
      switch self {
      case .basics: return "类目与信息"
      case .cover: return "系列主图"
      case .items: return "单品与价格"
      case .review: return "预览提交"
      }
    }

    var stepTitle: String {
      switch self {
      case .basics: return "① 选择类目与基本信息"
      case .cover: return "② 上传系列主图"
      case .items: return "③ 设置单品与价格（SKU）"
      case .review: return "④ 预览与提交"
      }
    }
  }

  /// 补录模式跳过系列级步骤（千牛「编辑宝贝」直接进商品内容）。
  private var visibleSteps: [WizardStep] {
    isSupplementMode ? [.items, .review] : WizardStep.allCases
  }

  @State private var step: WizardStep = .basics
  /// 当前步骤的校验红字（千牛：必填项不满足时红字提示，不跳步）
  @State private var stepError: String?

  // MARK: 系列字段（步骤①）
  // 注意：这批字段不能标 private——同文件的 DraftSnapshot（存草稿）要直接读写它们。

  @State var seriesName = ""
  @State var hasLaunchDate = true
  @State var launchDate = Date()
  @State var stage: MidsummerStage = .deposit
  /// 定金区间。价格区间**不在这里填**——它由单品价格自动派生（见 buildSeries）。
  @State var depositMinText = ""
  @State var depositMaxText = ""
  @State var selectedSizes: Set<String> = ["S", "M", "L", "XL"]
  @State var colorsText = ""
  @State var summaryText = ""
  @State var sourceURLText = ""

  // MARK: 单品（步骤③）

  @State var draftItems: [DraftItem] = [DraftItem()]

  // MARK: 系列主图（步骤②）

  @State private var photoItem: PhotosPickerItem?
  // 不标 private：同文件的 DraftSnapshot（存草稿）要写入恢复后的封面。
  @State var coverImage: UIImage?

  // MARK: 提交状态

  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var didSucceed = false
  /// 逐单品上传进度（千牛发布路径：每传完一个单品推进一格）
  @State private var uploadStatusText: String?

  // MARK: 草稿（千牛「存草稿」）

  @State private var savedDraft: DraftSnapshot?
  @State private var draftMessage: String?

  private let presetSizes = ["XS", "S", "M", "L", "XL", "均码", "定制"]
  private var isSupplementMode: Bool { existingSeries != nil }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if didSucceed {
          successPage
        } else {
          wizardHeader
          Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)

          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              stepTitleRow
              if let stepError {
                // 千牛式校验红字：必须能被看见，且带定位词（缺哪一步的哪一项）
                Label(stepError, systemImage: "exclamationmark.circle.fill")
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(MidsummerTheme.priceRed)
                  .padding(10)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(MidsummerTheme.orangeSurface)
                  .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                  .accessibilityIdentifier("midsummer-step-error")
              }
              stepContent
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
          }
          .scrollDismissesKeyboard(.interactively)
        }
      }
      .background(MidsummerTheme.pageBackground)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          // 千牛「存草稿」：只对新建模式开放（补录有明确目标，无需草稿）
          if !isSupplementMode && !didSucceed {
            Button("存草稿") { saveDraft() }
              .disabled(isSubmitting)
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if !didSucceed {
          VStack(spacing: 0) {
            // 草稿反馈必须全局可见：千牛在任意步骤都能点「存草稿」，
            // 提示若只画在某一步的内容区里，其他步骤点了就像没反应。
            if let draftMessage {
              Text(draftMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MidsummerTheme.freshGreen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(MidsummerTheme.orangeSurface)
            }
            bottomBar
          }
        }
      }
      .onChange(of: photoItem) { _, newValue in
        Task { await loadPhoto(newValue) }
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
      .onAppear {
        prefill()
        if isSupplementMode {
          step = .items
        }
        savedDraft = DraftSnapshot.load()
      }
    }
  }

  // MARK: 步骤条（千牛发布页顶部的分步导航）

  private var wizardHeader: some View {
    HStack(alignment: .center, spacing: 0) {
      ForEach(Array(visibleSteps.enumerated()), id: \.offset) { pair in
        let index = pair.offset
        let wizardStep = pair.element
        let isCurrent = wizardStep == step
        let isDone = wizardStep.rawValue < step.rawValue

        if index > 0 {
          Rectangle()
            .fill(
              wizardStep.rawValue <= step.rawValue
                ? MidsummerTheme.brandOrange : MidsummerTheme.divider
            )
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
        }

        Button {
          // 只允许往回点（千牛同理：前进必须过校验，回退随意）
          if wizardStep.rawValue < step.rawValue {
            withAnimation(.snappy(duration: 0.18)) {
              step = wizardStep
              stepError = nil
            }
          }
        } label: {
          HStack(spacing: 5) {
            ZStack {
              Circle()
                .fill(
                  isCurrent || isDone
                    ? MidsummerTheme.brandOrange : MidsummerTheme.subtleFill
                )
                .frame(width: 22, height: 22)
              if isDone {
                Image(systemName: "checkmark")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(MidsummerTheme.onAccent)
              } else {
                Text("\(wizardStep.rawValue + 1)")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(
                    isCurrent ? MidsummerTheme.onAccent : MidsummerTheme.secondaryText)
              }
            }
            Text(wizardStep.title)
              .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
              .foregroundStyle(isCurrent ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(wizardStep.rawValue > step.rawValue)
        .accessibilityIdentifier("midsummer-step-\(wizardStep.rawValue)")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(MidsummerTheme.surface)
  }

  private var stepTitleRow: some View {
    Text(step.stepTitle)
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(MidsummerTheme.primaryText)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: 步骤内容分发

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .basics:
      basicsStep
    case .cover:
      coverStep
    case .items:
      itemsStep
    case .review:
      reviewStep
    }
  }

  // MARK: 底部固定操作栏（千牛发布页底部：上一步 / 下一步 / 提交）

  private var bottomBar: some View {
    VStack(spacing: 0) {
      Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)
      HStack(spacing: 10) {
        if canGoBack {
          Button {
            goBack()
          } label: {
            Text("上一步")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(MidsummerTheme.primaryText)
              .frame(height: 42)
              .frame(width: 96)
              .background(MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .disabled(isSubmitting)
          .accessibilityIdentifier("midsummer-step-back")
        }

        Button {
          advance()
        } label: {
          HStack {
            if isSubmitting {
              ProgressView()
                .tint(MidsummerTheme.onAccent)
                .padding(.trailing, 6)
            }
            Text(primaryActionTitle)
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundStyle(MidsummerTheme.onAccent)
          .frame(height: 42)
          .frame(maxWidth: .infinity)
          .background(
            isSubmitting ? MidsummerTheme.brandOrange.opacity(0.6) : MidsummerTheme.brandOrange
          )
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .themeSkinLegibleText(level: .hero, slot: MidsummerThemeSlot.primaryButton)
        }
        .disabled(isSubmitting)
        .accessibilityIdentifier("midsummer-step-next")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(MidsummerTheme.surface)
    }
  }

  private var primaryActionTitle: String {
    if isSubmitting { return "正在上传…" }
    guard let last = visibleSteps.last else { return "提交宝贝信息" }
    return step == last ? "提交宝贝信息" : "下一步"
  }

  /// 千牛交互：「下一步」先校验当前步，不满足则红字提示、不跳步。
  private func advance() {
    guard !isSubmitting else { return }
    if let failure = validateCurrentStep() {
      stepError = failure.message
      return
    }
    stepError = nil
    guard let index = visibleSteps.firstIndex(of: step) else { return }
    if index + 1 < visibleSteps.count {
      withAnimation(.snappy(duration: 0.18)) {
        step = visibleSteps[index + 1]
      }
    } else {
      Task { await submit() }
    }
  }

  private var canGoBack: Bool {
    guard let index = visibleSteps.firstIndex(of: step) else { return false }
    return index > 0
  }

  private func goBack() {
    guard let index = visibleSteps.firstIndex(of: step), index > 0 else { return }
    withAnimation(.snappy(duration: 0.18)) {
      step = visibleSteps[index - 1]
      stepError = nil
    }
  }

  private func validateCurrentStep() -> MidsummerContributeFailure? {
    switch step {
    case .basics:
      // 与整页提交同一套校验器的分步版：只查本步的两个必填
      return MidsummerContributionValidator.validateSeriesName(seriesName)
        ?? MidsummerContributionValidator.validateSourceURL(sourceURLText)
    case .cover, .review:
      return nil
    case .items:
      return MidsummerContributionValidator.validateItems(draftItems.map(\.name))
    }
  }

  // MARK: 步骤① 类目与基本信息（千牛：选择类目 + 基本信息属性）

  private var basicsStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let savedDraft {
        draftRestoreBanner(savedDraft)
      }

      // —— 千牛「选择类目」：上新阶段是本业务里类目的等价物，选错会影响系列页的展示位
      wizardCard("选择上新阶段（类目）", hint: "选错阶段会让系列出现在错误的时间线上，提交前可随时回来改。") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
          ForEach(MidsummerStage.allCases, id: \.self) { candidate in
            let on = candidate == stage
            Button {
              stage = candidate
            } label: {
              HStack(spacing: 4) {
                Image(systemName: on ? "checkmark.circle.fill" : candidate.symbolName)
                  .font(.system(size: 11))
                Text(candidate.labelZH)
                  .font(.system(size: 12, weight: on ? .semibold : .regular))
                  .lineLimit(1)
              }
              .foregroundStyle(on ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 9)
              .background(on ? MidsummerTheme.orangeSurface : MidsummerTheme.subtleFill)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("midsummer-stage-option-\(candidate.rawValue)")
          }
        }
      }

      // —— 千牛「商品标题」：系列名 + 字数计数
      wizardCard("系列标题", hint: "相当于宝贝标题，30 字以内。写清系列主题，方便其他人检索。") {
        TextField("系列名，例如「小熊博物馆系列」", text: $seriesName)
          .font(.system(size: 14))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("midsummer-series-name")

        HStack {
          Toggle("已知上新日期", isOn: $hasLaunchDate)
            .font(.system(size: 13))
          if hasLaunchDate {
            Spacer()
            DatePicker("", selection: $launchDate, displayedComponents: .date)
              .labelsHidden()
              .environment(\.locale, Locale(identifier: "zh_CN"))
          }
        }
        if hasLaunchDate == false {
          Text("公开渠道常常查不到确切日期，关闭后界面会显示「上新日期待补充」。")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
      }

      // —— 千牛「销售属性 / 价格」：定金区间 + 尺码配色
      wizardCard("规格与价格属性", hint: "参考价 / 现货价的区间不用填：由步骤③每个单品的价格自动算出。") {
        HStack {
          Text("定金区间")
            .font(.system(size: 12))
            .foregroundStyle(MidsummerTheme.secondaryText)
          TextField("最低", text: $depositMinText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 13))
            .padding(.vertical, 6)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          Text("–").foregroundStyle(MidsummerTheme.secondaryText)
          TextField("最高", text: $depositMaxText)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 13))
            .padding(.vertical, 6)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
          Text("元").font(.system(size: 11)).foregroundStyle(MidsummerTheme.secondaryText)
        }

        sizeChips

        TextField("配色，用顿号或逗号分隔，例如「粉色、蓝色」", text: $colorsText)
          .font(.system(size: 13))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      // —— 千牛「详情描述」：简介
      wizardCard("系列简介（可选）", hint: "写清版型、柄图或联名背景。请用自己的话概括，不要直接粘贴店铺文案。") {
        TextEditor(text: $summaryText)
          .frame(minHeight: 68)
          .font(.system(size: 13))
          .scrollContentBackground(.hidden)
          .padding(8)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      // —— 原文出处（合规必填，Apple 5.2）
      wizardCard("原文出处（必填）", hint: "内容需要可溯源，这也是商店审核的要求。请勿填写短链或无法访问的地址。") {
        TextField("原文链接（微博 / 淘宝 / 小红书）", text: $sourceURLText)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(.system(size: 13))
          .padding(10)
          .background(MidsummerTheme.subtleFill)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("midsummer-source-url")
      }
    }
  }

  // MARK: 步骤② 系列主图（千牛：上传主图，第 1 张为主图）

  private var coverStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard("系列主图", hint: "用作系列页封面：建议正方形、清晰无水印、只上传你有权使用的图。上传后自动压缩到长边 1200px。") {
        ZStack(alignment: .topTrailing) {
          PhotosPicker(selection: $photoItem, matching: .images) {
            if let coverImage {
              Image(uiImage: coverImage)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
              VStack(spacing: 8) {
                Image(systemName: "camera")
                  .font(.system(size: 26, weight: .light))
                Text("上传主图（封面）")
                  .font(.system(size: 13, weight: .medium))
                Text("点击从相册选取")
                  .font(.system(size: 10))
                  .foregroundStyle(MidsummerTheme.secondaryText)
              }
              .foregroundStyle(MidsummerTheme.secondaryText)
              .frame(height: 200)
              .frame(maxWidth: .infinity)
              .background(MidsummerTheme.subtleFill)
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .strokeBorder(MidsummerTheme.divider, style: StrokeStyle(lineWidth: 1, dash: [5]))
              )
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
          }
          .accessibilityIdentifier("midsummer-cover-picker")

          if coverImage != nil {
            Button {
              coverImage = nil
              photoItem = nil
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(MidsummerTheme.primaryText)
                .shadow(radius: 2)
                .padding(6)
            }
            .accessibilityIdentifier("midsummer-cover-remove")
          }
        }
      }

      // —— 单品预告：提醒下一步要做什么（千牛主图 → SKU 的顺序）
      wizardCard("下一步预告", hint: nil) {
        Label("进入下一步后，为每个单品单独设置 5 张主图宫格、价格与尺码表。", systemImage: "arrow.right.circle")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
    }
  }

  // MARK: 步骤③ 单品与价格（千牛：设置 SKU）

  private var itemsStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      if isSupplementMode, let existingSeries {
        wizardCard("补录目标", hint: "提交后该系列会立即更新，无需等待云端同步。") {
          LabeledContent("系列", value: existingSeries.name)
          LabeledContent("当前收录", value: existingSeries.itemCountText)
          if existingSeries.launchedOn.isEmpty {
            Label("该系列上新日期待补充", systemImage: "exclamationmark.triangle")
              .font(.system(size: 12))
              .foregroundStyle(MidsummerTheme.brandOrange)
          }
        }
      }

      ForEach($draftItems) { $item in
        itemCard(item: $item)
      }
      .onDelete { draftItems.remove(atOffsets: $0) }

      Button {
        draftItems.append(DraftItem(inheritingSizesFrom: selectedSizes))
      } label: {
        Label("添加一个单品", systemImage: "plus.circle")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .accessibilityIdentifier("midsummer-add-item")
    }
  }

  /// 单张 SKU 卡（千牛：每个 SKU 独立的名称 / 价格 / 图片块）
  private func itemCard(item: Binding<DraftItem>) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("单品")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MidsummerTheme.brandOrange)
        Spacer()
        if !isSupplementMode && draftItems.count > 1 {
          Button {
            if let index = draftItems.firstIndex(where: { $0.id == item.wrappedValue.id }) {
              _ = draftItems.remove(at: index)
            }
          } label: {
            Label("删除", systemImage: "trash")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
        }
      }

      // SKU 名称（千牛：SKU 名称）
      TextField("款名，例如「樱花小羊 SK」", text: item.name)
        .font(.system(size: 14, weight: .medium))
        .padding(10)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("midsummer-item-name-\(item.wrappedValue.id)")

      // SKU 规格（千牛：规格属性）
      Picker("类型", selection: item.kind) {
        ForEach(MidsummerItemKind.allCases, id: \.self) { kind in
          Text(kind.shortLabel).tag(kind)
        }
      }
      .pickerStyle(.segmented)

      // SKU 价格（千牛：一口价 / 促销价）。价格三档齐全、按需选填：
      // 现货价（即买即得）/ 预约价（全款预约一次付清）/ 定金 + 尾款（分两次付）。
      // 每档都在表单里露出，避免「只能填现货价和定金尾款、漏掉预约价」。
      VStack(spacing: 8) {
        HStack(spacing: 8) {
          priceField("现货价", text: item.priceText)
          priceField("预约价（全款预约）", text: item.preorderPriceText)
        }
        HStack(spacing: 8) {
          priceField("定金", text: item.depositText)
          priceField("尾款", text: item.balanceText)
        }
      }

      if Int(item.wrappedValue.priceText) != nil {
        Picker("价格口径", selection: item.priceKind) {
          ForEach(MidsummerPriceKind.allCases, id: \.self) { kind in
            Text(kind.labelZH).tag(kind)
          }
        }
        .pickerStyle(.segmented)
        .font(.system(size: 12))
      }

      TextField("备注（价格差异、批次、待补项说明）", text: item.noteText)
        .font(.system(size: 12))
        .padding(10)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      // 单品主图宫格（千牛发布路径）：**每个单品一个独立宫格**，互不共用。
      // 第 1 格主图 → 列表行 / 详情页 / 一键入库；2–5 格附图。
      itemImageGrid(item: item)

      if let pickError = item.wrappedValue.itemImageLoadError {
        Text(pickError)
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.brandOrange)
      }

      // 尺码表上传（双方案设计 §五 使用方式）：复用封面图的 PhotosPicker + 1200px 压缩管线
      //（压缩在 MidsummerCloudService.makeAsset 统一做）。淘宝采集不到尺码表时由此补齐。
      PhotosPicker(selection: item.sizeChartPhotoItem, matching: .images) {
        HStack {
          Label("单品尺码表图（可选）", systemImage: "ruler")
            .font(.system(size: 12))
          Spacer()
          if item.wrappedValue.sizeChartImage != nil {
            Text("已选择")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.freshGreen)
          }
        }
      }
      .accessibilityIdentifier("draft-item-sizechart-picker-\(item.wrappedValue.id)")

      if let sizeChartImage = item.wrappedValue.sizeChartImage {
        Image(uiImage: sizeChartImage)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 120)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      if let pickError = item.wrappedValue.sizeChartLoadError {
        Text(pickError)
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.brandOrange)
      }
    }
    .onChange(of: item.wrappedValue.itemAddPhotoItem) { _, newValue in
      loadDraftImage(newValue, failureMessage: "单品图片读取失败，请换一张试试。") { image, failure in
        item.wrappedValue.itemImageLoadError = failure
        guard let image else { return }
        guard item.wrappedValue.itemImages.count < DraftItem.maxImages else { return }
        item.wrappedValue.itemImages.append(image)
      }
      item.wrappedValue.itemAddPhotoItem = nil
    }
    .onChange(of: item.wrappedValue.itemReplacePhotoItem) { _, newValue in
      loadDraftImage(newValue, failureMessage: "单品图片读取失败，请换一张试试。") { image, failure in
        item.wrappedValue.itemImageLoadError = failure
        guard let image, let index = item.wrappedValue.itemReplaceIndex,
          item.wrappedValue.itemImages.indices.contains(index)
        else { return }
        item.wrappedValue.itemImages[index] = image
      }
      item.wrappedValue.itemReplaceIndex = nil
      item.wrappedValue.itemReplacePhotoItem = nil
    }
    .onChange(of: item.wrappedValue.sizeChartPhotoItem) { _, newValue in
      loadDraftImage(newValue, failureMessage: "尺码表图读取失败，请换一张试试。") { image, failure in
        item.wrappedValue.sizeChartImage = image
        item.wrappedValue.sizeChartLoadError = failure
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

  private func priceField(_ placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(placeholder)
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
      TextField("0", text: text)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 14, weight: .medium))
        .padding(.vertical, 7)
        .background(MidsummerTheme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: 步骤④ 预览与提交（千牛：提交前确认）

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      wizardCard("系列预览", hint: "提交前最后确认。价格区间由单品自动派生，无需在此填写。") {
        LabeledContent("系列名", value: displayName)
        LabeledContent("上新阶段", value: stage.labelZH)
        LabeledContent(
          "上新日期",
          value: hasLaunchDate
            ? Self.dateText(launchDate) : "待补充")
        if Int(depositMinText) != nil || Int(depositMaxText) != nil {
          LabeledContent("定金区间", value: "\(depositMinText)-\(depositMaxText) 元")
        }
        LabeledContent("可用尺码", value: selectedSizes.sorted().joined(separator: " / "))
        if !colorsText.trimmingCharacters(in: .whitespaces).isEmpty {
          LabeledContent("配色", value: colorsText)
        }
        LabeledContent("原文出处", value: sourceURLText)
          .lineLimit(1)
      }

      wizardCard("单品清单（\(namedItemsCount) 个）", hint: nil) {
        ForEach(draftItems.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { item in
          HStack(spacing: 10) {
            if let image = item.itemImages.first {
              Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
              Image(systemName: "photo")
                .font(.system(size: 14))
                .foregroundStyle(MidsummerTheme.secondaryText)
                .frame(width: 44, height: 44)
                .background(MidsummerTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
              Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MidsummerTheme.primaryText)
              Text(item.priceSummary)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MidsummerTheme.priceRed)
            }
            Spacer()
            Text(item.kind.shortLabel)
              .font(.system(size: 10))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
          .padding(.vertical, 2)
        }
        if namedItemsCount == 0 {
          Text("还没有填了款名的单品——回到上一步添加。")
            .font(.system(size: 12))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
      }

      if let uploadStatusText {
        Text(uploadStatusText)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .frame(maxWidth: .infinity, alignment: .center)
          .accessibilityIdentifier("midsummer-upload-status")
      }
    }
  }

  private var displayName: String {
    isSupplementMode ? (existingSeries?.name ?? "") : seriesName
  }

  private var namedItemsCount: Int {
    draftItems.filter {
      !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }.count
  }

  // MARK: 发布成功页（千牛：发布成功 → 继续发布 / 查看宝贝）

  private var successPage: some View {
    VStack(spacing: 18) {
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundStyle(MidsummerTheme.freshGreen)
      Text("发布成功")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
      Text(
        isSupplementMode
          ? "单品已写入「\(existingSeries?.name ?? "")」，其他用户刷新后即可看到。"
          : "系列已写入公共库，其他用户刷新后即可看到。"
      )
      .font(.system(size: 13))
      .foregroundStyle(MidsummerTheme.secondaryText)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 32)

      VStack(spacing: 10) {
        Button {
          // 千牛成功页的「继续发布」：回到第一步，保留尺码选择
          withAnimation(.snappy(duration: 0.18)) {
            didSucceed = false
            uploadStatusText = nil
            seriesName = ""
            summaryText = ""
            colorsText = ""
            depositMinText = ""
            depositMaxText = ""
            sourceURLText = ""
            coverImage = nil
            photoItem = nil
            draftItems = [DraftItem(inheritingSizesFrom: selectedSizes)]
            step = isSupplementMode ? .items : .basics
          }
        } label: {
          Text("继续发布下一个")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MidsummerTheme.onAccent)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(MidsummerTheme.brandOrange)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityIdentifier("midsummer-publish-again")

        Button {
          dismiss()
        } label: {
          Text("完成")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityIdentifier("midsummer-publish-done")
      }
      .padding(.horizontal, 24)
      Spacer()
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MidsummerTheme.pageBackground)
  }

  // MARK: 通用卡片（千牛发布页的白色分区卡）

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

  // MARK: 草稿（千牛「存草稿」）

  private func saveDraft() {
    // 草稿同时只保存一份：先把上一份草稿引用的图片文件清掉，再落新的。
    DraftSnapshot.purgeDraftFiles(of: DraftSnapshot.load())
    let snapshot = DraftSnapshot(from: self)
    snapshot.save()
    savedDraft = snapshot
    withAnimation(.snappy(duration: 0.15)) { draftMessage = "草稿已保存，下次打开可恢复。" }
    Task {
      try? await Task.sleep(nanoseconds: 1_800_000_000)
      withAnimation(.snappy(duration: 0.15)) { draftMessage = nil }
    }
  }

  private func draftRestoreBanner(_ snapshot: DraftSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("检测到 \(Self.dateText(snapshot.savedAt)) 保存的草稿", systemImage: "doc.text")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.primaryText)
        Spacer()
        Button("恢复") {
          snapshot.restore(into: self)
          savedDraft = nil
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MidsummerTheme.brandOrange)
        Button("丢弃", role: .destructive) {
          DraftSnapshot.purgeDraftFiles(of: snapshot)
          DraftSnapshot.clear()
          savedDraft = nil
        }
        .font(.system(size: 12))
        .foregroundStyle(MidsummerTheme.secondaryText)
      }
    }
    .padding(10)
    .background(MidsummerTheme.orangeSurface)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  // MARK: 单品主图宫格（对齐千牛「发布宝贝」主图位）

  private static let gridColumns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

  /// 千牛式主图宫格：第 1 格主图（带「主图」角标），2–5 格附图可「设为主图」，
  /// 每格右上角 × 删除，点图片本体重传替换；未满 5 张时末尾显示「+」添加格。
  private func itemImageGrid(item: Binding<DraftItem>) -> some View {
    LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 8) {
      ForEach(item.wrappedValue.itemImages.indices, id: \.self) { index in
        itemImageCell(item: item, index: index)
      }
      if item.wrappedValue.itemImages.count < DraftItem.maxImages {
        PhotosPicker(selection: item.itemAddPhotoItem, matching: .images) {
          VStack(spacing: 3) {
            Image(systemName: "plus")
              .font(.system(size: 18, weight: .medium))
            Text("添加主图")
              .font(.system(size: 10))
            Text("\(item.wrappedValue.itemImages.count)/\(DraftItem.maxImages)")
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
        .accessibilityIdentifier("draft-item-image-add-\(item.wrappedValue.id)")
      }
    }
  }

  /// 单个主图格：点图 = 替换；右上角 × 删除；非主图提供「设为主图」（移到第 1 格）。
  private func itemImageCell(item: Binding<DraftItem>, index: Int) -> some View {
    ZStack(alignment: .topTrailing) {
      PhotosPicker(selection: item.itemReplacePhotoItem, matching: .images) {
        Image(uiImage: item.wrappedValue.itemImages[index])
          .resizable()
          .scaledToFill()
          .frame(height: 88)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .simultaneousGesture(
        // 点图替换：先记录格位，选择器回值后按 `itemReplaceIndex` 精确替换。
        TapGesture().onEnded { item.wrappedValue.itemReplaceIndex = index }
      )
      .accessibilityIdentifier("draft-item-image-cell-\(item.wrappedValue.id)-\(index)")

      // 删除（千牛主图格右上角的 ×）
      Button {
        _ = item.wrappedValue.itemImages.remove(at: index)
        item.wrappedValue.itemImageLoadError = nil
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.white)
          .shadow(radius: 2)
      }
      .accessibilityIdentifier("draft-item-image-delete-\(item.wrappedValue.id)-\(index)")
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
            let image = item.wrappedValue.itemImages.remove(at: index)
            item.wrappedValue.itemImages.insert(image, at: 0)
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
        .accessibilityIdentifier("draft-item-image-setmain-\(item.wrappedValue.id)-\(index)")
      }
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

  /// 读取单品图片 / 尺码表图的通用加载器。与封面图同一条读取路径（Data → UIImage），
  /// 但失败只写回单条单品的提示，不打断整张表单。
  /// 两类图片各用各的 picker 与字段——入口独立、互不共用。
  private func loadDraftImage(
    _ pickerItem: PhotosPickerItem?,
    failureMessage: String,
    apply: @escaping (UIImage?, String?) -> Void
  ) {
    guard let pickerItem else { return }
    Task {
      do {
        if let data = try await pickerItem.loadTransferable(type: Data.self),
          let image = UIImage(data: data)
        {
          apply(image, nil)
        } else {
          apply(nil, failureMessage)
        }
      } catch {
        apply(nil, failureMessage)
      }
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
    // 单品 DTO 与草稿一一配对：主图宫格和尺码表图都存在草稿上（UI 对象），
    // 提交时各自随**对应的那一个**单品上传——不共享、不串位。
    let itemDraftPairs: [(item: MidsummerItemDTO, images: [UIImage], sizeChartImage: UIImage?)] =
      draftItems
      .compactMap { draft in
        guard let dto = draft.makeItem(seriesID: "", sizes: Array(selectedSizes)) else { return nil }
        return (dto, draft.itemImages, draft.sizeChartImage)
      }
      .filter { !$0.item.name.isEmpty }

    isSubmitting = true
    defer {
      isSubmitting = false
      uploadStatusText = nil
    }

    do {
      // buildSeries 会为每个单品生成真正的 id / seriesID（补录时沿用已有系列 id），
      // 并把带 id 的新单品一并返回——上传必须用这批 DTO。
      // itemDraftPairs 里的 DTO id 还是空串，直接传会触发
      // CKException 'recordName can not be empty' 闪退。
      let (series, newItems) =
        buildSeries(sourceURL: trimmedSource, items: itemDraftPairs.map(\.item))
      let uploadedCoverName = try await MidsummerCloudService.shared.publish(
        series: series, coverImage: coverImage)

      // 千牛发布路径：逐单品上传，宫格图随单品走（第 1 张主图 + 附图）。
      // zip 保证「带 id 的 DTO ↔ 草稿里的图片」按顺序一一配对，不串位。
      let uploadPairs: [(item: MidsummerItemDTO, images: [UIImage], sizeChartImage: UIImage?)] =
        zip(newItems, itemDraftPairs).map { dto, draft in
          (item: dto, images: draft.images, sizeChartImage: draft.sizeChartImage)
        }
      var publishedItems: [MidsummerItemDTO] = []
      for (index, upload) in uploadPairs.enumerated() {
        uploadStatusText =
          upload.images.isEmpty
          ? "正在上传单品（\(index + 1)/\(uploadPairs.count)）：\(upload.item.name)"
          : "正在上传单品图片 \(index + 1)/\(uploadPairs.count)（\(upload.item.name)，\(upload.images.count) 张）…"
        let published = try await MidsummerCloudService.shared.publish(
          item: upload.item, images: upload.images, sizeChartImage: upload.sizeChartImage)
        // 上传时图片已落盘（midsummer-upload- 命名空间），把文件名回填进 DTO，
        // 乐观更新后详情页/列表行立刻有图，不用等云端刷新。
        publishedItems.append(
          Self.itemWithUploadedImages(upload.item, uploaded: published))
      }

      // 乐观更新：不等下一次云端刷新，界面立刻显示（封面/单品图都已回填）
      let historyCount = series.items.count - newItems.count
      let patchedSeries = Self.seriesWithUploadedImages(
        series,
        coverImageName: uploadedCoverName,
        newItems: publishedItems,
        historyCount: historyCount
      )
      store.applyUploaded(series: patchedSeries)
      // 发布成功后清掉草稿（千牛：发布成功草稿即失效），草稿图片一并清理
      DraftSnapshot.purgeDraftFiles(of: DraftSnapshot.load())
      DraftSnapshot.clear()
      savedDraft = nil
      didSucceed = true
    } catch let error as MidsummerUploadError {
      errorMessage = error.errorDescription
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 组装系列 DTO。返回值第二个元素是**本次新提交的单品**（已分配 id / seriesID），
  /// 上传循环必须用它们，而不是 submit 里草稿原始 DTO（那些 id 是空串）。
  private func buildSeries(sourceURL: String, items: [MidsummerItemDTO])
    -> (series: MidsummerSeriesDTO, newItems: [MidsummerItemDTO])
  {
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

    let series = MidsummerSeriesDTO(
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
    return (series, attachedItems)
  }

  /// 把上传返回的本地图片文件名回填进单品 DTO（乐观更新用）。
  private nonisolated static func itemWithUploadedImages(
    _ item: MidsummerItemDTO, uploaded: MidsummerPublishedImages
  ) -> MidsummerItemDTO {
    MidsummerItemDTO(
      id: item.id,
      seriesID: item.seriesID,
      name: item.name,
      kind: item.kind,
      price: item.price,
      preorderPrice: item.preorderPrice,
      deposit: item.deposit,
      balance: item.balance,
      priceKind: item.priceKind,
      priceCapturedOn: item.priceCapturedOn,
      priceNote: item.priceNote,
      sizes: item.sizes,
      colors: item.colors,
      coverImage: uploaded.coverImageName ?? item.coverImage,
      galleryImageNames: uploaded.galleryImageNames.isEmpty
        ? item.galleryImageNames : uploaded.galleryImageNames,
      itemURL: item.itemURL,
      sourceURL: item.sourceURL,
      note: item.note,
      sizeChartImageName: uploaded.sizeChartImageName ?? item.sizeChartImageName,
      variantImageNames: uploaded.variantImageNames.isEmpty ? item.variantImageNames : uploaded.variantImageNames,
      specGroups: item.specGroups,
      skus: item.skus
    )
  }

  /// 用回填后的单品与封面文件名重建系列 DTO（乐观更新用）。
  private nonisolated static func seriesWithUploadedImages(
    _ series: MidsummerSeriesDTO,
    coverImageName: String?,
    newItems: [MidsummerItemDTO],
    historyCount: Int
  ) -> MidsummerSeriesDTO {
    MidsummerSeriesDTO(
      id: series.id,
      name: series.name,
      year: series.year,
      launchedOn: series.launchedOn,
      stage: series.stage,
      coverImage: coverImageName ?? series.coverImage,
      depositMin: series.depositMin,
      depositMax: series.depositMax,
      priceSource: series.priceSource,
      sizes: series.sizes,
      colors: series.colors,
      summary: series.summary,
      sourceURL: series.sourceURL,
      sourceKind: series.sourceKind,
      verified: series.verified,
      items: Array(series.items.prefix(historyCount)) + newItems
    )
  }

  private static func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "M月d日"
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter.string(from: date)
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
      // 文案必须与真实校验一致：本条只查「款名非空」。
      // 旧文案"需要展示图片、价格与尺码"让人以为漏了图价码，实际那些根本不在校验里。
      return "请至少填写一个单品的款名——款名为空的单品不会被保存。价格与尺码可在提交后补录。"
    }
  }
}

nonisolated enum MidsummerContributionValidator {
  /// 分步校验①：系列名（千牛第 1 步必填项）
  static func validateSeriesName(_ seriesName: String) -> MidsummerContributeFailure? {
    seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .missingSeriesName : nil
  }

  /// 分步校验②：原文出处（合规必填，Apple 5.2）
  static func validateSourceURL(_ sourceURLText: String) -> MidsummerContributeFailure? {
    let raw = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: raw),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      url.host != nil
    else {
      return .invalidSourceURL
    }
    return nil
  }

  /// 分步校验③：至少一个有款名的单品（千牛 SKU 步骤）
  static func validateItems(_ itemNames: [String]) -> MidsummerContributeFailure? {
    let hasNamedItem = itemNames.contains {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return hasNamedItem ? nil : .noItems
  }

  static func validate(
    isSupplementMode: Bool,
    seriesName: String,
    sourceURLText: String,
    itemNames: [String]
  ) -> MidsummerContributeFailure? {
    // 补录模式沿用已有系列名，不要求重填
    if !isSupplementMode {
      if let failure = validateSeriesName(seriesName) {
        return failure
      }
    }

    if let failure = validateSourceURL(sourceURLText) {
      return failure
    }

    if !isSupplementMode {
      if let failure = validateItems(itemNames) {
        return failure
      }
    }

    return nil
  }
}

// MARK: - 草稿快照（千牛「存草稿」）
//
// 文字字段进 UserDefaults；图片（UIImage）不进 UserDefaults（会撑爆）——
// 落盘到 ImageManager 的 Images 目录（命名空间 `midsummer-draft-`），快照只存文件名。
// 草稿**同时只保存一份**：同一个 key，且保存新草稿前先清掉上一份引用的图片文件。

struct DraftSnapshot: Codable {
  var savedAt: Date
  var seriesName: String
  var hasLaunchDate: Bool
  var launchDate: Date
  var stageRaw: String
  var depositMinText: String
  var depositMaxText: String
  var selectedSizes: [String]
  var colorsText: String
  var summaryText: String
  var sourceURLText: String
  var coverFile: String?
  var items: [ItemSnapshot]

  struct ItemSnapshot: Codable {
    var name: String
    var kindRaw: String
    var depositText: String
    var balanceText: String
    var priceText: String
    /// 预约价文本。optional：旧草稿 JSON 没有这个 key，缺省解码为 nil（向后兼容）。
    var preorderPriceText: String? = nil
    var priceKindRaw: String
    var noteText: String
    var sizes: [String]
    /// 主图宫格（第 1 张 = 主图）落盘后的文件名。optional + 默认 nil：旧草稿可照常解码。
    var imageFiles: [String]? = nil
    var sizeChartFile: String? = nil
  }

  static let key = "midsummer.publish.draft"

  /// 草稿图片统一放 ImageManager 的 Images 目录，与正式图同目录、前缀区分。
  /// ImageManager 是 @MainActor，这组助手一并标 MainActor（调用方都在视图按钮/提交路径上）。
  @MainActor private static func draftImageURL(_ name: String) -> URL {
    ImageManager.shared.imagesDirectory.appendingPathComponent(name)
  }

  /// 草稿图片落盘，返回文件名（失败返回 nil，文字字段照常保存）。
  @MainActor private static func saveDraftImage(_ image: UIImage, suffix: String) -> String? {
    guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
    let name = "midsummer-draft-\(UUID().uuidString)-\(suffix).jpg"
    do {
      try jpeg.write(to: draftImageURL(name), options: .atomic)
      return name
    } catch {
      print("⚠️ [Midsummer] 草稿图片落盘失败：\(error.localizedDescription)")
      return nil
    }
  }

  @MainActor private static func loadDraftImage(_ name: String?) -> UIImage? {
    guard let name else { return nil }
    guard let data = try? Data(contentsOf: draftImageURL(name)) else { return nil }
    return UIImage(data: data)
  }

  /// 删除一份草稿引用的全部图片文件。
  /// 「只保存一份」的另一半：换新草稿 / 丢弃 / 发布成功时都必须先清旧文件。
  @MainActor static func purgeDraftFiles(of snapshot: DraftSnapshot?) {
    guard let snapshot else { return }
    var names = snapshot.items.flatMap { ($0.imageFiles ?? []) + [$0.sizeChartFile].compactMap { $0 } }
    if let cover = snapshot.coverFile { names.append(cover) }
    for name in names {
      try? FileManager.default.removeItem(at: draftImageURL(name))
    }
  }

  static func load() -> DraftSnapshot? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(DraftSnapshot.self, from: data)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: key)
  }

  @MainActor init(from view: MidsummerContributeView) {
    savedAt = Date()
    seriesName = view.seriesName
    hasLaunchDate = view.hasLaunchDate
    launchDate = view.launchDate
    stageRaw = view.stage.rawValue
    depositMinText = view.depositMinText
    depositMaxText = view.depositMaxText
    selectedSizes = Array(view.selectedSizes)
    colorsText = view.colorsText
    summaryText = view.summaryText
    sourceURLText = view.sourceURLText
    coverFile = view.coverImage.flatMap { Self.saveDraftImage($0, suffix: "cover") }
    items = view.draftItems.map { item in
      ItemSnapshot(
        name: item.name,
        kindRaw: item.kind.rawValue,
        depositText: item.depositText,
        balanceText: item.balanceText,
        priceText: item.priceText,
        preorderPriceText: item.preorderPriceText,
        priceKindRaw: item.priceKind.rawValue,
        noteText: item.noteText,
        sizes: item.sizes,
        imageFiles: item.itemImages.enumerated().compactMap { offset, image in
          Self.saveDraftImage(image, suffix: "img\(offset)")
        },
        sizeChartFile: item.sizeChartImage.flatMap { Self.saveDraftImage($0, suffix: "sizechart") }
      )
    }
  }

  func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: Self.key)
    }
  }

  /// 把快照写回视图状态（含图片：从磁盘读回 UIImage）。主 actor 上调用。
  @MainActor func restore(into view: MidsummerContributeView) {
    view.seriesName = seriesName
    view.hasLaunchDate = hasLaunchDate
    view.launchDate = launchDate
    view.stage = MidsummerStage(rawValue: stageRaw) ?? .deposit
    view.depositMinText = depositMinText
    view.depositMaxText = depositMaxText
    view.selectedSizes = Set(selectedSizes)
    view.colorsText = colorsText
    view.summaryText = summaryText
    view.sourceURLText = sourceURLText
    view.coverImage = Self.loadDraftImage(coverFile)
    view.draftItems = items.map { snapshot in
      var item = DraftItem()
      item.name = snapshot.name
      item.kind = MidsummerItemKind(rawValue: snapshot.kindRaw) ?? .op
      item.depositText = snapshot.depositText
      item.balanceText = snapshot.balanceText
      item.priceText = snapshot.priceText
      item.priceKind = MidsummerPriceKind(rawValue: snapshot.priceKindRaw) ?? .reference
      item.noteText = snapshot.noteText
      item.sizes = snapshot.sizes
      item.itemImages = (snapshot.imageFiles ?? []).compactMap { Self.loadDraftImage($0) }
      item.sizeChartImage = Self.loadDraftImage(snapshot.sizeChartFile)
      return item
    }
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
  /// 预约价（全款预约，元）。与现货价 / 定金尾款并列的第三档价格，
  /// 按商品实际经营方式选填——字段必须齐全，数字不强制三档全填。
  var preorderPriceText = ""
  /// `priceText` 的口径。填了价就必须选一个——否则界面只能猜这个数字是什么，
  /// 这也是价格数据「看起来有、实际不可信」的根源之一。
  var priceKind: MidsummerPriceKind = .reference
  var noteText = ""
  var sizes: [String] = []
  // MARK: 单品主图宫格（对齐千牛发布路径）
  //
  // 千牛「发布宝贝」：每个商品一个 5 格主图位，**第一格为主图**，逐格添加、
  // 单格删除、点图重传、可设主图，满 5 格后添加位消失。这里按同一交互实现：
  //
  /// 主图宫格：最多 5 张，`itemImages[0]` 为主图（列表行 / 详情页 / 一键入库都以它为准）。
  var itemImages: [UIImage] = []
  /// 「+」添加格的选择器暂存
  var itemAddPhotoItem: PhotosPickerItem?
  /// 点已有图 → 替换该格的选择器暂存（宫格内每格共用一个绑定，靠 `itemReplaceIndex` 区分格位）
  var itemReplacePhotoItem: PhotosPickerItem?
  /// 待替换的格位下标（点图时先记录，选择器回值后按它替换）
  var itemReplaceIndex: Int?
  /// 图片读取失败的提示（单条单品一行，不弹全局 alert）
  var itemImageLoadError: String?
  /// 单品主图上限（与千牛发布宝贝一致：5 张，第 1 张为主图）
  static let maxImages = 5
  /// 尺码表图选择器的暂存（双方案设计 §五：补录动作①「拍照/选图传尺码表」）。
  /// 不进 DTO：`PhotosPickerItem` 是 UI 对象；提交时把 `sizeChartImage` 随单品一起上传。
  var sizeChartPhotoItem: PhotosPickerItem?
  var sizeChartImage: UIImage?
  /// 尺码表图读取失败的提示（单条单品一行，不弹全局 alert）
  var sizeChartLoadError: String?

  init() {}

  init(inheritingSizesFrom sizes: Set<String>) {
    self.sizes = Array(sizes).sorted()
  }

  /// 预览/提交用的价格摘要（现货价 > 定金+尾款 > 预约价 > 提示待填）
  var priceSummary: String {
    if let price = Int(priceText) {
      return "¥\(price)"
    }
    let deposit = Int(depositText), balance = Int(balanceText)
    if deposit != nil || balance != nil {
      let parts = [deposit.map { "定金 \($0)" }, balance.map { "尾款 \($0)" }].compactMap { $0 }
      return parts.joined(separator: " + ")
    }
    if let preorder = Int(preorderPriceText) {
      return "预约价 ¥\(preorder)"
    }
    return "价格待填"
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
