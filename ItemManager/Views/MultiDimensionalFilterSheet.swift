import Foundation
import SwiftUI

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
enum DepositStatusFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
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

    var iconName: String {
        switch self {
        case .all: return "heart"
        case .owned: return "checkmark.seal"
        case .depositPlan: return "heart.fill"
        }
    }
}

// MARK: - 多维筛选候选快照
struct WardrobeFilterNamedOption: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
}

struct WardrobeFilterFacetSnapshot: Equatable, Sendable {
    let tags: [WardrobeFilterNamedOption]
    let brands: [WardrobeFilterNamedOption]
    let types: [String]
    let colors: [String]
    let sizes: [String]
    let lengths: [String]
    let conditions: [String]
    let accessories: [String]
    let tagNameByID: [UUID: String]
    let brandNameByID: [UUID: String]

    init(
        tags: [WardrobeFilterNamedOption] = [],
        brands: [WardrobeFilterNamedOption] = [],
        types: [String] = [],
        colors: [String] = [],
        sizes: [String] = [],
        lengths: [String] = [],
        conditions: [String] = [],
        accessories: [String] = [],
        tagNameByID: [UUID: String]? = nil,
        brandNameByID: [UUID: String]? = nil
    ) {
        self.tags = tags
        self.brands = brands
        self.types = types
        self.colors = colors
        self.sizes = sizes
        self.lengths = lengths
        self.conditions = conditions
        self.accessories = accessories
        self.tagNameByID = tagNameByID ?? Self.nameByID(from: tags)
        self.brandNameByID = brandNameByID ?? Self.nameByID(from: brands)
    }

    func options(for field: ClothingField) -> [String] {
        switch field {
        case .types: return types
        case .colors: return colors
        case .sizes: return sizes
        case .length: return lengths
        case .condition: return conditions
        case .accessories: return accessories
        }
    }

    private static func nameByID(from options: [WardrobeFilterNamedOption]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for option in options {
            result[option.id] = option.name
        }
        return result
    }
}

