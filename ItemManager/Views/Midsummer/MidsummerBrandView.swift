import PhotosUI
import SwiftData
import SwiftUI

// MARK: - 页面路由
//
// 用自管理的层级状态而不是 NavigationStack：本视图可能被嵌在任意容器里
// （时光馆的 tab 容器没有 NavigationStack），自管理可以避免嵌套导航的意外行为。

nonisolated enum MidsummerRoute: Equatable {
  case home
  case seriesList
  case seriesDetail(seriesID: String)
}

// MARK: - 品牌页宿主

struct MidsummerBrandView: View {
  var onClose: (() -> Void)?

  @ObservedObject private var store = MidsummerStore.shared
  /// 观察创作者模式：开关一变，顶栏的「上传上新」入口立即出现/隐藏，无需重进页面。
  @ObservedObject private var creatorMode = CreatorMode.shared
  @State private var route: MidsummerRoute = .home
  @State private var showingContribute = false

  var body: some View {
    ZStack {
      MidsummerTheme.pageBackground.ignoresSafeArea()

      VStack(spacing: 0) {
        MidsummerTopBar(
          title: title,
          subtitle: subtitle,
          showsBack: route != .home,
          canContribute: store.canContribute,
          onBack: goBack,
          onClose: onClose,
          onContribute: { showingContribute = true }
        )

        switch route {
        case .home:
          MidsummerHomeContent(store: store, onOpenSeriesList: { navigate(to: .seriesList) })
            .transition(pageTransition(forward: true))
        case .seriesList:
          MidsummerSeriesListView(
            store: store,
            onSelectSeries: { navigate(to: .seriesDetail(seriesID: $0)) }
          )
          .transition(pageTransition(forward: true))
        case .seriesDetail(let seriesID):
          MidsummerSeriesDetailView(store: store, seriesID: seriesID)
            .transition(pageTransition(forward: true))
        }
      }
    }
    .sheet(isPresented: $showingContribute) {
      MidsummerContributeView(store: store)
    }
    .task {
      await store.refreshFromCloud()
    }
  }

  // MARK: 顶栏文案

  private var title: String {
    switch route {
    case .home: return store.catalog?.brandName ?? "仲夏物语"
    case .seriesList: return "全部系列"
    case .seriesDetail(let seriesID): return store.series(withID: seriesID)?.name ?? "系列详情"
    }
  }

  private var subtitle: String? {
    switch route {
    case .home:
      guard let catalog = store.catalog else { return nil }
      return "\(catalog.brandNameEN) · \(catalog.foundedOn.prefix(4)) 年创立"
    case .seriesList:
      // 年份范围按实际收录动态给出，不写死——数据可以随时被创作者往前补
      let years = store.allSeries.map(\.year)
      guard let oldest = years.min(), let newest = years.max() else { return nil }
      let span = oldest == newest ? "\(newest)" : "\(oldest)–\(newest)"
      return "\(span) · 共 \(store.allSeries.count) 个系列"
    case .seriesDetail(let seriesID):
      guard let series = store.series(withID: seriesID) else { return nil }
      return series.launchedOn.isEmpty ? "上新日期待补充" : "\(series.launchDateText) 上新"
    }
  }

  // MARK: 导航

  private func navigate(to destination: MidsummerRoute) {
    withAnimation(.easeInOut(duration: 0.22)) { route = destination }
  }

  private func goBack() {
    switch route {
    case .home:
      onClose?()
    case .seriesList:
      navigate(to: .home)
    case .seriesDetail:
      navigate(to: .seriesList)
    }
  }

  private func pageTransition(forward: Bool) -> AnyTransition {
    .asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .move(edge: .leading).combined(with: .opacity)
    )
  }
}

// MARK: - 顶栏

struct MidsummerTopBar: View {
  let title: String
  let subtitle: String?
  let showsBack: Bool
  let canContribute: Bool
  let onBack: () -> Void
  let onClose: (() -> Void)?
  let onContribute: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
          .themeSkinLegibleSymbol(level: .badge, slot: MidsummerThemeSlot.topBarIconButton)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(showsBack ? "返回" : "关闭")

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 16, weight: .semibold, design: .serif))
          .foregroundStyle(MidsummerTheme.primaryText)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.topBar)
          .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.topBar)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)

      // 创作者上传入口：仅 admin 可见（合规闸门，见 docs 说明）
      if canContribute {
        Button(action: onContribute) {
          HStack(spacing: 4) {
            Image(systemName: "plus")
              .font(.system(size: 11, weight: .bold))
            Text("上传上新")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(MidsummerTheme.brandOrange)
          .themeSkinLegibleText(level: .badge, slot: MidsummerThemeSlot.topBarAddButton)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.regularMaterial)
    .themeSkinLegibilityBackdrop(level: .preview, slot: MidsummerThemeSlot.topBar, cornerRadius: 0)
    .overlay(alignment: .bottom) {
      Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)
    }
  }
}

// MARK: - 首页（对应图一）

struct MidsummerHomeContent: View {
  @ObservedObject var store: MidsummerStore
  let onOpenSeriesList: () -> Void

  @Environment(\.modelContext) private var modelContext

  @State private var selectedYear: Int?
  @State private var selectedSeriesID: String?
  @State private var detailItem: MidsummerItemDTO?
  @State private var detailSeries: MidsummerSeriesDTO?

  /// 形态 A（一键入库）的进行中 / 已完成状态
  @State private var insertingItemID: String?
  @State private var insertedItemIDs: Set<String> = []
  @State private var insertToast: String?

