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
            PetCurrencyExchangeSheet(preferredDirection: .fishToBone)
                .presentationDetents([.medium, .large])
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
            .navigationTitle("所有货币".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭".appLocalized) {
                        dismiss()
                    }
                    .foregroundStyle(themeManager.primaryTextColor)
                }
            }
        }
    }
}
