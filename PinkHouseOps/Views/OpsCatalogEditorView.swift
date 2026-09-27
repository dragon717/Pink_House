//
//  OpsCatalogEditorView.swift
//  PinkHouseOps
//
//  目录编辑：店家 → 系列 → 商品 三级联动，最右列把图片资源绑到商品上。
//
//  ## 两条必须遵守的仓库级口径
//
//  1. **`.sheet` 挂页面级，不挂在列表行上。**
//     行视图是惰性 + 可复用的：窗口缩放、切到别的 App 再回来、列表重排都会让它
//     重建，挂在行上的 sheet 会连同内容视图的全部 `@State` 一起归零（iOS 端为这个
//     问题专门收口过）。所以本页所有 sheet 合并成一个 `EditorSheet` 枚举，
//     统一挂在最外层。
//
//  2. **删除用墓碑表达，且有下级引用时拒绝删除。**
//     `removedShopIDs` / `removedSeriesIDs` / `removedProductIDs` 是发布端的
//     「下架」信号；删干净了发布端只会以为是「这次漏传了」，线上不会下架。
//     级联删除会把「删 1 个店家」变成「悄悄删掉 20 个商品」，这里一律拒绝并说明。
//
//  ## 年月为什么是数字输入
//
//  仓库里年月的唯一解析口径是 `CatalogYearMonthText`（`2026` / `2026-10` /
//  `2026年10月`），但它在 iOS App 里、**没有迁进 SharedCatalog**。
//  Mac 端就地再写一遍解析 = 出现第二个口径（正是要避免的事），
//  所以这里只收数字年月，不提供自由文本解析。
//
//  ## 系列配置为什么只留一个入口（一站式）
//
//  发售阶段、预约/尾款区间、系列价格表都存放在**同一个** `CatalogSeries` 上。
//  如果这里放一个「改阶段」的入口、商品页再放一个「改价格表」的入口，运营就会
//  在两边各改一半，而两边都没有对方的字段 —— 最后谁也说不清「系列现在声明的是什么」。
//  所以：系列的档期与价格表全部走 `SeriesConfigSheet` 一个 sheet，
//  它内部只写自己负责的字段（`updateSeriesSalePhase` / `updateSeriesPriceChart`），
//  **不碰任何价格、不碰批次与单品**。
//
//  ## 两个来自方案 R05/R06 的交互约束
//
//  3. **编辑命令成功才关窗。** 三个表单的「保存」不再无条件 `dismiss()`：
//     命令返回 false（名称空、系列不属于店家、草稿处于隔离态…）时留在表单里，
//     错误文案走全局 banner。旧实现无条件 dismiss，运营填完一整页才发现没保存。
//  4. **父子选择要按 ID 变化收敛，不能只看数量。** 只监听 `count` 会漏掉
//     「两个系列商品数刚好相同」的切换（数量没变 → 收敛逻辑不触发 → 右列
//     停在旧系列的商品上）。所以改成同时监听父选择的 ID。
//

import AppKit
import SwiftUI

