import Foundation
import SwiftData

// MARK: - 仲夏物语 → 衣橱
//
// 使用者要求「每个商品都要有直接加入衣橱的入口」。仲夏物语此前只有浏览与投稿，
// **完全没有接入衣橱**：商品卡右侧的 `bag.badge.plus` 只是个装饰图标，
// 详情弹窗里也只有「查看原文出处 / 完成」。本轮把两种形态都补上。
//
// 形态与日牌商品完全对齐（都由 `TimeHallWardrobeInsertMode` 定义）：
//   · A 一键入库   —— 不打开编辑页，直接落库
//   · B 加入并编辑 —— 跳衣橱编辑页并预填
//
// 落库统一走 `TimeHallWardrobeQuickInserter`，避免两条路径各写一份写库逻辑而走偏。

@MainActor
enum MidsummerWardrobeDraftBuilder {

  /// 把仲夏物语单品转成衣橱草稿。
  ///
  /// 与日牌不同的是：仲夏物语的价格是**人民币**（种子来自微博/淘宝上新贴），
  /// 且「预售」优先用「定金」表述，所以价格落到 `originalPrice`(CNY) 与 `deposit`，
  /// 而不是日牌的 JPY 字段。
  ///
  /// 字段解析口径（用户 2026-09-18，国牌店铺统一）：
  ///   · **类型**：优先从款式名解析（「sk 粉色」→ SK、「无腰op粉色」→ OP），
  ///     解析不出回退单品自带分类——款式名是创作者在表单里按「分类名+颜色」
  ///     规则生成的，比单品级分类更贴近使用者实际买的那件；
  ///   · **颜色**：显式选中的颜色分类 > 款式名解析出的颜色 > 单品自带配色；
  ///   · **尺码**：用户在规格抽屉里实际选的尺码（无尺码款留空，不硬塞）；
  ///   · **价格**：定金尾款类型 → `deposit` / `balance` 分别落定金与尾款、
  ///     `isDepositPlan = true`、总额 = 预约价（定金+尾款）；现货类型 →
  ///     SKU 逐款价 > 现货价 > 预约价。
  ///
  /// - Parameters:
  ///   - selection: 规格选择（颜色分类 / 尺码 / …）。缺省 `.empty` 表示不选规格，
  ///     此时配色与尺码沿用单品自带值——这是卡片上「快速入库」的路径。
  ///   - quantity: 入库数量。**没有上限**，也不做任何库存校验（见
  ///     `MidsummerSpecResolver` 顶部的产品差异说明）。
  ///   - extraNoteLines: 追加到备注末尾的行（多选套装入库用它写套装标记与成员，
  ///     普通单件入库不传，保持备注与旧版逐字一致）。
  ///   - presalePhase: 当前预售相位（由调用方从 `MidsummerListingStore` 查询后
  ///     传入；nil = 不走定金-尾款状态机）。决定价格口径与心愿尾款同步行为，
  ///     规则见下方价格口径注释。
  static func makeDraft(
    for item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selection: MidsummerSpecSelection = .empty,
    quantity: Int = 1,
    extraNoteLines: [String] = [],
    presalePhase: MidsummerPresalePhase? = nil,
    modelContext: ModelContext
  ) -> ClothingEditDraft {
    let now = Date()
    let mapping = MidsummerSpecResolver.wardrobeMapping(selection, of: item)

    // 类型 / 颜色：从款式名解析（用户 2026-09-18 入库口径）。
    let variantName = MidsummerSpecResolver.selectedVariantName(selection, of: item)
    let parsed = MidsummerSpecResolver.parseVariantFields(variantName ?? "")
    let resolvedTypes = parsed.type?.shortLabel ?? item.kind.shortLabel
    // 颜色优先级：显式颜色分类 > 款式名解析 > 单品自带（wardrobeMapping 的 fallback）。
    let resolvedColors: String
    if let explicit = MidsummerSpecResolver.selectedColorName(selection, of: item) {
      resolvedColors = explicit
    } else if let parsedColor = parsed.color {
      resolvedColors = parsedColor
    } else {
      resolvedColors = mapping.colors
    }
    // 尺码：只认用户实际选的；没选（无尺码款 / 未选）回退单品自带尺码。
    let resolvedSizes = MidsummerSpecResolver.selectedSizeName(selection, of: item)
      ?? mapping.sizes

    var noteLines: [String] = []
    noteLines.append("系列：\(series.name)")
    // 归集商品（一个链接含多款）把款式拼进名称，否则 9 个款式入库后全叫同一个名字。
    if let variant = MidsummerSpecResolver.selectedVariantName(selection, of: item) {
      noteLines.append("款式：\(variant)")
    }
    if !series.launchedOn.isEmpty {
      noteLines.append("上新日期：\(series.launchDateText)")
    }
    if let specText = mapping.specText {
      noteLines.append("已选规格：\(specText)")
    }
    if !item.sizes.isEmpty && mapping.sizes != item.sizes.joined(separator: ", ") {
      noteLines.append("该单品可选尺码：\(item.sizesText)")
    }
    if !item.colors.isEmpty && mapping.colors != item.colors.joined(separator: ", ") {
      noteLines.append("该单品可选配色：\(item.colors.joined(separator: " / "))")
    }
    if let note = item.note, !note.isEmpty {
      noteLines.append("备注：\(note)")
    }
    let source = item.itemURL.flatMap { $0.isEmpty ? nil : $0 } ?? item.sourceURL
    if !source.isEmpty {
      noteLines.append("原文出处：\(source)")
    }
    noteLines.append(contentsOf: extraNoteLines)

    // 价格口径（用户 2026-09-18，2026-09-19 按预售相位细分）：
    //   · **定金期 / 尾款期** → 一键加入定金：恒走定金尾款口径（这一阶段
    //     要付的就是定金），`isDepositPlan = true` 即同步心愿尾款，商品
    //     同时落衣橱；定金 / 尾款分别落 `deposit` / `balance`，总额 = 预约价
    //     （尾款缺省按「预约价 − 定金」推——与上新表单「尾款 = 预约价 − 定金」
    //     的生成规则互为逆运算）；
    //   · **预售结束** → 预约价与现货价同时可选：规格面板显式选「现货价」
    //     走现货口径，显式选「定金 / 尾款 / 预约价」走定金尾款口径；没选档位
    //     时现货价优先（面板默认选中项即现货价），无现货价回退定金尾款；
    //   · **不走状态机（phase = nil）** → 沿用旧口径：有定金即定金尾款；
    //     显式选了「现货价」也尊重（种子商品可两档并存）。
    // 现货口径 → SKU 逐款价 > 现货价 > 预约价（不把定金当价格写）。
    let tierPick = MidsummerSpecResolver.selectedPriceTier(selection, of: item)
    let isDepositPlan: Bool
    switch presalePhase {
    case .deposit, .balance:
      isDepositPlan = item.deposit != nil
    case .ended:
      if let tierPick {
        isDepositPlan = tierPick != .spot
      } else {
        isDepositPlan = item.price == nil && item.deposit != nil
      }
    case .none:
      isDepositPlan = tierPick == .spot ? false : item.deposit != nil
    }
    // 现货口径（预售结束选现货档）商品可能自带定金数据——落库时清零，
    // 避免出现「非定金计划却挂着定金/尾款」的自相矛盾记录。
    let depositAmount = isDepositPlan ? (item.deposit ?? 0) : 0
    let balanceAmount = isDepositPlan
      ? (item.balance ?? (item.preorderPrice.map { $0 - (item.deposit ?? 0) }) ?? 0)
      : 0
    let totalAmount: Int
    if isDepositPlan {
      totalAmount = item.preorderPrice ?? (depositAmount + balanceAmount)
    } else {
      totalAmount = MidsummerSpecResolver.price(for: selection, of: item)
        ?? item.price ?? item.preorderPrice ?? item.balance ?? item.deposit ?? 0
    }

    // 定金尾款类型的库存记录要把价格构成写清楚，衣橱侧一眼可读。
    if isDepositPlan {
      noteLines.append("价格口径：定金 ¥\(depositAmount) + 尾款 ¥\(balanceAmount) = 预约价 ¥\(totalAmount)")
      // 尾款时间同步（用户 2026-09-19）：定金截止 = 尾款开始，尾款截止 =
      // 尾款结束，随入库写进 `finalPaymentDate` / `finalPaymentEndDate`，
      // 心愿尾款页 / 日历 / 尾款提醒直接可读。创作者之后在表单里更新尾款
      // 时间只影响新入库的记录——已入库记录是快照，衣橱侧可手动改。
      if item.depositEndsAt != nil || item.balanceEndsAt != nil {
        noteLines.append("尾款时间：\(Self.balanceWindowText(item))（已同步心愿尾款）")
      }
    }

    // 尺码表随单品入库（双方案设计 §四.2）：`Clothing.sizeChartImagePath` 字段已存在，
    // 衣橱侧零改动——草稿带上文件名，落库由 `TimeHallWardrobeQuickInserter` 统一写。
    let sizeChartName = item.sizeChartImageName
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }

