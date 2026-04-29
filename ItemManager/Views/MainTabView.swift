//
//  MainTabView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import SwiftData
import Combine

private struct IsSimulationActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isSimulationActive: Bool {
        get { self[IsSimulationActiveKey.self] }
        set { self[IsSimulationActiveKey.self] = newValue }
    }
}

// MARK: - 衣橱 Tab 内容
struct WardrobeTabContent: View {
    @Binding var homeTabSelection: HomeTab
    
    var body: some View {
        NavigationStack {
            HomeView(selectedTab: $homeTabSelection)
        }
    }
}

// MARK: - House Tab 内容
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
struct MeTabContent: View {
    var body: some View {
        NavigationStack {
            MeView()
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - 搜索容器视图
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
                            Label("裙装/小物名称", systemImage: "tshirt")
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
            if #available(iOS 18.0, *) {
                OOTDViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                OOTDViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .ootdDefaultBook:
            if #available(iOS 18.0, *) {
                OOTDDefaultBookViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                OOTDDefaultBookViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .pet:
            if #available(iOS 18.0, *) {
                PetHomeViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                PetHomeViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .wealth(let initialTab):
            if #available(iOS 18.0, *) {
                WealthViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    initialTab: initialTab
                )
            } else {
                WealthViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    initialTab: initialTab
                )
            }
        case .calendar:
            if #available(iOS 18.0, *) {
                DreamDressCalendarViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                DreamDressCalendarViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .bigWorld:
            if #available(iOS 18.0, *) {
                BigWorldViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                BigWorldViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .perler:
            if #available(iOS 18.0, *) {
                PerlerBeadPatternListViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                PerlerBeadPatternListViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .recycleBin:
            if #available(iOS 18.0, *) {
                RecycleBinViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                RecycleBinViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .dressStock:
            if #available(iOS 18.0, *) {
                DressStockMarketViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            } else {
                DressStockMarketViewWithBackButtonLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination
                )
            }
        case .wardrobe, .depositPlan:
            // 这些功能直接跳转到 Tab 0，不会在这里显示
            EmptyView()
        }
    }
}

// MARK: - 主 Tab 视图
// MARK: - iOS 18以下 自定义椭圆胶囊底部导航栏
struct LegacyTabView: View {
    @Binding var selectedTab: Int
    @Binding var homeTabSelection: HomeTab
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    
    // 搜索文本状态
    @State private var searchText = ""

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var themedTabBarDescriptor: ThemeSkinDescriptor? {
        resolveTabBarDescriptor(for: .tabBarMain)
    }

    private var themedTabItemDescriptor: ThemeSkinDescriptor? {
        resolveTabBarDescriptor(for: .tabBarItem)
    }

