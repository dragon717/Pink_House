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
            
            Toggle("同步到裙子社区", isOn: $isShared)
                .padding(.top, 8)
            Text("分享你的裙子给其他用户参考")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    
    var body: some View {
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
}

// MARK: - Purchase Info Section

// 时间段选项（用于预计尾款时间计算）
enum PaymentDurationOption: Int, CaseIterable {
    case tenDays = 10
    case thirtyDays = 30
    case sixtyDays = 60
    
    var label: String {
        switch self {
        case .tenDays: return "10天"
        case .thirtyDays: return "30天"
        case .sixtyDays: return "60天"
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
    
    // 时间段滑块状态（0=10天, 1=30天, 2=60天）
    @State private var durationSliderValue: Double = 1.0
    
    // 根据滑块值获取当前选中的时间段
    private var selectedDuration: PaymentDurationOption {
        let index = Int(round(durationSliderValue))
        return PaymentDurationOption.allCases[min(max(index, 0), 2)]
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
                                .onChange(of: finalPaymentDate) { _, _ in
                                    // 开始时间变化时，根据时间段重新计算结束时间
                                    updateFinalPaymentEndDate()
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
                                        .foregroundStyle(.pink)
                                }
                                
                                // 自定义滑块样式
                                HStack(spacing: 8) {
                                    ForEach(0..<PaymentDurationOption.allCases.count, id: \.self) { index in
                                        Button {
                                            withAnimation(.spring(response: 0.3)) {
                                                durationSliderValue = Double(index)
                                                updateFinalPaymentEndDate()
                                            }
                                        } label: {
                                            Text(PaymentDurationOption.allCases[index].label)
                                                .font(.caption)
                                                .fontWeight(durationSliderValue == Double(index) ? .bold : .regular)
                                                .foregroundStyle(durationSliderValue == Double(index) ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .fill(durationSliderValue == Double(index) ? Color.pink : Color(uiColor: .tertiarySystemFill))
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            
                            // 结束时间（自动计算，只读显示）
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
    
    // 根据开始时间和时间段计算结束时间
    private func updateFinalPaymentEndDate() {
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
            // 找到最接近的时间段
            let closestOption = PaymentDurationOption.allCases.min { option1, option2 in
                abs(option1.rawValue - days) < abs(option2.rawValue - days)
            }
            if let closest = closestOption,
               let index = PaymentDurationOption.allCases.firstIndex(of: closest) {
                durationSliderValue = Double(index)
            }
        }
    }
}
