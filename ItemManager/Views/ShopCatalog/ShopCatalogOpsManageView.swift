//
//  ShopCatalogOpsManageView.swift
//  ItemManager
//
//  店家商品库 · 实体管理（重构方案 Phase 2，V1.1 §4.2）：
//    · 店家 / 系列 / 商品：编辑（id 不变）、归档（archivedAt）、引用保护删除
//    · 被用户心愿/尾款/衣橱引用 → 删除被拦截，仅可归档（ShopCatalogReferenceGuard）
//    · Bundle 种子实体不可物理删除（只读），仅可归档（同 id 替换生效）
//

import SwiftUI
import SwiftData
import UIKit

/// 实体类型分栏（2026-09-22 调整）：只保留 店家 / 系列 两栏。
/// 商品不再有顶层 Tab——商品的查看 / 新增 / 编辑 / 归档全部下移到
/// 系列详情页（ShopCatalogSeriesProductsView）内完成。
private enum ManageScope: String, CaseIterable, Identifiable {
    case shops
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shops: return "店家"
        case .series: return "系列"
        }
    }
}

struct ShopCatalogOpsManageView: View {
    @ObservedObject private var store = ShopCatalogStore.shared
    @Environment(\.modelContext) private var modelContext
    @State private var toast: String?
    @State private var actionError: String?
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var hudLetter: String?
    @State private var scope: ManageScope = .shops

    /// 修掉首尾空白后的搜索词
    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    // MARK: 搜索过滤

    private var filteredShops: [CatalogShop] {
        let all = store.shopsSortedByName()
        return all.filter {
            AZIndexGrouping.matches(name: $0.name, aliases: $0.aliases, query: trimmedQuery)
        }
    }

    private var filteredSeries: [CatalogSeries] {
        let all = store.seriesSortedByName()
        return all.filter { series in
            let shopName = store.shop(id: series.shopID)?.name ?? ""
            return AZIndexGrouping.matches(name: series.name,
                                           aliases: [shopName],
                                           query: trimmedQuery)
        }
    }

    // MARK: A-Z 分组（店家 / 系列共用同一套字典序）

    private var shopGroups: [(letter: String, items: [CatalogShop])] {
        AZIndexGrouping.groups(filteredShops) { $0.name }
    }

    private var seriesGroups: [(letter: String, items: [CatalogSeries])] {
        AZIndexGrouping.groups(filteredSeries) { $0.name }
    }

    /// 当前分栏的索引字母（与屏上分组一一对应 → 跳转无歧义）
    private var indexLetters: [String] {
        switch scope {
        case .shops: return shopGroups.map(\.letter)
        case .series: return seriesGroups.map(\.letter)
        }
    }

    private func totalCount(for scope: ManageScope) -> Int {
        switch scope {
        case .shops: return store.catalog?.shops.count ?? 0
        case .series: return store.catalog?.series.count ?? 0
        }
    }

