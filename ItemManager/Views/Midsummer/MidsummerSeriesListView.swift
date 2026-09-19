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
  /// 创作者视图标记（由品牌页宿主传入；快照测试直接构造本页时保持 false，
  /// 价格总表行不可点、不出现编辑标记）。基础条目改价走 CloudKit 白名单。
  var isCreatorMode: Bool = false
  /// 系列资料页入口（款式分类与尺码表 / 链接原始信息）。
  /// 由品牌页宿主注入导航闭包——本页不自己持有路由，保持与首页同一套导航栈。
  var onOpenStyleChartCatalog: (() -> Void)? = nil
  var onOpenLinkReport: (() -> Void)? = nil
  /// 删除系列成功后的回跳（用户 2026-09-18）：系列已不存在，宿主应退出本页。
  var onSeriesDeleted: (() -> Void)? = nil

  @Environment(\.modelContext) private var modelContext
  /// 角色闸门（用户 2026-09-18）：上架管理 / 改价 / 换图**只认角色**，
  /// 与「用户视图 / 创作者视图」这个纯展示开关无关——普通用户两种视图都没有编辑能力，
  /// 创作者即使在用户视图下也保留自己的编辑入口（切换只是读法不同）。
  /// 服务层（`MidsummerListingStore` / `MidsummerCloudService`）另有同一份校验兜底。
  @ObservedObject private var creatorAccess = CreatorAccess.shared
  /// 上架记录（定金-尾款预售相位分区与流转都从这读）。
  @ObservedObject private var listingStore = MidsummerListingStore.shared

  @State private var detailItem: MidsummerItemDTO?
  /// 上新工作台（用户 2026-09-16）：主图/阶段/尺码/单品价格 4 步表单 + 上架管理。
  @State private var showingListingWorkspace = false
  /// 价格总表行点击 → 改价目标（用户 2026-09-18）。
  @State private var priceEditTarget: PriceEditTarget?
  /// 删除系列（用户 2026-09-18）：确认弹窗 + 失败提示。
  @State private var showingDeleteConfirm = false
  @State private var deleteError: String?

  /// 改价目标：listing 非 nil = 工作台商品（本地编辑），nil = 基础条目（CloudKit）。
  private struct PriceEditTarget: Identifiable {
    let item: MidsummerItemDTO
    let listing: MidsummerListing?
    var id: String { item.id }
  }

  private var series: MidsummerSeriesDTO? { store.series(withID: seriesID) }
  private var brandName: String { store.catalog?.brandName ?? "仲夏物语" }

  /// 本页所有创作者能力的总闸：上新管理入口 + 价格总表改价。
  ///
  /// 内容为两类，都不看来源、只看角色：
  ///   · 创作者自己发布的系列（上新工作台 listing）
  ///   · 平台历史内容与外部渠道导入的条目（种子 / 云端基础条目）
  private var canEditContent: Bool { creatorAccess.isCreator }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      if let series {
        VStack(alignment: .leading, spacing: 0) {
          summaryCard(series)
          deleteSeriesSection(series)
          archiveSection(series)
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
    // 进入页面补一次预售流转：App 一直开着（没重启）时，跨过截止时刻
    // 也能把到期的定金商品推进尾款阶段，分区立即重新归属。
    .onAppear { listingStore.refreshPresaleTransitions() }
    // 删除系列确认（用户 2026-09-18）：误传商品时可整系列删除。
    .confirmationDialog(
      "删除「\(series?.name ?? "该系列")」？",
      isPresented: $showingDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button("删除系列（含全部上架商品）", role: .destructive) {
        deleteSeries()
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text(deleteConfirmMessage)
    }
    .sheet(item: $detailItem) { item in
      if let series {
        MidsummerItemDetailSheet(series: series, item: item, brandName: brandName)
      }
    }
    // 改价面板（用户 2026-09-18）：工作台商品走本地编辑链路；种子 / 云端
    // 基础条目走 CloudKit 发布（需要创作者白名单，失败时面板内给出原因）。
    .sheet(item: $priceEditTarget) { target in
      if let listing = target.listing {
        MidsummerListingPriceEditSheet(listing: listing)
      } else {
        MidsummerItemPriceEditSheet(item: target.item)
      }
    }
    // 上新工作台：所有系列无条件开放（旧版 canContribute 三态门控已随投稿
    // 表单一并移除，上新上传只保留这一条最新链路）。
    .sheet(isPresented: $showingListingWorkspace) {
      if let series {
        MidsummerListingWorkspaceView(store: store, series: series)
      }
    }
  }

  // MARK: 系列概览卡

  /// 删除系列（用户 2026-09-19 扩展）：任何系列都允许创作者删除——
  /// 自建系列是真删除；种子 / 云端系列是本机隐藏（资料不可变，云端不动，
  /// 可从隐藏账本恢复）。普通用户两种都没有。
  private var canDeleteSeries: Bool {
    canEditContent
  }

  /// 确认弹窗文案按系列类型分支：自建 = 真删除；种子 / 云端 = 本机隐藏。
  private var deleteConfirmMessage: String {
    if seriesID.hasPrefix("midsummer-custom-") {
      return "会一并删除该系列下的所有上架商品与图片，删除后不可恢复。"
    }
    return "该系列是平台基础资料：仅从本机移除（云端不受影响，可恢复），其下的上架商品会一并删除。"
  }

  private func deleteSeriesSection(_ series: MidsummerSeriesDTO) -> some View {
    Group {
      if canDeleteSeries {
        VStack(alignment: .leading, spacing: 6) {
          if let deleteError {
            Text(deleteError)
              .font(.system(size: 11))
              .foregroundStyle(MidsummerTheme.priceRed)
          }
          Button {
            showingDeleteConfirm = true
          } label: {
            Label(
              seriesID.hasPrefix("midsummer-custom-") ? "删除该系列" : "删除该系列（本机移除）",
              systemImage: "trash"
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MidsummerTheme.priceRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(MidsummerTheme.priceRed.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("series-delete-button")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
      }
    }
  }

  /// 执行删除：自建系列真删除（先清上架商品再删档案与封面图）；种子 / 云端
  /// 系列走隐藏账本（上架商品同样逐条真删，恢复系列后不带残留）。
  /// `MidsummerStore` 订阅了两边与账本的变更，catalog 会自动重算。
  private func deleteSeries() {
    do {
      for listing in listingStore.listings(inSeries: seriesID) {
        try listingStore.delete(listing.id)
      }
      if seriesID.hasPrefix("midsummer-custom-") {
        try MidsummerCustomSeriesStore.shared.remove(seriesID)
      } else {
        try MidsummerHiddenSeriesStore.shared.hide(seriesID)
      }
      deleteError = nil
      onSeriesDeleted?()
    } catch {
      deleteError = "删除失败：" + error.userMessage
    }
  }

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

      // 上新工作台入口（用户 2026-09-16）：基于本系列的商品上传上新系统，
      // 主图与信息 → 上新阶段 → 尺码信息 → 单品与价格，上架商品自动进系列 feed
      // 并可一键加入衣橱。上新上传只保留这一条链路（旧投稿表单已删除）。
      //
      // 2026-09-18 起重新上门控：上架管理是**创作者专属能力**，普通用户看不到
      // 这个入口，也进不去工作台（此前对所有用户无条件开放，属于越权敞口）。
      if canEditContent {
        Button {
          showingListingWorkspace = true
        } label: {
          HStack {
            Label("上新管理", systemImage: "plus.square.on.square")
              .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("已上架 \(MidsummerListingStore.shared.listedCount(inSeries: series.id))")
              .font(.system(size: 10))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
          .foregroundStyle(MidsummerTheme.brandOrange)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 9)
          .padding(.horizontal, 10)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("series-listing-workspace-button")
        .accessibilityLabel("上新管理")
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

  // MARK: 系列资料（款式分类与尺码表 / 链接原始信息）
  //
  // 这两份资料按系列整理，挂在**有资料数据的系列**详情页（清单见
  // `MidsummerStyleChartData.ArchiveContent.seriesIDs`，目前樱花小羊已整理，
  // 仲夏物语其余系列补齐数据后自动开放）。原先挂在品牌页首页顶层，
  // 与该系列的商品卡片分散在三行；合并入口后统一收进对应系列的详情页。
  // 资料尚未整理的系列不显示该区块——不出现点进去空空如也的入口。

  private func archiveSection(_ series: MidsummerSeriesDTO) -> some View {
    Group {
      if MidsummerStyleChartData.ArchiveContent.seriesIDs.contains(series.id) {
        VStack(spacing: 0) {
          MidsummerArchiveEntryRow(
            title: "款式分类与尺码表",
            subtitle:
              "\(MidsummerStyleChartCatalog.loadFromBundle()?.categories.count ?? 0) 个分类 · 尺码表原图",
            symbol: "ruler",
            a11yID: "midsummer-entry-stylechart"
          ) { onOpenStyleChartCatalog?() }
          MidsummerArchiveEntryRow(
            title: "链接原始信息",
            // 链接数取自链接报告 JSON（两条淘宝来源合并在一个条目里，
            // series.items.count 已不能反映真实链接数）。
            subtitle:
              "\(MidsummerLinkReport.loadFromBundle()?.links.count ?? 0) 个淘宝链接 · 原文转录",
            symbol: "link",
            a11yID: "midsummer-entry-linkreport"
          ) { onOpenLinkReport?() }
        }
        .padding(.top, 10)
      }
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
        // 创作者：点行直接改价（用户 2026-09-18），普通用户无此提示与手势。
        if canEditContent {
          Text("点行改价")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
        }
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
              priceTableRow(row)
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

  /// 价格总表行：创作者视图下点行进改价面板（工作台商品 → 本地编辑；
  /// 基础条目 → CloudKit 发布），普通用户保持纯展示。
  private func priceTableRow(_ row: PriceRow) -> some View {
    let rowContent = HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(row.name)
        .font(.system(size: 12))
        .foregroundStyle(MidsummerTheme.primaryText)
        .lineLimit(1)
      Spacer(minLength: 8)
      Text(row.amount)
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .foregroundStyle(MidsummerTheme.priceRed)
        .lineLimit(1)
      if canEditContent, row.itemID != nil {
        Image(systemName: "square.and.pencil")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
    }
    let editable = canEditContent && row.itemID != nil
    return Group {
      if editable {
        Button {
          openPriceEditor(itemID: row.itemID ?? "")
        } label: {
          rowContent
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("series-price-row-\(row.itemID ?? "")")
      } else {
        rowContent
      }
    }
  }

  /// 按单品 id 打开改价面板：工作台商品（id 带 listing 前缀或能反查到上架记录）
  /// 走本地编辑；种子 / 云端基础条目走 CloudKit 发布。
  private func openPriceEditor(itemID: String) {
    guard let series,
      let item = series.items.first(where: { $0.id == itemID })
    else { return }
    priceEditTarget = PriceEditTarget(item: item, listing: listingStore.listing(forItemID: itemID))
  }

  private struct PriceRow {
    let name: String
    let amount: String
    /// 该行对应的单品 id；创作者视图下点行进改价面板（nil = 无法定位的派生行）。
    let itemID: String?
  }

  private struct PriceGroup {
    let header: String
    let rows: [PriceRow]
  }

  /// 单品 → 价格归类。判定顺序：有定金+尾款 → 定金尾款预约；只有定金 → 全款预约
  /// （旧数据把全款预约价存在 deposit 里，与衣橱 `isFullPaymentReservation` 派生口径一致）；
  /// 显式填了 `preorderPrice` → 预约价（全款预约）；有现货价 → 现货价。
  private func priceGroups(_ series: MidsummerSeriesDTO) -> [PriceGroup] {
    var spot: [PriceRow] = []
    var fullPreorder: [PriceRow] = []
    var depositBalance: [PriceRow] = []
    for item in series.items {
      let itemID = item.id
      switch (item.deposit, item.balance) {
      case (let deposit?, let balance?):
        depositBalance.append(
          PriceRow(name: item.name, amount: "定金 ¥\(deposit) · 尾款 ¥\(balance)", itemID: itemID))
      case (let deposit?, nil):
        fullPreorder.append(
          PriceRow(name: item.name, amount: "全款 ¥\(deposit)", itemID: itemID))
      case (nil, let balance?):
        // 只有尾款没有定金：仍属预约链路，但单独标口径，不伪装成现货价。
        depositBalance.append(
          PriceRow(name: item.name, amount: "尾款 ¥\(balance)", itemID: itemID))
      case (nil, nil):
        // 显式预约价优先归「全款预约」组，不再靠「只有定金」猜口径。
        if let preorder = item.preorderPrice {
          fullPreorder.append(
            PriceRow(name: item.name, amount: "预约价 ¥\(preorder)", itemID: itemID))
        } else if let range = item.priceRange {
          let kindSuffix: String
          switch item.priceKind ?? item.variantPriceKind {
          case .shop: kindSuffix = "（现货价）"
          case .reference: kindSuffix = "（参考价）"
          case .balance, nil: kindSuffix = ""
          }
          spot.append(
            PriceRow(
              name: item.name,
              amount: range.min == range.max
                ? "¥\(range.min)\(kindSuffix)" : "¥\(range.min)–\(range.max)\(kindSuffix)",
              itemID: itemID))
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

  // MARK: 商品列表（预售相位分区：上新 · 定金 / 尾款 / 全部商品）

  /// 定金-尾款状态机驱动的列表归属（用户 2026-09-17 业务规则）：
  ///   · 定金期商品 → 「上新（定金）」区；
  ///   · 定金截止后自动从上新区移除 → 进入「尾款」区（行内显示尾款价）；
  ///   · 尾款期也结束 → 预售结束，商品回到「全部商品」区，
  ///     详情页同时展示预约价与现货价。
  private func presalePartition(_ series: MidsummerSeriesDTO, now: Date)
    -> (deposit: [MidsummerItemDTO], balance: [MidsummerItemDTO], rest: [MidsummerItemDTO])
  {
    var deposit: [MidsummerItemDTO] = []
    var balance: [MidsummerItemDTO] = []
    var rest: [MidsummerItemDTO] = []
    for item in series.items {
      switch listingStore.listing(forItemID: item.id)?.presalePhase(at: now) {
      case .deposit: deposit.append(item)
      case .balance: balance.append(item)
      default: rest.append(item)  // 预售结束 / 不走状态机（种子商品、现货、预约价）
      }
    }
    return (deposit, balance, rest)
  }

  private func itemsSection(_ series: MidsummerSeriesDTO) -> some View {
    let partition = presalePartition(series, now: Date())
    return VStack(alignment: .leading, spacing: 0) {
      if !partition.deposit.isEmpty {
        presaleSectionHeader(
          title: "上新（定金）", count: partition.deposit.count,
          caption: "定金期商品；截止后自动转入尾款列表",
          identifier: "midsummer-presale-section-deposit")
        ForEach(partition.deposit) { item in
          itemRow(series: series, item: item, presalePhase: .deposit)
          sectionDivider
        }
      }
      if !partition.balance.isEmpty {
        presaleSectionHeader(
          title: "尾款", count: partition.balance.count,
          caption: "尾款期商品；付清尾款即等出货",
          identifier: "midsummer-presale-section-balance")
        ForEach(partition.balance) { item in
          itemRow(series: series, item: item, presalePhase: .balance)
          sectionDivider
        }
      }

      HStack(spacing: 6) {
        Text("全部商品")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("\(partition.rest.count) 件")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.top, 20)
      .padding(.bottom, 8)

      if partition.rest.isEmpty && partition.deposit.isEmpty && partition.balance.isEmpty {
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
        ForEach(partition.rest) { item in
          itemRow(series: series, item: item)
          sectionDivider
        }
      }
    }
  }

  private var sectionDivider: some View {
    Rectangle()
      .fill(MidsummerTheme.divider)
      .frame(height: 0.5)
      .padding(.leading, 112)
  }

  private func presaleSectionHeader(title: String, count: Int, caption: String, identifier: String)
    -> some View
  {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("\(count) 件")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Spacer(minLength: 0)
      }
      Text(caption)
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
    }
    .padding(.horizontal, 14)
    .padding(.top, 20)
    .padding(.bottom, 8)
    .accessibilityIdentifier(identifier)
  }

  /// 列表行价格文案：预售期按相位显示「当前阶段要付的钱」。
  ///   · 定金期：定金 + 尾款一体展示（如「定金 ¥388 · 尾款 ¥400」）；
  ///   · 尾款期：只显示尾款（缺尾款数据时如实退回常规价格文案，不占位）；
  ///   · 其它相位（含预售结束）：常规带口径价格文案。
  private func priceLine(for item: MidsummerItemDTO, phase: MidsummerPresalePhase?) -> String {
    switch phase {
    case .deposit:
      // 定金与尾款成对出现是预售定金模式的口径；只有定金就只写定金。
      switch (item.deposit, item.balance) {
      case let (deposit?, balance?): return "定金 ¥\(deposit) · 尾款 ¥\(balance)"
      case let (deposit?, nil): return "定金 ¥\(deposit)"
      default: return item.priceTextWithKind
      }
    case .balance:
      if let balance = item.balance { return "尾款 ¥\(balance)" }
      return item.priceTextWithKind
    default:
      return item.priceTextWithKind
    }
  }

  private func itemRow(series: MidsummerSeriesDTO, item: MidsummerItemDTO, presalePhase: MidsummerPresalePhase? = nil) -> some View {
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
          // 系列详情页里概览卡的系列名与商品行名可能同文案（如「樱花小羊」），
          // UI 测试用这个 ASCII identifier 精确锁定商品行（中文 identifier 会被截断）。
          .accessibilityIdentifier("midsummer-series-item-\(item.id)")

        HStack(spacing: 5) {
          // 预售相位徽章：一眼看出商品此刻在上新期还是尾款期。
          if let presalePhase {
            Text(presalePhase.labelZH)
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(MidsummerTheme.brandOrange)
              .padding(.horizontal, 5)
              .padding(.vertical, 1.5)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(Capsule())
              .accessibilityIdentifier("midsummer-item-phase-\(item.id)")
          }
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
        // 尾款期商品按业务规则**只显示尾款价**（当前要付的钱）；
        // 定金期商品显示「定金 · 尾款」一体价（两者同属一个阶段体系）。
        Text(priceLine(for: item, phase: presalePhase))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(
            item.hasPrice ? MidsummerTheme.priceRed : MidsummerTheme.secondaryText
          )
          .lineLimit(1)

        MidsummerSizesRow(sizes: item.sizes, compact: true)
      }

      Spacer(minLength: 0)

      // 右侧操作列：创作者多一个「改价」（用户 2026-09-19）——与上新工作台的
      // 行内改价同款入口：工作台商品走本地编辑，种子 / 云端基础条目走 CloudKit。
      // 整行点击仍进商品详情（onTapGesture 不吃内层 Button 的事件）。
      VStack(spacing: 10) {
        Text("查看")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
          .frame(width: 54, height: 29)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        if canEditContent {
          Button {
            openPriceEditor(itemID: item.id)
          } label: {
            Label("改价", systemImage: "yensign.square")
              .labelStyle(.titleAndIcon)
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(MidsummerTheme.brandOrange)
              .frame(width: 54, height: 26)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("series-item-price-edit-\(item.id)")
          .accessibilityLabel("修改 \(item.name) 的价格")
        }
      }
      .padding(.top, 2)
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
