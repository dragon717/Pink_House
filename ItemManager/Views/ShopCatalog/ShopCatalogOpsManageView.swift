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
    /// 款式公共资料编辑目标（SPU 级：尺码表 / 面料 / 款式描述）
    @State private var styleProfileTarget: CatalogProduct?

    // MARK: 批量删除（2026-09-23：多选 + 二次确认）

    /// 是否处于批量删除选择模式
    @State private var isSelectingForDelete = false
    /// 已勾选的商品 id
    @State private var selectedProductIDs: Set<String> = []
    /// 待二次确认的删除目标（第一次确认后暂存，二次确认通过才真正执行）
    @State private var pendingDeleteProductIDs: Set<String> = []
    /// 是否展示「第一次确认」弹窗
    @State private var showsProductDeleteConfirm = false
    /// 只读预检结果：第一次确认弹窗里展示的真实影响范围
    @State private var productDeletePreview: CatalogProductDeletePreview?
    /// 是否展示「二次确认」弹窗
    @State private var showsFinalDeleteConfirm = false
    /// 被拦截的商品（展示原因，条目与选择都保留以便处理后重试）
    @State private var blockedProductDeletions: [CatalogProductDeleteBlock] = []

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
        .toolbar { toolbarContent }
        .sheet(isPresented: $showsAddProduct) {
            // 录入端重构（2026-09-23）：入口改为「款式优先」的两步表单 ——
            // 第 1 步建款式填公共资料（尺码表 / 面料 / 款式描述），第 2 步加颜色只传图 + 勾尺码。
            // 旧的「最小建档（名称+分类）」表单已移除：它不落款式尺码表，
            // 正是「粉色没有尺码表」那类问题的来源。
            ShopCatalogStyleEntrySheet(series: series,
                                       draftStore: ShopCatalogDraftStore.shared,
                                       store: store,
                                       toast: $toast,
                                       actionError: $actionError)
        }
        .sheet(item: $styleProfileTarget) { target in
            ShopCatalogStyleProfileEditor(representative: target,
                                          store: store,
                                          toast: $toast,
                                          actionError: $actionError)
        }
        // 二次确认第一步：说清真实影响范围（含会被跳过的条目与原因）
        .confirmationDialog(productDeleteConfirmTitle,
                            isPresented: $showsProductDeleteConfirm,
                            titleVisibility: .visible) {
            Button("继续") { showsFinalDeleteConfirm = true }
            Button("取消", role: .cancel) { clearPendingProductDelete() }
        } message: {
            Text(productDeleteImpactText)
        }
        // 二次确认第二步：显式再确认一次，删除不可撤销
        .alert("二次确认：删除后无法恢复", isPresented: $showsFinalDeleteConfirm) {
            Button("确认删除", role: .destructive) { performProductDelete() }
            Button("取消", role: .cancel) { clearPendingProductDelete() }
        } message: {
            Text(productDeleteFinalConfirmText)
        }
        // 被拦截的商品：逐条说明原因，条目与选择都保留以便处理后重试
        .alert("部分商品无法删除", isPresented: showsBlockedDeletionsBinding) {
            Button("好", role: .cancel) { blockedProductDeletions = [] }
        } message: {
            Text(blockedProductDeletionsText)
        }
    }

    // MARK: 批量删除 · 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelectingForDelete {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { exitProductSelection() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(selectedProductIDs.count == filteredProducts.count ? "取消全选" : "全选") {
                    toggleSelectAllProducts()
                }
                .disabled(filteredProducts.isEmpty)
                Button("删除(\(selectedProductIDs.count))") {
                    beginProductDelete(selectedProductIDs)
                }
                .foregroundStyle(selectedProductIDs.isEmpty ? Color.secondary : Color.red)
                .disabled(selectedProductIDs.isEmpty)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("选择") { enterProductSelection() }
                    .disabled(allProducts.isEmpty)
                Button {
                    showsAddProduct = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增商品")
            }
        }
    }

    // MARK: 批量删除 · 选择与两步确认

    private var showsBlockedDeletionsBinding: Binding<Bool> {
        Binding(get: { !blockedProductDeletions.isEmpty },
                set: { if !$0 { blockedProductDeletions = [] } })
    }

    private func enterProductSelection() {
        withAnimation { isSelectingForDelete = true }
        // 选择模式先展开全部款式组：否则未展开的颜色子项不可见、无法勾选，
        // 「全选」也会与屏幕上看到的行数对不上。
        expandedStyleKeys = Set(styleGroups.map(\.key))
    }

    private func exitProductSelection() {
        withAnimation { isSelectingForDelete = false }
        selectedProductIDs = []
        clearPendingProductDelete()
    }

    private func toggleProductSelection(_ id: String) {
        if selectedProductIDs.contains(id) {
            selectedProductIDs.remove(id)
        } else {
            selectedProductIDs.insert(id)
        }
    }

    private func toggleSelectAllProducts() {
        let visible = Set(filteredProducts.map(\.id))
        selectedProductIDs = (selectedProductIDs == visible) ? [] : visible
    }

    /// 第一次确认：先跑只读预检，把「会删几件 / 几件会被跳过及原因」说成实话。
    /// 预检与真正执行调同一个决策函数，所以弹窗数字与执行结果不会不一致。
    private func beginProductDelete(_ ids: Set<String>) {
        let products = allProducts.filter { ids.contains($0.id) }
        guard !products.isEmpty else { return }
        do {
            productDeletePreview = try ShopCatalogDraftStore.previewProductDeletion(
                products, store: store, modelContext: modelContext)
            pendingDeleteProductIDs = ids
            showsProductDeleteConfirm = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func clearPendingProductDelete() {
        pendingDeleteProductIDs = []
        productDeletePreview = nil
    }

    private var productDeleteConfirmTitle: String {
        let count = productDeletePreview?.deletableCount ?? 0
        return count <= 1 ? "删除 1 件商品？" : "删除 \(count) 件商品？"
    }

    private var productDeleteImpactText: String {
        guard let preview = productDeletePreview else { return "" }
        var lines: [String] = []
        if preview.deletableCount == 0 {
            lines.append("所选商品都不满足物理删除条件，本次不会有任何删除。")
        } else {
            lines.append("将物理删除 \(preview.deletableCount) 件：\(namePreview(preview.deletableNames))。")
        }
        lines.append("影响范围：连带删除其配色尺码与尺码表；销售历史按硬约束保留，不受影响。")
        if preview.blockedCount > 0 {
            let details = preview.blocked
                .map { "「\($0.name)」\($0.reason.message)" }
                .joined(separator: "\n")
            lines.append("另有 \(preview.blockedCount) 件会被跳过：\n\(details)")
        }
        return lines.joined(separator: "\n\n")
    }

    private var productDeleteFinalConfirmText: String {
        // 预检已被清空时回退到待删集合大小，保证文案不会退化成「删除 0 件」
        let count = productDeletePreview?.deletableCount ?? pendingDeleteProductIDs.count
        return "即将物理删除 \(count) 件商品。删除后无法恢复，也无法从随版本内置的种子档案中找回。确认继续？"
    }

    private func namePreview(_ names: [String]) -> String {
        let head = names.prefix(5).joined(separator: "、")
        return names.count > 5 ? "\(head) 等共 \(names.count) 件" : head
    }

    private var blockedProductDeletionsText: String {
        blockedProductDeletions
            .map { "「\($0.name)」\($0.reason.message)" }
            .joined(separator: "\n\n")
    }

    /// 二次确认通过后执行：删除成功的从选择里移除；被拦截的**保留条目与选择**并弹窗说明
    /// （处理后可用同样的选择重试）；落盘失败时磁盘未变化，走通用「操作失败」弹窗。
    private func performProductDelete() {
        let targets = allProducts.filter { pendingDeleteProductIDs.contains($0.id) }
        do {
            let result = try ShopCatalogDraftStore.deleteProducts(
                targets, store: store, modelContext: modelContext)
            clearPendingProductDelete()
            guard !result.deletedIDs.isEmpty else {
                blockedProductDeletions = result.blocked
                return
            }
            toast = result.blocked.isEmpty
                ? "已删除 \(result.deletedIDs.count) 件商品"
                : "已删除 \(result.deletedIDs.count) 件商品，\(result.blocked.count) 件被跳过"
            selectedProductIDs.subtract(result.deletedIDs)
            if !result.blocked.isEmpty {
                blockedProductDeletions = result.blocked
            } else if selectedProductIDs.isEmpty {
                exitProductSelection()
            }
        } catch {
            clearPendingProductDelete()
            actionError = error.localizedDescription
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
                        // 标题 = 款式名 + 同款颜色数（与商品详情页 / 点菜页卡片同一口径，
                        // 2026-09-23「内外标题一致」）：这里原来用粉色胶囊写「N 色」，
                        // 与其它两处样式不一致，现在共用同一份标题渲染。
                        ShopCatalogProductTitleLabel(
                            title: ShopCatalogTitleResolver.title(
                                designName: style.designName,
                                colorCount: style.products.count),
                            annotationColor: .secondary,
                            lineLimit: 1)
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
            // 款式级公共资料入口（SPU 层）：尺码表 / 面料 / 款式描述。
            // 放在颜色子项**之前**，与「公共属性在上、颜色差异属性在下」的层级一致；
            // 保存对整款全部颜色生效，所以它不属于任何一个颜色行。
            if !isSelectingForDelete, let representative = style.products.first {
                Button {
                    styleProfileTarget = representative
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 13))
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("款式公共资料")
                                .font(.system(size: 13, weight: .medium))
                            Text(stylePublicSummary(style))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("catalog-style-public-info-\(style.key)")
            }
            ForEach(style.products) { product in
                if isSelectingForDelete {
                    ProductSelectionRow(
                        product: product,
                        store: store,
                        isSelected: selectedProductIDs.contains(product.id),
                        onToggle: { toggleProductSelection(product.id) }
                    )
                } else {
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
    }

    /// 批量删除选择模式下的商品行：整行可点、左侧勾选圈。
    /// 行内只读展示「分类 · 价格」，避免选择态下误触其它操作入口。
    private struct ProductSelectionRow: View {
        let product: CatalogProduct
        @ObservedObject var store: ShopCatalogStore
        let isSelected: Bool
        let onToggle: () -> Void

        private var statusLine: String {
            let archive = store.priceArchive(forProduct: product.id)
            var parts: [String] = [product.category]
            if let r = archive.historicalReservationPrice { parts.append("预约 ¥\(r)") }
            if let s = archive.currentStockPrice { parts.append("现货 ¥\(s)") }
            return parts.joined(separator: " · ")
        }

        /// 颜色标注（统一口径）：显式规格色优先 → 名称里的颜色词 → 无则不给标签
        private var productColorLabel: String? {
            ShopCatalogColorPresentation.label(explicitColors: store.colors(forProduct: product.id),
                                               name: product.name)
        }

        var body: some View {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.pink : Color.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            // 标题 = 款式名（与商品详情页 / 点菜页同一口径）；
                            // 颜色是紧随其后的独立标签 —— 同款各颜色行只差这一个标签。
                            ShopCatalogProductTitleLabel(
                                title: ShopCatalogTitleResolver.title(product: product, siblings: []))
                            if let label = productColorLabel {
                                ShopCatalogColorChip(label: label)
                            }
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("catalog-product-select-\(product.id)")
            .accessibilityLabel("\(isSelected ? "已选中" : "未选中") \(product.name)")
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

    /// 款式公共资料摘要（说清「录了什么、覆盖几个颜色」）
    private func stylePublicSummary(_ style: StyleGroup) -> String {
        guard let first = style.products.first else { return "" }
        var parts: [String] = []
        if let fabric = store.fabric(forProduct: first.id) { parts.append("面料 \(fabric)") }
        if store.styleDescription(forProduct: first.id) != nil { parts.append("有描述") }
        let sizes = store.sizeRun(forProduct: first.id)
        parts.append(sizes.isEmpty ? "尺码表未录入" : "尺码 \(sizes.joined(separator: "/"))")
        parts.append("覆盖 \(style.products.count) 色")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 系列内快速商品录入（已下线，2026-09-23 录入端重构）
//
//  原 `ShopCatalogProductQuickAddSheet`（只填「名称 + 分类」就建档）已删除。
//  它不携带款式尺码表，颜色建出来天然没有尺码维度 —— 正是「同款某色没有尺码表」
//  这类问题的来源之一。建档入口统一收口到 `ShopCatalogStyleEntrySheet`
//  （第 1 步建款式填公共资料 → 第 2 步加颜色只传图 + 勾尺码）。

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

    /// 生效中的发售阶段（需求二 §二.3：包含「过了预约结束时间」的自动流转结果）。
    /// nil = 该系列未声明发售阶段（旧数据）→ 不显示标签，前端沿用档期推导。
    private var effectiveSalePhase: CatalogSeriesSalePhase? {
        CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: Date())
    }

    private func salePhaseBadgeTint(_ phase: CatalogSeriesSalePhase) -> Color {
        switch phase {
        case .reservationActive: return Color(hex: "C2185B")
        case .reservationEnded: return Color(hex: "7A5A54")
        case .inStock: return Color(hex: "2E7D6F")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(series.name).font(.system(size: 14, weight: .medium))
                    // 生效中的发售阶段（需求二 §二.3）：这里是**自动流转之后**的结果，
                    // 所以「预约中 + 已过期」的系列会直接显示「预约已结束」——
                    // 运营不必等任何后台任务，也不会看到存储值与展示值不一致。
                    if let phase = effectiveSalePhase {
                        Text(phase.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(salePhaseBadgeTint(phase)))
                    }
                    if series.archivedAt != nil {
                        Text("已归档")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.brown))
                    }
                }
                Text("\(store.shop(id: series.shopID)?.name ?? "—") · \(series.yearMonthText ?? "—") \(series.season ?? "") · \(store.productCount(inSeries: series.id)) 件")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("编辑（名称/年月/季节/封面/简介/发售阶段）") {
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

    /// 颜色标注（统一口径）：显式规格色优先 → 名称里的颜色词 → 无则不给标签
    private var productColorLabel: String? {
        ShopCatalogColorPresentation.label(explicitColors: store.colors(forProduct: product.id),
                                           name: product.name)
    }

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
                    // 标题 = 款式名（与商品详情页 / 点菜页同一口径）；
                    // 颜色是紧随其后的独立标签 —— 同款各颜色行只差这一个标签。
                    ShopCatalogProductTitleLabel(
                        title: ShopCatalogTitleResolver.title(product: product, siblings: []))
                    if let label = productColorLabel {
                        ShopCatalogColorChip(label: label)
                    }
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
    // 年月（2026-09-24 需求）：原「年份」升级，支持 "2026-10" / "2026年10月"，
    // 纯年份（"2026"）仍有效——存量系列回填后直接保存不能被校验拦下。
    @State private var yearMonthText = ""
    @State private var yearMonthError: String?
    @State private var season = ""
    @State private var cover = ""
    @State private var descriptionText = ""

    // 预约价格表（系列共用，2026-09-22）：独立于单品尺码表的上传入口。
    // 2026-09-23 需求一：**移除「上传价格表图片（自动识别）」与失败红字常驻提示**，
    //   价格表统一走「粘贴文本录入（推荐，最准）」+ 列名/行文本/单位手动输入区。
    //
    //   `priceChartImageText` 必须保留：它承载**既有**系列的 `sourceImage`，
    //   由 `onAppear` 回填、`makePriceChart()` 原样写回。删掉这个 state 会让
    //   「打开编辑系列 → 保存」把用户已上传的价格表原图静默抹掉。
    @State private var priceChartImageText = ""
    @State private var priceChartColumnsText = ""
    @State private var priceChartRowsText = ""
    @State private var priceChartUnitText = ""

    // 发售阶段（2026-09-23 需求二）：系列层面的「预约中 / 预约已结束 / 现货」声明 + 预约结束时间。
    // nil = 未声明（旧数据）→ 商品详情页沿用销售记录推导，与改动前完全一致。
    @State private var salePhase: CatalogSeriesSalePhase?
    @State private var reservationEndAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("名称", text: $name)
                    // 不用数字键盘：要允许输入「-」与「年/月」
                    TextField("年月（如 2026-10 或 2026年10月）", text: $yearMonthText)
                    if let yearMonthError {
                        Text(yearMonthError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    TextField("季节（如 冬）", text: $season)
                }
                salePhaseSection
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
                yearMonthText = series.yearMonthText ?? ""
                yearMonthError = nil
                season = series.season ?? ""
                cover = series.cover ?? ""
                descriptionText = series.description ?? ""
                salePhase = series.salePhase
                reservationEndAt = series.reservationEndAt ?? Date()
                if let chart = series.priceChart {
                    // 多图优先：sourceImages 是 2026-09-24 起的完整口径；
                    // 旧数据只有 sourceImage，按原值回填，保存时归一化为单元素列表
                    if let images = chart.sourceImages, !images.isEmpty {
                        priceChartImageText = images.joined(separator: "\n")
                    } else {
                        priceChartImageText = chart.sourceImage ?? ""
                    }
                    priceChartColumnsText = chart.columns.joined(separator: ",")
                    priceChartRowsText = chart.rows.map { row in
                        "\(row.label):" + row.values.map { $0 ?? "" }.joined(separator: ",")
                    }.joined(separator: "\n")
                    priceChartUnitText = chart.unit ?? ""
                }
            }
        }
    }

    // MARK: 发售阶段（2026-09-23 需求二）

    /// 需求 §二 的四条口径：
    ///   1. 基础信息处新增「发售阶段」状态字段（预约中 / 预约已结束 / 现货）；
    ///   2. 选「预约中」必须给出「预约结束时间」（DatePicker 常驻，必然有值）；
    ///      选「预约已结束 / 现货」时**不显示**该输入框；
    ///   3. 过了结束时间自动流转为「预约已结束」——由
    ///      `CatalogSeriesSalePhaseResolver.effectivePhase` 读取时判定（见该类型的注释：
    ///      不把运营声明改写掉，避免定时任务与声明互相覆盖）；
    ///   4. **数据保留**：这里只动阶段与时间两个字段，价格数据（预约价 / 定金 / 尾款 / 现货价）
    ///      一个都不碰、不清空、不隐藏；结束时间已过时下方只给提示，不拦保存。
    @ViewBuilder
    private var salePhaseSection: some View {
        Section {
            Picker("发售阶段", selection: $salePhase) {
                Text("未设置（沿用销售记录）").tag(Optional<CatalogSeriesSalePhase>.none)
                ForEach(CatalogSeriesSalePhase.allCases) { phase in
                    Text(phase.displayName).tag(Optional(phase))
                }
            }
            if salePhase == .reservationActive {
                DatePicker("预约结束时间",
                           selection: $reservationEndAt,
                           displayedComponents: [.date, .hourAndMinute])
                if CatalogSeriesSalePhaseResolver.hasAutoFlowed(
                    declared: salePhase, reservationEndAt: reservationEndAt, now: Date()
                ) {
                    Text("该时间已过，保存后本系列的生效状态会显示为「预约已结束」（价格数据保持不变）；若确实已结束，建议直接把发售阶段改为「预约已结束」。")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("发售阶段")
        } footer: {
            Text(salePhaseFooter)
        }
    }

    private var salePhaseFooter: String {
        switch salePhase {
        case .none:
            return "未设置时，商品详情页按销售记录（预约 / 现货档期）自动判断，与以往行为一致。"
        case .reservationActive:
            return "预约中：到「预约结束时间」后自动流转为「预约已结束」。无论哪个阶段，预约价 / 定金 / 尾款 / 现货价都会完整保留，不会清空或隐藏。"
        case .reservationEnded:
            return "预约已结束：前端价格档案照常展示原预约价；加购默认引导全款入橱，「定金 + 尾款」仍可在「其他记账方式」里记录。"
        case .inStock:
            return "现货：加购直接按现货价计入衣橱，不走定金 / 尾款。"
        }
    }

    // MARK: 预约价格表（整个系列共用）
    //
    //  2026-09-23 需求一之后只剩两条口径：
    //    1. 「粘贴文本录入（推荐，最准）」是唯一快捷入口；
    //    2. 列名 / 行文本 / 单位手动输入区保留，粘贴与手填共用同一套解析口径。
    //
    //  已移除（用户反馈：图片识别频繁报错且红字常驻霸屏）：
    //    `ShopCatalogImagePickerButton`（上传价格表图片）、识别进度行、
    //    「上次识别失败，未写入任何内容…」红字常驻块、失败 `alert`，
    //    以及只为它们服务的 `parsePriceChart` / `failPriceChartParse` / 三个 @State。
    //  **既有原图没有被丢弃**：`series.priceChart.sourceImage` 仍由 onAppear 回填、
    //    `makePriceChart()` 原样写回，只是不再提供新的上传入口。

    private var priceChartSection: some View {
        Section {
            // 2026-09-24 需求：恢复价格表图片上传入口，且支持一次多选。
            // 引用以「local:文件名」按行追加进 priceChartImageText，落库时拆行写
            // sourceImages（首图同步写 sourceImage，单一展示口径继续成立）。
            ShopCatalogImagePickerButton(mode: .append,
                                         text: $priceChartImageText,
                                         label: "上传价格表图片（可多选）")
            ShopCatalogChartPasteButton(kind: .priceChart,
                                        columnsText: $priceChartColumnsText,
                                        rowsText: $priceChartRowsText)
            // 手动录入区（与尺码表同交互）：列名 + 行文本 + 单位
            TextField("列名（逗号分隔，如：款式,预约价,定金,尾款）", text: $priceChartColumnsText)
                .font(.system(size: 13))
            TextEditor(text: $priceChartRowsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("价格表行：每行「标签:值,值,…」与列一一对应（如「大蝴蝶结背心裙:318,91,227」）；可在「粘贴文本录入」里整段贴入，或在此手动修正后保存")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("单位（可空，如 元）", text: $priceChartUnitText)
                .font(.system(size: 13))
            if !priceChartImageText.isEmpty || !priceChartColumnsText.isEmpty || !priceChartRowsText.isEmpty {
                Button("清除价格表", role: .destructive) {
                    priceChartImageText = ""
                    priceChartColumnsText = ""
                    priceChartRowsText = ""
                    priceChartUnitText = ""
                }
                .font(.system(size: 13))
            }
        } header: {
            Text("预约价格表（整个系列共用）")
        } footer: {
            Text("价格表归属系列而非单品：在此录入一次，该系列全部商品详情页自动展示；无需在单品编辑页上传。用「粘贴文本录入」把整段表格文本贴进来最省事，也可在下方手动修正后保存。")
        }
    }

    private func save() {
        // 年月校验（2026-09-24 需求）：空 = 清除；"2026-10" / "2026年10月" / 纯年份均有效；
        // 非法输入**不落库**，红字提示留在输入框下方，等用户改对再保存。
        if let errorText = CatalogYearMonthText.validationErrorText(for: yearMonthText) {
            yearMonthError = errorText
            return
        }
        yearMonthError = nil
        let parsedYearMonth = CatalogYearMonthText.parse(yearMonthText)
        var updated = series
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.year = parsedYearMonth?.year
        updated.month = parsedYearMonth?.month
        let seasonTrimmed = season.trimmingCharacters(in: .whitespaces)
        updated.season = seasonTrimmed.isEmpty ? nil : seasonTrimmed
        updated.cover = trimmedOrNil(cover)
        updated.description = trimmedOrNil(descriptionText)
        // 发售阶段（需求二）：只写「阶段」与「预约结束时间」两个字段。
        //   · 切到非「预约中」阶段**不清除**已录入的结束时间——那是「预约什么时候结束的」
        //     这条事实本身，清掉就再也查不回来了（表单只是把它隐藏，不是删除）。
        //   · **绝不触碰价格数据**：预约价 / 定金 / 尾款 / 现货价由价格表与销售记录负责，
        //     本页一个字段都不写（需求 §二.4 数据保留原则）。
        updated.salePhase = salePhase
        if salePhase == .reservationActive {
            updated.reservationEndAt = reservationEndAt
        }
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
    ///
    /// 多图（2026-09-24 需求）：priceChartImageText 按行拆为引用列表写 sourceImages；
    /// sourceImage 同步写首图——既有的单图展示/门禁口径（ShopCatalogChartPresentation）
    /// 继续以 sourceImage 为唯一入口，不被多图改动牵连。
    private func makePriceChart() -> CatalogPriceChart? {
        let imageReferences = CatalogPriceChartImageText.references(fromText: priceChartImageText)
        let sourceImage = imageReferences.first
        let parsedChart = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(priceChartColumnsText),
            rows: CatalogManualChartText.parseRows(priceChartRowsText))
        let columns = parsedChart.columns
        let rows = parsedChart.rows
        guard sourceImage != nil || !columns.isEmpty || !rows.isEmpty else { return nil }
        var chart = series.priceChart ?? CatalogPriceChart(
            id: "pricechart-\(series.id.prefix(8))", seriesID: series.id)
        chart.sourceImages = imageReferences.isEmpty ? nil : imageReferences
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
