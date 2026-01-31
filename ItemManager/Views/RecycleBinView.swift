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
    
    // 查询已删除的项目
    @Query(filter: #Predicate<Clothing> { $0.isDeleted == true }, sort: \Clothing.deletedAt, order: .reverse)
    private var deletedClothings: [Clothing]
    
    @State private var selectedItems: Set<UUID> = []
    @State private var editMode: EditMode = .inactive
    
    @State private var itemToRestore: Clothing?
    @State private var itemToDelete: Clothing?
    @State private var showingDeleteAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var showingRestoreAllAlert = false
    @State private var showingBatchDeleteAlert = false
    @State private var showingBatchRestoreAlert = false
    
    var body: some View {
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
                                restoreItem(clothing)
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
                        .tag(clothing.id)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle("回收站")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if !deletedClothings.isEmpty {
                        Button {
                            withAnimation {
                                if editMode == .active {
                                    editMode = .inactive
                                    selectedItems.removeAll()
                                } else {
                                    editMode = .active
                                }
                            }
                        } label: {
                            Text(editMode == .active ? "完成" : "编辑")
                        }
                        
                        if editMode == .inactive {
                            Menu {
                                Button {
                                    showingRestoreAllAlert = true
                                } label: {
                                    Label("全部恢复", systemImage: "arrow.uturn.backward")
                                }
                                
                                Button(role: .destructive) {
                                    showingDeleteAllAlert = true
                                } label: {
                                    Label("清空回收站", systemImage: "trash.slash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode == .active {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Button {
                            showingBatchRestoreAlert = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 20))
                                Text("恢复")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItems.isEmpty)
                        
                        Divider()
                            .frame(height: 30)
                        
                        VStack(spacing: 2) {
                            Text("已选择")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(selectedItems.count)")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                            .frame(height: 30)
                        
                        Button(role: .destructive) {
                            showingBatchDeleteAlert = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 20))
                                Text("删除")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedItems.isEmpty)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal)
                    .background(.regularMaterial)
                }
            }
        }
        .alert("彻底删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { itemToDelete = nil }
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    permanentlyDeleteItem(item)
                }
                itemToDelete = nil
            }
        } message: {
            Text("确定要彻底删除这件裙子吗？此操作无法撤销。")
        }
        .alert("批量删除", isPresented: $showingBatchDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedItems()
            }
        } message: {
            Text("确定要彻底删除选中的 \(selectedItems.count) 项吗？此操作无法撤销。")
        }
        .alert("批量恢复", isPresented: $showingBatchRestoreAlert) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .none) {
                restoreSelectedItems()
            }
        } message: {
            Text("确定要恢复选中的 \(selectedItems.count) 项吗？")
        }
        .alert("清空回收站", isPresented: $showingDeleteAllAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                deleteAllItems()
            }
        } message: {
            Text("确定要清空回收站吗？所有项目将被永久删除且无法撤销。")
        }
        .alert("全部恢复", isPresented: $showingRestoreAllAlert) {
            Button("取消", role: .cancel) { }
            Button("恢复", role: .none) {
                restoreAllItems()
            }
        } message: {
            Text("确定要恢复回收站中的所有项目吗？")
        }
    }
    
    // MARK: - Actions
    
    private func restoreSelectedItems() {
        withAnimation {
            let itemsToRestore = deletedClothings.filter { selectedItems.contains($0.id) }
            for clothing in itemsToRestore {
                clothing.isDeleted = false
                clothing.deletedAt = nil
            }
            selectedItems.removeAll()
            editMode = .inactive
        }
    }
    
    private func deleteSelectedItems() {
        withAnimation {
            let itemsToDelete = deletedClothings.filter { selectedItems.contains($0.id) }
            for clothing in itemsToDelete {
                NotificationManager.shared.cancelNotification(for: clothing)
                modelContext.delete(clothing)
            }
            selectedItems.removeAll()
            editMode = .inactive
        }
    }
    
    // MARK: - Actions
    
    private func restoreItem(_ clothing: Clothing) {
        withAnimation {
            clothing.isDeleted = false
            clothing.deletedAt = nil
        }
    }
    
    private func permanentlyDeleteItem(_ clothing: Clothing) {
        withAnimation {
            // Cancel any notifications
            NotificationManager.shared.cancelNotification(for: clothing)
            
            // Delete associated files if needed (e.g. images)
            // Note: Currently image deletion is handled manually or relies on system cleanup?
            // The original delete logic was just modelContext.delete(item)
            
            modelContext.delete(clothing)
        }
    }
    
    private func restoreAllItems() {
        withAnimation {
            for clothing in deletedClothings {
                clothing.isDeleted = false
                clothing.deletedAt = nil
            }
        }
    }
    
    private func deleteAllItems() {
        withAnimation {
            for clothing in deletedClothings {
                NotificationManager.shared.cancelNotification(for: clothing)
                modelContext.delete(clothing)
            }
        }
    }
}
