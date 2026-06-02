//
//  ModelManagementViews.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct BrandManagementView: View {
    @Query(sort: \Brand.name) private var brands: [Brand]
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedBrand: Brand?
    @State private var isEditing = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        List {
            ForEach(brands) { brand in
                HStack {
                    if let path = brand.imagePath,
                       let image = ImageManager.shared.loadImage(fileName: path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(hex: brand.colorHex))
                            .frame(width: 30, height: 30)
                    }
                    
                    Text(brand.name)
                    Spacer()
                    
                    Button(action: {
                        selectedBrand = brand
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
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle("品牌管理".appLocalized)
        .sheet(item: $selectedBrand) { brand in
             BrandEditSheet(brand: brand)
        }
        .alert("删除品牌".appLocalized, isPresented: $showingDeleteAlert) {
            Button("取消".appLocalized, role: .cancel) { }
            Button("删除".appLocalized, role: .destructive) {
                if let brand = selectedBrand {
                    modelContext.delete(brand)
                    try? modelContext.save()
                }
            }
        } message: {
            Text("确定要删除此品牌吗？\n删除后，商品上的品牌关联将被移除。".appLocalized)
        }
    }
}

struct BrandEditSheet: View {
    @Bindable var brand: Brand
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: PhotosPickerItem?
    
    private let predefinedColors: [String] = [
        "#FFB6C1", "#FF69B4", "#FF1493", "#FF4500", "#FFA500",
        "#FFD700", "#32CD32", "#00FA9A", "#00CED1", "#1E90FF",
        "#4169E1", "#9370DB", "#BA55D3", "#808080", "#000000"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息".appLocalized) {
                    TextField("品牌名称".appLocalized, text: $brand.name)
                }
                
                Section("品牌图片".appLocalized) {
                    HStack {
                        if let path = brand.imagePath,
                           let image = ImageManager.shared.loadImage(fileName: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Text(brand.imagePath == nil ? "选择图片".appLocalized : "更换图片".appLocalized)
                        }
                        
                        if brand.imagePath != nil {
                            Spacer()
                            Button(role: .destructive) {
                                brand.imagePath = nil
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
                
                Section("品牌颜色".appLocalized) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(predefinedColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: brand.colorHex == hex ? 2 : 0)
                                    )
                                    .onTapGesture {
                                        brand.colorHex = hex
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                LiquidBackground()
            }
            .navigationTitle("编辑品牌".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成".appLocalized) { dismiss() }
                }
            }
            .task(id: selectedItem) {
                if let item = selectedItem,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let filename = ImageManager.shared.saveImage(uiImage, context: modelContext) {
                    brand.imagePath = filename
                }
            }
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
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle("标签管理".appLocalized)
        .alert("修改标签名称".appLocalized, isPresented: $isEditing) {
            TextField("新名称".appLocalized, text: $editText)
            Button("取消".appLocalized, role: .cancel) { }
            Button("保存".appLocalized) {
                if let tag = selectedTag {
                    tag.name = editText
                    try? modelContext.save()
                }
            }
        }
        .alert("删除标签".appLocalized, isPresented: $showingDeleteAlert) {
            Button("取消".appLocalized, role: .cancel) { }
            Button("删除".appLocalized, role: .destructive) {
                if let tag = selectedTag {
                    modelContext.delete(tag)
                    try? modelContext.save()
                }
            }
        } message: {
            Text("确定要删除“%@”吗？\n删除后，商品上的标签关联将被移除。".appLocalized(selectedTag?.name ?? ""))
        }
    }
}
