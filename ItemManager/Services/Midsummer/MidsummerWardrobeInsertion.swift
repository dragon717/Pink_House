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

    // 现货价 > 定金 > 尾款：与卡片上的价格展示口径一致。
    // 若当前规格组合在 SKU 表里有独立定价，以 SKU 价为准。
    let priceCNY = MidsummerSpecResolver.price(for: selection, of: item)
      ?? item.deposit ?? item.balance ?? 0
    let isDepositPlan = item.deposit != nil

    // 尺码表随单品入库（双方案设计 §四.2）：`Clothing.sizeChartImagePath` 字段已存在，
    // 衣橱侧零改动——草稿带上文件名，落库由 `TimeHallWardrobeQuickInserter` 统一写。
    let sizeChartName = item.sizeChartImageName
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }

    return ClothingEditDraft(
      name: MidsummerSpecResolver.displayName(item, selection: selection),
      brandName: brandName,
      types: item.kind.shortLabel,
      colors: mapping.colors,
      sizes: mapping.sizes,
      length: "",
      condition: "全新",
      accessories: "",
      imagePaths: [],
      isShared: false,
      originalPrice: Double(priceCNY),
      originalPriceJPY: 0,
      originalPriceCurrencyCode: ClothingPriceCurrency.cny.rawValue,
      priceTotal: Double(priceCNY),
      deposit: Double(item.deposit ?? 0),
      balance: Double(item.balance ?? 0),
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
