//
//  ShopCatalogViews.swift
//  ItemManager
//
//  「店家上新」浏览页（计划 §7-12 + 附录A 参考图2/3/4）：
//    · ShopCatalogBrowseView   —— 浏览根（独立 NavigationStack，时光馆 fullScreenCover 呈现）
//    · ShopCatalogEntryCard    —— 时光馆内「店家上新 · 最近上新 · 历年系列」入口卡（§8，参考图2 NEW 角标）
//    · ShopCatalogListView     —— 店家列表（§9：Logo / 名称 / 最近上新 / 系列数 / 别名搜索，参考图3 列表风格）
//    · ShopCatalogShopView     —— 店家主页（§10：当前上新 + [当前上新][2026][2025]…年份翻阅；
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

/// 时光馆首屏「店家上新」（Phase 1：直接作为底部 Tab 根视图，也兼容 fullScreenCover）。
/// `onLegacyArchive` 非 nil 时，左上角按钮变为「馆藏档案」次级入口（过渡期只读旧馆）；
/// 否则保持原「返回时光馆」关闭按钮（fullScreenCover 场景）。
struct ShopCatalogBrowseView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ShopCatalogStore.shared
    /// 开售提醒深链：通知点击 → TabNavigationManager → 本栈压入商品详情
    @ObservedObject private var tabNav = TabNavigationManager.shared
    var onLegacyArchive: (() -> Void)? = nil

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
                ShopCatalogListView()
            }
            .navigationTitle("店家上新")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: showsDeepLinkProduct) {
                if let productID = tabNav.pendingShopCatalogProductID {
                    ShopCatalogProductView(productID: productID)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onLegacyArchive {
                        Button(action: onLegacyArchive) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("馆藏档案")
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("返回时光馆")
                    }
                }
            }
        }
        .onAppear {
            store.loadFromBundleIfNeeded()
        }
    }
}

// MARK: - 时光馆「店家上新」入口卡片（计划 §8，参考图2：NEW 角标）

/// 展示在时光馆品牌列表顶部：店家上新 · 最近上新 · 历年系列
struct ShopCatalogEntryCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(themeManager.accentTextColor.opacity(0.12))
                    Image(systemName: "bag.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(themeManager.accentTextColor)
                }
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    Text("NEW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.pink))
                        .offset(x: 6, y: -4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("店家上新")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text("最近上新 · 历年系列")
                        .font(.system(size: 12))
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(themeManager.tertiaryTextColor)
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .themeSkinSectionCard(cornerRadius: 16)
    }
}

// MARK: - 店家列表（计划 §9，参考图3）

struct ShopCatalogListView: View {
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared
    @State private var keyword = ""

    private var shops: [CatalogShop] {
        store.searchShops(keyword: keyword)
    }

    var body: some View {
        Group {
            if case let .failed(message) = store.status {
                ContentUnavailableView("店家商品库暂不可用", systemImage: "shippingbox",
                                       description: Text(message))
            } else {
                listContent
            }
        }
    }

    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
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

// MARK: - 店家主页（计划 §10，参考图4：[当前上新][2026][2025]…）

struct ShopCatalogShopView: View {
    let shopID: String

    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared
    /// 店主页系列筛选：当前上新 / 未标年份 / 具体年份
    enum YearFilter: Equatable {
        case current
        case noYear
        case year(Int)
    }
    @State private var yearFilter: YearFilter = .current
    /// 系列卡直达「点菜式选购页」（原合并大卡中转页已删除）
    @State private var menuSeries: CatalogSeries?

    private var shop: CatalogShop? { store.shop(id: shopID) }

    private var visibleSeries: [CatalogSeries] {
        switch yearFilter {
        case .current:
            return store.currentSeries(inShop: shopID)
        case .noYear:
            return store.archiveSeries(inShop: shopID).filter { $0.year == nil }
        case .year(let year):
            return store.archiveSeries(inShop: shopID).filter { $0.year == year }
        }
    }

    /// 无年份的历年系列（运营发布时年份选填），存在则显示「未标年份」chip 兜底
    private var hasNoYearArchiveSeries: Bool {
        store.archiveSeries(inShop: shopID).contains { $0.year == nil }
    }

    var body: some View {
        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    yearStrip
                    seriesSection
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(shop?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $menuSeries) { series in
            ShopCatalogSeriesMenuView(store: store, seriesID: series.id)
                .presentationDetents([.large])
        }
    }

    private var yearStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "当前上新", isSelected: yearFilter == .current) { yearFilter = .current }
                ForEach(store.years(inShop: shopID), id: \.self) { year in
                    chip(title: String(year), isSelected: yearFilter == .year(year)) { yearFilter = .year(year) }
                }
                if hasNoYearArchiveSeries {
                    chip(title: "未标年份", isSelected: yearFilter == .noYear) { yearFilter = .noYear }
                }
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.appLocalized)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : themeManager.secondaryTextColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.pink : Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var seriesSection: some View {
        if visibleSeries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(themeManager.tertiaryTextColor)
                Text(yearFilter == .current ? "暂无进行中的上新" : "该年份暂无收录系列")
                    .font(.system(size: 14))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            VStack(spacing: 12) {
                ForEach(visibleSeries) { s in
                    Button {
                        menuSeries = s
                    } label: {
                        seriesCard(s)
                    }
                    .buttonStyle(.plain)
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
                    .foregroundStyle(themeManager.primaryTextColor)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let latest = store.latestSeriesActivity(s) {
                        Text("\(ShopCatalogFormat.month(latest)) 上新".appLocalized)
                            .font(.system(size: 12))
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                    Text("· \(store.productCount(inSeries: s.id)) 件商品".appLocalized)
                        .font(.system(size: 12))
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
            }
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
