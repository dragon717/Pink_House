//
//  ShopCatalogCategoryManageSheet.swift
//  ItemManager
//
//  分类管理（2026-09-24 需求）：运营可新增 / 修改 / 删除自定义分类。
//
//  口径：
//    · 固定品类（ShopCatalogStore.canonicalCategoryOrder）是系统口径——品类参与
//      加购主物判定与类型分组，**不可改名、不可删除**（列表中标「系统内置」）；
//    · 自定义分类存 UserDefaults（ShopCatalogStore.customCategories），
//      新增即追加、改名同步迁移使用中的商品与草稿、删除只从候选移除
//      （已使用该分类的商品字段保留原值，不受影响）；
//    · 删除必须二次确认（防误删），确认文案说明有多少商品 / 草稿仍在使用；
//    · 需要运营白名单（写覆盖层 / 草稿的接口自带校验）。
//

import SwiftUI

struct ShopCatalogCategoryManageSheet: View {
    @ObservedObject private var store = ShopCatalogStore.shared
    @ObservedObject private var draftStore = ShopCatalogDraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    @State private var newCategoryName = ""
    @State private var customCategories: [String] = []
    /// 待改名的自定义分类（alert TextField 承接新名）
    @State private var renamingCategory: String?
    @State private var renameText = ""
    /// 待删除的自定义分类（二次确认）
    @State private var pendingDeleteCategory: String?
    @State private var showsDeleteConfirm = false
    @State private var errorText: String?
    @State private var toast: String?

    /// 固定品类（系统内置，不可改删）
    private var builtinCategories: [String] {
        ShopCatalogStore.canonicalCategoryOrder
    }