  private var brandName: String { store.catalog?.brandName ?? "仲夏物语" }

  private var activeYear: Int? { selectedYear ?? store.yearEntries.first?.year }

  private var seriesInActiveYear: [MidsummerSeriesDTO] {
    guard let activeYear else { return [] }
    return store.allSeries.filter { $0.year == activeYear }
  }

  private var feed: [(series: MidsummerSeriesDTO, item: MidsummerItemDTO)] {
    store.itemFeed(year: activeYear, seriesID: selectedSeriesID)
  }

  var body: some View {
    HStack(spacing: 0) {
      yearRail
      VStack(spacing: 0) {
        seriesChips
        allEntryRow
        itemList
      }
    }
    .background(MidsummerTheme.pageBackground)
    .overlay(alignment: .top) {
      if let insertToast {
        Text(insertToast)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white)
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
      // 兜底：`detailSeries` 与 `detailItem` 是同时赋值的，正常不会错位；
      // 但旧写法在 series 为 nil 时会呈现一个**完全空白的 sheet**（点进去一片白）。
      // 这里改为按 seriesID 回查，仍查不到才给明确空状态——任何情况下都不出白屏。
      if let series = detailSeries ?? store.series(withID: item.seriesID) {
        MidsummerItemDetailSheet(series: series, item: item, brandName: brandName)
      } else {
        ContentUnavailableView(
          "找不到该单品所属系列",
          systemImage: "questionmark.folder",
          description: Text("该系列可能已从资料库中移除，可返回后重新选择。")
        )
      }
    }
  }

  // MARK: 形态 A：一键入库（卡片上的快捷入口）
  //
  // 卡片上的 ⊕ 刻意**不弹规格面板**——那个入口的价值就是「快」。
  // 代价是使用者没有明确选规格，所以：
  //   1. 走 `defaultSelection`（有 SKU 表取主推组合，否则每组第一项）
  //   2. 吐司里把实际入库的规格写出来，不静默替使用者决定
  // 需要自己挑规格时走详情页的入口。

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
      insertToast = Self.insertToastText(clothingName: clothing.name, item: item, selection: selection)
    } catch {
      insertToast = "加入失败：" + error.localizedDescription
    }
  }

  /// 吐司文案：`已加入衣橱：樱花小羊 SK（Sk粉色 / M）`；无规格时退回旧文案。
  private static func insertToastText(
    clothingName: String,
    item: MidsummerItemDTO,
    selection: MidsummerSpecSelection
  ) -> String {
    guard let summary = MidsummerSpecResolver.summary(selection, of: item) else {
      return "已加入衣橱：\(clothingName)"
    }
    return "已加入衣橱：\(clothingName)（\(summary)）"
  }

  // MARK: 形态 B：加入并编辑

  private func openEditorToWardrobe(item: MidsummerItemDTO, series: MidsummerSeriesDTO) {
    MidsummerWardrobeInserter.openEditor(
      item: item,
      series: series,
      brandName: brandName,
      modelContext: modelContext
    )
  }

  // MARK: 左栏 · 年份（图一左侧竖排）

  private var yearRail: some View {
    MidsummerYearRail(
      entries: store.yearEntries,
      activeYear: activeYear,
      onSelect: { year in
        withAnimation(.snappy(duration: 0.2)) {
          selectedYear = year
          selectedSeriesID = nil
        }
      }
    )
  }

  // MARK: 顶部 · 系列 chips（图一横排筛选）

  private var seriesChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        MidsummerSeriesChip(title: "全部", isSelected: selectedSeriesID == nil) {
          withAnimation(.snappy(duration: 0.2)) { selectedSeriesID = nil }
        }
        ForEach(seriesInActiveYear) { series in
          MidsummerSeriesChip(
            title: chipTitle(for: series),
            isSelected: selectedSeriesID == series.id
          ) {
            withAnimation(.snappy(duration: 0.2)) { selectedSeriesID = series.id }
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
  }

  /// 图一的 chip 文案是「2.9 小熊博物馆系列」——月.日 + 系列名。
  private func chipTitle(for series: MidsummerSeriesDTO) -> String {
    guard !series.launchedOn.isEmpty else { return series.name }
    let parts = series.launchedOn.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
      return series.name
    }
    return "\(month).\(day) \(series.name)"
  }

  // MARK: 「全部 ▸」行 —— 图一里那个进入详情页的静态入口

  private var allEntryRow: some View {
    Button(action: onOpenSeriesList) {
      HStack(spacing: 6) {
        Text(selectedSeriesID.flatMap { store.series(withID: $0)?.name } ?? "全部")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
        Spacer(minLength: 0)
        Text("查看全部系列")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
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
    .overlay(alignment: .bottom) {
      Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)
    }
  }

  // MARK: 商品卡片列表

  private var itemList: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(spacing: 0) {
        if feed.isEmpty {
          emptyState
        } else {
          ForEach(Array(feed.enumerated()), id: \.offset) { _, entry in
            itemCard(series: entry.series, item: entry.item)
            Rectangle().fill(MidsummerTheme.divider).frame(height: 0.5)
          }
          MidsummerDataNote(store: store)
        }
      }
      // 底部留出悬浮 dock 的高度。原来只留 24pt，页脚最后一行（创作者模式引导）
      // 会被 dock 永久压住——既看不见也点不到。
      .padding(.bottom, 110)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "shippingbox")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .themeSkinLegibleSymbol(level: .badge, slot: MidsummerThemeSlot.emptyState)
      Text("该筛选下暂无收录")
        .font(.system(size: 13))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.emptyState)
      if store.canContribute {
        Text("可在右上角「上传上新」补充")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.emptyState)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 44)
    .themeSkinLegibilityBackdrop(
      level: .preview,
      slot: MidsummerThemeSlot.emptyState,
      cornerRadius: 0
    )
  }

  /// 商品卡片：实现见 MidsummerItemCard。
  /// 抽成独立组件是为了能被快照测试单独渲染——首页整页在 ScrollView 里，
  /// `ImageRenderer` 只渲染可视区框架，拿不到卡片真实内容。
  private func itemCard(series: MidsummerSeriesDTO, item: MidsummerItemDTO) -> some View {
    MidsummerItemCard(
      series: series,
      item: item,
      onTap: {
        detailSeries = series
        detailItem = item
      },
      // 「每个商品上提供直接加入衣橱的入口」——卡片右侧就是形态 A。
      onQuickInsert: { quickInsertToWardrobe(item: item, series: series) },
      isInserting: insertingItemID == item.id,
      didInsert: insertedItemIDs.contains(item.id)
    )
  }
}

