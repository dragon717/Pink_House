//
//  ShopCatalogViews.swift
//  ItemManager
//
//  「店铺时光册」浏览页：
//    · ShopCatalogBrowseView   —— 浏览根（独立 NavigationStack，时光馆 Tab 首屏）
//    · ShopCatalogListView     —— 店家列表（§9：Logo / 名称 / 最近上新 / 系列数 / 别名搜索，参考图3 列表风格）
//    · ShopCatalogShopView     —— 左侧年份、顶部系列名称筛选；
//      系列卡点击直达「点菜式选购页」ShopCatalogSeriesMenuView，原合并大卡中转页已删除）
//
//  视觉：约束 1「不改变现有 UI」——全部沿用 themeManager 令牌 + themeSkinSectionCard
//  + LiquidBackground(.timeHall)，不自创配色。
//

import SwiftUI
import SwiftData

// MARK: - 格式化工具

enum ShopCatalogFormat {
    static func month(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.MM"
        return f.string(from: date)
    }

    static func price(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return "¥\(NSDecimalNumber(decimal: value).stringValue)"
    }
}

// MARK: - 浏览根

/// 时光馆首屏「店铺时光册」（直接作为底部 Tab 根视图）。
struct ShopCatalogBrowseView: View {
    @ObservedObject private var store = ShopCatalogStore.shared
    /// 尾款阶段同步需要显式传入 context（内部不默认拿生产容器）
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isRoutePageActive) private var isRoutePageActive
    @Environment(\.scenePhase) private var scenePhase
    /// 开售提醒深链：通知点击 → TabNavigationManager → 本栈压入商品详情
    @ObservedObject private var tabNav = TabNavigationManager.shared

    private var showsDeepLinkProduct: Binding<Bool> {
        Binding(
            get: { tabNav.pendingShopCatalogProductID != nil },
            set: { if !$0 { tabNav.pendingShopCatalogProductID = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .timeHall)
                    .ignoresSafeArea()
                ShopCatalogListView(onRefresh: refreshCatalog)
            }
            .navigationTitle("店铺时光册")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: showsDeepLinkProduct) {
                if let productID = tabNav.pendingShopCatalogProductID {
                    ShopCatalogProductView(productID: productID)
                }
            }
        }
        .onAppear {
            store.loadFromBundleIfNeeded()
        }
        .task(id: isRoutePageActive && scenePhase == .active) {
            // 系统 TabView 会缓存页面；明确随路由再次进入和回到前台检查。
            // 近期检查由服务合并，后台及隐藏页面不从这里发起请求。
            guard isRoutePageActive, scenePhase == .active, !ShopCatalogAutoRefresh.isTestHost else { return }
            await ShopCatalogCloudSyncService.shared.syncIfNeeded()
            // 2026-09-25 需求二/三：目录更新（或本地已是最新）后，把「尾款中」
            // 系列的尾款窗口同步进用户衣橱条目（幂等；大致时间估算成固定具体日期）。
            ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: .shared, modelContext: modelContext)
        }
    }

    private func refreshCatalog() async {
        await ShopCatalogCloudSyncService.shared.syncIfNeeded(force: true)
        ShopCatalogWardrobeBalanceSync.syncIfNeeded(store: store, modelContext: modelContext)
        switch ShopCatalogCloudSyncService.shared.state {
        case .failed(let message): ToastManager.shared.showError(message)
        case .nothingPublished: ToastManager.shared.show(message: "线上暂未发布店家商品")
        default: break
        }
    }
}

// MARK: - 店家列表（计划 §9，参考图3）

struct ShopCatalogListView: View {
    var onRefresh: () async -> Void = {
        await ShopCatalogCloudSyncService.shared.syncIfNeeded(force: true)
    }
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared
    @State private var keyword = ""

    private var shops: [CatalogShop] {
        store.searchShops(keyword: keyword)
    }

