import PhotosUI
import SwiftUI

// MARK: - 价格编辑（用户 2026-09-18 · 创作者改价入口）
//
// 背景：上新工作台发布后，界面上没有修改现货价 / 预约价 / 定金 / 尾款的入口，
// 创作者只能删了重发。本文件补齐三条编辑链路：
//   1. `MidsummerPriceValidator`——纯函数校验，口径与上新表单同源：
//      单项整数金额（元）、非负；至少填一项；定金必配预约价且预约价 > 定金；
//      旧档口径预填迁移；供应两个编辑 sheet 与单测共用。
//   2. `MidsummerListingPriceEditSheet`——工作台商品（listing，本地存档）：
//      四类价格 + 商品图宫格（上传 / 替换 / 删除 / 设为主图 / 放大预览），
//      点「保存」才生效（落盘图片 + upsert，updatedAt 触发 feed 重算）。
//   3. `MidsummerItemPriceEditSheet`——种子 / 云端基础条目：价格改动走
//      CloudKit publish（与商品详情编辑同一条链路），保存后全量刷新前端。
//
// 口径说明（用户 2026-09-18 确认）：
//   · 尾款**可手动改**；留空且预约价 / 定金齐全时保存自动按「预约价 − 定金」补上
//     （与表单自动核算规则一致，但不强制等式，手改后不再校验相等）。

// MARK: - 校验后的价格值

nonisolated struct MidsummerPriceValues: Equatable, Sendable {
  var price: Int?  // 现货价
  var preorderPrice: Int?  // 预约价（全款）
  var deposit: Int?  // 定金
  var balance: Int?  // 尾款
}

/// 校验失败文案（包一层以适配 `Result` 的 Error 约束）。
nonisolated struct MidsummerPriceFieldError: Error, Equatable, Sendable {
  let message: String
}

// MARK: - 价格校验（纯函数，与上新表单规则同源）

