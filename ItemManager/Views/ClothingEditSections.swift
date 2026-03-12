//
//  ClothingEditSections.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
//

import SwiftUI
import SwiftData

// MARK: - Basic Info Section

struct ClothingBasicInfoView: View {
    @Binding var imagePaths: [String]
    @Binding var name: String
    @Binding var brandName: String
    @Binding var isShared: Bool
    
    // Dynamic Fields
    @Binding var types: String
    @Binding var colors: String
    @Binding var sizes: String
    @Binding var length: String
    @Binding var condition: String
    @Binding var accessories: String
    
    // UI State
    @Binding var showingBrandSelection: Bool
    @Binding var showingGenericSelection: Bool
    @Binding var activeSelectionField: ClothingField?
    
    @Environment(\.modelContext) private var modelContext
    @Query private var brands: [Brand]
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @ObservedObject private var networkManager = NetworkSettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("裙子信息")
                .font(.headline)
            
            ImagePickerGrid(imagePaths: $imagePaths)
                .onChange(of: imagePaths) { oldValue, newValue in
                    print("ClothingBasicInfoView: imagePaths changed from \(oldValue.count) to \(newValue.count) images")
                }
            
            AutoCompleteTextField(title: "裙子名称", placeholder: "请输入裙子名称", text: $name, field: .name, isRequired: true)
            
