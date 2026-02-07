import SwiftUI

struct PetStatusHeaderView: View {
    @ObservedObject var viewModel: PetViewModel
    let isLandscape: Bool
    
    var body: some View {
        Group {
            if isLandscape {
                VStack(spacing: 20) {
                    // 状态栏
                    statusRow(isVertical: true)
                    
                    Spacer()
                    
                    // 货币栏
                    currencyRow(isVertical: true)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 10)
                // .background(Material.ultraThin) // Removed background
                // .clipShape(Capsule()) // Removed clipShape
                .padding(.leading)
            } else {
                VStack(spacing: 10) {
                    // 状态栏 - 单行显示
                    statusRow(isVertical: false)
                    
                    currencyRow(isVertical: false)
                }
                .padding(.top, 10)
                .padding(.horizontal)
            }
        }
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
        let layout = isVertical ? AnyLayout(VStackLayout(spacing: 15)) : AnyLayout(HStackLayout(spacing: 15))
        return layout {
            CurrencyView(type: .meowCoin, amount: viewModel.status.meowCoin) {
                #if DEBUG
                viewModel.rechargeMeowCoin(amount: 100)
                #endif
            }
            
            CurrencyView(type: .fishCoin, amount: viewModel.status.fishCoin) {
                #if DEBUG
                viewModel.earnFishCoin(amount: 1000)
                #endif
            }
        }
    }
}
