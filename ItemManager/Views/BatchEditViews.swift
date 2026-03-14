//
//  BatchEditViews.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 3/14/26.
//

import SwiftUI

// MARK: - 批量字符串选择视图（用于颜色、尺码、衣长、小物）
struct BatchStringSelectionView: View {
    let title: String
    let options: [String]
    @Binding var selectedItems: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempSelectedItems: Set<String> = []
    @State private var newItemName: String = ""
    @State private var isAddingNew: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isAddingNew {
                        HStack {
                            TextField("新选项", text: $newItemName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addNewItem()
                                }
                            
                            Button("添加") {
                                addNewItem()
                            }
                            .disabled(newItemName.isEmpty)
                        }
                    } else {
                        Button(action: {
                            isAddingNew = true
                        }) {
                            Label("添加新选项", systemImage: "plus.circle.fill")
                                .foregroundStyle(.pink)
                        }
                    }
                }
                
                Section {
                    if options.isEmpty && tempSelectedItems.isEmpty {
                        Text("暂无选项")
                            .foregroundStyle(.secondary)
                    } else {
                        let displayOptions = Array(Set(options).union(tempSelectedItems)).sorted()
                        
                        ForEach(displayOptions, id: \.self) { option in
                            HStack {
                                Text(option)
                                Spacer()
                                if tempSelectedItems.contains(option) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.pink)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(option)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        tempSelectedItems.removeAll()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        selectedItems = Array(tempSelectedItems)
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempSelectedItems = Set(selectedItems)
            }
        }
    }
    
    private func toggleSelection(_ option: String) {
        if tempSelectedItems.contains(option) {
            tempSelectedItems.remove(option)
        } else {
            tempSelectedItems.insert(option)
        }
    }
    
    private func addNewItem() {
        guard !newItemName.isEmpty else { return }
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        toggleSelection(name)
        
        newItemName = ""
        isAddingNew = false
    }
}

// MARK: - 批量状态选择视图
struct BatchStatusSelectionView: View {
    @Binding var selectedStatus: String?
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempSelectedStatus: String? = nil
    
    private let statusOptions: [(String, String)] = [
        ("上架", "checkmark.circle.fill"),
        ("下架", "xmark.circle.fill")
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(statusOptions, id: \.0) { status, icon in
                        HStack {
                            Image(systemName: icon)
                                .foregroundStyle(status == "上架" ? .green : .orange)
                            Text(status)
                            Spacer()
                            if tempSelectedStatus == status {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.pink)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tempSelectedStatus = status
                        }
                    }
                }
            }
            .navigationTitle("改变状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        tempSelectedStatus = nil
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        selectedStatus = tempSelectedStatus
                        dismiss()
                    }
                    .disabled(tempSelectedStatus == nil)
                }
            }
            .onAppear {
                tempSelectedStatus = selectedStatus
            }
        }
    }
}
