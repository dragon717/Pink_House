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
    @Query private var allClothings: [Clothing]
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
                VStack(alignment: .leading, spacing: 16) {
                    Text("裙子信息")
                        .font(.headline)
                    
                    ImagePickerGrid(imagePaths: $imagePaths)
                    
                    AutoCompleteTextField(title: "裙子名称", placeholder: "请输入裙子名称", text: $name, field: .name, isRequired: true)
                    
                    // Brand Field with Selection Button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("品牌名称")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                // Try to find existing brand
                                if !brandName.isEmpty {
                                    let name = brandName
                                    let descriptor = FetchDescriptor<Brand>(predicate: #Predicate { $0.name == name })
                                    if let existing = try? modelContext.fetch(descriptor).first {
                                        tempSelectedBrand = existing
                                    } else {
                                        tempSelectedBrand = nil
                                    }
                                } else {
                                    tempSelectedBrand = nil
                                }
                                showingBrandSelection = true
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(Color(uiColor: .tertiarySystemFill))
                                    .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            AutoCompleteTextField(title: "", placeholder: "请输入品牌名称", text: $brandName, field: .brand)
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
                    
                    ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                        if visibilityManager.isVisible(field) {
                            buildFieldView(for: field)
                        }
                    }
                    
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
                
                // MARK: - 价格信息
                VStack(alignment: .leading, spacing: 24) {
                    Text("价格信息")
                        .font(.headline)
                    
                    // 原价和总价
                    VStack(spacing: 12) {
                        PriceRow(title: "原价", value: $originalPrice)
                        Divider()
                        PriceRow(title: "裙子总价合计", subtitle: "(自动计算=定金+尾款)", value: $priceTotal)
                    }
                    
                    // 定金和尾款
                    VStack(spacing: 12) {
                        PriceRow(title: "定金", value: $deposit)
                        Divider()
                        PriceRow(title: "尾款", value: $balance)
                    }
                    
                    // 小物总价
                    PriceRow(title: "小物总价", value: $accessoriesPrice)
                        .disabled(!accessoryList.isEmpty)
                    
                    // 自定义小物列表
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("自定义小物明细")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: addAccessory) {
                                Label("添加", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                        }
                        
                        if !accessoryList.isEmpty {
                            ForEach($accessoryList) { $item in
                                HStack {
                                    TextField("小物名称", text: $item.name)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    TextField("0", value: Binding<Double?>(
                                        get: { item.price == 0 ? nil : item.price },
                                        set: { item.price = $0 ?? 0 }
                                    ), format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: item.price) { _, _ in
                                            calculateAccessoriesTotal()
                                        }
                                    
                                    Menu {
                                        Button(role: .destructive) {
                                            if let index = accessoryList.firstIndex(where: { $0.id == item.id }) {
                                                deleteAccessory(at: IndexSet(integer: index))
                                            }
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            moveAccessoryUp(item)
                                        } label: {
                                            Label("上移", systemImage: "arrow.up")
                                        }
                                        
                                        Button {
                                            moveAccessoryDown(item)
                                        } label: {
                                            Label("下移", systemImage: "arrow.down")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    
                    HStack {
                        Text("库存数量")
                        Spacer()
                        Stepper("", value: $stock, in: 1...999)
                            .labelsHidden()
                        Text("\(stock)")
                            .font(.body.monospacedDigit())
                            .frame(minWidth: 40, alignment: .trailing)
                    }
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
                        Toggle("加入尾款天使", isOn: $isDepositPlan)
                            .tint(.green)
                        
                        Text("① 无限量创建尾款天使")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("勾选后，该裙子将显示在尾款天使中")
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
                                
                                Text("设置预估尾款时间范围，方便在尾款天使中统计和提醒")
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
                originalPrice = NSDecimalNumber(decimal: c.originalPrice).doubleValue
                let depositVal = NSDecimalNumber(decimal: c.deposit).doubleValue
                let balanceVal = NSDecimalNumber(decimal: c.balance).doubleValue
                deposit = depositVal
                balance = balanceVal
                
                accessoriesPrice = NSDecimalNumber(decimal: c.accessoriesPrice).doubleValue
                
                // Load accessory items
                if let items = c.accessoryItems {
                    accessoryList = items.sorted(by: { $0.sortIndex < $1.sortIndex })
                        .map { AccessoryItemData(id: UUID(), name: $0.name, price: NSDecimalNumber(decimal: $0.price).doubleValue) }
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
    
    private func isMultiSelect(_ field: ClothingField) -> Bool {
        switch field {
        case .types, .colors, .sizes, .accessories: return true
        case .length, .condition: return false
        }
    }
    
    private func getAllOptions(for field: ClothingField) -> [String] {
        var uniqueItems = Set<String>()
        
        // KeyPaths
        let keyPath: KeyPath<Clothing, String>
        switch field {
        case .types: keyPath = \.types
        case .colors: keyPath = \.colors
        case .sizes: keyPath = \.sizes
        case .length: keyPath = \.length
        case .condition: keyPath = \.condition
        case .accessories: keyPath = \.accessories
        }
        
        let isCommaSeparated = isMultiSelect(field)
        
        for clothing in allClothings {
            let value = clothing[keyPath: keyPath]
            if isCommaSeparated {
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for part in parts {
                    if !part.isEmpty {
                        uniqueItems.insert(part)
                    }
                }
            } else {
                if !value.isEmpty {
                    uniqueItems.insert(value)
                }
            }
        }
        
        // Default options for Condition if empty
        if field == .condition && uniqueItems.isEmpty {
            return ["全新", "99新", "95新", "9成新", "8成新", "有瑕疵"]
        }
        
        return Array(uniqueItems).sorted()
    }

    @ViewBuilder
    private func buildFieldView(for field: ClothingField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title for consistency (Optional, since AutoCompleteTextField has title, but we want to group button and field)
             Text(fieldTitle(for: field))
                 .font(.subheadline)
                 .foregroundStyle(.secondary)
                 .padding(.leading, 4)
            
            HStack(spacing: 8) {
                Button(action: {
                    activeSelectionField = field
                    showingGenericSelection = true
                }) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                
                switch field {
                case .types:
                    AutoCompleteTextField(title: "", placeholder: "例如: JSK,OP", text: $types, field: .type)
                case .colors:
                    AutoCompleteTextField(title: "", placeholder: "例如: 粉色,白色", text: $colors, field: .color)
                case .sizes:
                    AutoCompleteTextField(title: "", placeholder: "例如: S,M,L", text: $sizes, field: .size)
                case .length:
                    AutoCompleteTextField(title: "", placeholder: "例如: 90cm", text: $length, field: .size)
                case .condition:
                    AutoCompleteTextField(title: "", placeholder: "例如: 全新", text: $condition, field: .condition)
                case .accessories:
                    AutoCompleteTextField(title: "", placeholder: "例如: BNT,发箍KC", text: $accessories, field: .accessory, externalSearch: { query in
                        return await SuggestionManager.shared.searchAccessories(query: query, modelContext: modelContext)
                    })
                }
            }
        }
    }
    
    private func fieldTitle(for field: ClothingField) -> String {
        switch field {
        case .types: return "类型 (逗号分隔，如: JSK,OP,SK,小物)"
        case .colors: return "颜色 (逗号分隔，如: 粉色,白色,蓝色)"
        case .sizes: return "尺码 (逗号分隔，如: S,M,L)"
        case .length: return "衣长 (如: 90cm, 100cm)"
        case .condition: return "状态（如: 全新, 95新）"
        case .accessories: return "小物 (逗号分隔，如: BNT,发箍KC,发带)"
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
                AccessoryItem(name: data.name, price: Decimal(data.price), sortIndex: index)
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
                AccessoryItem(name: data.name, price: Decimal(data.price), sortIndex: index)
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
            SharedPersistence.shared.syncWidgetData()
        } catch {
            AppLogger.error("Failed to save context: \(error)")
        }
        
        dismiss()
    }
    
    private func addAccessory() {
        let newItem = AccessoryItemData(name: "", price: 0.0)
        accessoryList.append(newItem)
    }
    
    private func deleteAccessory(at offsets: IndexSet) {
        accessoryList.remove(atOffsets: offsets)
        calculateAccessoriesTotal()
    }
    
    private func moveAccessoryUp(_ item: AccessoryItemData) {
        guard let index = accessoryList.firstIndex(of: item), index > 0 else { return }
        accessoryList.swapAt(index, index - 1)
    }
    
    private func moveAccessoryDown(_ item: AccessoryItemData) {
        guard let index = accessoryList.firstIndex(of: item), index < accessoryList.count - 1 else { return }
        accessoryList.swapAt(index, index + 1)
    }
    
    private func calculateAccessoriesTotal() {
        let total = accessoryList.reduce(0) { $0 + $1.price }
        accessoriesPrice = total
    }
}

struct PriceRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var value: Double
    
    var body: some View {
        HStack {
            if let subtitle = subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(title)
            }
            Spacer()
            TextField("0", value: Binding<Double?>(
                get: { value == 0 ? nil : value },
                set: { value = $0 ?? 0 }
            ), format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("¥")
                .foregroundStyle(.secondary)
        }
    }
}

struct AccessoryItemData: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var price: Double
}

