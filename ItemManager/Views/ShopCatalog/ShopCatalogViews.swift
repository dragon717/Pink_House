//
//  ShopCatalogViews.swift
//  ItemManager
//
//  「店家上新」浏览页（计划 §7-12 + 附录A 参考图2/3/4）：
//    · ShopCatalogBrowseView   —— 浏览根（独立 NavigationStack，时光馆 fullScreenCover 呈现）
//    · ShopCatalogEntryCard    —— 时光馆内「店家上新 · 最近上新 · 历年系列」入口卡（§8，参考图2 NEW 角标）
//    · ShopCatalogListView     —— 店家列表（§9：Logo / 名称 / 最近上新 / 系列数 / 别名搜索，参考图3 列表风格）
//    · ShopCatalogShopView     —— 店家主页（§10：当前上新 + [当前上新][2026][2025]…年份翻阅，参考图4）
//    · ShopCatalogSeriesView   —— 系列详情（§11：主视觉 + 分类筛选 + §12 多选加入衣橱）
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
    var onLegacyArchive: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .timeHall)
                    .ignoresSafeArea()
                ShopCatalogListView()
            }
            .navigationTitle("店家上新")
            .navigationBarTitleDisplayMode(.inline)
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
    /// nil = 「当前上新」；有值 = 按年份翻阅历年
    @State private var selectedYear: Int?

    private var shop: CatalogShop? { store.shop(id: shopID) }

    private var visibleSeries: [CatalogSeries] {
        if let selectedYear {
            return store.archiveSeries(inShop: shopID).filter { $0.year == selectedYear }
        }
        return store.currentSeries(inShop: shopID)
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
    }

    private var yearStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "当前上新", isSelected: selectedYear == nil) { selectedYear = nil }
                ForEach(store.years(inShop: shopID), id: \.self) { year in
                    chip(title: String(year), isSelected: selectedYear == year) { selectedYear = year }
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
                Text(selectedYear == nil ? "暂无进行中的上新" : "该年份暂无收录系列")
                    .font(.system(size: 14))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            VStack(spacing: 12) {
                ForEach(visibleSeries) { s in
                    NavigationLink {
                        ShopCatalogSeriesView(seriesID: s.id)
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

// MARK: - 系列详情（V1.2：合并主卡 = 系列对外唯一主链路）
//
//  旧版把系列下单品铺成 N 张独立卡片（单品与链接一一对应的分散结构）；
//  现在整个系列对外只保留一张合并大卡，点进即「点菜式选购页」
//  （ShopCatalogSeriesMenuView）：按品类列出全部单品、明码标价、各带商品照，
//  勾选合并到同一次加入操作；规格选择图文绑定（选中配色切换对应照片）。
//  单品完整资料（尺码表/销售历史等）经点菜页行内「>」进入商品详情保留可达。

struct ShopCatalogSeriesView: View {
    let seriesID: String

    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared
    @State private var showsMenu = false

    private var series: CatalogSeries? { store.series(id: seriesID) }
    private var products: [CatalogProduct] { store.products(inSeries: seriesID) }

    var body: some View {
        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                seriesMainCard
                    .padding(16)
                    .padding(.bottom, 80)
            }
        }
        .navigationTitle(series?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsMenu) {
            ShopCatalogSeriesMenuView(store: store, seriesID: seriesID)
                .presentationDetents([.large])
        }
    }

    // MARK: 合并大卡（系列主卡）

    private var seriesMainCard: some View {
        Button {
            showsMenu = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ShopCatalogAssetImage(reference: coverReference)
                    .aspectRatio(16 / 10, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 4) {
                            Image(systemName: "menucard")
                            Text("点菜选购".appLocalized)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(10)
                    }
                    .overlay(alignment: .topLeading) {
                        ForEach(Array(statusTags.enumerated()), id: \.offset) { index, text in
                            if index == 0 {
                                statusTag(text)
                                    .padding(10)
                            }
                        }
                    }

                Text(series?.name ?? "")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)

                HStack(spacing: 6) {
                    if let year = series?.year { Text(String(year)) }
                    if let season = series?.season, !season.isEmpty { Text("· \(season)") }
                    Text("· \(products.count) 个单品")
                    if !categoriesSummary.isEmpty { Text("· \(categoriesSummary)") }
                }
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)

                HStack(spacing: 8) {
                    Text(priceRangeText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                    ForEach(statusTags, id: \.self) { statusTag($0) }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .themeSkinSectionCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: 汇总口径

    /// 封面：系列主视觉优先，缺省回退首个单品首图
    private var coverReference: String? {
        if let cover = series?.cover, !cover.isEmpty {
            return store.asset(id: cover)?.originalURL ?? cover
        }
        guard let first = products.first?.images.first else { return nil }
        return store.asset(id: first)?.originalURL ?? first
    }

    private var categoriesSummary: String {
        let cats = Array(Set(products.map(\.category)))
        return cats.isEmpty ? "" : cats.joined(separator: "/")
    }

    /// 价格区间：现货价优先、缺省回退预约价；单值时只显示一个
    private var priceRangeText: String {
        let prices = products.compactMap { p -> Decimal? in
            let archive = store.priceArchive(forProduct: p.id)
            return archive.currentStockPrice ?? archive.historicalReservationPrice
        }
        guard let minP = prices.min() else { return "价格待补充" }
        if prices.count == 1 || minP == (prices.max() ?? minP) {
            return ShopCatalogFormat.price(minP)
        }
        return "\(ShopCatalogFormat.price(minP)) – \(ShopCatalogFormat.price(prices.max()!))"
    }

    /// 系列整体状态：预约中 > 现货中 > 即将开始（去重，最多三枚）
    private var statusTags: [String] {
        var tags: [String] = []
        for p in products {
            let events = store.saleEvents(forProduct: p.id)
            if events.contains(where: { store.windowStatus(of: $0) == .open && $0.type == .reservation }) {
                if !tags.contains("预约中") { tags.append("预约中") }
            }
            if events.contains(where: { store.windowStatus(of: $0) == .open && $0.type == .stock }) {
                if !tags.contains("现货中") { tags.append("现货中") }
            }
            if events.contains(where: { store.windowStatus(of: $0) == .upcoming }) {
                if !tags.contains("即将开始") { tags.append("即将开始") }
            }
        }
        return tags
    }

    private func statusTag(_ text: String) -> some View {
        Text(text.appLocalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(themeManager.accentTextColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(themeManager.accentTextColor.opacity(0.1)))
    }
}
