//
//  SimpleStringSelectionView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
//

import SwiftUI

struct SimpleStringSelectionView: View {
    let title: String
    let options: [String]
    let allowMultiple: Bool
    @Binding var selection: String // For single selection or comma separated string
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedItems: Set<String> = []
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
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                Section {
                    if options.isEmpty && selectedItems.isEmpty {
                        Text("暂无选项".appLocalized)
                            .foregroundStyle(.secondary)
                    } else {
                        // Merge predefined options with any newly added ones that might not be in the list yet
                        // (Though in this simplified view we just rely on options passed in + selected items)
                        let displayOptions = Array(Set(options).union(selectedItems)).sorted()
                        
                        ForEach(displayOptions, id: \.self) { option in
                            HStack {
                                Text(option)
                                Spacer()
                                if selectedItems.contains(option) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
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
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成".appLocalized) {
                        saveSelection()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize selected items from the binding string
                if allowMultiple {
                    let items = selection.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }
                    selectedItems = Set(items)
                } else {
                    if !selection.isEmpty {
                        selectedItems = [selection]
                    }
                }
            }
        }
    }
    
    private func toggleSelection(_ option: String) {
        if allowMultiple {
            if selectedItems.contains(option) {
                selectedItems.remove(option)
            } else {
                selectedItems.insert(option)
            }
        } else {
            selectedItems = [option]
            // For single selection, we could auto-dismiss, but "Done" button is safer for consistency
        }
    }
    
    private func addNewItem() {
        guard !newItemName.isEmpty else { return }
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        toggleSelection(name) // Auto select the new item
        
        newItemName = ""
        isAddingNew = false
    }
    
    private func saveSelection() {
        if allowMultiple {
            selection = selectedItems.sorted().joined(separator: ",")
        } else {
            selection = selectedItems.first ?? ""
        }
    }
}
