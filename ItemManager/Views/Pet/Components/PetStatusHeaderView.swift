import SwiftUI

struct PetStatusHeaderView: View {
    @ObservedObject var viewModel: PetViewModel
    @Environment(ThemeManager.self) private var themeManager
    let isLandscape: Bool
    
    @State private var showExchangeSheet = false
    @State private var showMoreCurrenciesSheet = false
    
    var body: some View {
        Group {
            if isLandscape {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // 状态栏
                        statusRow(isVertical: true)
                        
                        Spacer()
                        
                        // 货币栏
                        currencyRow(isVertical: true)
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 10)
                    .padding(.leading)
                    .frame(minHeight: 300) // Ensure some minimum height for layout
                }
            } else {
                VStack(spacing: 10) {
                    // 状态栏 - 单行显示
                    statusRow(isVertical: false)
                    
                    // 货币栏 - 自动适配宽度
                    ViewThatFits(in: .horizontal) {
                        currencyRow(isVertical: false)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            currencyRow(isVertical: false)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showExchangeSheet) {
            ExchangeView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showMoreCurrenciesSheet) {
            MoreCurrenciesView(currencies: allCurrencies)
                .presentationDetents([.medium, .large])
        }
    }
    
    private var allCurrencies: [(type: PetCurrency, amount: Int, action: () -> Void)] {
        [
            (.meowCoin, viewModel.status.meowCoin, {
                #if DEBUG
                viewModel.rechargeMeowCoin(amount: 100)
                #endif
            }),
            (.fishCoin, viewModel.status.fishCoin, { showExchangeSheet = true }),
            (.boneCoin, viewModel.status.boneCoin, { showExchangeSheet = true })
        ]
    }
    
    private func statusRow(isVertical: Bool) -> some View {
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 15)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            StatusView(icon: "fork.knife", value: viewModel.status.hunger, color: .orange)
            StatusView(icon: "shower.fill", value: viewModel.status.hygiene, color: .blue)
            StatusView(icon: "bolt.fill", value: viewModel.status.energy, color: .green)
            StatusView(icon: "face.smiling.fill", value: viewModel.status.mood, color: .pink)
        }
    }
    
    private func currencyRow(isVertical: Bool) -> some View {
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 15)) : AnyLayout(HStackLayout(spacing: 8))
        let maxDisplayCount = 3
        let currencies = allCurrencies
        let shouldCollapse = currencies.count > maxDisplayCount
        
        // 如果需要折叠，显示前 max-1 个，最后一个位置留给 "..."
        // 如果不需要折叠，全部显示
        let displayItems = shouldCollapse ? Array(currencies.prefix(maxDisplayCount - 1)) : currencies
        
        return layout {
            ForEach(displayItems.indices, id: \.self) { index in
                let item = displayItems[index]
                CurrencyView(type: item.type, amount: item.amount, action: item.action)
            }
            
            if shouldCollapse {
                Button {
                    showMoreCurrenciesSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 1)
                }
            }
        }
    }
}

struct MoreCurrenciesView: View {
    let currencies: [(type: PetCurrency, amount: Int, action: () -> Void)]
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(currencies.indices, id: \.self) { index in
                    let item = currencies[index]
                    HStack {
                        CurrencyView(type: item.type, amount: item.amount, action: item.action)
                            .buttonStyle(.plain) // Ensure button tap works within List if needed, or just display
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("所有货币")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.primaryTextColor)
                }
            }
        }
    }
}

struct ExchangeView: View {
    @ObservedObject var viewModel: PetViewModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) var dismiss
    
    @State private var exchangeAmount: Double = 100
    @State private var showAmountInput = false
    @State private var inputAmountText = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Text("货币兑换")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(themeManager.primaryTextColor)
                    
                    Text("汇率 1:1")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                .padding(.top, 20)
                
                // Exchange Visualization
                HStack(spacing: 20) {
                    VStack {
                        Image(systemName: "fish.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("鱼币")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                    
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title2)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                    
                    VStack {
                        // 骨头币图标
                        ZStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(hex: "CD7F32")) // Bronze color
                            Text("🦴")
                                .font(.system(size: 24))
                        }
                        Text("骨头币")
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                
                Divider()
                
                // Amount Slider
                VStack(spacing: 10) {
                    Button {
                        inputAmountText = "\(Int(exchangeAmount))"
                        showAmountInput = true
                    } label: {
                        Text("兑换数量: \(Int(exchangeAmount))")
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Slider(value: $exchangeAmount, in: 1000...100000, step: 1000)
                        .tint(themeManager.accentTextColor)
                    
                    HStack {
                        Text("1000")
                        Spacer()
                        Text("100000")
                    }
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                }
                .padding(.horizontal, 30)
                
                // Actions
                VStack(spacing: 16) {
                    Button(action: {
                        if viewModel.exchangeFishToBone(amount: Int(exchangeAmount)) {
                            // Haptic?
                        }
                    }) {
                        HStack {
                            Text("鱼币")
                            Image(systemName: "arrow.right")
                            Text("骨头币")
                        }
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brown)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        if viewModel.exchangeBoneToFish(amount: Int(exchangeAmount)) {
                            // Haptic?
                        }
                    }) {
                        HStack {
                            Text("骨头币")
                            Image(systemName: "arrow.right")
                            Text("鱼币")
                        }
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 30)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
                
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.debugAddFishCoin(amount: 1000)
                        _ = PetDataManager.shared.updateCurrency(type: .boneCoin, delta: 1000)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                #endif
            }
            .alert("输入兑换数量", isPresented: $showAmountInput) {
                TextField("数量", text: $inputAmountText)
                    .keyboardType(.numberPad)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let value = Int(inputAmountText), value > 0 {
                        exchangeAmount = Double(value)
                    }
                }
            }
        }
    }
}