    var body: some View {
        // 搜索栏 + 分栏都在 VStack 上层、List 之外 → 常驻固定，不随内容滚动
        VStack(spacing: 0) {
            AZPinnedSearchBar(text: $searchText,
                              focused: $searchFieldFocused,
                              placeholder: "搜索名称或别名")
            Picker("实体类型", selection: $scope) {
                ForEach(ManageScope.allCases) { item in
                    Text("\(item.title) \(totalCount(for: item))").tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                List {
                    listContent(for: scope)
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
                .overlay(alignment: .trailing) {
                    // 有搜索词时隐藏索引（符合系统搜索交互）
                    if trimmedQuery.isEmpty, !indexLetters.isEmpty {
                        AZIndexRail(letters: indexLetters,
                                    hudLetter: $hudLetter) { letter in
                            withAnimation(nil) {
                                proxy.scrollTo(letter, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            AZIndexHUD(letter: hudLetter)
        }
        .navigationTitle("实体管理")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 16)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        await MainActor.run { self.toast = nil }
                    }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .onAppear { store.loadFromBundleIfNeeded() }
    }

    // MARK: 列表内容（每栏都是 A-Z 分组 + 组内字典序）

    @ViewBuilder
    private func listContent(for scope: ManageScope) -> some View {
        switch scope {
        case .shops:
            if filteredShops.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(shopGroups, id: \.letter) { group in
                    Section {
                        ForEach(group.items) { shop in
                            ShopManageRow(
                                shop: shop,
                                store: store,
                                modelContext: modelContext,
                                toast: $toast,
                                actionError: $actionError
                            )
                        }
                    } header: {
                        Text(group.letter).id(group.letter)
                    }
                }
            }

        case .series:
            if filteredSeries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(seriesGroups, id: \.letter) { group in
                    Section {
                        ForEach(group.items) { series in
                            // 商品管理已下移：点系列进入系列详情页（商品查看/新增/编辑/归档）
                            NavigationLink {
                                ShopCatalogSeriesProductsView(
                                    series: series,
                                    store: store,
                                    toast: $toast,
                                    actionError: $actionError
                                )
                            } label: {
                                SeriesManageRow(
                                    series: series,
                                    store: store,
                                    modelContext: modelContext,
                                    toast: $toast,
                                    actionError: $actionError
                                )
                            }
                        }
                    } header: {
                        Text(group.letter).id(group.letter)
                    }
                }
            }
        }
    }
}

// MARK: - 系列详情（商品管理入口，2026-09-22 自顶层「商品」Tab 下移）

/// 单个系列的商品管理页：查看 / 新增 / 编辑 / 归档全部在此完成。
/// 交互与视觉沿用实体管理层同一套组件：固定搜索栏 + A-Z 分组 + 索引滑块 + 既有商品行。
private struct ShopCatalogSeriesProductsView: View {
    let series: CatalogSeries
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var hudLetter: String?
    @State private var showsAddProduct = false
    /// 展开查看各颜色子项的款式（V1.4 同款不同色归组）
    @State private var expandedStyleKeys: Set<String> = []

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// 该系列全部商品（含已归档——运营需要能看到并管理；行内已有「已归档」徽标）
    private var allProducts: [CatalogProduct] {
        (store.catalog?.products ?? []).filter { $0.seriesID == series.id }
    }

    private var filteredProducts: [CatalogProduct] {
        allProducts.filter {
            AZIndexGrouping.matches(name: $0.name, aliases: [$0.category], query: trimmedQuery)
        }
    }

    // MARK: 款式归组（V1.4 同款不同色合并为一条）

    /// 一条款式组 = 同品类 + 同款式名（显式 designName 优先，缺省按名称派生）的全部颜色商品
    private struct StyleGroup: Identifiable {
        let key: String
        let designName: String
        let products: [CatalogProduct]
        var id: String { key }
    }

    private var styleGroups: [StyleGroup] {
        var order: [String] = []
        var buckets: [String: [CatalogProduct]] = [:]
        for p in filteredProducts {
            let key = ShopCatalogSameDesignGrouper.designKey(of: p)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(p)
        }
        return order.compactMap { key in
            guard let list = buckets[key], let first = list.first else { return nil }
            return StyleGroup(key: key,
                              designName: ShopCatalogSameDesignGrouper.designName(of: first),
                              products: list)
        }
    }

    /// 款式组按款名首字母 A-Z 分组（沿用现有索引分组组件）
    private var styleLetterGroups: [(letter: String, items: [StyleGroup])] {
        AZIndexGrouping.groups(styleGroups) { $0.designName }
    }

    var body: some View {
        VStack(spacing: 0) {
            AZPinnedSearchBar(text: $searchText,
                              focused: $searchFieldFocused,
                              placeholder: "搜索商品名称或分类")
            ScrollViewReader { proxy in
                List {
                    if filteredProducts.isEmpty {
                        ContentUnavailableView(
                            trimmedQuery.isEmpty ? "暂无商品" : "未找到商品",
                            systemImage: "shippingbox",
                            description: Text(trimmedQuery.isEmpty
                                              ? "点右上角「＋」新增本系列商品"
                                              : "换个关键词试试")
                        )
                    } else {
                        ForEach(styleLetterGroups, id: \.letter) { letterGroup in
                            Section {
                                ForEach(letterGroup.items) { style in
                                    styleGroupRows(style)
                                }
                            } header: {
                                Text(letterGroup.letter).id(letterGroup.letter)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
                .overlay(alignment: .trailing) {
                    if trimmedQuery.isEmpty, !styleLetterGroups.isEmpty {
                        AZIndexRail(letters: styleLetterGroups.map(\.letter),
                                    hudLetter: $hudLetter) { letter in
                            withAnimation(nil) {
                                proxy.scrollTo(letter, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            AZIndexHUD(letter: hudLetter)
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddProduct = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增商品")
            }
        }
        .sheet(isPresented: $showsAddProduct) {
            ShopCatalogProductQuickAddSheet(series: series, toast: $toast, actionError: $actionError)
        }
    }

    // MARK: 款式组行（展开 = 各颜色子项，子项沿用既有 ProductManageRow 全部操作）

    @ViewBuilder
    private func styleGroupRows(_ style: StyleGroup) -> some View {
        let isExpanded = expandedStyleKeys.contains(style.key)
        Button {
            if isExpanded {
                expandedStyleKeys.remove(style.key)
            } else {
                expandedStyleKeys.insert(style.key)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(style.designName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if style.products.count > 1 {
                            Text("\(style.products.count) 色")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.pink))
                        }
                    }
                    Text(styleSummary(style))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)

        if isExpanded {
            ForEach(style.products) { product in
                ProductManageRow(
                    product: product,
                    store: store,
                    modelContext: modelContext,
                    toast: $toast,
                    actionError: $actionError
                )
            }
        }
    }

    /// 款式组摘要：分类 · N 色 · 价格区间（预约 / 现货分别取全组最低–最高）
    private func styleSummary(_ style: StyleGroup) -> String {
        var parts: [String] = []
        let categories = Set(style.products.map(\.category))
        if categories.count == 1, let category = categories.first {
            parts.append(category)
        }
        let archives = style.products.map { store.priceArchive(forProduct: $0.id) }
        let reservationPrices = archives.compactMap(\.historicalReservationPrice)
        if !reservationPrices.isEmpty {
            parts.append("预约 \(priceRangeText(reservationPrices))")
        }
        let stockPrices = archives.compactMap(\.currentStockPrice)
        if !stockPrices.isEmpty {
            parts.append("现货 \(priceRangeText(stockPrices))")
        }
        return parts.joined(separator: " · ")
    }

    private func priceRangeText(_ prices: [Decimal]) -> String {
        guard let min = prices.min(), let max = prices.max() else { return "—" }
        if min == max { return "¥\(NSDecimalNumber(decimal: min).stringValue)" }
        return "¥\(NSDecimalNumber(decimal: min).stringValue)–¥\(NSDecimalNumber(decimal: max).stringValue)"
    }
}

// MARK: - 系列内快速新增商品

/// 系列详情页「＋新增」：最小必填（名称 + 分类）直接建档；
/// 图片 / 规格 / 价格等资料创建后走行内菜单的编辑与深度编辑补全。
private struct ShopCatalogProductQuickAddSheet: View {
    let series: CatalogSeries
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.dismiss) private var dismiss

    private let categories = ShopCatalogStore.canonicalCategoryOrder
    @State private var name = ""
    @State private var category = "JSK"
    /// V1.4「同款不同色」：款式名可空（默认按名称自动识别）+ 颜色（可空，建配色规格）
    @State private var designNameText = ""
    @State private var colorText = ""

    /// 名称剥离颜色词后的默认款式（实时派生，作为占位提示与兜底值）
    private var derivedDesignName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "自动识别" : ShopCatalogSameDesignGrouper.baseName(for: trimmed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("新商品（归属：\(series.name)）") {
                    TextField("商品名称", text: $name)
                    TextField("款式（可空，默认「\(derivedDesignName)」）", text: $designNameText)
                    TextField("颜色（可空，如：红色）", text: $colorText)
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Text("同款不同色归组：同一款式的其他颜色再新增一条（填同名款式），列表会自动合并展示")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新增商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let explicitDesign = designNameText.trimmingCharacters(in: .whitespaces)
        let product = CatalogProduct(id: "prod-ops-\(UUID().uuidString.prefix(8))",
                                     shopID: series.shopID,
                                     seriesID: series.id,
                                     name: trimmed,
                                     category: category,
                                     designName: ShopCatalogSameDesignGrouper.resolveDesignName(
                                         explicit: explicitDesign.isEmpty ? nil : explicitDesign,
                                         name: trimmed))
        do {
            try ShopCatalogDraftStore.upsertEntity(product, keyPath: \.products)
            // 颜色非空时同步建一条配色规格（尺码留空，后续编辑补全）
            let color = colorText.trimmingCharacters(in: .whitespaces)
            if !color.isEmpty {
                let variant = CatalogProductVariant(id: "var-ops-\(UUID().uuidString.prefix(8))",
                                                    productID: product.id,
                                                    color: color,
                                                    size: nil)
                try ShopCatalogDraftStore.upsertEntity(variant, keyPath: \.variants)
            }
            toast = "已新增商品「\(trimmed)」，点行进入编辑补全资料"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - 店家行

private struct ShopManageRow: View {
    let shop: CatalogShop
    @ObservedObject var store: ShopCatalogStore
    let modelContext: ModelContext
    @Binding var toast: String?
    @Binding var actionError: String?

    @State private var showsEdit = false
    @State private var showsArchiveConfirm = false
    @State private var showsDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(shop.name).font(.system(size: 14, weight: .medium))
                    if shop.archivedAt != nil {
                        Text("已归档")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.brown))
                    }
                }
                Text("系列 \(store.series(inShop: shop.id).count) · 别名 \(shop.aliases.joined(separator: "、"))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("编辑（名称/别名/Logo/封面/简介）") {
                    showsEdit = true
                }
                if shop.archivedAt == nil {
                    Button("归档", role: .destructive) { showsArchiveConfirm = true }
                }
                Button("删除", role: .destructive) { showsDeleteConfirm = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsEdit) {
            ShopCatalogShopEditSheet(shop: shop, toast: $toast, actionError: $actionError)
        }
        .confirmationDialog("归档「\(shop.name)」？", isPresented: $showsArchiveConfirm, titleVisibility: .visible) {
            Button("归档（用户端隐藏，数据保留）", role: .destructive) {
                do {
                    try ShopCatalogDraftStore.archiveShop(shop)
                    toast = "已归档「\(shop.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除「\(shop.name)」？", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do {
                    try ShopCatalogDraftStore.deleteShop(shop, store: store, modelContext: modelContext)
                    toast = "已删除「\(shop.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 系列行

private struct SeriesManageRow: View {
    let series: CatalogSeries
    @ObservedObject var store: ShopCatalogStore
    let modelContext: ModelContext
    @Binding var toast: String?
    @Binding var actionError: String?

    @State private var showsEdit = false
    @State private var showsArchiveConfirm = false
    @State private var showsDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(series.name).font(.system(size: 14, weight: .medium))
                    if series.archivedAt != nil {
                        Text("已归档")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.brown))
                    }
                }
                Text("\(store.shop(id: series.shopID)?.name ?? "—") · \(series.year.map(String.init) ?? "—") \(series.season ?? "") · \(store.productCount(inSeries: series.id)) 件")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("编辑（名称/年份/季节/封面/简介）") {
                    showsEdit = true
                }
                if series.archivedAt == nil {
                    Button("归档", role: .destructive) { showsArchiveConfirm = true }
                }
                Button("删除", role: .destructive) { showsDeleteConfirm = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsEdit) {
            ShopCatalogSeriesEditSheet(series: series, toast: $toast, actionError: $actionError)
        }
        .confirmationDialog("归档「\(series.name)」？", isPresented: $showsArchiveConfirm, titleVisibility: .visible) {
            Button("归档（用户端隐藏，收藏保留）", role: .destructive) {
                do {
                    try ShopCatalogDraftStore.archiveSeries(series)
                    toast = "已归档「\(series.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除「\(series.name)」？", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do {
                    try ShopCatalogDraftStore.deleteSeries(series, store: store, modelContext: modelContext)
                    toast = "已删除「\(series.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 商品行

private struct ProductManageRow: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    let modelContext: ModelContext
    @Binding var toast: String?
    @Binding var actionError: String?

    @State private var showsEdit = false
    @State private var showsDeepEdit = false
    @State private var showsPriceCorrection = false
    @State private var showsSaleRecordAppend = false
    @State private var showsArchiveConfirm = false
    @State private var showsDeleteConfirm = false
    @State private var draftName = ""
    @State private var draftCategory = "其他"

    private var statusLine: String {
        let archive = store.priceArchive(forProduct: product.id)
        var parts: [String] = [product.category]
        if let r = archive.historicalReservationPrice { parts.append("预约 ¥\(r)") }
        if let s = archive.currentStockPrice { parts.append("现货 ¥\(s)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(product.name).font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if product.archivedAt != nil {
                        Text("已归档")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.brown))
                    }
                }
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("编辑基础（名称/分类）") {
                    draftName = product.name
                    draftCategory = product.category
                    showsEdit = true
                }
                Button("深度编辑（图片/配色尺码/尺码表）") {
                    showsDeepEdit = true
                }
                // 价格两条流程：入口分开、语义写清楚，避免与「深度编辑」里混淆
                Button("价格修正（覆盖当前价 · 不产生历史）") {
                    showsPriceCorrection = true
                }
                Button("追加销售记录（再贩 · 带批次时间）") {
                    showsSaleRecordAppend = true
                }
                if product.archivedAt == nil {
                    Button("归档", role: .destructive) { showsArchiveConfirm = true }
                }
                Button("删除", role: .destructive) { showsDeleteConfirm = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsDeepEdit) {
            ShopCatalogProductDeepEditView(product: product, store: store,
                                           toast: $toast, actionError: $actionError)
        }
        .sheet(isPresented: $showsPriceCorrection) {
            ShopCatalogPriceCorrectionSheet(product: product, store: store,
                                            toast: $toast, actionError: $actionError)
        }
        .sheet(isPresented: $showsSaleRecordAppend) {
            ShopCatalogSaleRecordAppendSheet(product: product, store: store,
                                             toast: $toast, actionError: $actionError)
        }
        .alert("编辑商品", isPresented: $showsEdit) {
            TextField("名称", text: $draftName)
            TextField("分类（JSK/OP/SK/Blouse/KC/小物/鞋/包/其他）", text: $draftCategory)
            Button("保存") {
                var updated = product
                updated.name = draftName.trimmingCharacters(in: .whitespaces)
                updated.category = draftCategory.trimmingCharacters(in: .whitespaces)
                do {
                    try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.products)
                    toast = "已更新商品「\(updated.name)」，id 不变，用户引用不受影响"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("归档「\(product.name)」？", isPresented: $showsArchiveConfirm, titleVisibility: .visible) {
            Button("归档（用户端隐藏，收藏保留）", role: .destructive) {
                do {
                    try ShopCatalogDraftStore.archiveProduct(product)
                    toast = "已归档「\(product.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("删除「\(product.name)」？", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do {
                    try ShopCatalogDraftStore.deleteProduct(product, store: store, modelContext: modelContext)
                    toast = "已删除「\(product.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - 店家编辑（V1.1 §4.2 Shop：名称/别名/Logo/封面/简介，id 不变）

private struct ShopCatalogShopEditSheet: View {
    let shop: CatalogShop
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var aliases = ""
    @State private var logo = ""
    @State private var cover = ""
    @State private var descriptionText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("名称", text: $name)
                    TextField("别名（逗号分隔）", text: $aliases)
                }
                Section("视觉与简介") {
                    TextField("Logo（Bundle 文件名/URL，可空）", text: $logo)
                    ShopCatalogImagePickerButton(mode: .replace, text: $logo, label: "添加 Logo 图片")
                    TextField("封面（Bundle 文件名/URL，可空）", text: $cover)
                    ShopCatalogImagePickerButton(mode: .replace, text: $cover, label: "添加封面图片")
                    TextField("简介", text: $descriptionText)
                }
            }
            .navigationTitle("编辑店家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear {
                name = shop.name
                aliases = shop.aliases.joined(separator: "，")
                logo = shop.logo ?? ""
                cover = shop.cover ?? ""
                descriptionText = shop.description ?? ""
            }
        }
    }

    private func save() {
        var updated = shop
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.aliases = aliases
            .components(separatedBy: CharacterSet(charactersIn: "，,、"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        updated.logo = trimmedOrNil(logo)
        updated.cover = trimmedOrNil(cover)
        updated.description = trimmedOrNil(descriptionText)
        do {
            try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.shops)
            toast = "已更新店家「\(updated.name)」，下属系列/商品同步生效"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

// MARK: - 系列编辑（V1.1 §4.2 Series：名称/年份/季节/封面/简介，id 不变）

private struct ShopCatalogSeriesEditSheet: View {
    let series: CatalogSeries
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var yearText = ""
    @State private var season = ""
    @State private var cover = ""
    @State private var descriptionText = ""

    // 预约价格表（系列共用，2026-09-22）：独立于单品尺码表的上传入口
    // V1.5：手动录入区常驻（解析成功预填、解析失败可手填），交互与尺码表一致
    @State private var priceChartImageText = ""
    @State private var priceChartColumnsText = ""
    @State private var priceChartRowsText = ""
    @State private var priceChartUnitText = ""
    @State private var priceChartParseError: String?
    @State private var priceChartParsing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("名称", text: $name)
                    TextField("年份（如 2026）", text: $yearText)
                        .keyboardType(.numberPad)
                    TextField("季节（如 冬）", text: $season)
                }
                Section("视觉与简介") {
                    TextField("封面（Bundle 文件名/URL，可空）", text: $cover)
                    ShopCatalogImagePickerButton(mode: .replace, text: $cover, label: "添加封面图片")
                    TextField("简介", text: $descriptionText)
                }
                priceChartSection
            }
            .navigationTitle("编辑系列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear {
                name = series.name
                yearText = series.year.map(String.init) ?? ""
                season = series.season ?? ""
                cover = series.cover ?? ""
                descriptionText = series.description ?? ""
                if let chart = series.priceChart {
                    priceChartImageText = chart.sourceImage ?? ""
                    priceChartColumnsText = chart.columns.joined(separator: ",")
                    priceChartRowsText = chart.rows.map { row in
                        "\(row.label):" + row.values.map { $0 ?? "" }.joined(separator: ",")
                    }.joined(separator: "\n")
                    priceChartUnitText = chart.unit ?? ""
                }
            }
        }
    }

    // MARK: 预约价格表（系列共用；上传后 OCR 自动解析，无需人工二次录入）

    private var priceChartSection: some View {
        Section {
            if priceChartParsing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在解析价格表图片…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            ShopCatalogImagePickerButton(mode: .replace, text: $priceChartImageText,
                                         label: "上传价格表图片（自动解析）")
            if let error = priceChartParseError {
                // 解析失败：明确提示；下方手填区常驻，可直接手动录入
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
            // 手动录入区（与尺码表同交互）：列名 + 行文本 + 单位；
            // 解析成功时预填识别结果，失败 / 未上传时可直接手填，保存即生效
            TextField("列名（逗号分隔，如：款式,预约价,定金,尾款）", text: $priceChartColumnsText)
                .font(.system(size: 13))
            TextEditor(text: $priceChartRowsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("价格表行：每行「标签:值,值,…」与列一一对应（如「大蝴蝶结背心裙:318,91,227」），可手动录入或修正识别结果后保存")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("单位（可空，如 元）", text: $priceChartUnitText)
                .font(.system(size: 13))
            if !priceChartImageText.isEmpty {
                Button("清除价格表", role: .destructive) {
                    priceChartImageText = ""
                    priceChartColumnsText = ""
                    priceChartRowsText = ""
                    priceChartUnitText = ""
                    priceChartParseError = nil
                }
                .font(.system(size: 13))
            }
        } header: {
            Text("预约价格表（整个系列共用）")
        } footer: {
            Text("价格表归属系列而非单品：在此上传一次，该系列全部商品详情页自动展示；无需在单品编辑页上传。解析失败时可直接在下方手动录入，与尺码表同格式。")
        }
        .onChange(of: priceChartImageText) { oldValue, newValue in
            guard newValue != oldValue else { return }
            guard !newValue.isEmpty else {
                priceChartParseError = nil
                return
            }
            parsePriceChart(reference: newValue)
        }
    }

    /// 上传图片 → OCR 自动解析；失败给出明确提示并保留原图，手填区可直接修正
    private func parsePriceChart(reference: String) {
        priceChartParsing = true
        priceChartParseError = nil
        Task {
            defer { priceChartParsing = false }
            guard let url = ShopCatalogImageResolver.url(for: reference) else {
                priceChartParseError = CatalogChartParserError.imageUnavailable.localizedDescription
                return
            }
            let image: UIImage?
            if url.isFileURL {
                image = UIImage(contentsOfFile: url.path)
            } else if let data = try? Data(contentsOf: url) {
                image = UIImage(data: data)
            } else {
                image = nil
            }
            guard let image else {
                priceChartParseError = CatalogChartParserError.imageUnavailable.localizedDescription
                return
            }
            do {
                let table = try await CatalogChartParser.parse(image: image)
                priceChartColumnsText = table.columns.joined(separator: ",")
                priceChartRowsText = table.rows.map { row in
                    "\(row.label):" + row.values.map { $0 ?? "" }.joined(separator: ",")
                }.joined(separator: "\n")
            } catch {
                priceChartParseError = error.localizedDescription
            }
        }
    }

    private func save() {
        var updated = series
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.year = Int(yearText.trimmingCharacters(in: .whitespaces))
        let seasonTrimmed = season.trimmingCharacters(in: .whitespaces)
        updated.season = seasonTrimmed.isEmpty ? nil : seasonTrimmed
        updated.cover = trimmedOrNil(cover)
        updated.description = trimmedOrNil(descriptionText)
        updated.priceChart = makePriceChart()
        do {
            try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.series)
            toast = "已更新系列「\(updated.name)」，价格表对全系列商品生效"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 由表单内容组装系列价格表：图片与结构化内容二者留其一即可；
    /// 解析失败时保留原图（详情页给出「未解析成功」提示）。
    /// 共享解析口径：首列若为行标签列名（尺码/项目/款式…）剔除，值尾冒号清洗。
    private func makePriceChart() -> CatalogPriceChart? {
        let sourceImage = trimmedOrNil(priceChartImageText)
        let parsedChart = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(priceChartColumnsText),
            rows: CatalogManualChartText.parseRows(priceChartRowsText))
        let columns = parsedChart.columns
        let rows = parsedChart.rows
        guard sourceImage != nil || !columns.isEmpty || !rows.isEmpty else { return nil }
        var chart = series.priceChart ?? CatalogPriceChart(
            id: "pricechart-\(series.id.prefix(8))", seriesID: series.id)
        chart.sourceImage = sourceImage
        chart.columns = columns
        chart.rows = rows
        chart.unit = trimmedOrNil(priceChartUnitText)
        return chart
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
