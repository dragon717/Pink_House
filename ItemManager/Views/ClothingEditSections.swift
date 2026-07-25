//
//  ClothingEditSections.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
//

import SwiftUI
import SwiftData

// MARK: - Comma string helpers (edit UI ↔ Clothing storage)

enum CommaSeparatedTokens {
    static func parse(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func join(_ tokens: [String]) -> String {
        tokens.joined(separator: ",")
    }

    static func remove(_ token: String, from text: String) -> String {
        join(parse(text).filter { $0 != token })
    }

    /// Sheet 多选写回：保留原有顺序，新选项追加在末尾（按名排序仅用于新增段）
    static func joinPreservingOrder(previous: [String], selected: Set<String>) -> String {
        let kept = previous.filter { selected.contains($0) }
        let previousSet = Set(previous)
        let added = selected.filter { !previousSet.contains($0) }.sorted()
        return join(kept + added)
    }

    static func toggle(_ token: String, in text: String, allowsMultiple: Bool) -> String {
        let tokens = parse(text)
        if allowsMultiple {
            if tokens.contains(token) {
                return remove(token, from: text)
            }
            return join(tokens + [token])
        }
        return tokens.first == token ? "" : token
    }

    /// 行内展示：常用项顺序固定（点选只改颜色不挪位）；不在常用里的已选值追加在末尾
    static func inlineTags(selected: [String], preferred: [String], maxCount: Int = 10) -> [String] {
        var result = Array(preferred.prefix(maxCount))
        for token in selected where !result.contains(token) {
            result.append(token)
        }
        return result
    }
}

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
    
    // 表图字段
    @Binding var sizeChartImagePath: String?
    var deleteChartFileImmediately: Bool = true
    
    // UI State
    @Binding var showingBrandSelection: Bool
    @Binding var activeSelectionField: ClothingField?
    
    @Query private var brands: [Brand]
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @ObservedObject private var networkManager = NetworkSettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("裙装信息".appLocalized)
                .font(.headline)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            
            ImagePickerGrid(imagePaths: $imagePaths)
                .onChange(of: imagePaths) { oldValue, newValue in
                    print("ClothingBasicInfoView: imagePaths changed from \(oldValue.count) to \(newValue.count) images")
                }
            
            AutoCompleteTextField(title: "裙装名称", placeholder: "请输入裙装名称", text: $name, field: .name, isRequired: true)
            
            // Brand Field with Selection Button
            VStack(alignment: .leading, spacing: 8) {
                Text("品牌名称".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                    inlineFieldRow(for: field)
                }
            }
            
