//
//  ClothingListView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

struct ClothingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    
    @State private var searchText = ""
    @State private var selectedStatus: ClothingStatus?
    @State private var showingAddSheet = false
    
    var filteredClothings: [Clothing] {
        clothings.filter { clothing in
            let matchesSearch = searchText.isEmpty || 
                clothing.name.localizedCaseInsensitiveContains(searchText) ||
                clothing.types.localizedCaseInsensitiveContains(searchText)
            
            let matchesStatus = selectedStatus == nil || clothing.status == selectedStatus
            
            return matchesSearch && matchesStatus
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
                            Button("全部", action: { selectedStatus = nil })
                            ForEach(ClothingStatus.allCases) { status in
                                Button(status.rawValue, action: { selectedStatus = status })
                            }
                        } label: {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                                .symbolVariant(selectedStatus != nil ? .fill : .none)
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddSheet = true }) {
                            Label("新增", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("少女心愿")
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
                // Thumbnail Placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        if let firstPath = clothing.imagePaths.first {
                            // In real app, load image from path
                            Image(systemName: "photo")
                        } else {
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
                        
                        Text(clothing.status.rawValue)
                            .font(.caption)
                            .foregroundStyle(clothing.status == .onShelf ? .green : .gray)
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
