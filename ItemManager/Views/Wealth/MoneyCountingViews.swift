import SwiftUI
import Combine

// MARK: - 数钱容器视图

struct MoneyCountingContainerView: View {
    @Bindable var viewModel: WealthViewModel
    @Binding var moneyCountingState: WealthView.MoneyCountingState?
    
    var body: some View {
        VStack(spacing: 0) {
            // 子页签选择器
            Picker("货币", selection: $viewModel.selectedCurrency) {
                Text(CurrencyType.rmb.displayTitle).tag(CurrencyType.rmb)
                Text(CurrencyType.jpy.displayTitle).tag(CurrencyType.jpy)
                Text(CurrencyType.usd.displayTitle).tag(CurrencyType.usd)
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

    // 计算当前货币对人民币的汇率（用于财富等级计算）
    private var exchangeRateToCNY: Double {
        switch viewModel.selectedCurrency {
        case .rmb:
            return 1.0
        case .jpy:
            return 1.0 / viewModel.exchangeRateJPY
        case .usd:
            return 1.0 / viewModel.exchangeRateUSD
        case .gold, .silver:
            return 1.0
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.selectedCurrency.symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                LiquidRollingNumber(
                    value: Double(viewModel.totalAmount),
                    exchangeRateToCNY: exchangeRateToCNY
                )
                .font(.system(size: 64, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .themeSkinAdaptiveSectionCard(slot: .statsCard, cornerRadius: 24) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(.horizontal)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            
            VStack(spacing: 4) {
                Text(WealthExperienceCopy.Counting.sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 日元或美元时显示汇率
                if viewModel.selectedCurrency == .jpy || viewModel.selectedCurrency == .usd {
                    HStack(spacing: 4) {
                        let rateText = viewModel.selectedCurrency == .jpy
                            ? "汇率: 1 CNY ≈ \(String(format: "%.2f", viewModel.exchangeRateJPY)) JPY"
                            : "汇率: 1 CNY ≈ \(String(format: "%.4f", viewModel.exchangeRateUSD)) USD"
                        Text(rateText)

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

// MARK: - 货币可视化视图

struct MoneyVisualizationView: View {
    @Bindable var viewModel: WealthViewModel
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
                    WealthExperienceCopy.Counting.emptyTitle,
                    systemImage: "banknote",
                    description: Text(WealthExperienceCopy.Counting.emptyDescription)
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
