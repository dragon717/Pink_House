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
    @State private var length: String = ""
    @State private var condition: String = "全新"
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
    @State private var depositDate: Date = Date()
    @State private var isDepositPlan: Bool = false
    @State private var finalPaymentDate: Date = Date()
    @State private var finalPaymentEndDate: Date = Date()
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
                    
                    AutoCompleteTextField(title: "裙子名称", placeholder: "请输入裙子名称", text: $name, field: .name, isRequired: true)
                    
                    AutoCompleteTextField(title: "品牌名称", placeholder: "请输入品牌名称", text: $brandName, field: .brand)
                    
                    AutoCompleteTextField(title: "类型 (逗号分隔，如: JSK,OP,SK,小物)", placeholder: "例如: JSK,OP", text: $types, field: .type)
                    
                    AutoCompleteTextField(title: "颜色 (逗号分隔，如: 粉色,白色,蓝色)", placeholder: "例如: 粉色,白色", text: $colors, field: .color)
                    
                    AutoCompleteTextField(title: "尺码 (逗号分隔，如: S,M,L)", placeholder: "例如: S,M,L", text: $sizes, field: .size)
                    
                    AutoCompleteTextField(title: "衣长 (如: 90cm, 100cm)", placeholder: "例如: 90cm", text: $length, field: .size) // 使用 size 的建议或者新建一个 field
                    
                    AutoCompleteTextField(title: "状态（如: 全新, 95新）", placeholder: "例如: 全新", text: $condition, field: .condition)
                    
                    AutoCompleteTextField(title: "小物 (逗号分隔，如: BNT,发箍KC,发带)", placeholder: "例如: BNT,发箍KC", text: $accessories, field: .accessory, externalSearch: { query in
                        // 使用 SuggestionManager 中稳健的内存过滤方法
                        return await SuggestionManager.shared.searchAccessories(query: query, modelContext: modelContext)
                    })
                    
                    Toggle("同步到裙子社区", isOn: $isShared)
                        .padding(.top, 8)
                    Text("分享你的裙子给其他用户参考")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
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
                .background(Color(uiColor: .secondarySystemGroupedBackground))
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
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                
                // MARK: - 购买信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("购买信息")
                        .font(.headline)
                    
                    DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("加入定尾计划", isOn: $isDepositPlan)
                            .tint(.green)
                        
                        Text("① 无限量创建定尾计划")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("勾选后，该裙子将显示在定尾计划中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if isDepositPlan {
                            VStack(alignment: .leading, spacing: 8) {
                                DatePicker("定金日期", selection: $depositDate, displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                
                                DatePicker("预估尾款时间 (开始)", selection: $finalPaymentDate, displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                
                                DatePicker("预估尾款时间 (结束)", selection: $finalPaymentEndDate, displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                
                                Text("设置预估尾款时间范围，方便在定尾计划中统计和提醒")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                    
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
                .background(Color(uiColor: .secondarySystemGroupedBackground))
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
            print("ClothingEditView: onAppear triggered")
            // 加载自动补全数据
            SuggestionManager.shared.loadDataAndBuildIndex(modelContext: modelContext)
            
            if let c = clothing {
                name = c.name
                brandName = c.brand?.name ?? ""
                types = c.types
                colors = c.colors
                sizes = c.sizes
                length = c.length
                condition = c.condition
                accessories = c.accessories
                imagePaths = c.imagePaths
                isShared = c.isShared
                let depositVal = NSDecimalNumber(decimal: c.deposit).doubleValue
                let balanceVal = NSDecimalNumber(decimal: c.balance).doubleValue
                deposit = depositVal
                balance = balanceVal
                
                accessoriesPrice = NSDecimalNumber(decimal: c.accessoriesPrice).doubleValue
                purchaseDate = c.purchaseDate
                depositDate = c.depositDate ?? Date()
                isDepositPlan = c.isDepositPlan
                finalPaymentDate = c.finalPaymentDate ?? Date()
                finalPaymentEndDate = c.finalPaymentEndDate ?? (c.finalPaymentDate ?? Date())
                note = c.note
                selectedTags = c.tags ?? []
                
                // 加载时，如果定金和尾款都存在，则自动校正总价
                if depositVal > 0 && balanceVal > 0 {
                    priceTotal = depositVal + balanceVal
                } else {
                    priceTotal = NSDecimalNumber(decimal: c.price).doubleValue
                }
            }
        }
        .onChange(of: deposit) { oldValue, newValue in
            updateTotalPrice()
        }
        .onChange(of: balance) { oldValue, newValue in
            updateTotalPrice()
        }
    }
    
    private func updateTotalPrice() {
        if deposit > 0 && balance > 0 {
            priceTotal = deposit + balance
        }
    }
    
    private func normalizeTags(_ input: String) -> String {
        let components = input.replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
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
        // 若定金和尾款都存在，则自动校正总价
        if deposit > 0 && balance > 0 {
            priceTotal = deposit + balance
        }
        
        let finalBrand = getOrCreateBrand(name: brandName)
        let finalTypes = normalizeTags(types)
        let finalColors = normalizeTags(colors)
        let finalSizes = normalizeTags(sizes)
        let finalAccessories = normalizeTags(accessories)
        let finalLength = length.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let finalCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // 更新自动补全索引
        SuggestionManager.shared.addData(field: .name, value: name)
        SuggestionManager.shared.addData(field: .brand, value: brandName)
        SuggestionManager.shared.addData(field: .type, value: finalTypes)
        SuggestionManager.shared.addData(field: .color, value: finalColors)
        SuggestionManager.shared.addData(field: .size, value: finalSizes)
        SuggestionManager.shared.addData(field: .accessory, value: finalAccessories)
        SuggestionManager.shared.addData(field: .condition, value: finalCondition)
        
        // 特殊逻辑：如果类型包含"小物"，则该物品名称也加入小物索引
        SuggestionManager.shared.addAccessoryNameIfTypeContainsAccessory(name: name, types: finalTypes)
        
        if let c = clothing {
            // Update
            AppLogger.info("Updating clothing: \(c.id)")
            c.name = name
            c.brand = finalBrand
            c.types = finalTypes
            c.colors = finalColors
            c.sizes = finalSizes
            c.length = finalLength
            c.condition = finalCondition
            c.accessories = finalAccessories
            c.imagePaths = imagePaths
            c.isShared = isShared
            c.price = Decimal(priceTotal)
            c.deposit = Decimal(deposit)
            c.balance = Decimal(balance)
            c.accessoriesPrice = Decimal(accessoriesPrice)
            c.purchaseDate = purchaseDate
            c.depositDate = depositDate
            c.isDepositPlan = isDepositPlan
            c.finalPaymentDate = finalPaymentDate
            c.finalPaymentEndDate = finalPaymentEndDate
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
                length: finalLength,
                condition: finalCondition,
                accessories: finalAccessories,
                imagePaths: imagePaths,
                isShared: isShared,
                price: Decimal(priceTotal),
                deposit: Decimal(deposit),
                balance: Decimal(balance),
                accessoriesPrice: Decimal(accessoriesPrice),
                purchaseDate: purchaseDate,
                depositDate: depositDate,
                isDepositPlan: isDepositPlan,
                finalPaymentDate: finalPaymentDate,
                finalPaymentEndDate: finalPaymentEndDate,
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
