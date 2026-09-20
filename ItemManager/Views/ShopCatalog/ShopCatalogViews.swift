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

// MARK: - 系列详情（计划 §11-12，参考图4 卡片风格）

struct ShopCatalogSeriesView: View {
    let seriesID: String

    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared
    @State private var selectedCategory: String?
    /// 系列页多选加入衣橱（计划 §12，P0）：选择后进入确认页（参考图6）
    @State private var isSelecting = false
    @State private var selectedProductIDs: Set<String> = []
    @State private var showsMerge = false
    @State private var mergeToast: String?

    private var series: CatalogSeries? { store.series(id: seriesID) }

    private var visibleProducts: [CatalogProduct] {
        store.products(inSeries: seriesID, category: selectedCategory)
    }

    var body: some View {
        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    categoryStrip
                    productGrid
                }
                .padding(16)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(series?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "取消" : "多选") {
                    isSelecting.toggle()
                    if !isSelecting { selectedProductIDs = [] }
                }
                .font(.system(size: 14, weight: .medium))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { multiSelectBar }
        }
        .sheet(isPresented: $showsMerge) {
            NavigationStack {
                ShopCatalogWardrobeMergeView(selectedProductIDs: selectedProductIDs.sorted()) { count in
                    mergeToast = "已加入少女衣橱（\(count) 条记录）"
                }
            }
            .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) {
            if let mergeToast {
                Text(mergeToast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 60)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        await MainActor.run { self.mergeToast = nil }
                    }
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(store.categories(inSeries: seriesID), id: \.self) { c in
                    chip(title: c, isSelected: selectedCategory == c) { selectedCategory = c }
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
                .background(Capsule().fill(isSelected ? Color.pink : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var productGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(visibleProducts) { p in
                if isSelecting {
                    selectableProductCard(p)
                } else {
                    NavigationLink {
                        ShopCatalogProductView(productID: p.id)
                    } label: {
                        productCard(p)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 多选模式卡片：点按切换勾选
    private func selectableProductCard(_ p: CatalogProduct) -> some View {
        Button {
            if selectedProductIDs.contains(p.id) {
                selectedProductIDs.remove(p.id)
            } else {
                selectedProductIDs.insert(p.id)
            }
        } label: {
            productCard(p)
                .overlay(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(selectedProductIDs.contains(p.id) ? Color.pink : Color.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        if selectedProductIDs.contains(p.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(8)
                }
        }
        .buttonStyle(.plain)
    }

    /// 底部操作条（计划 §12：已选择 N 件 → [加入少女衣橱] → 确认页）
    private var multiSelectBar: some View {
        HStack(spacing: 12) {
            Text("已选择 \(selectedProductIDs.count) 件")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(themeManager.primaryTextColor)
            Spacer()
            Button {
                guard !selectedProductIDs.isEmpty else { return }
                showsMerge = true
            } label: {
                Text("加入少女衣橱")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(selectedProductIDs.isEmpty ? Color.gray.opacity(0.5) : Color.pink))
            }
            .disabled(selectedProductIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func productCard(_ p: CatalogProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShopCatalogAssetImage(reference: firstImageReference(of: p))
                .aspectRatio(3 / 4, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(p.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(themeManager.primaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            priceLine(p)
        }
        .padding(8)
        .themeSkinSectionCard(cornerRadius: 14)
    }

    private func priceLine(_ p: CatalogProduct) -> some View {
        let archive = store.priceArchive(forProduct: p.id)
        return HStack(spacing: 6) {
            if let stock = archive.currentStockPrice {
                Text(ShopCatalogFormat.price(stock))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
            } else if let r = archive.historicalReservationPrice {
                Text(ShopCatalogFormat.price(r))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(themeManager.accentTextColor)
            } else {
                Text("价格待补充")
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            statusTag(p)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func statusTag(_ p: CatalogProduct) -> some View {
        let events = store.saleEvents(forProduct: p.id)
        if let active = events.first(where: { store.windowStatus(of: $0) == .open }) {
            tag(text: active.type == .reservation ? "预约中" : "现货中")
        } else if let upcoming = events.first(where: { store.windowStatus(of: $0) == .upcoming }) {
            tag(text: "即将开始")
        }
    }

    private func tag(text: String) -> some View {
        Text(text.appLocalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(themeManager.accentTextColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(themeManager.accentTextColor.opacity(0.1)))
    }

    private func firstImageReference(of p: CatalogProduct) -> String? {
        guard let first = p.images.first else { return nil }
        return store.asset(id: first)?.originalURL ?? first
    }
}