            // Brand Field with Selection Button
            VStack(alignment: .leading, spacing: 8) {
                Text("品牌名称")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                HStack(spacing: 8) {
                    Button(action: {
                        showingBrandSelection = true
                    }) {
                        if let brand = brands.first(where: { $0.name == brandName }),
                           let path = brand.imagePath,
                           let image = ImageManager.shared.loadImage(fileName: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .cornerRadius(12)
                        } else {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .cornerRadius(12)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    AutoCompleteTextField(title: "", placeholder: "请输入品牌名称", text: $brandName, field: .brand)
                }
            }
            
            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                if visibilityManager.isVisible(field) {
                    buildFieldView(for: field)
                }
            }
            
            // 联网选项：只有在联网功能解锁并开启时才显示
            if networkManager.canShowNetworkUI() {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("加入联网社区", isOn: $isShared)
                        .tint(.pink)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("开启后，其他用户可以在社区中看到这条裙子")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    @ViewBuilder
    private func buildFieldView(for field: ClothingField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
}

// MARK: - Tag Section

struct ClothingTagsView: View {
    @Binding var selectedTags: [Tag]
    @Binding var showingAddTagSheet: Bool
    
    var body: some View {
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
    }
}

// MARK: - Price Section

struct ClothingPriceView: View {
    @Binding var originalPrice: Double
    @Binding var priceTotal: Double
    @Binding var deposit: Double
    @Binding var balance: Double
    @Binding var accessoriesPrice: Double
    @Binding var stock: Int
    @Binding var accessoryList: [AccessoryItemData]
    
    // 回调闭包用于显示 Toast
    var onShowToast: ((String, ToastType) -> Void)?
    
    // 提示类型
    enum ToastType {
        case success, error, warning
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "info.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("价格信息")
                .font(.headline)
            
            // 原价和总价
            VStack(spacing: 12) {
                PriceRow(title: "原价", value: $originalPrice)
                Divider()
                PriceRow(title: "裙子总价合计", value: $priceTotal)
            }
            
            // 定金和尾款
            VStack(spacing: 12) {
                PriceRow(title: "定金", value: $deposit)
                Divider()
                PriceRow(title: "尾款", value: $balance)
            }
            
            // 自动计算按钮
            Button(action: autoCalculateWithFeedback) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("自动计算")
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canAutoCalculate ? Color.pink : Color.gray)
                )
            }
            .disabled(!canAutoCalculate)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            
            // 汇总信息 (New Feature: Total Deposit & Balance)
            let totalDeposit = deposit + accessoryList.reduce(0) { $0 + $1.deposit }
            let totalBalance = balance + accessoryList.reduce(0) { $0 + $1.balance }
            let grandTotal = priceTotal + accessoriesPrice
            
            VStack(spacing: 12) {
                Divider()
                HStack {
                    Text("合计定金")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("¥ \(totalDeposit, specifier: "%.2f")")
                        .font(.subheadline.bold())
                }
                HStack {
                    Text("合计尾款")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("¥ \(totalBalance, specifier: "%.2f")")
                        .font(.subheadline.bold())
                }
                HStack {
                    Text("订单总价 (含小物)")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("¥ \(grandTotal, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundStyle(.pink)
                }
            }
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.5))
            .cornerRadius(8)
            
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
                        VStack(spacing: 8) {
                            HStack {
                                TextField("小物名称", text: $item.name)
                                    .textFieldStyle(.roundedBorder)
                                
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
                            
                            HStack {
                                // 定金
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("定金")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    TextField("0", value: Binding<Double?>(
                                        get: { item.deposit == 0 ? nil : item.deposit },
                                        set: {
                                            item.deposit = $0 ?? 0
                                            if item.deposit > 0 && item.balance > 0 {
                                                item.price = item.deposit + item.balance
                                            }
                                        }
                                    ), format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.trailing)
                                }
                                
                                Text("+")
                                    .foregroundStyle(.secondary)
                                
                                // 尾款
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("尾款")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    TextField("0", value: Binding<Double?>(
                                        get: { item.balance == 0 ? nil : item.balance },
                                        set: {
                                            item.balance = $0 ?? 0
                                            if item.deposit > 0 && item.balance > 0 {
                                                item.price = item.deposit + item.balance
                                            }
                                        }
                                    ), format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.trailing)
                                }
                                
                                Text("=")
                                    .foregroundStyle(.secondary)
                                
                                // 总价
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("单价")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    TextField("0", value: Binding<Double?>(
                                        get: { item.price == 0 ? nil : item.price },
                                        set: { item.price = $0 ?? 0 }
                                    ), format: .number)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: item.price) { _, _ in
                                            calculateAccessoriesTotal()
                                        }
                                        .onChange(of: item.deposit) { _, _ in
                                            calculateAccessoriesTotal()
                                        }
                                        .onChange(of: item.balance) { _, _ in
                                            calculateAccessoriesTotal()
                                        }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(8)
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
    }
    
    // MARK: - Helpers for Accessories
    
    private func addAccessory() {
        let newItem = AccessoryItemData(name: "", price: 0.0, deposit: 0.0, balance: 0.0)
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
    
    // MARK: - 价格自动计算逻辑
    
    /// 判断是否满足自动计算条件（三个价格中至少输入了两个）
    private var canAutoCalculate: Bool {
        let hasTotal = priceTotal > 0
        let hasDeposit = deposit > 0
        let hasBalance = balance > 0
        
        // 至少有两个值已输入，且第三个值为0或可以计算
        let filledCount = (hasTotal ? 1 : 0) + (hasDeposit ? 1 : 0) + (hasBalance ? 1 : 0)
        return filledCount >= 2
    }
    
    /// 自动计算价格（手动触发，带反馈）
    private func autoCalculateWithFeedback() {
        let result = performAutoCalculate()
        showToastMessage(result.message, type: result.success ? .success : .error)
    }
    
    /// 执行自动计算，返回结果和提示信息
    private func performAutoCalculate() -> (success: Bool, message: String) {
        // 情况1: 定金 + 尾款 → 计算总价
        if deposit > 0 && balance > 0 && priceTotal == 0 {
            priceTotal = deposit + balance
            return (true, "已自动计算总价：¥\(String(format: "%.2f", priceTotal))")
        }
        // 情况2: 总价 + 定金 → 计算尾款
        else if priceTotal > 0 && deposit > 0 && balance == 0 {
            let newBalance = priceTotal - deposit
            if newBalance >= 0 {
                balance = newBalance
                return (true, "已自动计算尾款：¥\(String(format: "%.2f", balance))")
            } else {
                return (false, "计算失败：定金不能大于总价")
            }
        }
        // 情况3: 总价 + 尾款 → 计算定金
        else if priceTotal > 0 && balance > 0 && deposit == 0 {
            let newDeposit = priceTotal - balance
            if newDeposit >= 0 {
                deposit = newDeposit
                return (true, "已自动计算定金：¥\(String(format: "%.2f", deposit))")
            } else {
                return (false, "计算失败：尾款不能大于总价")
            }
        }
        // 情况4: 三个值都已输入，校验并校正（以定金+尾款为准重新计算总价）
        else if priceTotal > 0 && deposit > 0 && balance > 0 {
            let calculatedTotal = deposit + balance
            if calculatedTotal != priceTotal {
                priceTotal = calculatedTotal
                return (true, "总价已校正为：¥\(String(format: "%.2f", priceTotal))")
            } else {
                return (true, "价格计算正确，无需调整")
            }
        }
        return (false, "无法计算，请至少输入两个价格值")
    }
    
    /// 显示提示信息
    private func showToastMessage(_ message: String, type: ToastType) {
        onShowToast?(message, type)
    }
}

// MARK: - Purchase Info Section

// 时间段选项（用于预计尾款时间计算）
enum PaymentDurationOption: Int, CaseIterable {
    case fiveteenDays = 15
    case thirtyDays = 30
    case sixtyDays = 60
    case custom = -1  // 自定义选项，用户手动选择日期
    
    var label: String {
        switch self {
        case .fiveteenDays: return "15天"
        case .thirtyDays: return "30天"
        case .sixtyDays: return "60天"
        case .custom: return "自定义"
        }
    }
}

struct ClothingPurchaseInfoView: View {
    @Binding var purchaseDate: Date
    @Binding var depositDate: Date
    @Binding var isDepositPlan: Bool
    @Binding var finalPaymentDate: Date
    @Binding var finalPaymentEndDate: Date
    @Binding var note: String
    
