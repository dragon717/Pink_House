import SwiftUI
import SwiftData
import Combine

// MARK: - 环境变量 Key

private struct IsWealthStorageActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isWealthStorageActive: Bool {
        get { self[IsWealthStorageActiveKey.self] }
        set { self[IsWealthStorageActiveKey.self] = newValue }
    }
}

// MARK: - 马上来财主页面

struct WealthView: View {
    @State private var viewModel = WealthViewModel()
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    // 初始页签（从外部传入）
    var initialTab: WealthMainTab? = nil

    // 主页面签选择
    @State private var selectedMainTab: WealthMainTab = .divination
    
    // 用于控制物理模拟的激活状态
    private var isWealthStorageActive: Bool {
        selectedMainTab == .wealthStorage
    }
    
    // 用于监听媒体状态通知
    @State private var cancellables = Set<AnyCancellable>()
    
    // Money Counting State
    struct MoneyCountingState: Identifiable {
        let id = UUID()
        let amount: Decimal
        let denomination: Denomination
    }
    
    @State private var moneyCountingState: MoneyCountingState?
    
    private var calculatedTotalAmount: Decimal {
        WealthViewModel.calculateBaseAmountCNY(
            clothings: allClothings
        )
    }

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .wealth)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 内容区域
                    TabView(selection: $selectedMainTab) {
                        // 请签
                        DivinationView()
                            .tag(WealthMainTab.divination)
                        
                        // 数钱
                        MoneyCountingContainerView(
                            viewModel: viewModel,
                            moneyCountingState: $moneyCountingState
                        )
                        .tag(WealthMainTab.moneyCounting)
                        
                        // 安财 - 只在选中时创建，避免物理模拟提前启动
                        Group {
                            if selectedMainTab == .wealthStorage {
                                WealthStorageContainerView(
                                    viewModel: viewModel
                                )
                            } else {
                                Color.clear
                            }
                        }
                        .tag(WealthMainTab.wealthStorage)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .environment(\.isWealthStorageActive, isWealthStorageActive)
                    .onChange(of: selectedMainTab) { oldValue, newValue in
                        // 当从安财页签切换到其他页签时，停止音效和震动
                        if oldValue == .wealthStorage && newValue != .wealthStorage {
                            soundManager.stopAllSounds()
                            hapticManager.stopHaptics()
                        }
                        
                        NotificationCenter.default.post(
                            name: .wealthMainTabChanged,
                            object: nil,
                            userInfo: ["tab": newValue.rawValue]
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(magicPalette.navigationBackground, for: .navigationBar)
            .toolbarColorScheme(magicPalette.navigationBackground.isDark ? .dark : .light, for: .navigationBar)
            .tint(magicPalette.accent)
            .toolbar {
                leadingToolbarContent
                centerToolbarContent
                trailingToolbarContent
            }
            .fullScreenCover(item: $moneyCountingState) { state in
                MoneyCountingView(
                    amount: state.amount,
                    denomination: state.denomination,
                    currency: viewModel.selectedCurrency,
                    onComplete: {
                        moneyCountingState = nil
                    },
                    onSkip: {
                        moneyCountingState = nil
                    }
                )
            }
            .onAppear {
                handleOnAppear()

                // 如果有指定初始页签，切换到该页签
                if let initialTab = initialTab {
                    selectedMainTab = initialTab
                }
                
                NotificationCenter.default.post(name: .wealthViewOpened, object: nil)
                NotificationCenter.default.post(
                    name: .wealthMainTabChanged,
                    object: nil,
                    userInfo: ["tab": selectedMainTab.rawValue]
                )

                // 通知媒体状态管理器切换到财富页面
                print("💰 WealthView.onAppear: 准备切换到财富页面")
                mediaStateManager.switchToPage(.wealth)
                print("💰 WealthView.onAppear: 已切换到财富页面")
                
                // 监听媒体停止通知（当切换到其他页面时）
                NotificationCenter.default.publisher(for: .wealthMediaShouldStop)
                    .sink { [weak soundManager, weak hapticManager] _ in
                        soundManager?.stopAllSounds()
                        hapticManager?.stopHaptics()
                    }
                    .store(in: &cancellables)
                
                // 监听媒体启动通知（当切换回财富页面时）
                NotificationCenter.default.publisher(for: .wealthMediaShouldStart)
                    .sink { [weak soundManager] _ in
                        soundManager?.isSoundEnabled = true
                        // 注意：财富页面的震动由具体交互（如金豆碰撞）触发，这里不需要自动启动
                    }
                    .store(in: &cancellables)
            }
            .onDisappear {
                lockOrientation(isLocked: false)
                stopEffects()
                
                // 清理通知监听
                cancellables.removeAll()
                
                // 如果当前页面是财富页面，切换到其他页面
                print("💰 WealthView.onDisappear: 准备切换到其他页面")
                if mediaStateManager.currentPage == .wealth {
                    mediaStateManager.switchToPage(.other)
                }
                print("💰 WealthView.onDisappear: 已切换到其他页面")
            }
            .onChange(of: viewModel.selectedCurrency) { _, newValue in
                handleCurrencyChange(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .wealthGuideSwitchMainTab)) { notification in
                if let tabRaw = notification.userInfo?["tab"] as? String,
                   let tab = WealthMainTab(rawValue: tabRaw) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMainTab = tab
                    }
                }
            }
            .onChange(of: allClothings) { _, _ in
                updateAmount()
            }
        }
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var leadingToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Text(WealthExperienceCopy.pageTitle)
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)
                Text(WealthExperienceCopy.pageSubtitle)
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
            } label: {
                Text("🐎")
                    .font(.caption)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var centerToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("功能".appLocalized, selection: $selectedMainTab) {
                ForEach(WealthMainTab.allCases) { tab in
                    Text(tab.localizedTitle).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .captureGuideTarget(.wealthMainTabSegment)
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        if selectedMainTab == .wealthStorage {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        soundManager.isSoundEnabled.toggle()
                    } label: {
                        Image(systemName: soundManager.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.caption)
                            .foregroundStyle(soundManager.isSoundEnabled ? magicPalette.accent : magicPalette.tertiaryText)
                    }
                    
                    Button {
                        hapticManager.isHapticsEnabled.toggle()
                    } label: {
                        Image(systemName: hapticManager.isHapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                            .font(.caption)
                            .foregroundStyle(hapticManager.isHapticsEnabled ? magicPalette.cardAccent : magicPalette.tertiaryText)
                    }
                }
            }
        }
        
        ToolbarItem(placement: .keyboard) {
            Button("完成".appLocalized) {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    private func handleOnAppear() {
        updateAmount()
        Task {
            await viewModel.fetchExchangeRate()
        }
    }
    
    private func handleCurrencyChange(_ newCurrency: CurrencyType) {
        if newCurrency == .gold || newCurrency == .silver {
            lockOrientation(isLocked: true)
        } else {
            lockOrientation(isLocked: false)
            stopEffects()
        }
    }
    
    private func stopEffects() {
        soundManager.stopAllSounds()
        hapticManager.stopHaptics()
    }
    
    private func updateAmount() {
        let total = calculatedTotalAmount
        print("💰 updateAmount: allClothings.count=\(allClothings.count), total=\(total)")
        viewModel.baseAmountCNY = total
    }
    
    private func lockOrientation(isLocked: Bool) {
        if isLocked {
            AppDelegate.orientationLock = .portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        } else {
            AppDelegate.orientationLock = .all
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

// MARK: - 主页面签枚举

enum WealthMainTab: String, CaseIterable, Identifiable {
    case divination = "请签"
    case moneyCounting = "数钱"
    case wealthStorage = "安财"
    
    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .divination:
            "请签".appLocalized
        case .moneyCounting:
            "数钱".appLocalized
        case .wealthStorage:
            "安财".appLocalized
        }
    }
}

// MARK: - 安财容器视图

struct WealthStorageContainerView: View {
    @Bindable var viewModel: WealthViewModel
    @State private var selectedStorageTab: StorageTab = .gold
    
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // 子页签选择器
                Picker("贵金属".appLocalized, selection: $selectedStorageTab) {
                    ForEach(StorageTab.allCases) { tab in
                        Text(tab.localizedTitle).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // 内容区域
                TabView(selection: $selectedStorageTab) {
                    // 黄金
                    GoldStorageView(viewModel: viewModel, isActive: selectedStorageTab == .gold)
                        .tag(StorageTab.gold)
                    
                    // 白银
                    SilverStorageView(viewModel: viewModel, isActive: selectedStorageTab == .silver)
                        .tag(StorageTab.silver)
                    
                    // 虚拟币
                    VirtualCurrencyView(viewModel: viewModel, isActive: selectedStorageTab == .virtual)
                        .tag(StorageTab.virtual)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .padding(.bottom, legacyCustomTabBarAvoidanceInset(safeAreaBottom: proxy.safeAreaInsets.bottom))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: selectedStorageTab) { _, newValue in
            switch newValue {
            case .gold:
                viewModel.selectedCurrency = .gold
            case .silver:
                viewModel.selectedCurrency = .silver
            case .virtual:
                // 虚拟币不需要设置货币类型
                break
            }
        }
    }
    
    private func legacyCustomTabBarAvoidanceInset(safeAreaBottom: CGFloat) -> CGFloat {
        if #available(iOS 26.0, *) {
            return 0
        }
        
        let customTabBarHeight: CGFloat = 56
        let customTabBarBottomOffset: CGFloat = safeAreaBottom > 0 ? 2 : 4
        let overlapWithSafeArea = max(0, customTabBarHeight + customTabBarBottomOffset - safeAreaBottom)
        
        return overlapWithSafeArea + 8
    }
}

// MARK: - 安财页签枚举

enum StorageTab: String, CaseIterable, Identifiable {
    case gold = "黄金"
    case silver = "白银"
    case virtual = "虚拟"
    
    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .gold:
            "黄金".appLocalized
        case .silver:
            "白银".appLocalized
        case .virtual:
            "虚拟".appLocalized
        }
    }
}

#Preview {
    WealthView()
}
