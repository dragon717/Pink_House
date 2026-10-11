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

private struct IsRouteTransitionCoolingDownKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct IsRoutePageActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isSimulationActive: Bool {
        get { self[IsSimulationActiveKey.self] }
        set { self[IsSimulationActiveKey.self] = newValue }
    }

    var isRouteTransitionCoolingDown: Bool {
        get { self[IsRouteTransitionCoolingDownKey.self] }
        set { self[IsRouteTransitionCoolingDownKey.self] = newValue }
    }

    var isRoutePageActive: Bool {
        get { self[IsRoutePageActiveKey.self] }
        set { self[IsRoutePageActiveKey.self] = newValue }
    }


}

private func performWithoutRouteContentAnimation(_ updates: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        updates()
    }
}

// MARK: - 主 Tab 视图
// 系统 TabView 负责导航栏外观与安全区。
struct NativeTabNavigation: View {
    @Binding var selectedTab: Int
    @Binding var homeTabSelection: HomeTab
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @ObservedObject private var petDataManager = PetDataManager.shared
    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @StateObject private var bottomDockSettingsManager = BottomDockSettingsManager.shared
    @StateObject private var floatingPetVisibilityManager = FloatingPetVisibilityManager.shared
    @StateObject private var guideManager = AppFirstLaunchGuideManager.shared

    // 搜索文本状态
    @State private var searchText = ""
    @State private var selectedFeatureID: AppFeatureID = .wardrobe
    @State private var petChatReturnTab = 0
    @State private var isRouteTransitionCoolingDown = false
    @State private var routeTransitionGeneration = 0