// MARK: - 商品卡片（图一的核心元素）
//
// 复刻图一的「左方图 + 右标题/价格」横向结构：
//   • 左：106pt 方图
//   • 右：阶段徽标 + 款名，价格用「小 ¥ + 大数字」两段字号拼接
//   • 底部：尺码行（缺项显示「款码待补」）
//   • 最右：橙色加购图标
//
// ⚠️ 历史问题（本轮修复）：最右那个橙色 `bag.badge.plus` 以前只是一个 **装饰性
// `Image`**，没有任何点击行为。使用者以为它是「加入衣橱」入口，点下去只会命中整行，
// 于是被理解成「点了加号却什么都没发生／只弹出一个没有加购功能的详情页」。
// 现在它是一颗真正的按钮，与日牌商品卡的行为对齐（形态 A 一键入库）。

struct MidsummerItemCard: View {
  let series: MidsummerSeriesDTO
  let item: MidsummerItemDTO
  let onTap: () -> Void
  /// 形态 A：一键入库。为 nil 时按钮退化为只读图标（快照用）。
  var onQuickInsert: (() -> Void)? = nil
  var isInserting: Bool = false
  var didInsert: Bool = false

  var body: some View {
    // 同 `TimeHallCommerceItemCard`：不能用「外层 Button 套内层 Button」。
    // 整卡点击交给 contentShape + onTapGesture，内层功能按钮保持真 Button。
    HStack(alignment: .top, spacing: 10) {
      MidsummerCoverView(imageName: series.coverImage, series: series)
        .frame(width: 106, height: 106)

      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 5) {
          MidsummerStageBadge(stage: series.stage)
          Text(item.name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
          Spacer(minLength: 0)
        }

        Spacer(minLength: 6)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
          priceView
          Text(cardSubtitle(series: series, item: item))
            .font(.system(size: 11))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .lineLimit(1)
        }

        HStack(spacing: 6) {
          MidsummerSizesRow(sizes: item.sizes.isEmpty ? series.sizes : item.sizes, compact: true)
          if item.sizes.isEmpty && !series.sizes.isEmpty {
            MidsummerPendingTag(text: "款码待补")
          }
        }
        .padding(.top, 5)
      }

      wardrobeInsertButton
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
    .themeSkinAdaptiveSectionCard(
      slot: MidsummerThemeSlot.card,
      cornerRadius: 0,
      showsDecoration: false
    ) {
      MidsummerTheme.surface
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(item.name)，\(item.priceTextWithKind)")
  }

  /// 卡片右侧的加入衣橱入口（形态 A）。
  private var wardrobeInsertButton: some View {
    MidsummerWardrobeIconButton(
      isInserting: isInserting,
      didInsert: didInsert,
      isEnabled: onQuickInsert != nil,
      action: { onQuickInsert?() }
    )
    .padding(.top, 36)
  }
  /// 价格用不同字号拼接，还原图一「小 ¥ + 大数字」的观感。
  ///
  /// 口径（顺序不要改，也不要把定金并进区间）：
  ///   1. 预售期有定金 → 先显示定金（这是当下真正要付的钱）
  ///   2. 否则显示「参考价 / 现货价」**派生区间**
  ///   3. 都没有 → 明确标注「价格待补充」，不猜
  ///
  /// 归集商品的 `price` 是 nil、价格全在 SKU 表里，所以第 2 条读的是派生区间
  /// `item.priceRange`——否则「樱花小羊」会误显示成「价格待补充」。
  private var priceView: some View {
    let range = item.priceRange
    let deposit = item.deposit

    return Group {
      if let deposit {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text("定金 ¥").font(.system(size: 11, weight: .semibold))
          Text("\(deposit)").font(.system(size: 17, weight: .bold))
        }
        .foregroundStyle(MidsummerTheme.priceRed)
      } else if let range {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text(rangePrefix)
            .font(.system(size: rangePrefix.count > 1 ? 11 : 12, weight: .semibold))
          Text(range.min == range.max ? "\(range.min)" : "\(range.min)–\(range.max)")
            .font(.system(size: 19, weight: .bold))
        }
        .foregroundStyle(MidsummerTheme.priceRed)
      } else if let balance = item.balance {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text("尾款 ¥").font(.system(size: 11, weight: .semibold))
          Text("\(balance)").font(.system(size: 17, weight: .bold))
        }
        .foregroundStyle(MidsummerTheme.priceRed)
      } else {
        MidsummerPendingTag(text: "价格待补充")
      }
    }
  }

  /// 区间价的前缀：`¥` / `参考价 ¥` / `尾款 ¥`。
  ///
  /// 归集商品的价格**全在 SKU 表里**，单品层的 `deposit` / `balance` 都是 nil，
  /// 光看「¥160–400」会被当成全款区间——而它其实是两款的尾款。
  ///
  /// 只给**尾款**加前缀：参考价 / 商品页价虽然出处不同，但都是全款量级，
  /// 卡片上一眼能看懂；尾款不是全款，不标出来就会让人按全款估预算。
  /// 完整口径（含「参考价」）在详情页的 `priceTextWithKind` 里给出。
  private var rangePrefix: String {
    guard item.deposit == nil, !item.hasItemLevelPrice,
      let kind = item.variantPriceKind, kind == .balance
    else { return "¥" }
    return "\(kind.labelZH) ¥"
  }

  /// 卡片副标题：`樱花小羊 · 含 9 个款式` / `蝴蝶结·永恒花园 · 4 款`。
  private func cardSubtitle(series: MidsummerSeriesDTO, item: MidsummerItemDTO) -> String {
    if item.variantCount > 1 {
      return "\(series.name) · 含 \(item.variantCount) 个款式"
    }
    return "\(series.name) · \(series.items.count) 款"
  }
}