nonisolated enum MidsummerPriceValidator {

  /// 自动尾款：预约价与定金都填了且差值为正时 = 预约价 − 定金，否则 nil。
  /// 与 `MidsummerListingDraft.autoBalance` 同一条规则。
  static func autoBalance(preorderPrice: Int?, deposit: Int?) -> Int? {
    guard let preorderPrice, let deposit, preorderPrice > deposit else { return nil }
    return preorderPrice - deposit
  }

  /// 单项解析：空白 = 未填（nil）；非纯整数、负数 → 报错文案。
  /// 金额范围沿用表单口径：整数（元），下限 0；超出 Int 可表示范围本身解析失败即报错。
  static func parseAmount(_ text: String, label: String) -> Result<Int?, MidsummerPriceFieldError> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .success(nil) }
    guard let value = Int(trimmed) else {
      return .failure(MidsummerPriceFieldError(message: "\(label) 需填整数金额（元）。"))
    }
    guard value >= 0 else {
      return .failure(MidsummerPriceFieldError(message: "\(label) 不能为负数。"))
    }
    return .success(value)
  }

  /// 编辑面板预填：把历史口径迁移成当前四类价格口径（纯函数，便于单测）。
  ///
  /// · 旧档「定金 + 尾款」缺预约价 → 预约价 = 定金 + 尾款，编辑不丢口径；
  /// · 旧档「只有定金」→ 那是历史「全款预约价存在定金里」的写法（与系列详情
  ///   `priceGroups` 的「只有定金 = 全款预约」同口径），这里迁移成
  ///   「预约价 = 定金、定金留空」，否则一进面板就撞上「定金需配预约价」的必填校验。
  static func prefill(preorderPrice: Int?, deposit: Int?, balance: Int?)
    -> (preorder: Int?, deposit: Int?, didMigrateLegacyDeposit: Bool)
  {
    if let preorderPrice { return (preorderPrice, deposit, false) }
    if let deposit, let balance { return (deposit + balance, deposit, false) }
    if let deposit { return (deposit, nil, true) }
    return (nil, nil, false)
  }

  /// 四类价格整表校验：单项各自合法 + 至少填一项 + 定金与预约价的联动
  ///（后两条与上新表单第 3 步逐字同文案，改价面板不允许写出表单不允许的价格）。
  static func validate(
    price: String, preorder: String, deposit: String, balance: String
  ) -> Result<MidsummerPriceValues, MidsummerPriceFieldError> {
    let fields: [(text: String, label: String)] = [
      (price, "现货价"), (preorder, "预约价"), (deposit, "定金"), (balance, "尾款"),
    ]
    var values = MidsummerPriceValues(price: nil, preorderPrice: nil, deposit: nil, balance: nil)
    for field in fields {
      switch parseAmount(field.text, label: field.label) {
      case .failure(let error):
        return .failure(error)
      case .success(nil):
        continue
      case .success(let value?):
        switch field.label {
        case "现货价": values.price = value
        case "预约价": values.preorderPrice = value
        case "定金": values.deposit = value
        default: values.balance = value
        }
      }
    }
    if values.price == nil, values.preorderPrice == nil, values.deposit == nil,
      values.balance == nil
    {
      return .failure(
        MidsummerPriceFieldError(message: "请至少填写一项价格（现货价 / 预约价 / 定金 / 尾款）。"))
    }
    // 联动校验（与上新表单同文案）：定金是预约链路的一部分，
    // 没有预约价就算不出尾款，定金也不能反过来比预约价还贵。
    if values.deposit != nil, values.preorderPrice == nil {
      return .failure(
        MidsummerPriceFieldError(
          message: "已配置定金：请再填预约价（全款），尾款会自动算出。"))
    }
    if let deposit = values.deposit, let preorder = values.preorderPrice, preorder <= deposit {
      return .failure(
        MidsummerPriceFieldError(
          message: "预约价需大于定金（当前差值 ¥\(preorder - deposit)），否则算不出尾款。"))
    }
    return .success(values)
  }

  /// 保存前的兜底：尾款留空且预约价 / 定金齐全 → 自动按「预约价 − 定金」补上。
  /// 这是表单自动核算规则的延续；手改过的尾款不再被覆盖。
  static func resolvingAutoBalance(_ values: MidsummerPriceValues) -> MidsummerPriceValues {
    var resolved = values
    if resolved.balance == nil,
      let auto = autoBalance(preorderPrice: resolved.preorderPrice, deposit: resolved.deposit)
    {
      resolved.balance = auto
    }
    return resolved
  }

  /// 定金 / 尾款 / 预约价三者齐全时的口径提示（不拦截保存——尾款允许手改）。
  /// `consistent == true` 返回绿色等式文案，否则返回橙色差值说明。
  static func consistencyHint(_ values: MidsummerPriceValues) -> (text: String, consistent: Bool)? {
    guard let deposit = values.deposit, let balance = values.balance,
      let preorder = values.preorderPrice
    else { return nil }
    let sum = deposit + balance
    if sum == preorder {
      return ("定金 ¥\(deposit) + 尾款 ¥\(balance) = 预约价 ¥\(preorder)（口径一致）", true)
    }
    let diff = abs(sum - preorder)
    return ("定金 + 尾款 = ¥\(sum)，与预约价 ¥\(preorder) 相差 ¥\(diff)。", false)
  }
}

// MARK: - 工作台商品 · 价格与商品图编辑（本地链路）

struct MidsummerListingPriceEditSheet: View {
  let listing: MidsummerListing
  /// 保存成功回调（吐司文案由宿主展示）。
  var onSaved: ((String) -> Void)? = nil

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var listingStore = MidsummerListingStore.shared
  /// 角色闸门：改价 / 换图是创作者能力。入口已被宿主门控，这里再守一次——
  /// 面板绕开入口被打开时（状态恢复 / 深链）显示只读说明，不给任何输入与保存。
  @ObservedObject private var creatorAccess = CreatorAccess.shared

