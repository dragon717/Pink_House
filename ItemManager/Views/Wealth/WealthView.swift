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
            if clothing.isDepositPlan {
                return partialResult + (clothing.totalDeposit * Decimal(clothing.stock))
            } else {
                return partialResult + ((clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock))
            }
        }
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
                                WealthStorageContainerView(viewModel: viewModel)
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
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
                Text("财运亨通，日进斗金")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(soundManager.isSoundEnabled ? .blue : .gray)
                    }
                    
                    Button {
                        hapticManager.isHapticsEnabled.toggle()
                    } label: {
                        Image(systemName: hapticManager.isHapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                            .font(.caption)
                            .foregroundStyle(hapticManager.isHapticsEnabled ? .yellow : .gray)
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

// MARK: - 请签视图

struct DivinationView: View {
    @State private var currentFortune: Fortune?
    @State private var videoState: VideoState = .initial
    @State private var showFortuneText = false
    
    enum VideoState {
        case initial      // 显示首帧
        case playing      // 播放视频中
        case finished     // 显示尾帧+签文
    }
    
    private let fortunes: [Fortune] = [
        Fortune(level: .supreme, text: "上上签", description: "财运亨通，福星高照", detail: "今日财运极佳，适合投资理财，可能会有意外之财降临。"),
        Fortune(level: .supreme, text: "上上签", description: "财源广进，日进斗金", detail: "财神眷顾，正财偏财皆旺，把握机会必有所获。"),
        Fortune(level: .supreme, text: "上上签", description: "富贵吉祥，万事顺遂", detail: "财星高照，事业财运双丰收，好运连连。"),
        Fortune(level: .good, text: "上签", description: "财运平稳，小有收获", detail: "今日财运不错，适合稳健理财，会有小惊喜。"),
        Fortune(level: .good, text: "上签", description: "积少成多，稳步前行", detail: "财运渐入佳境，坚持储蓄必有回报。"),
        Fortune(level: .good, text: "上签", description: "贵人相助，财运可期", detail: "有望得到贵人提携，财运有所提升。"),
    ]
    
    // 圆角大小
    private let cornerRadius: CGFloat = 20
    // 容器尺寸比例（相对于屏幕宽度）
    private let containerScale: CGFloat = 0.75
    // 最大容器尺寸
    private let maxContainerSize: CGFloat = 360
    // 最小容器尺寸
    private let minContainerSize: CGFloat = 280
    
    var body: some View {
        GeometryReader { geometry in
            let containerSize = calculateContainerSize(for: geometry.size)
            
            ZStack {
                // 主要内容区域 - 使用固定布局避免按钮影响
                VStack(spacing: 0) {
                    Spacer()
                    
                    // 圆角矩形容器 - 固定位置，不受按钮影响
                    ZStack {
                        // 初始状态：显示首帧
                        if videoState == .initial {
                            Image("divination_first_frame")
                                .resizable()
                                .scaledToFill()
                                .frame(width: containerSize, height: containerSize)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .transition(.opacity)
                        }
                        
                        // 播放中：显示视频
                        if videoState == .playing {
                            DivinationVideoPlayer(
                                videoName: "请签",
                                onFinished: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        videoState = .finished
                                    }
                                    // 延迟显示签文
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                            showFortuneText = true
                                        }
                                    }
                                }
                            )
                            .frame(width: containerSize, height: containerSize)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .transition(.opacity)
                        }
                        
                        // 结束状态：显示尾帧 + 签文
                        if videoState == .finished {
                            // 尾帧背景
                            Image("divination_last_frame")
                                .resizable()
                                .scaledToFill()
                                .frame(width: containerSize, height: containerSize)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                                .transition(.opacity)
                            
                            // 半透明遮罩，让签文更清晰
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.ultraThinMaterial.opacity(0.3))
                                .frame(width: containerSize, height: containerSize)
                            
                            // 竖向签文（居中偏上）
                            if showFortuneText {
                                VerticalFortuneText(fortune: currentFortune ?? fortunes[0], containerSize: containerSize)
                                    .transition(.asymmetric(
                                        insertion: .scale.combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }
                        
                        // 边框装饰
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.9, green: 0.75, blue: 0.4),
                                        Color(red: 0.7, green: 0.5, blue: 0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: containerSize, height: containerSize)
                        
                        // 外发光阴影
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color(red: 0.9, green: 0.75, blue: 0.4).opacity(0.3), lineWidth: 8)
                            .frame(width: containerSize + 6, height: containerSize + 6)
                            .blur(radius: 4)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                    // 固定偏移量，确保位置不变
                    .offset(y: -40)
                    
                    Spacer()
                    
                    // 解签内容区域 - 固定高度占位，不受显示/隐藏影响
                    ZStack {
                        if videoState == .finished && showFortuneText, let fortune = currentFortune {
                            FortuneInterpretationView(fortune: fortune)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .frame(height: 100)
                    
                    // 按钮区域 - 固定高度占位，保持布局稳定
                    ZStack {
                        // 开始求签按钮
                        if videoState == .initial {
                            Button {
                                startDivination()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "wand.and.stars")
                                    Text("开始求签")
                                }
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                                .shadow(color: Color(red: 0.8, green: 0.3, blue: 0.3).opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .transition(.opacity)
                        }
                        
                        // 再求一签按钮
                        if videoState == .finished && showFortuneText {
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showFortuneText = false
                                    videoState = .playing
                                }
                                // 重新随机选择
                                currentFortune = fortunes.randomElement()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("再求一签")
                                }
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.6, green: 0.2, blue: 0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                                .shadow(color: Color(red: 0.8, green: 0.3, blue: 0.3).opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                            .transition(.opacity)
                        }
                    }
                    // 固定高度，确保布局稳定
                    .frame(height: 80)
                    .padding(.bottom, 40)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    // 计算自适应容器尺寸
    private func calculateContainerSize(for size: CGSize) -> CGFloat {
        let minDimension = min(size.width, size.height)
        let calculatedSize = minDimension * containerScale
        return min(max(calculatedSize, minContainerSize), maxContainerSize)
    }
    
    private func startDivination() {
        // 随机选择一个签
        currentFortune = fortunes.randomElement()
        
        // 播放成功反馈
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)
        
        withAnimation(.easeInOut(duration: 0.3)) {
            videoState = .playing
        }
    }
}

// MARK: - 签的数据模型

struct Fortune: Identifiable {
    let id = UUID()
    let level: FortuneLevel
    let text: String
    let description: String
    let detail: String
}

enum FortuneLevel {
    case supreme  // 上上签
    case good     // 上签
}

// MARK: - 解签内容视图（Lolita风格）

struct FortuneInterpretationView: View {
    let fortune: Fortune
    
    var body: some View {
        VStack(spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.6))
                
                Text(fortune.description)
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.6, green: 0.35, blue: 0.45))
                
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.6))
            }
            
            // 详细解签
            Text(fortune.detail)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Color(red: 0.5, green: 0.4, blue: 0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.96, blue: 0.98).opacity(0.95),
                            Color(red: 0.98, green: 0.94, blue: 0.96).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.9, green: 0.7, blue: 0.8).opacity(0.6),
                                    Color(red: 0.8, green: 0.6, blue: 0.7).opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(red: 0.8, green: 0.5, blue: 0.6).opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 32)
    }
}

