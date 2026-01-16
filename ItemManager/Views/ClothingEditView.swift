//
//  ClothingEditView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation

struct ClothingEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var clothing: Clothing?
    
    // Form States
    @State private var name: String = ""
    @State private var brandName: String = ""
    @State private var types: String = ""
    @State private var colors: String = ""
    @State private var sizes: String = ""
    @State private var accessories: String = ""
    @State private var imagePaths: [String] = []
    @State private var isShared: Bool = false
    
    // Tag States
    @State private var showingAddTagSheet = false
    @State private var selectedTags: [Tag] = []
    
    // Price States
    @State private var priceTotal: Double = 0.0
    @State private var deposit: Double = 0.0
    @State private var balance: Double = 0.0
    @State private var accessoriesPrice: Double = 0.0
    
    // Purchase States
    @State private var purchaseDate: Date = Date()
    @State private var note: String = ""
    
    init(clothing: Clothing?) {
        _clothing = State(initialValue: clothing)
    }
    
    var isEditing: Bool { clothing != nil }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - 裙子信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("裙子信息")
                        .font(.headline)
                    
                    ImagePickerGrid(imagePaths: $imagePaths)
                    
                    RoundedTextField(title: "裙子名称", placeholder: "请输入裙子名称", text: $name, isRequired: true)
                    
                    RoundedTextField(title: "品牌名称", placeholder: "请输入品牌名称", text: $brandName)
                    
                    RoundedTextField(title: "类型 (逗号分隔，如: JSK,OP,SK)", placeholder: "例如: JSK,OP", text: $types)
                    RoundedTextField(title: "颜色 (逗号分隔，如: 粉色,白色,蓝色)", placeholder: "例如: 粉色,白色", text: $colors)
                    RoundedTextField(title: "尺码 (逗号分隔，如: S,M,L)", placeholder: "例如: S,M,L", text: $sizes)
                    RoundedTextField(title: "小物 (逗号分隔，如: BNT,发箍KC,发带)", placeholder: "例如: BNT,发箍KC", text: $accessories)
                    
                    Toggle("同步到裙子社区", isOn: $isShared)
                        .padding(.top, 8)
                    Text("分享你的裙子给其他用户参考")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                
                // MARK: - 标签分类
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("标签分类")
                            .font(.headline)
                        Spacer()
                        Button(action: { showingAddTagSheet = true }) {
                            Label("管理标签", systemImage: "tag")
                                .font(.subheadline)
                        }
                    }
                    
                    if !selectedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(selectedTags) { tag in
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: tag.colorHex))
                                            .frame(width: 8, height: 8)
                                        Text(tag.name)
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: tag.colorHex).opacity(0.2))
                                    .cornerRadius(16)
                                }
                            }
                        }
                    } else {
                        Text("暂无标签")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("可选择多个标签分类，帮助你更好地管理衣橱")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .sheet(isPresented: $showingAddTagSheet) {
                    TagSelectionView(selectedTags: $selectedTags)
                }
                
                // MARK: - 价格信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("价格信息")
                        .font(.headline)
                    
                    PriceRow(title: "裙子总价", value: $priceTotal)
                    PriceRow(title: "定金", value: $deposit)
                    PriceRow(title: "尾款", value: $balance)
                    PriceRow(title: "小物总价", value: $accessoriesPrice)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                
                // MARK: - 购买信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("购买信息")
                        .font(.headline)
                    
                    DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                    
                    VStack(alignment: .leading) {
                        Text("备注")
                        TextEditor(text: $note)
                            .frame(height: 100)
                            .padding(4)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(isEditing ? "编辑" : "手动添加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    // 如果是新建状态且用户取消，需要清理已上传的图片
                    if !isEditing {
                        for path in imagePaths {
                            ImageManager.shared.deleteImage(fileName: path, context: modelContext)
                        }
                    }
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(name.isEmpty)
            }
        }
        .onAppear {
            if let c = clothing {
                name = c.name
                brandName = c.brand?.name ?? ""
                types = c.types
                colors = c.colors
                sizes = c.sizes
                accessories = c.accessories
                imagePaths = c.imagePaths
                isShared = c.isShared
                priceTotal = NSDecimalNumber(decimal: c.price).doubleValue
                deposit = NSDecimalNumber(decimal: c.deposit).doubleValue
                balance = NSDecimalNumber(decimal: c.balance).doubleValue
                accessoriesPrice = NSDecimalNumber(decimal: c.accessoriesPrice).doubleValue
                purchaseDate = c.purchaseDate
                note = c.note
                selectedTags = c.tags ?? []
            }
        }
    }
    
    private func normalizeTags(_ input: String) -> String {
        let components = input.replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.joined(separator: ",")
    }
    
    private func getOrCreateBrand(name: String) -> Brand? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        
        let descriptor = FetchDescriptor<Brand>(
            predicate: #Predicate { $0.name == trimmedName }
        )
        
        do {
            let brands = try modelContext.fetch(descriptor)
            if let existingBrand = brands.first {
                return existingBrand
            } else {
                let newBrand = Brand(name: trimmedName)
                modelContext.insert(newBrand)
                return newBrand
            }
        } catch {
            AppLogger.error("Failed to fetch brand: \(error)")
            // Fallback: create new
            let newBrand = Brand(name: trimmedName)
            modelContext.insert(newBrand)
            return newBrand
        }
    }
    
    private func save() {
        let finalBrand = getOrCreateBrand(name: brandName)
        let finalTypes = normalizeTags(types)
        let finalColors = normalizeTags(colors)
        let finalSizes = normalizeTags(sizes)
        let finalAccessories = normalizeTags(accessories)
        
        if let c = clothing {
            // Update
            AppLogger.info("Updating clothing: \(c.id)")
            c.name = name
            c.brand = finalBrand
            c.types = finalTypes
            c.colors = finalColors
            c.sizes = finalSizes
            c.accessories = finalAccessories
            c.imagePaths = imagePaths
            c.isShared = isShared
            c.price = Decimal(priceTotal)
            c.deposit = Decimal(deposit)
            c.balance = Decimal(balance)
            c.accessoriesPrice = Decimal(accessoriesPrice)
            c.purchaseDate = purchaseDate
            c.note = note
            c.tags = selectedTags
            c.updatedAt = Date()
        } else {
            // Create
            AppLogger.info("Creating new clothing: \(name)")
            let newClothing = Clothing(
                name: name,
                brand: finalBrand,
                types: finalTypes,
                colors: finalColors,
                sizes: finalSizes,
                accessories: finalAccessories,
                imagePaths: imagePaths,
                isShared: isShared,
                price: Decimal(priceTotal),
                deposit: Decimal(deposit),
                balance: Decimal(balance),
                accessoriesPrice: Decimal(accessoriesPrice),
                purchaseDate: purchaseDate,
                note: note
            )
            newClothing.tags = selectedTags
            modelContext.insert(newClothing)
        }
        dismiss()
    }
}

struct PriceRow: View {
    var title: String
    @Binding var value: Double
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0.00", value: $value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("¥")
                .foregroundStyle(.secondary)
        }
    }
}