    var body: some View {
        listContent
    }

    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if case let .failed(message) = store.status {
                    ContentUnavailableView("店家商品库暂不可用", systemImage: "shippingbox",
                                           description: Text(message))
                }
                searchBar
                if shops.isEmpty {
                    emptyState
                } else {
                    ForEach(shops) { shop in
                        NavigationLink {
                            ShopCatalogShopView(shopID: shop.id)
                        } label: {
                            shopRow(shop)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable { await onRefresh() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(themeManager.secondaryTextColor)
            TextField("搜索店家名称".appLocalized, text: $keyword)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shopRow(_ shop: CatalogShop) -> some View {
        HStack(spacing: 12) {
            ShopCatalogAssetImage(reference: shop.logo ?? shop.cover)
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(initialBadge(shop))

            VStack(alignment: .leading, spacing: 5) {
                Text(shop.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
                    .lineLimit(2)
                Text("最近上新：\(ShopCatalogFormat.month(store.latestActivityDate(shopID: shop.id)))".appLocalized)
                    .font(.system(size: 12))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeManager.tertiaryTextColor)
        }
        .padding(12)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    /// Logo 缺图时以首字母占位
    @ViewBuilder
    private func initialBadge(_ shop: CatalogShop) -> some View {
        if (shop.logo ?? shop.cover) == nil {
            ZStack {
                Circle().fill(themeManager.accentTextColor.opacity(0.12))
                Text(String(shop.name.prefix(1)))
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(themeManager.accentTextColor)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(themeManager.tertiaryTextColor)
            Text("没有找到对应店家".appLocalized)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }
}

// MARK: - 店铺时光册：年份侧栏 + 系列名称筛选

struct ShopCatalogShopView: View {
    let shopID: String

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store: ShopCatalogStore
    @State private var selection = ShopCatalogAlbumSelection()
    /// 系列卡直达「点菜式选购页」（原合并大卡中转页已删除）
    @State private var menuSeries: CatalogSeries?

    init(shopID: String, store: ShopCatalogStore? = nil, initialSelection: ShopCatalogAlbumSelection = .init()) {
        self.shopID = shopID
        _store = ObservedObject(wrappedValue: store ?? .shared)
        _selection = State(initialValue: initialSelection)
    }

    private var shop: CatalogShop? { store.shop(id: shopID) }

    private var allSeries: [CatalogSeries] { store.series(inShop: shopID) }
    private var yearSeries: [CatalogSeries] { selection.seriesInYear(allSeries) }
    private var visibleSeries: [CatalogSeries] { selection.visibleSeries(allSeries) }
    private var surface: Color { themeManager.cardSurfaceColor(for: colorScheme) }
    private var palette: AdaptivePaletteV2 {
        themeManager.getPaletteForContainer(containerBackground: .solid(color: surface), colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 12) {
                yearRail
                VStack(spacing: 12) {
                    seriesStrip
                    ScrollView(.vertical, showsIndicators: false) {
                        seriesSection
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                    }
                    .id(selection.year.id + "/" + (selection.seriesID ?? "all"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 12).padding(.top, 12)
        }
        .navigationTitle(shop?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $menuSeries) { series in
            ShopCatalogSeriesMenuView(store: store, seriesID: series.id)
                .presentationDetents([.large])
        }
        .onChange(of: allSeries) { _, series in selection.reconcile(with: series) }
        .onAppear { selection.reconcile(with: allSeries) }
        .accessibilityIdentifier("shop.album")
    }

    private var yearRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(ShopCatalogAlbumSelection.years(in: allSeries)) { year in
                    chip(title: year.title.appLocalized, isSelected: selection.year == year) {
                        selection.selectYear(year)
                    }
                    .accessibilityIdentifier("shop.album.year.\(year.id)")
                }
            }
        }
        .frame(width: 78)
        .accessibilityLabel("年份".appLocalized)
    }

    private var seriesStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "全部".appLocalized, isSelected: selection.seriesID == nil) { selection.seriesID = nil }
                        .id("all").accessibilityIdentifier("shop.album.series.all")
                    ForEach(yearSeries) { series in
                        chip(title: series.name, isSelected: selection.seriesID == series.id) { selection.seriesID = series.id }
                            .id(series.id).accessibilityIdentifier("shop.album.series.\(series.id)")
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: selection.year) { _, _ in proxy.scrollTo("all", anchor: .leading) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("系列".appLocalized)
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? palette.primary : palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(surface)
                )
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? palette.accent : palette.divider, lineWidth: isSelected ? 1.5 : 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var seriesSection: some View {
        if visibleSeries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(palette.tertiary)
                Text("该年份暂无收录系列".appLocalized)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleSeries) { s in
                    Button {
                        menuSeries = s
                    } label: {
                        seriesCard(s)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shop.album.open.\(s.id)")
                }
            }
        }
    }

    /// 系列卡（参考图4：左图 + 系列名 + 「2026.10 上新 · N 件商品」）
    private func seriesCard(_ s: CatalogSeries) -> some View {
        HStack(spacing: 12) {
            ShopCatalogAssetImage(reference: s.cover)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(s.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                VStack(alignment: .leading, spacing: 3) {
                    if let latest = store.latestSeriesActivity(s) {
                        Text("\(ShopCatalogFormat.month(latest)) 上新".appLocalized)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                    }
                    Text("\(store.productCount(inSeries: s.id)) 件商品".appLocalized)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(5).background(surface, in: RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeManager.tertiaryTextColor)
        }
        .padding(10)
        .themeSkinSectionCard(cornerRadius: 16)
    }
}

// MARK: - 商品标题（内外一致口径，2026-09-23）
//
//  同一个商品在详情页、点菜页、商品管理的标题必须是**同一句话**：款式名。
//  颜色不参与标题，只在「· N 色」标注与独立的颜色元素（配色行 / 颜色 chips /
//  轮播胶囊 / 颜色标签）里出现。取值一律来自 `ShopCatalogProductTitle`
//  （`ShopCatalogTitlePresentation.swift`），三处共用这一份渲染，不许各自拼
//  `Text(product.name)` / `Text("· N 色")`。

/// 商品标题标签：款式名 +（同款多色时）「· N 色」标注
struct ShopCatalogProductTitleLabel: View {
    let title: ShopCatalogProductTitle
    var font: Font = .system(size: 14, weight: .medium)
    var textColor: Color = .primary
    var annotationColor: Color = .secondary
    var lineLimit: Int? = 1

    var body: some View {
        HStack(spacing: 4) {
            Text(title.text)
                .font(font)
                .foregroundStyle(textColor)
                .lineLimit(lineLimit)
            if let colorCountText = title.colorCountText {
                Text(colorCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(annotationColor)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 颜色标签

/// 单个颜色的小胶囊（颜色「单独呈现」时的统一形态）
struct ShopCatalogColorChip: View {
    let label: String
    var isSelected: Bool = false
    var accent: Color = .pink
    /// 未选中时的文字色：主题皮肤页面传 `themeManager.secondaryTextColor`，
    /// 普通列表用默认 `.secondary`（不依赖环境注入）。
    var unselectedColor: Color = .secondary

    var body: some View {
        Text(label.appLocalized)
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .white : unselectedColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? accent : Color.secondary.opacity(0.12)))
    }
}

// MARK: - 系列直达点菜式选购（V1.2 路由收口）
//
//  路由链路（2026-09-21 优化）：店家主页系列卡 → 直接弹出 ShopCatalogSeriesMenuView。
//  原「系列合并大卡」中转页（ShopCatalogSeriesView）已删除：它只承担「点一下进点菜页」
//  的转发职责，属于冗余层级；单品完整资料（尺码表/销售历史等）仍经点菜页行内「>」
//  进入商品详情保留可达。