struct OpsCatalogEditorView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var selectedShopID: String?
    @State private var selectedSeriesID: String?
    @State private var selectedProductID: String?
    @State private var sheet: EditorSheet?
    /// §6.1 系列列表筛选：「当前上新（未归档）/ 未标年份 / 指定年份」；"all" = 全部
    @State private var seriesFilterID = "all"
    /// 图1 顶部的搜索胶囊：过滤店家 / 系列 / 商品名
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 12) {
            pageHeader
            HSplitView {
                shopColumn
                seriesColumn
                productColumn
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .background(OpsFlowPageBackground())
        .sheet(item: $sheet) { item in
            switch item {
            case .shopForm(let existingID):
                ShopFormSheet(workspace: workspace, existingID: existingID)
            case .seriesForm(let existingID):
                SeriesFormSheet(
                    workspace: workspace, existingID: existingID, preferredShopID: selectedShopID)
            case .seriesConfig(let seriesID):
                SeriesConfigSheet(workspace: workspace, seriesID: seriesID)
            case .productForm(let existingID):
                ProductFormSheet(
                    workspace: workspace, existingID: existingID,
                    preferredShopID: selectedShopID, preferredSeriesID: selectedSeriesID)
            case .bindImages(let productID):
                BindImagesSheet(workspace: workspace, productID: productID)
            }
        }
        .onAppear { clampSelection() }
        // 父选择一换，下级选择必须立刻收敛（R06）—— 只盯 count 会漏掉
        // 「两个系列商品数相同」的切换。
        .onChange(of: selectedShopID) { _, _ in clampSelection() }
        .onChange(of: selectedSeriesID) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.shops.count) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.series.count) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.products.count) { _, _ in clampSelection() }
    }

    // MARK: 页头（图1：粉紫渐变带 + 标题 + 搜索胶囊）

    private var pageHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("店家与系列 · 商品查看与运营编辑")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("按「店家上新 → 系列 → 类型分组商品 → 详情」逐层查看；筛选支持当前上新、年份与未标年份。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(OpsFlowPalette.textSecondary)
                TextField("搜索店家、系列或商品", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(OpsFlowPalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(OpsFlowPalette.accentPink.opacity(0.35), lineWidth: 1))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [OpsFlowPalette.accentPink.opacity(0.85),
                         OpsFlowPalette.primaryPurple.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: OpsFlowPalette.cardShadow, radius: 10, x: 0, y: 4)
    }

    private func matchesSearch(_ text: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(query)
    }

    // MARK: 派生列表

    private var seriesUnderSelectedShop: [CatalogSeries] {
        guard let selectedShopID else { return [] }
        let all = workspace.catalog.series.filter { $0.shopID == selectedShopID }
        let filtered: [CatalogSeries]
        switch seriesFilterID {
        case "current":
            filtered = all.filter { $0.archivedAt == nil }
        case "untagged":
            filtered = all.filter { $0.year == nil }
        case "all":
            filtered = all
        default:
            // "year-2026" 形态
            let year = Int(seriesFilterID.dropFirst("year-".count))
            filtered = all.filter { $0.year == year }
        }
        return filtered.filter { matchesSearch($0.name) }
    }

    /// 筛选候选里的年份（**按该店系列首次出现顺序**，不用无序集合遍历序）
    private var filterYearOptions: [Int] {
        guard let selectedShopID else { return [] }
        var ordered: [Int] = []
        for series in workspace.catalog.series
        where series.shopID == selectedShopID {
            if let year = series.year, !ordered.contains(year) { ordered.append(year) }
        }
        return ordered
    }

    private var productsUnderSelectedSeries: [CatalogProduct] {
        guard let selectedSeriesID else { return [] }
        return workspace.catalog.products
            .filter { $0.seriesID == selectedSeriesID }
            .filter { matchesSearch($0.name) }
    }

    /// 店家列（图1 第一步「店家一览」）：搜索命中名称或别名
    private var filteredShops: [CatalogShop] {
        workspace.catalog.shops.filter { shop in
            matchesSearch(shop.name) || shop.aliases.contains { matchesSearch($0) }
        }
    }

    /// 该系列下的类型分组（§6.1）：按商品**首次出现顺序**，绝不用无序集合遍历序
    private var orderedCategoriesInSelectedSeries: [String] {
        var ordered: [String] = []
        for product in productsUnderSelectedSeries
        where !ordered.contains(product.category) {
            ordered.append(product.category)
        }
        return ordered
    }

    /// 选择态对不上数据时收敛回第一个 —— 列表是数据派生的，
    /// 删掉当前选中项之后如果不管，右两列会一直停在「空」上，看起来像坏了。
    private func clampSelection() {
        if !workspace.catalog.shops.contains(where: { $0.id == selectedShopID }) {
            selectedShopID = workspace.catalog.shops.first?.id
        }
        if !seriesUnderSelectedShop.contains(where: { $0.id == selectedSeriesID }) {
            selectedSeriesID = seriesUnderSelectedShop.first?.id
        }
        if !productsUnderSelectedSeries.contains(where: { $0.id == selectedProductID }) {
            selectedProductID = productsUnderSelectedSeries.first?.id
        }
    }

    // MARK: 店家列

    private var shopColumn: some View {
        ColumnShell(
            title: "店家",
            count: filteredShops.count,
            tint: OpsFlowPalette.tilePink,
            emptyHint: "还没有店家。先建一个店家，再往里加系列。",
            isEmpty: filteredShops.isEmpty,
            onAdd: { sheet = .shopForm(existingID: nil) },
            addHelp: "新增店家"
        ) {
            List(selection: $selectedShopID) {
                ForEach(filteredShops) { shop in
                    shopRow(shop).tag(shop.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 210, idealWidth: 240)
    }

    /// 店家行（图1 第一步）：粉色瓷片 + 头像圆 + 名称 + 元信息
    private func shopRow(_ shop: CatalogShop) -> some View {
        OpsFlowTile(color: OpsFlowPalette.tilePink, selected: shop.id == selectedShopID) {
            HStack(spacing: 10) {
                // 头像圆：取店名的第一个字符（图1 的圆形店家标识）
                ZStack {
                    Circle()
                        .fill(OpsFlowPalette.accentPink.opacity(0.85))
                    Text(String(shop.name.prefix(1)))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shop.name).lineLimit(1)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(OpsFlowPalette.textPrimary)
                    // §6.1：店家行显示最近上新时间（= 该店系列里最新的年月，无则「—」）
                    Text("\(workspace.catalog.series.filter { $0.shopID == shop.id }.count) 系列 · "
                         + "\(workspace.catalog.products.filter { $0.shopID == shop.id }.count) 商品 · "
                         + "最近上新 \(latestUpdateText(for: shop.id))")
                        .font(.caption)
                        .foregroundStyle(OpsFlowPalette.textSecondary)
                }
            }
        }
        .contextMenu {
            Button("编辑…") { sheet = .shopForm(existingID: shop.id) }
            Button("删除店家", role: .destructive) {
                if workspace.removeShop(id: shop.id) { clampSelection() }
            }
        }
    }

    // MARK: 系列列

    private var seriesColumn: some View {
        ColumnShell(
            title: "系列",
            count: seriesUnderSelectedShop.count,
            tint: OpsFlowPalette.tileLilac,
            emptyHint: selectedShopID == nil
                ? "先选一个店家。"
                : "这个店家下还没有系列。",
            isEmpty: seriesUnderSelectedShop.isEmpty,
            onAdd: { sheet = .seriesForm(existingID: nil) },
            addHelp: "新增系列",
            addDisabled: selectedShopID == nil
        ) {
            VStack(spacing: 0) {
                // §6.1：支持「当前上新 / 年份 / 未标年份」筛选
                Picker("筛选", selection: $seriesFilterID) {
                    Text("全部").tag("all")
                    Text("当前上新").tag("current")
                    Text("未标年份").tag("untagged")
                    ForEach(filterYearOptions, id: \.self) { year in
                        Text("\(year) 年").tag("year-\(year)")
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                List(selection: $selectedSeriesID) {
                    ForEach(seriesUnderSelectedShop) { series in
                        seriesRow(series).tag(series.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .safeAreaInset(edge: .bottom) { seriesFooter }
        }
        .frame(minWidth: 210, idealWidth: 240)
    }

    /// 系列行（图1 第二步）：瓷片 + 名称 + 年月/商品数 + 发售状态胶囊
    private func seriesRow(_ series: CatalogSeries) -> some View {
        OpsFlowTile(
            color: series.archivedAt == nil
                ? OpsFlowPalette.tileLilac : OpsFlowPalette.tileRed.opacity(0.7),
            selected: series.id == selectedSeriesID) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(series.name).lineLimit(1)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(OpsFlowPalette.textPrimary)
                    OpsFlowChip(
                        text: series.salePhase?.displayName ?? "未声明",
                        tint: series.salePhase == nil
                            ? OpsFlowPalette.textSecondary : OpsFlowPalette.primaryPurple)
                }
                Text(seriesSubtitle(series))
                    .font(.caption)
                    .foregroundStyle(OpsFlowPalette.textSecondary)
            }
        }
        .contextMenu {
            Button("编辑系列…") { sheet = .seriesForm(existingID: series.id) }
            Button("配置发售阶段与价格表…") { sheet = .seriesConfig(seriesID: series.id) }
            Divider()
            Button("删除系列", role: .destructive) {
                if workspace.removeSeries(id: series.id) { clampSelection() }
            }
        }
    }

    /// 最近上新文本（§6.1）：该店系列里最新的年月；没有年月信息则「—」
    private func latestUpdateText(for shopID: String) -> String {
        var latest: (year: Int, month: Int?)?
        for series in workspace.catalog.series where series.shopID == shopID {
            guard let year = series.year else { continue }
            if latest == nil || year > latest!.year {
                latest = (year, series.month)
            }
        }
        guard let latest else { return "—" }
        if let month = latest.month { return String(format: "%04d-%02d", latest.year, month) }
        return "\(latest.year)"
    }

    /// 系列列的底部：档期/价格表摘要 + 唯一入口。
    /// 摘要放在这里而不是列表行里 —— 行是复用的，长文案会把列表挤散。
    @ViewBuilder
    private var seriesFooter: some View {
        if let seriesID = selectedSeriesID,
           let series = workspace.catalog.series.first(where: { $0.id == seriesID }) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Text(series.name).font(.callout.weight(.medium)).lineLimit(1)
                OpsFootnote(text: "发售阶段：\(series.salePhase?.displayName ?? "未声明")　·　"
                            + "价格表：\(series.priceChart == nil ? "无" : "有")")
                Button {
                    sheet = .seriesConfig(seriesID: series.id)
                } label: {
                    Label("配置发售阶段与价格表…", systemImage: "calendar.badge.clock")
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
    }

    private func seriesSubtitle(_ series: CatalogSeries) -> String {
        let count = workspace.catalog.products.filter { $0.seriesID == series.id }.count
        let yearMonth: String
        switch (series.year, series.month) {
        case let (year?, month?): yearMonth = String(format: "%04d-%02d", year, month)
        case let (year?, nil): yearMonth = "\(year)"
        default: yearMonth = ""
        }
        return [yearMonth, "\(count) 商品"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: 商品列

    private var productColumn: some View {
        ColumnShell(
            title: "商品",
            count: productsUnderSelectedSeries.count,
            tint: OpsFlowPalette.tilePink,
            emptyHint: selectedSeriesID == nil
                ? "先选一个系列。"
                : "这个系列下还没有商品。",
            isEmpty: productsUnderSelectedSeries.isEmpty,
            onAdd: { sheet = .productForm(existingID: nil) },
            addHelp: "新增商品",
            addDisabled: selectedSeriesID == nil
        ) {
            List(selection: $selectedProductID) {
                // 需求 §6.1：商品列表按 JSK、OP、小物等**类型分组**。
                // 分组顺序 = 该系列下商品的**首次出现顺序**（禁用 Set/Dictionary 遍历序派生
                // —— 冷启动换排法是仓库红线的同类坑）。
                ForEach(orderedCategoriesInSelectedSeries, id: \.self) { category in
                    Section {
                        ForEach(productsUnderSelectedSeries.filter { $0.category == category }) { product in
                            productRow(product)
                                .tag(product.id)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    Button("编辑基本信息…") { sheet = .productForm(existingID: product.id) }
                                    Button("绑定商品图…") { sheet = .bindImages(productID: product.id) }
                                    Divider()
                                    if product.archivedAt == nil {
                                        Button("归档（下线）") {
                                            workspace.setArchived(true, kind: .product, id: product.id)
                                            clampSelection()
                                        }
                                    } else {
                                        Button("恢复上线") {
                                            workspace.setArchived(false, kind: .product, id: product.id)
                                        }
                                    }
                                    Button("删除商品", role: .destructive) {
                                        if workspace.removeProduct(id: product.id) { clampSelection() }
                                    }
                                }
                        }
                    } header: {
                        // 类型分组标题 = 图1 的分类胶囊（粉色实心）
                        OpsFlowChip(text: category.isEmpty ? "未分类" : category,
                                    tint: OpsFlowPalette.accentPink, filled: true)
                            .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) { productFooter }
        }
        .frame(minWidth: 280, idealWidth: 320)
    }

    private func productRow(_ product: CatalogProduct) -> some View {
        let archive = workspace.priceArchive(forProduct: product.id)
        let variants = workspace.variants(forProduct: product.id)
        // 颜色 / 尺码数：按**出现顺序**去重（不用无序集合遍历序）
        var orderedColors: [String] = []
        var orderedSizes: [String] = []
        for variant in variants {
            if let color = variant.color, !orderedColors.contains(color) { orderedColors.append(color) }
            if let size = variant.size, !orderedSizes.contains(size) { orderedSizes.append(size) }
        }
        let firstImageAsset = product.images.first.flatMap { id in
            workspace.catalog.assets.first { $0.id == id }
        }
        let imageURL = firstImageAsset.flatMap { workspace.stagedFileURL(forReference: $0.originalURL) }
        return OpsFlowTile(color: OpsFlowPalette.tilePink, selected: product.id == selectedProductID) {
            HStack(spacing: 10) {
                // 商品图（图1 商品卡左侧的图块）；无图 = 占位图标
                OpsThumbnail(url: imageURL, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.name).lineLimit(1)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(OpsFlowPalette.textPrimary)
                        if product.archivedAt != nil {
                            OpsFlowChip(text: "已归档", tint: OpsFlowPalette.textSecondary)
                        }
                    }
                    // §6.1：商品卡片显示价格与颜色/尺码摘要（胶囊标签）
                    HStack(spacing: 6) {
                        if let reservation = archive?.currentReservationPrice {
                            OpsFlowChip(text: "预约 " + priceText(reservation, archive?.currentCurrency),
                                        tint: OpsFlowPalette.accentPink)
                        }
                        if let stock = archive?.currentStockPrice {
                            OpsFlowChip(text: "现货 " + priceText(stock, archive?.currentCurrency),
                                        tint: OpsFlowPalette.okGreen)
                        }
                        if !orderedColors.isEmpty || !orderedSizes.isEmpty {
                            Text("\(orderedColors.count) 色 · "
                                 + (orderedSizes.isEmpty ? "均码" : orderedSizes.joined(separator: "/")))
                                .font(.caption)
                                .foregroundStyle(OpsFlowPalette.textSecondary)
                        }
                    }
                    .lineLimit(1)
                }
            }
        }
    }

    private func priceText(_ amount: Decimal, _ currency: CatalogCurrency?) -> String {
        CatalogMoney(amount: amount, currency: currency ?? .unknown).displayText
    }

    @ViewBuilder
    private var productFooter: some View {
        if let selectedProductID {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text(workspace.catalog.products.first { $0.id == selectedProductID }?.name ?? "")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Button {
                        sheet = .bindImages(productID: selectedProductID)
                    } label: {
                        Label("绑定商品图", systemImage: "photo.badge.plus")
                    }
                    Button(role: .destructive) {
                        if workspace.removeProduct(id: selectedProductID) { clampSelection() }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .controlSize(.small)
                OpsFootnote(text: "这一列只做结构（谁挂在谁下面）。规格 / 尺码表 / 价格与销售记录"
                            + "在「商品管理」里编排 —— 那也是**操作单位**所在的地方。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
    }
}

// MARK: - sheet 载体（合并成一个枚举，挂页面级）

private enum EditorSheet: Identifiable {
    case shopForm(existingID: String?)
    case seriesForm(existingID: String?)
    case seriesConfig(seriesID: String)
    case productForm(existingID: String?)
    case bindImages(productID: String)

    var id: String {
        switch self {
        case .shopForm(let existingID): return "shop-\(existingID ?? "new")"
        case .seriesForm(let existingID): return "series-\(existingID ?? "new")"
        case .seriesConfig(let seriesID): return "seriesconfig-\(seriesID)"
        case .productForm(let existingID): return "product-\(existingID ?? "new")"
        case .bindImages(let productID): return "bind-\(productID)"
        }
    }
}

// MARK: - 列外壳

/// 列外壳（图1 的分区卡）：白卡 + 粉彩标题条 + 粉色加号。
private struct ColumnShell<Content: View>: View {
    let title: String
    let count: Int
    var tint: Color = OpsFlowPalette.tilePink
    let emptyHint: String
    let isEmpty: Bool
    let onAdd: () -> Void
    let addHelp: String
    var addDisabled: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(OpsFlowPalette.textPrimary)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(OpsFlowPalette.accentPink, in: Capsule())
                Spacer(minLength: 4)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(OpsFlowPalette.accentPink, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(addDisabled)
                .opacity(addDisabled ? 0.4 : 1)
                .help(addHelp)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint)
            Divider().overlay(OpsFlowPalette.cardBorder)
            if isEmpty {
                Text(emptyHint)
                    .font(.callout)
                    .foregroundStyle(OpsFlowPalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            } else {
                content
            }
        }
        .background(OpsFlowPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(OpsFlowPalette.cardBorder, lineWidth: 1))
        .shadow(color: OpsFlowPalette.cardShadow, radius: 10, x: 0, y: 4)
    }
}

// MARK: - 店家表单

private struct ShopFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let existingID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var aliasesText = ""

    var body: some View {
        SheetFrame(title: existingID == nil ? "新增店家" : "编辑店家") {
            TextField("店家名", text: $name)
            TextField("别名（英文逗号分隔，用于搜索匹配）", text: $aliasesText)
        } onCancel: {
            dismiss()
        } onConfirm: {
            let aliases = aliasesText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            // R05：只有成功才关窗；失败留在表单里，原因在全局 banner
            let ok: Bool
            if let existingID {
                ok = workspace.updateShop(id: existingID, name: name, aliases: aliases)
            } else {
                ok = workspace.addShop(name: name)
            }
            if ok { dismiss() }
        }
        .onAppear {
            guard let existingID,
                  let shop = workspace.catalog.shops.first(where: { $0.id == existingID }) else { return }
            name = shop.name
            aliasesText = shop.aliases.joined(separator: ", ")
        }
    }
}

// MARK: - 系列表单

private struct SeriesFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let existingID: String?
    let preferredShopID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var shopID = ""
    @State private var name = ""
    @State private var yearText = ""
    @State private var monthText = ""
    @State private var season = ""

    var body: some View {
        SheetFrame(title: existingID == nil ? "新增系列" : "编辑系列") {
            Picker("所属店家", selection: $shopID) {
                ForEach(workspace.catalog.shops) { shop in
                    Text(shop.name).tag(shop.id)
                }
            }
            TextField("系列名", text: $name)
            HStack(spacing: 10) {
                TextField("年份（如 2026）", text: $yearText)
                TextField("月份（1–12，可空）", text: $monthText)
            }
            TextField("季节（可空，如「冬」）", text: $season)
            Text("月份留空 = 只记年份（与旧数据的口径一致）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } onCancel: {
            dismiss()
        } onConfirm: {
            let year = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
            let month = Int(monthText.trimmingCharacters(in: .whitespacesAndNewlines))
            let trimmedSeason = season.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedSeason = trimmedSeason.isEmpty ? nil : trimmedSeason
            // R05：新建也要带上 season —— 旧实现只在编辑路径传，新建出来的系列
            // 季节是空的，「新建后回显」这条验收因此永远过不了。
            let ok: Bool
            if let existingID {
                ok = workspace.updateSeries(
                    id: existingID, shopID: shopID, name: name,
                    year: year, month: month, season: resolvedSeason)
            } else {
                ok = workspace.addSeries(
                    shopID: shopID, name: name, year: year, month: month, season: resolvedSeason)
            }
            if ok { dismiss() }
        }
        .onAppear {
            if let existingID,
               let series = workspace.catalog.series.first(where: { $0.id == existingID }) {
                shopID = series.shopID
                name = series.name
                yearText = series.year.map(String.init) ?? ""
                monthText = series.month.map(String.init) ?? ""
                season = series.season ?? ""
            } else {
                shopID = preferredShopID ?? workspace.catalog.shops.first?.id ?? ""
            }
        }
    }
}

// MARK: - 商品表单

private struct ProductFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let existingID: String?
    let preferredShopID: String?
    let preferredSeriesID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var shopID = ""
    @State private var seriesID = ""
    @State private var name = ""
    @State private var category = ""

    private var seriesOfShop: [CatalogSeries] {
        workspace.catalog.series.filter { $0.shopID == shopID }
    }

    var body: some View {
        SheetFrame(title: existingID == nil ? "新增商品" : "编辑商品") {
            Picker("店家", selection: $shopID) {
                ForEach(workspace.catalog.shops) { shop in
                    Text(shop.name).tag(shop.id)
                }
            }
            .onChange(of: shopID) { _, _ in
                // 换店家之后原来的系列就不属于这个店家了，必须重选 ——
                // 不重选会写出「商品属于 A 店家、系列属于 B 店家」的悬空结构，
                // 发布门禁会拦，但那时运营已经填完一整页了。
                if !seriesOfShop.contains(where: { $0.id == seriesID }) {
                    seriesID = seriesOfShop.first?.id ?? ""
                }
            }
            Picker("系列", selection: $seriesID) {
                ForEach(seriesOfShop) { series in
                    Text(series.name).tag(series.id)
                }
            }
            TextField("商品名（如「星月夜 JSK 蓝色」）", text: $name)
            TextField("品类（如 JSK / OP / SK / 小物）", text: $category)
        } onCancel: {
            dismiss()
        } onConfirm: {
            // R05：只有成功才关窗
            let ok: Bool
            if let existingID {
                ok = workspace.updateProduct(
                    id: existingID, shopID: shopID, seriesID: seriesID,
                    name: name, category: category)
            } else {
                ok = workspace.addProduct(
                    shopID: shopID, seriesID: seriesID, name: name, category: category)
            }
            if ok { dismiss() }
        }
        .onAppear {
            if let existingID,
               let product = workspace.catalog.products.first(where: { $0.id == existingID }) {
                shopID = product.shopID
                seriesID = product.seriesID
                name = product.name
                category = product.category
            } else {
                shopID = preferredShopID ?? workspace.catalog.shops.first?.id ?? ""
                seriesID = preferredSeriesID ?? seriesOfShop.first?.id ?? ""
            }
        }
    }
}

// MARK: - 绑定商品图（R04：每个商品自己的**有序**图片数组）

/// 旧实现的两个问题（方案 R04）：
///   1. 勾选状态是 `Set<String>`，提交时按 `catalog.assets` 的**全局顺序**回写 ——
///      于是「商品图顺序」根本不是这个商品自己的顺序，而是素材库顺序。
///      两个商品共享同样三张图、想要不同顺序时，永远保存不下来。
///   2. 行里只显示 assetID / URL，运营要自己认 hash。
///
/// 现在：左边是**已选的有序列表**（顺序 = 商品图顺序，可上移/下移/移除/置首），
/// 右边是尚未选中的素材（可「加入」或「加入并置首」），两边都带缩略图。
private struct BindImagesSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    /// 已选图片的**有序**数组；提交时原样写入 `product.images`
    @State private var selectedOrder: [String] = []
    @State private var didLoad = false

    private var productName: String {
        workspace.catalog.products.first { $0.id == productID }?.name ?? ""
    }

    private var unselectedAssets: [CatalogAsset] {
        let chosen = Set(selectedOrder)
        return workspace.catalog.assets.filter { !chosen.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("绑定商品图").font(.headline)
                Text(productName).font(.callout).foregroundStyle(.secondary)
                // 拼接结果 = String 变量 → 必须过 `opsMarkdown`（单字面量才自动解析 Markdown）
                opsMarkdown("左边列表的顺序**就是**这个商品的图片顺序（第一张是首图）；"
                     + "它只属于这个商品，与素材库的列出顺序无关。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if workspace.catalog.assets.isEmpty {
                Text("还没有图片资源。先到「概览」导入商品图。")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    selectedColumn
                    Divider()
                    candidateColumn
                }
                .frame(maxHeight: .infinity)
            }

            footer
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // 原样取当前顺序 —— 不排序、不去重
            selectedOrder = workspace.catalog.products
                .first { $0.id == productID }?.images ?? []
        }
    }

    // MARK: 左：已选（有序）

    private var selectedColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已选（\(selectedOrder.count)）").font(.subheadline.weight(.semibold))
                Spacer()
                Button("清空") { selectedOrder = [] }
                    .buttonStyle(.link).font(.caption)
                    .disabled(selectedOrder.isEmpty)
            }
            if selectedOrder.isEmpty {
                Text("还没选图。从右边加入。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                List {
                    ForEach(Array(selectedOrder.enumerated()), id: \.element) { index, assetID in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            OpsAssetThumbnail(url: previewURL(for: assetID))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(assetLabel(assetID)).font(.callout).lineLimit(1)
                                if index == 0 {
                                    Text("首图")
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                                }
                            }
                            Spacer(minLength: 4)
                            Button { move(assetID, by: -1) } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                .help("上移")
                            Button { move(assetID, by: 1) } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless)
                                .disabled(index == selectedOrder.count - 1)
                                .help("下移")
                            Button { selectedOrder.removeAll { $0 == assetID } } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("解除绑定（只从本商品移除，不删素材）")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 右：候选素材

    private var candidateColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("素材库（\(unselectedAssets.count) 张可用）")
                .font(.subheadline.weight(.semibold))
            if unselectedAssets.isEmpty {
                Text("素材都已经在这个商品上了。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                List(unselectedAssets) { asset in
                    HStack(spacing: 8) {
                        OpsAssetThumbnail(url: previewURL(for: asset.id))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(assetLabel(asset.id)).font(.callout).lineLimit(1)
                            Text("\(assetTypeLabel(asset.type)) · "
                                 + "\(asset.width ?? 0)×\(asset.height ?? 0)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button("加入") { selectedOrder.append(asset.id) }
                            .buttonStyle(.link).font(.caption)
                        Button("置首") { selectedOrder.insert(asset.id, at: 0) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("已选 \(selectedOrder.count) 张")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("取消") { dismiss() }
            Button("确定") {
                // R05：绑定失败（例如草稿处于只读隔离态）不关窗
                if workspace.bindImages(selectedOrder, toProduct: productID) { dismiss() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: 小工具

    private func move(_ assetID: String, by delta: Int) {
        guard let index = selectedOrder.firstIndex(of: assetID) else { return }
        let target = index + delta
        guard selectedOrder.indices.contains(target) else { return }
        selectedOrder.swapAt(index, target)
    }

    /// 优先显示**源文件名** —— 运营认文件名，不认内容 hash
    private func assetLabel(_ assetID: String) -> String {
        guard let asset = workspace.catalog.assets.first(where: { $0.id == assetID }) else {
            return assetID + "（素材已不存在）"
        }
        if let url = previewURL(for: assetID) { return url.lastPathComponent }
        return asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }

    private func previewURL(for assetID: String) -> URL? {
        guard let asset = workspace.catalog.assets.first(where: { $0.id == assetID }) else { return nil }
        return workspace.stagedFileURL(forReference: asset.originalURL)
            ?? workspace.stagedFileURL(forReference: asset.previewURL)
            ?? workspace.stagedFileURL(forReference: asset.thumbnailURL)
    }
}

/// 素材缩略图。不确定的引用退化成占位图标，不留空白
/// （空白会被读成「图丢了」，占位图标读成「这里本来就没图」）。
private struct OpsAssetThumbnail: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

private func assetTypeLabel(_ type: CatalogAssetType) -> String {
    switch type {
    case .productImage: return "商品图"
    case .sizeChartImage: return "尺码表原图"
    case .seriesCover: return "系列主视觉"
    case .shopCover: return "店家封面"
    }
}

// MARK: - 表单外壳

private struct SheetFrame<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
