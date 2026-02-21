//
//  ClothingEditView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

// MARK: - 编辑草稿数据结构
struct ClothingEditDraft: Codable {
    let id: UUID
    let name: String
    let brandName: String
    let types: String
    let colors: String
    let sizes: String
    let length: String
    let condition: String
    let accessories: String
    let imagePaths: [String]
    let isShared: Bool
    let originalPrice: Double
    let priceTotal: Double
    let deposit: Double
    let balance: Double
    let accessoriesPrice: Double
    let stock: Int
    let purchaseDate: Date
    let depositDate: Date
    let isDepositPlan: Bool
    let finalPaymentDate: Date
    let finalPaymentEndDate: Date
    let note: String
    let accessoryList: [AccessoryItemData]
    let timestamp: Date
    
    init(id: UUID = UUID(),
         name: String,
         brandName: String,
         types: String,
         colors: String,
         sizes: String,
         length: String,
         condition: String,
         accessories: String,
         imagePaths: [String],
         isShared: Bool,
         originalPrice: Double,
         priceTotal: Double,
         deposit: Double,
         balance: Double,
         accessoriesPrice: Double,
         stock: Int,
         purchaseDate: Date,
         depositDate: Date,
         isDepositPlan: Bool,
         finalPaymentDate: Date,
         finalPaymentEndDate: Date,
         note: String,
         accessoryList: [AccessoryItemData]) {
        self.id = id
        self.name = name
        self.brandName = brandName
        self.types = types
        self.colors = colors
        self.sizes = sizes
        self.length = length
        self.condition = condition
        self.accessories = accessories
        self.imagePaths = imagePaths
        self.isShared = isShared
        self.originalPrice = originalPrice
        self.priceTotal = priceTotal
        self.deposit = deposit
        self.balance = balance
        self.accessoriesPrice = accessoriesPrice
        self.stock = stock
        self.purchaseDate = purchaseDate
        self.depositDate = depositDate
        self.isDepositPlan = isDepositPlan
        self.finalPaymentDate = finalPaymentDate
        self.finalPaymentEndDate = finalPaymentEndDate
        self.note = note
        self.accessoryList = accessoryList
        self.timestamp = Date()
    }
}

// MARK: - 草稿管理器
final class ClothingEditDraftManager {
    static let shared = ClothingEditDraftManager()

    private let userDefaults = UserDefaults.standard
    private let draftKey = "ClothingEditDraft"
    private let draftIDKey = "ClothingEditDraftID"

    // 当前编辑状态（用于后台保存）
    @Published var currentDraft: ClothingEditDraft?

    private init() {
        // 监听应用进入后台通知
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("DraftManager: Background notification received")
            if let draft = self?.currentDraft {
                print("DraftManager: Saving current draft on background, images: \(draft.imagePaths.count)")
                self?.saveDraft(draft)
            } else {
                print("DraftManager: No current draft to save on background")
            }
        }
    }

    func saveDraft(_ draft: ClothingEditDraft) {
        print("DraftManager: Saving draft with ID: \(draft.id), images: \(draft.imagePaths.count)")
        if let data = try? JSONEncoder().encode(draft) {
            userDefaults.set(data, forKey: draftKey)
            userDefaults.set(draft.id.uuidString, forKey: draftIDKey)
            userDefaults.synchronize()
            print("DraftManager: Draft saved successfully")
        } else {
            print("DraftManager: Failed to encode draft")
        }
    }

    func loadDraft() -> ClothingEditDraft? {
        guard let data = userDefaults.data(forKey: draftKey) else {
            print("DraftManager: No draft data found in UserDefaults")
            return nil
        }
        guard let draft = try? JSONDecoder().decode(ClothingEditDraft.self, from: data) else {
            print("DraftManager: Failed to decode draft data")
            return nil
        }
        print("DraftManager: Loaded draft with ID: \(draft.id), images: \(draft.imagePaths.count)")
        return draft
    }

    func loadDraftID() -> UUID? {
        guard let idString = userDefaults.string(forKey: draftIDKey) else {
            print("DraftManager: No draftID found in UserDefaults")
            return nil
        }
        guard let uuid = UUID(uuidString: idString) else {
            print("DraftManager: Failed to parse draftID: \(idString)")
            return nil
        }
        print("DraftManager: Loaded draftID: \(uuid)")
        return uuid
    }

    func clearDraft() {
        print("DraftManager: Clearing draft")
        currentDraft = nil
        userDefaults.removeObject(forKey: draftKey)
        userDefaults.removeObject(forKey: draftIDKey)
        userDefaults.synchronize()
        print("DraftManager: Draft cleared")
    }

    func hasDraft() -> Bool {
        let hasDraft = loadDraft() != nil
        print("DraftManager: hasDraft = \(hasDraft)")
        return hasDraft
    }
}

