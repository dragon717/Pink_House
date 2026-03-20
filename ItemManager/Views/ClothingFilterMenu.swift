import SwiftUI
import SwiftData

struct ClothingFilterMenu: View {
    let clothings: [Clothing]
    let tags: [Tag]
    let brands: [Brand]
    
    @Binding var selectedTagIDs: Set<UUID>
    @Binding var selectedBrandIDs: Set<UUID>
    @Binding var selectedTypes: Set<String>
    @Binding var selectedColors: Set<String>
    @Binding var selectedSizes: Set<String>
    @Binding var selectedLengths: Set<String>
    @Binding var selectedConditions: Set<String>
    @Binding var selectedAccessories: Set<String>
    
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    
    // 特殊筛选值：与 HomeView 中定义的一致
    static let noTagUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let noBrandUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    
    // 字符串类型字段的"无"标记
    static let noTypeMarker = "__NO_TYPE__"
    static let noColorMarker = "__NO_COLOR__"
    static let noSizeMarker = "__NO_SIZE__"
    static let noLengthMarker = "__NO_LENGTH__"
    static let noConditionMarker = "__NO_CONDITION__"
    static let noAccessoryMarker = "__NO_ACCESSORY__"
    
    var body: some View {
        Menu {
            // Tags Filter
            Menu {
                Button(role: .destructive) {
                    selectedTagIDs.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无标签选项
                Button {
                    if selectedTagIDs.contains(ClothingFilterMenu.noTagUUID) {
                        selectedTagIDs.remove(ClothingFilterMenu.noTagUUID)
                    } else {
                        selectedTagIDs.removeAll()
                        selectedTagIDs.insert(ClothingFilterMenu.noTagUUID)
                    }
                } label: {
                    HStack {
                        Text("无标签")
                        if selectedTagIDs.contains(ClothingFilterMenu.noTagUUID) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(tags) { tag in
                    Button {
                        if selectedTagIDs.contains(tag.id) {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.removeAll()
                            selectedTagIDs.insert(tag.id)
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                            if selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedTagName: String? = selectedTagIDs.first.flatMap { id in
                    if id == ClothingFilterMenu.noTagUUID {
                        return "无标签"
                    }
                    return tags.first(where: { $0.id == id })?.name
                }
                Label(selectedTagName ?? "标签", systemImage: selectedTagIDs.isEmpty ? "tag" : "tag.fill")
            }
            
            // Brands Filter
            Menu {
                Button(role: .destructive) {
                    selectedBrandIDs.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无品牌选项
                Button {
                    if selectedBrandIDs.contains(ClothingFilterMenu.noBrandUUID) {
                        selectedBrandIDs.remove(ClothingFilterMenu.noBrandUUID)
                    } else {
                        selectedBrandIDs.removeAll()
                        selectedBrandIDs.insert(ClothingFilterMenu.noBrandUUID)
                    }
                } label: {
                    HStack {
                        Text("无品牌")
                        if selectedBrandIDs.contains(ClothingFilterMenu.noBrandUUID) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(brands) { brand in
                    Button {
                        if selectedBrandIDs.contains(brand.id) {
                            selectedBrandIDs.remove(brand.id)
                        } else {
                            selectedBrandIDs.removeAll()
                            selectedBrandIDs.insert(brand.id)
                        }
                    } label: {
                        HStack {
                            Text(brand.name)
                            if selectedBrandIDs.contains(brand.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedBrandName: String? = selectedBrandIDs.first.flatMap { id in
                    if id == ClothingFilterMenu.noBrandUUID {
                        return "无品牌"
                    }
                    return brands.first(where: { $0.id == id })?.name
                }
                Label(selectedBrandName ?? "品牌", systemImage: selectedBrandIDs.isEmpty ? "bag" : "bag.fill")
            }
            
            // String-based Filters
            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                if visibilityManager.isVisible(field) {
                    buildFilterSection(for: field)
                }
            }
            
        } label: {
            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
    
    @ViewBuilder
    private func buildFilterSection(for field: ClothingField) -> some View {
        switch field {
        case .types:
            // 类型筛选需要特殊处理"无类型"选项
            Menu {
                Button(role: .destructive) {
                    selectedTypes.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无类型选项
                Button {
                    if selectedTypes.contains(ClothingFilterMenu.noTypeMarker) {
                        selectedTypes.remove(ClothingFilterMenu.noTypeMarker)
                    } else {
                        selectedTypes.removeAll()
                        selectedTypes.insert(ClothingFilterMenu.noTypeMarker)
                    }
                } label: {
                    HStack {
                        Text("无类型")
                        if selectedTypes.contains(ClothingFilterMenu.noTypeMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.types), id: \.self) { type in
                    Button {
                        if selectedTypes.contains(type) {
                            selectedTypes.remove(type)
                        } else {
                            selectedTypes.removeAll()
                            selectedTypes.insert(type)
                        }
                    } label: {
                        HStack {
                            Text(type)
                            if selectedTypes.contains(type) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedTypeName: String? = selectedTypes.first.flatMap { type in
                    type == ClothingFilterMenu.noTypeMarker ? "无类型" : type
                }
                Label(selectedTypeName ?? "类型", systemImage: selectedTypes.isEmpty ? "tshirt" : "tshirt.fill")
            }
            
        case .colors:
            // 颜色筛选需要特殊处理"无颜色"选项
            Menu {
                Button(role: .destructive) {
                    selectedColors.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无颜色选项
                Button {
                    if selectedColors.contains(ClothingFilterMenu.noColorMarker) {
                        selectedColors.remove(ClothingFilterMenu.noColorMarker)
                    } else {
                        selectedColors.removeAll()
                        selectedColors.insert(ClothingFilterMenu.noColorMarker)
                    }
                } label: {
                    HStack {
                        Text("无颜色")
                        if selectedColors.contains(ClothingFilterMenu.noColorMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.colors), id: \.self) { color in
                    Button {
                        if selectedColors.contains(color) {
                            selectedColors.remove(color)
                        } else {
                            selectedColors.removeAll()
                            selectedColors.insert(color)
                        }
                    } label: {
                        HStack {
                            Text(color)
                            if selectedColors.contains(color) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedColorName: String? = selectedColors.first.flatMap { color in
                    color == ClothingFilterMenu.noColorMarker ? "无颜色" : color
                }
                Label(selectedColorName ?? "颜色", systemImage: selectedColors.isEmpty ? "paintpalette" : "paintpalette.fill")
            }
            
        case .sizes:
            // 尺码筛选需要特殊处理"无尺码"选项
            Menu {
                Button(role: .destructive) {
                    selectedSizes.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无尺码选项
                Button {
                    if selectedSizes.contains(ClothingFilterMenu.noSizeMarker) {
                        selectedSizes.remove(ClothingFilterMenu.noSizeMarker)
                    } else {
                        selectedSizes.removeAll()
                        selectedSizes.insert(ClothingFilterMenu.noSizeMarker)
                    }
                } label: {
                    HStack {
                        Text("无尺码")
                        if selectedSizes.contains(ClothingFilterMenu.noSizeMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.sizes), id: \.self) { size in
                    Button {
                        if selectedSizes.contains(size) {
                            selectedSizes.remove(size)
                        } else {
                            selectedSizes.removeAll()
                            selectedSizes.insert(size)
                        }
                    } label: {
                        HStack {
                            Text(size)
                            if selectedSizes.contains(size) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedSizeName: String? = selectedSizes.first.flatMap { size in
                    size == ClothingFilterMenu.noSizeMarker ? "无尺码" : size
                }
                Label(selectedSizeName ?? "尺码", systemImage: selectedSizes.isEmpty ? "ruler" : "ruler.fill")
            }
            
        case .length:
            // 衣长筛选需要特殊处理"无衣长"选项
            Menu {
                Button(role: .destructive) {
                    selectedLengths.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无衣长选项
                Button {
                    if selectedLengths.contains(ClothingFilterMenu.noLengthMarker) {
                        selectedLengths.remove(ClothingFilterMenu.noLengthMarker)
                    } else {
                        selectedLengths.removeAll()
                        selectedLengths.insert(ClothingFilterMenu.noLengthMarker)
                    }
                } label: {
                    HStack {
                        Text("无衣长")
                        if selectedLengths.contains(ClothingFilterMenu.noLengthMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.length), id: \.self) { length in
                    Button {
                        if selectedLengths.contains(length) {
                            selectedLengths.remove(length)
                        } else {
                            selectedLengths.removeAll()
                            selectedLengths.insert(length)
                        }
                    } label: {
                        HStack {
                            Text(length)
                            if selectedLengths.contains(length) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedLengthName: String? = selectedLengths.first.flatMap { length in
                    length == ClothingFilterMenu.noLengthMarker ? "无衣长" : length
                }
                Label(selectedLengthName ?? "衣长", systemImage: selectedLengths.isEmpty ? "arrow.up.and.down" : "arrow.up.and.down.circle.fill")
            }
            
        case .condition:
            // 状态筛选需要特殊处理"无状态"选项
            Menu {
                Button(role: .destructive) {
                    selectedConditions.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无状态选项
                Button {
                    if selectedConditions.contains(ClothingFilterMenu.noConditionMarker) {
                        selectedConditions.remove(ClothingFilterMenu.noConditionMarker)
                    } else {
                        selectedConditions.removeAll()
                        selectedConditions.insert(ClothingFilterMenu.noConditionMarker)
                    }
                } label: {
                    HStack {
                        Text("无状态")
                        if selectedConditions.contains(ClothingFilterMenu.noConditionMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.condition), id: \.self) { condition in
                    Button {
                        if selectedConditions.contains(condition) {
                            selectedConditions.remove(condition)
                        } else {
                            selectedConditions.removeAll()
                            selectedConditions.insert(condition)
                        }
                    } label: {
                        HStack {
                            Text(condition)
                            if selectedConditions.contains(condition) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedConditionName: String? = selectedConditions.first.flatMap { condition in
                    condition == ClothingFilterMenu.noConditionMarker ? "无状态" : condition
                }
                Label(selectedConditionName ?? "状态", systemImage: selectedConditions.isEmpty ? "star" : "star.fill")
            }
            
        case .accessories:
            // 小物筛选需要特殊处理"无小物"选项
            Menu {
                Button(role: .destructive) {
                    selectedAccessories.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                
                // 无小物选项
                Button {
                    if selectedAccessories.contains(ClothingFilterMenu.noAccessoryMarker) {
                        selectedAccessories.remove(ClothingFilterMenu.noAccessoryMarker)
                    } else {
                        selectedAccessories.removeAll()
                        selectedAccessories.insert(ClothingFilterMenu.noAccessoryMarker)
                    }
                } label: {
                    HStack {
                        Text("无小物")
                        if selectedAccessories.contains(ClothingFilterMenu.noAccessoryMarker) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                ForEach(getAllValues(for: \.accessories), id: \.self) { accessory in
                    Button {
                        if selectedAccessories.contains(accessory) {
                            selectedAccessories.remove(accessory)
                        } else {
                            selectedAccessories.removeAll()
                            selectedAccessories.insert(accessory)
                        }
                    } label: {
                        HStack {
                            Text(accessory)
                            if selectedAccessories.contains(accessory) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let selectedAccessoryName: String? = selectedAccessories.first.flatMap { accessory in
                    accessory == ClothingFilterMenu.noAccessoryMarker ? "无小物" : accessory
                }
                Label(selectedAccessoryName ?? "小物", systemImage: selectedAccessories.isEmpty ? "sparkles" : "sparkles.rectangle.stack.fill")
            }
        }
    }
    
    // Helper to extract unique values from comma-separated strings
    private func getAllValues(for keyPath: KeyPath<Clothing, String>) -> [String] {
        let allString = clothings.map { $0[keyPath: keyPath] }.joined(separator: ",")
        // Replace Chinese comma with English comma before splitting
        let normalizedString = allString.replacingOccurrences(of: "，", with: ",")
        return Array(Set(normalizedString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
}

struct FilterStringSection: View {
    let title: String
    let icon: String
    let selectedIcon: String
    let options: [String]
    @Binding var selection: Set<String>
    
    var body: some View {
        Menu {
            Button(role: .destructive) {
                selection.removeAll()
            } label: {
                Label("清除筛选", systemImage: "xmark.circle")
            }
            
            ForEach(options, id: \.self) { option in
                Button {
                    if selection.contains(option) {
                        selection.remove(option)
                    } else {
                        selection.removeAll()
                        selection.insert(option)
                    }
                } label: {
                    HStack {
                        Text(option)
                        if selection.contains(option) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selection.first ?? title, systemImage: selection.isEmpty ? icon : selectedIcon)
        }
    }
}
