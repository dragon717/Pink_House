//
//  BrandSelectionView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/17/26.
//

import SwiftUI
import SwiftData
import Foundation

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
                            TextField("新品牌名称", text: $newBrandName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addNewBrand()
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
                                Circle()
                                    .fill(Color(hex: brand.colorHex))
                                    .frame(width: 12, height: 12)
                                
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
                BrandEditSheet(brand: brand, predefinedColors: predefinedColors)
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
            let newBrand = Brand(name: newBrandName, colorHex: selectedColorHex)
            modelContext.insert(newBrand)
            selectedBrand = newBrand // Auto select new brand
        }
        
        newBrandName = ""
        selectedColorHex = "#FFB6C1" // Reset to default
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

struct BrandEditSheet: View {
    let brand: Brand
    let predefinedColors: [String]
    
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    
    init(brand: Brand, predefinedColors: [String]) {
        self.brand = brand
        self.predefinedColors = predefinedColors
        _name = State(initialValue: brand.name)
        _colorHex = State(initialValue: brand.colorHex)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("品牌信息") {
                    TextField("品牌名称", text: $name)
                }
                
                Section("品牌颜色") {
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
            .navigationTitle("编辑品牌")
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
        brand.name = name
        brand.colorHex = colorHex
        dismiss()
    }
}