  @State private var priceText = ""
  @State private var preorderText = ""
  @State private var depositText = ""
  @State private var balanceText = ""
  /// 旧档「只有定金」被迁移成「预约价 = 定金」时置真，用于给一句说明，
  /// 免得使用者以为面板擅自改了他的数字。
  @State private var didMigrateLegacyDeposit = false
  // 商品图：编辑期间的本地副本；用户动过图才在保存时重新落盘（避免无谓重编码）。
  @State private var images: [UIImage] = []
  @State private var imagesDirty = false
  // 款式图副本：款式图与商品图共用 `midsummer-listing-<id>` 命名空间，
  // saveImages（替换语义）会按前缀把款式图文件一并清掉——与上新表单同序，
  // 必须在 saveImages **之前**先把款式图读进内存，之后按原槽位重写回磁盘。
  @State private var styleImages: [Int: UIImage] = [:]
  @State private var errorText: String?
  @State private var isSaving = false

  private let maxImages = 5

  /// 尾款自动参考值：预约价 / 定金齐全且尾款留空时展示。
  private var autoBalanceHint: Int? {
    guard balanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return MidsummerPriceValidator.autoBalance(
      preorderPrice: Int(preorderText.trimmingCharacters(in: .whitespacesAndNewlines)),
      deposit: Int(depositText.trimmingCharacters(in: .whitespacesAndNewlines)))
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
          Text(listing.name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(2)

          if !creatorAccess.isCreator {
            MidsummerCreatorOnlyNotice(operation: .priceEdit)
          } else {
          priceCard
          MidsummerPriceImageGrid(
            images: $images,
            maxImages: maxImages,
            note: "第 1 张为主图；改动在点「保存」后生效，🔍 可放大预览。"
          ) {
            imagesDirty = true
          }
          }

          if let errorText {
            Label(errorText, systemImage: "exclamationmark.circle.fill")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.priceRed)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .accessibilityIdentifier("price-edit-error")
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MidsummerTheme.pageBackground)
      .navigationTitle("编辑价格与商品图")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .accessibilityIdentifier("price-edit-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          if isSaving {
            ProgressView()
          } else if creatorAccess.isCreator {
            Button("保存") { save() }
              .disabled(isSaving)
              .accessibilityIdentifier("price-edit-save")
          }
        }
      }
      .onAppear(perform: prefill)
    }
  }

  // MARK: 价格卡

  private var priceCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("价格（元）")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)

      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8
      ) {
        priceField("现货价", text: $priceText, identifier: "price-edit-shop")
        priceField("预约价（全款）", text: $preorderText, identifier: "price-edit-preorder")
        priceField("定金", text: $depositText, identifier: "price-edit-deposit")
        priceField("尾款", text: $balanceText, identifier: "price-edit-balance")
      }

      if didMigrateLegacyDeposit {
        Text("旧档把全款预约价记在「定金」上，已按预约价预填；要拆成定金 + 尾款，填定金即可，尾款自动算出。")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .accessibilityIdentifier("price-edit-legacy-hint")
      }
      if let auto = autoBalanceHint {
        Text("尾款留空时自动按「预约价 − 定金 = ¥\(auto)」计算；也可直接填写覆盖。")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .accessibilityIdentifier("price-edit-auto-hint")
      }
      if let hint = currentConsistencyHint {
        Text(hint.text)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(hint.consistent ? MidsummerTheme.freshGreen : MidsummerTheme.brandOrange)
          .accessibilityIdentifier("price-edit-consistency")
      }
      Text("金额为整数（元）；留空即清除该档价格，至少保留一项。")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
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

  private var currentConsistencyHint: (text: String, consistent: Bool)? {
    MidsummerPriceValidator.consistencyHint(
      MidsummerPriceValues(
        price: nil,
        preorderPrice: Int(preorderText.trimmingCharacters(in: .whitespacesAndNewlines)),
        deposit: Int(depositText.trimmingCharacters(in: .whitespacesAndNewlines)),
        balance: Int(balanceText.trimmingCharacters(in: .whitespacesAndNewlines))
      ))
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

  // MARK: 预填与保存

  private func prefill() {
    priceText = listing.price.map(String.init) ?? ""
    // 旧档口径迁移：定金+尾款 → 补预约价；只有定金 → 视作全款预约价。
    let filled = MidsummerPriceValidator.prefill(
      preorderPrice: listing.preorderPrice, deposit: listing.deposit, balance: listing.balance)
    preorderText = filled.preorder.map(String.init) ?? ""
    depositText = filled.deposit.map(String.init) ?? ""
    didMigrateLegacyDeposit = filled.didMigrateLegacyDeposit
    balanceText = listing.balance.map(String.init) ?? ""
    images = listing.imageFiles.compactMap { ImageManager.shared.loadImage(fileName: $0) }
    styleImages = [:]
    for (index, style) in (listing.styles ?? []).enumerated() {
      styleImages[index] = style.imageFile.flatMap { ImageManager.shared.loadImage(fileName: $0) }
    }
  }

  private func save() {
    guard !isSaving else { return }
    // 两类内容（创作者自建 listing / 平台历史与导入条目）共用同一条校验与保存口径，
    // 差别只在落哪里：本面板落本地存档，基础条目面板发布到 CloudKit。
    do {
      try CreatorAccess.requireCreator(.priceEdit)
    } catch {
      errorText = error.userMessage
      return
    }
    let values: MidsummerPriceValues
    switch MidsummerPriceValidator.validate(
      price: priceText, preorder: preorderText, deposit: depositText, balance: balanceText)
    {
    case .failure(let error):
      errorText = error.message
      return
    case .success(let raw):
      values = MidsummerPriceValidator.resolvingAutoBalance(raw)
    }

    isSaving = true
    defer { isSaving = false }

    var updated = listing
    updated.price = values.price
    updated.preorderPrice = values.preorderPrice
    updated.deposit = values.deposit
    updated.balance = values.balance
    // 有现货价必须自报口径：原本无口径时按现货价口径补上；已有口径保留
    //（只改数字不改口径）；清空现货价则口径一并清。
    if values.price == nil {
      updated.priceKind = nil
    } else if updated.priceKind == nil {
      updated.priceKind = .shop
    }
    do {
      if imagesDirty {
        // 替换语义落盘：saveImages 按前缀清旧图（含款式图），款式图内存副本
        // 在 prefill 时已读出，这里按原槽位重写回磁盘（与表单保存同序）。
        updated.imageFiles = try listingStore.saveImages(images, listingID: listing.id)
        try restoreStyleImages(of: &updated)
      }

      try listingStore.upsert(updated, operation: .priceEdit)
    } catch {
      // 权限被拒 / 落盘失败都在面板内说清楚，不静默关闭。
      errorText = error.userMessage
      return
    }
    onSaved?("已更新「\(updated.name)」价格，列表与详情已刷新。")
    dismiss()
  }

  /// 款式图按原槽位重写（文件已被 saveImages 清掉）；原本无图的款式位不动，
  /// 没有内存副本的历史文件名原样保留（不乱猜）。
  private func restoreStyleImages(of listing: inout MidsummerListing) throws {
    guard var styles = listing.styles, !styles.isEmpty else { return }
    for index in styles.indices {
      if let image = styleImages[index] {
        styles[index].imageFile = try listingStore.saveStyleImage(
          image, listingID: listing.id, index: index)
      }
    }
    listing.styles = styles
  }
}