    // 时间段滑块状态（0=10天, 1=30天, 2=60天, 3=自定义）
    @State private var durationSliderValue: Double = 1.0
    
    // 根据滑块值获取当前选中的时间段
    private var selectedDuration: PaymentDurationOption {
        let index = Int(round(durationSliderValue))
        let allCases = PaymentDurationOption.allCases
        guard index >= 0 && index < allCases.count else {
            return .thirtyDays
        }
        return allCases[index]
    }
    
    // 判断是否为自定义模式
    private var isCustomMode: Bool {
        selectedDuration == .custom
    }
    
    var body: some View {
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
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("定金日期", selection: $depositDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                        
                        Divider()
                        
                        // 预计尾款时间区域
                        VStack(alignment: .leading, spacing: 8) {
                            Text("预计尾款时间")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            // 开始时间选择
                            DatePicker("开始", selection: $finalPaymentDate, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                                .onChange(of: finalPaymentDate) { _, newValue in
                                    // 开始时间变化时，如果不是自定义模式，根据时间段重新计算结束时间
                                    if !isCustomMode {
                                        updateFinalPaymentEndDate()
                                    } else {
                                        // 自定义模式下，如果结束时间早于新的开始时间，强制设置结束时间为开始时间
                                        if finalPaymentEndDate < newValue {
                                            finalPaymentEndDate = newValue
                                        }
                                    }
                                }
                            
                            // 时间段滑块
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("时间段")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(selectedDuration.label)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(isCustomMode ? .orange : .pink)
                                }
                                
                                // 自定义滑块样式（包含自定义选项）
                                HStack(spacing: 8) {
                                    ForEach(0..<PaymentDurationOption.allCases.count, id: \.self) { index in
                                        Button {
                                            withAnimation(.spring(response: 0.3)) {
                                                durationSliderValue = Double(index)
                                                // 切换到非自定义模式时，自动计算结束时间
                                                if PaymentDurationOption.allCases[index] != .custom {
                                                    updateFinalPaymentEndDate()
                                                }
                                            }
                                        } label: {
                                            Text(PaymentDurationOption.allCases[index].label)
                                                .font(.caption)
                                                .fontWeight(durationSliderValue == Double(index) ? .bold : .regular)
                                                .foregroundStyle(durationSliderValue == Double(index) ? .white : .primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .fill(buttonBackgroundColor(for: index))
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            
                            // 结束时间显示
                            if isCustomMode {
                                // 自定义模式：显示日期选择器
                                DatePicker("结束", selection: $finalPaymentEndDate, in: finalPaymentDate..., displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "zh_CN"))
                                    .onChange(of: finalPaymentEndDate) { _, newValue in
                                        // 如果结束时间早于开始时间，强制设置为开始时间
                                        if newValue < finalPaymentDate {
                                            finalPaymentEndDate = finalPaymentDate
                                        }
                                    }
                            } else {
                                // 预设模式：只读显示自动计算的结束时间
                                HStack {
                                    Text("结束")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(finalPaymentEndDate, style: .date)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                            
                            Text("设置预计尾款时间范围，方便在尾款天使中统计和提醒")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        .onAppear {
            // 初始化时根据当前finalPaymentEndDate反推滑块值
            initializeDurationSlider()
        }
    }
    
    // 根据索引返回按钮背景色
    private func buttonBackgroundColor(for index: Int) -> Color {
        let isSelected = durationSliderValue == Double(index)
        let option = PaymentDurationOption.allCases[index]
        
        if isSelected {
            return option == .custom ? Color.orange : Color.pink
        } else {
            return Color(uiColor: .tertiarySystemFill)
        }
    }
    
    // 根据开始时间和时间段计算结束时间
    private func updateFinalPaymentEndDate() {
        // 自定义模式下不自动计算
        guard selectedDuration != .custom else { return }
        
        let calendar = Calendar.current
        if let newEndDate = calendar.date(byAdding: .day, value: selectedDuration.rawValue, to: finalPaymentDate) {
            finalPaymentEndDate = newEndDate
        }
    }
    
    // 初始化滑块值（根据当前结束时间和开始时间的差值）
    private func initializeDurationSlider() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: finalPaymentDate, to: finalPaymentEndDate)
        
        if let days = components.day {
            // 检查是否匹配预设的时间段
            if let exactMatch = PaymentDurationOption.allCases.first(where: { $0.rawValue == days && $0 != .custom }) {
                // 精确匹配某个预设值
                if let index = PaymentDurationOption.allCases.firstIndex(of: exactMatch) {
                    durationSliderValue = Double(index)
                    return
                }
            }
            
            // 不匹配任何预设值，使用自定义模式
            if let customIndex = PaymentDurationOption.allCases.firstIndex(of: .custom) {
                durationSliderValue = Double(customIndex)
            }
        }
    }
}
