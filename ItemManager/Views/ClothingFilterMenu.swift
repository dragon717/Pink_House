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
            FilterStringSection(
                title: "类型",
                icon: "tshirt",
                selectedIcon: "tshirt.fill",
                options: getAllValues(for: \.types),
                selection: $selectedTypes
            )
        case .colors:
            FilterStringSection(
                title: "颜色",
                icon: "paintpalette",
                selectedIcon: "paintpalette.fill",
                options: getAllValues(for: \.colors),
                selection: $selectedColors
            )
        case .sizes:
            FilterStringSection(
                title: "尺码",
                icon: "ruler",
                selectedIcon: "ruler.fill",
                options: getAllValues(for: \.sizes),
                selection: $selectedSizes
            )
        case .length:
            FilterStringSection(
                title: "衣长",
                icon: "arrow.up.and.down",
                selectedIcon: "arrow.up.and.down.circle.fill",
                options: getAllValues(for: \.length),
                selection: $selectedLengths
            )
        case .condition:
            FilterStringSection(
                title: "状态",
                icon: "star",
                selectedIcon: "star.fill",
                options: getAllValues(for: \.condition),
                selection: $selectedConditions
            )
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
