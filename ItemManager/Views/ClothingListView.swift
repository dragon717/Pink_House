//
//  ClothingListView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation

struct ClothingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Brand.name) private var brands: [Brand]
    
    @State private var searchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var selectedTypes: Set<String> = []
    @State private var selectedColors: Set<String> = []
    @State private var selectedSizes: Set<String> = []
    @State private var selectedAccessories: Set<String> = []
    @State private var showingAddSheet = false
    @State private var itemToDelete: Clothing?
    @State private var showingDeleteAlert = false
    
    // Helper to extract unique values from comma-separated strings
    private func getAllValues(for keyPath: KeyPath<Clothing, String>) -> [String] {
        let allString = clothings.map { $0[keyPath: keyPath] }.joined(separator: ",")
        // Replace Chinese comma with English comma before splitting
        let normalizedString = allString.replacingOccurrences(of: "，", with: ",")
        return Array(Set(normalizedString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
    
    var filteredClothings: [Clothing] {
        clothings.filter { clothing in
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                // Optimization: Check simple string properties first
                matchesSearch = clothing.name.localizedCaseInsensitiveContains(searchText) ||
                    clothing.types.localizedCaseInsensitiveContains(searchText) ||
                    clothing.colors.localizedCaseInsensitiveContains(searchText) ||
                    clothing.sizes.localizedCaseInsensitiveContains(searchText) ||
                    clothing.accessories.localizedCaseInsensitiveContains(searchText) ||
                    (clothing.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (clothing.tags?.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ?? false)
            }
            
            let matchesTag: Bool
            if selectedTagIDs.isEmpty {
                matchesTag = true
            } else {
                let clothingTagIDs = Set(clothing.tags?.map { $0.id } ?? [])
                matchesTag = !selectedTagIDs.isDisjoint(with: clothingTagIDs)
            }
            
            let matchesBrand: Bool
            if selectedBrandIDs.isEmpty {
                matchesBrand = true
            } else {
                if let brand = clothing.brand {
                    matchesBrand = selectedBrandIDs.contains(brand.id)
                } else {
                    matchesBrand = false
                }
            }
            
            // Helper for splitting strings with support for both English and Chinese commas
            func splitValues(_ string: String) -> Set<String> {
                let normalized = string.replacingOccurrences(of: "，", with: ",")
                return Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }
            
            let matchesType: Bool = selectedTypes.isEmpty || !selectedTypes.isDisjoint(with: splitValues(clothing.types))
            
            let matchesColor: Bool = selectedColors.isEmpty || !selectedColors.isDisjoint(with: splitValues(clothing.colors))
            
            let matchesSize: Bool = selectedSizes.isEmpty || !selectedSizes.isDisjoint(with: splitValues(clothing.sizes))
            
            let matchesAccessory: Bool = selectedAccessories.isEmpty || !selectedAccessories.isDisjoint(with: splitValues(clothing.accessories))
            
            return matchesSearch && matchesTag && matchesBrand && matchesType && matchesColor && matchesSize && matchesAccessory
        }
    }
    
    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    content
                        .navigationTitle("少女衣柜")
                }
            } else {
                NavigationSplitView {
                    content
                        .navigationTitle("少女衣柜")
                } detail: {
                    ZStack {
                        LiquidBackground()
                        Text("请选择一件裙子")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                ClothingEditView(clothing: nil)
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { itemToDelete = nil }
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    modelContext.delete(item)
                }
                itemToDelete = nil
            }
        } message: {
            Text("确定要删除这件裙子吗？此操作无法撤销。")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ZStack {
            LiquidBackground()
            
            List {
                ForEach(filteredClothings) { clothing in
                    NavigationLink {
                        ClothingDetailView(clothing: clothing)
                    } label: {
                        ClothingRow(clothing: clothing)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: deleteItems)
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "搜索名称、品牌、标签、属性...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Menu {
                            Menu {
                                Button(role: .destructive) {
                                    selectedTagIDs.removeAll()
                                } label: {
                                    Label("清除筛选", systemImage: "xmark.circle")
                                }
                                
                                ForEach(tags) { tag in
                                    Button {
                                        if selectedTagIDs.contains(tag.id) {
                                            selectedTagIDs.remove(tag.id)
                                        } else {
                                            selectedTagIDs.removeAll()
                                            selectedTagIDs.insert(tag.id)
                                        }
                                    } label: {
                                        HStack {
                                            Text(tag.name)
                                            if selectedTagIDs.contains(tag.id) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                let selectedTagName = selectedTagIDs.first.flatMap { id in tags.first(where: { $0.id == id })?.name }
                                Label(selectedTagName ?? "标签", systemImage: selectedTagIDs.isEmpty ? "tag" : "tag.fill")
                            }
                            
                            Menu {
                                Button(role: .destructive) {
                                    selectedBrandIDs.removeAll()
                                } label: {
                                    Label("清除筛选", systemImage: "xmark.circle")
                                }
                                
                                ForEach(brands) { brand in
                                    Button {
                                        if selectedBrandIDs.contains(brand.id) {
                                            selectedBrandIDs.remove(brand.id)
                                        } else {
                                            selectedBrandIDs.removeAll()
                                            selectedBrandIDs.insert(brand.id)
                                        }
                                    } label: {
                                        HStack {
                                            Text(brand.name)
                                            if selectedBrandIDs.contains(brand.id) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                let selectedBrandName = selectedBrandIDs.first.flatMap { id in brands.first(where: { $0.id == id })?.name }
                                Label(selectedBrandName ?? "品牌", systemImage: selectedBrandIDs.isEmpty ? "bag" : "bag.fill")
                            }
                            
                            // Types Filter
                            Menu {
                                Button(role: .destructive) {
                                    selectedTypes.removeAll()
                                } label: {
                                    Label("清除筛选", systemImage: "xmark.circle")
                                }
                                
                                ForEach(getAllValues(for: \.types), id: \.self) { type in
                                    Button {
                                        if selectedTypes.contains(type) {
                                            selectedTypes.remove(type)
                                        } else {
                                            selectedTypes.removeAll()
                                            selectedTypes.insert(type)
                                        }
                                    } label: {
                                        HStack {
                                            Text(type)
                                            if selectedTypes.contains(type) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(selectedTypes.first ?? "类型", systemImage: selectedTypes.isEmpty ? "tshirt" : "tshirt.fill")
                            }
                            
                            // Colors Filter
                            Menu {
                                Button(role: .destructive) {
                                    selectedColors.removeAll()
                                } label: {
                                    Label("清除筛选", systemImage: "xmark.circle")
                                }
                                
                                ForEach(getAllValues(for: \.colors), id: \.self) { color in
                                    Button {
                                        if selectedColors.contains(color) {
                                            selectedColors.remove(color)
                                        } else {
                                            selectedColors.removeAll()
                                            selectedColors.insert(color)
                                        }
                                    } label: {
                                        HStack {
                                            Text(color)
                                            if selectedColors.contains(color) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(selectedColors.first ?? "颜色", systemImage: selectedColors.isEmpty ? "paintpalette" : "paintpalette.fill")
                            }
                            
                            // Sizes Filter
                            Menu {
                                Button(role: .destructive) {
                                    selectedSizes.removeAll()
                                } label: {
                                    Label("清除筛选", systemImage: "xmark.circle")
                                }
                                
                                ForEach(getAllValues(for: \.sizes), id: \.self) { size in
                                    Button {
                                        if selectedSizes.contains(size) {
                                            selectedSizes.remove(size)
                                        } else {
                                            selectedSizes.removeAll()
                                            selectedSizes.insert(size)
                                        }
                                    } label: {
                                        HStack {
                                            Text(size)
                                            if selectedSizes.contains(size) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(selectedSizes.first ?? "尺码", systemImage: selectedSizes.isEmpty ? "ruler" : "ruler.fill")
                            }
                            
                            // Accessories Filter
                            Menu {
                                Button(role: .destructive) {
                                    selectedAccessories.removeAll()
                                } label: {
                                    Label("清除筛选", systemImage: "xmark.circle")
                                }
                                
                                ForEach(getAllValues(for: \.accessories), id: \.self) { accessory in
                                    Button {
                                        if selectedAccessories.contains(accessory) {
                                            selectedAccessories.remove(accessory)
                                        } else {
                                            selectedAccessories.removeAll()
                                            selectedAccessories.insert(accessory)
                                        }
                                    } label: {
                                        HStack {
                                            Text(accessory)
                                            if selectedAccessories.contains(accessory) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label(selectedAccessories.first ?? "小物", systemImage: "sparkles")
                            }
                        } label: {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                                .symbolVariant(selectedTagIDs.isEmpty && selectedBrandIDs.isEmpty && selectedTypes.isEmpty && selectedColors.isEmpty && selectedSizes.isEmpty && selectedAccessories.isEmpty ? .none : .fill)
                        }
                        
                        Button(action: { showingAddSheet = true }) {
                            Label("新增", systemImage: "plus")
                        }
                    }
                }
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        if let index = offsets.first {
            itemToDelete = filteredClothings[index]
            showingDeleteAlert = true
        }
    }
}

struct ClothingRow: View {
    let clothing: Clothing
    
    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                // Thumbnail
                if let firstPath = clothing.imagePaths.first,
                   let image = ImageManager.shared.loadImage(fileName: firstPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "tshirt")
                                .foregroundStyle(.pink.opacity(0.5))
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(clothing.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack {
                        if !clothing.types.isEmpty {
                            Text(clothing.types)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.pink.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    if let tags = clothing.tags, !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags.prefix(3)) { tag in
                                Text("#\(tag.name)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if tags.count > 3 {
                                Text("...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("¥\(clothing.price, format: .number.precision(.fractionLength(2)))")
                        .font(.subheadline)
                        .bold()
                    
                    if clothing.stock > 0 {
                        Text("库存: \(clothing.stock)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