// MARK: - 签条视图

struct FortuneStickView: View {
    let fortune: Fortune
    
    var body: some View {
        ZStack {
            // 签条主体
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.9, blue: 0.8),
                            Color(red: 0.9, green: 0.85, blue: 0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 40, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(red: 0.6, green: 0.4, blue: 0.2), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            
            // 签文
            Text(fortune.text.prefix(2))
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.6, green: 0.2, blue: 0.1))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - 数钱容器视图

struct MoneyCountingContainerView: View {
    @Bindable var viewModel: WealthViewModel
    @Binding var moneyCountingState: WealthView.MoneyCountingState?
    
    var body: some View {
        VStack(spacing: 0) {
            // 子页签选择器
            Picker("货币", selection: $viewModel.selectedCurrency) {
                Text("人民币").tag(CurrencyType.rmb)
                Text("日元").tag(CurrencyType.jpy)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // 金额显示
            MoneyCountingHeaderView(viewModel: viewModel)
                .padding(.top, 16)
            
            // 货币堆叠展示
            MoneyVisualizationView(viewModel: viewModel) { pile in
                self.moneyCountingState = WealthView.MoneyCountingState(
                    amount: Decimal(pile.count * pile.denomination.value),
                    denomination: pile.denomination
                )
            }
        }
    }
}

// MARK: - 数钱头部视图

struct MoneyCountingHeaderView: View {
    @Bindable var viewModel: WealthViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                LiquidRollingNumber(
                    value: Double(viewModel.totalAmount),
                    exchangeRateToCNY: viewModel.selectedCurrency == .rmb ? 1.0 : (1.0 / viewModel.exchangeRateJPY)
                )
                .font(.system(size: 64, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            )
            .padding(.horizontal)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            
            VStack(spacing: 4) {
                Text("已购入小裙子总价 + 尾款天使已付总定金")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if viewModel.selectedCurrency == .jpy {
                    HStack(spacing: 4) {
                        Text("汇率: 1 CNY ≈ \(String(format: "%.2f", viewModel.exchangeRateJPY)) JPY")
                        
                        if viewModel.isFetchingRate {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Button {
                                Task {
                                    await viewModel.fetchExchangeRate()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - 安财容器视图

struct WealthStorageContainerView: View {
    @Bindable var viewModel: WealthViewModel
    
    @State private var selectedStorageTab: StorageTab = .gold
    
    var body: some View {
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
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .onChange(of: selectedStorageTab) { _, newValue in
            if newValue == .gold {
                viewModel.selectedCurrency = .gold
            } else {
                viewModel.selectedCurrency = .silver
            }
        }
    }
}

// MARK: - 安财页签枚举

enum StorageTab: String, CaseIterable, Identifiable {
    case gold = "黄金"
    case silver = "白银"
    
    var id: String { rawValue }
}

// MARK: - 黄金存储视图

struct GoldStorageView: View {
    @Bindable var viewModel: WealthViewModel
    let isActive: Bool
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // 黄金重量显示
            goldDisplay
                .padding(.top, 16)
            
            // 金价信息
            HStack(spacing: 4) {
                Text("金价: \(String(format: "%.0f", viewModel.goldPriceCNYPerGram)) CNY/g")
                Text(viewModel.goldPriceSource)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .scaleEffect(0.8)
                
                if viewModel.isFetchingRate {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button {
                        Task {
                            await viewModel.fetchExchangeRate()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            
            // 物理模拟视图 - 只在当前 Tab 激活时创建
            if isActive {
                if viewModel.isGoldReady {
                    GoldPhysicsView(
                        totalWeightGrams: viewModel.totalGoldWeightGrams,
                        beanWeight: viewModel.goldBeanWeightGrams
                    )
                } else {
                    VStack {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在计算金克重...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // 非激活状态显示占位
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: isActive) { oldValue, newValue in
            if oldValue && !newValue {
                // 从激活变为非激活，停止音效和震动
                soundManager.stopAllSounds()
                hapticManager.stopHaptics()
            }
        }
    }
    
    private var goldDisplay: some View {
        let goldInfo = viewModel.goldDisplayValue
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            LiquidRollingNumber(
                value: goldInfo.value,
                exchangeRateToCNY: 1.0,
                fractionLength: goldInfo.value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2,
                fixedTier: .sparklingGold
            )
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            
            Text(goldInfo.unit)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: WealthTier.sparklingGold.textColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        )
        .padding(.horizontal)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - 白银存储视图

struct SilverStorageView: View {
    @Bindable var viewModel: WealthViewModel
    let isActive: Bool
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // 白银重量显示
            silverDisplay
                .padding(.top, 16)
            
            // 银价信息
            HStack(spacing: 4) {
                Text("银价: \(String(format: "%.1f", viewModel.silverPriceCNYPerGram)) CNY/g")
                Text(viewModel.silverPriceSource)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .scaleEffect(0.8)
                
                if viewModel.isFetchingRate {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button {
                        Task {
                            await viewModel.fetchExchangeRate()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            
            // 物理模拟视图 - 只在当前 Tab 激活时创建
            if isActive {
                if viewModel.isSilverReady {
                    SilverPhysicsView(
                        totalWeightGrams: viewModel.totalSilverWeightGrams,
                        beanWeight: viewModel.silverBeanWeightGrams
                    )
                } else {
                    VStack {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在计算白银重量...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // 非激活状态显示占位
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: isActive) { oldValue, newValue in
            if oldValue && !newValue {
                // 从激活变为非激活，停止音效和震动
                soundManager.stopAllSounds()
                hapticManager.stopHaptics()
            }
        }
    }
    
    private var silverDisplay: some View {
        let silverInfo = viewModel.silverDisplayValue
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            LiquidRollingNumber(
                value: silverInfo.value,
                exchangeRateToCNY: 1.0,
                fractionLength: silverInfo.value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2,
                fixedTier: .silver
            )
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            
            Text(silverInfo.unit)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: WealthTier.silver.textColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        )
        .padding(.horizontal)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - 货币可视化视图

struct MoneyVisualizationView: View {
    var viewModel: WealthViewModel
    var onPileTap: ((WealthViewModel.MoneyPile) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            moneyStackScrollView(geometry: geometry)
        }
    }
    
    private func moneyStackScrollView(geometry: GeometryProxy) -> some View {
        ScrollView {
            let stacks = viewModel.calculateStacks()
            
            if stacks.isEmpty {
                ContentUnavailableView(
                    "暂无资产",
                    systemImage: "banknote",
                    description: Text("衣橱空空如也，快去添加吧")
                )
                .padding(.top, 50)
                .frame(maxWidth: .infinity)
            } else {
                moneyStacksGrid(stacks: stacks, geometry: geometry)
            }
        }
    }
    
    private func moneyStacksGrid(stacks: [WealthViewModel.MoneyPile], geometry: GeometryProxy) -> some View {
        let screenWidth = geometry.size.width
        let columnCount = 5
        let availableWidth = screenWidth - 16
        let columnWidth = availableWidth / CGFloat(columnCount)
        
        let visualRefWidth: CGFloat = 170
        let visualRefHeight: CGFloat = 98
        
        let scale = columnWidth / visualRefWidth
        let rowHeight = visualRefHeight * scale * 0.5
        
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(columnWidth), spacing: 0), count: columnCount),
            spacing: -rowHeight
        ) {
            ForEach(stacks) { pile in
                MoneyStackView(
                    denomination: pile.denomination,
                    count: pile.count,
                    currency: viewModel.selectedCurrency
                )
                .scaleEffect(scale)
                .frame(width: columnWidth, height: visualRefHeight * scale)
                .onTapGesture {
                    onPileTap?(pile)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 50)
        .padding(.bottom, 100)
    }
}

#Preview {
    WealthView()
}