    // 尾款窗口：定金截止 = 尾款开始，尾款截止 = 尾款结束；没配截止时间
    // 退回当前时刻（与旧行为一致，不会把「未配置」变成无穷远）。
    let balanceWindow = Self.balanceWindow(of: item, fallback: now)

    return ClothingEditDraft(
      name: MidsummerSpecResolver.displayName(item, selection: selection),
      brandName: brandName,
      types: resolvedTypes,
      colors: resolvedColors,
      sizes: resolvedSizes,
      length: "",
      condition: "全新",
      accessories: "",
      imagePaths: [],
      isShared: false,
      originalPrice: Double(totalAmount),
      originalPriceJPY: 0,
      originalPriceCurrencyCode: ClothingPriceCurrency.cny.rawValue,
      priceTotal: Double(totalAmount),
      deposit: Double(depositAmount),
      balance: Double(balanceAmount),
      accessoriesPrice: 0,
      // 不限数量：直接用使用者填的数量，最低 1。这里**不做**任何库存校验。
      stock: max(1, quantity),
      purchaseDate: now,
      depositDate: now,
      isDepositPlan: isDepositPlan,
      reservationKindRawValue: ClothingReservationKind.owned.rawValue,
      finalPaymentDate: isDepositPlan ? balanceWindow.start : now,
      finalPaymentEndDate: isDepositPlan ? balanceWindow.end : now,
      note: noteLines.joined(separator: "\n"),
      accessoryList: [],
      sizeChartImagePath: sizeChartName
    )
  }

  // MARK: 尾款窗口（心愿尾款同步，用户 2026-09-19）

  /// 尾款窗口：`(start, end)` =（定金截止，尾款截止）。
  /// 任一缺省退回 `fallback`（当前时刻）；配置倒挂时按开始时刻压平，
  /// 保证 `end >= start`（衣橱编辑页对窗口有「结束不早于开始」的约束）。
  static func balanceWindow(of item: MidsummerItemDTO, fallback: Date) -> (start: Date, end: Date) {
    let start = item.depositEndsAt ?? fallback
    let end = max(item.balanceEndsAt ?? start, start)
    return (start, end)
  }

  private static let balanceWindowFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy年M月d日"
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter
  }()

  /// 尾款窗口的备注文案：「2026年9月25日」或「2026年9月25日 – 2026年10月10日」。
  static func balanceWindowText(_ item: MidsummerItemDTO) -> String {
    let window = balanceWindow(of: item, fallback: Date())
    let start = balanceWindowFormatter.string(from: window.start)
    let end = balanceWindowFormatter.string(from: window.end)
    return Calendar.current.isDate(window.start, inSameDayAs: window.end) ? start : "\(start) – \(end)"
  }

  /// 多选配一套 → **一条**衣橱记录（用户 2026-09-18 合并口径）。
  ///
  /// 旧口径是「每个勾选项各落一条 Clothing、凭备注里的套装标记互相认定」；
  /// 使用者改为要求**合并录入同一个衣橱，不得拆分**。合并规则：
  ///   · 名称：成员款式名用「＋」连接（如「sk 粉色＋衬衫 奶白色（套装）」）；
  ///   · 类型 / 颜色 / 尺码：成员字段去重合并（「SK、衬衫」/「粉色、奶白色」），
  ///     成员各自的类型与颜色已按单件口径解析；
  ///   · 价格：总额 = 成员总额之和；定金 / 尾款分别求和（定金尾款一套
  ///     一起付，金额必须可对账）；任一成员是定金计划即整条是定金计划；
  ///   · 库存：一套一条记录，`stock` = 套数（quantity），不再按件数拆记录；
  ///   · 备注：保留套装标记与成员清单（互相认定的能力不丢），逐成员写明
  ///     已选规格与价格，合并后明细不缺失。
  static func makeSetDraft(
    for item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selections: [MidsummerSpecSelection],
    quantity: Int = 1,
    setMarker: String,
    presalePhase: MidsummerPresalePhase? = nil,
    modelContext: ModelContext
  ) -> ClothingEditDraft {
    let memberDrafts = selections.map {
      makeDraft(
        for: item, series: series, brandName: brandName,
        selection: $0, quantity: 1,
        presalePhase: presalePhase,
        modelContext: modelContext
      )
    }

    // 成员短名：款式名（剥「现 」前缀）优先，无款式组的成员退回单品名。
    let memberLabels: [String] = selections.map { selection in
      if let variant = MidsummerSpecResolver.selectedVariantName(selection, of: item) {
        return variant.hasPrefix("现 ") ? String(variant.dropFirst("现 ".count)) : variant
      }
      return MidsummerSpecResolver.displayName(item, selection: selection)
    }

    // 成员字段去重合并：types / colors / sizes 都是「分隔符串」，
    // 按逗号 / 顿号拆开归一，保持出现顺序去重。
    func mergeField(_ values: [String]) -> String {
      var seen: [String] = []
      for value in values {
        for part in value.components(separatedBy: CharacterSet(charactersIn: "，,、")) {
          let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty, !seen.contains(trimmed) { seen.append(trimmed) }
        }
      }
      return seen.joined(separator: "、")
    }

    let totalPrice = memberDrafts.reduce(0) { $0 + Int($1.priceTotal) }
    let totalDeposit = memberDrafts.reduce(0) { $0 + Int($1.deposit) }
    let totalBalance = memberDrafts.reduce(0) { $0 + Int($1.balance) }
    let isDepositPlan = memberDrafts.contains { $0.isDepositPlan }

    var noteLines: [String] = []
    noteLines.append("系列：\(series.name)")
    if !series.launchedOn.isEmpty {
      noteLines.append("上新日期：\(series.launchDateText)")
    }
    let source = item.itemURL.flatMap { $0.isEmpty ? nil : $0 } ?? item.sourceURL
    if !source.isEmpty {
      noteLines.append("原文出处：\(source)")
    }
    noteLines.append("套装入库：\(setMarker)（\(selections.count) 件一套，合并为一条衣橱记录）")
    noteLines.append("套装成员：\(memberLabels.joined(separator: "、"))")
    for (label, draft) in zip(memberLabels, memberDrafts) {
      var line = "· \(label)"
      if let specLine = draft.note.components(separatedBy: "\n")
        .first(where: { $0.hasPrefix("已选规格：") }) {
        line += "，\(String(specLine.dropFirst("已选规格：".count)))"
      }
      line += "，¥\(Int(draft.priceTotal))"
      noteLines.append(line)
    }
    if isDepositPlan {
      noteLines.append("价格口径：定金 ¥\(totalDeposit) + 尾款 ¥\(totalBalance) = 预约价 ¥\(totalPrice)")
      if item.depositEndsAt != nil || item.balanceEndsAt != nil {
        noteLines.append("尾款时间：\(Self.balanceWindowText(item))（已同步心愿尾款）")
      }
    }

    let sizeChartName = memberDrafts.compactMap(\.sizeChartImagePath).first

    // 套装一起付定金尾款，尾款窗口与单件同源（定金截止 → 尾款截止）。
    let setBalanceWindow = Self.balanceWindow(of: item, fallback: Date())

    return ClothingEditDraft(
      name: "\(memberLabels.joined(separator: "＋"))（套装）",
      brandName: brandName,
      types: mergeField(memberDrafts.map(\.types)),
      colors: mergeField(memberDrafts.map(\.colors)),
      sizes: mergeField(memberDrafts.map(\.sizes)),
      length: "",
      condition: "全新",
      accessories: "",
      imagePaths: [],
      isShared: false,
      originalPrice: Double(totalPrice),
      originalPriceJPY: 0,
      originalPriceCurrencyCode: ClothingPriceCurrency.cny.rawValue,
      priceTotal: Double(totalPrice),
      deposit: Double(totalDeposit),
      balance: Double(totalBalance),
      accessoriesPrice: 0,
      // 一套一条记录：stock 是「套数」，不是件数。
      stock: max(1, quantity),
      purchaseDate: Date(),
      depositDate: Date(),
      isDepositPlan: isDepositPlan,
      reservationKindRawValue: ClothingReservationKind.owned.rawValue,
      finalPaymentDate: isDepositPlan ? setBalanceWindow.start : Date(),
      finalPaymentEndDate: isDepositPlan ? setBalanceWindow.end : Date(),
      note: noteLines.joined(separator: "\n"),
      accessoryList: [],
      sizeChartImagePath: sizeChartName
    )
  }
}

