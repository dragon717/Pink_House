//
//  ClothingListView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation

struct ClothingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    // Filter out deleted items at the query level
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }, sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \Brand.name) private var brands: [Brand]
    
    @State private var searchText = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var selectedTypes: Set<String> = []
    @State private var selectedColors: Set<String> = []
    @State private var selectedSizes: Set<String> = []
    @State private var selectedLengths: Set<String> = []
    @State private var selectedConditions: Set<String> = []
    @State private var selectedAccessories: Set<String> = []
    @State private var showingAddSheet = false
    @State private var showingBatchImportSheet = false
    @State private var itemToDelete: Clothing?
    @State private var showingDeleteAlert = false
    
    @State private var viewLayout: ViewLayout = .listDetailed
    
    // 3D模型筛选
    @State private var showOnly3DModels = false
    
    // 价格显示设置 - 使用单例管理器
    //@ObservedObject private var privacyManager = PrivacyManager.shared
    
    private var gridColumns: [GridItem] {
        let count: Int
        let spacing: CGFloat
        switch viewLayout {
        case .grid2: 
            count = 2
            spacing = 16
        case .grid3: 
            count = 3
            spacing = 16
        case .grid6: 
            count = 6
            spacing = 2
        default: 
            count = 1
            spacing = 16
        }
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
    
    var filteredClothings: [Clothing] {
        clothings.filter { clothing in
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                // Optimization: Check simple string properties first
                matchesSearch = clothing.name.localizedCaseInsensitiveContains(searchText) ||
                    clothing.types.localizedCaseInsensitiveContains(searchText) ||
                    clothing.colors.localizedCaseInsensitiveContains(searchText) ||
                    clothing.sizes.localizedCaseInsensitiveContains(searchText) ||
                    clothing.length.localizedCaseInsensitiveContains(searchText) ||
                    clothing.condition.localizedCaseInsensitiveContains(searchText) ||
                    clothing.accessories.localizedCaseInsensitiveContains(searchText) ||
                    (clothing.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (clothing.tags?.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ?? false)
            }
            
            let matchesTag: Bool
            if selectedTagIDs.isEmpty {
                matchesTag = true
            } else {
                let clothingTagIDs = Set(clothing.tags?.map { $0.id } ?? [])
                matchesTag = !selectedTagIDs.isDisjoint(with: clothingTagIDs)
            }
            
            let matchesBrand: Bool
            if selectedBrandIDs.isEmpty {
                matchesBrand = true
            } else {
                if let brand = clothing.brand {
                    matchesBrand = selectedBrandIDs.contains(brand.id)
                } else {
                    matchesBrand = false
                }
            }
            
            // Helper for splitting strings with support for both English and Chinese commas
            func splitValues(_ string: String) -> Set<String> {
                let normalized = string.replacingOccurrences(of: "，", with: ",")
                return Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }
            
            let matchesType: Bool = selectedTypes.isEmpty || !selectedTypes.isDisjoint(with: splitValues(clothing.types))
            
            let matchesColor: Bool = selectedColors.isEmpty || !selectedColors.isDisjoint(with: splitValues(clothing.colors))
            
            let matchesSize: Bool = selectedSizes.isEmpty || !selectedSizes.isDisjoint(with: splitValues(clothing.sizes))
            
            let matchesLength: Bool = selectedLengths.isEmpty || !selectedLengths.isDisjoint(with: splitValues(clothing.length))
            
            let matchesCondition: Bool = selectedConditions.isEmpty || !selectedConditions.isDisjoint(with: splitValues(clothing.condition))
            
            let matchesAccessory: Bool = selectedAccessories.isEmpty || !selectedAccessories.isDisjoint(with: splitValues(clothing.accessories))
            
            // 3D模型筛选
            let matches3DFilter: Bool = !showOnly3DModels || clothing.is3DModel
            
            return matchesSearch && matchesTag && matchesBrand && matchesType && matchesColor && matchesSize && matchesLength && matchesCondition && matchesAccessory && matches3DFilter
        }
    }
    
    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    content
                        .navigationTitle("少女衣柜")
                }
            } else {
                NavigationSplitView {
                    content
                        .navigationTitle("少女衣柜")
                } detail: {
                    ZStack {
                        LiquidBackground()
                        Text("请选择一件裙子")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                ClothingEditView(
                    clothing: nil,
                    initialBrandID: selectedBrandIDs.first,
                    initialTypes: selectedTypes
                )
            }
        }
        .sheet(isPresented: $showingBatchImportSheet) {
            BatchImportView()
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { itemToDelete = nil }
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    NotificationManager.shared.cancelNotification(for: item)
                    modelContext.delete(item)
                    // Sync widget
                    Task { await SharedPersistence.shared.syncWidgetData() }
                }
                itemToDelete = nil
            }
        } message: {
            Text("确定要删除这件裙子吗？此操作无法撤销。")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ZStack {
            LiquidBackground()
            
            Group {
                switch viewLayout {
                case .listBrief:
                    List {
                        ForEach(filteredClothings) { clothing in
                            NavigationLink {
                                ClothingDetailView(clothing: clothing)
                            } label: {
                                ClothingRowBrief(clothing: clothing)
                                    .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    itemToDelete = clothing
                                    showingDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                
                                Button {
                                    duplicateItem(clothing)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    duplicateItem(clothing)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                
                                Button(role: .destructive) {
                                    itemToDelete = clothing
                                    showingDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    
                case .listDetailed:
                    List {
                        ForEach(filteredClothings) { clothing in
                            Group {
                                ClothingRow(clothing: clothing)
                            }
                            .background(
                                NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
                                    EmptyView()
                                }
                                .opacity(0)
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    itemToDelete = clothing
                                    showingDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                
                                Button {
                                    duplicateItem(clothing)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    duplicateItem(clothing)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                
                                Button(role: .destructive) {
                                    itemToDelete = clothing
                                    showingDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    
                case .grid2, .grid3:
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filteredClothings) { clothing in
                                NavigationLink {
                                    ClothingDetailView(clothing: clothing)
                                } label: {
                                    ClothingCard(clothing: clothing)
                                        .contextMenu {
                                            Button {
                                                duplicateItem(clothing)
                                            } label: {
                                                Label("复制", systemImage: "doc.on.doc")
                                            }
                                            
                                            Button(role: .destructive) {
                                                itemToDelete = clothing
                                                showingDeleteAlert = true
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        .padding()
                    }
                    
                case .grid6:
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 2) {
                            ForEach(filteredClothings) { clothing in
                                NavigationLink {
                                    ClothingDetailView(clothing: clothing)
                                } label: {
                                    ClothingThumbnail(clothing: clothing)
                                        .contextMenu {
                                            Button {
                                                duplicateItem(clothing)
                                            } label: {
                                                Label("复制", systemImage: "doc.on.doc")
                                            }
                                            
                                            Button(role: .destructive) {
                                                itemToDelete = clothing
                                                showingDeleteAlert = true
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
            }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "衣橱里搜索名称、品牌、标签、属性...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        // 3D模型筛选按钮
                        Button {
                            showOnly3DModels.toggle()
                        } label: {
                            Label("3D模型", systemImage: "cube.box")
                                .symbolVariant(showOnly3DModels ? .fill : .none)
                        }
                        .foregroundStyle(showOnly3DModels ? .purple : .primary)
                        
                        Menu {
                            Picker("布局", selection: $viewLayout) {
                                ForEach(ViewLayout.allCases) { layout in
                                    Label(layout.rawValue, systemImage: layout.icon)
                                        .tag(layout)
                                }
                            }
                        } label: {
                            Label("布局", systemImage: viewLayout.icon)
                        }
                        
                        ClothingFilterMenu(
                            clothings: clothings,
                            tags: tags,
                            brands: brands,
                            selectedTagIDs: $selectedTagIDs,
                            selectedBrandIDs: $selectedBrandIDs,
                            selectedTypes: $selectedTypes,
                            selectedColors: $selectedColors,
                            selectedSizes: $selectedSizes,
                            selectedLengths: $selectedLengths,
                            selectedConditions: $selectedConditions,
                            selectedAccessories: $selectedAccessories
                        )
                        
                        Menu {
                            Button {
                                showingAddSheet = true
                            } label: {
                                Label("手动添加", systemImage: "plus")
                            }
                            
                            Button {
                                showingBatchImportSheet = true
                            } label: {
                                Label("批量导入", systemImage: "square.and.arrow.down.on.square")
                            }
                        } label: {
                            Label("新增", systemImage: "plus")
                        }
                    }
                }
            }
        }
    }
    
    private func duplicateItem(_ item: Clothing) {
        // Increment image ref counts
        for path in item.imagePaths {
            ImageManager.shared.incrementRefCount(fileName: path, context: modelContext)
        }
        
        let newItem = Clothing(
            name: "\(item.name) 副本",
            brand: item.brand,
            types: item.types,
            colors: item.colors,
            sizes: item.sizes,
            length: item.length,
            condition: item.condition,
            accessories: item.accessories,
            imagePaths: item.imagePaths,
            isShared: item.isShared,
            originalPrice: item.originalPrice,
            price: item.price,
            deposit: item.deposit,
            balance: item.balance,
            accessoriesPrice: item.accessoriesPrice,
            purchaseDate: item.purchaseDate,
            depositDate: item.depositDate,
            isDepositPlan: item.isDepositPlan,
            finalPaymentDate: item.finalPaymentDate,
            finalPaymentEndDate: item.finalPaymentEndDate,
            note: item.note,
            stock: item.stock,
            status: item.status
        )
        newItem.tags = item.tags
        
        // Duplicate accessory items
        if let items = item.accessoryItems {
            newItem.accessoryItems = items.map { item in
                AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex)
            }
        }
        
        modelContext.insert(newItem)
        
        // Schedule notification for the copy
        NotificationManager.shared.scheduleNotification(for: newItem)
        
        // Sync widget
        Task { await SharedPersistence.shared.syncWidgetData() }
    }
}