// MARK: - 多维筛选Sheet
struct MultiDimensionalFilterSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let facetSnapshot: WardrobeFilterFacetSnapshot

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

    private var panelFallbackColor: Color {
        magicPalette.cardBackground.opacity(colorScheme == .dark ? 0.52 : 0.82)
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
                LiquidBackground(themeSkinWallpaperContext: .wardrobe)
                    .ignoresSafeArea()

                contentPanel
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
                    if totalFilterCount > 0 {
                        Button {
                            clearAllFilters()
                        } label: {
                            Text("清除")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .themeSkinLegibleText(level: .inline, slot: .filterSheet)
                        }
                    }
                }
            }
            .tint(magicPalette.accent)
            .onAppear {
                _ = MenuPerfSignpost.menuOpen("wardrobe.multi_filter.sheet_presented")
            }
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private var contentPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if totalFilterCount > 0 {
                    selectedFiltersSummary
                }

                depositStatusSelector
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView {
                VStack(spacing: 12) {
                    filterRow(
                        section: .tags,
                        title: "标签",
                        icon: "tag",
                        selectedCount: selectedTagIDs.count,
                        options: tagOptions
                    )

                    filterRow(
                        section: .brands,
                        title: "品牌",
                        icon: "bag",
                        selectedCount: selectedBrandIDs.count,
                        options: brandOptions
                    )

                    ForEach(visibleFields, id: \.self) { field in
                        dynamicFilterRow(for: field)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .themeSkinAdaptiveSectionCard(slot: .filterSheet, cornerRadius: 28, showsDecoration: true) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(panelFallbackColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var visibleFields: [ClothingField] {
        visibilityManager.fieldOrder.filter { visibilityManager.isVisible($0) }
    }

    // MARK: - 心愿尾款筛选
    private var depositStatusSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: depositStatusFilter.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(depositStatusFilter == .all ? magicPalette.secondaryText : magicPalette.accent)

                Text("心愿尾款")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(magicPalette.primaryText)
                    .themeSkinLegibleText(level: .inline, slot: .filterSheet)

                Spacer()

                Text(depositStatusFilter.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(depositStatusFilter == .all ? magicPalette.secondaryText : magicPalette.accent)
                    .themeSkinLegibleText(level: .inline, slot: .filterSheet)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(DepositStatusFilter.allCases) { filter in
                    depositStatusChip(filter)
                }
            }
        }
        .padding(12)
        .themeSkinAdaptiveSectionCard(slot: .filterSheet, cornerRadius: 18, showsDecoration: false) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(magicPalette.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(magicPalette.secondaryText.opacity(0.18), lineWidth: 0.6)
        }
    }

    private func depositStatusChip(_ filter: DepositStatusFilter) -> some View {
        let isSelected = depositStatusFilter == filter

        return Button {
            depositStatusFilter = filter
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.iconName)
                    .font(.system(size: 12, weight: .semibold))

                Text(filter.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? magicPalette.accent : magicPalette.secondaryText)
            .themeSkinLegibleText(level: isSelected ? .chip : .inline, slot: .filterChip)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .themeSkinAdaptiveSectionCard(slot: .filterChip, cornerRadius: 14, showsDecoration: false) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? magicPalette.accent.opacity(0.15) : magicPalette.cardBackground.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? magicPalette.accent.opacity(0.72) : magicPalette.secondaryText.opacity(0.22), lineWidth: isSelected ? 1.4 : 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 已选条件摘要
    private var selectedFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已选条件 (\(totalFilterCount))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(magicPalette.primaryText)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedFilterItems) { item in
                        selectedFilterChip(item: item)
                    }
                }
            }
        }
        .padding(12)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(magicPalette.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(magicPalette.secondaryText.opacity(0.18), lineWidth: 0.6)
        }
    }

    // 已选条件数据结构
    private struct SelectedFilterItem: Identifiable, Equatable {
        let section: FilterSection
        let value: String
        let rawValue: String // 用于删除时识别

        var id: String { "\(section.id):\(rawValue)" }
    }

    // 获取所有已选条件
    private var selectedFilterItems: [SelectedFilterItem] {
        var items: [SelectedFilterItem] = []

        for id in selectedTagIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let name = id == MultiDimensionalFilterSheet.noTagUUID ? "无标签" : facetSnapshot.tagNameByID[id] ?? "未知标签"
            items.append(SelectedFilterItem(section: .tags, value: name, rawValue: id.uuidString))
        }

        for id in selectedBrandIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let name = id == MultiDimensionalFilterSheet.noBrandUUID ? "无品牌" : facetSnapshot.brandNameByID[id] ?? "未知品牌"
            items.append(SelectedFilterItem(section: .brands, value: name, rawValue: id.uuidString))
        }

        for type in selectedTypes.sorted() {
            let name = type == MultiDimensionalFilterSheet.noTypeMarker ? "无类型" : type
            items.append(SelectedFilterItem(section: .types, value: name, rawValue: type))
        }

        for color in selectedColors.sorted() {
            let name = color == MultiDimensionalFilterSheet.noColorMarker ? "无颜色" : color
            items.append(SelectedFilterItem(section: .colors, value: name, rawValue: color))
        }

        for size in selectedSizes.sorted() {
            let name = size == MultiDimensionalFilterSheet.noSizeMarker ? "无尺码" : size
            items.append(SelectedFilterItem(section: .sizes, value: name, rawValue: size))
        }

        for length in selectedLengths.sorted() {
            let name = length == MultiDimensionalFilterSheet.noLengthMarker ? "无衣长" : length
            items.append(SelectedFilterItem(section: .length, value: name, rawValue: length))
        }

        for condition in selectedConditions.sorted() {
            let name = condition == MultiDimensionalFilterSheet.noConditionMarker ? "无状态" : condition
            items.append(SelectedFilterItem(section: .condition, value: name, rawValue: condition))
        }

        for accessory in selectedAccessories.sorted() {
            let name = accessory == MultiDimensionalFilterSheet.noAccessoryMarker ? "无小物" : accessory
            items.append(SelectedFilterItem(section: .accessories, value: name, rawValue: accessory))
        }

        if depositStatusFilter != .all {
            items.append(SelectedFilterItem(section: .depositStatus, value: depositStatusFilter.displayName, rawValue: depositStatusFilter.rawValue))
        }

        return items
    }

    // 已选条件标签
    private func selectedFilterChip(item: SelectedFilterItem) -> some View {
        HStack(spacing: 4) {
            Text(item.value)
                .font(.caption)
                .fontWeight(.medium)
                .themeSkinLegibleText(level: .chip, slot: .filterChip)

            Button {
                removeFilterItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(magicPalette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .themeSkinAdaptiveSectionCard(slot: .filterChip, cornerRadius: 16, showsDecoration: false) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(magicPalette.accent.opacity(0.15))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(magicPalette.accent.opacity(0.48), lineWidth: 0.8)
        }
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
        case .depositStatus:
            depositStatusFilter = .all
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
            Button {
                let nextSection: FilterSection? = expandedSection == section ? nil : section
                if nextSection != nil {
                    _ = MenuPerfSignpost.menuOpen("wardrobe.multi_filter.section.\(section.id)")
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = nextSection
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedCount > 0 ? magicPalette.accent : magicPalette.secondaryText)
                        .frame(width: 28)

                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(magicPalette.primaryText)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)

                    Spacer()

                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .themeSkinLegibleText(level: .chip, slot: .filterChip)
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
            }
            .buttonStyle(.plain)

            if expandedSection == section {
                Divider()
                    .opacity(0.22)
                    .padding(.horizontal, 16)

                filterOptionsGrid(options: options, section: section)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(magicPalette.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    selectedCount > 0 ? magicPalette.accent.opacity(0.55) : magicPalette.secondaryText.opacity(0.22),
                    lineWidth: selectedCount > 0 ? 1.4 : 0.6
                )
        }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
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
                .themeSkinLegibleText(level: isSelected ? .chip : .inline, slot: .filterChip)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .themeSkinAdaptiveSectionCard(slot: .filterChip, cornerRadius: 10, showsDecoration: false) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? magicPalette.accent.opacity(0.15) : magicPalette.cardBackground.opacity(0.55))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? magicPalette.accent : magicPalette.secondaryText.opacity(0.28), lineWidth: isSelected ? 1.4 : 0.6)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 选项数据
    private struct FilterOption: Identifiable, Equatable {
        let section: FilterSection
        let value: String
        let displayName: String
        let isSpecial: Bool // 标记是否是“无XXX”选项

        var id: String { "\(section.id):\(value)" }
    }

    private func specialOption(section: FilterSection, value: String, displayName: String) -> FilterOption {
        FilterOption(section: section, value: value, displayName: displayName, isSpecial: true)
    }

    // 标签选项
    private var tagOptions: [FilterOption] {
        [specialOption(section: .tags, value: MultiDimensionalFilterSheet.noTagUUID.uuidString, displayName: "无标签")] +
        facetSnapshot.tags.map { FilterOption(section: .tags, value: $0.id.uuidString, displayName: $0.name, isSpecial: false) }
    }

    // 品牌选项
    private var brandOptions: [FilterOption] {
        [specialOption(section: .brands, value: MultiDimensionalFilterSheet.noBrandUUID.uuidString, displayName: "无品牌")] +
        facetSnapshot.brands.map { FilterOption(section: .brands, value: $0.id.uuidString, displayName: $0.name, isSpecial: false) }
    }

    // 类型选项
    private var typeOptions: [FilterOption] {
        [specialOption(section: .types, value: MultiDimensionalFilterSheet.noTypeMarker, displayName: "无类型")] +
        facetSnapshot.types.map { FilterOption(section: .types, value: $0, displayName: $0, isSpecial: false) }
    }

    // 颜色选项
    private var colorOptions: [FilterOption] {
        [specialOption(section: .colors, value: MultiDimensionalFilterSheet.noColorMarker, displayName: "无颜色")] +
        facetSnapshot.colors.map { FilterOption(section: .colors, value: $0, displayName: $0, isSpecial: false) }
    }

    // 尺码选项
    private var sizeOptions: [FilterOption] {
        [specialOption(section: .sizes, value: MultiDimensionalFilterSheet.noSizeMarker, displayName: "无尺码")] +
        facetSnapshot.sizes.map { FilterOption(section: .sizes, value: $0, displayName: $0, isSpecial: false) }
    }

    // 衣长选项
    private var lengthOptions: [FilterOption] {
        [specialOption(section: .length, value: MultiDimensionalFilterSheet.noLengthMarker, displayName: "无衣长")] +
        facetSnapshot.lengths.map { FilterOption(section: .length, value: $0, displayName: $0, isSpecial: false) }
    }

    // 状态选项
    private var conditionOptions: [FilterOption] {
        [specialOption(section: .condition, value: MultiDimensionalFilterSheet.noConditionMarker, displayName: "无状态")] +
        facetSnapshot.conditions.map { FilterOption(section: .condition, value: $0, displayName: $0, isSpecial: false) }
    }

    // 小物选项
    private var accessoryOptions: [FilterOption] {
        [specialOption(section: .accessories, value: MultiDimensionalFilterSheet.noAccessoryMarker, displayName: "无小物")] +
        facetSnapshot.accessories.map { FilterOption(section: .accessories, value: $0, displayName: $0, isSpecial: false) }
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
        case .depositStatus:
            return depositStatusFilter.rawValue == option.value
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
        case .depositStatus:
            depositStatusFilter = DepositStatusFilter(rawValue: option.value) ?? .all
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
}

// MARK: - 筛选区块枚举
enum FilterSection: String, Identifiable, Hashable {
    case tags
    case brands
    case types
    case colors
    case sizes
    case length
    case condition
    case accessories
    case depositStatus

    var id: String { rawValue }
}
