//
//  RecycleBinView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/31/26.
//

import SwiftUI
import SwiftData

struct RecycleBinView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Wardrobe Query
    @Query(filter: #Predicate<Clothing> { $0.deletedAt != nil }, sort: \Clothing.deletedAt, order: .reverse)
    private var deletedClothings: [Clothing]
    
    // OOTD Queries
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt != nil }, sort: \BookGroup.deletedAt, order: .reverse)
    private var deletedBooks: [BookGroup]
    
    @Query(filter: #Predicate<Outfit> { $0.deletedAt != nil }, sort: \Outfit.deletedAt, order: .reverse)
    private var allDeletedOutfits: [Outfit]
    
    // Filter out outfits that belong to deleted books (to avoid duplicates in the list)
    var isolatedDeletedOutfits: [Outfit] {
        allDeletedOutfits.filter { $0.book == nil || $0.book?.deletedAt == nil }
    }
    
    @State private var selectedTab: Int = 0 // 0: 衣橱, 1: 手帐
    @State private var selectedItems: Set<UUID> = [] // For Wardrobe
    @State private var editMode: EditMode = .inactive
    
    // Alerts
    @State private var itemToDelete: Any? // Can be Clothing, BookGroup, or Outfit
    @State private var showingDeleteAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var showingRestoreAllAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("分类", selection: $selectedTab) {
                Text("衣橱").tag(0)
                Text("手帐").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedTab == 0 {
                wardrobeList
            } else {
                ootdList
            }
        }
        .navigationTitle("回收站")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            LiquidBackground()
        }
        .alert("彻底删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { itemToDelete = nil }
            Button("删除", role: .destructive) {
                if let clothing = itemToDelete as? Clothing {
                    permanentlyDeleteClothing(clothing)
                } else if let book = itemToDelete as? BookGroup {
                    permanentlyDeleteBook(book)
                } else if let outfit = itemToDelete as? Outfit {
                    permanentlyDeleteOutfit(outfit)
                }
                itemToDelete = nil
            }
        } message: {
            Text("确定要彻底删除吗？此操作无法撤销。")
        }
    }
    
    // MARK: - Wardrobe View
    
    var wardrobeList: some View {
        List(selection: $selectedItems) {
            if deletedClothings.isEmpty {
                ContentUnavailableView(
                    "回收站是空的",
                    systemImage: "trash",
                    description: Text("删除的裙子会出现在这里")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(deletedClothings) { clothing in
                    ClothingRowBrief(clothing: clothing)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                restoreClothing(clothing)
                            } label: {
                                Label("恢复", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                itemToDelete = clothing
                                showingDeleteAlert = true
                            } label: {
                                Label("彻底删除", systemImage: "trash.slash")
                            }
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - OOTD View
    
    var ootdList: some View {
        List {
            if deletedBooks.isEmpty && isolatedDeletedOutfits.isEmpty {
                ContentUnavailableView(
                    "回收站是空的",
                    systemImage: "book.closed",
                    description: Text("删除的手帐和书页会出现在这里")
                )
                .listRowBackground(Color.clear)
            } else {
                // Deleted Books Section
                if !deletedBooks.isEmpty {
                    Section("手帐本") {
                        ForEach(deletedBooks) { book in
                            DeletedBookRow(book: book, onRestore: {
                                restoreBook(book)
                            }, onDelete: {
                                itemToDelete = book
                                showingDeleteAlert = true
                            })
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                
                // Deleted Pages Section
                if !isolatedDeletedOutfits.isEmpty {
                    Section("单独删除的书页") {
                        ForEach(isolatedDeletedOutfits) { outfit in
                            DeletedOutfitRow(outfit: outfit, onRestore: {
                                restoreOutfit(outfit)
                            }, onDelete: {
                                itemToDelete = outfit
                                showingDeleteAlert = true
                            })
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Actions
    
    private func restoreClothing(_ clothing: Clothing) {
        withAnimation {
            clothing.isDeleted = false
            clothing.deletedAt = nil
        }
    }
    
    private func permanentlyDeleteClothing(_ clothing: Clothing) {
        withAnimation {
            NotificationManager.shared.cancelNotification(for: clothing)
            modelContext.delete(clothing)
        }
    }
    
    private func restoreBook(_ book: BookGroup) {
        withAnimation {
            book.isDeleted = false
            book.deletedAt = nil
            // Restore all pages in this book
            for page in book.pages {
                page.isDeleted = false
                page.deletedAt = nil
            }
        }
    }
    
    private func permanentlyDeleteBook(_ book: BookGroup) {
        withAnimation {
            // Delete snapshot files for all pages
            for page in book.pages {
                if let path = page.snapshotPath {
                    ImageManager.shared.deleteImage(fileName: path, context: modelContext)
                }
            }
            modelContext.delete(book)
        }
    }
    
    private func restoreOutfit(_ outfit: Outfit) {
        withAnimation {
            outfit.isDeleted = false
            outfit.deletedAt = nil
        }
    }
    
    private func permanentlyDeleteOutfit(_ outfit: Outfit) {
        withAnimation {
            if let path = outfit.snapshotPath {
                ImageManager.shared.deleteImage(fileName: path, context: modelContext)
            }
            modelContext.delete(outfit)
        }
    }
}

struct DeletedBookRow: View {
    let book: BookGroup
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        
                        Text(book.title)
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(book.pages.count) 页")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                // Actions
                HStack(spacing: 16) {
                    Button(action: onRestore) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                    }
                }
            }
            
            if isExpanded {
                ForEach(book.pages) { page in
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 28)
                        
                        Text(page.note.isEmpty ? "未命名书页" : page.note)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        if let snapshotPath = page.snapshotPath,
                           let uiImage = ImageManager.shared.loadImage(fileName: snapshotPath) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        .cornerRadius(12)
    }
}

struct DeletedOutfitRow: View {
    let outfit: Outfit
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            if let snapshotPath = outfit.snapshotPath,
               let uiImage = ImageManager.shared.loadImage(fileName: snapshotPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            } else {
                Image(systemName: "tshirt")
                    .frame(width: 40, height: 40)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading) {
                Text(outfit.note.isEmpty ? "未命名书页" : outfit.note)
                    .font(.body)
                Text(outfit.deletedAt?.formatted() ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(.blue)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        .cornerRadius(12)
    }
}