// MARK: - 加入衣橱的图标入口（商品卡与系列页共用）
//
// 统一一处的意义：以前仲夏物语那个橙色 `bag.badge.plus` 在**每个**列表页各画了一遍，
// 都是「无底色的描边图标」——压在浅色商品图上对比度低，且一个都不是按钮。
// 现在收敛成组件：橙底白图标 + 细白描边 + 投影，并且**一定是真按钮**。

struct MidsummerWardrobeIconButton: View {
  var isInserting = false
  var didInsert = false
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(
        systemName: didInsert
          ? "checkmark.circle.fill"
          : (isInserting ? "hourglass" : TimeHallWardrobeInsertMode.quickInsert.symbolName)
      )
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(.white)
      .padding(8)
      .background(MidsummerTheme.brandOrange, in: Circle())
      .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
      .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
    .buttonStyle(.plain)
    .disabled(isInserting || !isEnabled)
    .accessibilityLabel(TimeHallWardrobeInsertMode.quickInsert.title)
    .accessibilityHint(TimeHallWardrobeInsertMode.quickInsert.hint)
  }
}

// MARK: - 单品详情弹窗

struct MidsummerItemDetailSheet: View {
  let series: MidsummerSeriesDTO
  let item: MidsummerItemDTO
  /// 入库时的品牌名。默认取品牌页固定的「仲夏物语」。
  var brandName: String = "仲夏物语"

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var isInsertingToWardrobe = false
  @State private var quickInsertMessage: String?
  /// 规格抽屉是否展开
  @State private var showsSpecDrawer = false
  /// 抽屉的入库意图：详情页两个按钮共用同一个面板，只是主按钮的去向不同
  @State private var drawerIntent: MidsummerWardrobeInsertIntent = .quickInsert

  // 单品图补录（对齐千牛发布路径：主图宫格，最多 5 张，第 1 张为主图；运营者白名单门控）：
  // 本弹层里的 `item` 是值拷贝，保存后用 `uploadedImageNames` 乐观回显，
  // 背后列表交给 `refreshFromCloud()` 全量刷新。
  @State private var supplementPhotoItem: [PhotosPickerItem] = []
  @State private var isUploadingItemImage = false
  @State private var uploadedImageNames: [String]?
  @State private var itemImageMessage: String?
  // 款式对应图（图2「粉色JSK / 粉色OP」样式）：每款一个独立图位，图与款式一一对应。
  @State private var uploadedVariantImageNames: [String: String]?
  /// 正在为哪个款式选图（单个 PhotosPicker 供全部款式共用，靠它区分目标款式）
  @State private var variantPickerTarget: String?
  @State private var variantPhotoItem: PhotosPickerItem?

  /// 单品图片上限（与千牛发布宝贝一致：5 张，第 1 张为主图）
  private static let maxItemImages = 5

  /// 展示/编辑中的图片名列表：本会话已保存的 > 云端已回填的（主图 + 附图，按序）。
  private var workingImageNames: [String] {
    if let uploadedImageNames { return uploadedImageNames }
    return ([item.coverImage] + (item.galleryImageNames ?? [])).compactMap { $0 }
  }

  /// 图片名 → 本地 UIImage（供整条重写时把已有图一并带上）。
  private func loadImages(_ names: [String]) -> [UIImage] {
    names.compactMap { ImageManager.shared.loadImage(fileName: $0) }
  }

  /// 形态 A：一键入库。
  ///
  /// 与淘宝「加入购物车」一致：点按钮先**选规格**，不直接落库。
  /// 规格缺省的单品也走同一条路径——面板会明确写「该单品暂无规格可选」，
  /// 而不是悄悄跳过选择这一步（使用者无从判断自己漏选了什么）。
  private func quickInsertToWardrobe(selection: MidsummerSpecSelection, quantity: Int) {
    guard !isInsertingToWardrobe else { return }
    isInsertingToWardrobe = true
    defer { isInsertingToWardrobe = false }

    do {
      let clothing = try MidsummerWardrobeInserter.quickInsert(
        item: item,
        series: series,
        brandName: brandName,
        selection: selection,
        quantity: quantity,
        modelContext: modelContext
      )
      let spec = MidsummerSpecResolver.summary(selection, of: item)
      let count = quantity > 1 ? " ×\(quantity)" : ""
      quickInsertMessage = spec.map { "已加入衣橱：\(clothing.name)\(count)（\($0)）" }
        ?? "已加入衣橱：\(clothing.name)\(count)"
    } catch {
      quickInsertMessage = "加入失败：" + error.localizedDescription
    }
  }

