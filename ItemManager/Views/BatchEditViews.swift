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
                            TextField("新选项".appLocalized, text: $newItemName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addNewItem()
                                }
                            
                            Button("添加".appLocalized) {
                                addNewItem()
                            }
                            .disabled(newItemName.isEmpty)
                        }
                    } else {
                        Button(action: {
                            isAddingNew = true
                        }) {
                            Label("添加新选项".appLocalized, systemImage: "plus.circle.fill")
                                .foregroundStyle(.pink)
                        }
                    }
                }
                
                Section {
                    if options.isEmpty && tempSelectedItems.isEmpty {
                        Text("暂无选项".appLocalized)
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
            .navigationTitle(title.appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".appLocalized) {
                        tempSelectedItems.removeAll()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成".appLocalized) {
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

// MARK: - 批量成色选择视图
struct BatchConditionSelectionView: View {
    @Binding var selectedCondition: String?
    let options: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempSelectedCondition: String? = nil

    private var conditionOptions: [String] {
        Array(
            Set(
                options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if conditionOptions.isEmpty {
                        Text("暂无可选成色".appLocalized)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(conditionOptions, id: \.self) { condition in
                            HStack {
                                Text(condition)
                                Spacer()
                                if tempSelectedCondition == condition {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.pink)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tempSelectedCondition = condition
                            }
                        }
                    }
                }
            }
            .navigationTitle("改变成色".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".appLocalized) {
                        tempSelectedCondition = nil
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成".appLocalized) {
                        selectedCondition = tempSelectedCondition
                        dismiss()
                    }
                    .disabled(tempSelectedCondition == nil)
                }
            }
            .onAppear {
                tempSelectedCondition = selectedCondition
            }
        }
    }
}
