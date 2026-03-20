import SwiftUI
import SwiftData

// MARK: - 筛选模式枚举
enum FilterMode: String, CaseIterable, Identifiable {
    case classic = "classic"
    case multiDimensional = "multiDimensional"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "经典筛选"
        case .multiDimensional: return "多维筛选"
        }
    }
}

// MARK: - 心愿尾款筛选状态
enum DepositStatusFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case owned = "owned"
    case depositPlan = "depositPlan"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .owned: return "已拥有/全款"
        case .depositPlan: return "心愿尾款"
        }
    }
}

// MARK: - 多维筛选Sheet
struct MultiDimensionalFilterSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // 数据
    let clothings: [Clothing]
    let tags: [Tag]
    let brands: [Brand]

    // 筛选状态绑定
    @Binding var selectedTagIDs: Set<UUID>
    @Binding var selectedBrandIDs: Set<UUID>
    @Binding var selectedTypes: Set<String>
    @Binding var selectedColors: Set<String>
    @Binding var selectedSizes: Set<String>
    @Binding var selectedLengths: Set<String>
    @Binding var selectedConditions: Set<String>
    @Binding var selectedAccessories: Set<String>

    // 心愿尾款筛选状态
    @Binding var depositStatusFilter: DepositStatusFilter

    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared

    // 特殊筛选值
    static let noTagUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let noBrandUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let noTypeMarker = "__NO_TYPE__"
    static let noColorMarker = "__NO_COLOR__"
    static let noSizeMarker = "__NO_SIZE__"
    static let noLengthMarker = "__NO_LENGTH__"
    static let noConditionMarker = "__NO_CONDITION__"
    static let noAccessoryMarker = "__NO_ACCESSORY__"

    // 当前展开的区块
    @State private var expandedSection: FilterSection? = nil

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    // 计算所有筛选条件的数量
    private var totalFilterCount: Int {
        selectedTagIDs.count +
        selectedBrandIDs.count +
        selectedTypes.count +
        selectedColors.count +
        selectedSizes.count +
        selectedLengths.count +
        selectedConditions.count +
        selectedAccessories.count +
        (depositStatusFilter != .all ? 1 : 0)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 已选条件摘要
                    if totalFilterCount > 0 {
                        selectedFiltersSummary
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    
                    // 筛选列表
                    ScrollView {
                        VStack(spacing: 12) {
                            // 标签筛选行
                            filterRow(
                                section: .tags,
                                title: "标签",
                                icon: "tag",
                                selectedCount: selectedTagIDs.count,
                                options: tagOptions
                            )
                            
                            // 品牌筛选行
                            filterRow(
                                section: .brands,
                                title: "品牌",
                                icon: "bag",
                                selectedCount: selectedBrandIDs.count,
                                options: brandOptions
                            )
                            
                            // 动态字段筛选行
                            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                                if visibilityManager.isVisible(field) {
                                    dynamicFilterRow(for: field)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("多维筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(magicPalette.secondaryText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // 心愿尾款筛选
                        Menu {
                            ForEach(DepositStatusFilter.allCases) { filter in
                                Button {
                                    depositStatusFilter = filter
                                } label: {
                                    HStack {
                                        Text(filter.displayName)
                                        if depositStatusFilter == filter {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: depositStatusFilter == .all ? "heart" : "heart.fill")
                                if depositStatusFilter != .all {
                                    Text("\(depositStatusFilter == .owned ? "已拥有" : "心愿")")
                                        .font(.caption)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(depositStatusFilter == .all ? magicPalette.secondaryText : magicPalette.accent)
                        }

                        if totalFilterCount > 0 {
                            Button {
                                clearAllFilters()
                            } label: {
                                Text("清除")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .tint(magicPalette.accent)
        }
        .presentationDetents([.fraction(0.7)])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - 已选条件摘要
    private var selectedFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选条件 (\(totalFilterCount))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(magicPalette.primaryText)
                
                Spacer()
            }
            
            // 横向滚动的已选标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedFilterItems, id: \.id) { item in
                        selectedFilterChip(item: item)
                    }
                }
            }
        }
        .padding(12)
        .background(magicPalette.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(magicPalette.secondaryText.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    // 已选条件数据结构
    private struct SelectedFilterItem: Identifiable {
        let id = UUID()
        let section: FilterSection
        let value: String
        let rawValue: String // 用于删除时识别
    }
    
    // 获取所有已选条件
    private var selectedFilterItems: [SelectedFilterItem] {
        var items: [SelectedFilterItem] = []
        
        // 标签
        for id in selectedTagIDs {
            let name = id == MultiDimensionalFilterSheet.noTagUUID ? "无标签" : tags.first(where: { $0.id == id })?.name ?? ""
            items.append(SelectedFilterItem(section: .tags, value: name, rawValue: id.uuidString))
        }
        
        // 品牌
        for id in selectedBrandIDs {
            let name = id == MultiDimensionalFilterSheet.noBrandUUID ? "无品牌" : brands.first(where: { $0.id == id })?.name ?? ""
            items.append(SelectedFilterItem(section: .brands, value: name, rawValue: id.uuidString))
        }
        
        // 类型
        for type in selectedTypes {
            let name = type == MultiDimensionalFilterSheet.noTypeMarker ? "无类型" : type
            items.append(SelectedFilterItem(section: .types, value: name, rawValue: type))
        }
        
        // 颜色
        for color in selectedColors {
            let name = color == MultiDimensionalFilterSheet.noColorMarker ? "无颜色" : color
            items.append(SelectedFilterItem(section: .colors, value: name, rawValue: color))
        }
        
        // 尺码
        for size in selectedSizes {
            let name = size == MultiDimensionalFilterSheet.noSizeMarker ? "无尺码" : size
            items.append(SelectedFilterItem(section: .sizes, value: name, rawValue: size))
        }
        
        // 衣长
        for length in selectedLengths {
            let name = length == MultiDimensionalFilterSheet.noLengthMarker ? "无衣长" : length
            items.append(SelectedFilterItem(section: .length, value: name, rawValue: length))
        }
        
        // 状态
        for condition in selectedConditions {
            let name = condition == MultiDimensionalFilterSheet.noConditionMarker ? "无状态" : condition
            items.append(SelectedFilterItem(section: .condition, value: name, rawValue: condition))
        }
        
        // 小物
        for accessory in selectedAccessories {
            let name = accessory == MultiDimensionalFilterSheet.noAccessoryMarker ? "无小物" : accessory
            items.append(SelectedFilterItem(section: .accessories, value: name, rawValue: accessory))
        }
        
        return items
    }
    
    // 已选条件标签
    private func selectedFilterChip(item: SelectedFilterItem) -> some View {
        HStack(spacing: 4) {
            Text(item.value)
                .font(.caption)
                .fontWeight(.medium)
            
            Button {
                removeFilterItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
        }
        .foregroundStyle(magicPalette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(magicPalette.accent.opacity(0.15))
        .cornerRadius(16)
    }
    
    // 移除单个筛选条件
    private func removeFilterItem(_ item: SelectedFilterItem) {
        switch item.section {
        case .tags:
            if let uuid = UUID(uuidString: item.rawValue) {
                selectedTagIDs.remove(uuid)
            }
        case .brands:
            if let uuid = UUID(uuidString: item.rawValue) {
                selectedBrandIDs.remove(uuid)
            }
        case .types:
            selectedTypes.remove(item.rawValue)
        case .colors:
            selectedColors.remove(item.rawValue)
        case .sizes:
            selectedSizes.remove(item.rawValue)
        case .length:
            selectedLengths.remove(item.rawValue)
        case .condition:
            selectedConditions.remove(item.rawValue)
        case .accessories:
            selectedAccessories.remove(item.rawValue)
        }
    }
    
    // MARK: - 筛选行
    private func filterRow(
        section: FilterSection,
        title: String,
        icon: String,
        selectedCount: Int,
        options: [FilterOption]
    ) -> some View {
        VStack(spacing: 0) {
            // 标题行（可点击展开）
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedSection == section {
                        expandedSection = nil
                    } else {
                        expandedSection = section
                    }
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedCount > 0 ? magicPalette.accent : magicPalette.secondaryText)
                        .frame(width: 28)
                    
                    Text(title)
                        .font(.body)
                        .foregroundStyle(magicPalette.primaryText)
                    
                    Spacer()
                    
                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(magicPalette.accent)
                            .cornerRadius(10)
                    }
                    
                    Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(magicPalette.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(magicPalette.cardBackground)
            }
            .buttonStyle(.plain)
            
            // 展开的选项区域
            if expandedSection == section {
                filterOptionsGrid(options: options, section: section)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .background(magicPalette.cardBackground)
            }
        }
        .background(magicPalette.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectedCount > 0 ? magicPalette.accent.opacity(0.5) : magicPalette.secondaryText.opacity(0.3), lineWidth: selectedCount > 0 ? 1.5 : 0.5)
        )
    }
    
    // MARK: - 动态字段筛选行
    private func dynamicFilterRow(for field: ClothingField) -> some View {
        let (title, icon, selectedCount, options) = fieldConfig(for: field)
        return filterRow(
            section: filterSection(for: field),
            title: title,
            icon: icon,
            selectedCount: selectedCount,
            options: options
        )
    }
    
    // 字段配置
    private func fieldConfig(for field: ClothingField) -> (title: String, icon: String, count: Int, options: [FilterOption]) {
        switch field {
        case .types:
            return ("类型", "tshirt", selectedTypes.count, typeOptions)
        case .colors:
            return ("颜色", "paintpalette", selectedColors.count, colorOptions)
        case .sizes:
            return ("尺码", "ruler", selectedSizes.count, sizeOptions)
        case .length:
            return ("衣长", "arrow.up.and.down", selectedLengths.count, lengthOptions)
        case .condition:
            return ("状态", "star", selectedConditions.count, conditionOptions)
        case .accessories:
            return ("小物", "sparkles", selectedAccessories.count, accessoryOptions)
        }
    }
    
    // 字段转区块
    private func filterSection(for field: ClothingField) -> FilterSection {
        switch field {
        case .types: return .types
        case .colors: return .colors
        case .sizes: return .sizes
        case .length: return .length
        case .condition: return .condition
        case .accessories: return .accessories
        }
    }
    
    // MARK: - 选项网格
    private func filterOptionsGrid(options: [FilterOption], section: FilterSection) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(options) { option in
                filterOptionButton(option: option, section: section)
            }
        }
    }
    
    // 单个选项按钮
    private func filterOptionButton(option: FilterOption, section: FilterSection) -> some View {
        let isSelected = isOptionSelected(option: option, section: section)
        
        return Button {
            toggleOption(option: option, section: section)
        } label: {
            Text(option.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? magicPalette.accent : magicPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? magicPalette.accent.opacity(0.15) : magicPalette.cardBackground.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? magicPalette.accent : magicPalette.secondaryText.opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 选项数据
    private struct FilterOption: Identifiable {
        let id = UUID()
        let value: String
        let displayName: String
        let isSpecial: Bool // 标记是否是"无XXX"选项
    }
    
    // 标签选项
    private var tagOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noTagUUID.uuidString, displayName: "无标签", isSpecial: true))
        options.append(contentsOf: tags.map { FilterOption(value: $0.id.uuidString, displayName: $0.name, isSpecial: false) })
        return options
    }
    
    // 品牌选项
    private var brandOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noBrandUUID.uuidString, displayName: "无品牌", isSpecial: true))
        options.append(contentsOf: brands.map { FilterOption(value: $0.id.uuidString, displayName: $0.name, isSpecial: false) })
        return options
    }
    
    // 类型选项
    private var typeOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noTypeMarker, displayName: "无类型", isSpecial: true))
        let values = getAllValues(for: \.types)
        options.append(contentsOf: values.map { FilterOption(value: $0, displayName: $0, isSpecial: false) })
        return options
    }
    
    // 颜色选项
    private var colorOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noColorMarker, displayName: "无颜色", isSpecial: true))
        let values = getAllValues(for: \.colors)
        options.append(contentsOf: values.map { FilterOption(value: $0, displayName: $0, isSpecial: false) })
        return options
    }
    
    // 尺码选项
    private var sizeOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noSizeMarker, displayName: "无尺码", isSpecial: true))
        let values = getAllValues(for: \.sizes)
        options.append(contentsOf: values.map { FilterOption(value: $0, displayName: $0, isSpecial: false) })
        return options
    }
    
    // 衣长选项
    private var lengthOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noLengthMarker, displayName: "无衣长", isSpecial: true))
        let values = getAllValues(for: \.length)
        options.append(contentsOf: values.map { FilterOption(value: $0, displayName: $0, isSpecial: false) })
        return options
    }
    
    // 状态选项
    private var conditionOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noConditionMarker, displayName: "无状态", isSpecial: true))
        let values = getAllValues(for: \.condition)
        options.append(contentsOf: values.map { FilterOption(value: $0, displayName: $0, isSpecial: false) })
        return options
    }
    
    // 小物选项
    private var accessoryOptions: [FilterOption] {
        var options: [FilterOption] = []
        options.append(FilterOption(value: MultiDimensionalFilterSheet.noAccessoryMarker, displayName: "无小物", isSpecial: true))
        let values = getAllValues(for: \.accessories)
        options.append(contentsOf: values.map { FilterOption(value: $0, displayName: $0, isSpecial: false) })
        return options
    }
    
    // MARK: - 辅助方法
    
    // 检查选项是否被选中
    private func isOptionSelected(option: FilterOption, section: FilterSection) -> Bool {
        switch section {
        case .tags:
            if let uuid = UUID(uuidString: option.value) {
                return selectedTagIDs.contains(uuid)
            }
            return false
        case .brands:
            if let uuid = UUID(uuidString: option.value) {
                return selectedBrandIDs.contains(uuid)
            }
            return false
        case .types:
            return selectedTypes.contains(option.value)
        case .colors:
            return selectedColors.contains(option.value)
        case .sizes:
            return selectedSizes.contains(option.value)
        case .length:
            return selectedLengths.contains(option.value)
        case .condition:
            return selectedConditions.contains(option.value)
        case .accessories:
            return selectedAccessories.contains(option.value)
        }
    }
    
    // 切换选项选中状态
    private func toggleOption(option: FilterOption, section: FilterSection) {
        switch section {
        case .tags:
            if let uuid = UUID(uuidString: option.value) {
                if selectedTagIDs.contains(uuid) {
                    selectedTagIDs.remove(uuid)
                } else {
                    selectedTagIDs.insert(uuid)
                }
            }
        case .brands:
            if let uuid = UUID(uuidString: option.value) {
                if selectedBrandIDs.contains(uuid) {
                    selectedBrandIDs.remove(uuid)
                } else {
                    selectedBrandIDs.insert(uuid)
                }
            }
        case .types:
            if selectedTypes.contains(option.value) {
                selectedTypes.remove(option.value)
            } else {
                selectedTypes.insert(option.value)
            }
        case .colors:
            if selectedColors.contains(option.value) {
                selectedColors.remove(option.value)
            } else {
                selectedColors.insert(option.value)
            }
        case .sizes:
            if selectedSizes.contains(option.value) {
                selectedSizes.remove(option.value)
            } else {
                selectedSizes.insert(option.value)
            }
        case .length:
            if selectedLengths.contains(option.value) {
                selectedLengths.remove(option.value)
            } else {
                selectedLengths.insert(option.value)
            }
        case .condition:
            if selectedConditions.contains(option.value) {
                selectedConditions.remove(option.value)
            } else {
                selectedConditions.insert(option.value)
            }
        case .accessories:
            if selectedAccessories.contains(option.value) {
                selectedAccessories.remove(option.value)
            } else {
                selectedAccessories.insert(option.value)
            }
        }
    }
    
    // 清除所有筛选
    private func clearAllFilters() {
        selectedTagIDs.removeAll()
        selectedBrandIDs.removeAll()
        selectedTypes.removeAll()
        selectedColors.removeAll()
        selectedSizes.removeAll()
        selectedLengths.removeAll()
        selectedConditions.removeAll()
        selectedAccessories.removeAll()
        depositStatusFilter = .all
    }
    
    // Helper to extract unique values from comma-separated strings
    private func getAllValues(for keyPath: KeyPath<Clothing, String>) -> [String] {
        let allString = clothings.map { $0[keyPath: keyPath] }.joined(separator: ",")
        let normalizedString = allString.replacingOccurrences(of: "，", with: ",")
        return Array(Set(normalizedString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
}

// MARK: - 筛选区块枚举
enum FilterSection {
    case tags, brands, types, colors, sizes, length, condition, accessories
}