    var body: some View {
        Group {
            if #available(iOS 18, *) {
                TabView(selection: nativeSelection) {
                    ForEach(navigationFeatures) { feature in
                        Tab(value: feature.id) {
                            tabContent(for: feature)
                        } label: {
                            Label(tabTitle(for: feature), systemImage: tabIcon(for: feature))
                        }
                    }
                }
                .tabViewStyle(.tabBarOnly)
            } else {
                // 最低部署版本为 iOS 17.4；旧系统同样使用原生 TabView。
                TabView(selection: nativeSelection) {
                    ForEach(navigationFeatures) { feature in
                        tabContent(for: feature)
                            .tabItem {
                                Label(tabTitle(for: feature), systemImage: tabIcon(for: feature))
                            }
                            .tag(feature.id)
                    }
                }
            }
        }
        .tint(.accentColor)
        .overlay {
            // The floating pet is a root companionship layer; task, guide, and modal
            // flows report blockers through FloatingPetVisibilityManager.
            if effectiveFloatingPetHiddenReasons.isEmpty && !isRouteTransitionCoolingDown {
                PetOverlayView(action: {
                    // 点击悬浮小猫：切换到萌宠对话 Tab 并自动展开搜索栏
                    switchRouteWithoutContentAnimation {
                        selectedTab = 3
                    }
                },
                petName: petDataManager.status.displayName)
            }
        }
        .onReceive(tabNavigationManager.$navigateToTab) { tab in
            if let tab = tab {
                switchRouteWithoutContentAnimation {
                    if tab == 1 && selectedTab != 1 {
                        tabNavigationManager.recordEnteringSmallWorldFromHomeTab(homeTabSelection)
                    }
                    selectedTab = tab
                }
                tabNavigationManager.navigateToTab = nil
            }
        }
        .onReceive(tabNavigationManager.$navigateToHomeTab) { homeTab in
            if let homeTab = homeTab {
                switchRouteWithoutContentAnimation {
                    homeTabSelection = homeTab
                }
                tabNavigationManager.navigateToHomeTab = nil
            }
        }
        .onReceive(tabNavigationManager.$navigateToSmallWorld) { destination in
            if let destination = destination {
                switchRouteWithoutContentAnimation {
                    if !tabNavigationManager.isNavigatingInsideSmallWorld {
                        tabNavigationManager.recordEnteringSmallWorldFromHomeTab(homeTabSelection)
                    }
                    smallWorldDestination = destination
                }
                tabNavigationManager.navigateToSmallWorld = nil
            }
        }
        .onAppear {
            synchronizeNativeSelection()
        }
        .onChange(of: selectedTab) { _, newTab in
            synchronizeNativeSelection()
            if newTab != 3 {
                petChatReturnTab = newTab
            }
            beginRouteTransitionQuietPeriod()

            // 发送Tab切换通知，用于新手引导
            let tabName: String
            switch newTab {
            case 0: tabName = "wardrobe"
            case 1: tabName = "smallWorld"
            case 2: tabName = "me"
            case 3: tabName = "petChat"
            case 4: tabName = "timeHall"
            default: tabName = "unknown"
            }
            NotificationCenter.default.post(
                name: .homeTabChanged,
                object: nil,
                userInfo: ["tab": tabName]
            )
        }
        .onChange(of: homeTabSelection) { _, _ in
            synchronizeNativeSelection()
            beginRouteTransitionQuietPeriod()
        }
        .onChange(of: smallWorldDestination) { _, _ in
            synchronizeNativeSelection()
            beginRouteTransitionQuietPeriod()
        }
        .onChange(of: bottomDockSettingsManager.selectedFeatureIDs) { _, _ in
            synchronizeNativeSelection()
        }
        .task(id: routeTransitionGeneration) {
            guard isRouteTransitionCoolingDown else { return }
            let generation = routeTransitionGeneration
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                guard generation == routeTransitionGeneration else { return }
                isRouteTransitionCoolingDown = false
            } catch {
                // 新路由或离开视图会取消本轮冷却，由下一轮任务继续管理。
            }
        }
    }

    private var navigationFeatures: [AppFeatureDescriptor] {
        bottomDockSettingsManager.slots.map { bottomDockSettingsManager.feature(at: $0) }
    }

    private var nativeSelection: Binding<AppFeatureID> {
        Binding(get: { selectedFeatureID }, set: { id in
            guard let feature = navigationFeatures.first(where: { $0.id == id }),
                  feature.isUnlocked else { return }
            selectedFeatureID = id
            activateBottomDockFeature(feature)
        })
    }

    private func synchronizeNativeSelection() {
        if let feature = navigationFeatures.first(where: { isFeatureActive($0) }) {
            selectedFeatureID = feature.id
        } else if !navigationFeatures.contains(where: { $0.id == selectedFeatureID }),
                  let first = navigationFeatures.first {
            selectedFeatureID = first.id
        }
    }

    private func tabContent(for feature: AppFeatureDescriptor) -> some View {
        NativeTabPage(
            feature: feature,
            isActive: selectedFeatureID == feature.id,
            isCoolingDown: isRouteTransitionCoolingDown,
            selectedTab: $selectedTab,
            homeTabSelection: $homeTabSelection,
            smallWorldDestination: $smallWorldDestination,
            isPlayingOpeningAnimation: $isPlayingOpeningAnimation,
            searchText: $searchText,
            hidePetChat: hidePetChat)
    }

    private func beginRouteTransitionQuietPeriod() {
        _ = PerformanceSignpost.event(
            .routeTransition,
            label: "tab=\(selectedTab)",
            detail: "home=\(homeTabSelection) destination=\(smallWorldDestination)"
        )

        if !isRouteTransitionCoolingDown {
            isRouteTransitionCoolingDown = true
        }

        routeTransitionGeneration += 1
    }

    private var isHouseRouteActive: Bool {
        selectedTab == 1
    }

    private var isPetChatRouteActive: Bool {
        selectedTab == 3
    }

    private var effectiveFloatingPetHiddenReasons: Set<FloatingPetHiddenReason> {
        floatingPetVisibilityManager.hiddenReasons.union(localFloatingPetHiddenReasons)
    }

    private var localFloatingPetHiddenReasons: Set<FloatingPetHiddenReason> {
        var reasons = Set<FloatingPetHiddenReason>()

        if petDataManager.status.ownedPetIds.isEmpty {
            reasons.insert(.noOwnedPet)
        }

        if isHouseRouteActive {
            reasons.insert(.houseRoute)
        }

        if isPetChatRouteActive {
            reasons.insert(.petChatRoute)
        }

        if isRouteTransitionCoolingDown {
            reasons.insert(.routeTransition)
        }

        if guideManager.isShowingGuide ||
            guideManager.isShowingFeatureExperienceGuide ||
            guideManager.isRunningAnimation ||
            guideManager.showPointingVideo {
            reasons.insert(.guideActive)
        }

        return reasons
    }

    private func tabTitle(for feature: AppFeatureDescriptor) -> String {
        if feature.id == .house && shouldUseDynamicHouseLabel {
            return smallWorldTabTitle
        }
        return feature.localizedTitle
    }

    private func tabIcon(for feature: AppFeatureDescriptor) -> String {
        if feature.id == .house && shouldUseDynamicHouseLabel {
            return smallWorldTabIcon
        }
        return feature.systemImage
    }

    private var shouldUseDynamicHouseLabel: Bool {
        selectedTab == 1 && !hasActiveSpecificSmallWorldFeature
    }

    private var hasActiveSpecificSmallWorldFeature: Bool {
        bottomDockSettingsManager.selectedFeatureIDs.contains { featureID in
            featureID != .house && routeMatches(AppFeatureRegistry.descriptor(for: featureID))
        }
    }

    private func isFeatureActive(_ feature: AppFeatureDescriptor) -> Bool {
        if feature.id == .house {
            guard selectedTab == 1 else { return false }
            return !hasActiveSpecificSmallWorldFeature
        }
        return routeMatches(feature)
    }

    private func routeMatches(_ feature: AppFeatureDescriptor) -> Bool {
        switch feature.route {
        case .tab(let tabIndex):
            return selectedTab == tabIndex
        case .wardrobe(let homeTab):
            return selectedTab == 0 && homeTabSelection == homeTab
        case .smallWorld(let destination):
            return selectedTab == 1 && smallWorldDestination == destination
        }
    }

    private func activateBottomDockFeature(_ feature: AppFeatureDescriptor) {
        guard feature.isUnlocked else { return }

        switchRouteWithoutContentAnimation {
            switch feature.route {
            case .tab(let tabIndex):
                selectedTab = tabIndex
            case .wardrobe(let homeTab):
                homeTabSelection = homeTab
                selectedTab = 0
            case .smallWorld(let destination):
                if selectedTab == 1 {
                    tabNavigationManager.markNavigatingInsideSmallWorld()
                } else {
                    tabNavigationManager.recordEnteringSmallWorldFromHomeTab(homeTabSelection)
                }
                smallWorldDestination = destination
                selectedTab = 1
            }
        }
    }

    private func switchRouteWithoutContentAnimation(_ updates: () -> Void) {
        beginRouteTransitionQuietPeriod()
        performWithoutRouteContentAnimation(updates)
    }

    private func hidePetChat() {
        switchRouteWithoutContentAnimation {
            selectedTab = petChatReturnTab
        }
    }

    private var smallWorldTabTitle: String {
        switch smallWorldDestination {
        case .calendar: return "梦裙日历".appLocalized
        case .wealth(_): return "来财".appLocalized
        case .pet: return petDataManager.status.displayName
        case .ootd: return "穿搭手帐".appLocalized
        case .ootdDefaultBook: return "魔法贴纸".appLocalized
        case .menu: return "House".appLocalized
        case .wardrobe: return "衣橱".appLocalized
        case .depositPlan: return "心愿尾款".appLocalized
        case .recycleBin: return "回收站".appLocalized
        }
    }

    private var smallWorldTabIcon: String {
        switch smallWorldDestination {
        case .calendar: return "calendar"
        case .wealth(_): return "yensign.circle"
        case .pet: return "pawprint"
        case .ootd: return "book.pages"
        case .ootdDefaultBook: return "book.pages"
        case .menu: return "house.fill"
        case .wardrobe: return "cabinet.fill"
        case .depositPlan: return "tag.fill"
        case .recycleBin: return "trash.fill"
        }
    }
}

