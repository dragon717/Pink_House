//
//  TagSelectionView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation

struct TagSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedTags: [Tag]
    
    @State private var newTagName: String = ""
    @State private var isAddingTag: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isAddingTag {
                        HStack {
                            TextField("新标签名称", text: $newTagName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addNewTag()
                                }
                            
                            Button("添加") {
                                addNewTag()
                            }
                            .disabled(newTagName.isEmpty)
                        }
                    } else {
                        Button(action: {
                            isAddingTag = true
                        }) {
                            Label("新建标签", systemImage: "plus.circle.fill")
                                .foregroundStyle(.pink)
                        }
                    }
                }
                
                Section("所有标签") {
                    ForEach(allTags) { tag in
                        HStack {
                            Circle()
                                .fill(Color(hex: tag.colorHex))
                                .frame(width: 12, height: 12)
                            
                            Text(tag.name)
                            
                            Spacer()
                            
                            if selectedTags.contains(where: { $0.id == tag.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(tag)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTag(tag)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("管理标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addNewTag() {
        guard !newTagName.isEmpty else { return }
        
        // Check for duplicates
        if !allTags.contains(where: { $0.name == newTagName }) {
            let newTag = Tag(name: newTagName)
            modelContext.insert(newTag)
            selectedTags.append(newTag)
        }
        
        newTagName = ""
        isAddingTag = false
    }
    
    private func deleteTag(_ tag: Tag) {
        if let index = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: index)
        }
        modelContext.delete(tag)
    }
    
    private func toggleSelection(_ tag: Tag) {
        if let index = selectedTags.firstIndex(where: { $0.id == tag.id }) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }
}