    var body: some View {
        NavigationStack {
            Form {
                addSection
                builtinSection
                customSection
            }
            .navigationTitle("管理分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                store.loadFromBundleIfNeeded()
                customCategories = ShopCatalogStore.customCategories
            }
            .alert("重命名分类", isPresented: Binding(
                get: { renamingCategory != nil },
                set: { if !$0 { renamingCategory = nil } }
            )) {
                TextField("新名称", text: $renameText)
                Button("保存") { commitRename() }
                Button("取消", role: .cancel) { renamingCategory = nil }
            } message: {
                Text("使用「\(renamingCategory ?? "")」分类的商品与草稿会一并更新为新名称。")
            }
            .confirmationDialog(deleteConfirmTitle,
                                isPresented: $showsDeleteConfirm,
                                titleVisibility: .visible) {
                Button("删除分类", role: .destructive) { performDelete() }
                Button("取消", role: .cancel) { pendingDeleteCategory = nil }
            } message: {
                Text(deleteImpactText)
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
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
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            await MainActor.run { self.toast = nil }
                        }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 新增

    private var addSection: some View {
        Section {
            HStack {
                TextField("新分类名称（如：斗篷）", text: $newCategoryName)
                    .onSubmit(addCategory)
                Button("添加") { addCategory() }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("新增分类")
        } footer: {
            Text("新增后立即出现在所有分类选择列表中，并参与商品类型分组。")
        }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !ShopCatalogStore.categoryCandidates.contains(name) else {
            errorText = "分类「\(name)」已存在"
            return
        }
        var custom = ShopCatalogStore.customCategories
        custom.append(name)
        ShopCatalogStore.customCategories = custom
        customCategories = ShopCatalogStore.customCategories
        newCategoryName = ""
        toast = "已添加分类「\(name)」"
    }

    // MARK: 固定分类（系统内置）

    private var builtinSection: some View {
        Section {
            ForEach(builtinCategories, id: \.self) { category in
                HStack {
                    Text(category)
                        .foregroundStyle(themeManager.primaryTextColor)
                    Spacer()
                    Text("系统内置")
                        .font(.system(size: 11))
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }
            }
        } header: {
            Text("内置分类（不可修改）")
        } footer: {
            Text("内置分类参与加购主物判定与类型分组，为保持数据一致不允许改名或删除。")
        }
    }

    // MARK: 自定义分类（可改名 / 可删除）

    private var customSection: some View {
        Section {
            if customCategories.isEmpty {
                Text("暂无自定义分类。用上方「新增分类」添加。")
                    .font(.system(size: 12))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            ForEach(customCategories, id: \.self) { category in
                HStack {
                    Text(category)
                        .foregroundStyle(themeManager.primaryTextColor)
                    Spacer()
                    Button("改名") {
                        renamingCategory = category
                        renameText = category
                    }
                    .font(.system(size: 13))
                    Button(role: .destructive) {
                        pendingDeleteCategory = category
                        showsDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("删除分类 \(category)")
                }
            }
        } header: {
            Text("自定义分类")
        } footer: {
            Text("删除只把分类从候选列表移除；已使用该分类的商品记录保持不变。")
        }
    }

    // MARK: 使用统计（确认文案口径）

    /// 使用某分类的已发布商品数（含已归档——它们仍占着这个分类字段）
    private func publishedProductCount(of category: String) -> Int {
        store.catalog?.products.filter { $0.category == category }.count ?? 0
    }

    /// 使用某分类的草稿数
    private func draftCount(of category: String) -> Int {
        draftStore.drafts.filter { $0.category == category }.count
    }

    private var deleteConfirmTitle: String {
        "删除分类「\(pendingDeleteCategory ?? "")」？"
    }

    private var deleteImpactText: String {
        guard let category = pendingDeleteCategory else { return "" }
        let productCount = publishedProductCount(of: category)
        let draftCount = draftCount(of: category)
        var lines: [String] = ["该操作需要二次确认，防止误删。"]
        lines.append("删除后「\(category)」将从所有分类选择列表中移除。")
        if productCount > 0 {
            lines.append("有 \(productCount) 件已发布商品仍在使用该分类——它们的分类字段将保持「\(category)」不变，不受影响。")
        }
        if draftCount > 0 {
            lines.append("有 \(draftCount) 条草稿仍在使用该分类，同样保持不变。")
        }
        if productCount == 0 && draftCount == 0 {
            lines.append("当前没有商品或草稿使用该分类。")
        }
        return lines.joined(separator: "\n")
    }

    private func performDelete() {
        guard let category = pendingDeleteCategory else { return }
        pendingDeleteCategory = nil
        ShopCatalogStore.customCategories = ShopCatalogStore.customCategories.filter { $0 != category }
        customCategories = ShopCatalogStore.customCategories
        toast = "已删除分类「\(category)」"
    }

    // MARK: 改名（词表 + 使用中的商品 / 草稿一并迁移）

    private func commitRename() {
        guard let old = renamingCategory else { return }
        renamingCategory = nil
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            errorText = "分类名称不能为空"
            return
        }
        guard newName != old else { return }
        guard !ShopCatalogStore.categoryCandidates.contains(newName) else {
            errorText = "分类「\(newName)」已存在"
            return
        }
        // 1. 词表改名
        var custom = ShopCatalogStore.customCategories
        guard let index = custom.firstIndex(of: old) else {
            errorText = "分类「\(old)」不存在或已被删除"
            return
        }
        custom[index] = newName
        ShopCatalogStore.customCategories = custom
        customCategories = ShopCatalogStore.customCategories

        // 2. 使用中的已发布商品同步迁移（同 id 整体替换覆盖层）
        var migratedProducts = 0
        if let catalog = store.catalog {
            for product in catalog.products where product.category == old {
                var updated = product
                updated.category = newName
                do {
                    try ShopCatalogDraftStore.upsertEntity(updated, keyPath: \.products)
                    migratedProducts += 1
                } catch {
                    errorText = "商品「\(product.name)」分类更新失败：\(error.localizedDescription)"
                    return
                }
            }
        }

        // 3. 使用中的草稿同步迁移（整批一次落盘）
        var migratedDrafts = 0
        let affectedDrafts = draftStore.drafts.filter { $0.category == old }
        if !affectedDrafts.isEmpty {
            var updatedDrafts: [CatalogProductDraft] = []
            for var draft in affectedDrafts {
                draft.category = newName
                updatedDrafts.append(draft)
            }
            do {
                try draftStore.upsert(updatedDrafts)
                migratedDrafts = updatedDrafts.count
            } catch {
                errorText = "草稿分类更新失败：\(error.localizedDescription)"
                return
            }
        }

        var summary = "已重命名为「\(newName)」"
        if migratedProducts > 0 { summary += "，同步更新 \(migratedProducts) 件商品" }
        if migratedDrafts > 0 { summary += "、\(migratedDrafts) 条草稿" }
        toast = summary
    }
}
