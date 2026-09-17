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
  /// 款式分类与尺码表（原生资料页）
  case styleChartCatalog
  /// 链接原始信息（原生资料页）
  case linkReport
}

// MARK: - 品牌页宿主

struct MidsummerBrandView: View {
  var onClose: (() -> Void)?

  @ObservedObject private var store = MidsummerStore.shared
  /// 导航栈：同一页面可能从多个层级进入（首页卡片 → 系列详情 → 系列资料页），
  /// 用栈而不是单值路由，返回键才能总是回到「进入时的那一层」。
  @State private var path: [MidsummerRoute] = []
  /// 双视角状态（用户 / 创作者）：同一套骨架按它切换交互与可编辑性。
  @StateObject private var viewModeStore = MidsummerViewModeStore()
  /// 品牌首页右上角「上传上新」：直达新建系列的四步表单（不再选既有系列）。
  @State private var showingUploadForm = false

  private var route: MidsummerRoute { path.last ?? .home }

  var body: some View {
    ZStack {
      MidsummerTheme.pageBackground.ignoresSafeArea()

      VStack(spacing: 0) {
        MidsummerTopBar(
          title: title,
          subtitle: subtitle,
          showsBack: !path.isEmpty,
          onBack: goBack,
          onClose: onClose,
          // 主操作入口常驻品牌首页右上角：不上折叠菜单、不放二级弹窗（用户 2026-09-17）。
          onUpload: route == .home && viewModeStore.isCreator ? { showingUploadForm = true } : nil,
          // 切换控件本身只对运营白名单渲染；普通用户既无切换也无上传入口。
          viewMode: route == .home && store.canEnterCreatorView ? viewModeStore : nil
        )

        switch route {
        case .home:
          MidsummerHomeContent(
            store: store,
            onOpenSeriesList: { navigate(to: .seriesList) },
            onOpenSeriesDetail: { navigate(to: .seriesDetail(seriesID: $0)) }
          )
          .transition(pageTransition(forward: true))
        case .seriesList:
          MidsummerSeriesListView(
            store: store,
            onSelectSeries: { navigate(to: .seriesDetail(seriesID: $0)) }
          )
          .transition(pageTransition(forward: true))
        case .seriesDetail(let seriesID):
          MidsummerSeriesDetailView(
            store: store,
            seriesID: seriesID,
            onOpenStyleChartCatalog: { navigate(to: .styleChartCatalog) },
            onOpenLinkReport: { navigate(to: .linkReport) }
          )
          .transition(pageTransition(forward: true))
        case .styleChartCatalog:
          MidsummerStyleChartCatalogView()
            .transition(pageTransition(forward: true))
        case .linkReport:
          MidsummerLinkReportView()
            .transition(pageTransition(forward: true))
        }
      }
    }
    .task {
      await store.refreshFromCloud()
    }
    // 双视角状态向下传递：首页卡片 / 详情 / 规格面板读同一份真值。
    .environmentObject(viewModeStore)
    .sheet(isPresented: $showingUploadForm) {
      // 直达新建系列（用户 2026-09-17）：series 传 nil 进入新建模式，
      // 提交时用第①步填写的系列档案创建自建系列并挂上新品。
      MidsummerListingFormView(store: store)
    }
  }

  // MARK: 顶栏文案

  private var title: String {
    switch route {
    case .home: return store.catalog?.brandName ?? "仲夏物语"
    case .seriesList: return "全部系列"
    case .seriesDetail(let seriesID): return store.series(withID: seriesID)?.name ?? "系列详情"
    case .styleChartCatalog: return "款式分类与尺码表"
    case .linkReport: return "链接原始信息"
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
    case .styleChartCatalog:
      return "樱花小羊 · 15 类尺码资料"
    case .linkReport:
      return "淘宝商品页原文转录"
    }
  }

  // MARK: 导航

  private func navigate(to destination: MidsummerRoute) {
    withAnimation(.easeInOut(duration: 0.22)) { path.append(destination) }
  }

