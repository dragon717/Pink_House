import SwiftUI
import SwiftData

struct WealthView: View {
    @State private var viewModel = WealthViewModel()
    @Query private var allClothings: [Clothing]
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    
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
                // 尾款天使：已付定金总价
                return partialResult + (clothing.deposit * Decimal(clothing.stock))
            } else {
                // 衣橱（非尾款天使）：总价（包含小物）
                return partialResult + ((clothing.price + clothing.accessoriesPrice) * Decimal(clothing.stock))
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    WealthHeaderView(viewModel: viewModel)
                    
                    WealthVisualizationView(viewModel: viewModel) { pile in
                        // Trigger money counting on tap
                        self.moneyCountingState = MoneyCountingState(
                            amount: Decimal(pile.count * pile.denomination.value),
                            denomination: pile.denomination
                        )
                    }
                }
            }
            .navigationTitle("来财")
            .toolbar {
                toolbarContent
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
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.selectedCurrency == .gold || viewModel.selectedCurrency == .silver {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Sound Toggle
                    Button {
                        soundManager.isSoundEnabled.toggle()
                    } label: {
                        Image(systemName: soundManager.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundStyle(soundManager.isSoundEnabled ? .blue : .gray)
                    }
                    
                    // Haptic Toggle
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
        // Check initial state
        if viewModel.selectedCurrency == .gold || viewModel.selectedCurrency == .silver {
            lockOrientation(isLocked: true)
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

// MARK: - Subviews

struct WealthHeaderView: View {
    @Bindable var viewModel: WealthViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Picker("Currency", selection: $viewModel.selectedCurrency) {
                ForEach(CurrencyType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                if viewModel.selectedCurrency == .gold {
                    goldDisplay
                } else if viewModel.selectedCurrency == .silver {
                    silverDisplay
                } else {
                    standardCurrencyDisplay
                }
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
                    jpyExchangeRateView
                } else if viewModel.selectedCurrency == .gold {
                    goldPriceView
                } else if viewModel.selectedCurrency == .silver {
                    silverPriceView
                }
            }
        }
        .padding(.top)
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
    }
    
    private var silverDisplay: some View {
        let silverInfo = viewModel.silverDisplayValue
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            LiquidRollingNumber(
                value: silverInfo.value,
                exchangeRateToCNY: 1.0,
                fractionLength: silverInfo.value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2,
                fixedTier: .silver // Assuming there is a silver tier or reuse gold with different color
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
    }
    
    private var standardCurrencyDisplay: some View {
        LiquidRollingNumber(
            value: Double(viewModel.totalAmount),
            exchangeRateToCNY: viewModel.selectedCurrency == .rmb ? 1.0 : (1.0 / viewModel.exchangeRateJPY)
        )
        .font(.system(size: 64, weight: .heavy, design: .rounded))
    }
    
    private var jpyExchangeRateView: some View {
        HStack(spacing: 4) {
            Text("汇率: 1 CNY ≈ \(String(format: "%.2f", viewModel.exchangeRateJPY)) JPY")
            refreshButton
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    
    private var goldPriceView: some View {
        HStack(spacing: 4) {
            Text("金价: \(String(format: "%.0f", viewModel.goldPriceCNYPerGram)) CNY/g")
            Text(viewModel.goldPriceSource)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .scaleEffect(0.8)
            
            refreshButton
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    
    private var silverPriceView: some View {
        HStack(spacing: 4) {
            Text("银价: \(String(format: "%.1f", viewModel.silverPriceCNYPerGram)) CNY/g")
            Text(viewModel.silverPriceSource)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .scaleEffect(0.8)
            
            refreshButton
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    
    private var refreshButton: some View {
        Group {
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
    }
}

struct WealthVisualizationView: View {
    var viewModel: WealthViewModel
    var onPileTap: ((WealthViewModel.MoneyPile) -> Void)? = nil
    
    var body: some View {
        GeometryReader { geometry in
            if viewModel.selectedCurrency == .gold {
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
            } else if viewModel.selectedCurrency == .silver {
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
                moneyStackScrollView(geometry: geometry)
            }
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
