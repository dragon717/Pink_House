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
    @State private var selectedTab: HomeTab = .wardrobe
    @State private var showingAddSheet = false
    @State private var sortOption: SortOption = .createdAtDesc
    
    // For Wardrobe View
    @State private var wardrobeSearchText = ""
    
    // For Deposit Plan View
    @State private var depositSearchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                LiquidBackground()
                    .ignoresSafeArea()
                
                // Content
                ScrollView {
                    if selectedTab == .wardrobe {
                        WardrobeView(searchText: $wardrobeSearchText, sortOption: sortOption)
                    } else {
                        DepositPlanView(searchText: $depositSearchText, sortOption: sortOption)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    tabSwitcher
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    actionButtons
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                    Text("定尾计划")
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
                    HStack {
                        if option == sortOption {
                            Image(systemName: "checkmark")
                        }
                        Text(option.rawValue)
                    }
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
            Button {} label: { Label("筛选品牌", systemImage: "tag") }
            Button {} label: { Label("筛选颜色", systemImage: "paintpalette") }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 16))
                .foregroundStyle(.primary)
        }
    }
    
    private var displayButton: some View {
        Menu {
            Button {} label: { Label("隐藏统计", systemImage: "chart.bar") }
            Button {} label: { Label("切换视图", systemImage: "square.grid.2x2") }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14))
                .foregroundStyle(.primary)
        }
    }
    
    private var addButton: some View {
        Menu {
            Button { showingAddSheet = true } label: { Label("手动添加", systemImage: "square.and.pencil") }
            Button {} label: { Label("从社区导入", systemImage: "cloud.download") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    HomeView()
}
