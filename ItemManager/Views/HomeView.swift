//
//  HomeView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

enum SortOption: String, CaseIterable, Identifiable {
    case createdAtDesc = "添加时间从晚到早"
    case priceAsc = "价格从低到高"
    case priceDesc = "价格从高到低"
    case purchaseDateAsc = "购买时间从早到晚"
    case purchaseDateDesc = "购买时间从晚到早"
    case nameAsc = "名称从A到Z"
    case nameDesc = "名称从Z到A"
    
    var id: String { rawValue }
    
    var sortDescriptors: [SortDescriptor<Clothing>] {
        switch self {
        case .createdAtDesc:
            return [SortDescriptor(\Clothing.createdAt, order: .reverse)]
        case .priceAsc:
            return [SortDescriptor(\Clothing.price, order: .forward)]
        case .priceDesc:
            return [SortDescriptor(\Clothing.price, order: .reverse)]
        case .purchaseDateAsc:
            return [SortDescriptor(\Clothing.purchaseDate, order: .forward)]
        case .purchaseDateDesc:
            return [SortDescriptor(\Clothing.purchaseDate, order: .reverse)]
        case .nameAsc:
            return [SortDescriptor(\Clothing.name, order: .forward)]
        case .nameDesc:
            return [SortDescriptor(\Clothing.name, order: .reverse)]
        }
    }
}

