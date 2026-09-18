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
  static func makeDraft(
    for item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selection: MidsummerSpecSelection = .empty,
    quantity: Int = 1,
    extraNoteLines: [String] = [],
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

    // 价格口径（用户 2026-09-18）：定金尾款类型 → 总额 = 预约价（定金+尾款），
    // 定金 / 尾款分别落 `deposit` / `balance`，`isDepositPlan = true`；
    // 尾款缺省时按「预约价 − 定金」推——与上新表单「尾款 = 预约价 − 定金」
    // 的生成规则互为逆运算，保证两边口径一致。
    // 现货类型 → SKU 逐款价 > 现货价 > 预约价（不把定金当价格写）。
    let isDepositPlan = item.deposit != nil
    let depositAmount = item.deposit ?? 0
    let balanceAmount = item.balance
      ?? (isDepositPlan ? (item.preorderPrice.map { $0 - depositAmount }) : nil) ?? 0
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
    }

    // 尺码表随单品入库（双方案设计 §四.2）：`Clothing.sizeChartImagePath` 字段已存在，
    // 衣橱侧零改动——草稿带上文件名，落库由 `TimeHallWardrobeQuickInserter` 统一写。
    let sizeChartName = item.sizeChartImageName
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }

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
      finalPaymentDate: now,
      finalPaymentEndDate: now,
      note: noteLines.joined(separator: "\n"),
      accessoryList: [],
      sizeChartImagePath: sizeChartName
    )
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
    modelContext: ModelContext
  ) -> ClothingEditDraft {
    let memberDrafts = selections.map {
      makeDraft(
        for: item, series: series, brandName: brandName,
        selection: $0, quantity: 1, modelContext: modelContext
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
    }

    let sizeChartName = memberDrafts.compactMap(\.sizeChartImagePath).first

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
      finalPaymentDate: Date(),
      finalPaymentEndDate: Date(),
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
  @discardableResult
  static func quickInsert(
    item: MidsummerItemDTO,
    series: MidsummerSeriesDTO,
    brandName: String,
    selection: MidsummerSpecSelection = .empty,
    quantity: Int = 1,
    modelContext: ModelContext
  ) throws -> Clothing {
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: item,
      series: series,
      brandName: brandName,
      selection: selection,
      quantity: quantity,
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
    modelContext: ModelContext
  ) throws -> Clothing {
    let draft = MidsummerWardrobeDraftBuilder.makeSetDraft(
      for: item,
      series: series,
      brandName: brandName,
      selections: selections,
      quantity: quantity,
      setMarker: setMarker,
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
    modelContext: ModelContext
  ) {
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: item,
      series: series,
      brandName: brandName,
      selection: selection,
      quantity: quantity,
      modelContext: modelContext
    )
    TabNavigationManager.shared.presentWardrobeCreation(with: draft)
  }
}
