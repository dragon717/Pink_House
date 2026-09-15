import SwiftData
import SwiftUI

// MARK: - 系列列表页（对应图二）
//
// 图二给的是一行「方图 + 标题 + 副信息 + 橙色按钮 + 更多」的列表范式。
// 本页把该范式用在「系列」这一层：每行一个系列，并按要求带出
// 图片、价格区间与尺码，方便一眼浏览全部上新历史。

struct MidsummerSeriesListView: View {
  @ObservedObject var store: MidsummerStore
  let onSelectSeries: (String) -> Void

  private var groupedByYear: [(year: Int, series: [MidsummerSeriesDTO])] {
    store.allSeries
      .reduce(into: [Int: [MidsummerSeriesDTO]]()) { acc, series in
        acc[series.year, default: []].append(series)
      }
      .map { (year: $0.key, series: $0.value.sorted { $0.launchedOn > $1.launchedOn }) }
      .sorted { $0.year > $1.year }
  }

  /// 「新」角标：出现在最新年份的系列上（对应图二每个店铺头像左下角的绿标）。
  private var newestYear: Int { store.allSeries.map(\.year).max() ?? 0 }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
        header

        if store.allSeries.isEmpty {
          emptyState
        } else {
          ForEach(groupedByYear, id: \.year) { group in
            sectionHeader(group.year, count: group.series.count)
            ForEach(group.series) { series in
              MidsummerSeriesRow(
                series: series,
                isFresh: series.year == newestYear,
                onTap: { onSelectSeries(series.id) }
              )
              Rectangle()
                .fill(MidsummerTheme.divider)
                .frame(height: 0.5)
                .padding(.leading, 112)
            }
          }
          MidsummerDataNote(store: store)
        }
      }
      // 同品牌页：底部要给悬浮 dock 让位，否则页脚的创作者模式引导会被永久压住。
      .padding(.bottom, 110)
    }
    .background(MidsummerTheme.pageBackground)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("上新系列 · 按时间排列")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
      Text("涵盖品牌公开可查的全部上新系列；缺项以「待补充」标注，可在上传入口补齐。")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 10)
  }

  private func sectionHeader(_ year: Int, count: Int) -> some View {
    HStack(spacing: 6) {
      Text(String(year))
        .font(.system(size: 13, weight: .semibold, design: .serif))
        .foregroundStyle(MidsummerTheme.brandOrange)
      Text("\(count) 个系列")
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(MidsummerTheme.pageBackground)
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "square.stack.3d.up.slash")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(MidsummerTheme.secondaryText)
      Text("暂无系列数据")
        .font(.system(size: 13))
        .foregroundStyle(MidsummerTheme.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
  }
}

// MARK: - 系列行（图二行式的复用组件）

struct MidsummerSeriesRow: View {
  let series: MidsummerSeriesDTO
  var isFresh: Bool = false
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: 12) {
        cover

        VStack(alignment: .leading, spacing: 4) {
          Text(series.name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(1)

          HStack(spacing: 5) {
            Text(series.itemCountText)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.brandOrange)
            Text("|")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.divider)
            Text(series.launchedOn.isEmpty ? "上新日期待补充" : "\(series.launchDateText) 上新")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.secondaryText)
              .lineLimit(1)
          }

          HStack(spacing: 6) {
            if !series.hasPrice {
              MidsummerPendingTag(text: "价格待补充")
            } else {
              Text(series.priceRangeText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MidsummerTheme.priceRed)
            }
            MidsummerStageBadge(stage: series.stage)
          }
          .padding(.top, 1)

          // 定金与「参考价 / 现货价」分列——把两者混成一个区间会让人算不清要付多少。
          if let depositText = series.depositRangeText {
            Text(depositText)
              .font(.system(size: 10))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }

          MidsummerSizesRow(sizes: series.sizes, compact: true)
            .padding(.top, 1)
        }

        Spacer(minLength: 0)

        VStack(spacing: 10) {
          Text("查看")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
            .frame(width: 54, height: 29)
            .background(MidsummerTheme.orangeSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MidsummerTheme.secondaryText.opacity(0.7))
        }
        .padding(.top, 2)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 0,
      showsDecoration: false
    ) {
      MidsummerTheme.surface
    }
    .accessibilityLabel("\(series.name)，\(series.priceRangeText)，\(series.sizesText)")
  }

  private var cover: some View {
    MidsummerCoverView(imageName: series.coverImage, series: series, cornerRadius: 8)
      .frame(width: 84, height: 84)
      .overlay(alignment: .bottomLeading) {
        if isFresh {
          Text("新")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(MidsummerTheme.onAccent)
            .frame(width: 18, height: 16)
            .background(MidsummerTheme.freshGreen)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(4)
        }
      }
  }
}

