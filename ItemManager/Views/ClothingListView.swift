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
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Brand.name) private var brands: [Brand]
    
    @State private var searchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var showingAddSheet = false
    @State private var itemToDelete: Clothing?
    @State private var showingDeleteAlert = false
    
    var filteredClothings: [Clothing] {
        clothings.filter { clothing in
            let matchesSearch = searchText.isEmpty || 
                clothing.name.localizedCaseInsensitiveContains(searchText) ||
                clothing.types.localizedCaseInsensitiveContains(searchText)
            
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
            
            return matchesSearch && matchesTag && matchesBrand
        }
    }
    
    var body: some View {
        NavigationSplitView {
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
                .searchable(text: $searchText, prompt: "搜索名称或款式")
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
                                                selectedTagIDs.insert(tag.id)
                                            }
                                        } label: {
                                            HStack {
                                                Text(tag.name)
                                                if selectedTagIDs.contains(tag.id) {
                                                    Image(systemName: "checkmark")
                                                } else {
                                                    Image(systemName: "circle.fill")
                                                        .foregroundStyle(Color(hex: tag.colorHex))
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label("全部标签", systemImage: "tag")
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
                                                selectedBrandIDs.insert(brand.id)
                                            }
                                        } label: {
                                            HStack {
                                                Text(brand.name)
                                                if selectedBrandIDs.contains(brand.id) {
                                                    Image(systemName: "checkmark")
                                                } else {
                                                    Image(systemName: "circle.fill")
                                                        .foregroundStyle(Color(hex: brand.colorHex))
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label("全部品牌", systemImage: "bag")
                                }
                            } label: {
                                Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                                    .symbolVariant(selectedTagIDs.isEmpty && selectedBrandIDs.isEmpty ? .none : .fill)
                            }
                            
                            Button(action: { showingAddSheet = true }) {
                                Label("新增", systemImage: "plus")
                            }
                        }
                    }
                }
            }
            .navigationTitle("少女衣柜")
        } detail: {
            ZStack {
                LiquidBackground()
                Text("请选择一件裙子")
                    .foregroundStyle(.secondary)
                    .font(.title2)
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
