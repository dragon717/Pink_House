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
        allClothings.reduce(Decimal(0)) { partialResult, clothing in
            guard !clothing.isDeleted && clothing.deletedAt == nil else { return partialResult }
            if clothing.isDepositPlan {
                let savedFinalPayment = clothing.isFinalPaymentSavedToWealth ? clothing.totalBalance : 0
                return partialResult + clothing.totalDeposit + savedFinalPayment + clothing.resolvedShippingFee
            } else {
                return partialResult + clothing.inventoryTotalPrice
            }
        }
    }

    private var magicPalette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
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
                                WealthStorageContainerView(viewModel: viewModel, clothings: allClothings)
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
                    FinalPaymentVaultView(clothings: clothings)
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

    @StateObject private var tabNavigationManager = TabNavigationManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    private var activeDepositClothings: [Clothing] {
        clothings.filter { $0.isDepositPlan && !$0.isDeleted && $0.deletedAt == nil }
    }

    private var savedClothings: [Clothing] {
        activeDepositClothings.filter { $0.isFinalPaymentSavedToWealth }
    }

    private var unsavedClothings: [Clothing] {
        activeDepositClothings.filter { !$0.isFinalPaymentSavedToWealth }
    }

    private var savedTotal: Decimal {
        savedClothings.reduce(0) { $0 + $1.totalBalance }
    }

    private var unsavedTotal: Decimal {
        unsavedClothings.reduce(0) { $0 + $1.totalBalance }
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

                if savedClothings.isEmpty {
                    emptyState
                } else {
                    savedList
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 120)
        }
    }

    private var fortuneCatHeader: some View {
        VStack(spacing: 12) {
            FortuneCatVaultIcon()
                .frame(width: 150, height: 150)
                .shadow(color: Color.orange.opacity(0.25), radius: 16, x: 0, y: 8)

            Text("招财猫尾款小金库")
                .font(.title3.weight(.heavy))
                .foregroundStyle(themeManager.primaryTextColor)

            Text("存进去的尾款会计入马上来财统计，付尾款后自动转为已用。")
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
                vaultStat(title: "已存入", value: "\(savedClothings.count)条", color: .orange)
                Divider().frame(height: 34)
                vaultStat(title: "待存入", value: "¥\(NSDecimalNumber(decimal: unsavedTotal).stringValue)", color: palette.accent)
                Divider().frame(height: 34)
                vaultStat(title: "总尾款", value: "¥\(NSDecimalNumber(decimal: savedTotal + unsavedTotal).stringValue)", color: Color(hex: "C94C72"))
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(.orange.opacity(0.8))
            Text("还没有存入尾款")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
            Text("去心愿尾款列表选择一条尾款，点击「存入招财猫」。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(themeManager.secondaryTextColor)
            Button {
                tabNavigationManager.navigate(to: .wardrobe(.depositPlan))
            } label: {
                Label("去心愿尾款", systemImage: "heart.text.square.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.16))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
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
            Text("已存入明细")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            ForEach(savedClothings.sorted { ($0.finalPaymentSavedAt ?? .distantPast) > ($1.finalPaymentSavedAt ?? .distantPast) }) { clothing in
                HStack(spacing: 10) {
                    Image(systemName: "cat.fill")
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
                        if let date = clothing.finalPaymentSavedAt {
                            Text("存入于 \(date.formatted(date: .numeric, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                    }

                    Spacer()

                    Text("¥\(NSDecimalNumber(decimal: clothing.totalBalance).stringValue)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(hex: "C94C72"))
                        .monospacedDigit()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.48))
                )
            }
        }
    }
}

private struct FortuneCatVaultIcon: View {
    var body: some View {
        Group {
            if let uiImage = UIImage(named: "wealth_fortune_cat") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                FortuneCatFallbackIcon()
            }
        }
        .accessibilityLabel("招财猫尾款小金库")
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