            // 联网选项：只有在联网功能解锁并开启时才显示
            if networkManager.canShowNetworkUI() {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("加入联网社区".appLocalized, isOn: $isShared)
                        .tint(.pink)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text("开启后，其他用户可以在社区中看到这条裙装".appLocalized)
                            .font(.caption)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
    
    @ViewBuilder
    private func inlineFieldRow(for field: ClothingField) -> some View {
        // ponytail: Equatable 行跳过未改字段的 body；点选不动画、不重排
        InlineToggleTagsRow(
            field: field,
            text: binding(for: field).wrappedValue,
            textBinding: binding(for: field),
            preferred: Self.preferredTags(for: field),
            allowsMultiple: fieldAllowsMultiple(field),
            sizeChartImagePath: field == .sizes ? $sizeChartImagePath : nil,
            deleteChartFileImmediately: deleteChartFileImmediately,
            onMore: { openSelection(for: field) }
        )
        .equatable()
    }

    private func openSelection(for field: ClothingField) {
        // sheet(item:) 只靠非 nil 打开，避免 isPresented 抢跑导致白 sheet
        activeSelectionField = field
    }

    private func fieldAllowsMultiple(_ field: ClothingField) -> Bool {
        switch field {
        case .types, .colors, .sizes, .accessories:
            return true
        case .length, .condition:
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

    private static func preferredTags(for field: ClothingField) -> [String] {
        // 静态缓存，避免每次 body 重建数组
        preferredTagsCache[field] ?? {
            let tags = SuggestionManager.shared.orderedDefaults(for: field)
            preferredTagsCache[field] = tags
            return tags
        }()
    }

    private static var preferredTagsCache: [ClothingField: [String]] = [:]
}

/// 单行字段 tag；Equatable 用 text 快照跳过无关刷新
private struct InlineToggleTagsRow: View, Equatable {
    let field: ClothingField
    let text: String
    @Binding var textBinding: String
    let preferred: [String]
    let allowsMultiple: Bool
    var sizeChartImagePath: Binding<String?>?
    var deleteChartFileImmediately: Bool = true
    let onMore: () -> Void

    static func == (lhs: InlineToggleTagsRow, rhs: InlineToggleTagsRow) -> Bool {
        lhs.field == rhs.field
            && lhs.text == rhs.text
            && lhs.allowsMultiple == rhs.allowsMultiple
            && lhs.preferred == rhs.preferred
            && lhs.sizeChartImagePath?.wrappedValue == rhs.sizeChartImagePath?.wrappedValue
    }

    var body: some View {
        let selected = CommaSeparatedTokens.parse(text)
        let selectedSet = Set(selected)
        let tags = CommaSeparatedTokens.inlineTags(selected: selected, preferred: preferred, maxCount: 10)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(field.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let sizeChartImagePath {
                    ChartImagePicker(
                        imagePath: sizeChartImagePath,
                        placeholder: "添加表图",
                        editMode: true,
                        deleteFileImmediately: deleteChartFileImmediately
                    )
                }
            }
            .padding(.leading, 4)

            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { token in
                    let isOn = selectedSet.contains(token)
                    Button {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            textBinding = CommaSeparatedTokens.toggle(
                                token,
                                in: textBinding,
                                allowsMultiple: allowsMultiple
                            )
                        }
                    } label: {
                        Text(token)
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Color.white : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isOn ? Color.pink : Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onMore) {
                    HStack(spacing: 2) {
                        Text("更多".appLocalized)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
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
                Text("标签分类".appLocalized)
                    .font(.headline)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Spacer()
                Button(action: { showingAddTagSheet = true }) {
                    Label("管理标签".appLocalized, systemImage: "tag")
                        .font(.subheadline)
                        .themeSkinLegibleText(level: .chip, slot: .primaryButton)
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
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: tag.colorHex).opacity(0.2))
                            .cornerRadius(16)
                        }
                    }
                }
            } else {
                Text("暂无标签".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
            
            Text("可选择多个标签分类，帮助你更好地管理衣橱".appLocalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

// MARK: - Price Section

struct ClothingPriceView: View {
    @Binding var originalPrice: Double
    @Binding var originalPriceJPY: Double
    @Binding var originalPriceCurrency: ClothingPriceCurrency
    @Binding var originalPriceRateUpdatedAt: Date?
    @Binding var priceTotal: Double
    @Binding var deposit: Double
    @Binding var balance: Double
    @Binding var reservationKind: ClothingReservationKind
    @Binding var accessoriesPrice: Double
    @Binding var shippingFee: Double
    @Binding var shippingFeeJPY: Double
    @Binding var shippingFeeCurrency: ClothingPriceCurrency
    @Binding var stock: Int
    @Binding var accessoryList: [AccessoryItemData]
    var jpyExchangeRate: Double = CurrencyExchangeRateService.defaultJPYRate
    var onRefreshJPYRate: (() async -> CurrencyExchangeRateRefreshResult)?
    
    // 价格表图片
    @Binding var priceChartImagePath: String?
    var deleteChartFileImmediately: Bool = true
    
    // 回调闭包用于显示 Toast
    var onShowToast: ((String, ToastType) -> Void)?

    @State private var showingRefreshRateConfirmation = false
    @State private var isRefreshingJPYRate = false
    
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
            HStack {
                Text("价格信息".appLocalized)
                    .font(.headline)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Spacer()
                ChartImagePicker(
                    imagePath: $priceChartImagePath,
                    placeholder: "添加表图",
                    editMode: true,
                    deleteFileImmediately: deleteChartFileImmediately
                )
            }
            
            // 原价和总价
            VStack(spacing: 12) {
                CurrencyPriceRow(
                    title: "原价",
                    cnyValue: $originalPrice,
                    jpyValue: $originalPriceJPY,
                    currency: $originalPriceCurrency,
                    exchangeRateJPY: jpyExchangeRate
                )
                originalPriceExchangeRateSnapshot
                Divider()
                PriceRow(title: "裙装总价合计", value: $priceTotal)
                Divider()
                CurrencyPriceRow(
                    title: "邮费",
                    cnyValue: $shippingFee,
                    jpyValue: $shippingFeeJPY,
                    currency: $shippingFeeCurrency,
                    exchangeRateJPY: jpyExchangeRate
                )
            }
            
            if reservationKind == .depositPlan {
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
                        Text("自动计算".appLocalized)
                            .themeSkinLegibleText(level: .chip, slot: .primaryButton)
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
            }
            
            // 汇总信息 (New Feature: Total Deposit & Balance)
            let totalDeposit = deposit + accessoryList.reduce(0) { $0 + $1.deposit }
            let totalBalance = balance + accessoryList.reduce(0) { $0 + $1.balance }
            let grandTotal = priceTotal + accessoriesPrice
            let grandTotalWithShipping = grandTotal + shippingFee
            
            VStack(spacing: 12) {
                Divider()
                if reservationKind == .fullPaymentReservation {
                    HStack {
                        Text("全款预约金额（单件含邮）".appLocalized)
                            .foregroundStyle(.primary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        Spacer()
                        Text("¥ \(grandTotalWithShipping, specifier: "%.2f")")
                            .font(.headline)
                            .foregroundStyle(.pink)
                            .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                    }
                    if stock > 1 {
                        HStack {
                            Text("全款预约总额".appLocalized)
                                .foregroundStyle(.secondary)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            Spacer()
                            Text("¥ \(grandTotalWithShipping * Double(stock), specifier: "%.2f")")
                                .font(.subheadline.bold())
                                .foregroundStyle(.pink)
                                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                        }
                    }
                    Text("保存时会自动写入为「全款预约」，不再显示定金、尾款或尾款日期。".appLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if reservationKind == .depositPlan {
                    HStack {
                        Text("合计定金".appLocalized)
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        Spacer()
                        Text("¥ \(totalDeposit, specifier: "%.2f")")
                            .font(.subheadline.bold())
                            .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                    }
                    HStack {
                        Text("合计尾款".appLocalized)
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        Spacer()
                        Text("¥ \(totalBalance, specifier: "%.2f")")
                            .font(.subheadline.bold())
                            .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                    }
                }
                HStack {
                    Text("订单总价 (含小物)".appLocalized)
                        .foregroundStyle(.primary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Spacer()
                    Text("¥ \(grandTotal, specifier: "%.2f")")
                        .font(.subheadline.bold())
                        .foregroundStyle(.pink)
                        .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                }
                HStack {
                    Text("含邮订单总价".appLocalized)
                        .foregroundStyle(.primary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Spacer()
                    Text("¥ \(grandTotalWithShipping, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundStyle(.pink)
                        .themeSkinLegibleText(level: .chip, slot: .sectionCard)
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
                    Text("自定义小物明细".appLocalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Spacer()
                    Button(action: addAccessory) {
                        Label("添加".appLocalized, systemImage: "plus.circle")
                            .font(.subheadline)
                            .themeSkinLegibleText(level: .chip, slot: .primaryButton)
                    }
                }
                
                if !accessoryList.isEmpty {
                    ForEach($accessoryList) { $item in
                        VStack(spacing: 8) {
                            HStack {
                                TextField("小物名称".appLocalized, text: $item.name)
                                    .textFieldStyle(.roundedBorder)
                                
                                Menu {
                                    Button(role: .destructive) {
                                        if let index = accessoryList.firstIndex(where: { $0.id == item.id }) {
                                            deleteAccessory(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Label("删除".appLocalized, systemImage: "trash")
                                    }
                                    
                                    Button {
                                        moveAccessoryUp(item)
                                    } label: {
                                        Label("上移".appLocalized, systemImage: "arrow.up")
                                    }
                                    
                                    Button {
                                        moveAccessoryDown(item)
                                    } label: {
                                        Label("下移".appLocalized, systemImage: "arrow.down")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            HStack {
                                if reservationKind == .depositPlan {
                                    // 定金
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("定金".appLocalized)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                                    // 尾款
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("尾款".appLocalized)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                }

                                // 总价
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("单价".appLocalized)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                Text("库存数量".appLocalized)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Spacer()
                Stepper("", value: $stock, in: 1...999)
                    .labelsHidden()
                Text("\(stock)")
                    .font(.body.monospacedDigit())
                    .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
        .padding()
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
        .alert("刷新日元汇率？".appLocalized, isPresented: $showingRefreshRateConfirmation) {
            Button("取消".appLocalized, role: .cancel) {}
            Button("刷新汇率".appLocalized) {
                Task { await refreshJPYRateAfterConfirmation() }
            }
        } message: {
            Text("会联网查询当前 CNY→JPY 汇率，并用新汇率重新折算原价和邮费。保存后，这个汇率会作为这条裙装记录的当时汇率。".appLocalized)
        }
    }

    private var originalPriceExchangeRateSnapshot: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.checkmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text("原价日元汇率".appLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Text("1 CNY = \(jpyExchangeRate, specifier: "%.4f") JPY")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.primary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Text(originalPriceRateUpdatedAt.map { "记录时间：%@".appLocalized(formattedRateUpdateDate($0)) } ?? "尚未记录实时汇率".appLocalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }

            Spacer(minLength: 8)

            Button {
                showingRefreshRateConfirmation = true
            } label: {
                if isRefreshingJPYRate {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("刷新".appLocalized, systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshingJPYRate || onRefreshJPYRate == nil)
            .accessibilityLabel("刷新日元汇率".appLocalized)
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.55))
        .cornerRadius(8)
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
        let total = accessoryList.reduce(0.0) { $0 + $1.price }
        accessoriesPrice = total
    }
    
    // MARK: - 价格自动计算逻辑
    
    /// 判断是否满足自动计算条件：总价必须已填，且定金或尾款至少填了一个
    private var canAutoCalculate: Bool {
        let hasTotal = priceTotal > 0
        let hasDeposit = deposit > 0
        let hasBalance = balance > 0

        // 总价必须有值，才能计算定金或尾款
        return hasTotal && (hasDeposit || hasBalance)
    }
    
    /// 自动计算价格（手动触发，带反馈）
    private func autoCalculateWithFeedback() {
        let result = performAutoCalculate()
        showToastMessage(result.message, type: result.success ? .success : .error)
    }
    
    /// 执行自动计算，返回结果和提示信息
    private func performAutoCalculate() -> (success: Bool, message: String) {
        // 情况1: 总价 + 定金 → 计算尾款
        if priceTotal > 0 && deposit > 0 && balance == 0 {
            let newBalance = priceTotal - deposit
            if newBalance >= 0 {
                balance = newBalance
                return (true, "已自动计算尾款：%@".appLocalized(formattedCNYAmount(balance)))
            } else {
                return (false, "计算失败：定金不能大于总价".appLocalized)
            }
        }
        // 情况2: 总价 + 尾款 → 计算定金
        else if priceTotal > 0 && balance > 0 && deposit == 0 {
            let newDeposit = priceTotal - balance
            if newDeposit >= 0 {
                deposit = newDeposit
                return (true, "已自动计算定金：%@".appLocalized(formattedCNYAmount(deposit)))
            } else {
                return (false, "计算失败：尾款不能大于总价".appLocalized)
            }
        }
        // 情况3: 三个值都已输入，校验并校正（以定金+尾款为准重新计算总价）
        else if priceTotal > 0 && deposit > 0 && balance > 0 {
            let calculatedTotal = deposit + balance
            if calculatedTotal != priceTotal {
                priceTotal = calculatedTotal
                return (true, "总价已校正为：%@".appLocalized(formattedCNYAmount(priceTotal)))
            } else {
                return (true, "价格计算正确，无需调整".appLocalized)
            }
        }
        return (false, "无法计算，请至少输入两个价格值".appLocalized)
    }
    
    /// 显示提示信息
    private func showToastMessage(_ message: String, type: ToastType) {
        onShowToast?(message, type)
    }

    private func refreshJPYRateAfterConfirmation() async {
        guard let onRefreshJPYRate else { return }
        isRefreshingJPYRate = true
        let result = await onRefreshJPYRate()
        isRefreshingJPYRate = false
        if let errorMessage = result.errorMessage {
            showToastMessage("刷新失败：%@".appLocalized(errorMessage), type: .error)
        } else {
            showToastMessage("已刷新并记录当前日元汇率".appLocalized, type: .success)
        }
    }

    private func formattedCNYAmount(_ value: Double) -> String {
        String(format: "¥%.2f", value)
    }

    private func formattedRateUpdateDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        case .fiveteenDays, .thirtyDays, .sixtyDays:
            return "%d天".appLocalized(rawValue)
        case .custom:
            return "自定义".appLocalized
        }
    }
}

struct ClothingPurchaseInfoView: View {
    @Binding var purchaseDate: Date
    @Binding var depositDate: Date
    @Binding var reservationKind: ClothingReservationKind
    @Binding var finalPaymentDate: Date
    @Binding var finalPaymentEndDate: Date
    
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

    private var reservationHint: String {
        switch reservationKind {
        case .owned:
            return "已拥有：按普通入库裙装保存，不进入预约列表。".appLocalized
        case .fullPaymentReservation:
            return "全款预约：进入预约列表，只显示全款预约日期和全款金额。".appLocalized
        case .depositPlan:
            return "定金尾款：进入心愿尾款，可设置定金日期和预计尾款时间。".appLocalized
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("购买信息".appLocalized)
                .font(.headline)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            
            DatePicker("购买日期".appLocalized, selection: $purchaseDate, displayedComponents: .date)
                .environment(\.locale, LanguageManager.shared.locale)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Picker("预约状态".appLocalized, selection: $reservationKind) {
                    ForEach(ClothingReservationKind.allCases) { kind in
                        Text(kind.displayName.appLocalized)
                            .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Text(reservationHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                
                switch reservationKind {
                case .owned:
                    EmptyView()
                case .fullPaymentReservation:
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("全款预约日期".appLocalized, selection: $depositDate, displayedComponents: .date)
                            .environment(\.locale, LanguageManager.shared.locale)
                        Text("全款预约会复用现有预约数据结构：保存时自动将全款金额写入定金字段，尾款为 0。".appLocalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                case .depositPlan:
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("定金日期".appLocalized, selection: $depositDate, displayedComponents: .date)
                            .environment(\.locale, LanguageManager.shared.locale)
                        
                        Divider()
                        
                        // 预计尾款时间区域
                        VStack(alignment: .leading, spacing: 8) {
                            Text("预计尾款时间".appLocalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            
                            // 开始时间选择
                            DatePicker("开始".appLocalized, selection: $finalPaymentDate, displayedComponents: .date)
                                .environment(\.locale, LanguageManager.shared.locale)
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
                                    Text("时间段".appLocalized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                    Spacer()
                                    Text(selectedDuration.label)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(isCustomMode ? .orange : .pink)
                                        .themeSkinLegibleText(level: .chip, slot: .sectionCard)
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
                                                .themeSkinLegibleText(level: .chip, slot: .filterChip)
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
                                DatePicker("结束".appLocalized, selection: $finalPaymentEndDate, in: finalPaymentDate..., displayedComponents: .date)
                                    .environment(\.locale, LanguageManager.shared.locale)
                                    .onChange(of: finalPaymentEndDate) { _, newValue in
                                        // 如果结束时间早于开始时间，强制设置为开始时间
                                        if newValue < finalPaymentDate {
                                            finalPaymentEndDate = finalPaymentDate
                                        }
                                    }
                            } else {
                                // 预设模式：只读显示自动计算的结束时间
                                HStack {
                                    Text("结束".appLocalized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                    Spacer()
                                    Text(finalPaymentEndDate, style: .date)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                            
                            Text("设置预计尾款时间范围，方便在心愿尾款中统计和提醒".appLocalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        }
                    }
                }
            }
        }
        .padding()
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
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

struct ClothingNoteView: View {
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备注".appLocalized)
                .font(.headline)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            TextEditor(text: $note)
                .frame(height: 100)
                .padding(4)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(8)
        }
        .padding()
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 16) {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}
