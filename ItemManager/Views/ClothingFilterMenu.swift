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
    
    var body: some View {
        Menu {
            // Tags Filter
            Menu {
                Button(role: .destructive) {
                    selectedTagIDs.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                let selectedTagName = selectedTagIDs.first.flatMap { id in tags.first(where: { $0.id == id })?.name }
                Label(selectedTagName ?? "标签", systemImage: selectedTagIDs.isEmpty ? "tag" : "tag.fill")
            }
            
            // Brands Filter
            Menu {
                Button(role: .destructive) {
                    selectedBrandIDs.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                let selectedBrandName = selectedBrandIDs.first.flatMap { id in brands.first(where: { $0.id == id })?.name }
                Label(selectedBrandName ?? "品牌", systemImage: selectedBrandIDs.isEmpty ? "bag" : "bag.fill")
            }
            
            // String-based Filters
            if visibilityManager.isVisible(.types) {
                FilterStringSection(
                    title: "类型",
                    icon: "tshirt",
                    selectedIcon: "tshirt.fill",
                    options: getAllValues(for: \.types),
                    selection: $selectedTypes
                )
            }
            
            if visibilityManager.isVisible(.colors) {
                FilterStringSection(
                    title: "颜色",
                    icon: "paintpalette",
                    selectedIcon: "paintpalette.fill",
                    options: getAllValues(for: \.colors),
                    selection: $selectedColors
                )
            }
            
            if visibilityManager.isVisible(.sizes) {
                FilterStringSection(
                    title: "尺码",
                    icon: "ruler",
                    selectedIcon: "ruler.fill",
                    options: getAllValues(for: \.sizes),
                    selection: $selectedSizes
                )
            }
            
            if visibilityManager.isVisible(.length) {
                FilterStringSection(
                    title: "衣长",
                    icon: "arrow.up.and.down",
                    selectedIcon: "arrow.up.and.down.circle.fill",
                    options: getAllValues(for: \.length),
                    selection: $selectedLengths
                )
            }
            
            if visibilityManager.isVisible(.condition) {
                FilterStringSection(
                    title: "状态",
                    icon: "star",
                    selectedIcon: "star.fill",
                    options: getAllValues(for: \.condition),
                    selection: $selectedConditions
                )
            }
            
            if visibilityManager.isVisible(.accessories) {
                FilterStringSection(
                    title: "小物",
                    icon: "sparkles",
                    selectedIcon: "sparkles.rectangle.stack.fill",
                    options: getAllValues(for: \.accessories),
                    selection: $selectedAccessories
                )
            }
            
        } label: {
            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
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
