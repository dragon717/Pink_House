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

    var body: some View {
        Form {
            shopSection
            seriesSection
            productSection
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

    // MARK: 店家

    private var shopSection: some View {
        Section("店家（\(store.catalog?.shops.count ?? 0)）") {
            ForEach(store.catalog?.shops ?? []) { shop in
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
    @State private var draftName = ""
    @State private var draftAliases = ""

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
                Button("编辑名称/别名") {
                    draftName = shop.name
                    draftAliases = shop.aliases.joined(separator: "，")
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
        .alert("编辑店家", isPresented: $showsEdit) {
            TextField("名称", text: $draftName)
            TextField("别名（逗号分隔）", text: $draftAliases)
            Button("保存") {
                var updated = shop
                updated.name = draftName.trimmingCharacters(in: .whitespaces)
                updated.aliases = draftAliases
                    .components(separatedBy: CharacterSet(charactersIn: "，,、"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                do {
                    try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.shops)
                    toast = "已更新店家「\(updated.name)」，下属系列/商品同步生效"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
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
    @State private var draftName = ""
    @State private var draftYear = ""
    @State private var draftSeason = ""

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
                Button("编辑名称/年份/季节") {
                    draftName = series.name
                    draftYear = series.year.map(String.init) ?? ""
                    draftSeason = series.season ?? ""
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
        .alert("编辑系列", isPresented: $showsEdit) {
            TextField("名称", text: $draftName)
            TextField("年份", text: $draftYear)
                .keyboardType(.numberPad)
            TextField("季节（如 冬）", text: $draftSeason)
            Button("保存") {
                var updated = series
                updated.name = draftName.trimmingCharacters(in: .whitespaces)
                updated.year = Int(draftYear.trimmingCharacters(in: .whitespaces))
                let season = draftSeason.trimmingCharacters(in: .whitespaces)
                updated.season = season.isEmpty ? nil : season
                do {
                    try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.series)
                    toast = "已更新系列「\(updated.name)」"
                } catch { actionError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
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
                Button("编辑名称/分类") {
                    draftName = product.name
                    draftCategory = product.category
                    showsEdit = true
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
