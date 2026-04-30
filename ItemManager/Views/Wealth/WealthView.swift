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
    @Query private var wealthSavingEntries: [WealthSavingEntry]
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    @StateObject private var mediaStateManager = MediaStateManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

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
        let wardrobeTotal = allClothings.reduce(Decimal(0)) { partialResult, clothing in
            guard !clothing.isDeleted && clothing.deletedAt == nil else { return partialResult }
            if clothing.isDepositPlan {
                return partialResult + clothing.totalDeposit + clothing.resolvedShippingFee
            } else {
                return partialResult + clothing.inventoryTotalPrice
            }
        }
        return wardrobeTotal + WealthSavingLedger.activeTotal(in: wealthSavingEntries)
    }

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var wealthSavingChangeToken: String {
        wealthSavingEntries
            .map {
                "\($0.id.uuidString)|\($0.amount)|\($0.updatedAt.timeIntervalSince1970)|\($0.usedAt?.timeIntervalSince1970 ?? 0)|\($0.voidedAt?.timeIntervalSince1970 ?? 0)"
            }
            .joined(separator: "#")
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
                                    viewModel: viewModel,
                                    clothings: allClothings,
                                    wealthSavingEntries: wealthSavingEntries
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
            .onChange(of: wealthSavingChangeToken) { _, _ in
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
            Picker("功能", selection: $selectedMainTab) {
                ForEach(WealthMainTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
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
            Button("完成") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    private func handleOnAppear() {
        WealthSavingLedger.migrateLegacySavedFinalPayments(
            clothings: allClothings,
            entries: wealthSavingEntries,
            context: modelContext
        )
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
}

// MARK: - 安财容器视图

struct WealthStorageContainerView: View {
    @Bindable var viewModel: WealthViewModel
    let clothings: [Clothing]
    let wealthSavingEntries: [WealthSavingEntry]
    
    @State private var selectedStorageTab: StorageTab = .gold
    
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                // 子页签选择器
                Picker("贵金属", selection: $selectedStorageTab) {
                    ForEach(StorageTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
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

                    // 尾款心愿小匣
                    FinalPaymentVaultView(
                        clothings: clothings,
                        wealthSavingEntries: wealthSavingEntries
                    )
                        .tag(StorageTab.finalPayment)
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
            case .finalPayment:
                viewModel.selectedCurrency = .rmb
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
    case finalPayment = "尾款"
    
    var id: String { rawValue }
}

// MARK: - 尾款心愿小匣

struct FinalPaymentVaultView: View {
    let clothings: [Clothing]
    let wealthSavingEntries: [WealthSavingEntry]

    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @State private var appearanceManager = WealthAppearanceManager.shared
    @State private var showingSavingSheet = false
    @State private var showingUnassignedManager = false
    @State private var savingTargetClothingID: UUID?
    @State private var detailTargetClothing: Clothing?
    @State private var celebrationAmount: Decimal?
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var activeDepositClothings: [Clothing] {
        clothings.filter { $0.isDepositPlan && !$0.isDeleted && $0.deletedAt == nil }
    }

    private var activeClothings: [Clothing] {
        clothings.filter { !$0.isDeleted && $0.deletedAt == nil }
    }

    private var clothingsWithSavingsOrDepositPlans: [Clothing] {
        let savedIDs = Set(wealthSavingEntries.compactMap { entry -> UUID? in
            WealthSavingLedger.isActive(entry) ? entry.clothingID : nil
        })
        return activeClothings
            .filter { $0.isDepositPlan || savedIDs.contains($0.id) }
            .sorted {
                let left = WealthSavingLedger.activeTotal(for: $0.id, in: wealthSavingEntries)
                let right = WealthSavingLedger.activeTotal(for: $1.id, in: wealthSavingEntries)
                if left != right { return left > right }
                return $0.updatedAt > $1.updatedAt
            }
    }

    private var savedTotal: Decimal {
        WealthSavingLedger.activeTotal(in: wealthSavingEntries)
    }

    private var unassignedSavedTotal: Decimal {
        WealthSavingLedger.activeUnassignedTotal(in: wealthSavingEntries)
    }

    private var linkedSavedTotal: Decimal {
        savedTotal - unassignedSavedTotal
    }

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var vaultHeroTitle: String {
        let displayName = appearanceManager.finalPaymentVaultMascot.displayName
        if displayName == WealthExperienceCopy.Vault.heroSuffix {
            return displayName
        }
        return "\(displayName) · \(WealthExperienceCopy.Vault.heroSuffix)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                fortuneCatHeader
                    .padding(.top, 18)

                statsCard

                quickSaveCard

                if clothingsWithSavingsOrDepositPlans.isEmpty {
                    emptyState
                } else {
                    savedList
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 120)
        }
        .sheet(isPresented: $showingSavingSheet) {
            VaultSavingSheet(
                targetClothing: savingTargetClothing,
                currentSavedAmount: savingTargetClothing.map {
                    WealthSavingLedger.activeTotal(for: $0.id, in: wealthSavingEntries)
                } ?? unassignedSavedTotal,
                onSave: saveAmount
            )
        }
        .sheet(isPresented: $showingUnassignedManager) {
            UnassignedSavingManagerSheet(
                depositClothings: activeDepositClothings,
                onFillComplete: { amount in
                    if amount > 0 {
                        celebrationAmount = amount
                    }
                }
            )
        }
        .navigationDestination(item: $detailTargetClothing) { clothing in
            ClothingDetailView(clothing: clothing)
        }
        .overlay {
            if let celebrationAmount {
                VaultSavingCelebrationOverlay(
                    amount: celebrationAmount,
                    onComplete: { self.celebrationAmount = nil }
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var savingTargetClothing: Clothing? {
        guard let savingTargetClothingID else { return nil }
        return activeClothings.first { $0.id == savingTargetClothingID }
    }

    private var fortuneCatHeader: some View {
        VStack(spacing: 12) {
            FortuneCatVaultIcon(mascot: appearanceManager.finalPaymentVaultMascot)
                .frame(width: 150, height: 150)
                .shadow(color: Color.orange.opacity(0.25), radius: 16, x: 0, y: 8)

            Text(vaultHeroTitle)
                .font(.title3.weight(.heavy))
                .foregroundStyle(themeManager.primaryTextColor)

            Text(WealthExperienceCopy.Vault.heroDescription)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 28) {
            RoundedRectangle(cornerRadius: 28)
                .fill(WealthExperienceStyle.softPanelGradient)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
        .wealthTeaPartyOrnaments(cornerRadius: 28)
    }

    private var statsCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WealthExperienceStyle.rose)
                Text(NSDecimalNumber(decimal: savedTotal).stringValue)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WealthExperienceStyle.roseGoldGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }

            HStack(spacing: 0) {
                vaultStat(title: WealthExperienceCopy.Vault.savedTitle, value: "¥\(NSDecimalNumber(decimal: savedTotal).stringValue)", color: WealthExperienceStyle.rose)
                Divider().frame(height: 34)
                vaultStat(title: WealthExperienceCopy.Vault.linkedTitle, value: "¥\(NSDecimalNumber(decimal: linkedSavedTotal).stringValue)", color: palette.accent)
                Divider().frame(height: 34)
                unassignedVaultStatButton
            }
        }
        .padding(18)
        .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 24) {
            RoundedRectangle(cornerRadius: 24)
                .fill(WealthExperienceStyle.softPanelGradient)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        .wealthTeaPartyOrnaments(cornerRadius: 24)
    }

    private func vaultStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(themeManager.secondaryTextColor)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var unassignedVaultStatButton: some View {
        Button {
            showingUnassignedManager = true
        } label: {
            VStack(spacing: 6) {
                Text(WealthExperienceCopy.Vault.unassignedTitle)
                    .font(.caption2)
                    .foregroundStyle(themeManager.secondaryTextColor)
                HStack(spacing: 3) {
                    Text("¥\(NSDecimalNumber(decimal: unassignedSavedTotal).stringValue)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: "C94C72"))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(hex: "C94C72").opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WealthExperienceCopy.Vault.manageUnassigned)
    }

    private var quickSaveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(WealthExperienceCopy.Vault.quickSaveTitle)
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text(WealthExperienceCopy.Vault.quickSaveDescription)
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                Spacer()
                Button {
                    savingTargetClothingID = nil
                    showingSavingSheet = true
                } label: {
                    Label(WealthExperienceCopy.Vault.quickSaveAction, systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(WealthExperienceStyle.rose)
                        .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 18, showsDecoration: false) {
                            Capsule().fill(WealthExperienceStyle.blush.opacity(0.45))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 22) {
            RoundedRectangle(cornerRadius: 22)
                .fill(WealthExperienceStyle.softPanelGradient)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
        .wealthTeaPartyOrnaments(cornerRadius: 22)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(WealthExperienceStyle.rose.opacity(0.8))
            Text(WealthExperienceCopy.Vault.emptyTitle)
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
            Text(WealthExperienceCopy.Vault.emptyDescription)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.secondaryTextColor)
            HStack(spacing: 10) {
                Button {
                    savingTargetClothingID = nil
                    showingSavingSheet = true
                } label: {
                    Label("存一笔", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(WealthExperienceStyle.rose)
                        .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 20, showsDecoration: false) {
                            Capsule().fill(WealthExperienceStyle.blush.opacity(0.45))
                        }
                }
                .buttonStyle(.plain)

                Button {
                    tabNavigationManager.navigate(to: .wardrobe(.depositPlan))
                } label: {
                    Label("去心愿尾款", systemImage: "heart.text.square.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(palette.accent)
                        .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 20, showsDecoration: false) {
                            Capsule().fill(palette.accent.opacity(0.14))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .themeSkinSectionCard(slot: .emptyState, cornerRadius: 24)
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(WealthExperienceCopy.Vault.listTitle)
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            ForEach(clothingsWithSavingsOrDepositPlans) { clothing in
                let saved = WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
                let numerator = WealthSavingLedger.progressNumerator(for: clothing, entries: wealthSavingEntries)
                let target = WealthSavingLedger.purchaseTarget(for: clothing)
                let cap = WealthSavingLedger.assignableSavingCap(for: clothing)
                let remaining = WealthSavingLedger.remainingAssignableAmount(for: clothing, entries: wealthSavingEntries)
                let overflow = WealthSavingLedger.overflowAmount(for: clothing, entries: wealthSavingEntries)
                let ratio = WealthSavingLedger.progressRatio(for: clothing, entries: wealthSavingEntries)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            detailTargetClothing = clothing
                        } label: {
                            HStack(spacing: 10) {
                                WealthClothingThumbnailView(
                                    clothing: clothing,
                                    size: CGSize(width: 52, height: 52),
                                    cornerRadius: 14
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(clothing.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(themeManager.primaryTextColor)
                                        .lineLimit(1)
                                    Text(clothing.isDepositPlan ? WealthExperienceCopy.Vault.depositProgressLabel : WealthExperienceCopy.Vault.normalProgressLabel)
                                        .font(.caption2)
                                        .foregroundStyle(themeManager.tertiaryTextColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            savingTargetClothingID = clothing.id
                            showingSavingSheet = true
                        } label: {
                            Label(remaining > 0 ? "存一笔" : "已满", systemImage: remaining > 0 ? "plus" : "checkmark")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .foregroundStyle(WealthExperienceStyle.rose)
                                .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 16, showsDecoration: false) {
                                    Capsule().fill(WealthExperienceStyle.blush.opacity(0.42))
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(remaining <= 0)
                    }

                    Button {
                        detailTargetClothing = clothing
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("已存 ¥\(NSDecimalNumber(decimal: saved).stringValue)")
                                Spacer()
                                Text("\(Int((ratio * 100).rounded()))%")
                                    .foregroundStyle(ratio > 1 ? WealthExperienceStyle.rose : WealthExperienceStyle.gold)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.secondaryTextColor)

                            ProgressView(value: min(ratio, 1.0))
                                .tint(ratio > 1 ? WealthExperienceStyle.rose : WealthExperienceStyle.gold)

                            Text("进度 ¥\(NSDecimalNumber(decimal: numerator).stringValue) / ¥\(NSDecimalNumber(decimal: target).stringValue)")
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                            Text("指定上限 ¥\(NSDecimalNumber(decimal: cap).stringValue) · 还能存 ¥\(NSDecimalNumber(decimal: remaining).stringValue)")
                                .font(.caption2)
                                .foregroundStyle(remaining > 0 ? themeManager.tertiaryTextColor : Color(hex: "C94C72"))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if overflow > 0 {
                        Button {
                            moveOverflowSavingToUnassigned(for: clothing)
                        } label: {
                            Label("转出超额 ¥\(NSDecimalNumber(decimal: overflow).stringValue) 到未指定", systemImage: "arrow.uturn.left.circle.fill")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Color(hex: "C94C72"))
                                .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 14, showsDecoration: false) {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(hex: "C94C72").opacity(0.10))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .themeSkinSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false)
            }
        }
    }

    private func saveAmount(_ amount: Decimal) {
        let target = savingTargetClothing
        do {
            let savedEntry: WealthSavingEntry?
            if let target {
                savedEntry = try WealthSavingLedger.addSaving(
                    amount: amount,
                    for: target,
                    entries: wealthSavingEntries,
                    note: "为「\(target.name)」存钱",
                    context: modelContext
                )
            } else {
                savedEntry = try WealthSavingLedger.addSaving(
                    amount: amount,
                    clothingID: nil,
                    note: "不指定裙装存钱",
                    context: modelContext
                )
            }
            guard let savedEntry else { return }
            Task { await SharedPersistence.shared.syncWidgetData() }
            celebrationAmount = savedEntry.amount
        } catch {
            print("FinalPaymentVaultView: Failed to save wealth saving entry: \(error)")
        }
    }

    private func moveOverflowSavingToUnassigned(for clothing: Clothing) {
        do {
            let movedAmount = try WealthSavingLedger.moveOverflowToUnassigned(
                for: clothing,
                entries: wealthSavingEntries,
                context: modelContext
            )
            if movedAmount > 0 {
                Task { await SharedPersistence.shared.syncWidgetData() }
            }
        } catch {
            print("FinalPaymentVaultView: Failed to move overflow wealth saving: \(error)")
        }
    }
}

struct UnassignedSavingManagerSheet: View {
    let depositClothings: [Clothing]
    let onFillComplete: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query private var wealthSavingEntries: [WealthSavingEntry]
    @State private var statusMessage: String?

    private var unassignedSavedTotal: Decimal {
        WealthSavingLedger.activeUnassignedTotal(in: wealthSavingEntries)
    }

    private var sortedDepositClothings: [Clothing] {
        depositClothings
            .filter { !$0.isDeleted && $0.deletedAt == nil && $0.isDepositPlan }
            .sorted {
                let leftRemaining = WealthSavingLedger.remainingAssignableAmount(for: $0, entries: wealthSavingEntries)
                let rightRemaining = WealthSavingLedger.remainingAssignableAmount(for: $1, entries: wealthSavingEntries)
                if leftRemaining != rightRemaining { return leftRemaining > rightRemaining }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                            Label(WealthExperienceCopy.Vault.manageUnassigned, systemImage: "tray.full.fill")
                            .font(.headline)
                            .foregroundStyle(Color(hex: "C94C72"))
                        Text("\(WealthExperienceCopy.Vault.unassignedSheetDescriptionPrefix)¥\(NSDecimalNumber(decimal: unassignedSavedTotal).stringValue)\(WealthExperienceCopy.Vault.unassignedSheetDescriptionSuffix)")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                    .padding(16)
                    .themeSkinSectionCard(slot: .statsCard, cornerRadius: 22)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .themeSkinAdaptiveSectionCard(slot: .filterChip, cornerRadius: 14, showsDecoration: false) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.orange.opacity(0.10))
                            }
                    }

                    if sortedDepositClothings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "heart.slash")
                                .font(.title2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                            Text(WealthExperienceCopy.Vault.unassignedEmptyTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.primaryTextColor)
                            Text(WealthExperienceCopy.Vault.unassignedEmptyDescription)
                                .font(.caption)
                                .foregroundStyle(themeManager.secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .themeSkinSectionCard(slot: .emptyState, cornerRadius: 22)
                    } else {
                        ForEach(sortedDepositClothings) { clothing in
                            managerRow(for: clothing)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(WealthExperienceCopy.Vault.unassignedSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func managerRow(for clothing: Clothing) -> some View {
        let saved = WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
        let cap = WealthSavingLedger.assignableSavingCap(for: clothing)
        let remaining = WealthSavingLedger.remainingAssignableAmount(for: clothing, entries: wealthSavingEntries)
        let fillAmount = min(unassignedSavedTotal, remaining)
        let overflow = WealthSavingLedger.overflowAmount(for: clothing, entries: wealthSavingEntries)
        let progress = cap > 0 ? NSDecimalNumber(decimal: min(saved, cap) / cap).doubleValue : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                WealthClothingThumbnailView(
                    clothing: clothing,
                    size: CGSize(width: 52, height: 52),
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(clothing.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                        .lineLimit(1)
                    Text("已存 ¥\(NSDecimalNumber(decimal: saved).stringValue) / 上限 ¥\(NSDecimalNumber(decimal: cap).stringValue)")
                        .font(.caption2)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
            }

            ProgressView(value: progress)
                .tint(overflow > 0 ? Color(hex: "C94C72") : .orange)

            HStack {
                Text("还能填充 ¥\(NSDecimalNumber(decimal: remaining).stringValue)")
                Spacer()
                Text("本次最多 ¥\(NSDecimalNumber(decimal: fillAmount).stringValue)")
            }
            .font(.caption2)
            .foregroundStyle(themeManager.tertiaryTextColor)

            HStack(spacing: 10) {
                Button {
                    fillUnassignedSavings(to: clothing)
                } label: {
                    Label(fillAmount > 0 ? "填充到上限" : "不可填充", systemImage: "arrow.down.to.line.compact")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.orange)
                        .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 14, showsDecoration: false) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.orange.opacity(0.12))
                        }
                }
                .buttonStyle(.plain)
                .disabled(fillAmount <= 0)

                if overflow > 0 {
                    Button {
                        moveOverflowSavingToUnassigned(for: clothing)
                    } label: {
                        Label("转出超额", systemImage: "arrow.uturn.left.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Color(hex: "C94C72"))
                            .themeSkinAdaptiveSectionCard(slot: .primaryButton, cornerRadius: 14, showsDecoration: false) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: "C94C72").opacity(0.10))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .themeSkinSectionCard(slot: .sectionCard, cornerRadius: 18, showsDecoration: false)
    }

    private func fillUnassignedSavings(to clothing: Clothing) {
        do {
            let movedAmount = try WealthSavingLedger.transferUnassignedSavings(
                to: clothing,
                entries: wealthSavingEntries,
                context: modelContext
            )
            if movedAmount > 0 {
                statusMessage = "已为「\(clothing.name)」填充 ¥\(NSDecimalNumber(decimal: movedAmount).stringValue)"
                onFillComplete(movedAmount)
                Task { await SharedPersistence.shared.syncWidgetData() }
            } else {
                statusMessage = "「\(clothing.name)」已达上限，未发生转移"
            }
        } catch {
            statusMessage = "填充失败，请稍后再试"
            print("UnassignedSavingManagerSheet: Failed to fill unassigned saving: \(error)")
        }
    }

    private func moveOverflowSavingToUnassigned(for clothing: Clothing) {
        do {
            let movedAmount = try WealthSavingLedger.moveOverflowToUnassigned(
                for: clothing,
                entries: wealthSavingEntries,
                context: modelContext
            )
            if movedAmount > 0 {
                statusMessage = "已从「\(clothing.name)」转出超额 ¥\(NSDecimalNumber(decimal: movedAmount).stringValue)"
                Task { await SharedPersistence.shared.syncWidgetData() }
            } else {
                statusMessage = "「\(clothing.name)」没有需要转出的超额"
            }
        } catch {
            statusMessage = "转出失败，请稍后再试"
            print("UnassignedSavingManagerSheet: Failed to move overflow saving: \(error)")
        }
    }
}

struct VaultSavingSheet: View {
    let targetClothing: Clothing?
    let currentSavedAmount: Decimal
    let onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var amountText: String = ""

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var assignableCap: Decimal? {
        targetClothing.map { WealthSavingLedger.assignableSavingCap(for: $0) }
    }

    private var remainingAmount: Decimal? {
        guard let assignableCap else { return nil }
        return max(assignableCap - currentSavedAmount, Decimal(0))
    }

    private var effectiveSaveAmount: Decimal? {
        guard let parsedAmount, parsedAmount > 0 else { return nil }
        guard let remainingAmount else { return parsedAmount }
        let effectiveAmount = min(parsedAmount, remainingAmount)
        return effectiveAmount > 0 ? effectiveAmount : nil
    }

    private var isAmountClamped: Bool {
        guard let parsedAmount, let effectiveSaveAmount else { return false }
        return parsedAmount > effectiveSaveAmount
    }

    private var canSave: Bool {
        effectiveSaveAmount != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    if let targetClothing {
                        HStack(alignment: .center, spacing: 12) {
                            WealthClothingThumbnailView(
                                clothing: targetClothing,
                                size: CGSize(width: 56, height: 56),
                                cornerRadius: 16
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Label(WealthExperienceCopy.Vault.sheetTargetTitle, systemImage: "tray.and.arrow.down.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text(targetClothing.name)
                                    .font(.subheadline)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                                    .lineLimit(2)
                            }
                        }
                    } else {
                        Label(WealthExperienceCopy.Vault.sheetUnassignedTitle, systemImage: "tray.and.arrow.down.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(WealthExperienceCopy.Vault.sheetUnassignedDescription)
                            .font(.subheadline)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(WealthExperienceCopy.Vault.amountTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.secondaryTextColor)
                    HStack {
                        Text("¥")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.orange)
                        TextField("例如 100", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding()
                    .themeSkinAdaptiveSectionCard(slot: .sectionCard, cornerRadius: 20, showsDecoration: false) {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
                    }
                }

                Text("\(WealthExperienceCopy.Vault.currentSaved) ¥\(NSDecimalNumber(decimal: currentSavedAmount).stringValue)")
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)

                if let assignableCap, let remainingAmount {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(WealthExperienceCopy.Vault.capTitle)
                            Spacer()
                            Text("¥\(NSDecimalNumber(decimal: assignableCap).stringValue)")
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text(WealthExperienceCopy.Vault.remainingTitle)
                            Spacer()
                            Text("¥\(NSDecimalNumber(decimal: remainingAmount).stringValue)")
                                .fontWeight(.semibold)
                                .foregroundStyle(remainingAmount > 0 ? .orange : Color(hex: "C94C72"))
                        }

                        if remainingAmount <= 0 {
                            Text(WealthExperienceCopy.Vault.fullHint)
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        } else if isAmountClamped, let effectiveSaveAmount {
                            Text("\(WealthExperienceCopy.Vault.clampHintPrefix)¥\(NSDecimalNumber(decimal: effectiveSaveAmount).stringValue)\(WealthExperienceCopy.Vault.clampHintSuffix)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text(WealthExperienceCopy.Vault.capHint)
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                    }
                    .font(.caption)
                    .padding(12)
                    .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 16, showsDecoration: false) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.08))
                    }
                } else {
                    Text(WealthExperienceCopy.Vault.unassignedNoCapHint)
                        .font(.caption2)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 16, showsDecoration: false) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.orange.opacity(0.08))
                        }
                }

                Spacer()
            }
            .padding()
            .navigationTitle(WealthExperienceCopy.Vault.sheetNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存入") {
                        guard let amount = effectiveSaveAmount else { return }
                        onSave(amount)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct WealthClothingThumbnailView: View {
    let clothing: Clothing
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let imagePath = clothing.imagePaths.first, !imagePath.isEmpty {
                AsyncDownsampledImage(
                    fileName: imagePath,
                    targetSize: size
                ) { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
    }

    private var placeholder: some View {
        CutePlaceholderView(iconSize: min(size.width, size.height) * 0.34)
    }
}

private extension View {
    func wealthTeaPartyOrnaments(cornerRadius: CGFloat) -> some View {
        self
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                WealthExperienceStyle.pearl.opacity(0.9),
                                WealthExperienceStyle.rose.opacity(0.28),
                                WealthExperienceStyle.gold.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Circle().fill(WealthExperienceStyle.pearl)
                    Circle().fill(WealthExperienceStyle.blush)
                    Circle().fill(WealthExperienceStyle.rose.opacity(0.72))
                }
                .frame(width: 38, height: 8)
                .padding(.leading, 18)
                .padding(.top, 12)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "ribbon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WealthExperienceStyle.rose.opacity(0.55))
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
    }
}

struct VaultSavingCelebrationOverlay: View {
    let amount: Decimal
    let onComplete: () -> Void

    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.opacity(animate ? 0.18 : 0)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    ForEach(0..<14, id: \.self) { index in
                        Image(systemName: index.isMultiple(of: 3) ? "yensign.circle.fill" : "banknote.fill")
                            .font(.system(size: index.isMultiple(of: 3) ? 30 : 26, weight: .bold))
                            .foregroundStyle(index.isMultiple(of: 3) ? .yellow : .green)
                            .rotationEffect(.degrees(animate ? Double(index * 23 - 130) : 0))
                            .offset(
                                x: animate ? CGFloat((index % 7) - 3) * 28 : 0,
                                y: animate ? CGFloat(index % 5 - 2) * 24 - 34 : 0
                            )
                            .opacity(animate ? 0.0 : 1.0)
                    }
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: animate ? 130 : 50, height: animate ? 130 : 50)
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(.orange)
                }
                .frame(width: 170, height: 130)

                Text("\(WealthExperienceCopy.Vault.celebrationPrefix)¥\(NSDecimalNumber(decimal: amount).stringValue)")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.58), in: Capsule())
            }
            .scaleEffect(animate ? 1.05 : 0.82)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                animate = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                onComplete()
            }
        }
    }
}

private struct FortuneCatVaultIcon: View {
    let mascot: FinalPaymentVaultMascot

    var body: some View {
        Group {
            if let uiImage = UIImage(named: mascot.assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                switch mascot {
                case .miniVault:
                    MiniVaultIcon()
                case .fortuneCat:
                    FortuneCatFallbackIcon()
                case .piggyBank:
                    PiggyBankIcon()
                case .goldPig:
                    GoldPigIcon()
                }
            }
        }
        .accessibilityLabel("\(mascot.displayName)\(WealthExperienceCopy.Vault.accessibilitySuffix)")
    }
}

private struct MiniVaultIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.22), Color.yellow.opacity(0.18), Color.brown.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFD36A"), Color(hex: "C78B2B")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 82)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.55), lineWidth: 2)
                )

            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 8)
                .frame(width: 42, height: 42)
            Circle()
                .fill(Color(hex: "8B5A18"))
                .frame(width: 12, height: 12)
            Image(systemName: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .offset(y: 36)
        }
    }
}