  /// 形态 B：加入并编辑（跳衣橱编辑页并预填）。
  ///
  /// 同样先选规格：预填进编辑页的配色/尺码就是使用者刚挑的那套，
  /// 否则编辑页里会出现「我明明选了粉色，怎么没有」的困惑。
  private func openEditorToWardrobe(selection: MidsummerSpecSelection, quantity: Int) {
    let draft = MidsummerWardrobeDraftBuilder.makeDraft(
      for: item,
      series: series,
      brandName: brandName,
      selection: selection,
      quantity: quantity,
      modelContext: modelContext
    )
    dismiss()
    TabNavigationManager.shared.presentWardrobeCreation(with: draft)
  }

  private func presentDrawer(_ intent: MidsummerWardrobeInsertIntent) {
    drawerIntent = intent
    withAnimation(.easeOut(duration: 0.2)) { showsSpecDrawer = true }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          MidsummerCoverView(
            imageName: workingImageNames.first ?? series.coverImage, series: series
          )
          .frame(height: 200)
          .frame(maxWidth: .infinity)

          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              MidsummerStageBadge(stage: series.stage, filled: true)
              Text(item.kind.shortLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MidsummerTheme.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(MidsummerTheme.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Text(item.name)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(MidsummerTheme.primaryText)

            Text(item.priceTextWithKind)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(MidsummerTheme.priceRed)

            if item.variantCount > 1 {
              labeledRow("包含款式", value: "\(item.variantCount) 款（同一商品链接内可选）")
            }
            if !item.colors.isEmpty {
              labeledRow("配色", value: item.colors.joined(separator: " / "))
            }
            labeledRow("尺码", value: item.sizesText)
            sizeChartSection
            variantImageSection
            itemImageSection
            if MidsummerSpecResolver.hasSpecs(item) {
              labeledRow("可选规格", value: MidsummerSpecResolver.groups(of: item).map(\.name).joined(separator: " / "))
            }
            labeledRow("所属系列", value: series.name)
            if !series.launchedOn.isEmpty {
              labeledRow("上新日期", value: series.launchDateText)
            } else {
              labeledRow("上新日期", value: "待补充")
            }

            if let note = item.note, !note.isEmpty {
              Text(note)
                .font(.system(size: 11))
                .foregroundStyle(MidsummerTheme.secondaryText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MidsummerTheme.orangeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 2)
            }

            // 加入衣橱：与日牌商品详情页一致，两种形态并列、视觉权重对等。
            // 两者都**先弹规格面板**再执行——对应淘宝「加入购物车」的交互。
            VStack(spacing: 7) {
              TimeHallWardrobeInsertButtons(
                isBusy: isInsertingToWardrobe,
                onQuickInsert: { presentDrawer(.quickInsert) },
                onOpenEditor: { presentDrawer(.openEditor) },
                // 详情页弹在列表之上，背后卡片的同名按钮仍在层级里；
                // 加前缀让 UI 测试能精确定位到详情页这一组。
                identifierPrefix: "midsummer-detail"
              )

              if let quickInsertMessage {
                Text(quickInsertMessage)
                  .font(.system(size: 11))
                  .foregroundStyle(MidsummerTheme.brandOrange)
                  .transition(.opacity)
              }
            }
            .padding(.top, 6)

            // 归集后的商品在同一个电商链接下展示，所以这里把「商品链接」单独给出；
            // 「原文出处」仍是资料出处（可能是资讯页），两者用途不同，不要合并。
            if let shopURL = item.itemURL.flatMap({ $0.isEmpty ? nil : $0 }),
              let shop = URL(string: shopURL)
            {
              Link(destination: shop) {
                Label("查看商品链接（该商品全部款式在同一链接内）", systemImage: "link")
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(MidsummerTheme.brandOrange)
                  .fixedSize(horizontal: false, vertical: true)
                  .multilineTextAlignment(.leading)
              }
              .padding(.top, 2)
            }

            Text("本页仅作衣橱搭配参考，不提供购买。")
              .font(.system(size: 10))
              .foregroundStyle(MidsummerTheme.secondaryText)
              .padding(.top, 4)
          }
          .padding(.horizontal, 16)
        }
        .padding(.bottom, 24)
      }
      .background(MidsummerTheme.pageBackground)
      .navigationTitle(series.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("完成") { dismiss() }
        }
      }
      .onChange(of: supplementPhotoItem) { _, newValue in
        guard !newValue.isEmpty else { return }
        let picked = newValue
        supplementPhotoItem = []
        Task { await appendItemImages(picked) }
      }
      .onChange(of: variantPhotoItem) { _, newValue in
        guard let newValue, let target = variantPickerTarget else { return }
        variantPhotoItem = nil
        variantPickerTarget = nil
        Task { await uploadVariantImage(newValue, for: target) }
      }
    }
    // 规格抽屉：覆盖在整个详情页之上（含导航栏），与淘宝「加入购物车」面板一致。
    // 用 `if` 而不是「常驻 + 位移」，是为了让**没展开时这些按钮根本不在层级里**——
    // 否则 UI 测试会误以为能看到、能点到，真实使用者却看不到（本轮踩过的坑）。
    .overlay {
      if showsSpecDrawer {
        MidsummerSpecDrawer(
          item: item,
          series: series,
          intent: drawerIntent,
          onConfirm: { selection, quantity in
            let intent = drawerIntent
            withAnimation(.easeOut(duration: 0.2)) { showsSpecDrawer = false }
            if intent == .quickInsert {
              quickInsertToWardrobe(selection: selection, quantity: quantity)
            } else {
              openEditorToWardrobe(selection: selection, quantity: quantity)
            }
          },
          onClose: {
            withAnimation(.easeOut(duration: 0.2)) { showsSpecDrawer = false }
          }
        )
        .transition(.opacity)
      }
    }
  }

  /// 单品尺码表（双方案设计 §一.2 / §四）：
  /// 有图 → 折叠面板展开即看；无图 → 如实标注「待补充」，不虚构数据。
  /// 图片来源两处：淘宝详情页自动采集（scrapers/ 管线，经 CloudKit 下发）或运营者补录上传，
  /// 两者最终都落在 `MidsummerItemDTO.sizeChartImageName` 这一个字段上。
  @ViewBuilder
  private var sizeChartSection: some View {
    let chartName = item.sizeChartImageName
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .flatMap { $0.isEmpty ? nil : $0 }
    DisclosureGroup {
      if let chartName, let image = ImageManager.shared.loadImage(fileName: chartName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("midsummer-item-sizechart-image")
      } else {
        Label("尺码表待补充——运营者可在补录入口上传", systemImage: "ruler")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .padding(.vertical, 4)
          .accessibilityIdentifier("midsummer-item-sizechart-missing")
      }
    } label: {
      Text("单品尺码表")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)
    }
    .accessibilityIdentifier("midsummer-item-sizechart")
  }

  // MARK: 款式对应图（图2「粉色JSK / 粉色OP」样式）

  /// 展示/编辑中的款式图：本会话已保存的 > 云端已回填的。
  private var workingVariantImages: [String: String] {
    if let uploadedVariantImageNames { return uploadedVariantImageNames }
    return item.variantImageNames ?? [:]
  }

  /// 款式名列表（图位的分组依据）：
  /// 1. 有「款式」规格组 → 选项名（如「印花JSK」）；
  /// 2. 没有规格组但有颜色分类 → 「颜色 + 类型短标」（如「粉色OP」——图2 的对应方式）；
  ///    单品自身 colors 为空时回退系列级颜色分类（上新表单把颜色填在系列步骤①）；
  /// 3. 都没有 → 不展示该区块，单品图只有整条宫格。
  private var variantKeys: [String] {
    if let groups = item.specGroups,
      let variant = groups.first(where: { $0.resolvedRole == .variant && !$0.options.isEmpty })
    {
      return variant.options.map(\.name)
    }
    let colors = item.colors.isEmpty ? series.colors : item.colors
    guard !colors.isEmpty else { return [] }
    return colors.map { "\($0)\(item.kind.shortLabel)" }
  }

  /// 款式对应图区块：每个款式一个独立图位（图 + 补录/更换/删除入口），
  /// 与下方整条单品共用的主图宫格是两个维度——图必须**归属到具体款式**，
  /// 而不是把所有图堆进同一个宫格。
  @ViewBuilder
  private var variantImageSection: some View {
    let keys = variantKeys
    let extraKeys = workingVariantImages.keys.filter { !keys.contains($0) }.sorted()
    let allKeys = keys + extraKeys
    if !allKeys.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("款式对应图")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("每款一张专属图，与款式一一对应；不会混入下方整条商品的主图宫格。")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)

        ForEach(allKeys, id: \.self) { key in
          variantImageRow(key)
        }
      }
    }
  }

  private func variantImageRow(_ variant: String) -> some View {
    let imageFile = workingVariantImages[variant]
    return HStack(alignment: .center, spacing: 10) {
      Group {
        if let imageFile, let image = ImageManager.shared.loadImage(fileName: imageFile) {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          ZStack {
            MidsummerTheme.subtleFill
            Image(systemName: "photo")
              .font(.system(size: 18, weight: .light))
              .foregroundStyle(MidsummerTheme.secondaryText)
          }
        }
      }
      .frame(width: 56, height: 56)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .accessibilityIdentifier("midsummer-variant-image-\(variant)")

      VStack(alignment: .leading, spacing: 4) {
        Text(variant)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MidsummerTheme.primaryText)
        if imageFile == nil {
          Text("款式图待补充")
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.secondaryText)
        }
        if MidsummerStore.shared.isAdminUser {
          HStack(spacing: 12) {
            PhotosPicker(
              selection: Binding(
                get: { variantPickerTarget == variant ? variantPhotoItem : nil },
                set: { newValue in
                  variantPickerTarget = variant
                  variantPhotoItem = newValue
                }
              ),
              matching: .images
            ) {
              Label(
                imageFile == nil ? "补录款式图" : "更换",
                systemImage: imageFile == nil ? "photo.badge.plus" : "arrow.2.squarepath"
              )
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(MidsummerTheme.brandOrange)
            }
            .disabled(isUploadingItemImage)
            .accessibilityIdentifier("midsummer-variant-image-pick-\(variant)")

            if imageFile != nil {
              Button {
                Task { await deleteVariantImage(variant) }
              } label: {
                Label("删除", systemImage: "trash")
                  .font(.system(size: 11))
                  .foregroundStyle(MidsummerTheme.secondaryText)
              }
              .disabled(isUploadingItemImage)
              .accessibilityIdentifier("midsummer-variant-image-delete-\(variant)")
            }

            if isUploadingItemImage {
              ProgressView()
            }
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
  }

  /// 单品图宫格 + 运营者补录入口（对齐千牛发布路径）。
  ///
  /// 展示：主图（第 1 张，带角标）+ 附图按序宫格；无图时如实标注「待补充」，
  /// 且**始终保留上传位**。运营者（`MidsummerStore.shared.isAdminUser`）可
  /// 多选追加（最多补到 5 张）、单张删除，保存走 `publish(item:images:)`
  /// 以单品 id 为 recordID 整条重写——DTO 字段齐全，不会覆盖丢失已有数据。
  private var itemImageSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("单品图片")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)

      let names = workingImageNames
      if names.isEmpty {
        Label("单品图待补充——运营者可在下方上传", systemImage: "photo")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .padding(.vertical, 4)
          .accessibilityIdentifier("midsummer-item-image-missing")
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
          ForEach(names.indices, id: \.self) { index in
            ZStack(alignment: .topTrailing) {
              Group {
                if let image = ImageManager.shared.loadImage(fileName: names[index]) {
                  Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                } else {
                  MidsummerCoverView(imageName: names[index], series: nil)
                }
              }
              .frame(height: 88)
              .frame(maxWidth: .infinity)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              .accessibilityIdentifier("midsummer-item-image-\(index)")

              if MidsummerStore.shared.isAdminUser, !isUploadingItemImage {
                Button {
                  Task { await deleteItemImage(at: index) }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                }
                .accessibilityIdentifier("midsummer-item-image-delete-\(index)")
              }
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
              }
            }
          }
        }
      }

      if MidsummerStore.shared.isAdminUser {
        PhotosPicker(
          selection: $supplementPhotoItem,
          maxSelectionCount: Self.maxItemImages - names.count,
          matching: .images
        ) {
          HStack {
            Label(
              names.isEmpty ? "补录单品图" : "追加图片（还可传 \(Self.maxItemImages - names.count) 张）",
              systemImage: "plus.square.on.square"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(MidsummerTheme.brandOrange)
            Spacer()
            if isUploadingItemImage {
              ProgressView()
            }
          }
        }
        .disabled(isUploadingItemImage || names.count >= Self.maxItemImages)
        .accessibilityIdentifier("midsummer-item-image-supplement")
      }

      if let itemImageMessage {
        Text(itemImageMessage)
          .font(.system(size: 10))
          .foregroundStyle(
            itemImageMessage.hasPrefix("已") ? MidsummerTheme.freshGreen : MidsummerTheme.brandOrange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// 追加图片：新图先落盘（与 fetch 侧 copyItemCoverAsset 同一命名空间），
  /// 再把「已有图 + 新图」按千牛宫格顺序整条重写。
  private func appendItemImages(_ pickerItems: [PhotosPickerItem]) async {
    guard !pickerItems.isEmpty, !isUploadingItemImage else { return }
    isUploadingItemImage = true
    defer {
      isUploadingItemImage = false
      itemImageMessage = nil
    }

    do {
      var names = workingImageNames
      let stamp = Int(Date().timeIntervalSince1970)
      for (offset, pickerItem) in pickerItems.prefix(Self.maxItemImages - names.count).enumerated() {
        guard let data = try await pickerItem.loadTransferable(type: Data.self),
          let image = UIImage(data: data),
          let jpeg = image.jpegData(compressionQuality: 0.85)
        else {
          itemImageMessage = "有图片读取失败，其余图片已保存。"
          continue
        }
        let fileName = "midsummer-item-\(item.id)-new-\(stamp)-\(offset).jpg"
        let destination = ImageManager.shared.imagesDirectory.appendingPathComponent(fileName)
        try jpeg.write(to: destination, options: .atomic)
        names.append(fileName)
      }

      // 整条重写：已有图（本地读回）+ 新图一并按序上传，主图始终是第 1 张。
      try await MidsummerCloudService.shared.publish(
        item: item, images: loadImages(names), sizeChartImage: nil)
      uploadedImageNames = names
      itemImageMessage = "已上传，其他用户刷新后可见。"
      Task { await MidsummerStore.shared.refreshFromCloud() }
    } catch {
      itemImageMessage = "上传失败：\(error.localizedDescription)"
    }
  }

  /// 删除单张图：从宫格移除后整条重写（主图位顺移，与千牛删除主图格一致）。
  private func deleteItemImage(at index: Int) async {
    guard workingImageNames.indices.contains(index), !isUploadingItemImage else { return }
    isUploadingItemImage = true
    defer {
      isUploadingItemImage = false
      itemImageMessage = nil
    }

    var names = workingImageNames
    names.remove(at: index)
    do {
      try await MidsummerCloudService.shared.publish(
        item: item, images: loadImages(names), sizeChartImage: nil)
      uploadedImageNames = names
      itemImageMessage = names.isEmpty ? "已清空单品图。" : "已删除，其他用户刷新后可见。"
      Task { await MidsummerStore.shared.refreshFromCloud() }
    } catch {
      itemImageMessage = "删除失败：\(error.localizedDescription)"
    }
  }

  /// 上传/更换某个款式的对应图。
  ///
  /// publish 是整条重写：主图宫格 + **全部**款式图必须一并带上，缺一即被抹掉。
  /// 槽位顺序 = 款式名顺序（variantKeys 优先，历史遗留 key 排尾），保证重复上传时
  /// 同一款式稳定落在同一资产槽，不会互相串位。
  private func uploadVariantImage(_ pickerItem: PhotosPickerItem, for variant: String) async {
    guard !isUploadingItemImage else { return }
    isUploadingItemImage = true
    defer { isUploadingItemImage = false }

    do {
      guard let data = try await pickerItem.loadTransferable(type: Data.self),
        let image = UIImage(data: data)
      else {
        itemImageMessage = "图片读取失败，请换一张试试。"
        return
      }

      let orderedKeys =
        variantKeys
        + workingVariantImages.keys.filter { !variantKeys.contains($0) }.sorted()
      var entries: [(name: String, image: UIImage)] = []
      for key in orderedKeys {
        if key == variant {
          entries.append((key, image))
        } else if let fileName = workingVariantImages[key],
          let existing = ImageManager.shared.loadImage(fileName: fileName)
        {
          entries.append((key, existing))
        }
      }

      let published = try await MidsummerCloudService.shared.publish(
        item: item,
        images: loadImages(workingImageNames),
        sizeChartImage: nil,
        variantImages: entries
      )
      uploadedVariantImageNames = published.variantImageNames
      itemImageMessage = "已上传「\(variant)」款式图，其他用户刷新后可见。"
      Task { await MidsummerStore.shared.refreshFromCloud() }
    } catch {
      itemImageMessage = "上传失败：\(error.localizedDescription)"
    }
  }

  /// 删除某个款式的对应图：同样整条重写，只是该款式不再带图。
  private func deleteVariantImage(_ variant: String) async {
    guard workingVariantImages[variant] != nil, !isUploadingItemImage else { return }
    isUploadingItemImage = true
    defer { isUploadingItemImage = false }

    do {
      let orderedKeys =
        variantKeys
        + workingVariantImages.keys.filter { !variantKeys.contains($0) }.sorted()
      let entries: [(name: String, image: UIImage)] = orderedKeys.compactMap { key in
        guard key != variant,
          let fileName = workingVariantImages[key],
          let existing = ImageManager.shared.loadImage(fileName: fileName)
        else { return nil }
        return (key, existing)
      }

      let published = try await MidsummerCloudService.shared.publish(
        item: item,
        images: loadImages(workingImageNames),
        sizeChartImage: nil,
        variantImages: entries
      )
      uploadedVariantImageNames = published.variantImageNames
      itemImageMessage = "已删除「\(variant)」款式图。"
      Task { await MidsummerStore.shared.refreshFromCloud() }
    } catch {
      itemImageMessage = "删除失败：\(error.localizedDescription)"
    }
  }

  private func labeledRow(_ label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text(label)
        .font(.system(size: 12))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .frame(width: 60, alignment: .leading)
      Text(value)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MidsummerTheme.primaryText)
      Spacer(minLength: 0)
    }
  }
}

