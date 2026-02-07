import SwiftUI

struct PetStatusHeaderView: View {
    @ObservedObject var viewModel: PetViewModel
    let isLandscape: Bool
    
    var body: some View {
        Group {
            if isLandscape {
                HStack(alignment: .top, spacing: 20) {
                    // 状态栏
                    statusRow
                    
                    Spacer()
                    
                    // 货币栏
                    currencyRow
                }
            } else {
                VStack(spacing: 10) {
                    // 状态栏 - 单行显示
                    statusRow
                    
                    currencyRow
                }
            }
        }
        .padding(.top, 10)
        .padding(.horizontal)
    }
    
    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusView(icon: "fork.knife", value: viewModel.status.hunger, color: .orange)
            StatusView(icon: "shower.fill", value: viewModel.status.hygiene, color: .blue)
            StatusView(icon: "bolt.fill", value: viewModel.status.energy, color: .green)
            StatusView(icon: "face.smiling.fill", value: viewModel.status.mood, color: .pink)
        }
    }
    
    private var currencyRow: some View {
        HStack(spacing: 15) {
            CurrencyView(type: .meowCoin, amount: viewModel.status.meowCoin) {
                viewModel.rechargeMeowCoin(amount: 100)
            }
            
            CurrencyView(type: .fishCoin, amount: viewModel.status.fishCoin) {
                viewModel.earnFishCoin(amount: 1000)
            }
        }
    }
}