// MARK: - 只读提示（非创作者落到编辑面板时的兜底）

/// 非创作者进入任何编辑面板时展示：说清缺什么权限，不渲染输入与保存。
struct MidsummerCreatorOnlyNotice: View {
  let operation: CreatorOperation

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("「\(operation.labelZH)」仅创作者可用")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
      Text(CreatorAccess.shared.isCreator ? "" : CreatorAccess.shared.deniedGuidance)
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(MidsummerTheme.subtleFill)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityIdentifier("creator-only-notice")
  }
}

// MARK: - 基础条目（种子 / 云端单品）· 价格编辑（CloudKit 链路）

struct MidsummerItemPriceEditSheet: View {
  let item: MidsummerItemDTO

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var store = MidsummerStore.shared
  /// 角色闸门：历史内容与外部渠道导入的条目同样只有创作者能改价 / 换图。
  /// 内容与来源不限（种子 / 云端 / 导入的条目一视同仁），只看角色。
  @ObservedObject private var creatorAccess = CreatorAccess.shared

  @State private var priceText = ""
  @State private var preorderText = ""
  @State private var depositText = ""
  @State private var balanceText = ""
  /// 旧档「只有定金」被迁移成「预约价 = 定金」时置真（与工作台面板同口径）。
  @State private var didMigrateLegacyDeposit = false
  /// 商品图（主图 + 附图）的本地副本；动过才随保存一起发布到云端。
  @State private var images: [UIImage] = []
  @State private var imagesDirty = false
  @State private var errorText: String?
  @State private var isSaving = false