enum HomeTab {
    case wardrobe
    case depositPlan
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allClothings: [Clothing]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Brand.name) private var brands: [Brand]

    @State private var selectedTab: HomeTab = .wardrobe
    @State private var showingAddSheet = false
    @State private var sortOption: SortOption = .createdAtDesc
    
    // Filter States
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var selectedTypes: Set<String> = []
    @State private var selectedColors: Set<String> = []
    @State private var selectedSizes: Set<String> = []
    @State private var selectedLengths: Set<String> = []
    @State private var selectedConditions: Set<String> = []
    @State private var selectedAccessories: Set<String> = []
    
    // For Wardrobe View
    @State private var wardrobeSearchText = ""
    
    // For Deposit Plan View
    @State private var depositSearchText = ""
    
    // View Layout Management
    enum ViewLayout: String, CaseIterable, Identifiable {
        case listBrief = "单行简略"
        case listDetailed = "单行详细"
        case grid2 = "双列"
        case grid3 = "三列"
        case grid6 = "六列"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .listBrief: return "list.bullet"
            case .listDetailed: return "list.bullet.rectangle.portrait"
            case .grid2: return "square.grid.2x2"
            case .grid3: return "square.grid.3x3"
            case .grid6: return "square.grid.3x2"
            }
        }
    }
    
    @State private var viewLayout: ViewLayout = .grid2
    @State private var showingCommunityImportAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                LiquidBackground()
                    .ignoresSafeArea()
                
                // Content
                if selectedTab == .wardrobe {
                    WardrobeView(
                        searchText: $wardrobeSearchText,
                        sortOption: sortOption,
                        viewLayout: viewLayout,
                        selectedTagIDs: selectedTagIDs,
                        selectedBrandIDs: selectedBrandIDs,
                        selectedTypes: selectedTypes,
                        selectedColors: selectedColors,
                        selectedSizes: selectedSizes,
                        selectedLengths: selectedLengths,
                        selectedConditions: selectedConditions,
                        selectedAccessories: selectedAccessories,
                        filterDescription: getFilterDescription(),
                        onClearFilter: clearAllFilters
                    )
                } else {
                    DepositPlanView(
                        searchText: $depositSearchText,
                        sortOption: sortOption,
                        selectedTagIDs: selectedTagIDs,
                        selectedBrandIDs: selectedBrandIDs,
                        selectedTypes: selectedTypes,
                        selectedColors: selectedColors,
                        selectedSizes: selectedSizes,
                        selectedLengths: selectedLengths,
                        selectedConditions: selectedConditions,
                        selectedAccessories: selectedAccessories
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    tabSwitcher
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    actionButtons
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(
                text: Binding(
                    get: { selectedTab == .wardrobe ? wardrobeSearchText : depositSearchText },
                    set: { newValue in
                        if selectedTab == .wardrobe {
                            wardrobeSearchText = newValue
                        } else {
                            depositSearchText = newValue
                        }
                    }
                ),
                placement: .automatic,
                prompt: "搜索名称、品牌、标签、属性..."
            )
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    ClothingEditView(clothing: nil)
                }
            }
        }
    }
    
    private var tabSwitcher: some View {
        HStack(spacing: 24) {
            Button {
                withAnimation {
                    selectedTab = .wardrobe
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .wardrobe ? "tshirt.fill" : "tshirt")
                        .font(.system(size: 16))
                    Text("少女衣橱")
                        .font(.system(size: 10, weight: selectedTab == .wardrobe ? .bold : .medium))
                }
                .foregroundStyle(selectedTab == .wardrobe ? Color.brown : .secondary)
                .frame(height: 44) // Ensure touch target meets guidelines
            }
            
            Button {
                withAnimation {
                    selectedTab = .depositPlan
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .depositPlan ? "calendar.badge.clock" : "calendar")
                        .font(.system(size: 16))
                    Text("尾款天使")
                        .font(.system(size: 10, weight: selectedTab == .depositPlan ? .bold : .medium))
                }
                .foregroundStyle(selectedTab == .depositPlan ? Color.brown : .secondary)
                .frame(height: 44) // Ensure touch target meets guidelines
            }
        }
    }
    
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            // Full Layout
            HStack(spacing: 12) {
                sortButton
                filterButton
                displayButton
                addButton
            }
            
            // Compact Layout (Three Dots)
            Menu {
                sortButton
                filterButton
                displayButton
                addButton
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }
    
    // Extracted buttons for reuse
    private var sortButton: some View {
        Menu {
            Picker("排序", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
        } label: {
            if let _ =  Optional(true) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
        }
    }
    
    private var filterButton: some View {
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
            
            // Types Filter
            Menu {
                Button(role: .destructive) {
                    selectedTypes.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                Label(selectedTypes.first ?? "类型", systemImage: selectedTypes.isEmpty ? "tshirt" : "tshirt.fill")
            }
            
            // Colors Filter
            Menu {
                Button(role: .destructive) {
                    selectedColors.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                Label(selectedColors.first ?? "颜色", systemImage: selectedColors.isEmpty ? "paintpalette" : "paintpalette.fill")
            }
            
            // Sizes Filter
            Menu {
                Button(role: .destructive) {
                    selectedSizes.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                Label(selectedSizes.first ?? "尺码", systemImage: selectedSizes.isEmpty ? "ruler" : "ruler.fill")
            }
            
            // Lengths Filter
            Menu {
                Button(role: .destructive) {
                    selectedLengths.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                Label(selectedLengths.first ?? "衣长", systemImage: selectedLengths.isEmpty ? "arrow.up.and.down" : "arrow.up.and.down.circle.fill")
            }
            
            // Conditions Filter
            Menu {
                Button(role: .destructive) {
                    selectedConditions.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                Label(selectedConditions.first ?? "状态", systemImage: selectedConditions.isEmpty ? "star" : "star.fill")
            }
            
            // Accessories Filter
            Menu {
                Button(role: .destructive) {
                    selectedAccessories.removeAll()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
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
                Label(selectedAccessories.first ?? "小物", systemImage: selectedAccessories.isEmpty ? "crown" : "crown.fill")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .symbolVariant(selectedTagIDs.isEmpty && selectedBrandIDs.isEmpty && selectedTypes.isEmpty && selectedColors.isEmpty && selectedSizes.isEmpty && selectedLengths.isEmpty && selectedConditions.isEmpty && selectedAccessories.isEmpty ? .none : .fill)
        }
    }
    
    // Helper to extract unique values from comma-separated strings
    private func getAllValues(for keyPath: KeyPath<Clothing, String>) -> [String] {
        let allString = allClothings.map { $0[keyPath: keyPath] }.joined(separator: ",")
        // Replace Chinese comma with English comma before splitting
        let normalizedString = allString.replacingOccurrences(of: "，", with: ",")
        return Array(Set(normalizedString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
    
    private var displayButton: some View {
        Menu {
            Picker("布局", selection: $viewLayout) {
                ForEach(ViewLayout.allCases) { layout in
                    Label(layout.rawValue, systemImage: layout.icon)
                        .tag(layout)
                }
            }
        } label: {
            Image(systemName: viewLayout.icon)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
        }
    }
    
    private var addButton: some View {
        Menu {
            Button { showingAddSheet = true } label: { Label("手动添加", systemImage: "square.and.pencil") }
            Button { showingCommunityImportAlert = true } label: { Label("从社区导入", systemImage: "icloud.and.arrow.down") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16))
                .foregroundStyle(.primary)
        }
        .alert("该功能敬请期待，联网版本激情开拓中～！", isPresented: $showingCommunityImportAlert) {
            Button("好的", role: .cancel) { }
        }
    }
    
    private func getFilterDescription() -> String? {
        var descriptions: [String] = []
        
        // Tags
        if !selectedTagIDs.isEmpty {
            let names = selectedTagIDs.compactMap { id in tags.first(where: { $0.id == id })?.name }
            if !names.isEmpty { descriptions.append(names.joined(separator: "/")) }
        }
        
        // Brands
        if !selectedBrandIDs.isEmpty {
            let names = selectedBrandIDs.compactMap { id in brands.first(where: { $0.id == id })?.name }
            if !names.isEmpty { descriptions.append(names.joined(separator: "/")) }
        }
        
        // Types
        if !selectedTypes.isEmpty { descriptions.append(selectedTypes.joined(separator: "/")) }
        
        // Colors
        if !selectedColors.isEmpty { descriptions.append(selectedColors.joined(separator: "/")) }
        
        // Sizes
        if !selectedSizes.isEmpty { descriptions.append(selectedSizes.joined(separator: "/")) }
        
        // Lengths
        if !selectedLengths.isEmpty { descriptions.append(selectedLengths.joined(separator: "/")) }
        
        // Conditions
        if !selectedConditions.isEmpty { descriptions.append(selectedConditions.joined(separator: "/")) }
        
        // Accessories
        if !selectedAccessories.isEmpty { descriptions.append(selectedAccessories.joined(separator: "/")) }
        
        if descriptions.isEmpty { return nil }
        return descriptions.joined(separator: " + ")
    }
    
    private func clearAllFilters() {
        selectedTagIDs.removeAll()
        selectedBrandIDs.removeAll()
        selectedTypes.removeAll()
        selectedColors.removeAll()
        selectedSizes.removeAll()
        selectedLengths.removeAll()
        selectedConditions.removeAll()
        selectedAccessories.removeAll()
    }
}

#Preview {
    HomeView()
}