// MARK: - 数据完整性说明（页脚）
//
// 这里同时承担第二个职责：**创作者模式的发现入口**。
// 上传入口默认隐藏在顶栏之外（避免普通浏览者误入投稿页），如果不在页脚留一条可点的引导，
// 内容维护者就得自己猜到「设置 → 创作者模式」才能开启——那和「找不到入口」没区别。

struct MidsummerDataNote: View {
  @ObservedObject var store: MidsummerStore
  @ObservedObject private var creatorMode = CreatorMode.shared

  @State private var showsEnablePrompt = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 5) {
        Image(systemName: "info.circle")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Text(store.syncStatusText ?? "内容由公开渠道整理")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }

      Text("公开渠道信息可能不完整，缺项已标注「待补充」。")
        .font(.system(size: 10))
        .foregroundStyle(MidsummerTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

      if store.canContribute {
        HStack(spacing: 4) {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 10, weight: .semibold))
          Text(store.isAdminUser ? "点右上角「上传上新」补充缺项。" : "创作者模式已开启，点右上角「上传上新」补充缺项。")
            .font(.system(size: 10))
        }
        .foregroundStyle(MidsummerTheme.brandOrange)
      } else if store.creatorGate.isDefinitelyNotOperator {
        // 明确不在白名单：不再给出「开启创作者模式」的引导——那个开关撬不开这个闸门，
        // 给了按钮只会让人以为开关坏了。这里如实说明原因。
        Text("本机 iCloud 账户不在运营白名单里，因此不显示上传入口。")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("midsummer-creator-denied-note")
      } else {
        Button {
          showsEnablePrompt = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 10, weight: .semibold))
            Text("我是内容维护者，开启创作者模式以补充缺项")
              .font(.system(size: 10, weight: .medium))
          }
          .foregroundStyle(MidsummerTheme.brandOrange)
          .padding(.horizontal, 8)
          .padding(.vertical, 5)
          .background(MidsummerTheme.orangeSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("midsummer-enable-creator-mode")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.top, 18)
    .confirmationDialog(
      "开启创作者模式？",
      isPresented: $showsEnablePrompt,
      titleVisibility: .visible
    ) {
      Button("开启") { creatorMode.setEnabled(true) }
      Button("取消", role: .cancel) {}
    } message: {
      Text(
        "开启后，品牌页右上角会出现「上传上新」入口，用于补充缺失的上新系列与单品资料。\n\n"
          + "该开关只在「取不到本机 iCloud 身份」时（模拟器、未登录 iCloud、断网）用来放行界面。"
          + "如果本机账户已被明确判定为「不在运营白名单里」，入口一律不显示，这个开关也打不开它。\n\n"
          + "能否真正写入线上内容库，取决于该 iCloud 账户是否已被加入 CloudKit 创作者名单。"
      )
    }
  }
}
