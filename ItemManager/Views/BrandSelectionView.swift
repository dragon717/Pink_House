//
//  BrandSelectionView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/17/26.
//

import SwiftUI
import SwiftData
import Foundation
import PhotosUI

struct BrandSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Brand.name) private var allBrands: [Brand]
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedBrand: Brand?
    
    @State private var newBrandName: String = ""
    @State private var selectedColorHex: String = "#FFB6C1"
    @State private var isAddingBrand: Bool = false
    @State private var editingBrand: Brand?
    @State private var brandToDelete: Brand?
    @State private var showingDeleteAlert: Bool = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var tempImagePath: String?
    
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
                    if isAddingBrand {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                if let path = tempImagePath,
                                   let image = ImageManager.shared.loadImage(fileName: path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                
                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                                .task(id: selectedItem) {
                                    if let item = selectedItem,
                                       let data = try? await item.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data),
                                       let filename = ImageManager.shared.saveImage(uiImage, context: modelContext) {
                                        tempImagePath = filename
                                    }
                                }
                                
                                TextField("新品牌名称", text: $newBrandName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        addNewBrand()
                                    }
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
                                    isAddingBrand = false
                                    newBrandName = ""
                                    selectedColorHex = "#FFB6C1"
                                }
                                .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Button("添加") {
                                    addNewBrand()
                                }
                                .disabled(newBrandName.isEmpty)
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button(action: {
                            isAddingBrand = true
                        }) {
                            Label("新建品牌", systemImage: "plus.circle.fill")
                                .foregroundStyle(.pink)
                        }
                    }
                }
                
                Section("所有品牌") {
                    if allBrands.isEmpty {
                        Text("暂无品牌")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allBrands) { brand in
                            HStack {
                                if let path = brand.imagePath,
                                   let image = ImageManager.shared.loadImage(fileName: path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color(hex: brand.colorHex))
                                        .frame(width: 12, height: 12)
                                }
                                
                                Text(brand.name)
                                
                                Spacer()
                                
                                if selectedBrand?.id == brand.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectBrand(brand)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteBrand(brand)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                
                                Button {
                                    editingBrand = brand
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择品牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingBrand) { brand in
                BrandEditSheet(brand: brand)
            }
            .alert("确认删除品牌", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {
                    brandToDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let brand = brandToDelete {
                        performDelete(brand)
                    }
                    brandToDelete = nil
                }
            } message: {
                if let brand = brandToDelete, let count = brand.clothings?.count {
                    Text("该品牌已被 \(count) 件裙子使用，删除后这些裙子的品牌信息将被清除。确定要删除吗？")
                } else {
                    Text("确定要删除此品牌吗？")
                }
            }
        }
    }
    
    private func addNewBrand() {
        guard !newBrandName.isEmpty else { return }
        
        // Check for duplicates
        if !allBrands.contains(where: { $0.name == newBrandName }) {
            let newBrand = Brand(name: newBrandName, colorHex: selectedColorHex, imagePath: tempImagePath)
            modelContext.insert(newBrand)
            selectedBrand = newBrand // Auto select new brand
        }
        
        newBrandName = ""
        selectedColorHex = "#FFB6C1" // Reset to default
        tempImagePath = nil
        selectedItem = nil
        isAddingBrand = false
    }
    
    private func deleteBrand(_ brand: Brand) {
        // Check if brand is used by any clothing
        if let clothings = brand.clothings, !clothings.isEmpty {
            brandToDelete = brand
            showingDeleteAlert = true
        } else {
            performDelete(brand)
        }
    }
    
    private func performDelete(_ brand: Brand) {
        if selectedBrand?.id == brand.id {
            selectedBrand = nil
        }
        modelContext.delete(brand)
    }
    
    private func selectBrand(_ brand: Brand) {
        selectedBrand = brand
        dismiss()
    }
}
