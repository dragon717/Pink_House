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
    @State private var searchText: String = ""

    private var displayOptions: [String] {
        let all = Array(Set(options).union(selectedItems)).sorted()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedStandardContains(query) }
    }

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
                            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            isAddingNew = true
                        } label: {
                            Label("添加新选项".appLocalized, systemImage: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Section {
                    if displayOptions.isEmpty {
                        Text((options.isEmpty && selectedItems.isEmpty) ? "暂无选项".appLocalized : "无匹配选项".appLocalized)
                            .foregroundStyle(.secondary)
                    } else {
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
            .searchable(text: $searchText, prompt: Text("搜索".appLocalized))
            .navigationTitle(title)
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
                if allowMultiple {
                    selectedItems = Set(CommaSeparatedTokens.parse(selection))
                } else if !selection.isEmpty {
                    // 单选字段历史数据偶发带逗号时，只取首个 token
                    selectedItems = Set(CommaSeparatedTokens.parse(selection).prefix(1))
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
        }
    }

    private func addNewItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        toggleSelection(name)
        newItemName = ""
        isAddingNew = false
        searchText = ""
    }

    private func saveSelection() {
        if allowMultiple {
            selection = CommaSeparatedTokens.joinPreservingOrder(
                previous: CommaSeparatedTokens.parse(selection),
                selected: selectedItems
            )
        } else {
            selection = selectedItems.first ?? ""
        }
    }
}
