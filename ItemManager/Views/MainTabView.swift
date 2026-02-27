//
//  MainTabView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private struct IsSimulationActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isSimulationActive: Bool {
        get { self[IsSimulationActiveKey.self] }
        set { self[IsSimulationActiveKey.self] = newValue }
    }
}

// MARK: - View 扩展：条件应用 searchToolbarBehavior
extension View {
    @ViewBuilder
    func applySearchToolbarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.automatic)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func applyTabBarMinimizeBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

// MARK: - iOS 18+ 现代 TabView
@available(iOS 18.0, *)
struct ModernTabView: View {
    @Binding var selectedTab: Int
    @Binding var homeTabSelection: HomeTab
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    
    @State private var searchText = ""
    
    // MARK: - 动态 Tab 标题和图标
    private var smallWorldTabTitle: String {
        switch smallWorldDestination {
        case .bigWorld:
            return "世界书"
        case .calendar:
            return "梦裙日历"
        case .wealth:
            return "来财"
        case .pet:
            return petDataManager.status.displayName
        case .ootd:
            return "穿搭手帐"
        case .ootdDefaultBook:
            return "魔法贴纸"
        case .menu:
            return "House"
        case .perler:
            return "拼豆工坊"
        case .wardrobe:
            return "衣橱"
        case .depositPlan:
            return "尾款天使"
        case .recycleBin:
            return "回收站"
        case .dressStock:
            return "裙子股市"
        }
    }

