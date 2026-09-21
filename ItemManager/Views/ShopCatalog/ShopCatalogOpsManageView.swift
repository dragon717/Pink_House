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

struct ShopCatalogOpsManageView: View {
    @ObservedObject private var store = ShopCatalogStore.shared
    @Environment(\.modelContext) private var modelContext
    @State private var toast: String?
    @State private var actionError: String?
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var hudLetter: String?

    /// 修掉首尾空白后的搜索词
    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// 搜索过滤后的店家（名称或别名命中）
    private var filteredShops: [CatalogShop] {
        let shops = store.catalog?.shops ?? []
        return shops.filter {
            AZIndexGrouping.matches(name: $0.name, aliases: $0.aliases, query: trimmedQuery)
        }
    }

    /// A-Z 分组（含中文转拼音首字母）
    private var shopGroups: [(letter: String, items: [CatalogShop])] {
        AZIndexGrouping.groups(filteredShops) { $0.name }
    }

    var body: some View {
        // 搜索栏在 VStack 上层、List 之外 → 常驻固定，不随内容滚动
        VStack(spacing: 0) {
            AZPinnedSearchBar(text: $searchText,
                              focused: $searchFieldFocused,
                              placeholder: "搜索店家名称或别名")
            ScrollViewReader { proxy in
                List {
                    if trimmedQuery.isEmpty {
                        // 店家：A-Z 分组 + 右侧索引滑块
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
                        seriesSection
                        productSection
                    } else {
                        if filteredShops.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            Section("店家（\(filteredShops.count)）") {
                                ForEach(filteredShops) { shop in
                                    ShopManageRow(
                                        shop: shop,
                                        store: store,
                                        modelContext: modelContext,
                                        toast: $toast,
                                        actionError: $actionError
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
                .overlay(alignment: .trailing) {
                    // 有搜索词时隐藏索引（符合系统搜索交互）
                    if trimmedQuery.isEmpty, !shopGroups.isEmpty {
                        AZIndexRail(letters: shopGroups.map(\.letter),
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

    // MARK: 系列

    private var seriesSection: some View {
        Section("系列（\(store.catalog?.series.count ?? 0)）") {
            ForEach(store.catalog?.series ?? []) { series in
                SeriesManageRow(
                    series: series,
                    store: store,
                    modelContext: modelContext,
                    toast: $toast,
                    actionError: $actionError
                )
            }
        }
    }

    // MARK: 商品

    private var productSection: some View {
        Section("商品（\(store.catalog?.products.count ?? 0)，长按名称进入编辑）") {
            ForEach(store.catalog?.products ?? []) { product in
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
                Button("深度编辑（图片/配色尺码/尺码表/销售记录）") {
                    showsDeepEdit = true
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
        do {
            try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.series)
            toast = "已更新系列「\(updated.name)」，下属商品自动跟随"
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