  private let maxImages = 5

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
          Text(item.name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(2)
          Text("该条目属于系列基础资料：价格与商品图改动会发布到云端公共库，其他用户刷新后可见。")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)

          if !creatorAccess.isCreator {
            MidsummerCreatorOnlyNotice(operation: .priceEdit)
          } else {
            priceFieldsCard
            MidsummerPriceImageGrid(
              images: $images,
              maxImages: maxImages,
              note: "第 1 张为主图；改动在点「保存」后随价格一起发布，🔍 可放大预览。"
            ) {
              imagesDirty = true
            }
          }

          if let errorText {
            Label(errorText, systemImage: "exclamationmark.circle.fill")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.priceRed)
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .accessibilityIdentifier("price-edit-error")
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MidsummerTheme.pageBackground)
      .navigationTitle("编辑价格")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .accessibilityIdentifier("price-edit-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          if isSaving {
            ProgressView()
          } else if creatorAccess.isCreator {
            Button("保存") { Task { await save() } }
              .disabled(isSaving)
              .accessibilityIdentifier("price-edit-save")
          }
        }
      }
      .onAppear(perform: prefill)
    }
  }

  private var priceFieldsCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("价格（元）")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8
      ) {
        priceField("现货价", text: $priceText, identifier: "price-edit-shop")
        priceField("预约价（全款）", text: $preorderText, identifier: "price-edit-preorder")
        priceField("定金", text: $depositText, identifier: "price-edit-deposit")
        priceField("尾款", text: $balanceText, identifier: "price-edit-balance")
      }
      Text("金额为整数（元）；留空即清除该档价格，至少保留一项。")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
      if didMigrateLegacyDeposit {
        Text("旧档把全款预约价记在「定金」上，已按预约价预填；要拆成定金 + 尾款，填定金即可，尾款自动算出。")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .accessibilityIdentifier("price-edit-legacy-hint")
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

  private func prefill() {
    priceText = item.price.map(String.init) ?? ""
    // 旧档口径迁移（与工作台面板同口径）：定金+尾款 → 补预约价；只有定金 → 全款预约价。
    let filled = MidsummerPriceValidator.prefill(
      preorderPrice: item.preorderPrice, deposit: item.deposit, balance: item.balance)
    preorderText = filled.preorder.map(String.init) ?? ""
    depositText = filled.deposit.map(String.init) ?? ""
    didMigrateLegacyDeposit = filled.didMigrateLegacyDeposit
    balanceText = item.balance.map(String.init) ?? ""
    let names = ([item.coverImage] + (item.galleryImageNames ?? [])).compactMap { $0 }
    images = names.compactMap { ImageManager.shared.loadImage(fileName: $0) }
  }

  /// 价格改动发布到云端：与商品详情编辑同一条 publish 链路（整条重写，
  /// 主图 / 附图 / 款式图按现存文件一并带上，缺一即被抹掉）。
  private func save() async {
    guard !isSaving else { return }
    // 与工作台面板同口径：先过角色校验，再用同一个校验器走同一套数据校验。
    do {
      try CreatorAccess.requireCreator(.priceEdit)
    } catch {
      errorText = error.userMessage
      return
    }
    let values: MidsummerPriceValues
    switch MidsummerPriceValidator.validate(
      price: priceText, preorder: preorderText, deposit: depositText, balance: balanceText)
    {
    case .failure(let error):
      errorText = error.message
      return
    case .success(let raw):
      values = MidsummerPriceValidator.resolvingAutoBalance(raw)
    }

    isSaving = true
    defer { isSaving = false }

    let priceTouched = values.price != item.price
    let updated = MidsummerItemDTO(
      id: item.id,
      seriesID: item.seriesID,
      name: item.name,
      kind: item.kind,
      price: values.price,
      preorderPrice: values.preorderPrice,
      deposit: values.deposit,
      balance: values.balance,
      priceKind: priceKind(for: values),
      priceCapturedOn: priceCapturedOn(priceTouched: priceTouched, newValue: values.price),
      priceNote: item.priceNote,
      sizes: item.sizes,
      colors: item.colors,
      coverImage: item.coverImage,
      galleryImageNames: item.galleryImageNames,
      itemURL: item.itemURL,
      sourceURL: item.sourceURL,
      note: item.note,
      sizeChartImages: item.sizeChartImages,
      variantImageNames: item.variantImageNames,
      specGroups: item.specGroups,
      skus: item.skus
    )

    do {
      // 商品图：动过就用编辑后的宫格（第 1 张 = 主图）；没动过按现存文件原样带过去，
      // publish 是整条重写，缺一即被抹掉。
      let imagesToPublish = imagesDirty ? images : Self.existingImages(of: item)
      let variantEntries: [(name: String, image: UIImage)] = (item.variantImageNames ?? [:])
        .compactMap { key, file in
          guard let image = ImageManager.shared.loadImage(fileName: file) else { return nil }
          return (key, image)
        }
      _ = try await MidsummerCloudService.shared.publish(
        item: updated,
        images: imagesToPublish,
        sizeChartImage: nil,
        variantImages: variantEntries
      )
      // 全量回读：价格总表 / 卡片 / 详情价格行立即拿到新数字。
      await MidsummerStore.shared.refreshFromCloud()
      dismiss()
    } catch {
      // 权限拒绝用它的原话（带原因与怎么办），其余沿用系统描述。
      errorText =
        (error as? CreatorAccessDenied) != nil
        ? error.userMessage : "保存失败：\(error.localizedDescription)"
    }
  }

  /// 口径规则：清空现货价 → 口径一并清；新填现货价且原本无口径 → 现货价口径；
  /// 原有口径保留（只改数字不改口径）。
  private func priceKind(for values: MidsummerPriceValues) -> MidsummerPriceKind? {
    if values.price == nil { return nil }
    return item.priceKind ?? .shop
  }

  /// 价格采集日：改动了现货价才更新为今天（价格会变，没有采集日的价格无法判断时效）。
  private func priceCapturedOn(priceTouched: Bool, newValue: Int?) -> String? {
    if !priceTouched { return item.priceCapturedOn }
    return newValue == nil ? nil : MidsummerListing.todayStamp()
  }

  /// 现存主图 + 附图（按文件名顺序，第 1 张为主图）。
  private static func existingImages(of item: MidsummerItemDTO) -> [UIImage] {
    let names = ([item.coverImage] + (item.galleryImageNames ?? [])).compactMap { $0 }
    return names.compactMap { ImageManager.shared.loadImage(fileName: $0) }
  }
}

