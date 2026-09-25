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

import SwiftUI

struct OpsCatalogEditorView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var selectedShopID: String?
    @State private var selectedSeriesID: String?
    @State private var selectedProductID: String?
    @State private var sheet: EditorSheet?

    var body: some View {
        HSplitView {
            shopColumn
            seriesColumn
            productColumn
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .shopForm(let existingID):
                ShopFormSheet(workspace: workspace, existingID: existingID)
            case .seriesForm(let existingID):
                SeriesFormSheet(
                    workspace: workspace, existingID: existingID, preferredShopID: selectedShopID)
            case .productForm(let existingID):
                ProductFormSheet(
                    workspace: workspace, existingID: existingID,
                    preferredShopID: selectedShopID, preferredSeriesID: selectedSeriesID)
            case .bindImages(let productID):
                BindImagesSheet(workspace: workspace, productID: productID)
            }
        }
        .onAppear { clampSelection() }
        .onChange(of: workspace.catalog.shops.count) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.series.count) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.products.count) { _, _ in clampSelection() }
    }

    // MARK: 派生列表

    private var seriesUnderSelectedShop: [CatalogSeries] {
        guard let selectedShopID else { return [] }
        return workspace.catalog.series.filter { $0.shopID == selectedShopID }
    }

    private var productsUnderSelectedSeries: [CatalogProduct] {
        guard let selectedSeriesID else { return [] }
        return workspace.catalog.products.filter { $0.seriesID == selectedSeriesID }
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
            count: workspace.catalog.shops.count,
            emptyHint: "还没有店家。先建一个店家，再往里加系列。",
            isEmpty: workspace.catalog.shops.isEmpty,
            onAdd: { sheet = .shopForm(existingID: nil) },
            addHelp: "新增店家"
        ) {
            List(selection: $selectedShopID) {
                ForEach(workspace.catalog.shops) { shop in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shop.name).lineLimit(1)
                        Text("\(workspace.catalog.series.filter { $0.shopID == shop.id }.count) 系列 · "
                             + "\(workspace.catalog.products.filter { $0.shopID == shop.id }.count) 商品")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(shop.id)
                    .contextMenu {
                        Button("编辑…") { sheet = .shopForm(existingID: shop.id) }
                        Button("删除店家", role: .destructive) {
                            _ = workspace.removeShop(id: shop.id)
                            clampSelection()
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 190, idealWidth: 215)
    }

    // MARK: 系列列

    private var seriesColumn: some View {
        ColumnShell(
            title: "系列",
            count: seriesUnderSelectedShop.count,
            emptyHint: selectedShopID == nil
                ? "先选一个店家。"
                : "这个店家下还没有系列。",
            isEmpty: seriesUnderSelectedShop.isEmpty,
            onAdd: { sheet = .seriesForm(existingID: nil) },
            addHelp: "新增系列",
            addDisabled: selectedShopID == nil
        ) {
            List(selection: $selectedSeriesID) {
                ForEach(seriesUnderSelectedShop) { series in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(series.name).lineLimit(1)
                        Text(seriesSubtitle(series))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(series.id)
                    .contextMenu {
                        Button("编辑…") { sheet = .seriesForm(existingID: series.id) }
                        Button("删除系列", role: .destructive) {
                            _ = workspace.removeSeries(id: series.id)
                            clampSelection()
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 190, idealWidth: 215)
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
            emptyHint: selectedSeriesID == nil
                ? "先选一个系列。"
                : "这个系列下还没有商品。",
            isEmpty: productsUnderSelectedSeries.isEmpty,
            onAdd: { sheet = .productForm(existingID: nil) },
            addHelp: "新增商品",
            addDisabled: selectedSeriesID == nil
        ) {
            List(selection: $selectedProductID) {
                ForEach(productsUnderSelectedSeries) { product in
                    productRow(product)
                        .tag(product.id)
                        .contextMenu {
                            Button("编辑…") { sheet = .productForm(existingID: product.id) }
                            Button("绑定商品图…") { sheet = .bindImages(productID: product.id) }
                            Divider()
                            Button("删除商品", role: .destructive) {
                                workspace.removeProduct(id: product.id)
                                clampSelection()
                            }
                        }
                }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom) { productFooter }
        }
        .frame(minWidth: 260, idealWidth: 300)
    }

    private func productRow(_ product: CatalogProduct) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(product.name).lineLimit(1)
                if product.category.isEmpty == false {
                    Text(product.category)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Label("\(product.images.count) 图", systemImage: "photo")
                if let designName = product.designName, !designName.isEmpty {
                    Text("款式 \(designName)")
                }
            }
            .font(.caption)
            .foregroundStyle(product.images.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
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
                        workspace.removeProduct(id: selectedProductID)
                        clampSelection()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .controlSize(.small)
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
    case productForm(existingID: String?)
    case bindImages(productID: String)

    var id: String {
        switch self {
        case .shopForm(let existingID): return "shop-\(existingID ?? "new")"
        case .seriesForm(let existingID): return "series-\(existingID ?? "new")"
        case .productForm(let existingID): return "product-\(existingID ?? "new")"
        case .bindImages(let productID): return "bind-\(productID)"
        }
    }
}

// MARK: - 列外壳

private struct ColumnShell<Content: View>: View {
    let title: String
    let count: Int
    let emptyHint: String
    let isEmpty: Bool
    let onAdd: () -> Void
    let addHelp: String
    var addDisabled: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(addDisabled)
                .help(addHelp)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()
            if isEmpty {
                Text(emptyHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            } else {
                content
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
            if let existingID {
                workspace.updateShop(id: existingID, name: name, aliases: aliases)
            } else {
                workspace.addShop(name: name)
            }
            dismiss()
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
            if let existingID {
                workspace.updateSeries(
                    id: existingID, shopID: shopID, name: name,
                    year: year, month: month, season: resolvedSeason)
            } else {
                workspace.addSeries(shopID: shopID, name: name, year: year, month: month)
            }
            dismiss()
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
            if let existingID {
                workspace.updateProduct(
                    id: existingID, shopID: shopID, seriesID: seriesID,
                    name: name, category: category)
            } else {
                workspace.addProduct(
                    shopID: shopID, seriesID: seriesID, name: name, category: category)
            }
            dismiss()
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

// MARK: - 绑定商品图

private struct BindImagesSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("绑定商品图").font(.headline)
                Text(workspace.catalog.products.first { $0.id == productID }?.name ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if workspace.catalog.assets.isEmpty {
                Text("还没有图片资源。先到「概览」导入商品图。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("勾选的图片会成为这个商品的图片列表，顺序与这里的列出顺序一致。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List {
                    ForEach(workspace.catalog.assets) { asset in
                        HStack(spacing: 8) {
                            Toggle(isOn: binding(for: asset.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.id).font(.callout)
                                    Text("\(assetTypeLabel(asset.type)) · "
                                         + "\(asset.width ?? 0)×\(asset.height ?? 0) · "
                                         + (asset.originalURL.isEmpty ? "无原图" : asset.originalURL))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(minHeight: 220)
            }

            HStack {
                Text("已选 \(selected.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("确定") {
                    // 按 assets 的列出顺序回写，保证「文件夹里的顺序 = 商品图顺序」
                    let ordered = workspace.catalog.assets
                        .map(\.id)
                        .filter { selected.contains($0) }
                    workspace.bindImages(ordered, toProduct: productID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selected = Set(workspace.catalog.products
                .first { $0.id == productID }?.images ?? [])
        }
    }

    private func binding(for assetID: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(assetID) },
            set: { isOn in
                if isOn { selected.insert(assetID) } else { selected.remove(assetID) }
            })
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
