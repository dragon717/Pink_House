//
//  RecycleBinView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
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
    
    // Space OOTD Queries
    @Query(filter: #Predicate<SpaceBookGroup> { $0.deletedAt != nil }, sort: \SpaceBookGroup.deletedAt, order: .reverse)
    private var deletedSpaceBooks: [SpaceBookGroup]
    
    @Query(filter: #Predicate<SpaceOutfit> { $0.deletedAt != nil }, sort: \SpaceOutfit.deletedAt, order: .reverse)
    private var allDeletedSpaceOutfits: [SpaceOutfit]
    
    // Model3D Query
    @Query(filter: #Predicate<Model3D> { $0.isDeleted == true }, sort: \Model3D.deletedAt, order: .reverse)
    private var deletedModel3Ds: [Model3D]
    
    // Perler Bead Pattern Query
    @Query(filter: #Predicate<PerlerBeadPattern> { $0.isDeleted == true }, sort: \PerlerBeadPattern.deletedAt, order: .reverse)
    private var deletedPatterns: [PerlerBeadPattern]
    
    // Filter out outfits that belong to deleted books (to avoid duplicates in the list)
    var isolatedDeletedOutfits: [Outfit] {
        allDeletedOutfits.filter { $0.book == nil || $0.book?.deletedAt == nil }
    }
    
    var isolatedDeletedSpaceOutfits: [SpaceOutfit] {
        allDeletedSpaceOutfits.filter { $0.book == nil || $0.book?.deletedAt == nil }
    }
    
    @State private var selectedTab: Int
    @State private var selectedSubTab: Int = 0 // 0=平面, 1=空间, 2=模型 (用于手帐子页签)
    @State private var selectedItems: Set<UUID> = [] // Shared selection
    @State private var editMode: EditMode = .inactive
    
    // Alerts
    @State private var itemToDelete: Any? // Can be Clothing, BookGroup, Outfit, Model3D, or PerlerBeadPattern
    @State private var showingDeleteAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var showingRestoreAllAlert = false
    @State private var showingBatchDeleteAlert = false
    @State private var showingBatchRestoreAlert = false
    
    // Recovery/Delete from Trash
    @State private var showingRestoreAlert = false
    
    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    // Tab indices: 0=Wardrobe, 1=手帐(包含平面/空间/模型), 2=PerlerBeads
    
    var body: some View {
        contentView
            .environment(\.editMode, $editMode)
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .background {
                LiquidBackground()
            }
            .toolbar { trailingToolbar }
            .onChange(of: selectedTab) { handleTabChange() }
            .onChange(of: selectedSubTab) { handleSubTabChange() }
            .alert("彻底删除", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { itemToDelete = nil }
                Button("删除", role: .destructive, action: handleDelete)
            } message: {
                Text("确定要彻底删除吗？此操作无法撤销。")
            }
            .alert("全部删除", isPresented: $showingDeleteAllAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive, action: deleteAll)
            } message: {
                Text("确定要清空当前列表吗？此操作无法撤销。")
            }
            .alert("全部恢复", isPresented: $showingRestoreAllAlert) {
                Button("取消", role: .cancel) { }
                Button("恢复", action: restoreAll)
            } message: {
                Text("确定要恢复当前列表的所有项目吗？")
            }
            .alert("批量删除", isPresented: $showingBatchDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteSelected()
                    editMode = .inactive
                }
            } message: {
                Text("确定要删除选中的 \(selectedItems.count) 个项目吗？此操作无法撤销。")
            }
            .alert("批量恢复", isPresented: $showingBatchRestoreAlert) {
                Button("取消", role: .cancel) { }
                Button("恢复") {
                    restoreSelected()
                    editMode = .inactive
                }
            } message: {
                Text("确定要恢复选中的 \(selectedItems.count) 个项目吗？")
            }
            .alert("恢复", isPresented: $showingRestoreAlert) {
                Button("取消", role: .cancel) { itemToDelete = nil }
                Button("恢复", action: handleRestore)
            } message: {
                Text("确定要恢复这个项目吗？")
            }
    }
    
    private var contentView: some View {
        VStack(spacing: 0) {
            mainPicker
            
            if selectedTab == 1 {
                subTabPicker
            }
            
            listContent
        }
    }
    
    private var mainPicker: some View {
        Picker("分类", selection: $selectedTab) {
            Text("衣橱").tag(0)
            Text("手帐").tag(1)
            Text("拼豆").tag(2)
        }
        .pickerStyle(.segmented)
        .padding()
    }
    
    private var subTabPicker: some View {
        Picker("手帐类型", selection: $selectedSubTab) {
            Text("平面").tag(0)
            Text("空间").tag(1)
            Text("模型").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var listContent: some View {
        Group {
            if selectedTab == 0 {
                wardrobeList
            } else if selectedTab == 1 {
                if selectedSubTab == 0 {
                    ootdList
                } else if selectedSubTab == 1 {
                    spaceOOTDList
                } else {
                    model3DList
                }
            } else {
                perlerBeadsList
            }
        }
    }
    
    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if editMode == .active {
                editModeToolbar
            } else {
                normalToolbar
            }
        }
    }
    
    private var editModeToolbar: some View {
        HStack(spacing: 16) {
            Button {
                showingBatchRestoreAlert = true
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(selectedItems.isEmpty)
            
            Button {
                showingBatchDeleteAlert = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedItems.isEmpty)
            .foregroundStyle(.red)
            
            Button("完成") {
                withAnimation {
                    editMode = .inactive
                    selectedItems.removeAll()
                }
            }
            .fontWeight(.bold)
        }
    }
    
    private var normalToolbar: some View {
        Menu {
            Button {
                withAnimation {
                    editMode = .active
                }
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            
            Button {
                showingRestoreAllAlert = true
            } label: {
                Label("全部恢复", systemImage: "arrow.uturn.backward.circle")
            }
            
            Button(role: .destructive) {
                showingDeleteAllAlert = true
            } label: {
                Label("全部删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private func handleTabChange() {
        editMode = .inactive
        selectedItems.removeAll()
        if selectedTab != 1 {
            selectedSubTab = 0
        }
    }
    
    private func handleSubTabChange() {
        editMode = .inactive
        selectedItems.removeAll()
    }
    
    private func handleDelete() {
        if let clothing = itemToDelete as? Clothing {
            permanentlyDeleteClothing(clothing)
        } else if let book = itemToDelete as? BookGroup {
            permanentlyDeleteBook(book)
        } else if let outfit = itemToDelete as? Outfit {
            permanentlyDeleteOutfit(outfit)
        } else if let spaceBook = itemToDelete as? SpaceBookGroup {
            permanentlyDeleteSpaceBook(spaceBook)
        } else if let spaceOutfit = itemToDelete as? SpaceOutfit {
            permanentlyDeleteSpaceOutfit(spaceOutfit)
        } else if let model3D = itemToDelete as? Model3D {
            permanentlyDeleteModel3D(model3D)
        } else if let pattern = itemToDelete as? PerlerBeadPattern {
            permanentlyDeletePerlerPattern(pattern)
        }
        itemToDelete = nil
    }
    
    private func handleRestore() {
        if let clothing = itemToDelete as? Clothing {
            restoreClothing(clothing)
        } else if let book = itemToDelete as? BookGroup {
            restoreBook(book)
        } else if let outfit = itemToDelete as? Outfit {
            restoreOutfit(outfit)
        } else if let spaceBook = itemToDelete as? SpaceBookGroup {
            restoreSpaceBook(spaceBook)
        } else if let spaceOutfit = itemToDelete as? SpaceOutfit {
            restoreSpaceOutfit(spaceOutfit)
        } else if let model3D = itemToDelete as? Model3D {
            restoreModel3D(model3D)
        } else if let pattern = itemToDelete as? PerlerBeadPattern {
            restorePerlerPattern(pattern)
        }
        itemToDelete = nil
    }
    
    // MARK: - Wardrobe View
    
    var wardrobeList: some View {
        List(selection: $selectedItems) {
            if deletedClothings.isEmpty {
                ContentUnavailableView(
                    "回收站是空的",
                    systemImage: "trash",
                    description: Text("删除的裙装会出现在这里")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(deletedClothings) { clothing in
                    ClothingRowBrief(clothing: clothing)
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if editMode == .inactive {
                                Button {
                                    itemToDelete = clothing
                                    showingRestoreAlert = true
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if editMode == .inactive {
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
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - OOTD View
    
    var ootdList: some View {
        List(selection: $selectedItems) {
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
                            DeletedBookRow(book: book, isEditing: editMode == .active, onRestore: {
                                itemToDelete = book
                                showingRestoreAlert = true
                            }, onDelete: {
                                itemToDelete = book
                                showingDeleteAlert = true
                            })
                            .listRowBackground(Color.clear)
                            .tag(book.id) // Ensure ID is captured for selection
                        }
                    }
                }
                
                // Deleted Pages Section
                if !isolatedDeletedOutfits.isEmpty {
                    Section("单独删除的书页") {
                        ForEach(isolatedDeletedOutfits) { outfit in
                            DeletedOutfitRow(outfit: outfit, isEditing: editMode == .active, onRestore: {
                                itemToDelete = outfit
                                showingRestoreAlert = true
                            }, onDelete: {
                                itemToDelete = outfit
                                showingDeleteAlert = true
                            })
                            .listRowBackground(Color.clear)
                            .tag(outfit.id) // Ensure ID is captured for selection
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Space OOTD View
    
    var spaceOOTDList: some View {
        List(selection: $selectedItems) {
            if deletedSpaceBooks.isEmpty && isolatedDeletedSpaceOutfits.isEmpty {
                ContentUnavailableView(
                    "回收站是空的",
                    systemImage: "cube.transparent",
                    description: Text("删除的空间手帐和书页会出现在这里")
                )
                .listRowBackground(Color.clear)
            } else {
                // Deleted Books Section
                if !deletedSpaceBooks.isEmpty {
                    Section("空间手帐") {
                        ForEach(deletedSpaceBooks) { book in
                            DeletedSpaceBookRow(book: book, isEditing: editMode == .active, onRestore: {
                                itemToDelete = book
                                showingRestoreAlert = true
                            }, onDelete: {
                                itemToDelete = book
                                showingDeleteAlert = true
                            })
                            .listRowBackground(Color.clear)
                            .tag(book.id)
                        }
                    }
                }
                
                // Deleted Pages Section
                if !isolatedDeletedSpaceOutfits.isEmpty {
                    Section("单独删除的空间书页") {
                        ForEach(isolatedDeletedSpaceOutfits) { outfit in
                            DeletedSpaceOutfitRow(outfit: outfit, isEditing: editMode == .active, onRestore: {
                                itemToDelete = outfit
                                showingRestoreAlert = true
                            }, onDelete: {
                                itemToDelete = outfit
                                showingDeleteAlert = true
                            })
                            .listRowBackground(Color.clear)
                            .tag(outfit.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Model3D View
    
    var model3DList: some View {
        List(selection: $selectedItems) {
            if deletedModel3Ds.isEmpty {
                ContentUnavailableView(
                    "回收站是空的",
                    systemImage: "cube.box",
                    description: Text("删除的3D模型会出现在这里")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(deletedModel3Ds) { model in
                    DeletedModel3DRow(model: model, isEditing: editMode == .active, onRestore: {
                        itemToDelete = model
                        showingRestoreAlert = true
                    }, onDelete: {
                        itemToDelete = model
                        showingDeleteAlert = true
                    })
                    .listRowBackground(Color.clear)
                    .tag(model.id)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Perler Beads View
    
    var perlerBeadsList: some View {
        List(selection: $selectedItems) {
            if deletedPatterns.isEmpty {
                ContentUnavailableView(
                    "回收站是空的",
                    systemImage: "circle.grid.2x2",
                    description: Text("删除的拼豆/像素画会出现在这里")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(deletedPatterns) { pattern in
                    DeletedPerlerPatternRow(pattern: pattern, isEditing: editMode == .active, onRestore: {
                        itemToDelete = pattern
                        showingRestoreAlert = true
                    }, onDelete: {
                        itemToDelete = pattern
                        showingDeleteAlert = true
                    })
                    .listRowBackground(Color.clear)
                    .tag(pattern.id)
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
            // 关键：更新 lastModified，确保恢复后的状态不会被 iCloud 同步覆盖
            clothing.lastModified = Date()
        }
        // 从 DeleteTracker 中移除删除记录，防止被再次删除
        DeleteTracker.shared.removeDeletedClothing(id: clothing.id)
        
        // 立即保存，确保恢复状态被持久化
        do {
            try modelContext.save()
            print("RecycleBinView: 恢复裙装 '\(clothing.name)' 成功，lastModified 已更新")
        } catch {
            print("RecycleBinView: 恢复裙装保存失败: \(error)")
        }
    }
    
    private func permanentlyDeleteClothing(_ clothing: Clothing) {
        withAnimation {
            NotificationManager.shared.cancelNotification(for: clothing)
            modelContext.delete(clothing)
        }
        // 从 DeleteTracker 中移除删除记录，因为项目已被彻底删除
        DeleteTracker.shared.removeDeletedClothing(id: clothing.id)
    }
    
    private func restoreBook(_ book: BookGroup) {
        withAnimation {
            book.isDeleted = false
            book.deletedAt = nil
            book.lastModified = Date()
            // Restore all pages in this book
            for page in book.pages ?? [] {
                page.isDeleted = false
                page.deletedAt = nil
                page.lastModified = Date()
                // 从 DeleteTracker 中移除书页的删除记录
                DeleteTracker.shared.removeDeletedOutfit(id: page.id)
            }
        }
        // 从 DeleteTracker 中移除手帐本的删除记录
        DeleteTracker.shared.removeDeletedBookGroup(id: book.id)
        saveRestoreState("平面手帐「\(book.title)」")
    }
    
    private func permanentlyDeleteBook(_ book: BookGroup) {
        withAnimation {
            // Delete snapshot files for all pages
            for page in book.pages ?? [] {
                if let path = page.snapshotPath {
                    ImageManager.shared.deleteImage(fileName: path, context: modelContext)
                }
                // 从 DeleteTracker 中移除书页的删除记录
                DeleteTracker.shared.removeDeletedOutfit(id: page.id)
            }
            modelContext.delete(book)
        }
        // 从 DeleteTracker 中移除手帐本的删除记录
        DeleteTracker.shared.removeDeletedBookGroup(id: book.id)
    }
    
    private func restoreOutfit(_ outfit: Outfit) {
        withAnimation {
            outfit.isDeleted = false
            outfit.deletedAt = nil
            outfit.lastModified = Date()
        }
        // 从 DeleteTracker 中移除删除记录，防止被再次删除
        DeleteTracker.shared.removeDeletedOutfit(id: outfit.id)
        saveRestoreState("平面书页「\(outfit.note)」")
    }
    
    private func permanentlyDeleteOutfit(_ outfit: Outfit) {
        withAnimation {
            if let path = outfit.snapshotPath {
                ImageManager.shared.deleteImage(fileName: path, context: modelContext)
            }
            modelContext.delete(outfit)
        }
        // 从 DeleteTracker 中移除删除记录，因为项目已被彻底删除
        DeleteTracker.shared.removeDeletedOutfit(id: outfit.id)
    }
    
    private func restoreSpaceBook(_ book: SpaceBookGroup) {
        withAnimation {
            book.isDeleted = false
            book.deletedAt = nil
            book.lastModified = Date()
            // Restore all pages in this book
            for page in book.pages ?? [] {
                page.isDeleted = false
                page.deletedAt = nil
                page.lastModified = Date()
            }
        }
        saveRestoreState("空间手帐「\(book.title)」")
    }

    private func permanentlyDeleteSpaceBook(_ book: SpaceBookGroup) {
        withAnimation {
            // Delete snapshot files for all pages
            for page in book.pages ?? [] {
                if let path = page.snapshotPath {
                    ImageManager.shared.deleteImage(fileName: path, context: modelContext)
                }
            }
            modelContext.delete(book)
        }
        // 注意：SpaceBookGroup 和 SpaceOutfit 目前没有在 DeleteTracker 中单独追踪
        // 如果需要，可以在这里添加相应的清理逻辑
    }
    
    private func restoreSpaceOutfit(_ outfit: SpaceOutfit) {
        withAnimation {
            outfit.isDeleted = false
            outfit.deletedAt = nil
            outfit.lastModified = Date()
        }
        saveRestoreState("空间书页「\(outfit.note)」")
    }
    
    private func permanentlyDeleteSpaceOutfit(_ outfit: SpaceOutfit) {
        withAnimation {
            if let path = outfit.snapshotPath {
                ImageManager.shared.deleteImage(fileName: path, context: modelContext)
            }
            modelContext.delete(outfit)
        }
        // 注意：SpaceOutfit 目前没有在 DeleteTracker 中单独追踪
        // 如果需要，可以在这里添加相应的清理逻辑
    }
    
    private func restoreModel3D(_ model: Model3D) {
        withAnimation {
            model.isDeleted = false
            model.deletedAt = nil
            model.updatedAt = Date()
        }
        // 从 DeleteTracker 中移除删除记录，防止被再次删除
        DeleteTracker.shared.removeDeletedModel3D(id: model.id)
        saveRestoreState("3D模型「\(model.name)」")
    }
    
    private func permanentlyDeleteModel3D(_ model: Model3D) {
        withAnimation {
            // 删除模型文件和目录
            let fileManager = FileManager.default
            if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let modelDir = documentsPath.appendingPathComponent("Models/\(model.id.uuidString)")
                try? fileManager.removeItem(at: modelDir)
            }

            // 删除数据库记录
            modelContext.delete(model)

            print("[RecycleBin] 彻底删除 Model3D: \(model.name) (ID: \(model.id))")
        }
        // 从 DeleteTracker 中移除删除记录，因为项目已被彻底删除
        DeleteTracker.shared.removeDeletedModel3D(id: model.id)
    }
    
    private func restorePerlerPattern(_ pattern: PerlerBeadPattern) {
        withAnimation {
            pattern.isDeleted = false
            pattern.deletedAt = nil
            pattern.updatedAt = Date()
            pattern.lastModified = Date()
        }
        // 从 DeleteTracker 中移除删除记录，防止被再次删除
        DeleteTracker.shared.removeDeletedPerlerPattern(id: pattern.id)
        saveRestoreState("拼豆图案「\(pattern.name)」")
    }

    private func saveRestoreState(_ label: String) {
        do {
            modelContext.processPendingChanges()
            try modelContext.save()
            print("RecycleBinView: 恢复\(label)成功，状态已保存")
        } catch {
            print("RecycleBinView: 恢复\(label)保存失败: \(error)")
        }
    }
    
    private func permanentlyDeletePerlerPattern(_ pattern: PerlerBeadPattern) {
        withAnimation {
            // 删除缩略图
            if let thumbnailPath = pattern.thumbnailPath {
                ImageManager.shared.deleteImage(fileName: thumbnailPath, context: modelContext)
            }

            // 删除数据库记录
            modelContext.delete(pattern)

            print("[RecycleBin] 彻底删除 PerlerPattern: \(pattern.name) (ID: \(pattern.id))")
        }
        // 从 DeleteTracker 中移除删除记录，因为项目已被彻底删除
        DeleteTracker.shared.removeDeletedPerlerPattern(id: pattern.id)
    }
    
    // MARK: - Batch Actions
    
    private func restoreAll() {
        if selectedTab == 0 {
            for clothing in deletedClothings {
                restoreClothing(clothing)
            }
        } else if selectedTab == 1 {
            if selectedSubTab == 0 {
                for book in deletedBooks {
                    restoreBook(book)
                }
                for outfit in isolatedDeletedOutfits {
                    restoreOutfit(outfit)
                }
            } else if selectedSubTab == 1 {
                for book in deletedSpaceBooks {
                    restoreSpaceBook(book)
                }
                for outfit in isolatedDeletedSpaceOutfits {
                    restoreSpaceOutfit(outfit)
                }
            } else {
                for model in deletedModel3Ds {
                    restoreModel3D(model)
                }
            }
        } else {
            for pattern in deletedPatterns {
                restorePerlerPattern(pattern)
            }
        }
    }
    
    private func deleteAll() {
        if selectedTab == 0 {
            for clothing in deletedClothings {
                permanentlyDeleteClothing(clothing)
            }
        } else if selectedTab == 1 {
            if selectedSubTab == 0 {
                for book in deletedBooks {
                    permanentlyDeleteBook(book)
                }
                for outfit in isolatedDeletedOutfits {
                    permanentlyDeleteOutfit(outfit)
                }
            } else if selectedSubTab == 1 {
                for book in deletedSpaceBooks {
                    permanentlyDeleteSpaceBook(book)
                }
                for outfit in isolatedDeletedSpaceOutfits {
                    permanentlyDeleteSpaceOutfit(outfit)
                }
            } else {
                for model in deletedModel3Ds {
                    permanentlyDeleteModel3D(model)
                }
            }
        } else {
            for pattern in deletedPatterns {
                permanentlyDeletePerlerPattern(pattern)
            }
        }
    }
    
    private func restoreSelected() {
        if selectedTab == 0 {
            let itemsToRestore = deletedClothings.filter { selectedItems.contains($0.id) }
            for item in itemsToRestore {
                restoreClothing(item)
            }
        } else if selectedTab == 1 {
            if selectedSubTab == 0 {
                let booksToRestore = deletedBooks.filter { selectedItems.contains($0.id) }
                for book in booksToRestore {
                    restoreBook(book)
                }
                
                let outfitsToRestore = isolatedDeletedOutfits.filter { selectedItems.contains($0.id) }
                for outfit in outfitsToRestore {
                    restoreOutfit(outfit)
                }
            } else if selectedSubTab == 1 {
                let booksToRestore = deletedSpaceBooks.filter { selectedItems.contains($0.id) }
                for book in booksToRestore {
                    restoreSpaceBook(book)
                }
                
                let outfitsToRestore = isolatedDeletedSpaceOutfits.filter { selectedItems.contains($0.id) }
                for outfit in outfitsToRestore {
                    restoreSpaceOutfit(outfit)
                }
            } else {
                let modelsToRestore = deletedModel3Ds.filter { selectedItems.contains($0.id) }
                for model in modelsToRestore {
                    restoreModel3D(model)
                }
            }
        } else {
            let patternsToRestore = deletedPatterns.filter { selectedItems.contains($0.id) }
            for pattern in patternsToRestore {
                restorePerlerPattern(pattern)
            }
        }
        selectedItems.removeAll()
    }
    
    private func deleteSelected() {
        if selectedTab == 0 {
            let itemsToDelete = deletedClothings.filter { selectedItems.contains($0.id) }
            for item in itemsToDelete {
                permanentlyDeleteClothing(item)
            }
        } else if selectedTab == 1 {
            if selectedSubTab == 0 {
                let booksToDelete = deletedBooks.filter { selectedItems.contains($0.id) }
                for book in booksToDelete {
                    permanentlyDeleteBook(book)
                }
                
                let outfitsToDelete = isolatedDeletedOutfits.filter { selectedItems.contains($0.id) }
                for outfit in outfitsToDelete {
                    permanentlyDeleteOutfit(outfit)
                }
            } else if selectedSubTab == 1 {
                let booksToDelete = deletedSpaceBooks.filter { selectedItems.contains($0.id) }
                for book in booksToDelete {
                    permanentlyDeleteSpaceBook(book)
                }
                
                let outfitsToDelete = isolatedDeletedSpaceOutfits.filter { selectedItems.contains($0.id) }
                for outfit in outfitsToDelete {
                    permanentlyDeleteSpaceOutfit(outfit)
                }
            } else {
                let modelsToDelete = deletedModel3Ds.filter { selectedItems.contains($0.id) }
                for model in modelsToDelete {
                    permanentlyDeleteModel3D(model)
                }
            }
        } else {
            let patternsToDelete = deletedPatterns.filter { selectedItems.contains($0.id) }
            for pattern in patternsToDelete {
                permanentlyDeletePerlerPattern(pattern)
            }
        }
        selectedItems.removeAll()
    }
}

struct DeletedBookRow: View {
    let book: BookGroup
    var isEditing: Bool = false
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
                        
                        Text("\(book.pages?.count ?? 0) 页")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isEditing)

                // Actions
                if !isEditing {
                    HStack(spacing: 16) {
                        Button(action: onRestore) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Button(action: onDelete) {
                            Image(systemName: "trash.circle.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isExpanded {
                ForEach(book.pages ?? []) { page in
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 28)
                        
                        Text(page.note.isEmpty ? "未命名书页" : page.note)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        if page.shouldUseStoredSnapshot,
                           let snapshotPath = page.snapshotPath,
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

// MARK: - DeletedModel3DRow

struct DeletedModel3DRow: View {
    let model: Model3D
    var isEditing: Bool = false
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // 缩略图
            if let thumbnailPath = model.resolvedThumbnailPath,
               let uiImage = UIImage(contentsOfFile: thumbnailPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "cube.box")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)
                
                if let deletedAt = model.deletedAt {
                    Text("删除于 \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            if !isEditing {
                HStack(spacing: 16) {
                    Button(action: onRestore) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
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
    var isEditing: Bool = false
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            if outfit.shouldUseStoredSnapshot,
               let snapshotPath = outfit.snapshotPath,
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
            
            if !isEditing {
                HStack(spacing: 16) {
                    Button(action: onRestore) {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        .cornerRadius(12)
    }
}

struct DeletedSpaceBookRow: View {
    let book: SpaceBookGroup
    var isEditing: Bool = false
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
                        
                        Text("\(book.pages?.count ?? 0) 页")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isEditing)

                // Actions
                if !isEditing {
                    HStack(spacing: 16) {
                        Button(action: onRestore) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Button(action: onDelete) {
                            Image(systemName: "trash.circle.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isExpanded {
                ForEach(book.pages ?? []) { page in
                    HStack {
                        Image(systemName: "cube.transparent")
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

struct DeletedSpaceOutfitRow: View {
    let outfit: SpaceOutfit
    var isEditing: Bool = false
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
                Image(systemName: "cube.transparent")
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
            
            if !isEditing {
                HStack(spacing: 16) {
                    Button(action: onRestore) {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - DeletedPerlerPatternRow

struct DeletedPerlerPatternRow: View {
    let pattern: PerlerBeadPattern
    var isEditing: Bool = false
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // 缩略图
            if let thumbnailPath = pattern.thumbnailPath,
               let uiImage = ImageManager.shared.loadImage(fileName: thumbnailPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: pattern.typeEnum.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text(pattern.typeEnum.rawValue)
                        .font(.caption)
                        .foregroundStyle(.pink)
                    
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(pattern.totalPixels) 像素")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let deletedAt = pattern.deletedAt {
                    Text("删除于 \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            if !isEditing {
                HStack(spacing: 16) {
                    Button(action: onRestore) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
        .cornerRadius(12)
    }
}
