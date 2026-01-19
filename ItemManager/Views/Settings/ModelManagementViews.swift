//
//  ModelManagementViews.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import SwiftUI
import SwiftData

struct BrandManagementView: View {
    @Query(sort: \Brand.name) private var brands: [Brand]
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedBrand: Brand?
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            ForEach(brands) { brand in
                HStack {
                    Text(brand.name)
                    Spacer()
                    
                    Button(action: {
                        selectedBrand = brand
                        editText = brand.name
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.trailing, 10)
                    
                    Button(action: {
                        selectedBrand = brand
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .navigationTitle("品牌管理")
        .alert("修改品牌名称", isPresented: $isEditing) {
            TextField("新名称", text: $editText)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let brand = selectedBrand {
                    brand.name = editText
                    try? modelContext.save()
                }
            }
        }
        .alert("删除品牌", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let brand = selectedBrand {
                    modelContext.delete(brand)
                    try? modelContext.save()
                }
            }
        } message: {
            Text("确定要删除“\(selectedBrand?.name ?? "")”吗？\n删除后，商品上的品牌关联将被移除。")
        }
    }
}

struct TagModelManagementView: View {
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedTag: Tag?
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            ForEach(tags) { tag in
                HStack {
                    Text(tag.name)
                    Spacer()
                    
                    Button(action: {
                        selectedTag = tag
                        editText = tag.name
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.trailing, 10)
                    
                    Button(action: {
                        selectedTag = tag
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .navigationTitle("标签管理")
        .alert("修改标签名称", isPresented: $isEditing) {
            TextField("新名称", text: $editText)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let tag = selectedTag {
                    tag.name = editText
                    try? modelContext.save()
                }
            }
        }
        .alert("删除标签", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let tag = selectedTag {
                    modelContext.delete(tag)
                    try? modelContext.save()
                }
            }
        } message: {
            Text("确定要删除“\(selectedTag?.name ?? "")”吗？\n删除后，商品上的标签关联将被移除。")
        }
    }
}