private struct PiggyBankIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.20), Color.orange.opacity(0.14), Color.yellow.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                Ellipse()
                    .fill(Color.pink.opacity(0.92))
                    .frame(width: 110, height: 74)
                Circle()
                    .fill(Color.pink.opacity(0.96))
                    .frame(width: 48, height: 46)
                    .offset(x: 42, y: -6)
                Triangle()
                    .fill(Color.pink.opacity(0.86))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(18))
                    .offset(x: 32, y: -36)
                Circle()
                    .fill(Color.black.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .offset(x: 52, y: -14)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.pink.opacity(0.65))
                    .frame(width: 23, height: 14)
                    .offset(x: 65, y: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 34, height: 5)
                    .offset(y: -28)
                HStack(spacing: 46) {
                    Capsule().fill(Color.pink.opacity(0.75)).frame(width: 14, height: 20)
                    Capsule().fill(Color.pink.opacity(0.75)).frame(width: 14, height: 20)
                }
                .offset(y: 38)
            }
        }
    }
}

private struct GoldPigIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.24), Color.orange.opacity(0.18), Color.pink.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            PiggyBankIcon()
                .scaleEffect(0.78)
                .offset(y: 8)

            HStack(spacing: -6) {
                Image(systemName: "yensign.circle.fill")
                Image(systemName: "yensign.circle.fill")
                Image(systemName: "yensign.circle.fill")
            }
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.yellow)
            .shadow(color: .orange.opacity(0.35), radius: 5, x: 0, y: 3)
            .offset(y: -42)
        }
    }
}

private struct FortuneCatFallbackIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.22), Color.yellow.opacity(0.18), Color.pink.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: -4) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 86, height: 78)
                    HStack(spacing: 42) {
                        Triangle()
                            .fill(Color.orange.opacity(0.82))
                            .frame(width: 24, height: 24)
                            .rotationEffect(.degrees(-18))
                        Triangle()
                            .fill(Color.orange.opacity(0.82))
                            .frame(width: 24, height: 24)
                            .rotationEffect(.degrees(18))
                    }
                    .offset(y: -34)
                    HStack(spacing: 22) {
                        Circle().fill(Color.black.opacity(0.78)).frame(width: 8, height: 8)
                        Circle().fill(Color.black.opacity(0.78)).frame(width: 8, height: 8)
                    }
                    .offset(y: -6)
                    Text("₍˄·͈༝·͈˄₎")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange)
                        .offset(y: 14)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white)
                        .frame(width: 104, height: 72)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.red.opacity(0.92))
                        .frame(width: 44, height: 52)
                    Text("财")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.yellow)
                    Image(systemName: "yensign.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.yellow)
                        .offset(x: 42, y: 14)
                }
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    WealthView()
}