// MARK: - 商品图宫格（两个改价面板共用）

/// 商品图编辑宫格：添加 / 点图替换 / 删除 / 设为主图 / 🔍 放大预览。
///
/// 改动只落在内存里的 `images`，由宿主在「保存」时统一落盘（工作台商品）
/// 或发布到云端（基础条目）——与上新表单同一手感：**不点保存不生效**。
/// 工作台商品与基础条目共用同一套 identifier，两个面板不会同时打开。
struct MidsummerPriceImageGrid: View {
  @Binding var images: [UIImage]
  var maxImages: Int = 5
  var title: String = "商品图"
  /// 卡尾说明（宿主按链路写：本地落盘 / 云端发布）。
  var note: String = ""
  /// 每次改动回调（宿主用它打 dirty 标记）。
  var onChange: () -> Void = {}

  @State private var addPhotoItem: PhotosPickerItem?
  @State private var replacePhotoItem: PhotosPickerItem?
  @State private var replaceIndex: Int?
  @State private var previewIndex: Int?
  @State private var message: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("\(title)（最多 \(maxImages) 张）")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
      grid
      if !note.isEmpty {
        Text(note)
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
    .sheet(isPresented: previewBinding) { imagePreviewSheet }
    .onChange(of: addPhotoItem) { _, newValue in
      loadPicker(newValue) { image in
        guard let image else { return }
        guard images.count < maxImages else {
          message = "最多 \(maxImages) 张商品图，先删一张再添加。"
          return
        }
        images.append(image)
        onChange()
        message = nil
      }
      addPhotoItem = nil
    }
    .onChange(of: replacePhotoItem) { _, newValue in
      loadPicker(newValue) { image in
        guard let image, let index = replaceIndex, images.indices.contains(index) else { return }
        images[index] = image
        onChange()
      }
      replaceIndex = nil
      replacePhotoItem = nil
    }
  }

