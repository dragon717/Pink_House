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
    @Query(filter: #Predicate<Clothing> { $0.isDeleted == false }) private var allClothings: [Clothing]
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    
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
    @State private var originalPrice: Double = 0.0
    @State private var priceTotal: Double = 0.0
    @State private var deposit: Double = 0.0
    @State private var balance: Double = 0.0
    @State private var accessoriesPrice: Double = 0.0
    @State private var stock: Int = 1
    
    // Selection Sheets
    @State private var showingBrandSelection = false
    @State private var tempSelectedBrand: Brand?
    @State private var activeSelectionField: ClothingField?
    @State private var showingGenericSelection = false
    
    // Custom Accessories
    @State private var accessoryList: [AccessoryItemData] = []
    
    // Purchase States
    @State private var purchaseDate: Date = Date()
    @State private var depositDate: Date = Date()
    @State private var isDepositPlan: Bool = false
    @State private var finalPaymentDate: Date = Date()
    @State private var finalPaymentEndDate: Date = Date()
    @State private var note: String = ""
    
    private var initialBrandID: UUID?
    private var initialTypes: Set<String>?
    
    init(clothing: Clothing?, initialBrandID: UUID? = nil, initialTypes: Set<String>? = nil) {
        _clothing = State(initialValue: clothing)
        self.initialBrandID = initialBrandID
        self.initialTypes = initialTypes
    }
    
    var isEditing: Bool { clothing != nil }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - 裙子信息
                ClothingBasicInfoView(
                    imagePaths: $imagePaths,
                    name: $name,
                    brandName: $brandName,
                    isShared: $isShared,
                    types: $types,
                    colors: $colors,
                    sizes: $sizes,
                    length: $length,
                    condition: $condition,
                    accessories: $accessories,
                    showingBrandSelection: $showingBrandSelection,
                    showingGenericSelection: $showingGenericSelection,
                    activeSelectionField: $activeSelectionField
                )
                
                // MARK: - 标签分类
                ClothingTagsView(
                    selectedTags: $selectedTags,
                    showingAddTagSheet: $showingAddTagSheet
                )
                
                // MARK: - 价格信息
                ClothingPriceView(
                    originalPrice: $originalPrice,
                    priceTotal: $priceTotal,
                    deposit: $deposit,
                    balance: $balance,
                    accessoriesPrice: $accessoriesPrice,
                    stock: $stock,
                    accessoryList: $accessoryList
                )
                
                // MARK: - 购买信息
                ClothingPurchaseInfoView(
                    purchaseDate: $purchaseDate,
                    depositDate: $depositDate,
                    isDepositPlan: $isDepositPlan,
                    finalPaymentDate: $finalPaymentDate,
                    finalPaymentEndDate: $finalPaymentEndDate,
                    note: $note
                )
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
        .sheet(isPresented: $showingBrandSelection) {
            BrandSelectionView(selectedBrand: $tempSelectedBrand)
        }
        .onChange(of: tempSelectedBrand) { _, newValue in
            if let brand = newValue {
                brandName = brand.name
            }
        }
        .sheet(isPresented: $showingAddTagSheet) {
            TagSelectionView(selectedTags: $selectedTags)
        }
        .sheet(isPresented: $showingGenericSelection) {
            if let field = activeSelectionField {
                SimpleStringSelectionView(
                    title: "选择\(field.rawValue)",
                    options: getAllOptions(for: field),
                    allowMultiple: isMultiSelect(field),
                    selection: binding(for: field)
                )
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
                originalPrice = NSDecimalNumber(decimal: c.originalPrice).doubleValue
                let depositVal = NSDecimalNumber(decimal: c.deposit).doubleValue
                let balanceVal = NSDecimalNumber(decimal: c.balance).doubleValue
                deposit = depositVal
                balance = balanceVal
                
                accessoriesPrice = NSDecimalNumber(decimal: c.accessoriesPrice).doubleValue
                
                // Load accessory items
                if let items = c.accessoryItems {
                    accessoryList = items.sorted(by: { $0.sortIndex < $1.sortIndex })
                        .map { AccessoryItemData(id: UUID(), name: $0.name, price: NSDecimalNumber(decimal: $0.price).doubleValue, deposit: NSDecimalNumber(decimal: $0.deposit).doubleValue, balance: NSDecimalNumber(decimal: $0.balance).doubleValue) }
                }
                
                stock = c.stock
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
            } else {
                // New Item: Apply initial values from filters if available
                if brandName.isEmpty, let brandID = initialBrandID {
                    let descriptor = FetchDescriptor<Brand>(predicate: #Predicate { $0.id == brandID })
                    if let brand = try? modelContext.fetch(descriptor).first {
                        brandName = brand.name
                    }
                }
                
                if types.isEmpty, let initTypes = initialTypes, !initTypes.isEmpty {
                    // Filter out empty strings just in case
                    let validTypes = initTypes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if !validTypes.isEmpty {
                        types = validTypes.joined(separator: ",")
                    }
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
    
    // MARK: - Helpers
    
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
    
    private func updateTotalPrice() {
        // 若定金和尾款都存在，则自动校正总价
        if deposit > 0 && balance > 0 {
            priceTotal = deposit + balance
        }
    }
    
    private func getAllOptions(for field: ClothingField) -> [String] {
        // Collect all unique values from existing clothings
        var options: Set<String> = []
        for item in allClothings {
            switch field {
            case .types:
                options.formUnion(item.types.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .colors:
                options.formUnion(item.colors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .sizes:
                options.formUnion(item.sizes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .accessories:
                options.formUnion(item.accessories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            case .length:
                if !item.length.isEmpty { options.insert(item.length) }
            case .condition:
                if !item.condition.isEmpty { options.insert(item.condition) }
            default:
                break
            }
        }
        return options.filter { !$0.isEmpty }.sorted()
    }
    
    private func isMultiSelect(_ field: ClothingField) -> Bool {
        switch field {
        case .types, .colors, .sizes, .accessories:
            return true
        default:
            return false
        }
    }
    
    private func binding(for field: ClothingField) -> Binding<String> {
        switch field {
        case .types: return $types
        case .colors: return $colors
        case .sizes: return $sizes
        case .length: return $length
        case .condition: return $condition
        case .accessories: return $accessories
        }
    }

    private func save() {
        updateTotalPrice()
        
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
            c.originalPrice = Decimal(originalPrice)
            c.price = Decimal(priceTotal)
            c.deposit = Decimal(deposit)
            c.balance = Decimal(balance)
            c.accessoriesPrice = Decimal(accessoriesPrice)
            
            // Update accessory items
            // Remove old items (since we are replacing the list)
            if let oldItems = c.accessoryItems {
                for item in oldItems {
                    modelContext.delete(item)
                }
            }
            // Create new items
            let newItems = accessoryList.enumerated().map { index, data in
                AccessoryItem(name: data.name, price: Decimal(data.price), deposit: Decimal(data.deposit), balance: Decimal(data.balance), sortIndex: index)
            }
            c.accessoryItems = newItems
            
            c.purchaseDate = purchaseDate
            c.depositDate = depositDate
            c.isDepositPlan = isDepositPlan
            c.finalPaymentDate = finalPaymentDate
            c.finalPaymentEndDate = finalPaymentEndDate
            c.note = note
            c.stock = stock
            c.tags = selectedTags
            c.updatedAt = Date()
            
            // Update notification
            NotificationManager.shared.scheduleNotification(for: c)
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
                originalPrice: Decimal(originalPrice),
                price: Decimal(priceTotal),
                deposit: Decimal(deposit),
                balance: Decimal(balance),
                accessoriesPrice: Decimal(accessoriesPrice),
                purchaseDate: purchaseDate,
                depositDate: depositDate,
                isDepositPlan: isDepositPlan,
                finalPaymentDate: finalPaymentDate,
                finalPaymentEndDate: finalPaymentEndDate,
                note: note,
                stock: stock
            )
            
            let newItems = accessoryList.enumerated().map { index, data in
                AccessoryItem(name: data.name, price: Decimal(data.price), deposit: Decimal(data.deposit), balance: Decimal(data.balance), sortIndex: index)
            }
            newClothing.accessoryItems = newItems
            
            newClothing.tags = selectedTags
            modelContext.insert(newClothing)
            
            // Schedule notification
            NotificationManager.shared.scheduleNotification(for: newClothing)
        }
        
        // Save context and sync widget
        do {
            try modelContext.save()
            Task { await SharedPersistence.shared.syncWidgetData() }
        } catch {
            AppLogger.error("Failed to save context: \(error)")
        }
        
        dismiss()
    }
}
