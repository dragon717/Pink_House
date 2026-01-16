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
    
    @State private var searchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
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
            
            return matchesSearch && matchesTag
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
                        HStack {
                            Menu {
                                Button(action: { selectedTagIDs.removeAll() }) {
                                    if selectedTagIDs.isEmpty {
                                        Text("全部")
                                    } else {
                                        Label("全部", systemImage: "xmark.circle")
                                    }
                                }
                                
                                ForEach(tags) { tag in
                                    Button(action: { toggleTag(tag) }) {
                                        if selectedTagIDs.contains(tag.id) {
                                            Label(tag.name, systemImage: "checkmark")
                                        } else {
                                            Label {
                                                Text(tag.name)
                                            } icon: {
                                                Image(systemName: "circle.fill")
                                                    .foregroundStyle(Color(hex: tag.colorHex))
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                                    .symbolVariant(!selectedTagIDs.isEmpty ? .fill : .none)
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
                ClothingDetailView(clothing: nil)
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
    
    private func toggleTag(_ tag: Tag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
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