// 每个 Tab 的内容独立观察页面主题，避免主题刷新重建整个导航容器。
private struct NativeTabPage: View {
    let feature: AppFeatureDescriptor
    let isActive: Bool
    let isCoolingDown: Bool
    @Binding var selectedTab: Int
    @Binding var homeTabSelection: HomeTab
    @Binding var smallWorldDestination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @Binding var searchText: String
    let hidePetChat: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        content
            .tint(themeManager.accentTextColor)
            .environment(\.isRoutePageActive, isActive)
            .environment(\.isSimulationActive, isActive && !isCoolingDown)
            .environment(\.isRouteTransitionCoolingDown, isCoolingDown)
    }

    @ViewBuilder
    private var content: some View {
        switch isActive ? selectedTab : feature.route.tabIndex {
        case 0:
            HomeView(selectedTab: homeSelection(for: feature, isActive: isActive))
        case 1:
            NavigationStack {
                SmallWorldRouteContent(
                    selectedTab: $selectedTab, homeTab: $homeTabSelection,
                    destination: worldSelection(for: feature, isActive: isActive),
                    isPlayingOpeningAnimation: $isPlayingOpeningAnimation)
            }
        case 2:
            NavigationStack { MeView() }
        case 3:
            PetChatViewLegacy(searchText: $searchText, onHide: hidePetChat)
        case 4:
            NavigationStack { TimeHallView() }
        default:
            EmptyView()
        }
    }

    private func homeSelection(for feature: AppFeatureDescriptor, isActive: Bool) -> Binding<HomeTab> {
        if isActive { return $homeTabSelection }
        if case .wardrobe(let homeTab) = feature.route { return .constant(homeTab) }
        return .constant(.wardrobe)
    }

    private func worldSelection(for feature: AppFeatureDescriptor, isActive: Bool) -> Binding<SmallWorldDestination> {
        if isActive { return $smallWorldDestination }
        if case .smallWorld(let destination) = feature.route { return .constant(destination) }
        return .constant(.menu)
    }

}