struct ClothingEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Clothing> { $0.isDeleted == false }) private var allClothings: [Clothing]
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @State private var draftManager = ClothingEditDraftManager.shared
    
    @State private var clothing: Clothing?
    @State private var draftID: UUID = UUID()
    
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
    
    // 标记是否是通过"保存"按钮离开的
    @State private var isSaving = false
    
    // 标记是否从草稿继续（false表示新建，清除草稿）
    private var continueFromDraft: Bool
    
    // 标记是否已经处理过草稿逻辑（防止onAppear多次执行）
    @State private var hasProcessedDraft = false
    
    private var initialBrandID: UUID?
    private var initialTypes: Set<String>?
    
    init(clothing: Clothing?, initialBrandID: UUID? = nil, initialTypes: Set<String>? = nil, continueFromDraft: Bool = true) {
        _clothing = State(initialValue: clothing)
        self.initialBrandID = initialBrandID
        self.initialTypes = initialTypes
        self.continueFromDraft = continueFromDraft
        print("ClothingEditView: INIT called, isEditing: \(clothing != nil), continueFromDraft: \(continueFromDraft)")
    }
    
    var isEditing: Bool { clothing != nil }
    
    var body: some View {
        ZStack {
            // Background
            LiquidBackground()
                .ignoresSafeArea()
            
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
        }
        .navigationTitle(isEditing ? "编辑" : "手动创建")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    // 清除草稿
                    draftManager.clearDraft()
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
                    // 标记为保存操作
                    isSaving = true
                    // 保存前清除草稿
                    draftManager.clearDraft()
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
            print("ClothingEditView: onAppear triggered, isEditing: \(isEditing), draftID: \(draftID), continueFromDraft: \(continueFromDraft), hasProcessedDraft: \(hasProcessedDraft)")
            
            // 防止多次处理草稿逻辑
            guard !hasProcessedDraft else {
                print("ClothingEditView: Draft already processed, skipping")
                return
            }
            hasProcessedDraft = true
            
            // 加载自动补全数据
            SuggestionManager.shared.loadDataAndBuildIndex(modelContext: modelContext)

            // 尝试恢复草稿（视图可能被重新创建）
            if isEditing {
                print("ClothingEditView: Skipping draft restore, in editing mode")
            } else if continueFromDraft, let draft = draftManager.loadDraft() {
                print("ClothingEditView: Found draft with \(draft.imagePaths.count) images")
                // 恢复草稿
                restoreFromDraft(draft)
            } else if !continueFromDraft {
                // 用户选择"手动创建"，需要清除草稿并重新开始
                print("ClothingEditView: Creating new item (manual creation), clearing draft")
                draftManager.clearDraft()
                resetAllStates()
            } else {
                print("ClothingEditView: No draft found to restore")
            }

            // 更新当前草稿到管理器（用于后台保存）
            updateCurrentDraft()
            
            if let c = clothing {
                // 编辑模式：从数据库加载
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
        .onChange(of: imagePaths) { oldValue, newValue in
            print("ClothingEditView: imagePaths changed from \(oldValue.count) to \(newValue.count) images")
            // 更新当前草稿到管理器
            updateCurrentDraft()
            // 图片变化后立即保存草稿到磁盘，防止丢失
            if !isEditing {
                print("ClothingEditView: Image paths changed, immediately saving draft to disk")
                saveCurrentStateAsDraft()
            }
        }
        .onChange(of: name) { _, _ in updateCurrentDraft() }
        .onChange(of: brandName) { _, _ in updateCurrentDraft() }
        .onChange(of: types) { _, _ in updateCurrentDraft() }
        .onChange(of: colors) { _, _ in updateCurrentDraft() }
        .onChange(of: sizes) { _, _ in updateCurrentDraft() }
        .onChange(of: length) { _, _ in updateCurrentDraft() }
        .onChange(of: condition) { _, _ in updateCurrentDraft() }
        .onChange(of: accessories) { _, _ in updateCurrentDraft() }
        .onDisappear {
            print("ClothingEditView: onDisappear, isSaving: \(isSaving), isEditing: \(isEditing)")
            // 如果不是保存操作且不是编辑模式，保存草稿（作为后备方案）
            if !isSaving && !isEditing {
                print("ClothingEditView: Saving draft on disappear")
                saveCurrentStateAsDraft()
            } else {
                print("ClothingEditView: Not saving draft on disappear (isSaving: \(isSaving), isEditing: \(isEditing))")
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
    
    // 保存当前状态为草稿
    private func saveCurrentStateAsDraft() {
        print("ClothingEditView: saveCurrentStateAsDraft called, draftID: \(draftID), imagePaths count: \(imagePaths.count), name: \(name)")
        let draft = ClothingEditDraft(
            id: draftID,
            name: name,
            brandName: brandName,
            types: types,
            colors: colors,
            sizes: sizes,
            length: length,
            condition: condition,
            accessories: accessories,
            imagePaths: imagePaths,
            isShared: isShared,
            originalPrice: originalPrice,
            priceTotal: priceTotal,
            deposit: deposit,
            balance: balance,
            accessoriesPrice: accessoriesPrice,
            stock: stock,
            purchaseDate: purchaseDate,
            depositDate: depositDate,
            isDepositPlan: isDepositPlan,
            finalPaymentDate: finalPaymentDate,
            finalPaymentEndDate: finalPaymentEndDate,
            note: note,
            accessoryList: accessoryList
        )
        draftManager.saveDraft(draft)
        print("ClothingEditView: Draft saved successfully with \(draft.imagePaths.count) images")
    }

    // 更新当前草稿到管理器（用于后台保存）
    private func updateCurrentDraft() {
        // 只有在新建模式下才更新草稿
        guard !isEditing else { return }

        let draft = ClothingEditDraft(
            id: draftID,
            name: name,
            brandName: brandName,
            types: types,
            colors: colors,
            sizes: sizes,
            length: length,
            condition: condition,
            accessories: accessories,
            imagePaths: imagePaths,
            isShared: isShared,
            originalPrice: originalPrice,
            priceTotal: priceTotal,
            deposit: deposit,
            balance: balance,
            accessoriesPrice: accessoriesPrice,
            stock: stock,
            purchaseDate: purchaseDate,
            depositDate: depositDate,
            isDepositPlan: isDepositPlan,
            finalPaymentDate: finalPaymentDate,
            finalPaymentEndDate: finalPaymentEndDate,
            note: note,
            accessoryList: accessoryList
        )
        draftManager.currentDraft = draft
        print("ClothingEditView: Updated current draft with \(draft.imagePaths.count) images")
    }

    // 从草稿恢复状态
    private func restoreFromDraft(_ draft: ClothingEditDraft) {
        print("ClothingEditView: restoreFromDraft called, draft has \(draft.imagePaths.count) images, current has \(imagePaths.count) images")
        name = draft.name
        brandName = draft.brandName
        types = draft.types
        colors = draft.colors
        sizes = draft.sizes
        length = draft.length
        condition = draft.condition
        accessories = draft.accessories
        // 只有当草稿中的图片数量 >= 当前图片数量时才恢复图片
        // 避免覆盖用户刚添加但还没保存到草稿的图片
        if draft.imagePaths.count >= imagePaths.count {
            print("ClothingEditView: Restoring \(draft.imagePaths.count) images from draft")
            imagePaths = draft.imagePaths
        } else {
            print("ClothingEditView: Skipping image restore, draft has \(draft.imagePaths.count) images, current has \(imagePaths.count)")
        }
        isShared = draft.isShared
        originalPrice = draft.originalPrice
        priceTotal = draft.priceTotal
        deposit = draft.deposit
        balance = draft.balance
        accessoriesPrice = draft.accessoriesPrice
        stock = draft.stock
        purchaseDate = draft.purchaseDate
        depositDate = draft.depositDate
        isDepositPlan = draft.isDepositPlan
        finalPaymentDate = draft.finalPaymentDate
        finalPaymentEndDate = draft.finalPaymentEndDate
        note = draft.note
        accessoryList = draft.accessoryList
        draftID = draft.id
        print("ClothingEditView: Draft restored, draftID set to \(draftID)")
    }
    
    // 重置所有状态（用于新建时清除草稿）
    private func resetAllStates() {
        print("ClothingEditView: resetAllStates called")
        name = ""
        brandName = ""
        types = ""
        colors = ""
        sizes = ""
        length = ""
        condition = "全新"
        accessories = ""
        imagePaths = []
        isShared = false
        originalPrice = 0.0
        priceTotal = 0.0
        deposit = 0.0
        balance = 0.0
        accessoriesPrice = 0.0
        stock = 1
        purchaseDate = Date()
        depositDate = Date()
        isDepositPlan = false
        finalPaymentDate = Date()
        finalPaymentEndDate = Date()
        note = ""
        accessoryList = []
        selectedTags = []
        draftID = UUID()
        print("ClothingEditView: All states reset, new draftID: \(draftID)")
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
            // 检查 replacedCutoutID 是否还有效
            if let replacedID = c.replacedCutoutID {
                // 如果图片列表为空，或者 replacedCutoutID 对应的图片已经不在 imagePaths 中，则重置
                // 注意：imagePaths 存储的是文件名，我们需要根据 replacedCutoutID 找到对应的 CutoutItem，然后获取其 imagePath
                
                // 为了性能，我们先不查数据库，而是直接在 CutoutService 中提供一个辅助检查方法
                // 或者更简单：我们不依赖 CutoutItem 的查找，而是依赖 CutoutService.handleCutoutDeletion 已经在删除时处理了。
                // 但是！这里是全量替换 imagePaths。如果是 UI 上的“删除”操作，已经在 ImagePickerGrid 中触发了 handleCutoutDeletion。
                // 如果是“移动”或“添加”操作，imagePaths 会变化，但文件没被删。
                
                // 用户的需求是：若图片里删除抠图，则保存时，clothing.replacedCutoutID, 也应该重新保存（置空或更新）。
                // 在 ClothingEditView 中，imagePaths 是最终状态。
                // 如果 replacedCutoutID 对应的抠图图片还在 imagePaths 中，则保留。
                // 如果不在了，则置空。
                
                // 问题：我们只知道 replacedCutoutID (UUID)，不知道它对应的 imagePath。
                // 所以必须查询 CutoutItem。
                
                let descriptor = FetchDescriptor<CutoutItem>(predicate: #Predicate { $0.id == replacedID })
                if let cutout = try? modelContext.fetch(descriptor).first {
                    if !imagePaths.contains(cutout.imagePath) {
                        c.replacedCutoutID = nil
                    }
                } else {
                    // 找不到 CutoutItem，说明可能被删了，或者数据不一致
                    c.replacedCutoutID = nil
                }
            }
            
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
            
            // Trigger Reward for adding new clothing
            RewardManager.shared.triggerReward(type: .addClothing)
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