  private var grid: some View {
    VStack(spacing: 8) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8
      ) {
        ForEach(images.indices, id: \.self) { index in
          imageCell(index)
        }
        if images.count < maxImages {
          PhotosPicker(selection: $addPhotoItem, matching: .images) {
            VStack(spacing: 3) {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
              Text("添加商品图")
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
          .accessibilityIdentifier("price-edit-image-add")
        }
      }
      if let message {
        Text(message)
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .accessibilityIdentifier("price-edit-image-error")
      }
    }
  }

  private func imageCell(_ index: Int) -> some View {
    ZStack(alignment: .topTrailing) {
      // 点图 = 替换（与上新表单一致的手感）
      PhotosPicker(selection: $replacePhotoItem, matching: .images) {
        Image(uiImage: images[index])
          .resizable()
          .scaledToFill()
          .frame(height: 88)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .simultaneousGesture(TapGesture().onEnded { replaceIndex = index })
      .accessibilityIdentifier("price-edit-image-cell-\(index)")

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
        .accessibilityIdentifier("price-edit-image-preview-\(index)")
        .accessibilityLabel("放大预览商品图")

        Button {
          _ = images.remove(at: index)
          onChange()
          message = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("price-edit-image-delete-\(index)")
        .accessibilityLabel("删除商品图")
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
            let image = images.remove(at: index)
            images.insert(image, at: 0)
          }
          onChange()
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
        .accessibilityIdentifier("price-edit-image-setmain-\(index)")
      }
    }
  }

  private var previewBinding: Binding<Bool> {
    Binding(
      get: { previewIndex != nil },
      set: { if !$0 { previewIndex = nil } }
    )
  }

  /// 放大预览：全屏 scaledToFit，非主图可顺手「设为主图」。
  private var imagePreviewSheet: some View {
    NavigationStack {
      Group {
        if let index = previewIndex, images.indices.contains(index) {
          Image(uiImage: images[index])
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
            .accessibilityIdentifier("price-edit-image-preview-close")
        }
        if let index = previewIndex, index > 0 {
          ToolbarItem(placement: .topBarTrailing) {
            Button("设为主图") {
              let image = images.remove(at: index)
              images.insert(image, at: 0)
              onChange()
              previewIndex = nil
            }
            .accessibilityIdentifier("price-edit-image-preview-setmain")
          }
        }
      }
    }
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
          message = "商品图读取失败，请换一张试试。"
        }
      } catch {
        apply(nil)
        message = "商品图读取失败，请换一张试试。"
      }
    }
  }
}