// MARK: - House 路由内容
struct SmallWorldRouteContent: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    @Binding var destination: SmallWorldDestination
    @Binding var isPlayingOpeningAnimation: Bool
    @Environment(\.isRoutePageActive) private var isRoutePageActive

    var body: some View {
        if isRoutePageActive {
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
            case .wealth(let initialTab):
                WealthViewWithBackButton(
                    selectedTab: $selectedTab,
                    homeTab: $homeTab,
                    destination: $destination,
                    initialTab: initialTab
                )
            case .calendar:
                DreamDressCalendarViewWithBackButton(
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
            case .wardrobe, .depositPlan:
                EmptyView()
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - House 路由返回
struct SmallWorldBackButton: View {
    @Binding var selectedTab: Int
    @Binding var homeTab: HomeTab
    var onBackToMenu: () -> Void
    @ObservedObject private var tabNavigationManager = TabNavigationManager.shared

    var body: some View {
        Button {
            performWithoutRouteContentAnimation {
                switch tabNavigationManager.currentSmallWorldSource {
                case .wardrobe:
                    homeTab = .wardrobe
                    selectedTab = 0
                case .depositPlan:
                    homeTab = .depositPlan
                    selectedTab = 0
                case .smallWorld:
                    if AppFeatureID.house.isShipHidden {
                        homeTab = .wardrobe
                        selectedTab = 0
                    } else {
                        onBackToMenu()
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

struct OOTDViewWithBackButton: View {
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
                        SmallWorldBackButton(
                            selectedTab: $selectedTab,
                            homeTab: $homeTab,
                            onBackToMenu: { destination = .menu }
                        )
                    }
                }
            }
    }
}

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
                performWithoutRouteContentAnimation {
                    destination = .ootd
                }
            }
    }
}

// MARK: - 魔法贴纸返回按钮（带菜单）- iOS 18以下
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
        performWithoutRouteContentAnimation {
            switch tabNavigationManager.currentSmallWorldSource {
            case .wardrobe:
                homeTab = .wardrobe
                selectedTab = 0
            case .depositPlan:
                homeTab = .depositPlan
                selectedTab = 0
            case .smallWorld:
                if AppFeatureID.house.isShipHidden {
                    homeTab = .wardrobe
                    selectedTab = 0
                } else {
                    destination = .menu
                }
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
struct BookPickerSheet: View {
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
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

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
                        onBackToMenu: { destination = .menu }
                    )
                }
            }
    }
}

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
    @StateObject private var noticePopupManager = NoticePopupManager.shared
    @StateObject private var unlockNotificationManager = FeatureUnlockNotificationManager.shared

    var body: some View {
        NativeTabNavigation(
            selectedTab: $selectedTab,
            homeTabSelection: $homeTabSelection,
            smallWorldDestination: $smallWorldDestination,
            isPlayingOpeningAnimation: $isPlayingOpeningAnimation
        )
        .floatingPetHidden(.noticeModal, isActive: noticePopupManager.isShowing)
        .floatingPetHidden(.unlockNotification, isActive: unlockNotificationManager.isShowing)
        .floatingPetHidden(.immersiveMedia, isActive: isPlayingOpeningAnimation)
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
                    performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
                performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
                performWithoutRouteContentAnimation {
                    selectedTab = 0
                    homeTabSelection = .wardrobe
                }
                startFeatureGuideAfterNavigation(feature)
            }
        case .calendar:
            performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
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
            performWithoutRouteContentAnimation {
                selectedTab = 0
                homeTabSelection = .wardrobe
            }
            startFeatureGuideAfterNavigation(feature)
        case .batchEdit:
            // 批量编辑从衣橱列表进入，先回到衣橱页
            performWithoutRouteContentAnimation {
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