    var body: some View {
        ZStack {
            // 内容区域
            contentView

            // 自定义底部导航栏
            VStack {
                Spacer()
                customTabBar
            }
        }
        .overlay {
            RewardBubbleView()
            // 进入 House / 萌宠对话页后不再显示全局悬浮宠物，避免挡住房间热区或搜索/输入交互
            if selectedTab != 1 && selectedTab != 3 {
                PetOverlayView(action: {
                    // 点击悬浮小猫：切换到萌宠对话 Tab 并自动展开搜索栏
                    withAnimation {
                        selectedTab = 3
                    }
                }, petName: petDataManager.status.displayName)
            }
            SmallWorldMenuOverlay(
                selectedTab: $selectedTab,
                smallWorldDestination: $smallWorldDestination,
                homeTab: $homeTabSelection
            )
        }
        .onReceive(tabNavigationManager.$navigateToTab) { tab in
            if let tab = tab {
                withAnimation {
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
                    if !tabNavigationManager.isNavigatingInsideSmallWorld {
                        tabNavigationManager.recordEnteringSmallWorldFromHomeTab(homeTabSelection)
                    }
                    smallWorldDestination = destination
                }
                tabNavigationManager.navigateToSmallWorld = nil
            }
        }
        .onChange(of: selectedTab) { newTab in
            // 发送Tab切换通知，用于新手引导
            let tabName: String
            switch newTab {
            case 0: tabName = "wardrobe"
            case 1: tabName = "smallWorld"
            case 2: tabName = "me"
            case 3: tabName = "petChat"
            default: tabName = "unknown"
            }
            NotificationCenter.default.post(
                name: .homeTabChanged,
                object: nil,
                userInfo: ["tab": tabName]
            )
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 0:
            NavigationStack {
                HomeView(selectedTab: $homeTabSelection)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        case 1:
            NavigationStack {
                SmallWorldContainerViewLegacy(
                    selectedTab: $selectedTab,
                    homeTab: $homeTabSelection,
                    destination: $smallWorldDestination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        case 2:
            NavigationStack {
                MeView()
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        case 3:
            PetChatViewLegacy(searchText: $searchText)
        default:
            NavigationStack {
                HomeView(selectedTab: $homeTabSelection)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }

    private var customTabBar: some View {
        GeometryReader { geometry in
            let safeAreaBottom = geometry.safeAreaInsets.bottom

            // 使用VStack将内容推到底部
            VStack {
                Spacer()
                // 椭圆胶囊容器
                HStack(spacing: -8) {
                    // 衣橱 Tab
                    tabButton(
                        index: 0,
                        title: "衣橱",
                        icon: "cabinet.fill",
                        tabRole: .wardrobe
                    )

                    // House Tab
                    tabButton(
                        index: 1,
                        title: smallWorldTabTitle,
                        icon: smallWorldTabIcon,
                        tabRole: .house
                    )

                    // 我 Tab
                    tabButton(
                        index: 2,
                        title: "我",
                        icon: "face.smiling",
                        tabRole: .me
                    )

                    // 萌宠对话 Tab
                    tabButton(
                        index: 3,
                        title: "萌宠对话",
                        icon: "bubble.left.and.bubble.right.fill",
                        tabRole: .petChat
                    )
                }
                .frame(height: 56)
                .background {
                    if themedTabBarDescriptor != nil {
                        ThemeSkinTabBarBackdrop(
                            descriptor: themedTabBarDescriptor,
                            safeAreaBottom: 0,
                            horizontalPadding: 0,
                            bottomPadding: 0
                        )
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(magicPalette.navigationBackground.opacity(colorScheme == .dark ? 0.78 : 0.88))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(magicPalette.quickOptionStroke.opacity(0.55), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
                    }
                }
                .padding(.horizontal, 16)
                // 往下挪，紧贴底部（减小安全区域间距）
                .padding(.bottom, safeAreaBottom > 0 ? 2 : 4)
            }
        }
    }

    private func tabButton(index: Int, title: String, icon: String, tabRole: ThemeSkinTabRole) -> some View {
        let isSelected = selectedTab == index
        let isNotOnMenu: Bool = {
            if case .menu = smallWorldDestination { return false }
            return true
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                // 修复：如果已经在 House Tab (index=1) 且当前不在 menu 页面，则返回到 menu
                if index == 1 && selectedTab == 1 && isNotOnMenu {
                    smallWorldDestination = .menu
                } else {
                    selectedTab = index
                }
            }
        } label: {
            ThemeSkinLegacyTabLabel(
                descriptor: themedTabItemDescriptor,
                title: title,
                systemImage: icon,
                isSelected: isSelected,
                selectedColor: magicPalette.accent,
                inactiveColor: magicPalette.secondaryText,
                tabRole: tabRole
            )
            .captureGuideTarget(index == 1 ? .homeHouseTab : nil)
            .overlay {
                Color.clear
                    .frame(width: 68, height: 56)
                    .allowsHitTesting(false)
                    .captureGuideTarget(index == 3 ? .homePetChatTab : nil)
            }
        }
    }

    private func resolveTabBarDescriptor(for slot: ThemeSkinSlot) -> ThemeSkinDescriptor? {
        guard let descriptor = themeSkinManager.activeThemeDescriptor(for: slot, state: .default),
              WardrobeThemeSkinSupport.isThemeSkinDescriptor(descriptor) else {
            return nil
        }
        return descriptor
    }

    private var smallWorldTabTitle: String {
        switch smallWorldDestination {
        case .bigWorld: return "世界书"
        case .calendar: return "梦裙日历"
        case .wealth(_): return "来财"
        case .pet: return petDataManager.status.displayName
        case .ootd: return "穿搭手帐"
        case .ootdDefaultBook: return "魔法贴纸"
        case .menu: return "House"
        case .perler: return "拼豆工坊"
        case .wardrobe: return "衣橱"
        case .depositPlan: return "心愿尾款"
        case .recycleBin: return "回收站"
        case .dressStock: return "裙子股市"
        }
    }

    private var smallWorldTabIcon: String {
        switch smallWorldDestination {
        case .bigWorld: return "globe.asia.australia"
        case .calendar: return "calendar"
        case .wealth(_): return "yensign.circle"
        case .pet: return "pawprint"
        case .ootd: return "book.pages"
        case .ootdDefaultBook: return "book.pages"
        case .menu: return "house.fill"
        case .perler: return "circle.grid.2x2"
        case .wardrobe: return "cabinet.fill"
        case .depositPlan: return "tag.fill"
        case .recycleBin: return "trash.fill"
        case .dressStock: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - iOS 18以下 SmallWorld容器视图
struct SmallWorldContainerViewLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool

    var body: some View {
        switch destination {
        case .menu:
            SmallWorldView(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
        case .ootd:
            OOTDViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .ootdDefaultBook:
            OOTDDefaultBookViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .pet:
            PetHomeViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .wealth(let initialTab):
            WealthViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination,
                initialTab: initialTab
            )
        case .calendar:
            DreamDressCalendarViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .bigWorld:
            BigWorldViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .perler:
            PerlerBeadPatternListViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .recycleBin:
            RecycleBinViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .dressStock:
            DressStockMarketViewWithBackButtonLegacy(
                selectedTab: $selectedTab,
                homeTab: $homeTab,
                destination: $destination
            )
        case .wardrobe, .depositPlan:
            EmptyView()
        }
    }
}

// MARK: - iOS 18以下 全局搜索视图
struct GlobalSearchViewLegacy: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]
    @State private var searchText = ""

    var filteredClothings: [Clothing] {
        if searchText.isEmpty { return [] }
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
                LiquidBackground()
                    .ignoresSafeArea()

                List {
                    if searchText.isEmpty {
                        Section("搜索建议") {
                            Label("裙装/小物名称", systemImage: "tshirt")
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

// MARK: - iOS 18以下 返回按钮包装视图
struct SmallWorldBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    var onBackToMenu: () -> Void
    @ObservedObject private var tabNavigationManager = TabNavigationManager.shared

    var body: some View {
        Button {
            withAnimation {
                switch tabNavigationManager.currentSmallWorldSource {
                case .wardrobe:
                    homeTab = .wardrobe
                    selectedTab = 0
                case .depositPlan:
                    homeTab = .depositPlan
                    selectedTab = 0
                case .smallWorld:
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

struct OOTDViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @State private var isBookSelected: Bool = false
    @State private var isSpaceBookSelected: Bool = false

    var body: some View {
        OOTDView(hideBackButton: true, isBookSelected: $isBookSelected, isSpaceBookSelected: $isSpaceBookSelected)
            .toolbar {
                if !isBookSelected && !isSpaceBookSelected {
                    ToolbarItem(placement: .topBarLeading) {
                        SmallWorldBackButtonLegacy(
                            selectedTab: $selectedTab,
                            homeTab: $homeTab,
                            onBackToMenu: { destination = .menu }
                        )
                    }
                }
            }
    }
}

struct OOTDDefaultBookViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        OOTDDefaultBookView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MagicStickerBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        destination: $destination
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToBook)) { _ in
                // 导航到 OOTD 手帐列表
                withAnimation {
                    destination = .ootd
                }
            }
    }
}

// MARK: - 魔法贴纸返回按钮（带菜单）- iOS 18以下
struct MagicStickerBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil && $0.title != "默认手帐" }, sort: \BookGroup.sortIndex) private var otherBooks: [BookGroup]

    @ObservedObject private var tabNavigationManager = TabNavigationManager.shared
    @State private var showingMoveOptions = false
    @State private var showingBookPicker = false

    var body: some View {
        Button {
            showingMoveOptions = true
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
        .confirmationDialog("书页管理", isPresented: $showingMoveOptions, titleVisibility: .visible) {
            Button("保持在默认手帐") {
                goBack()
            }

            if !otherBooks.isEmpty {
                Button("加入其他手帐") {
                    showingBookPicker = true
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("当前书页在'默认手帐'中，您可以选择保持现状或移动到其他手帐")
        }
        .sheet(isPresented: $showingBookPicker) {
            BookPickerSheetLegacy(
                books: otherBooks,
                onSelect: { selectedBook in
                    moveCurrentPage(to: selectedBook)
                },
                onCancel: {
                    showingBookPicker = false
                }
            )
        }
    }

    private func goBack() {
        withAnimation {
            switch tabNavigationManager.currentSmallWorldSource {
            case .wardrobe:
                homeTab = .wardrobe
                selectedTab = 0
            case .depositPlan:
                homeTab = .depositPlan
                selectedTab = 0
            case .smallWorld:
                destination = .menu
            }
        }
    }

    private func moveCurrentPage(to book: BookGroup) {
        // 获取当前默认手帐
        let bookDescriptor = FetchDescriptor<BookGroup>(
            predicate: #Predicate<BookGroup> { $0.title == "默认手帐" && $0.deletedAt == nil }
        )
        guard let defaultBook = try? modelContext.fetch(bookDescriptor).first else { return }

        // 获取默认手帐的第一页 - 使用bookID避免在Predicate中捕获外部变量
        let defaultBookID = defaultBook.id
        let outfitDescriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate<Outfit> { outfit in
                outfit.isDeleted == false
            },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        let allOutfits = (try? modelContext.fetch(outfitDescriptor)) ?? []
        guard let firstOutfit = allOutfits.first(where: { $0.book?.id == defaultBookID }) else { return }

        // 移动书页到选中的手帐
        firstOutfit.book = book
        firstOutfit.lastModified = Date()

        // 重新计算sortIndex - 使用bookID避免在Predicate中捕获外部变量
        let targetBookID = book.id
        let existingPages = allOutfits.filter { $0.book?.id == targetBookID && $0.isDeleted == false }
            .sorted { $0.sortIndex > $1.sortIndex }
        firstOutfit.sortIndex = (existingPages.first?.sortIndex ?? 0) + 1

        try? modelContext.save()

        showingBookPicker = false

        // 发送通知让 OOTDDefaultBookView 显示 Toast 并导航
        NotificationCenter.default.post(
            name: .magicStickerPageMoved,
            object: nil,
            userInfo: ["bookTitle": book.title, "bookID": book.id]
        )
    }
}

// MARK: - 手帐选择Sheet - iOS 18以下
struct BookPickerSheetLegacy: View {
    let books: [BookGroup]
    let onSelect: (BookGroup) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            List(books) { book in
                Button {
                    onSelect(book)
                } label: {
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.pink)
                        Text(book.title)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("选择目标手帐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct PetHomeViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    var body: some View {
        PetHomeView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

struct WealthViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    var initialTab: WealthMainTab? = nil

    var body: some View {
        WealthView(initialTab: initialTab)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

struct DreamDressCalendarViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    var body: some View {
        // 使用toolbar添加返回按钮，与其他视图保持一致
        DreamDressCalendarView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

struct BigWorldViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    var body: some View {
        BigWorldView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

struct PerlerBeadPatternListViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    var body: some View {
        PerlerBeadPatternListView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

struct RecycleBinViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    var body: some View {
        RecycleBinView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

struct DressStockMarketViewWithBackButtonLegacy: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination

    var body: some View {
        DressStockMarketView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButtonLegacy(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

// MARK: - 主 Tab 视图
struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @State private var homeTabSelection: HomeTab = .wardrobe
    @State private var smallWorldDestination: SmallWorldDestination = .menu
    @State private var isPlayingOpeningAnimation = false

    var body: some View {
        LegacyTabView(
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
        .noticePopup()
        .withMagicTaskCompletions()
        // 监听解锁后的跳转通知
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSmallWorldDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? SmallWorldDestination {
                // 检查功能是否已解锁
                if destination.canAccess {
                    withAnimation {
                        smallWorldDestination = destination
                        selectedTab = 1 // 切换到 House Tab
                    }
                } else {
                    // 未解锁，显示提示
                    NotificationCenter.default.post(
                        name: .navigateToMagicTasks,
                        object: nil
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { notification in
            print("[PetChatGuide] MainTabView 收到 navigateToSettings 通知")
            // 跳转到设置页面
            withAnimation {
                selectedTab = 2 // 切换到"我"Tab
                print("[PetChatGuide] 已切换到 Tab 2 (我)")
            }
            // 如果有具体功能参数，延迟后发送到 MeView 处理导航
            if let feature = notification.userInfo?["feature"] as? String {
                print("[PetChatGuide] 有具体功能参数: \(feature)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .navigateToSettingsFeature,
                        object: nil,
                        userInfo: ["feature": feature]
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHomeTab)) { notification in
            // 跳转到衣橱页面（用于批量导入等功能）
            if let homeTabString = notification.userInfo?["homeTab"] as? String {
                withAnimation {
                    if homeTabString == "wardrobe" {
                        homeTabSelection = .wardrobe
                    } else if homeTabString == "depositPlan" {
                        homeTabSelection = .depositPlan
                    }
                    selectedTab = 0 // 切换到衣橱 Tab
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMagicTasks)) { _ in
            // 跳转到"我"Tab，然后显示魔法任务
            withAnimation {
                selectedTab = 2 // 切换到"我"Tab
            }
            // 延迟后发送通知显示魔法任务
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .showMagicTasks,
                    object: nil
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPetChat)) { _ in
            // 跳转到萌宠对话页面
            withAnimation {
                selectedTab = 3
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFirstUseGuide)) { notification in
            // 显示功能首次使用引导
            if let featureString = notification.userInfo?["feature"] as? String,
               let feature = FeatureItem(rawValue: featureString) {
                // 跳转到对应功能并显示引导
                navigateToFeatureWithGuide(feature)
            }
        }
        .onChange(of: smallWorldDestination) { _, newDestination in
            if case .wealth = newDestination {
                NotificationCenter.default.post(name: .wealthDestinationOpened, object: nil)
            }
        }
    }

    private func navigateToFeatureWithGuide(_ feature: FeatureItem) {
        let isUnlocked = FeatureUnlockManager.shared.isUnlocked(feature)

        switch feature {
        case .dataBackup:
            // 跳转到设置页面的备份功能
            withAnimation {
                selectedTab = 2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .navigateToSettings,
                    object: nil,
                    userInfo: ["feature": "dataBackup"]
                )
                startFeatureGuideAfterNavigation(feature)
            }
        case .cloudSync:
            // 跳转到设置页面的iCloud同步功能
            withAnimation {
                selectedTab = 2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .navigateToSettings,
                    object: nil,
                    userInfo: ["feature": "cloudSync"]
                )
                startFeatureGuideAfterNavigation(feature)
            }
        case .themeCustomize:
            // 从魔法任务详情页开始，先引导真实返回到「我」页，再找主题配色豆腐块
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .themeCustomize)
        case .customColorPersonalization:
            // 从魔法任务详情页开始，先引导返回「我」，再进入主题配色里的客制化与个性化路径
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .customColorPersonalization)
        case .localFileBackupRestore:
            // 从魔法任务详情页开始：先返回「我」并进入系统与更多，再依次讲解备份/恢复，最后引导首次备份
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .localFileBackupRestore)
        case .exportCSV:
            // 从魔法任务详情页开始，先引导返回「我」，再下滑到系统与更多并点击导出 CSV
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .exportCSV)
        case .cloudFileBackupRestore:
            // 从魔法任务详情页开始，先引导返回「我」，再进入账户与同步完成云端备份体验
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .cloudFileBackupRestore)
        case .widgetCustomize:
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .widgetCustomize)
        case .ootd:
            withAnimation {
                if isUnlocked {
                    selectedTab = 1
                    smallWorldDestination = .menu
                } else {
                    selectedTab = 0
                    homeTabSelection = .wardrobe
                }
            }
            startFeatureGuideAfterNavigation(feature)
        case .ootdDefaultBook:
            if isUnlocked {
                AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .ootdDefaultBook)
            } else {
                withAnimation {
                    selectedTab = 0
                    homeTabSelection = .wardrobe
                }
                startFeatureGuideAfterNavigation(feature)
            }
        case .calendar:
            withAnimation {
                if isUnlocked {
                    selectedTab = 1
                    smallWorldDestination = .menu
                } else {
                    selectedTab = 0
                    homeTabSelection = .wardrobe
                }
            }
            startFeatureGuideAfterNavigation(feature)
        case .wealth:
            // 不自动跳转到萌宠对话，按引导第一步由用户手动点击 House 页签
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .wealth)
        case .batchImport:
            withAnimation {
                selectedTab = 0
                homeTabSelection = .wardrobe
            }
            startFeatureGuideAfterNavigation(feature)
        case .filterClassic:
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .filterClassic)
        case .privacyDisplay:
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .privacyDisplay)
        case .tagBrandFieldDisplay:
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .tagBrandFieldDisplay)
        case .spaceBook:
            if !isUnlocked && !FeatureUnlockManager.shared.isUnlocked(.ootd) &&
                FeatureUnlockManager.shared.checkUnlockCondition(.ootd).met {
                NotificationCenter.default.post(name: .navigateToMagicTasks, object: nil)
                startFeatureGuideAfterNavigation(feature, delay: 0.75)
                return
            }

            if isUnlocked {
                // 空间手账引导要求先从「平面」切到「空间」，这里确保步骤2稳定可见
                UserDefaults.standard.set("平面", forKey: "bookShelfViewMode")
            }
            withAnimation {
                selectedTab = 0
                homeTabSelection = .wardrobe
            }
            startFeatureGuideAfterNavigation(feature)
        case .batchEdit:
            // 批量编辑从衣橱列表进入，先回到衣橱页
            withAnimation {
                selectedTab = 0
                homeTabSelection = .wardrobe
            }
            startFeatureGuideAfterNavigation(feature)
        case .aiAnalysis:
            // 萌宠智能对话引导：从当前页面开始，引导用户返回到「我」界面
            // 引导流程由 FirstUseGuideOverlay 中的 aiAnalysisGuideContent 处理
            // 直接启动首次使用引导
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: .aiAnalysis)
        default:
            // 兜底：只要在体验引导列表里，就启动引导
            if FeatureUnlockManager.experienceGuidedFeatures.contains(feature) {
                startFeatureGuideAfterNavigation(feature)
            }
        }
    }

    private func startFeatureGuideAfterNavigation(_ feature: FeatureItem, delay: TimeInterval = 0.45) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            AppFirstLaunchGuideManager.shared.startFeatureExperienceGuide(for: feature)
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
                    // 返回心愿尾款
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
    
    // 监听当前是否选中了书（书页列表模式下隐藏全局导航返回按钮）
    @State private var isBookSelected: Bool = false
    
    // 监听当前是否选中了空间书（空间书页列表模式下隐藏全局导航返回按钮）
    @State private var isSpaceBookSelected: Bool = false
    
    var body: some View {
        OOTDView(hideBackButton: true, isBookSelected: $isBookSelected, isSpaceBookSelected: $isSpaceBookSelected)
            .toolbar {
                // 只在书架列表模式下显示全局导航返回按钮
                // 选中书时（平面或空间书页列表），使用自定义的返回按钮
                if !isBookSelected && !isSpaceBookSelected {
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
}

// MARK: - OOTDDefaultBookView 带返回按钮
@available(iOS 18.0, *)
struct OOTDDefaultBookViewWithBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        OOTDDefaultBookView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MagicStickerBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        destination: $destination
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToBook)) { _ in
                // 导航到 OOTD 手帐列表
                withAnimation {
                    destination = .ootd
                }
            }
    }
}

// MARK: - 魔法贴纸返回按钮（带菜单）
@available(iOS 18.0, *)
struct MagicStickerBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BookGroup> { $0.deletedAt == nil && $0.title != "默认手帐" }, sort: \BookGroup.sortIndex) private var otherBooks: [BookGroup]

    @ObservedObject private var tabNavigationManager = TabNavigationManager.shared
    @State private var showingMoveOptions = false
    @State private var showingBookPicker = false

    var body: some View {
        Button {
            showingMoveOptions = true
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
        .confirmationDialog("书页管理", isPresented: $showingMoveOptions, titleVisibility: .visible) {
            Button("保持在默认手帐") {
                // 直接返回，不做任何操作
                goBack()
            }

            if !otherBooks.isEmpty {
                Button("加入其他手帐") {
                    showingBookPicker = true
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("当前书页在'默认手帐'中，您可以选择保持现状或移动到其他手帐")
        }
        .sheet(isPresented: $showingBookPicker) {
            BookPickerSheet(
                books: otherBooks,
                onSelect: { selectedBook in
                    moveCurrentPage(to: selectedBook)
                },
                onCancel: {
                    showingBookPicker = false
                }
            )
        }
    }

    private func goBack() {
        withAnimation {
            switch tabNavigationManager.currentSmallWorldSource {
            case .wardrobe:
                homeTab = .wardrobe
                selectedTab = 0
            case .depositPlan:
                homeTab = .depositPlan
                selectedTab = 0
            case .smallWorld:
                destination = .menu
            }
        }
    }

    private func moveCurrentPage(to book: BookGroup) {
        // 获取当前默认手帐
        let bookDescriptor = FetchDescriptor<BookGroup>(
            predicate: #Predicate<BookGroup> { $0.title == "默认手帐" && $0.deletedAt == nil }
        )
        guard let defaultBook = try? modelContext.fetch(bookDescriptor).first else { return }

        // 获取默认手帐的第一页 - 使用bookID避免在Predicate中捕获外部变量
        let defaultBookID = defaultBook.id
        let outfitDescriptor = FetchDescriptor<Outfit>(
            predicate: #Predicate<Outfit> { outfit in
                outfit.isDeleted == false
            },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        let allOutfits = (try? modelContext.fetch(outfitDescriptor)) ?? []
        guard let firstOutfit = allOutfits.first(where: { $0.book?.id == defaultBookID }) else { return }

        // 移动书页到选中的手帐
        firstOutfit.book = book
        firstOutfit.lastModified = Date()

        // 重新计算sortIndex - 使用bookID避免在Predicate中捕获外部变量
        let targetBookID = book.id
        let existingPages = allOutfits.filter { $0.book?.id == targetBookID && $0.isDeleted == false }
            .sorted { $0.sortIndex > $1.sortIndex }
        firstOutfit.sortIndex = (existingPages.first?.sortIndex ?? 0) + 1

        try? modelContext.save()

        showingBookPicker = false

        // 发送通知让 OOTDDefaultBookView 显示 Toast 并导航
        NotificationCenter.default.post(
            name: .magicStickerPageMoved,
            object: nil,
            userInfo: ["bookTitle": book.title, "bookID": book.id]
        )
    }
}

// MARK: - 手帐选择Sheet
@available(iOS 18.0, *)
struct BookPickerSheet: View {
    let books: [BookGroup]
    let onSelect: (BookGroup) -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            List(books) { book in
                Button {
                    onSelect(book)
                } label: {
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.pink)
                        Text(book.title)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("选择目标手帐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        onCancel()
                    }
                }
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
    var initialTab: WealthMainTab? = nil

    var body: some View {
        WealthView(initialTab: initialTab)
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
        // 使用toolbar添加返回按钮，与其他视图保持一致
        DreamDressCalendarView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SmallWorldBackButton(
                        selectedTab: $selectedTab,
                        homeTab: $homeTab,
                        onBackToMenu: { destination = .menu }
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
        // 使用整合版 DressStockMarketView（包含价格概览、K线图、市场统计、AI解析等）
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
