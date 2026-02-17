import SwiftUI
import SwiftData

// MARK: - 马上来财主页面

struct WealthView: View {
    @State private var viewModel = WealthViewModel()
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) private var allClothings: [Clothing]
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    
    // 主页面签选择
    @State private var selectedMainTab: WealthMainTab = .divination
    
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
                        
                        // 安财
                        WealthStorageContainerView(viewModel: viewModel)
                            .tag(WealthMainTab.wealthStorage)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("🐎上来财")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                principalToolbarContent
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
            }
            .onDisappear {
                lockOrientation(isLocked: false)
                stopEffects()
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
    private var principalToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("功能", selection: $selectedMainTab) {
                ForEach(WealthMainTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }
    
    @ToolbarContentBuilder
    private var trailingToolbarContent: some ToolbarContent {
        if selectedMainTab == .wealthStorage {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        soundManager.isSoundEnabled.toggle()
                    } label: {
                        Image(systemName: soundManager.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundStyle(soundManager.isSoundEnabled ? .blue : .gray)
                    }
                    
                    Button {
                        hapticManager.isHapticsEnabled.toggle()
                    } label: {
                        Image(systemName: hapticManager.isHapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
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
    @State private var isShaking = false
    @State private var showResult = false
    @State private var shakeCount = 0
    
    private let fortunes: [Fortune] = [
        Fortune(level: .supreme, text: "上上签", description: "财运亨通，福星高照", detail: "今日财运极佳，适合投资理财，可能会有意外之财降临。"),
        Fortune(level: .supreme, text: "上上签", description: "财源广进，日进斗金", detail: "财神眷顾，正财偏财皆旺，把握机会必有所获。"),
        Fortune(level: .supreme, text: "上上签", description: "富贵吉祥，万事顺遂", detail: "财星高照，事业财运双丰收，好运连连。"),
        Fortune(level: .good, text: "上签", description: "财运平稳，小有收获", detail: "今日财运不错，适合稳健理财，会有小惊喜。"),
        Fortune(level: .good, text: "上签", description: "积少成多，稳步前行", detail: "财运渐入佳境，坚持储蓄必有回报。"),
        Fortune(level: .good, text: "上签", description: "贵人相助，财运可期", detail: "有望得到贵人提携，财运有所提升。"),
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 签筒
            ZStack {
                // 签筒主体
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.3, blue: 0.1),
                                Color(red: 0.4, green: 0.2, blue: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(red: 0.8, green: 0.6, blue: 0.2), lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .rotationEffect(.degrees(isShaking ? Double.random(in: -15...15) : 0))
                    .offset(x: isShaking ? CGFloat.random(in: -10...10) : 0)
                    .animation(isShaking ? .linear(duration: 0.05).repeatCount(20) : .spring(), value: isShaking)
                
                // 签筒文字
                VStack {
                    Text("财")
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.9, green: 0.7, blue: 0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2)
                    
                    Text("运")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.9, green: 0.7, blue: 0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
                
                // 签（当显示结果时）
                if showResult, let fortune = currentFortune {
                    FortuneStickView(fortune: fortune)
                        .offset(y: -80)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            
            Spacer()
            
            // 结果展示
            if showResult, let fortune = currentFortune {
                VStack(spacing: 12) {
                    Text(fortune.text)
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(fortune.level == .supreme ? 
                            LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.9, green: 0.5, blue: 0.1)], startPoint: .top, endPoint: .bottom) :
                            LinearGradient(colors: [Color(red: 0.5, green: 0.7, blue: 0.9), Color(red: 0.3, green: 0.5, blue: 0.8)], startPoint: .top, endPoint: .bottom)
                        )
                    
                    Text(fortune.description)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(fortune.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.8))
                        .background(.ultraThinMaterial)
                )
                .padding(.horizontal)
            }
            
            // 求签按钮
            Button {
                performDivination()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    Text(showResult ? "再求一签" : "开始求签")
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
            .disabled(isShaking)
            .padding(.bottom, 40)
        }
    }
    
    private func performDivination() {
        // 重置状态
        withAnimation {
            showResult = false
            currentFortune = nil
        }
        
        // 开始摇晃动画
        isShaking = true
        
        // 播放震动反馈
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        
        // 定时触发震动
        var shakeTimer: Timer?
        shakeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            generator.impactOccurred()
        }
        
        // 1秒后停止摇晃并显示结果
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            shakeTimer?.invalidate()
            isShaking = false
            
            // 随机选择一个签
            currentFortune = fortunes.randomElement()
            
            // 播放成功反馈
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showResult = true
            }
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
                GoldStorageView(viewModel: viewModel)
                    .tag(StorageTab.gold)
                
                // 白银
                SilverStorageView(viewModel: viewModel)
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
            
            // 物理模拟视图
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
            
            // 物理模拟视图
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
