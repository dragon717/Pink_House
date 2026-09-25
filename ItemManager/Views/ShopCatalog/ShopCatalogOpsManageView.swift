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
import Combine

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

    /// 正在编辑的系列（**统一挂在页面级**，而不是挂在 `List` 的行上）。
    /// 行是惰性 + 可复用的，把 `.sheet` 绑在行上会在切后台 / 相册选图 / 切应用返回时
    /// 把编辑页连同用户已填内容一起重建（2026-09-24 状态丢失根源修复）。
    @State private var editingSeries: CatalogSeries?

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
                // 底部悬浮 Dock 避让：本页在 tab 内容层内 push，最后一行会被 Dock 盖住（2026-09-24）。
                .avoidingBottomDock()
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
        .sheet(item: $editingSeries) { series in
            ShopCatalogSeriesEditSheet(series: series, toast: $toast, actionError: $actionError)
        }
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
                                    actionError: $actionError,
                                    onEdit: { editingSeries = series }
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
/// 交互与视觉沿用实体管理层同一套组件：固定搜索栏 + 按类型（分类）分组展示（2026-09-24
/// 需求：替代原「款名首字母 A-Z 分组」，分区顺序 = 分类候选固定序，组内款式归组不变）。
private struct ShopCatalogSeriesProductsView: View {
    let series: CatalogSeries
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var showsAddProduct = false
    /// 展开查看各颜色子项的款式（V1.4 同款不同色归组）
    @State private var expandedStyleKeys: Set<String> = []
    /// 款式公共资料编辑目标（SPU 级：尺码表 / 面料 / 款式描述）
    @State private var styleProfileTarget: CatalogProduct?

    // MARK: 改名（2026-09-24：款式级，一次改整款）

    /// 改名目标。**挂在页面级、不挂在列表行上**：行视图是惰性 + 可复用的，
    /// 列表一重排（滚动 / 切后台 / 跳系统相册返回）就会重建，挂在行上的弹窗
    /// 连同它的 `@State` 一起归零 —— 名称输入到一半就会丢。
    /// `styleProfileTarget` 早就是页面级，这里保持一致。
    @State private var renameTarget: CatalogProduct?
    @State private var showsRenameProduct = false
    @State private var renameNameDraft = ""
    @State private var renameCategoryDraft = "其他"

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

    // MARK: 商品行模态（2026-09-24 需求十四：整组从 List 行视图上移到页面级）