  private func goBack() {
    guard !path.isEmpty else {
      onClose?()
      return
    }
    withAnimation(.easeInOut(duration: 0.22)) { path.removeLast() }
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
  let onBack: () -> Void
  let onClose: (() -> Void)?
  /// 非 nil 时右上角显示「上传上新」主操作按钮（仅品牌首页传入）。
  var onUpload: (() -> Void)? = nil
  /// 双视角：非 nil 时右上角显示「用户 / 创作者」分段控件（仅品牌首页、
  /// 且仅运营白名单可见；普通用户完全看不到，见 `MidsummerStore.canEnterCreatorView`）。
  var viewMode: MidsummerViewModeStore? = nil

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
          .minimumScaleFactor(0.75)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(MidsummerTheme.secondaryText)
            .themeSkinLegibleText(level: .inline, slot: MidsummerThemeSlot.topBar)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
      }
      // 标题区让位：小屏时标题/副标题先缩放、再截断，保证右侧主按钮完整可点不重叠。
      .layoutPriority(1)

      Spacer(minLength: 0)

      // 双视角：切换控件在上，创作者视图下的「上传」入口在它正下方。
      if let viewMode {
        VStack(alignment: .trailing, spacing: 6) {
          MidsummerViewModeSwitch(store: viewMode)
          if viewMode.isCreator, let onUpload {
            Button(action: onUpload) {
              HStack(spacing: 4) {
                Image(systemName: "plus.square.on.square")
                  .font(.system(size: 11, weight: .bold))
                Text("上传上新")
                  .font(.system(size: 12, weight: .medium))
              }
              .foregroundStyle(MidsummerTheme.brandOrange)
              .themeSkinLegibleText(level: .badge, slot: MidsummerThemeSlot.topBarAddButton)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("brand-upload-entry")
            .accessibilityLabel("上传上新")
            .transition(.move(edge: .trailing).combined(with: .opacity))
          }
        }
        .animation(.easeOut(duration: 0.18), value: viewMode.mode)
      } else if let onUpload {
        Button(action: onUpload) {
          HStack(spacing: 4) {
            Image(systemName: "plus.square.on.square")
              .font(.system(size: 11, weight: .bold))
            Text("上传上新")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(MidsummerTheme.brandOrange)
          .themeSkinLegibleText(level: .badge, slot: MidsummerThemeSlot.topBarAddButton)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(MidsummerTheme.orangeSurface)
          .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brand-upload-entry")
        .accessibilityLabel("上传上新")
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

// MARK: - 双视角切换（用户 2026-09-17）

/// 顶栏右上角的两段式切换：当前视角高亮 + 图标，一眼可辨。
/// 只对运营白名单渲染（调用方已按 `canEnterCreatorView` 门控）。
struct MidsummerViewModeSwitch: View {
  @ObservedObject var store: MidsummerViewModeStore

  var body: some View {
    HStack(spacing: 0) {
      ForEach(MidsummerViewMode.allCases, id: \.self) { mode in
        let isSelected = store.mode == mode
        Button {
          withAnimation(.easeOut(duration: 0.16)) { store.setMode(mode) }
        } label: {
          HStack(spacing: 3) {
            Image(systemName: mode.iconSystemName)
              .font(.system(size: 9, weight: .bold))
            Text(mode.shortLabel)
              .font(.system(size: 11, weight: .semibold))
          }
          .foregroundStyle(isSelected ? Color.white : MidsummerTheme.secondaryText)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(
            isSelected ? MidsummerTheme.brandOrange : MidsummerTheme.secondaryText.opacity(0.10),
            in: Capsule()
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(mode.accessibilityIdentifier)
        .accessibilityLabel(mode.labelZH)
        .accessibilityValue(isSelected ? "当前视角" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(2)
    // ⚠️ 容器上**不要**再挂 accessibilityIdentifier：SwiftUI 会把容器标识
    // 合并给子按钮，两段按钮会同时报同一个 identifier，UI 测试无法区分
    // （本轮踩过）。区分靠各自按钮上的 `mode.accessibilityIdentifier`。
    .background(MidsummerTheme.secondaryText.opacity(0.08), in: Capsule())
  }
}

// MARK: - 首页（对应图一）

struct MidsummerHomeContent: View {
  @ObservedObject var store: MidsummerStore
  let onOpenSeriesList: () -> Void
  /// 合并后的系列入口卡片 → 系列详情（同一系列的多个链接从详情页进入）
  let onOpenSeriesDetail: (String) -> Void

  @Environment(\.modelContext) private var modelContext
  /// 双视角：同一套卡片骨架，创作者视图下点卡片进编辑态、并显示编辑角标。
  @EnvironmentObject private var viewMode: MidsummerViewModeStore

  @State private var selectedYear: Int?
  @State private var selectedSeriesID: String?
  @State private var detailItem: MidsummerItemDTO?
  @State private var detailSeries: MidsummerSeriesDTO?
  /// 创作者视图下点卡片 → 详情直接是可编辑表单，而不是只读展示。
  @State private var detailStartsEditing = false

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

  /// 首页 feed 按系列归组：同一系列的多个商品链接（如樱花小羊 主链 + 小物链）
  /// 合并为一张系列入口卡片，不再各自占一行——「三个条目指向同一系列」的
  /// 旧布局会让人以为它们是三件不相关的商品。
  private var visibleSeries: [MidsummerSeriesDTO] {
    guard let activeYear else { return [] }
    let inYear = store.allSeries.filter { $0.year == activeYear }
    if let selectedSeriesID { return inYear.filter { $0.id == selectedSeriesID } }
    return inYear
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
        // 同一份详情组件：用户视图只读，创作者视图直接是可编辑表单。
        MidsummerItemDetailSheet(
          series: series,
          item: item,
          brandName: brandName,
          startsEditing: detailStartsEditing
        )
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
    // 「全部商品」入口行的 ASCII identifier：UI 测试经「全部商品 → 系列列表 →
    // 系列详情」这条路径访问资料页（合并后樱花小羊是单条目系列，首页卡片
    // 直开单品详情，不再经过系列详情）。
    .accessibilityIdentifier("midsummer-entry-all-series")
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
        if visibleSeries.isEmpty {
          emptyState
        } else {
          ForEach(visibleSeries) { series in
            // 上新工作台（用户 2026-09-16）的单品 id 带 `midsummer-listing-` 命名空间。
            // 单链接/组卡的判定只看**基础条目**——否则一上新就会把「樱花小羊」的
            // 单品卡变成组卡，改变既有交互；上架新品以独立商品卡追加在本系列下方，
            // 与原款同样可点详情、可一键入库。
            let listingItems = series.items.filter { $0.id.hasPrefix(MidsummerListingItemIDPrefix) }
            let baseItems = series.items.filter { !$0.id.hasPrefix(MidsummerListingItemIDPrefix) }
            if baseItems.count == 1, let item = baseItems.first {
              // 单链接系列：与原来一样直接展示商品卡片（点击 → 单品详情）
              itemCard(series: series, item: item)
            } else {
              // 多链接系列：合并为一张系列入口卡片（点击 → 系列详情）
              MidsummerSeriesGroupCard(series: series) {
                onOpenSeriesDetail(series.id)
              }
            }
            ForEach(listingItems, id: \.id) { item in
              itemCard(series: series, item: item)
            }
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
        // 创作者视图：点卡片 = 进入该商品的编辑态，不再只是浏览。
        detailStartsEditing = viewMode.isCreator
      },
      // 「每个商品上提供直接加入衣橱的入口」——卡片右侧就是形态 A。
      onQuickInsert: { quickInsertToWardrobe(item: item, series: series) },
      isInserting: insertingItemID == item.id,
      didInsert: insertedItemIDs.contains(item.id),
      showsEditingBadge: viewMode.isCreator
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
  /// 创作者视图下的可编辑提示角标（同一张卡片骨架，仅多一枚提示）。
  var showsEditingBadge: Bool = false

  /// 用户视图留白更足，创作者视图更紧凑（信息密度优先）——只改数值，不改结构。
  private var contentSpacing: CGFloat { showsEditingBadge ? 10 : 12 }

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

        // 创作者视图：告诉你「点开直接编辑」，与用户视图的浏览预期区分开。
        if showsEditingBadge {
          HStack(spacing: 4) {
            Image(systemName: "square.and.pencil")
              .font(.system(size: 9, weight: .bold))
            Text("点击编辑名称 / 图片 / 描述")
              .font(.system(size: 10))
          }
          .foregroundStyle(MidsummerTheme.brandOrange)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(MidsummerTheme.orangeSurface, in: Capsule())
          .padding(.top, 6)
          .accessibilityIdentifier("midsummer-card-edit-badge-\(item.id)")
        }
      }

      wardrobeInsertButton
    }
    .padding(.horizontal, 12)
    .padding(.vertical, showsEditingBadge ? 11 : 14)
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
    // 按单品 id 的 ASCII identifier：UI 测试可定点到某张卡片的入库按钮，
    // 而不是「屏幕上第一个可见的一键入库」。
    // 注意必须挂在按钮本身上——外层卡片是 accessibilityElement(children:.contain)
    // 容器，挂在外部只会落到整卡元素上，查询会命中整卡而不是这颗按钮。
    .accessibilityIdentifier("midsummer-card-insert-\(item.id)")
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
  /// 只给**尾款**加前缀：参考价 / 现货价虽然出处不同，但都是全款量级，
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

// MARK: - 系列入口合并卡片（多链接系列）
//
// 同一系列的多个商品链接（樱花小羊 主链 + 小物链）在首页合并为一张卡片：
//   • 卡片外观与 MidsummerItemCard 同构（方图 + 徽章 + 名称 + 价格 + 尺码行），
//     价格/尺码/款数取全系列派生口径（¥59–999 覆盖两个链接的全部款式）；
//   • 点击整卡进入系列详情——两个链接、款式分类与尺码表、链接原始信息都在那里；
//   • 右侧不放「一键入库 ⊕」：一键入库需要明确到具体商品，两个链接时替使用者
//     静默挑一个就是以前的坑。入口收敛为「查看系列」，入库在详情页逐商品进行。

struct MidsummerSeriesGroupCard: View {
  let series: MidsummerSeriesDTO
  let onTap: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      MidsummerCoverView(imageName: series.coverImage, series: series)
        .frame(width: 106, height: 106)

      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 5) {
          MidsummerStageBadge(stage: series.stage)
          Text(series.name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MidsummerTheme.primaryText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
          Spacer(minLength: 0)
        }

        Spacer(minLength: 6)

        priceView

        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .lineLimit(1)

        MidsummerSizesRow(sizes: series.sizes, compact: true)
          .padding(.top, 5)
      }

      openSeriesButton
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
    .accessibilityLabel("\(series.name)，系列入口，\(series.items.count) 个商品链接，\(series.priceRangeText)")
    .accessibilityIdentifier("midsummer-series-card-\(series.id)")
  }

  private var priceView: some View {
    Group {
      if let range = series.priceRange {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text("¥").font(.system(size: 12, weight: .semibold))
          Text(range.min == range.max ? "\(range.min)" : "\(range.min)–\(range.max)")
            .font(.system(size: 19, weight: .bold))
        }
        .foregroundStyle(MidsummerTheme.priceRed)
      } else {
        MidsummerPendingTag(text: "价格待补充")
      }
    }
  }

  private var subtitle: String {
    let links = series.items.count
    let variants = series.variantCount
    if links > 1 && variants > 0 {
      return "\(series.name) 系列 · \(links) 个链接 · 含 \(variants) 个款式"
    }
    return "\(series.name) 系列 · \(series.itemCountText)"
  }

  /// 与 MidsummerWardrobeIconButton 同一视觉规格的圆形入口（箭头语义 = 查看）。
  /// 不是 Button：整卡点击已由 onTapGesture 承接，嵌套按钮会互相打架。
  private var openSeriesButton: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(.white)
      .padding(8)
      .background(MidsummerTheme.brandOrange, in: Circle())
      .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
      .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
      .padding(.top, 36)
  }
}

// MARK: - 资料页入口行（款式分类与尺码表 / 链接原始信息）
//
// 原先挂在品牌页首页顶层——同一系列的内容散落在三行里；现统一收进系列详情页。
// 视觉与 `allEntryRow`（全部商品入口）同一卡片样式。

struct MidsummerArchiveEntryRow: View {
  let title: String
  let subtitle: String
  let symbol: String
  let a11yID: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MidsummerTheme.brandOrange)
        Text(title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
        Spacer(minLength: 0)
        Text(subtitle)
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
    .accessibilityIdentifier(a11yID)
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
  /// 创作者视图下点开即编辑（用户 2026-09-17）：同一份组件，字段变可编辑 + 出现保存。
  var startsEditing: Bool = false

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var viewMode: MidsummerViewModeStore

  @State private var isInsertingToWardrobe = false
  @State private var quickInsertMessage: String?
  /// 规格抽屉是否展开
  @State private var showsSpecDrawer = false
  /// 抽屉的入库意图：详情页两个按钮共用同一个面板，只是主按钮的去向不同
  @State private var drawerIntent: MidsummerWardrobeInsertIntent = .quickInsert

  // 编辑态：名称 / 描述 / 主图（创作者视图，用户 2026-09-17）。
  @State private var isEditing = false
  @State private var editedName: String = ""
  @State private var editedNote: String = ""
  @State private var isSaving = false
  @State private var saveMessage: String?
  /// 主图替换（PhotosPicker）：保存时与整条图片一起 publish。
  @State private var coverPickerItem: PhotosPickerItem?
  @State private var pickedCoverImage: UIImage?

  // 图片上传进度与提示（款式对应图的补录/更换/删除共用；白名单门控见 isAdminUser）：
  // 本弹层里的 `item` 是值拷贝，保存后背后列表交给 `refreshFromCloud()` 全量刷新。
  @State private var isUploadingItemImage = false
  @State private var itemImageMessage: String?
  // 款式对应图（图2「粉色JSK / 粉色OP」样式）：每款一个独立图位，图与款式一一对应。
  @State private var uploadedVariantImageNames: [String: String]?
  /// 正在为哪个款式选图（单个 PhotosPicker 供全部款式共用，靠它区分目标款式）
  @State private var variantPickerTarget: String?
  @State private var variantPhotoItem: PhotosPickerItem?

  /// 详情头图与款式图整条重写时携带的图片名列表（主图 + 附图，按序）。
  private var workingImageNames: [String] {
    ([item.coverImage] + (item.galleryImageNames ?? [])).compactMap { $0 }
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

  /// 多选配一套（用户 2026-09-16）：勾选的多件款式一次入库为**同一套**。
  ///
  /// 每个勾选项各落一条 `Clothing`（字段互不相同，合并成一条会丢数据），
  /// 「同一套」由**共同的套装标记**体现：每条记录的备注里写
  /// 「套装入库：<时间标记>（N 件一套）」+「套装成员：…」，按标记即可互相认定。
  /// 复用既有单件链路（makeDraft → QuickInserter），字段口径完全一致；
  /// 中途失败时已写入的成员保留（真实落库成功），失败原因进吐司。
  private func quickInsertSetToWardrobe(selections: [MidsummerSpecSelection], quantity: Int) {
    guard !isInsertingToWardrobe, !selections.isEmpty else { return }
    isInsertingToWardrobe = true
    defer { isInsertingToWardrobe = false }

    let memberNames = selections.map { MidsummerSpecResolver.displayName(item, selection: $0) }
    let marker = Self.setFormatter.string(from: Date())
    let setLines = [
      "套装入库：\(marker)（\(selections.count) 件一套）",
      "套装成员：\(memberNames.joined(separator: "、"))",
    ]
    let countSuffix = quantity > 1 ? " ×\(quantity)" : ""

    do {
      for selection in selections {
        let draft = MidsummerWardrobeDraftBuilder.makeDraft(
          for: item,
          series: series,
          brandName: brandName,
          selection: selection,
          quantity: quantity,
          extraNoteLines: setLines,
          modelContext: modelContext
        )
        _ = try TimeHallWardrobeQuickInserter.insert(draft: draft, modelContext: modelContext)
      }
      quickInsertMessage =
        "已加入衣橱：\(selections.count) 件一套\(countSuffix)（\(memberNames.joined(separator: "、"))）"
    } catch {
      quickInsertMessage = "加入失败：" + error.localizedDescription
    }
  }

  /// 套装标记的时间戳（同批成员共享同一标记，凭备注互相认定一套）。
  private static let setFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()

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
          .clipped()
          .accessibilityIdentifier("midsummer-detail-hero")

          VStack(alignment: .leading, spacing: 8) {
            if isEditing {
              // 创作者视图：同一块位置和层级，只是把静态文本换成输入控件。
              VStack(alignment: .leading, spacing: 4) {
                Text("商品名称")
                  .font(.system(size: 11))
                  .foregroundStyle(MidsummerTheme.secondaryText)
                TextField("商品名称", text: $editedName)
                  .textFieldStyle(.roundedBorder)
                  .font(.system(size: 15, weight: .semibold))
                  .accessibilityIdentifier("midsummer-detail-name-field")

                Text("描述 / 备注")
                  .font(.system(size: 11))
                  .foregroundStyle(MidsummerTheme.secondaryText)
                  .padding(.top, 6)
                TextEditor(text: $editedNote)
                  .font(.system(size: 13))
                  .frame(minHeight: 76)
                  .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                      .stroke(MidsummerTheme.divider, lineWidth: 0.8)
                  )
                  .accessibilityIdentifier("midsummer-detail-note-field")

                HStack(spacing: 10) {
                  PhotosPicker(selection: $coverPickerItem, matching: .images) {
                    Label(
                      pickedCoverImage == nil ? "更换主图" : "已选新主图",
                      systemImage: "photo.badge.plus"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MidsummerTheme.brandOrange)
                  }
                  .accessibilityIdentifier("midsummer-detail-cover-picker")
                  if pickedCoverImage != nil {
                    Button("取消换图") { pickedCoverImage = nil; coverPickerItem = nil }
                      .font(.system(size: 12))
                  }
                  Spacer(minLength: 0)
                }
                .padding(.top, 6)
              }
              .padding(10)
              .background(MidsummerTheme.orangeSurface)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
              Text(item.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MidsummerTheme.primaryText)
            }

            // —— 价格区（用户 2026-09-17）：上新阶段只保留四类价格 ——
            // 定金 / 尾款 / 现货价 / 预约价。显示条件与互斥关系见
            // `MidsummerItemDTO.detailPriceRows(stage:)` 注释；其余（参考价、
            // 划线价、会员价、到手价、促销标签）一律不渲染。缺哪类就少哪行，
            // 不出现空白或「待补充」占位。
            // 上新工作台商品（id 带 listing 前缀）：定金-尾款预售结束后，
            // 预约价与现货价**同时展示**（业务规则第 4 条）。
            let isListingPresaleEnded = MidsummerListingStore.shared
              .listing(forItemID: item.id)?.presalePhase() == .ended
            let priceRows = item.detailPriceRows(stage: series.stage, presaleEnded: isListingPresaleEnded)
            if let headline = priceRows.first {
              Text("\(headline.label) \(headline.value)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MidsummerTheme.priceRed)
                .accessibilityIdentifier("midsummer-detail-price-headline")
              ForEach(priceRows.dropFirst(), id: \.label) { row in
                labeledRow(row.label, value: row.value)
                  .accessibilityIdentifier("midsummer-detail-price-row-\(row.label)")
              }
            } else {
              // 四类全空才走诚实态；这不是定金/尾款单缺时的占位。
              MidsummerPendingTag(text: "价格待补充")
                .accessibilityIdentifier("midsummer-detail-price-pending")
            }

            if !item.colors.isEmpty {
              labeledRow("配色", value: item.colors.joined(separator: " / "))
            }
            labeledRow("尺码", value: item.sizesText)

            // 加入衣橱：与日牌商品详情页一致，两种形态并列、视觉权重对等。
            // 两者都**先弹规格面板**再执行——对应淘宝「加入购物车」的交互。
            // 位置（用户 2026-09-16）：移到「款式对应图」上方，先给行动入口再看款式图。
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

            // 「单品尺码表」折叠区已移除（用户 2026-09-16：与款式对应图组内嵌的
            // 尺码表重复）——尺码表统一由 variantImageSection 各款式组下方承载。
            variantImageSection
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

            // 加入衣橱按钮已上移至「款式对应图」上方（用户 2026-09-16）。

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
          if isEditing {
            HStack(spacing: 12) {
              if isSaving { ProgressView() }
              Button("保存") { Task { await saveEdits() } }
                .disabled(isSaving)
                .accessibilityIdentifier("midsummer-detail-save")
              Button("完成") { dismiss() }
            }
          } else {
            HStack(spacing: 12) {
              // 只有创作者视图（运营白名单）才给出编辑入口——用户视图是只读详情。
              if viewMode.isCreator {
                Button {
                  withAnimation(.easeOut(duration: 0.18)) { isEditing = true }
                } label: {
                  Image(systemName: "square.and.pencil")
                }
                .accessibilityIdentifier("midsummer-detail-edit")
                .accessibilityLabel("编辑商品")
              }
              Button("完成") { dismiss() }
            }
          }
        }
      }
      .onAppear {
        editedName = item.name
        editedNote = item.note ?? ""
        if startsEditing || viewMode.isCreator { isEditing = startsEditing || viewMode.isCreator }
      }
      .onChange(of: coverPickerItem) { _, newValue in
        guard let newValue else { return }
        coverPickerItem = nil
        Task {
          guard let data = try? await newValue.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
          else { return }
          pickedCoverImage = image
        }
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
          },
          onMultiConfirm: { selections, quantity in
            withAnimation(.easeOut(duration: 0.2)) { showsSpecDrawer = false }
            quickInsertSetToWardrobe(selections: selections, quantity: quantity)
          }
        )
        .transition(.opacity)
      }
    }
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

  /// 按款式归组后的款式图数据：「现 sk 粉色 / 现 sk 蓝绿色」同属一族「sk」。
  /// 归组规则（用户口径：同款不同色一类，内搭等独立款式各自一类）：
  /// 选项名形如「现 <款式> <颜色>」——去掉「现」前缀后，最后一个 token 是颜色，
  /// 其余拼接为款式族；族名与 `sizeChartImages.style` 大小写不敏感匹配，
  /// 匹配上的族在其图片下方内嵌该款尺码表（图 2 注释口径：尺码表放归类好的图片下面）。
  private struct VariantStyleGroup: Identifiable {
    let family: String
    let displayName: String
    var keys: [String]
    let chart: MidsummerItemDTO.SizeChartEntry?
    var id: String { family }
  }

  private var variantStyleGroups: [VariantStyleGroup] {
    let ordered =
      variantKeys
      + workingVariantImages.keys.filter { !variantKeys.contains($0) }.sorted()
    var groups: [VariantStyleGroup] = []
    var indexByFamily: [String: Int] = [:]
    let charts = item.sizeChartImages ?? []
    for key in ordered {
      let tokens = key.split(separator: " ").map(String.init)
      let family: String
      if tokens.count >= 3, tokens.first == "现" {
        family = tokens.dropFirst().dropLast().joined(separator: " ")
      } else {
        // 历史遗留命名（如「粉色OP」）没有三段结构，整名自成一组。
        family = key
      }
      if let i = indexByFamily[family] {
        groups[i].keys.append(key)
      } else {
        indexByFamily[family] = groups.count
        let chart = charts.first { $0.style.lowercased() == family.lowercased() }
        groups.append(
          VariantStyleGroup(
            family: family,
            displayName: chart?.style ?? family,
            keys: [key],
            chart: chart
          ))
      }
    }
    return groups
  }

  /// 款式对应图区块：按款式归组展示（同款不同色同组），每组下方内嵌该款尺码表，
  /// 与下方整条单品共用的主图宫格是两个维度——图必须**归属到具体款式**，
  /// 而不是把所有图堆进同一个宫格。
  @ViewBuilder
  private var variantImageSection: some View {
    let groups = variantStyleGroups
    if !groups.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("款式对应图")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(MidsummerTheme.primaryText)
        Text("同款不同色归为一组；每组下方附该款尺码表，对照查看不用来回翻。")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)

        ForEach(groups) { group in
          variantStyleGroupSection(group)
        }
      }
    }
  }

  /// 单个款式组：组标题（款式名 + 配色数）→ 各配色图行 → 该款尺码表。
  private func variantStyleGroupSection(_ group: VariantStyleGroup) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(group.displayName)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MidsummerTheme.brandOrange)
        Text("\(group.keys.count) 个配色")
          .font(.system(size: 10))
          .foregroundStyle(MidsummerTheme.secondaryText)
        Spacer(minLength: 0)
      }
      .padding(.top, 4)

      // 配色图并排网格（用户 2026-09-16：可以并排，数量过多时可以多排）——
      // 固定 3 列自适应等宽，选项多时 LazyVGrid 自动换行，一行放不下 3 个才折行。
      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 10),
          GridItem(.flexible(), spacing: 10),
          GridItem(.flexible(), spacing: 10),
        ],
        alignment: .leading,
        spacing: 10
      ) {
        ForEach(group.keys, id: \.self) { key in
          variantImageCard(key)
        }
      }

      if let chart = group.chart {
        groupSizeChartRow(chart)
      }
    }
  }

  /// 组内尺码表：只放图（款式名已由组标题给出），保留与逐款尺码表一致的
  /// a11y 标识，保证两个入口的图都能被测试与辅助功能定位。
  private func groupSizeChartRow(_ entry: MidsummerItemDTO.SizeChartEntry) -> some View {
    Group {
      if let image = ImageManager.shared.loadImage(fileName: entry.imageName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("尺码表 \(entry.style)")
          .accessibilityIdentifier("midsummer-sizechart-\(entry.style)")
      } else {
        Label("该款式尺码表图缺失", systemImage: "ruler")
          .font(.system(size: 11))
          .foregroundStyle(MidsummerTheme.secondaryText)
          .padding(.vertical, 2)
      }
    }
    .padding(.top, 2)
    .padding(.bottom, 6)
  }

  /// 配色图卡片（网格单元）：方图在上、款式名在下，运营者操作按钮收纳在名字下方。
  /// 与旧横排行（56pt 小图 + 右侧长文案）相比，并排网格一屏能同框更多配色，
  /// 方便同款不同色对照（用户 2026-09-16 改版口径）。
  private func variantImageCard(_ variant: String) -> some View {
    let imageFile = workingVariantImages[variant]
    // 展示名去掉「现 」前缀（用户 2026-09-16：款式名前的「现」字不要）；
    // 注意「现货价」信息行不受影响。key 本身不动——图映射、identifier、
    // 上传槽位仍用全名，只改这一处可见文案。
    let displayName =
      variant.hasPrefix("现 ")
      ? String(variant.dropFirst("现 ".count))
      : variant
    return VStack(alignment: .leading, spacing: 4) {
      // Color.clear 撑出正方形画布，图 scaledToFill 铺满后被圆角裁切；
      // 直接在 Image 上加 aspectRatio 会和 scaledToFill 打架，这是稳定写法。
      Color.clear
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          if let imageFile, let image = ImageManager.shared.loadImage(fileName: imageFile) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            ZStack {
              MidsummerTheme.subtleFill
              Image(systemName: "photo")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(MidsummerTheme.secondaryText)
            }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("midsummer-variant-image-\(variant)")

      Text(displayName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MidsummerTheme.primaryText)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
      if imageFile == nil {
        Text("款式图待补充")
          .font(.system(size: 9))
          .foregroundStyle(MidsummerTheme.secondaryText)
      }
      if viewMode.isCreator || MidsummerStore.shared.isAdminUser {
        HStack(spacing: 8) {
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
            Image(systemName: imageFile == nil ? "photo.badge.plus" : "arrow.2.squarepath")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(MidsummerTheme.brandOrange)
          }
          .disabled(isUploadingItemImage)
          .accessibilityIdentifier("midsummer-variant-image-pick-\(variant)")

          if imageFile != nil {
            Button {
              Task { await deleteVariantImage(variant) }
            } label: {
              Image(systemName: "trash")
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
  }

  // MARK: 创作者视图 · 保存编辑（用户 2026-09-17）

  /// 名称 / 描述 / 主图改动落库：与款式图上传同一条 publish 链路，
  /// 保存后整页由 `refreshFromCloud()` 全量回读，用户视图立即看到新内容。
  private func saveEdits() async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
      let updated = MidsummerItemDTO(
        id: item.id,
        seriesID: item.seriesID,
        name: trimmedName.isEmpty ? item.name : trimmedName,
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
        coverImage: item.coverImage,
        galleryImageNames: item.galleryImageNames,
        itemURL: item.itemURL,
        sourceURL: item.sourceURL,
        note: editedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : editedNote,
        sizeChartImages: item.sizeChartImages,
        variantImageNames: workingVariantImages,
        specGroups: item.specGroups,
        skus: item.skus
      )
      // 主图替换：新图排在最前，其余图原位保留（publish 是整条重写）。
      var images: [UIImage] = []
      if let pickedCoverImage { images.append(pickedCoverImage) }
      images += loadImages(workingImageNames)

      let orderedKeys =
        variantKeys
        + workingVariantImages.keys.filter { !variantKeys.contains($0) }.sorted()
      let entries: [(name: String, image: UIImage)] = orderedKeys.compactMap { key in
        guard let fileName = workingVariantImages[key],
          let existing = ImageManager.shared.loadImage(fileName: fileName)
        else { return nil }
        return (key, existing)
      }

      _ = try await MidsummerCloudService.shared.publish(
        item: updated,
        images: images,
        sizeChartImage: nil,
        variantImages: entries
      )
      saveMessage = "已保存，其他用户刷新后可见。"
      isEditing = false
      await MidsummerStore.shared.refreshFromCloud()
      dismiss()
    } catch {
      saveMessage = "保存失败：\(error.localizedDescription)"
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

struct MidsummerDataNote: View {
  @ObservedObject var store: MidsummerStore

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
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.top, 18)
  }
}
