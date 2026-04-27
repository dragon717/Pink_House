//
//  ClothingListView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Foundation

struct ClothingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
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
        // 使用 ClothingSearchService 进行搜索
        let searchService = ClothingSearchService(clothings: clothings)
        let searchResults = searchService.search(query: searchText)
        
        // 如果没有搜索词，返回所有衣物
        let baseResults = searchText.isEmpty ? clothings : searchResults
        
        // 使用统一的筛选服务
        let config = ClothingFilterService.FilterConfig(
            selectedTagIDs: selectedTagIDs,
            selectedBrandIDs: selectedBrandIDs,
            selectedTypes: selectedTypes,
            selectedColors: selectedColors,
            selectedSizes: selectedSizes,
            selectedLengths: selectedLengths,
            selectedConditions: selectedConditions,
            selectedAccessories: selectedAccessories,
            depositStatusFilter: .all
        )
        
        let filtered = ClothingFilterService.filter(baseResults, config: config)
        
        // 应用3D模型筛选
        return filtered.filter { clothing in
            !showOnly3DModels || clothing.is3DModel
        }
    }
    
    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    content
                        .navigationTitle("少女衣柜")
                        .environment(\.containerPalette, containerPalette)
                }
            } else {
                NavigationSplitView {
                    content
                        .navigationTitle("少女衣柜")
                        .environment(\.containerPalette, containerPalette)
                } detail: {
                    ZStack {
                        LiquidBackground()
                        Text("请选择一件裙装")
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
            Text("确定要删除这件裙装吗？此操作无法撤销。")
        }
    }
    
    // 获取容器配色
    private var containerPalette: AdaptivePaletteV2 {
        themeManager.getPaletteForContainer(
            containerBackground: .ultraThinMaterial,
            colorScheme: colorScheme
        )
    }
    
    private var content: some View {
        ZStack {
            LiquidBackground()
            
            Group {
                switch viewLayout {
                case .listBrief:
                    contentList
                case .listDetailed:
                    contentList
                case .grid2, .grid3, .grid6:
                    gridContent
                }
            }
        }
    }
    
    // 列表内容 - 应用容器配色
    private var contentList: some View {
        List {
            ForEach(filteredClothings) { clothing in
                NavigationLink {
                    ClothingDetailView(clothing: clothing)
                } label: {
                    ClothingRowBrief(clothing: clothing)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: deleteClothings)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.containerPalette, containerPalette)
    }
    
    // 网格内容 - 应用容器配色
    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredClothings) { clothing in
                    NavigationLink {
                        ClothingDetailView(clothing: clothing)
                    } label: {
                        ClothingCard(clothing: clothing)
                    }
                }
            }
            .padding()
        }
        .environment(\.containerPalette, containerPalette)
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
        // 复制其他属性
        newItem.copyCurrencyAndShippingMetadata(from: item)
        newItem.tags = item.tags
        newItem.sortIndex = item.sortIndex
        newItem.replacedCutoutID = item.replacedCutoutID
        newItem.model3DPath = item.model3DPath
        newItem.model3DType = item.model3DType
        newItem.model3DThumbnailPath = item.model3DThumbnailPath
        
        // 复制尺码表图和价格表图
        newItem.sizeChartImagePath = item.sizeChartImagePath
        newItem.priceChartImagePath = item.priceChartImagePath
        
        // Duplicate accessory items
        if let items = item.accessoryItems {
            newItem.accessoryItems = items.map { item in
                AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex, imagePaths: item.imagePaths)
            }
        }
        
        // 增加尺码表图和价格表图的引用计数
        if let sizeChartPath = item.sizeChartImagePath {
            ImageManager.shared.incrementRefCount(fileName: sizeChartPath, context: modelContext)
        }
        if let priceChartPath = item.priceChartImagePath {
            ImageManager.shared.incrementRefCount(fileName: priceChartPath, context: modelContext)
        }
        
        modelContext.insert(newItem)

        do {
            try modelContext.save()
            NotificationManager.shared.scheduleNotification(for: newItem, modelContext: modelContext)
            Task { await SharedPersistence.shared.syncWidgetData(reason: "clothing-list-duplicate") }
            updateClothingCountCache()
        } catch {
            print("ClothingListView: Failed to save duplicated clothing: \(error)")
        }
    }
    
    /// 处理列表滑动删除
    private func deleteClothings(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { filteredClothings[$0] }
        
        for item in itemsToDelete {
            NotificationManager.shared.cancelNotification(for: item)
            
            // 软删除
            item.isDeleted = true
            item.deletedAt = Date()
            item.lastModified = Date()
            
            // 记录删除到 DeleteTracker，防止iCloud同步覆盖
            DeleteTracker.shared.recordDeletedClothing(id: item.id)
        }
        
        do {
            try modelContext.save()
            Task { @MainActor in
                await NotificationManager.shared.refreshAllKnownDepositNotifications(
                    modelContext: modelContext,
                    force: true,
                    reason: "list-delete"
                )
            }
            
            // Sync widget
            Task { await SharedPersistence.shared.syncWidgetData() }
            
            // 更新衣物数量缓存，用于魔法任务进度实时显示
            updateClothingCountCache()
        } catch {
            print("ClothingListView: Failed to save deletion: \(error)")
        }
    }
    
    /// 更新衣物数量缓存，用于魔法任务进度实时显示
    private func updateClothingCountCache() {
        do {
            let descriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.isDeleted == false })
            let count = try modelContext.fetchCount(descriptor)
            FeatureUnlockManager.shared.updateClothingCount(count)
            print("👗 衣物数量缓存已更新: \(count)")
        } catch {
            print("❌ 更新衣物数量缓存失败: \(error)")
        }
    }
}
