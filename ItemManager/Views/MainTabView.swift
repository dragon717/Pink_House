//
//  MainTabView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

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
    @Binding var homeTabSelection: HomeTab
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    
    @State private var searchText = ""
    // 修复：添加 selectedTab 状态来跟踪当前选中的 Tab，用于 SmallWorldMenuOverlay
    @State private var selectedTab: Int = 1
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("衣橱", systemImage: "cabinet.fill", value: 0) {
                WardrobeTabContent(homeTabSelection: $homeTabSelection)
            }
            
            Tab("小世界", systemImage: "map", value: 1) {
                SmallWorldTabContent(
                    homeTab: $homeTabSelection,
                    destination: $smallWorldDestination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            }
            
            Tab("我的", systemImage: "face.smiling", value: 2) {
                MeTabContent()
            }
            
            Tab(value: 3, role: .search) {
                SearchContainerView(searchText: $searchText)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        // iOS 26+ 原生 API：向下滑动时自动最小化 TabBar
        .applyTabBarMinimizeBehavior()
        .applySearchToolbarBehavior()
        .environment(\.isSimulationActive, isSimulationActive)
        .overlay {
            RewardBubbleView()
            PetOverlayView(action: {
                smallWorldDestination = .pet
            }, petName: petDataManager.status.displayName)
            // 修复：使用正确的 Binding 传递 selectedTab
            SmallWorldMenuOverlay(
                selectedTab: $selectedTab,
                smallWorldDestination: $smallWorldDestination
            )
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

// MARK: - 小世界 Tab 内容
@available(iOS 18.0, *)
struct SmallWorldTabContent: View {
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    var body: some View {
        NavigationStack {
            SmallWorldContainerView(
                selectedTab: .constant(1),
                homeTab: $homeTab,
                destination: $destination,
                isPlayingOpeningAnimation: $isPlayingOpeningAnimation
            )
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - 我的 Tab 内容
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
            List {
                if searchText.isEmpty {
                    Section("搜索建议") {
                        Label("搜索衣物名称", systemImage: "tshirt")
                        Label("搜索品牌", systemImage: "tag")
                        Label("搜索标签", systemImage: "number")
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
            .navigationTitle("搜索")
        }
    }
    
    @ViewBuilder
    private func clothingThumbnail(_ clothing: Clothing) -> some View {
        if let firstImagePath = clothing.imagePaths.first,
           let image = loadImage(from: firstImagePath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
    
    private func loadImage(from path: String) -> UIImage? {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let imagePath = documentsPath.appendingPathComponent(path)
        guard let imageData = try? Data(contentsOf: imagePath) else {
            return nil
        }
        return UIImage(data: imageData)
    }
}

// MARK: - 小世界容器视图
@available(iOS 18.0, *)
struct SmallWorldContainerView: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    
    var body: some View {
        Group {
            switch destination {
            case .menu:
                SmallWorldView(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            case .ootd:
                OOTDView()
            case .pet:
                PetHomeView()
            case .wealth:
                WealthView()
            case .calendar:
                DreamDressCalendarView()
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
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                ModernTabView(
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
            } else {
                LegacyTabView(
                    selectedTab: $selectedTab,
                    homeTabSelection: $homeTabSelection,
                    smallWorldDestination: $smallWorldDestination,
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                )
            }
        }
    }
}

// MARK: - 传统 TabView
struct LegacyTabView: View {
    @Binding var selectedTab: Int
    @Binding var homeTabSelection: HomeTab
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    
    var body: some View {
        ZStack {
            TabView(selection: tabSelectionBinding) {
                HomeView(selectedTab: $homeTabSelection)
                    .tabItem {
                        Image(systemName: selectedTab == 0 ? "cabinet" : "cabinet.fill")
                            .renderingMode(.original)
                        Text("衣橱")
                    }
                    .tag(0)
                
                Group {
                    switch smallWorldDestination {
                    case .menu:
                        SmallWorldView(
                            selectedTab: $selectedTab,
                            homeTab: $homeTabSelection,
                            destination: $smallWorldDestination,
                            isPlayingOpeningAnimation: $isPlayingOpeningAnimation
                        )
                    case .ootd:
                        OOTDView()
                    case .pet:
                        PetHomeView()
                    case .wealth:
                        WealthView()
                    case .calendar:
                        DreamDressCalendarView()
                    }
                }
                .tabItem {
                    switch smallWorldDestination {
                    case .menu:
                        Label("小世界", systemImage: "map")
                    case .ootd:
                        Label("穿搭手帐", systemImage: "tshirt")
                    case .pet:
                        Label(petDataManager.status.displayName, systemImage: "pawprint")
                    case .wealth:
                        Label("马上来财", systemImage: "yensign.circle")
                    case .calendar:
                        Label("梦裙日历", systemImage: "calendar")
                    }
                }
                .tag(1)

                MeView()
                    .tabItem {
                        Label("我的", systemImage: "face.smiling")
                    }
                    .tag(2)
                
                SearchLegacyView()
                    .tabItem {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    .tag(3)
            }
            .environment(\.isSimulationActive, isSimulationActive)
            
            RewardBubbleView()
            PetOverlayView(action: {
                selectedTab = 1
                smallWorldDestination = .pet
            }, petName: petDataManager.status.displayName)
            SmallWorldMenuOverlay(selectedTab: $selectedTab, smallWorldDestination: $smallWorldDestination)
            
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
    }
    
    private var tabSelectionBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab && newValue == 1 {
                    if smallWorldDestination != .menu {
                        smallWorldDestination = .menu
                    }
                }
                selectedTab = newValue
                handleTabChange(newTab: newValue)
            }
        )
    }
    
    private func handleTabChange(newTab: Int) {
        switch newTab {
        case 0:
            mediaStateManager.switchToPage(.wardrobe)
        case 1:
            switch smallWorldDestination {
            case .pet:
                mediaStateManager.switchToPage(.pet)
            case .wealth:
                mediaStateManager.switchToPage(.wealth)
            default:
                mediaStateManager.switchToPage(.other)
            }
        default:
            mediaStateManager.switchToPage(.other)
        }
    }
    
    private var isSimulationActive: Bool {
        return selectedTab == 1 && smallWorldDestination == .wealth
    }
}

// MARK: - iOS 17 搜索视图
struct SearchLegacyView: View {
    @State private var searchText = ""
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
            List {
                if searchText.isEmpty {
                    Section("搜索建议") {
                        Label("搜索衣物名称", systemImage: "tshirt")
                        Label("搜索品牌", systemImage: "tag")
                        Label("搜索标签", systemImage: "number")
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
            .navigationTitle("搜索")
            .searchable(text: $searchText, prompt: "搜索衣物、品牌、标签...")
        }
    }
    
    @ViewBuilder
    private func clothingThumbnail(_ clothing: Clothing) -> some View {
        if let firstImagePath = clothing.imagePaths.first,
           let image = loadImage(from: firstImagePath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
    
    private func loadImage(from path: String) -> UIImage? {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let imagePath = documentsPath.appendingPathComponent(path)
        guard let imageData = try? Data(contentsOf: imagePath) else {
            return nil
        }
        return UIImage(data: imageData)
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

#Preview {
    MainTabView()
}