    private var smallWorldTabIcon: String {
        switch smallWorldDestination {
        case .bigWorld:
            return "globe.asia.australia"
        case .calendar:
            return "calendar"
        case .wealth:
            return "yensign.circle"
        case .pet:
            return "pawprint"
        case .ootd:
            return "book.pages"
        case .ootdDefaultBook:
            return "book.pages"
        case .menu:
            return "house.fill"
        case .perler:
            return "circle.grid.2x2"
        case .wardrobe:
            return "cabinet.fill"
        case .depositPlan:
            return "tag.fill"
        case .recycleBin:
            return "trash.fill"
        case .dressStock:
            return "chart.line.uptrend.xyaxis"
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("衣橱", systemImage: "cabinet.fill", value: 0) {
                WardrobeTabContent(homeTabSelection: $homeTabSelection)
            }
            
            Tab(smallWorldTabTitle, systemImage: smallWorldTabIcon, value: 1) {
                SmallWorldTabContent(
                    selectedTab: $selectedTab,
                    homeTab: $homeTabSelection,
                    destination: $smallWorldDestination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            }
            
            Tab("我", systemImage: "face.smiling", value: 2) {
                MeTabContent()
            }
            
            Tab(value: 3, role: .search) {
                GlobalSearchView(searchText: $searchText)
            }
        }
        // iOS 26+ 原生 API：向下滑动时自动最小化 TabBar
        .applyTabBarMinimizeBehavior()
        .applySearchToolbarBehavior()
        .toolbarBackground(Color(red: 0.698, green: 0.133, blue: 0.133), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .environment(\.isSimulationActive, isSimulationActive)
        .overlay {
            RewardBubbleView()
            PetOverlayView(action: {
                smallWorldDestination = .pet
            }, petName: petDataManager.status.displayName)
            // 修复：使用正确的 Binding 传递 selectedTab
            SmallWorldMenuOverlay(
                selectedTab: $selectedTab,
                smallWorldDestination: $smallWorldDestination,
                homeTab: $homeTabSelection
            )
        }
        .onReceive(tabNavigationManager.$navigateToTab) { tab in
            if let tab = tab {
                withAnimation {
                    // 如果是要跳转到HouseTab(1)，记录是从Tab 0进入的
                    if tab == 1 && selectedTab != 1 {
                        tabNavigationManager.recordEnteringSmallWorldFromHomeTab(homeTabSelection)
                    }
                    selectedTab = tab
                }
            }
        }
        .onReceive(tabNavigationManager.$navigateToHomeTab) { homeTab in
            if let homeTab = homeTab {
                withAnimation {
                    homeTabSelection = homeTab
                }
                tabNavigationManager.navigateToHomeTab = nil
            }
        }
        .onReceive(tabNavigationManager.$navigateToSmallWorld) { destination in
            if let destination = destination {
                withAnimation {
                    // 注意：此时 selectedTab 可能已经被 navigateToTab 的处理器设置为 1
                    // 所以不能依赖 selectedTab 来判断是否是House内部导航
                    // 而是应该依赖 TabNavigationManager 中的 isNavigatingInsideSmallWorld 标记
                    // 如果 isNavigatingInsideSmallWorld 为 false，说明是从外部进入
                    if !tabNavigationManager.isNavigatingInsideSmallWorld {
                        // 从其他Tab进入House，记录来源
                        tabNavigationManager.recordEnteringSmallWorldFromHomeTab(homeTabSelection)
                    }
                    // 如果 isNavigatingInsideSmallWorld 为 true，保持标记不变（内部导航）
                    smallWorldDestination = destination
                }
                tabNavigationManager.navigateToSmallWorld = nil
            }
        }
    }
    
    private var isSimulationActive: Bool {
        return smallWorldDestination == .wealth
    }
}

// MARK: - 衣橱 Tab 内容
@available(iOS 18.0, *)
struct WardrobeTabContent: View {
    @Binding var homeTabSelection: HomeTab
    
    var body: some View {
        NavigationStack {
            HomeView(selectedTab: $homeTabSelection)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - House Tab 内容
@available(iOS 18.0, *)
struct SmallWorldTabContent: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    var body: some View {
        NavigationStack {
            SmallWorldContainerView(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - 我 Tab 内容
@available(iOS 18.0, *)
struct MeTabContent: View {
    var body: some View {
        NavigationStack {
            MeView()
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - 搜索容器视图
@available(iOS 18.0, *)
struct SearchContainerView: View {
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]
    
    var filteredClothings: [Clothing] {
        if searchText.isEmpty {
            return []
        }
        return clothings.filter { clothing in
            let nameMatch = clothing.name.localizedCaseInsensitiveContains(searchText)
            let brandMatch = clothing.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false
            let tagMatch = clothing.tags?.contains { $0.name.localizedCaseInsensitiveContains(searchText) } ?? false
            return nameMatch || brandMatch || tagMatch
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                List {
                    if searchText.isEmpty {
                        Section("搜索建议") {
                            Label("裙子/小物名称", systemImage: "tshirt")
                            Label("品牌/标签tag", systemImage: "tag")
                        }
                    } else if filteredClothings.isEmpty {
                        ContentUnavailableView {
                            Label("未找到结果", systemImage: "magnifyingglass")
                        } description: {
                            Text("尝试其他关键词搜索")
                        }
                    } else {
                        Section("找到 \(filteredClothings.count) 件衣物") {
                            ForEach(filteredClothings) { clothing in
                                NavigationLink(destination: ClothingDetailView(clothing: clothing)) {
                                    HStack {
                                        clothingThumbnail(clothing)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(clothing.name)
                                                .font(.headline)
                                            if let brand = clothing.brand {
                                                Text(brand.name)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("全局搜索")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "全局搜索裙子、品牌、标签..."
            )
        }
    }
    
    @ViewBuilder
    private func clothingThumbnail(_ clothing: Clothing) -> some View {
        if let firstImagePath = clothing.imagePaths.first {
            AsyncLocalImageView(
                fileName: firstImagePath,
                displaySize: CGSize(width: 50, height: 50),
                contentMode: .fill,
                cornerRadius: 8,
                placeholderColor: Color.gray.opacity(0.2)
            )
            .overlay(
                Image(systemName: "tshirt")
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            )
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "tshirt")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

// MARK: - House容器视图
@available(iOS 18.0, *)
struct SmallWorldContainerView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        switch destination {
        case .menu:
            SmallWorldView(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
        case .ootd:
            OOTDViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .ootdDefaultBook:
            OOTDDefaultBookViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .pet:
            PetHomeViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .wealth:
            WealthViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .calendar:
            DreamDressCalendarViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .bigWorld:
            BigWorldViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .perler:
            PerlerBeadPatternListViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .recycleBin:
            RecycleBinViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .dressStock:
            DressStockMarketViewWithBackButton(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .wardrobe, .depositPlan:
            // 这些功能直接跳转到 Tab 0，不会在这里显示
            EmptyView()
        }
    }
}

// MARK: - 主 Tab 视图
struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @State private var homeTabSelection: HomeTab = .wardrobe
    @State private var smallWorldDestination: SmallWorldDestination = .menu
    @State private var isPlayingOpeningAnimation = false
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                ModernTabView(
                    selectedTab: $selectedTab,
                    homeTabSelection: $homeTabSelection,
                    smallWorldDestination: $smallWorldDestination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
                .overlay {
                    if isPlayingOpeningAnimation {
                        OpeningVideoOverlay(
                            isPlaying: $isPlayingOpeningAnimation,
                            onComplete: {
                                homeTabSelection = .wardrobe
                                selectedTab = 0
                            }
                        )
                    }
                }
                .noticePopup() // 添加公告弹窗
            }
        }
    }
}

// MARK: - 开场视频遮罩
struct OpeningVideoOverlay: View {
    @Binding var isPlaying: Bool
    let onComplete: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            PetVideoPlayer(videoName: "open_dress", isLooping: false, onFinished: {
                onComplete()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.8)) {
                        isPlaying = false
                    }
                }
            })
            .ignoresSafeArea()
            
            Button {
                onComplete()
                withAnimation(.easeOut(duration: 0.5)) {
                    isPlaying = false
                }
            } label: {
                Text("跳过")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.4))
                    .clipShape(Capsule())
            }
            .padding(.top, 50)
            .padding(.trailing, 20)
        }
        .transition(.opacity)
        .zIndex(200)
        .id("OpeningVideoOverlay")
    }
}

// MARK: - House页面返回按钮包装视图
// 这些包装视图用于在House页面显示自定义返回按钮，智能返回上一页

@available(iOS 18.0, *)
struct SmallWorldBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    var onBackToMenu: () -> Void
    
    @ObservedObject private var tabNavigationManager = TabNavigationManager.shared
    
    var body: some View {
        Button {
            withAnimation {
                switch tabNavigationManager.currentSmallWorldSource {
                case .wardrobe:
                    // 返回衣橱
                    homeTab = .wardrobe
                    selectedTab = 0
                case .depositPlan:
                    // 返回尾款天使
                    homeTab = .depositPlan
                    selectedTab = 0
                case .smallWorld:
                    // 返回House菜单
                    onBackToMenu()
                }
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - OOTDView 带返回按钮
@available(iOS 18.0, *)
struct OOTDViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        OOTDView(hideBackButton: true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - OOTDDefaultBookView 带返回按钮
@available(iOS 18.0, *)
struct OOTDDefaultBookViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        OOTDDefaultBookView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - PetHomeView 带返回按钮
@available(iOS 18.0, *)
struct PetHomeViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        PetHomeView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - WealthView 带返回按钮
@available(iOS 18.0, *)
struct WealthViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        WealthView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - DreamDressCalendarView 带返回按钮
@available(iOS 18.0, *)
struct DreamDressCalendarViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        DreamDressCalendarView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - BigWorldView 带返回按钮
@available(iOS 18.0, *)
struct BigWorldViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        BigWorldView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - PerlerBeadPatternListView 带返回按钮
@available(iOS 18.0, *)
struct PerlerBeadPatternListViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        PerlerBeadPatternListView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - RecycleBinView 带返回按钮
@available(iOS 18.0, *)
struct RecycleBinViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        RecycleBinView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

// MARK: - DressStockMarketView 带返回按钮
@available(iOS 18.0, *)
struct DressStockMarketViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        DressStockMarketView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: {
                            destination = .menu
                        }
                    )
                }
            }
    }
}

#Preview {
    MainTabView()
}
