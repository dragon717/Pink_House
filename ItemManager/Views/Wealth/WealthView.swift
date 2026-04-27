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
                LiquidBackground()
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
                Text("马上来财")
                    .font(.headline)
                    .foregroundStyle(themeManager.primaryTextColor)
                Text("财运亨通，日进斗金")
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

                    // 尾款招财猫
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

// MARK: - 尾款招财猫小金库

struct FinalPaymentVaultView: View {
    let clothings: [Clothing]
    let wealthSavingEntries: [WealthSavingEntry]

    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @State private var appearanceManager = WealthAppearanceManager.shared
    @State private var showingSavingSheet = false
    @State private var savingTargetClothingID: UUID?
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

            Text("\(appearanceManager.finalPaymentVaultMascot.displayName)小金库")
                .font(.title3.weight(.heavy))
                .foregroundStyle(themeManager.primaryTextColor)

            Text("为裙装一笔笔存钱，或先放进不指定小金库；都会计入马上来财统计。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.58))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        )
    }

    private var statsCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.orange)
                Text(NSDecimalNumber(decimal: savedTotal).stringValue)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.yellow, Color(hex: "C94C72")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }

            HStack(spacing: 0) {
                vaultStat(title: "已存入", value: "¥\(NSDecimalNumber(decimal: savedTotal).stringValue)", color: .orange)
                Divider().frame(height: 34)
                vaultStat(title: "指定裙装", value: "¥\(NSDecimalNumber(decimal: linkedSavedTotal).stringValue)", color: palette.accent)
                Divider().frame(height: 34)
                vaultStat(title: "未指定", value: "¥\(NSDecimalNumber(decimal: unassignedSavedTotal).stringValue)", color: Color(hex: "C94C72"))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.62))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        )
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

    private var quickSaveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("存一笔到小金库")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text("不指定裙装也可以先存，之后来财统计会一起计算。")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                Spacer()
                Button {
                    savingTargetClothingID = nil
                    showingSavingSheet = true
                } label: {
                    Label("不指定存钱", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.16))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.orange.opacity(0.8))
            Text("还没有小金库存款")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
            Text("可以先不指定裙装存一笔，也可以去心愿尾款列表为目标裙装存钱。")
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
                        .background(Color.orange.opacity(0.16))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    tabNavigationManager.navigate(to: .wardrobe(.depositPlan))
                } label: {
                    Label("去心愿尾款", systemImage: "heart.text.square.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(palette.accent.opacity(0.14))
                        .foregroundStyle(palette.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.45))
        )
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("裙装存钱进度")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            ForEach(clothingsWithSavingsOrDepositPlans) { clothing in
                let saved = WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
                let numerator = WealthSavingLedger.progressNumerator(for: clothing, entries: wealthSavingEntries)
                let target = WealthSavingLedger.purchaseTarget(for: clothing)
                let ratio = WealthSavingLedger.progressRatio(for: clothing, entries: wealthSavingEntries)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: clothing.isDepositPlan ? "heart.text.square.fill" : "tshirt.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(clothing.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.primaryTextColor)
                                .lineLimit(1)
                            Text(clothing.isDepositPlan ? "定金 + 小金库存款 / 当前总价" : "小金库存款 / 当前总价")
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }

                        Spacer()

                        Button {
                            savingTargetClothingID = clothing.id
                            showingSavingSheet = true
                        } label: {
                            Label("存一笔", systemImage: "plus")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.orange.opacity(0.14))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("已存 ¥\(NSDecimalNumber(decimal: saved).stringValue)")
                            Spacer()
                            Text("\(Int((ratio * 100).rounded()))%")
                                .foregroundStyle(ratio > 1 ? Color(hex: "C94C72") : .orange)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.secondaryTextColor)

                        ProgressView(value: min(ratio, 1.0))
                            .tint(ratio > 1 ? Color(hex: "C94C72") : .orange)

                        Text("进度 ¥\(NSDecimalNumber(decimal: numerator).stringValue) / ¥\(NSDecimalNumber(decimal: target).stringValue)")
                            .font(.caption2)
                            .foregroundStyle(themeManager.tertiaryTextColor)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.48))
                )
            }
        }
    }

    private func saveAmount(_ amount: Decimal) {
        let target = savingTargetClothing
        do {
            _ = try WealthSavingLedger.addSaving(
                amount: amount,
                clothingID: target?.id,
                note: target.map { "为「\($0.name)」存钱" } ?? "不指定裙装存钱",
                context: modelContext
            )
            Task { await SharedPersistence.shared.syncWidgetData() }
            celebrationAmount = amount
        } catch {
            print("FinalPaymentVaultView: Failed to save wealth saving entry: \(error)")
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

    private var canSave: Bool {
        (parsedAmount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(targetClothing == nil ? "不指定裙装存钱" : "为裙装存一笔", systemImage: "tray.and.arrow.down.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(targetClothing?.name ?? "先存进自由小金库，暂不绑定具体裙装。")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("存入金额")
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
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
                    )
                }

                Text("当前已存 ¥\(NSDecimalNumber(decimal: currentSavedAmount).stringValue)")
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)

                Spacer()
            }
            .padding()
            .navigationTitle("存一笔到小金库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存入") {
                        guard let amount = parsedAmount, amount > 0 else { return }
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

                Text("已存入 ¥\(NSDecimalNumber(decimal: amount).stringValue)")
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
        .accessibilityLabel("\(mascot.displayName)尾款小金库")
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
