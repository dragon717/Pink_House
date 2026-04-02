import SwiftUI
import Combine

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