@MainActor
enum MidsummerWardrobeInserter {

  /// 形态 A：一键入库。复用与日牌相同的落库实现（含失败回滚）。
  ///
  /// `selection` 缺省时表示「未选规格」，配色 / 尺码沿用单品自带值。
  /// `presalePhase` 决定价格口径与心愿尾款同步（见 `makeDraft` 注释）；
  /// 调用方从 `MidsummerListingStore.listing(forItemID:)?.presalePhase()` 取。
  @discardableResult
  static func quickInsert(
    item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selection: MidsummerSpecSelection = .empty,
    quantity: Int = 1,
    presalePhase: MidsummerPresalePhase? = nil,
    modelContext: ModelContext
  ) throws -> Clothing {
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: item,
      series: series,
      brandName: brandName,
      selection: selection,
      quantity: quantity,
      presalePhase: presalePhase,
      modelContext: modelContext
    )
    return try TimeHallWardrobeQuickInserter.insert(draft: draft, modelContext: modelContext)
  }

  /// 卡片上「快速入库」用的默认规格（有 SKU 表则取主推组合，否则每组第一项）。
  static func defaultSelection(for item: MidsummerItemDTO) -> MidsummerSpecSelection {
    MidsummerSpecResolver.defaultSelection(of: item)
  }

  /// 多选配一套（合并口径，用户 2026-09-18）：勾选的多件款式合并为**一条**
  /// 衣橱记录一次落库。与单件共用 `TimeHallWardrobeQuickInserter`（含失败回滚），
  /// 不再逐件各写一条。
  @discardableResult
  static func quickInsertSet(
    item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selections: [MidsummerSpecSelection],
    quantity: Int = 1,
    setMarker: String,
    presalePhase: MidsummerPresalePhase? = nil,
    modelContext: ModelContext
  ) throws -> Clothing {
    let draft = MidsummerWardrobeDraftBuilder.makeSetDraft(
      for: item,
      series: series,
      brandName: brandName,
      selections: selections,
      quantity: quantity,
      setMarker: setMarker,
      presalePhase: presalePhase,
      modelContext: modelContext
    )
    return try TimeHallWardrobeQuickInserter.insert(draft: draft, modelContext: modelContext)
  }

  /// 形态 B：跳衣橱编辑页并预填。
  static func openEditor(
    item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selection: MidsummerSpecSelection = .empty,
    quantity: Int = 1,
    presalePhase: MidsummerPresalePhase? = nil,
    modelContext: ModelContext
  ) {
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: item,
      series: series,
      brandName: brandName,
      selection: selection,
      quantity: quantity,
      presalePhase: presalePhase,
      modelContext: modelContext
    )
    TabNavigationManager.shared.presentWardrobeCreation(with: draft)
  }
}
