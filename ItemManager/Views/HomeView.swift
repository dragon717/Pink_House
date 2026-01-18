//
//  HomeView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

enum HomeTab {
    case wardrobe
    case depositPlan
}

struct HomeView: View {
    @State private var selectedTab: HomeTab = .wardrobe
    @State private var showingAddSheet = false
    
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
                        WardrobeView(searchText: $wardrobeSearchText)
                    } else {
                        DepositPlanView(searchText: $depositSearchText)
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
            Picker("排序", selection: .constant(0)) {
                Text("按时间").tag(0)
                Text("按价格").tag(1)
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
