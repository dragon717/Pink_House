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
    @State private var selectedColorHex: String = "#FFB6C1"
    @State private var isAddingTag: Bool = false
    @State private var editingTag: Tag?
    @State private var tagToDelete: Tag?
    @State private var showingDeleteAlert: Bool = false
    
    private let predefinedColors: [String] = [
        "#FFB6C1", // Light Pink
        "#FF69B4", // Hot Pink
        "#FF1493", // Deep Pink
        "#FF4500", // Orange Red
        "#FFA500", // Orange
        "#FFD700", // Gold
        "#32CD32", // Lime Green
        "#00FA9A", // Medium Spring Green
        "#00CED1", // Dark Turquoise
        "#1E90FF", // Dodger Blue
        "#4169E1", // Royal Blue
        "#9370DB", // Medium Purple
        "#BA55D3", // Medium Orchid
        "#808080", // Gray
        "#000000"  // Black
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isAddingTag {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("新标签名称", text: $newTagName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addNewTag()
                                }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(predefinedColors, id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 30, height: 30)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.primary, lineWidth: selectedColorHex == hex ? 2 : 0)
                                            )
                                            .onTapGesture {
                                                selectedColorHex = hex
                                            }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            
                            HStack {
                                Button("取消") {
                                    isAddingTag = false
                                    newTagName = ""
                                    selectedColorHex = "#FFB6C1"
                                }
                                .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Button("添加") {
                                    addNewTag()
                                }
                                .disabled(newTagName.isEmpty)
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
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
                    if allTags.isEmpty {
                        Text("暂无标签")
                            .foregroundStyle(.secondary)
                    } else {
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
                                
                                Button {
                                    editingTag = tag
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.orange)
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
            .sheet(item: $editingTag) { tag in
                TagEditSheet(tag: tag, predefinedColors: predefinedColors)
            }
            .alert("确认删除标签", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {
                    tagToDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let tag = tagToDelete {
                        performDelete(tag)
                    }
                    tagToDelete = nil
                }
            } message: {
                if let tag = tagToDelete, let count = tag.clothings?.count {
                    Text("该标签已被 \(count) 件裙子使用，删除后这些裙子将不再包含此标签。确定要删除吗？")
                } else {
                    Text("确定要删除此标签吗？")
                }
            }
        }
    }
    
    private func addNewTag() {
        guard !newTagName.isEmpty else { return }
        
        // Check for duplicates
        if !allTags.contains(where: { $0.name == newTagName }) {
            let newTag = Tag(name: newTagName, colorHex: selectedColorHex)
            modelContext.insert(newTag)
            selectedTags.append(newTag)
        }
        
        newTagName = ""
        selectedColorHex = "#FFB6C1" // Reset to default
        isAddingTag = false
    }
    
    private func deleteTag(_ tag: Tag) {
        // Check if tag is used by any clothing
        if let clothings = tag.clothings, !clothings.isEmpty {
            tagToDelete = tag
            showingDeleteAlert = true
        } else {
            performDelete(tag)
        }
    }
    
    private func performDelete(_ tag: Tag) {
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

struct TagEditSheet: View {
    let tag: Tag
    let predefinedColors: [String]
    
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    
    init(tag: Tag, predefinedColors: [String]) {
        self.tag = tag
        self.predefinedColors = predefinedColors
        _name = State(initialValue: tag.name)
        _colorHex = State(initialValue: tag.colorHex)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("标签信息") {
                    TextField("标签名称", text: $name)
                }
                
                Section("标签颜色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(predefinedColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                                    )
                                    .onTapGesture {
                                        colorHex = hex
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        tag.name = name
        tag.colorHex = colorHex
        dismiss()
    }
}
