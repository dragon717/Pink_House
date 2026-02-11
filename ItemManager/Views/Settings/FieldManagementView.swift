//
//  FieldManagementView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import SwiftData

struct FieldManagementView: View {
    let title: String
    let keyPath: ReferenceWritableKeyPath<Clothing, String>
    let isCommaSeparated: Bool
    
    @Query private var clothings: [Clothing]
    @Environment(\.modelContext) private var modelContext
    
    @State private var items: [String] = []
    @State private var selectedItem: String?
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item)
                    Spacer()
                    Button(action: {
                        selectedItem = item
                        editText = item
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.trailing, 10)
                    
                    Button(action: {
                        selectedItem = item
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle(title)
        .onAppear {
            loadItems()
        }
        .alert("修改\(title)", isPresented: $isEditing) {
            TextField("新名称", text: $editText)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let oldItem = selectedItem {
                    updateItem(oldItem: oldItem, newItem: editText)
                }
            }
        }
        .alert("删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let item = selectedItem {
                    deleteItem(item)
                }
            }
        } message: {
            Text("确定要删除“\(selectedItem ?? "")”吗？\n删除后，所有商品中的该属性将被移除，但商品本身会保留。")
        }
    }
    
    private func loadItems() {
        var uniqueItems = Set<String>()
        
        for clothing in clothings {
            let value = clothing[keyPath: keyPath]
            if isCommaSeparated {
                let parts = StringHelper.extractItems(from: value)
                for part in parts {
                    uniqueItems.insert(part)
                }
            } else {
                if !value.isEmpty {
                    uniqueItems.insert(value)
                }
            }
        }
        
        items = Array(uniqueItems).sorted()
    }
    
    private func updateItem(oldItem: String, newItem: String) {
        guard !newItem.isEmpty else { return }
        
        for clothing in clothings {
            let currentValue = clothing[keyPath: keyPath]
            
            if isCommaSeparated {
                // 检查是否包含旧值
                let parts = StringHelper.extractItems(from: currentValue)
                if parts.contains(oldItem) {
                    let newValue = StringHelper.updateStringList(original: currentValue, oldItem: oldItem, newItem: newItem)
                    clothing[keyPath: keyPath] = newValue
                }
            } else {
                // 完全匹配
                if currentValue == oldItem {
                    clothing[keyPath: keyPath] = newItem
                }
            }
        }
        
        // 保存并刷新
        try? modelContext.save()
        loadItems()
    }
    
    private func deleteItem(_ item: String) {
        for clothing in clothings {
            let currentValue = clothing[keyPath: keyPath]
            
            if isCommaSeparated {
                let parts = StringHelper.extractItems(from: currentValue)
                if parts.contains(item) {
                    let newValue = StringHelper.updateStringList(original: currentValue, oldItem: item, newItem: nil)
                    clothing[keyPath: keyPath] = newValue
                }
            } else {
                if currentValue == item {
                    clothing[keyPath: keyPath] = "" // 清空
                }
            }
        }
        
        try? modelContext.save()
        loadItems()
    }
}
