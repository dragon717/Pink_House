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
    @State private var selectedTag: Tag?
    @State private var showingAddSheet = false
    
    var filteredClothings: [Clothing] {
        clothings.filter { clothing in
            let matchesSearch = searchText.isEmpty || 
                clothing.name.localizedCaseInsensitiveContains(searchText) ||
                clothing.types.localizedCaseInsensitiveContains(searchText)
            
            let matchesTag: Bool
            if let targetTag = selectedTag {
                matchesTag = clothing.tags?.contains(where: { $0.id == targetTag.id }) ?? false
            } else {
                matchesTag = true
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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("全部标签", action: { selectedTag = nil })
                            ForEach(tags) { tag in
                                Button(action: { selectedTag = tag }) {
                                    Label {
                                        Text(tag.name)
                                    } icon: {
                                        Image(systemName: "circle.fill")
                                            .foregroundStyle(Color(hex: tag.colorHex))
                                    }
                                }
                            }
                        } label: {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                                .symbolVariant(selectedTag != nil ? .fill : .none)
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddSheet = true }) {
                            Label("新增", systemImage: "plus")
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
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredClothings[index])
            }
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