    /// 行的「弹出表单」目标（深度编辑 / 价格修正 / 追加销售记录）
    @State private var productSheet: ProductRowSheet?
    /// 行的「危险操作确认」目标（归档 / 删除）
    @State private var productConfirm: ProductRowConfirm?

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
        let category: String
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
                              category: first.category,
                              products: list)
        }
    }

    /// 按类型（分类）分组 + 统一排序（2026-09-24 需求：替代原「款名首字母 A-Z」分组）：
    ///   · 分区顺序 = `categoryCandidates` 固定品类序（JSK / OP / SK / … / 自定义 / 其他）；
    ///   · 词表之外的未知分类（历史数据遗留）排在固定序之后，按名称排序；
    ///   · 组内保持款式归组与出现顺序，搜索过滤后分组随之收缩。
    private var styleCategoryGroups: [(category: String, items: [StyleGroup])] {
        var buckets: [String: [StyleGroup]] = [:]
        for group in styleGroups {
            buckets[group.category, default: []].append(group)
        }
        let known = ShopCatalogStore.categoryCandidates
        var ordered: [(category: String, items: [StyleGroup])] = []
        for category in known where buckets[category] != nil {
            ordered.append((category, buckets[category]!))
        }
        let knownSet = Set(known)
        let unknown = buckets.keys.filter { !knownSet.contains($0) }.sorted()
        for category in unknown {
            ordered.append((category, buckets[category] ?? []))
        }
        return ordered
    }

    // MARK: 改名 · 预览与执行（2026-09-24）

    /// 改名计划：弹窗的预览文案与「保存」**共用同一份**计算结果
    /// （`ShopCatalogProductRename.plan` 是唯一口径，界面不许另算一套）。
    private var renamePlan: ShopCatalogProductRename.Plan? {
        guard let target = renameTarget else { return nil }
        return ShopCatalogProductRename.plan(product: target,
                                             newName: renameNameDraft,
                                             newCategory: renameCategoryDraft,
                                             among: allProducts,
                                             profiles: store.catalog?.styleProfiles ?? [])
    }

    /// 弹窗 message：改名前先让用户**看见**款式名会变成什么、影响几个颜色。
    /// 用户截图里的困惑正是「改完什么都没变」，而真实规则是
    /// 「各处标题只显示款式名（不含颜色词）」—— 这件事必须提前可见，不许静默。
    private var renamePreviewText: String {
        guard let plan = renamePlan else { return "" }
        return ShopCatalogProductRename.previewText(plan, typedName: renameNameDraft) ?? ""
    }

    private func beginRename(_ product: CatalogProduct) {
        renameTarget = product
        renameNameDraft = product.name
        renameCategoryDraft = product.category
        showsRenameProduct = true
    }

    /// 保存改名：走款式级唯一入口，然后**如实回报**影响范围（整款色数 / 衣橱心愿快照条数）。
    private func performRename() {
        guard let target = renameTarget else { return }
        let typedName = renameNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typedName.isEmpty else {
            actionError = "商品名称不能为空"
            return
        }
        do {
            let plan = try ShopCatalogDraftStore.renameProduct(productID: target.id,
                                                              newName: typedName,
                                                              newCategory: renameCategoryDraft)
            var message = plan.changesDesignName
                ? "已把款式名改为「\(plan.designNameAfter)」（原「\(plan.designNameBefore)」）"
                : "款式名未变（仍是「\(plan.designNameAfter)」）"
            if plan.changesCategory { message += "，品类改为「\(plan.categoryAfter)」" }
            if plan.siblingCount > 0 {
                message += "；同款 \(plan.totalColorCount) 个颜色（含其余 \(plan.siblingCount) 色）一并更新"
            }
            // 衣橱 / 心愿记录的名字是加入时的快照，改名不跟着改 —— 但不许静默
            let referenced = (try? ShopCatalogReferenceGuard.referencedRecordCount(
                Set(plan.products.map(\.id)), modelContext: modelContext)) ?? 0
            if let note = ShopCatalogProductRename.referenceNote(referencedRecordCount: referenced) {
                message += note
            }
            toast = message
            renameTarget = nil
        } catch { actionError = error.localizedDescription }
    }

    // MARK: 商品行模态 · 呈现与执行（2026-09-24 需求十四）

    /// 归档 / 删除确认框的标题 —— 内容随目标变，所以不能写死在 `.confirmationDialog` 上
    private var productConfirmTitle: String {
        guard let target = productConfirm else { return "" }
        switch target {
        case .archive(let product): return "归档「\(product.name)」？"
        case .delete(let product): return "删除「\(product.name)」？"
        }
    }

    /// 「有目标 = 展示」的推导绑定：与 `showsBlockedDeletionsBinding` 同一写法，
    /// 避免为两个确认框再各加一个 Bool `@State`（两个状态彼此不同步是这类 bug 的常见来源）
    private var productConfirmBinding: Binding<Bool> {
        Binding(get: { productConfirm != nil },
                set: { if !$0 { productConfirm = nil } })
    }

    private func performArchive(_ product: CatalogProduct) {
        do {
            try ShopCatalogDraftStore.archiveProduct(product)
            toast = "已归档「\(product.name)」"
        } catch { actionError = error.localizedDescription }
    }

    private func performProductDelete(_ product: CatalogProduct) {
        do {
            let preserved = try ShopCatalogDraftStore.deleteProduct(product, store: store, modelContext: modelContext)
            // 2026-09-25 需求一：删除不影响用户数据，但必须如实说清保留了多少条
            toast = preserved > 0
                ? "已删除「\(product.name)」；\(preserved) 条衣橱/心愿记录按加入时快照保留"
                : "已删除「\(product.name)」"
        } catch { actionError = error.localizedDescription }
    }

    var body: some View {
        VStack(spacing: 0) {
            AZPinnedSearchBar(text: $searchText,
                              focused: $searchFieldFocused,
                              placeholder: "搜索商品名称或分类")
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
                    ForEach(styleCategoryGroups, id: \.category) { group in
                        Section {
                            ForEach(group.items) { style in
                                styleGroupRows(style)
                            }
                        } header: {
                            // 分区标题 = 分类名 + 组数（2026-09-24：按类型归类展示）
                            Text("\(group.category) · \(group.items.count) 款")
                                .id(group.category)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            // 底部悬浮 Dock 避让：截图标注的「毛绒拉夫领针织内搭」被 Dock 盖住即此页（2026-09-24）。
            .avoidingBottomDock()
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
        // 改名（2026-09-24）：**页面级**弹窗，不挂在 `ProductManageRow` 上。
        // 「名称」继续是完整 SKU 名（可含颜色词），款式名由它派生 —— 与录入端
        // 「draft.name = 颜色 + 款式名」同一套口径；message 让用户先看见结果。
        .alert("编辑商品", isPresented: $showsRenameProduct) {
            TextField("名称", text: $renameNameDraft)
            TextField("分类（JSK/OP/SK/Blouse/KC/小物/鞋/包/其他）", text: $renameCategoryDraft)
            Button("保存") { performRename() }
            Button("取消", role: .cancel) { renameTarget = nil }
        } message: {
            Text(renamePreviewText)
        }
        // 商品行的三个表单 + 两个危险操作确认：**整组挂在页面级**。
        // 按 09-24 需求十四的红线，`.sheet` / `.confirmationDialog` 一律不许挂在
        // `ForEach`/`List` 的行视图上 —— 行是惰性 + 可复用的，列表一重排
        // （滚动 / 切后台 / 跳系统相册返回）就会重建，挂在行上的模态连同它的
        // `@State` 一起归零（深度编辑页正好带相册选图入口，是这条红线最初的踩坑场景）。
        .sheet(item: $productSheet) { target in
            switch target {
            case .deepEdit(let product):
                ShopCatalogProductDeepEditView(product: product, store: store,
                                               toast: $toast, actionError: $actionError)
            case .priceCorrection(let product):
                ShopCatalogPriceCorrectionSheet(product: product, store: store,
                                                toast: $toast, actionError: $actionError)
            case .saleRecordAppend(let product):
                ShopCatalogSaleRecordAppendSheet(product: product, store: store,
                                                 toast: $toast, actionError: $actionError)
            }
        }
        .confirmationDialog(productConfirmTitle,
                            isPresented: productConfirmBinding,
                            titleVisibility: .visible,
                            presenting: productConfirm) { target in
            switch target {
            case .archive(let product):
                Button("归档（用户端隐藏，收藏保留）", role: .destructive) {
                    performArchive(product)
                }
            case .delete(let product):
                Button("删除", role: .destructive) {
                    performProductDelete(product)
                }
            }
            Button("取消", role: .cancel) {}
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
        // 2026-09-25 需求一：被引用商品可删，用户记录按加入时快照保留（如实说清）
        if preview.preservedRecordCount > 0 {
            lines.append("已加入衣橱/心愿的 \(preview.preservedRecordCount) 条记录按加入时快照保留，不受删除影响。")
        }
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
            // 2026-09-25 需求一：被引用商品已照删，用户记录按快照保留（如实告知）
            if result.preservedRecordCount > 0 {
                toast = (toast ?? "") + "；\(result.preservedRecordCount) 条衣橱/心愿记录按快照保留"
            }
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
                        onEditBasics: { beginRename($0) },
                        onSheet: { productSheet = $0 },
                        onConfirm: { productConfirm = $0 }
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
    /// 强制删除（级联）：确认弹窗文案在点菜单时预检生成（预检与执行同源）
    @State private var showsForceDeleteConfirm = false
    @State private var forceDeleteImpactText = ""

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
                Button("强制删除（含全部下级）", role: .destructive) {
                    do {
                        let report = try ShopCatalogDraftStore.previewShopForceDeletion(
                            shop, store: store, modelContext: modelContext)
                        forceDeleteImpactText = Self.impactText(report)
                        showsForceDeleteConfirm = true
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
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
        // 强制删除第一步：预检出的真实影响范围（系列/商品/规格/尺码表 + 引用保留说明）
        .confirmationDialog("强制删除「\(shop.name)」及其全部下级？", isPresented: $showsForceDeleteConfirm, titleVisibility: .visible) {
            Button("强制删除", role: .destructive) {
                do {
                    let report = try ShopCatalogDraftStore.forceDeleteShop(
                        shop, store: store, modelContext: modelContext)
                    toast = Self.resultText(report)
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(forceDeleteImpactText)
        }
    }

    /// 影响范围文案（预检生成；销售历史按硬约束保留，明确告知）
    private static func impactText(_ report: ShopCatalogDraftStore.ShopForceDeletionReport) -> String {
        var text = "将级联删除：系列 \(report.deletedSeriesCount)、商品 \(report.deletedProductCount)、规格 \(report.deletedVariantCount)、尺码表 \(report.deletedSizeChartCount)。销售历史 \(report.retainedSaleEventCount) 条按规则保留。"
        // 2026-09-25 需求一：被引用商品照删，用户记录按快照保留（如实说清两件事）
        if !report.referencedProductNames.isEmpty {
            text += "\n其中 \(report.referencedProductNames.count) 件曾被心愿/衣橱引用：用户的 \(report.preservedRecordCount) 条记录按加入时快照保留，不受删除影响。"
        }
        return text
    }

    /// 执行结果文案（数量口径与预检一致：预检与执行同源）
    private static func resultText(_ report: ShopCatalogDraftStore.ShopForceDeletionReport) -> String {
        var text = "已删除「\(report.shopName)」：系列 \(report.deletedSeriesCount) · 商品 \(report.deletedProductCount) · 规格 \(report.deletedVariantCount) · 尺码表 \(report.deletedSizeChartCount)（子级合计 \(report.childRecordCount) 条）"
        if !report.referencedProductNames.isEmpty {
            text += "；\(report.preservedRecordCount) 条衣橱/心愿记录按快照保留"
        }
        return text
    }
}

// MARK: - 系列行

private struct SeriesManageRow: View {
    let series: CatalogSeries
    @ObservedObject var store: ShopCatalogStore
    let modelContext: ModelContext
    @Binding var toast: String?
    @Binding var actionError: String?
    /// 打开系列编辑页。**由外层统一持有 sheet**（2026-09-24 状态丢失根源修复）：
    /// 行内自持 `@State` + `.sheet` 会在 `List` 复用行时把编辑页连同用户已填内容
    /// （含封面图）一起重建。
    var onEdit: (() -> Void)? = nil

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
        // 尾款中（2026-09-24 需求三）：琥珀色 —— 与「预约已结束」的灰棕、
        // 「现货」的墨绿都区分得开，一眼能看出这条系列正在收尾款
        case .balancePending: return Color(hex: "B26A00")
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
                // 预约期（2026-09-24 需求五：开始 + 结束）：填过就展示，运营一眼看到
                // 这条系列什么时候开约、什么时候截止
                if let window = CatalogSeriesReservationWindow.displayText(of: series) {
                    Text(window)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                // 尾款时间 / 尾款期（2026-09-24 需求四、需求五）：填过就展示 —— 运营扫一眼列表
                // 就知道这条系列什么时候开始收尾款、什么时候收完
                if let due = CatalogSeriesBalanceDue.displayText(of: series) {
                    Text(due)
                        .font(.system(size: 11))
                        .foregroundStyle(effectiveSalePhase == .balancePending
                                         ? Color(hex: "B26A00") : Color.secondary)
                }
            }
            Spacer()
            Menu {
                Button("编辑（名称/年月/季节/封面/简介/发售阶段）") {
                    onEdit?()
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

// MARK: - 商品行模态目标（行只发意图，模态一律页面级呈现）

/// 行的「弹出表单」目标（深度编辑 / 价格修正 / 追加销售记录）。
///
/// 为什么用 `Identifiable` 枚举，而不是给每个表单一个 `Bool` `@State`：
///   ① 行视图会被 `List` 重建，挂在行上的 `.sheet` 连同内容视图的 `@State` 一起归零
///      （09-24 需求十四红线；深度编辑页带相册选图入口，正是该红线最初的踩坑场景）；
///   ② 一个 `Bool` 只表达「要不要弹」，还得另存一份「是哪个商品」——
///      两个状态一旦不同步就会弹出**别的商品**的表单，这类 bug 极难复现。
/// `id` 带上 case 名 + 商品 id：同一行在三种表单间切换时 SwiftUI 才会重建内容视图。
private enum ProductRowSheet: Identifiable {
    case deepEdit(CatalogProduct)
    case priceCorrection(CatalogProduct)
    case saleRecordAppend(CatalogProduct)

    var id: String {
        switch self {
        case .deepEdit(let product): return "deepEdit-\(product.id)"
        case .priceCorrection(let product): return "priceCorrection-\(product.id)"
        case .saleRecordAppend(let product): return "saleRecordAppend-\(product.id)"
        }
    }
}

/// 行的「危险操作确认」目标（归档 / 删除）。标题随目标变，所以不写死在
/// `.confirmationDialog` 上，改用 `presenting:` 拿到目标再算。
private enum ProductRowConfirm: Identifiable {
    case archive(CatalogProduct)
    case delete(CatalogProduct)

    var id: String {
        switch self {
        case .archive(let product): return "archive-\(product.id)"
        case .delete(let product): return "delete-\(product.id)"
        }
    }
}

// MARK: - 商品行

/// 商品行**只负责渲染 + 发出意图**：3 个表单与 2 个危险操作确认全部由
/// `ShopCatalogSeriesProductsView` 页面级呈现（理由见 `ProductRowSheet` 注释）。
private struct ProductManageRow: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    /// 「编辑基础（名称/分类）」→ 页面级弹窗（改名是款式级操作，需要整款视角做预览）
    let onEditBasics: (CatalogProduct) -> Void
    /// 三个表单类模态
    let onSheet: (ProductRowSheet) -> Void
    /// 两个危险操作确认
    let onConfirm: (ProductRowConfirm) -> Void

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
                    onEditBasics(product)
                }
                Button("深度编辑（图片/配色尺码/尺码表）") {
                    onSheet(.deepEdit(product))
                }
                // 价格两条流程：入口分开、语义写清楚，避免与「深度编辑」里混淆
                Button("价格修正（覆盖当前价 · 不产生历史）") {
                    onSheet(.priceCorrection(product))
                }
                Button("追加销售记录（再贩 · 带批次时间）") {
                    onSheet(.saleRecordAppend(product))
                }
                if product.archivedAt == nil {
                    Button("归档", role: .destructive) { onConfirm(.archive(product)) }
                }
                Button("删除", role: .destructive) { onConfirm(.delete(product)) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
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
    /// onAppear 一次性回填守卫（2026-09-24 状态丢失修复，与系列编辑同款）
    @State private var loaded = false

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
                // 一次性回填守卫（2026-09-24 状态丢失修复，与系列编辑同款）：
                // 切后台 / 相册选图 / 切应用返回重触发 onAppear 时不再覆盖已填内容
                guard !loaded else { return }
                loaded = true
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
    // 系列级三项配置（发售阶段 / 视觉与简介 / 预约价格表）改由**共用表单**承载
    // （2026-09-24 需求：批次详情页「一站式配置」）。
    // 这里不再各自持有十余个 @State：两个入口各持一套状态的话，迟早出现
    // 「在批次页填了尾款时间，回系列页保存一次就没了」这类互相吃掉字段的问题。
    // 共用实现：`ShopCatalogSeriesConfigSections` + `ShopCatalogSeriesConfigForm`。
    @State private var configForm = ShopCatalogSeriesConfigForm(series: CatalogSeries(id: "", shopID: "", name: ""))
    /// 已加载配置的系列 id：用于「系列变了才重建表单」的判定
    @State private var configFormSeriesID: String?
    /// onAppear 一次性回填守卫（2026-09-24 状态丢失修复）：防止切后台 / 相册选图 /
    /// 切应用返回时重复回填把已填内容覆盖成 series 原始值
    @State private var loaded = false

    @Environment(\.scenePhase) private var scenePhase

    /// 编辑中快照管家（2026-09-24 状态丢失**根源**修复）。
    ///
    /// 上面的 `loaded` 守卫只能挡「`onAppear` 被多触发一次」，挡不住真正的病灶 ——
    /// **承载它的视图被重建**。`loaded` 自己是 `@State`，视图一重建就归零，
    /// 守卫失效、表单被 `series` 原值重新回填（用户看到的就是「内容全没了」）。
    /// 根治靠不依赖视图生命周期：把未提交的输入落盘，重建后自动恢复。
    @State private var snapshotKeeper = ShopCatalogFormSnapshotKeeper<ShopCatalogSeriesEditSnapshot>(scope: "")

    var body: some View {
        NavigationStack {
            Form {
                snapshotNoticeSection
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
                // 系列级三项配置（发售阶段 / 视觉与简介 / 预约价格表）：
                // 与**批次详情页**同一份实现（`ShopCatalogSeriesConfigSections`）。
                // scope 传 nil：系列编辑页没有「本批次 N 条单品」这个上下文。
                ShopCatalogSeriesConfigSections(form: $configForm, sharedScope: nil)
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
                // 一次性回填（2026-09-24 状态丢失修复）：切后台回前台、进相册选图、
                // 切其他应用再返回都会重新触发 onAppear —— 无守卫时这里会用 series
                // 原始值覆盖用户已填的全部内容（表现为表单被重置）。
                //
                // ⚠️ 但守卫本身救不了「视图被重建」（`loaded` 也是 `@State`）——
                // 真正的兜底是下面那层快照：重建后把未提交的编辑自动恢复回来。
                guard !loaded else { return }
                loaded = true
                snapshotKeeper.scope = Self.snapshotScope(seriesID: series.id)
                name = series.name
                yearMonthText = series.yearMonthText ?? ""
                yearMonthError = nil
                season = series.season ?? ""
                configForm = ShopCatalogSeriesConfigForm(series: series)
                configFormSeriesID = series.id
                // 在「按存储值填好的默认态」之上，用快照恢复用户离开前的未保存编辑
                snapshotKeeper.restoreOrDiscard(defaults: makeSnapshot()) { applySnapshot($0) }
            }
            // ── 编辑中快照（2026-09-24 状态丢失根源修复）─────────────────────────
            // 三处「页面即将离开」的时机各立即落盘一次；再叠一层「改一下就存一下」
            // 的防抖落盘 —— 跳系统相册返回不会走 onDisappear，只有这层兜得住。
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                snapshotKeeper.flush(makeSnapshot())
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                snapshotKeeper.flush(makeSnapshot())
            }
            .onChange(of: makeSnapshot()) { _, snapshot in
                snapshotKeeper.schedule(snapshot)
            }
            .onDisappear {
                snapshotKeeper.flush(makeSnapshot())
            }
        }
    }

    // MARK: 编辑中快照（切后台 / 相册选图 / 切应用返回后不丢内容）

    private static func snapshotScope(seriesID: String) -> String {
        "series-edit-\(seriesID)"
    }

    /// 把当前整页表单组装成快照（唯一组装口径）。含 `configForm` 里的封面图引用。
    private func makeSnapshot() -> ShopCatalogSeriesEditSnapshot {
        ShopCatalogSeriesEditSnapshot(seriesID: series.id,
                                      name: name,
                                      yearMonthText: yearMonthText,
                                      season: season,
                                      config: configForm)
    }

    private func applySnapshot(_ snapshot: ShopCatalogSeriesEditSnapshot) {
        name = snapshot.name
        yearMonthText = snapshot.yearMonthText
        season = snapshot.season
        configForm = snapshot.config
        // 快照里没有校验态：恢复后让保存时的校验重新判定，不沿用旧红字
        yearMonthError = nil
        configFormSeriesID = series.id
    }

    /// 用户主动放弃恢复出来的未提交编辑
    private func discardRestoredSnapshot() {
        snapshotKeeper.discard()
        name = series.name
        yearMonthText = series.yearMonthText ?? ""
        yearMonthError = nil
        season = series.season ?? ""
        configForm = ShopCatalogSeriesConfigForm(series: series)
        configFormSeriesID = series.id
        toast = "已放弃上次未保存的编辑"
    }

    /// 「已恢复未保存编辑」提示条：不静默恢复，且给一条一键放弃的路
    @ViewBuilder
    private var snapshotNoticeSection: some View {
        if snapshotKeeper.didRestore {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已恢复上次未保存的编辑")
                        .font(.system(size: 13, weight: .semibold))
                    Text("离开页面时（切后台 / 去相册选图 / 切到其他应用）自动保留了这里的内容，包括已选的封面图。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("知道了") { snapshotKeeper.markRestoreAcknowledged() }
                            .font(.system(size: 13))
                        Button("放弃修改", role: .destructive) { discardRestoredSnapshot() }
                            .font(.system(size: 13))
                    }
                }
            } footer: {
                Text("「放弃修改」只清掉这份未保存的内容，不会动已保存的系列数据。")
            }
        }
    }

    // MARK: 保存（本页只补「基础信息」；三项系列配置由共用组件写回）

    private func save() {
        // 年月校验（2026-09-24 需求）：空 = 清除；"2026-10" / "2026年10月" / 纯年份均有效；
        // 非法输入**不落库**，红字提示留在输入框下方，等用户改对再保存。
        if let errorText = CatalogYearMonthText.validationErrorText(for: yearMonthText) {
            yearMonthError = errorText
            return
        }
        yearMonthError = nil
        // 尾款时间校验（2026-09-24 需求四）：与批次详情页共用同一份判定，不另写一套
        if let error = configForm.balanceDueValidationErrorText() {
            actionError = error
            return
        }
        let parsedYearMonth = CatalogYearMonthText.parse(yearMonthText)
        // 三项系列配置（发售阶段 / 视觉与简介 / 预约价格表）统一由共用表单写回 ——
        // 它只覆盖自己负责的字段，所以「在批次页填过尾款时间」这类并行编辑不会被本页吃掉。
        var updated = configForm.apply(to: series)
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.year = parsedYearMonth?.year
        updated.month = parsedYearMonth?.month
        let seasonTrimmed = season.trimmingCharacters(in: .whitespaces)
        updated.season = seasonTrimmed.isEmpty ? nil : seasonTrimmed
        do {
            try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.series)
            // 落库成功 = 这一份内容已提交：把表单归一成「实际保存的值」并清掉编辑中快照，
            // 免得关页时（onDisappear）又把刚保存的内容当成「未保存的编辑」写回去。
            name = updated.name
            yearMonthText = CatalogYearMonthText.displayText(year: updated.year, month: updated.month) ?? ""
            season = updated.season ?? ""
            yearMonthError = nil
            snapshotKeeper.commit(makeSnapshot())
            toast = "已更新系列「\(updated.name)」，发售阶段与价格表对全系列商品生效"
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