// MARK: - 系列详情：该系列的全部单品

struct MidsummerSeriesDetailView: View {
  @ObservedObject var store: MidsummerStore
  let seriesID: String

  @Environment(\.modelContext) private var modelContext

  @State private var detailItem: MidsummerItemDTO?
  /// 形态 A（一键入库）的进行中 / 已完成状态
  @State private var insertingItemID: String?
  @State private var insertedItemIDs: Set<String> = []
  @State private var insertToast: String?
  /// 运营者补录（尺码表 / 价格表）：白名单门控，见 summaryCard 里的入口按钮
  @State private var showingSupplement = false

  private var series: MidsummerSeriesDTO? { store.series(withID: seriesID) }
  private var brandName: String { store.catalog?.brandName ?? "仲夏物语" }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      if let series {
        VStack(alignment: .leading, spacing: 0) {
          summaryCard(series)
          priceTableSection(series)
          itemsSection(series)
          MidsummerDataNote(store: store)
        }
        // 底部留出悬浮 dock 的高度，否则页脚最后一行会被 dock 压住（同品牌页）。
        .padding(.bottom, 110)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "questionmark.folder")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(MidsummerTheme.secondaryText)
          Text("找不到该系列")
            .font(.system(size: 13))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
      }
    }
    .background(MidsummerTheme.pageBackground)
    .overlay(alignment: .top) {
      if let insertToast {
        Text(insertToast)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MidsummerTheme.onAccent)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(MidsummerTheme.brandOrange.opacity(0.94), in: Capsule())
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
          .allowsHitTesting(false)
      }
    }
    .animation(.easeOut(duration: 0.18), value: insertToast)
    .sheet(item: $detailItem) { item in
      if let series {
        MidsummerItemDetailSheet(series: series, item: item, brandName: brandName)
      }
    }
    // 运营者补录：沿用投稿表单的补录模式（existingSeries 非空即补录），
    // 白名单门控在按钮与表单内各有一道（isAdminUser / CloudKit 角色双重保险）。
    .sheet(isPresented: $showingSupplement) {
      if let series {
        MidsummerContributeView(store: store, existingSeries: series)
      }
    }
  }

  // MARK: 形态 A：一键入库（行内快捷入口）

  /// 与品牌页卡片上的 ⊕ 同口径：走默认规格，并把实际入库的规格写进吐司。
  /// 需要自己挑规格时点进详情页——那里的一键入库会先弹规格面板。
  private func quickInsertToWardrobe(item: MidsummerItemDTO, series: MidsummerSeriesDTO) {
    guard insertingItemID == nil else { return }
    insertingItemID = item.id
    defer { insertingItemID = nil }

    let selection = MidsummerWardrobeInserter.defaultSelection(for: item)

    do {
      let clothing = try MidsummerWardrobeInserter.quickInsert(
        item: item,
        series: series,
        brandName: brandName,
        selection: selection,
        modelContext: modelContext
      )
      insertedItemIDs.insert(item.id)
      if let summary = MidsummerSpecResolver.summary(selection, of: item) {
        insertToast = "已加入衣橱：\(clothing.name)（\(summary)）"
      } else {
        insertToast = "已加入衣橱：\(clothing.name)"
      }
    } catch {
      insertToast = "加入失败：" + error.localizedDescription
    }
  }

  // MARK: 系列概览卡

  private func summaryCard(_ series: MidsummerSeriesDTO) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        MidsummerCoverView(imageName: series.coverImage, series: series)
          .frame(width: 96, height: 96)

        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            MidsummerStageBadge(stage: series.stage, filled: true)
            if series.sourceKind == "editorial" {
              Text("创作者补充")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MidsummerTheme.freshGreen)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(MidsummerTheme.freshGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
          }

          Text(series.name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(MidsummerTheme.primaryText)

          if !series.hasPrice {
            MidsummerPendingTag(text: "价格待补充")
          } else {
            Text(series.priceRangeText)
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(MidsummerTheme.priceRed)
            if let depositText = series.depositRangeText {
              Text(depositText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MidsummerTheme.secondaryText)
            }
          }

          Text(series.launchedOn.isEmpty ? "上新日期待补充" : "\(series.launchDateText) 上新")
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }

        Spacer(minLength: 0)
      }

      if let summary = series.summary, !summary.isEmpty {
        Text(summary)
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.primaryText.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 6) {
        attributeRow("可选尺码", value: series.sizesText)
        if !series.colors.isEmpty {
          attributeRow("配色", value: series.colors.joined(separator: " / "))
        }
        attributeRow("收录款数", value: series.itemCountText)
        // 把价格口径写出来：区间是派生的，使用者有权知道这些数字从哪来、是什么口径。
        if let priceSource = series.priceSource, !priceSource.isEmpty {
          attributeRow("价格口径", value: priceSource)
        }
        if !series.verified {
          attributeRow("资料状态", value: "公开渠道信息，部分项待创作者核对")
        }
      }

      if let url = URL(string: series.sourceURL), !series.sourceURL.isEmpty {
        Link(destination: url) {
          Label("查看原文出处", systemImage: "arrow.up.right.square")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
        }
      }

      // 运营者补充上传入口（方案设计 docs/上新咨询双方案设计.md §五）：
      // 尺码表 / 价格表优先来自淘宝详情页采集，缺项时由白名单运营者在此补录。
      if store.isAdminUser {
        Button {
          showingSupplement = true
        } label: {
          Label("补录尺码表 / 价格表", systemImage: "square.and.pencil")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(MidsummerTheme.orangeSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("series-supplement-button")
        .accessibilityLabel("补录尺码表或价格表")
      }
    }
    .padding(14)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 14,
      showsDecoration: true
    ) {
      MidsummerTheme.surface
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
  }

  private func attributeRow(_ label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(label)
        .font(.system(size: 11))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .frame(width: 58, alignment: .leading)
      Text(value)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }

  // MARK: 价格总表（方案一必含资料，docs/上新咨询双方案设计.md §四）
  //
  // 按 2026-09-15 定的价格归类分三组：现货价 / 全款预约 / 定金尾款预约。
  // 数据不另存——全部从单品 price/deposit/balance/priceKind 派生，与卡片口径同源。

  private func priceTableSection(_ series: MidsummerSeriesDTO) -> some View {
    let groups = priceGroups(series)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text("价格总表")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("按购买方式分组")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Spacer(minLength: 0)
      }

      if groups.isEmpty {
        Text("暂无可核验价格")
          .font(.system(size: 12))
          .foregroundStyle(MidsummerTheme.secondaryText)
      } else {
        ForEach(groups, id: \.header) { group in
          VStack(alignment: .leading, spacing: 4) {
            Text(group.header)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(MidsummerTheme.brandOrange)
            ForEach(group.rows, id: \.name) { row in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name)
                  .font(.system(size: 12))
                  .foregroundStyle(MidsummerTheme.primaryText)
                  .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.amount)
                  .font(.system(size: 12, weight: .semibold).monospacedDigit())
                  .foregroundStyle(MidsummerTheme.priceRed)
                  .lineLimit(1)
              }
            }
          }
          .padding(.vertical, 4)
          if group.header != groups.last?.header {
            Rectangle()
              .fill(MidsummerTheme.divider)
              .frame(height: 0.5)
          }
        }
      }

      Text("口径：现货价即买即得；全款预约一次付清；定金尾款预约需付两次。价格为采集时点数据，以商品页为准。")
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 14,
      showsDecoration: true
    ) {
      MidsummerTheme.surface
    }
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .accessibilityIdentifier("series-price-table")
  }

  private struct PriceRow {
    let name: String
    let amount: String
  }

  private struct PriceGroup {
    let header: String
    let rows: [PriceRow]
  }

  /// 单品 → 价格归类。判定顺序：有定金+尾款 → 定金尾款预约；只有定金 → 全款预约
  /// （与衣橱 `isFullPaymentReservation` 的派生口径一致）；无预约款但有价 → 现货价。
  private func priceGroups(_ series: MidsummerSeriesDTO) -> [PriceGroup] {
    var spot: [PriceRow] = []
    var fullPreorder: [PriceRow] = []
    var depositBalance: [PriceRow] = []
    for item in series.items {
      switch (item.deposit, item.balance) {
      case (let deposit?, let balance?):
        depositBalance.append(
          PriceRow(name: item.name, amount: "定金 ¥\(deposit) · 尾款 ¥\(balance)"))
      case (let deposit?, nil):
        fullPreorder.append(PriceRow(name: item.name, amount: "全款 ¥\(deposit)"))
      case (nil, let balance?):
        // 只有尾款没有定金：仍属预约链路，但单独标口径，不伪装成现货价。
        depositBalance.append(PriceRow(name: item.name, amount: "尾款 ¥\(balance)"))
      case (nil, nil):
        if let range = item.priceRange {
          let kindSuffix: String
          switch item.priceKind ?? item.variantPriceKind {
          case .shop: kindSuffix = "（商品页价）"
          case .reference: kindSuffix = "（参考价）"
          case .balance, nil: kindSuffix = ""
          }
          spot.append(
            PriceRow(
              name: item.name,
              amount: range.min == range.max
                ? "¥\(range.min)\(kindSuffix)" : "¥\(range.min)–\(range.max)\(kindSuffix)"))
        }
      }
    }
    var groups: [PriceGroup] = []
    if !spot.isEmpty { groups.append(PriceGroup(header: "现货价", rows: spot)) }
    if !fullPreorder.isEmpty {
      groups.append(PriceGroup(header: "预约价 · 全款预约", rows: fullPreorder))
    }
    if !depositBalance.isEmpty {
      groups.append(PriceGroup(header: "预约价 · 定金尾款预约", rows: depositBalance))
    }
    return groups
  }

  // MARK: 单品列表

  private func itemsSection(_ series: MidsummerSeriesDTO) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Text("全部商品")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text(series.itemCountText)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.top, 20)
      .padding(.bottom, 8)

      if series.items.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: "tray")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(MidsummerTheme.secondaryText)
          Text("本系列尚未收录具体商品")
            .font(.system(size: 12))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
      } else {
        ForEach(series.items) { item in
          itemRow(series: series, item: item)
          Rectangle()
            .fill(MidsummerTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, 112)
        }
      }
    }
  }

  private func itemRow(series: MidsummerSeriesDTO, item: MidsummerItemDTO) -> some View {
    // 同一个坑：外层 Button 套内层 Button 会让「加入衣橱」和整行点击互相打架。
    // 整行点击交给 contentShape + onTapGesture，入库按钮保持真 Button。
    HStack(alignment: .top, spacing: 12) {
      // 单品图优先：每个单品展示**自己的**图；该单品没传图时才回退系列封面。
      MidsummerCoverView(imageName: item.coverImage ?? series.coverImage, series: nil, cornerRadius: 8)
        .frame(width: 84, height: 84)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.name)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        HStack(spacing: 5) {
          Text(item.kind.shortLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(MidsummerTheme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
          // 归集商品（一个淘宝链接含多款）在这里讲清「里面有几款」，
          // 否则使用者会以为 5 个独立单品被合并丢掉了。
          if item.variantCount > 1 {
            Text("含 \(item.variantCount) 个款式")
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.brandOrange)
          }
          if !item.colors.isEmpty {
            Text(item.colors.joined(separator: " / "))
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.secondaryText)
              .lineLimit(1)
          }
        }

        // 带口径：归集商品的逐款价可能是「尾款」口径（如卢瓦尔葡萄园 3.0），
        // 只显示 ¥160–400 会让人按全款估预算。
        Text(item.priceTextWithKind)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(
            item.hasPrice ? MidsummerTheme.priceRed : MidsummerTheme.secondaryText
          )
          .lineLimit(1)

        MidsummerSizesRow(sizes: item.sizes, compact: true)
      }

      Spacer(minLength: 0)

      VStack(spacing: 10) {
        Text("查看")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .frame(width: 54, height: 29)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        // 「每个商品上提供直接加入衣橱的入口」——系列页同样保留形态 A。
        MidsummerWardrobeIconButton(
          isInserting: insertingItemID == item.id,
          didInsert: insertedItemIDs.contains(item.id),
          action: { quickInsertToWardrobe(item: item, series: series) }
        )
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
    .onTapGesture { detailItem = item }
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 0,
      showsDecoration: false
    ) {
      MidsummerTheme.surface
    }
  }
}
