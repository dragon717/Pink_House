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
                
                VStack(spacing: 0) {
                    // Custom Header
                    headerView
                        .padding(.top, 47) // Approximate safe area top
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                        .background(.ultraThinMaterial)
                    
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
            }
            .ignoresSafeArea()
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    ClothingEditView(clothing: nil)
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack(alignment: .center) {
            // Tab Switcher
            HStack(spacing: 20) {
                Button {
                    withAnimation {
                        selectedTab = .wardrobe
                    }
                } label: {
                    Text("我的衣橱")
                        .font(.system(size: selectedTab == .wardrobe ? 24 : 18, weight: selectedTab == .wardrobe ? .bold : .medium))
                        .foregroundStyle(selectedTab == .wardrobe ? .primary : .secondary)
                }
                
                Button {
                    withAnimation {
                        selectedTab = .depositPlan
                    }
                } label: {
                    Text("定尾计划")
                        .font(.system(size: selectedTab == .depositPlan ? 24 : 18, weight: selectedTab == .depositPlan ? .bold : .medium))
                        .foregroundStyle(selectedTab == .depositPlan ? .primary : .secondary)
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 16) {
                // Sort
                Menu {
                    Picker("排序", selection: .constant(0)) {
                        Text("按时间").tag(0)
                        Text("按价格").tag(1)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                // Filter
                Menu {
                    Button {
                        // Filter action
                    } label: {
                        Label("筛选品牌", systemImage: "tag")
                    }
                    Button {
                        // Filter action
                    } label: {
                        Label("筛选颜色", systemImage: "paintpalette")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                // Display
                Menu {
                    Button {
                        // Toggle stats
                    } label: {
                        Label("隐藏统计", systemImage: "chart.bar")
                    }
                    Button {
                        // Toggle grid/list
                    } label: {
                        Label("切换视图", systemImage: "square.grid.2x2")
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                }
                
                // Add
                Menu {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("手动添加", systemImage: "square.and.pencil")
                    }
                    
                    Button {
                        // Import action
                    } label: {
                        Label("从社区导入", systemImage: "cloud.download")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

#Preview {
    HomeView()
}
