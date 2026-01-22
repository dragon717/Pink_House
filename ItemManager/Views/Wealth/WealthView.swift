
import SwiftUI
import SwiftData

struct WealthView: View {
    @State private var viewModel = WealthViewModel()
    @Query private var allClothings: [Clothing]
    
    private var calculatedTotalAmount: Decimal {
        allClothings.reduce(Decimal(0)) { partialResult, clothing in
            if clothing.isDepositPlan {
                // 定尾计划：已付定金总价
                return partialResult + (clothing.deposit * Decimal(clothing.stock))
            } else {
                // 衣橱（非定尾计划）：总价（包含小物）
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
                    // Input Area
                    VStack(spacing: 16) {
                        Picker("Currency", selection: $viewModel.selectedCurrency) {
                            ForEach(CurrencyType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        HStack {
                            Text(viewModel.selectedCurrency.symbol)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 8) {
                                Text(viewModel.inputAmount)
                                    .font(.largeTitle)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                                
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                        }
                        .padding(.horizontal)
                        
                        VStack(spacing: 4) {
                            Text("已购入小裙子总价 + 定尾计划已付总定金")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if viewModel.selectedCurrency == .jpy {
                                HStack(spacing: 4) {
                                    Text("汇率: 1 CNY ≈ \(String(format: "%.2f", viewModel.exchangeRate)) JPY")
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
                    .padding(.top)
                    
                    // Visualization Area
                    GeometryReader { geometry in
                        ScrollView {
                            // Get stacks
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
                                // Calculate Dimensions
                                let screenWidth = geometry.size.width
                                let columnCount = 5
                                // 16px horizontal padding total (8 leading, 8 trailing)
                                let availableWidth = screenWidth - 16
                                let columnWidth = availableWidth / CGFloat(columnCount)
                                
                                // Base Visual Size of the Banknote (Rotated)
                                // Width ~ 170, Height ~ 98
                                let visualRefWidth: CGFloat = 170
                                let visualRefHeight: CGFloat = 98
                                
                                let scale = columnWidth / visualRefWidth
                                let rowHeight = visualRefHeight * scale * 0.5 // Overlap by 50%
                                
                                // Fixed 5 columns with calculated width
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.fixed(columnWidth), spacing: 0), count: columnCount),
                                    spacing: -rowHeight // Negative spacing to overlap rows
                                ) {
                                    ForEach(stacks) { pile in
                                        MoneyStackView(
                                            denomination: pile.denomination,
                                            count: pile.count,
                                            currency: viewModel.selectedCurrency
                                        )
                                        // The visual content is much larger than the cell, we scale it down
                                        .scaleEffect(scale)
                                        // Force the frame to match the grid cell size to maintain layout
                                        // But allow content to overflow visually
                                        .frame(width: columnWidth, height: visualRefHeight * scale)
                                        // Ensure Z-Index correct for overlap (Lower rows cover upper rows)
                                        // LazyVGrid renders top-to-bottom. Last item is on top.
                                        // Row 2 is drawn AFTER Row 1, so Row 2 covers Row 1. This is correct.
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 50) // Space for the first row's overflow
                                .padding(.bottom, 100)
                            }
                        }
                    }
                }
            }
            .navigationTitle("来财")
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("完成") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear {
                updateAmount()
                Task {
                    await viewModel.fetchExchangeRate()
                }
            }
            .onChange(of: allClothings) { _, _ in
                updateAmount()
            }
        }
    }
    
    private func updateAmount() {
        let total = calculatedTotalAmount
        viewModel.baseAmountCNY = total
    }
}

#Preview {
    WealthView()
}
